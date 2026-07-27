import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/number_field.dart';
import '../../../state/editor_controller.dart';
import '../commands.dart';
import '../providers.dart';

/// The transport bar — play/pause, loop mode, duration and the seconds↔`t`
/// readout (F9.1, docs/v3/05 §2 TRANSPORT row).
///
/// **The one hot path is the Ticker, and it writes ONLY `playhead.value`**
/// (docs/v3/04 §4). Each frame it computes elapsed seconds and pushes
/// `normalizedTime(activeAnimation, elapsed)` into the `playheadProvider`
/// notifier — no provider is invalidated and no panel rebuilds, so the tick
/// reaches the canvas painter through `CustomPainter(repaint:)` without entering
/// any `build()`. Legacy derived the playhead from a widget's pixel width
/// through a `BuildContext`, which made the engine resolution-dependent and the
/// playhead impossible to test without a widget tree; here the playhead is a
/// unitless double the whole way down and pixels never touch it (AC-9.1.4).
///
/// **`playing` is the single source of truth for the Ticker's lifecycle.** The
/// play button and the shell's `Enter` shortcut both merely flip
/// `EditorState.playing`; a `ref.listen` here reconciles the Ticker to it —
/// start on `true`, stop-and-commit on `false`. That is what lets a shortcut in
/// a different widget drive a Ticker this widget owns without either reaching
/// into the other. On stop the settled `t` is committed once via
/// `commitPlayhead`, exactly as scrub-end does.
///
/// The Ticker is DISPOSED with the widget: a leaked Ticker keeps ticking after
/// the editor is gone (docs/v3/04 §4), and `SingleTickerProviderStateMixin`
/// asserts it was disposed.
class TransportBar extends ConsumerStatefulWidget {
  const TransportBar({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends ConsumerState<TransportBar>
    with SingleTickerProviderStateMixin {
  /// Created eagerly in [initState], NOT lazily: a lazy `late` initializer would
  /// run `createTicker` (which does an ancestor `TickerMode` lookup) on first
  /// touch — and in a session that never played, first touch is [dispose], when
  /// the element is deactivated and that lookup throws. Building it while mounted
  /// keeps [dispose] a plain `_ticker.dispose()`.
  late final Ticker _ticker;

  /// The elapsed-seconds offset that maps the frame the Ticker started on to the
  /// playhead position play resumed from — so pressing Play mid-timeline picks
  /// up where the playhead is, not from zero.
  double _startElapsedSeconds = 0.0;

  /// The loop mode + duration the tick needs, cached from the watched slice so
  /// the tick reads a plain field and never the document (docs/v3/08 §2).
  TransportModel _model = restingTransport;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  static double _clampT(double t) =>
      t.isNaN ? 0.0 : t.clamp(0.0, 1.0).toDouble();

  /// Reconcile the Ticker to [playing] — the ONE place it starts or stops.
  void _reconcile(bool playing) {
    if (playing) {
      if (_ticker.isActive) return;
      var startT = _clampT(ref.read(playheadProvider).value);
      // `once` parked at the end replays from the top, so Play is never a dead
      // button once the clip has finished.
      if (_model.loop == LoopMode.once && startT >= 1.0) startT = 0.0;
      _startElapsedSeconds = startT * _model.durationSeconds;
      _ticker.start();
    } else {
      if (!_ticker.isActive) return;
      _ticker.stop();
      // Settle the live value into EditorState ONCE, exactly as scrub-end does.
      ref
          .read(editorControllerProvider.notifier)
          .commitPlayhead(_clampT(ref.read(playheadProvider).value));
    }
  }

  void _onTick(Duration elapsed) {
    final model = _model;
    final elapsedSeconds = _startElapsedSeconds +
        elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    // THE ONLY per-frame write — the ValueNotifier hot path (docs/v3/04 §4).
    ref.read(playheadProvider).value =
        transportNormalizedTime(model, elapsedSeconds);
    // `once` STOPS at t = 1 (AC-9.1.2). Requesting pause through `playing` keeps
    // one reconciler: the listener stops the Ticker and commits the settled t.
    if (model.loop == LoopMode.once &&
        elapsedSeconds >= model.durationSeconds) {
      ref.read(editorControllerProvider.notifier).setPlaying(false);
    }
  }

  void _setLoop(LoopMode loop) {
    final id = _model.animationId;
    if (id == null) return;
    _report(TransportCommands(ref, widget.projectId).setLoop(id, loop));
  }

  void _setDuration(double seconds) {
    final id = _model.animationId;
    if (id == null) return;
    _report(TransportCommands(ref, widget.projectId).setDuration(id, seconds));
  }

  /// The ⏮ / ⏭ skip — jump to `t = 0` / `t = 1`. Pauses first so it never fights
  /// the Ticker (docs/v3/05 §4.7), then writes the live notifier (the canvas
  /// repaints) and settles `EditorState` — the same live/settled pair the scrub
  /// keeps in step, and the playhead never round-trips through pixels
  /// (AC-9.1.4).
  void _seek(double t) {
    ref.read(editorControllerProvider.notifier).setPlaying(false);
    ref.read(playheadProvider).value = t;
    ref.read(editorControllerProvider.notifier).commitPlayhead(t);
  }

  /// Capture the messenger and **handle `onError`** — the net every reporter in
  /// the app has, so a failure that escapes `TransportCommands._guard` becomes a
  /// snackbar rather than an unhandled async error (docs/v3/08 §1).
  void _report(Future<String?> pending) {
    final messenger = ScaffoldMessenger.of(context);
    void show(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    pending.then(
      (message) {
        if (message != null) show(message);
      },
      onError: (Object _, StackTrace __) => show(kRejectedTransportEditMessage),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Named slices only. `_model` changes on a loop/duration edit; `playing`
    // changes on a play/pause. Neither changes per tick, so playback rebuilds
    // this bar not once (only the leaf readout below, off the notifier).
    _model = ref.watch(transportModelProvider(widget.projectId));
    final playing =
        ref.watch(editorControllerProvider.select((s) => s.playing));
    // Reconcile the Ticker to `playing` AFTER the build, never during it — a
    // `ref.listen` is the side-effect-safe channel between the button/shortcut
    // that flips the bit and the Ticker this widget owns.
    ref.listen(editorControllerProvider.select((s) => s.playing),
        (_, next) => _reconcile(next));

    final playhead = ref.watch(playheadProvider);
    final scheme = Theme.of(context).colorScheme;
    final hasAnimation = _model.animationId != null;

    // The fixed control cluster, left of the readout. Kept as a list so the two
    // width regimes below share exactly one definition of the controls.
    final controls = <Widget>[
      IconButton(
        key: const Key('transport-skip-start'),
        tooltip: 'To start',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        onPressed: () => _seek(0.0),
        icon: const Icon(Icons.skip_previous),
      ),
      IconButton(
        key: const Key('transport-play'),
        tooltip: playing ? 'Pause' : 'Play',
        iconSize: 22,
        visualDensity: VisualDensity.compact,
        onPressed: () =>
            ref.read(editorControllerProvider.notifier).togglePlaying(),
        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      ),
      IconButton(
        key: const Key('transport-skip-end'),
        tooltip: 'To end',
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        onPressed: () => _seek(1.0),
        icon: const Icon(Icons.skip_next),
      ),
      const SizedBox(width: 12),
      _LoopSelector(
          loop: _model.loop, enabled: hasAnimation, onChanged: _setLoop),
      const SizedBox(width: 16),
      Text('duration',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      const SizedBox(width: 6),
      SizedBox(
        width: 64,
        child: CommittedNumberField(
          key: const Key('transport-duration'),
          value: _model.durationSeconds,
          enabled: hasAnimation,
          onCommit: _setDuration,
        ),
      ),
      const SizedBox(width: 4),
      Text('s', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    ];

    // The seconds↔t readout, a LEAF ValueListenableBuilder so ONLY it rebuilds
    // per tick — not the bar, and never the canvas (docs/v3/04 §4, AC-9.1.3).
    Widget readout({required bool tight}) => ValueListenableBuilder<double>(
          valueListenable: playhead,
          builder: (context, raw, _) {
            final t = _clampT(raw);
            final duration = _model.durationSeconds;
            return Text(
              '${(t * duration).toStringAsFixed(2)} s / '
              '${duration.toStringAsFixed(2)} s  ·  t = '
              '${t.toStringAsFixed(3)}',
              key: const Key('transport-readout'),
              textAlign: tight ? TextAlign.left : TextAlign.right,
              maxLines: 1,
              overflow: tight ? TextOverflow.clip : TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            );
          },
        );

    // The centre column is narrow (the transport lives beneath the canvas, not
    // full-width — see editor_shell), so the bar must never RenderFlex-overflow:
    // a panel throwing during layout is docs/v3/08 §2's white screen. When there
    // is room the readout is `Expanded` and right-aligned; when there is not, the
    // whole cluster scrolls horizontally rather than overflowing.
    const double roomyWidth = 460.0;
    return Container(
      color: scheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= roomyWidth) {
            return Row(
              children: [
                ...controls,
                const SizedBox(width: 12),
                Expanded(child: readout(tight: false)),
              ],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...controls,
                const SizedBox(width: 12),
                readout(tight: true),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The once / loop / pingPong selector — three keyed chips rather than a
/// `SegmentedButton`, so each mode is a stable hit target in a fixed-height bar
/// (`transport-loop-<mode>`), and the whole control stays compact enough not to
/// overflow the TRANSPORT row.
class _LoopSelector extends StatelessWidget {
  const _LoopSelector({
    required this.loop,
    required this.enabled,
    required this.onChanged,
  });

  final LoopMode loop;
  final bool enabled;
  final ValueChanged<LoopMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in LoopMode.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _LoopChip(
              key: Key('transport-loop-${mode.name}'),
              label: mode.name,
              selected: mode == loop,
              enabled: enabled,
              onTap: () => onChanged(mode),
            ),
          ),
      ],
    );
  }
}

class _LoopChip extends StatelessWidget {
  const _LoopChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(6);
    final Color fg = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(label, style: TextStyle(fontSize: 11, color: fg)),
        ),
      ),
    );
  }
}
