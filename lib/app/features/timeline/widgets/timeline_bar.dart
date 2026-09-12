import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/editor_toast.dart';
import '../../../state/editor_controller.dart';
import '../commands.dart';
import '../providers.dart';
import 'timeline_rows.dart';

/// The timeline panel — F9.1 scrub, F6/F7 rows, keyframes and per-segment
/// easing (docs/v3/03, docs/v3/05 §2).
///
/// **Pixels appear only in this widget's paint and hit-test (AC-9.1.4).** The
/// scrub conversion `t = dx / width` lives in [_scrub] and the row/overlay
/// painters; the model is a unitless normalized `t` everywhere else.
///
/// **Live scrub preview (AC-9.1.3), unchanged from M0.** The drag writes
/// `playhead.value` directly — no `setState`, no provider write, no rebuild —
/// and the canvas painters take that same notifier as `repaint:`, so
/// interpolated geometry appears *while* dragging. The keyframe editing below
/// is the opposite kind of write (a `Command` that returns a new `Document`),
/// and the two never cross: nothing in a `build`/`paint` here mutates the
/// document (AC-6.2.5).
///
/// **Keyboard (docs/v3/05 §5), the timeline's own five.** `,`/`.` step the
/// selected property row's keys, `Home`/`End` jump the playhead, `K` keys the
/// selected property at the playhead with its evaluated value and `Shift+K`
/// removes the key under it. They live in a [Focus] scope this panel owns —
/// the shell owns the *global* shortcuts and this file may not edit it, so
/// these fire only while the timeline holds focus, which is also why they can
/// never fire while a text field elsewhere is focused (a text field has focus,
/// the timeline does not). A local text-field guard backs that up.
class TimelineBar extends ConsumerStatefulWidget {
  const TimelineBar({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<TimelineBar> createState() => _TimelineBarState();
}

class _TimelineBarState extends ConsumerState<TimelineBar> {
  final FocusNode _keyFocus = FocusNode(debugLabel: 'timeline-shortcuts');

  /// Tall enough for the **grab handle**, the second labels and the ticks
  /// (docs/v3/05 §4.6). It was 18 px and a bare 1-px line: the playhead read as
  /// decoration rather than as the thing you drag, and with no scale on the
  /// ruler there was nothing on screen that answered "*which* moment am I
  /// looking at?" — the question every keyframe flow starts from.
  static const double _rulerHeight = 32.0;

  /// The handle's band, measured from the top of the ruler. The line starts
  /// where it ends.
  static const double _handleHeight = 15.0;

  @override
  void dispose() {
    _keyFocus.dispose();
    super.dispose();
  }

  // --- The one pixel→t conversion for the scrub (AC-9.1.4) -------------------

  static void _scrub(ValueNotifier<double> playhead, double dx, double width) {
    if (!(width > 0)) return; // a zero-width rail has no defined position
    playhead.value = (dx / width).clamp(0.0, 1.0);
  }

  double _playheadT() {
    final t = ref.read(playheadProvider).value;
    return t.isNaN ? 0.0 : t.clamp(0.0, 1.0).toDouble();
  }

  TimelineCommands get _commands => TimelineCommands(ref, widget.projectId);

  /// Capture the messenger, and **handle `onError`** — the net every other
  /// reporter in the app has (canvas/inspector/layers/shell). A failure that is
  /// not a `StoreException`/`ArgumentError` escapes `TimelineCommands._guard` and
  /// would otherwise complete this dropped future as an unhandled async error
  /// instead of a snackbar.
  void _report(Future<String?> pending) {
    final messenger = ScaffoldMessenger.of(context);
    void show(String message) => showEditorToast(messenger, message);
    pending.then(
      (message) {
        if (message != null) show(message);
      },
      onError: (Object _, StackTrace __) => show(kRejectedKeyframeEditMessage),
    );
  }

  // --- Keyboard (docs/v3/05 §5) ---------------------------------------------

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Belt to the Focus-scope's braces: even if this node somehow held focus
    // while an EditableText did, a bare `K` must not key a track (the shell's
    // established ancestor-walk guard, replicated locally because the shell is
    // out of this milestone's scope).
    if (_typingInAField()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.comma) {
      _stepKey(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.period) {
      _stepKey(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _seek(0.0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _seek(1.0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _removeUnderPlayhead();
      } else {
        _keyAtPlayhead();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Move the playhead to [t] — `Home`/`End`. Writes the live notifier (so the
  /// canvas repaints) and settles `EditorState` (so edit-at-keyframe reads a
  /// stable value), the same live/settled pair the scrub keeps in step.
  void _seek(double t) {
    ref.read(playheadProvider).value = t;
    ref.read(editorControllerProvider.notifier).commitPlayhead(t);
  }

  /// `,` / `.` — step to the previous/next key on the selected property row,
  /// moving both the playhead and `selectedKeyframe` (via [selectKeyframe],
  /// which snaps the playhead to the key's own `t`).
  void _stepKey(int dir) {
    final selected = ref.read(editorControllerProvider).selectedKeyframe;
    if (selected == null) return;
    final (node, property, _) = selected;
    final times = _timesFor(node, property);
    if (times.isEmpty) return;
    final t = _playheadT();

    int? target;
    if (dir < 0) {
      for (var i = times.length - 1; i >= 0; i--) {
        if (times[i] < t - TrackOps.minSeparation) {
          target = i;
          break;
        }
      }
    } else {
      for (var i = 0; i < times.length; i++) {
        if (times[i] > t + TrackOps.minSeparation) {
          target = i;
          break;
        }
      }
    }
    if (target == null) return;
    ref.read(editorControllerProvider.notifier).selectKeyframe(
          node,
          property,
          target,
          snapT: times[target],
        );
  }

  /// `K` — key the selected property at the playhead with its evaluated value.
  void _keyAtPlayhead() {
    final selected = ref.read(editorControllerProvider).selectedKeyframe;
    if (selected == null) return;
    final (node, property, _) = selected;
    _report(_commands.keyAtPlayhead(node, property, _playheadT()));
  }

  /// `Shift+K` — remove the key under the playhead on the selected property row.
  void _removeUnderPlayhead() {
    final selected = ref.read(editorControllerProvider).selectedKeyframe;
    if (selected == null) return;
    final (node, property, _) = selected;
    final times = _timesFor(node, property);
    final t = _playheadT();
    for (var i = 0; i < times.length; i++) {
      if ((times[i] - t).abs() <= TrackOps.minSeparation) {
        _report(_commands.remove(node, property, i));
        return;
      }
    }
  }

  /// The selected row's key times, read off the value-equal projection — no
  /// document read from this widget (docs/v3/08 §2).
  List<double> _timesFor(NodeId node, PropertyKey property) {
    final model = ref.read(timelineModelProvider(widget.projectId));
    for (final n in model.nodes) {
      if (n.node != node) continue;
      for (final row in n.rows) {
        if (row.property == property) return row.times;
      }
    }
    return const <double>[];
  }

  /// True when the primary focus is inside an [EditableText] — the shell's
  /// load-bearing ancestor walk, replicated because the shell is out of scope.
  bool _typingInAField() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) {
    // Named slices only: duration for the readout, the notifier for the scrub.
    // Neither changes while the playhead moves, so a live scrub rebuilds nothing
    // here — only the leaf `ValueListenableBuilder` readout below (AC-9.1.3).
    final duration = ref.watch(timelineDurationProvider(widget.projectId));
    final playhead = ref.watch(playheadProvider);
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _keyFocus,
      onKeyEvent: (_, event) => _onKey(event),
      child: Container(
        color: scheme.surfaceContainerHigh,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(duration: duration, playhead: playhead),
            Expanded(
              child: Stack(
                children: [
                  Column(
                    children: [
                      _ruler(playhead, scheme, duration),
                      Expanded(
                        // Clicking in the rows focuses the timeline so its
                        // shortcuts go live — kept OFF the ruler so the scrub
                        // hot path never touches focus (and never rebuilds the
                        // canvas).
                        child: Listener(
                          onPointerDown: (_) {
                            if (!_keyFocus.hasFocus) _keyFocus.requestFocus();
                          },
                          child: TimelineRows(
                            projectId: widget.projectId,
                            labelWidth: kTimelineLabelWidth,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // The playhead, one line across the ruler and every row,
                  // driven by the notifier so the tick reaches paint() without
                  // a build. IgnorePointer so it never eats a scrub or a dot.
                  Positioned(
                    left: kTimelineLabelWidth,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _PlayheadPainter(
                          playhead: playhead,
                          color: scheme.primary,
                          onColor: scheme.onPrimary,
                          duration: duration,
                          handleHeight: _handleHeight,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruler(
      ValueNotifier<double> playhead, ColorScheme scheme, double duration) {
    return SizedBox(
      height: _rulerHeight,
      child: Row(
        children: [
          SizedBox(
            width: kTimelineLabelWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'timeline',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                // The whole ruler is the scrub target — the handle drawn on top
                // of it is `IgnorePointer`, so grabbing the handle and clicking
                // the rail are the same gesture and there is no way to "miss"
                // the thing that looks grabbable.
                return MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    key: const Key('timeline'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) =>
                        _scrub(playhead, d.localPosition.dx, width),
                    onHorizontalDragStart: (d) =>
                        _scrub(playhead, d.localPosition.dx, width),
                    onHorizontalDragUpdate: (d) =>
                        _scrub(playhead, d.localPosition.dx, width),
                    onHorizontalDragEnd: (_) =>
                        _commands.commitScrub(playhead.value),
                    child: CustomPaint(
                      size: Size(width, _rulerHeight),
                      painter: _RulerPainter(
                        rail: scheme.outlineVariant,
                        label: scheme.onSurfaceVariant,
                        duration: duration,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The seconds/`t` readout. Its own widget so only it rebuilds per tick — a leaf
/// `ValueListenableBuilder`, not a tree rebuild (AC-9.1.3).
class _Header extends StatelessWidget {
  const _Header({required this.duration, required this.playhead});

  final double duration;
  final ValueNotifier<double> playhead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Spacer(),
        ValueListenableBuilder<double>(
          valueListenable: playhead,
          builder: (context, t, _) => Text(
            // Seconds are derived for display and never stored (AC-9.1.5): the
            // document holds `t`, so a retime is one field.
            '${(t * duration).toStringAsFixed(2)} s / '
            '${duration.toStringAsFixed(2)} s  ·  t = '
            '${t.toStringAsFixed(3)}',
            key: const Key('timeline-readout'),
            style: TextStyle(
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The time scale: a baseline, a tick every tenth, and a **seconds label** on
/// the quarters.
///
/// Seconds are derived for display and never stored (AC-9.1.5) — the ruler is
/// drawn from the unitless `t` and multiplied by [duration] only here, so
/// retiming the animation relabels the ruler and moves no keyframe. Nothing
/// mutable; it repaints when the duration or the theme changes.
class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.rail,
    required this.label,
    required this.duration,
  });

  final Color rail;
  final Color label;
  final double duration;

  /// Where the scale sits inside the ruler: the top band belongs to the
  /// playhead handle, which is painted by the overlay above this one.
  static const double _labelTop = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height - 1;
    final rule = Paint()
      ..color = rail
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, baseline), Offset(size.width, baseline), rule);

    for (var i = 0; i <= 20; i++) {
      final t = i / 20;
      // The last tick is pulled a pixel inside so it is not clipped away at the
      // rail's right edge.
      final x = i == 20 ? size.width - 1 : t * size.width;
      final major = i % 5 == 0;
      canvas.drawLine(
          Offset(x, baseline - (major ? 6 : 3)), Offset(x, baseline), rule);
      if (!major) continue;

      final seconds = (t * duration).toStringAsFixed(2);
      final text = TextPainter(
        text: TextSpan(
          text: '${seconds}s',
          style: TextStyle(fontSize: 9, color: label),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Nudged inward at both ends so the first and last labels stay whole.
      final left = (x - text.width / 2)
          .clamp(0.0, math.max(0.0, size.width - text.width))
          .toDouble();
      text.paint(canvas, Offset(left, _labelTop));
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.rail != rail || old.label != label || old.duration != duration;
}

/// The playhead: a **grab handle** carrying the current time, and the line it
/// drops. Repainted from the notifier without a build, so a scrub costs one
/// paint and no rebuild (AC-9.1.3).
///
/// The handle exists because a 1-px line is not an affordance: nothing about it
/// says "drag me", and with the time only in a readout at the far right of the
/// panel, *where the playhead is* and *what time that is* were two separate
/// lookups. Reading the time off the thing you are dragging is what makes
/// "move the playhead to 0.5 s, then change the value" a single motion.
class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({
    required this.playhead,
    required this.color,
    required this.onColor,
    required this.duration,
    required this.handleHeight,
  }) : super(repaint: playhead);

  final ValueNotifier<double> playhead;
  final Color color;
  final Color onColor;
  final double duration;
  final double handleHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final raw = playhead.value;
    final t = raw.isNaN ? 0.0 : raw.clamp(0.0, 1.0).toDouble();
    final x = t * size.width;
    final paint = Paint()..color = color;

    canvas.drawLine(
      Offset(x, handleHeight),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );

    final text = TextPainter(
      text: TextSpan(
        text: '${(t * duration).toStringAsFixed(2)}s',
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600, color: onColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final w = math.max(28.0, text.width + 12);
    final body = handleHeight - 4;
    // Clamped to the rail so the handle stays whole (and readable) at t = 0 and
    // t = 1; only the pointed tip tracks the exact position.
    final left =
        (x - w / 2).clamp(0.0, math.max(0.0, size.width - w)).toDouble();

    final flag = Path()
      ..addRRect(RRect.fromLTRBR(
          left, 0, left + w, body, const Radius.circular(3)))
      ..moveTo(x - 4, body)
      ..lineTo(x + 4, body)
      ..lineTo(x, handleHeight)
      ..close();
    canvas.drawPath(flag, paint);
    text.paint(
        canvas, Offset(left + (w - text.width) / 2, (body - text.height) / 2));
    text.dispose();
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.color != color ||
      old.onColor != onColor ||
      old.duration != duration ||
      old.handleHeight != handleHeight ||
      !identical(old.playhead, playhead);
}
