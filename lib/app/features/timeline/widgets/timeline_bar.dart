import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_controller.dart';
import '../commands.dart';
import '../providers.dart';

/// The scrub bar — F9.1, thin (docs/v3/03).
///
/// **Pixels appear only in this widget's paint and hit-test (AC-9.1.4).** The
/// conversion `t = dx / width` happens in [_seek] and nowhere else; downstream
/// the playhead is a unitless normalized double. Legacy round-tripped it
/// through pixels and a `BuildContext`, so the model's notion of "now" was a
/// function of the window size.
///
/// **Live scrub preview (AC-9.1.3).** The drag writes `playhead.value`
/// directly: no `setState`, no provider write, no rebuild. The two canvas
/// painters take that same notifier as `repaint:`, so interpolated geometry
/// appears *while* dragging rather than on release, and it costs a paint rather
/// than a frame's worth of widget building.
class TimelineBar extends ConsumerWidget {
  const TimelineBar({required this.projectId, super.key});

  final String projectId;

  static const double railInset = 16.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Named slices only; neither changes while the playhead moves. `build` is a
    // pure read — no code path here mutates the document (AC-6.2.5).
    final duration = ref.watch(timelineDurationProvider(projectId));
    final keys = ref.watch(timelineKeyTimesProvider(projectId));
    final playhead = ref.watch(playheadProvider);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: railInset, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${keys.length} key${keys.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              // Only this readout rebuilds per tick, and it rebuilds because a
              // number changed on screen — not because state moved. The canvas
              // above is untouched.
              ValueListenableBuilder<double>(
                valueListenable: playhead,
                builder: (context, t, _) => Text(
                  // Seconds are derived for display and never stored
                  // (AC-9.1.5): the document holds t, so retiming is one field.
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
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  key: const Key('timeline'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _seek(playhead, d.localPosition.dx, width),
                  onHorizontalDragStart: (d) =>
                      _seek(playhead, d.localPosition.dx, width),
                  onHorizontalDragUpdate: (d) =>
                      _seek(playhead, d.localPosition.dx, width),
                  onHorizontalDragEnd: (_) =>
                      TimelineCommands(ref).commitScrub(playhead.value),
                  child: CustomPaint(
                    size: Size(width, 28),
                    painter: _ScrubPainter(
                      playhead: playhead,
                      keys: keys,
                      rail: scheme.outlineVariant,
                      keyDot: scheme.tertiary,
                      handle: scheme.primary,
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

  /// The one and only pixel→`t` conversion in the app.
  ///
  /// Clamped rather than rejected: a drag that leaves the bar should pin to the
  /// end, which is what every scrub bar the user has ever touched does. Writing
  /// `.value` is the whole mechanism — it reaches `paint()` on the next frame
  /// without invalidating a provider or rebuilding a widget.
  static void _seek(ValueNotifier<double> playhead, double dx, double width) {
    if (!(width > 0)) return; // a zero-width rail has no defined position
    playhead.value = (dx / width).clamp(0.0, 1.0);
  }
}

/// Rail, keyframe dots, playhead handle. Nothing else, and nothing mutable.
class _ScrubPainter extends CustomPainter {
  _ScrubPainter({
    required this.playhead,
    required this.keys,
    required this.rail,
    required this.keyDot,
    required this.handle,
  }) : super(repaint: playhead);

  final ValueNotifier<double> playhead;
  final List<double> keys;
  final Color rail;
  final Color keyDot;
  final Color handle;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    double x(double t) => t.clamp(0.0, 1.0) * size.width;

    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..strokeWidth = 2
        ..color = rail,
    );

    // Dots come from the document's key times, so a key at 0.13 sits at 0.13 —
    // there is no grid to snap to and no column to align with (AC-6.1.1).
    final dot = Paint()..color = keyDot;
    for (final t in keys) {
      if (!t.isFinite) continue;
      canvas.drawCircle(Offset(x(t), y), 4, dot);
    }

    final t = playhead.value;
    final at = x(t.isNaN ? 0.0 : t);
    canvas.drawLine(
      Offset(at, 2),
      Offset(at, size.height - 2),
      Paint()
        ..strokeWidth = 2
        ..color = handle,
    );
  }

  @override
  bool shouldRepaint(_ScrubPainter old) =>
      !identical(old.playhead, playhead) ||
      !listEquals(old.keys, keys) ||
      old.rail != rail ||
      old.keyDot != keyDot ||
      old.handle != handle;
}
