/// The drop-in playback widget: an exported document on screen, animating,
/// with no editor attached (docs/v3/03 F11.1's other half).
///
/// This is the whole public surface a *consuming* app needs. Everything else in
/// this package and in `anim_core` is machinery underneath it, which is why the
/// player generator (`tool/build_player.dart`) can ship a subset: the editor's
/// ops, overlay and draft layers are unreachable from here.
///
/// **The playhead never enters `build()`.** It is a `ValueNotifier` handed to
/// [ArtboardPainter], which passes it to `super(repaint:)` — so a tick repaints
/// the `CustomPaint` and rebuilds no widget at all. The same structural reason
/// the editor's canvas stays cheap applies here, and it is the difference
/// between an icon costing a frame and costing a subtree.
library;

import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_core/anim_core.dart' as anim show Animation;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'artboard_painter.dart';
import 'paint_translation.dart';
import 'path_geometry.dart';

/// Renders a [Document] — or the JSON the editor exported — and animates it.
///
/// Two constructors rather than one taking `dynamic`: [AnimPlayer.fromJson]
/// owns a decode that can fail, and a failure there is a *widget-boundary*
/// concern with an [errorBuilder], not something to push onto every caller that
/// already holds a decoded document.
///
/// ```dart
/// AnimPlayer.fromJson(await rootBundle.loadString('assets/spinner.json'))
/// ```
class AnimPlayer extends StatefulWidget {
  /// Play an already-decoded document.
  const AnimPlayer({
    super.key,
    required Document this.document,
    this.animationId,
    this.playing = true,
    this.speed = 1.0,
    this.drawBackground = true,
    this.clipToArtboard = true,
    this.onCompleted,
    this.errorBuilder,
  })  : source = null,
        assert(speed > 0, 'speed must be positive');

  /// Decode and play the editor's `Export .json` output.
  ///
  /// The bytes are exactly what `Document.toJson` writes, so a file exported
  /// from the editor re-opens here with no conversion step.
  const AnimPlayer.fromJson(
    String this.source, {
    super.key,
    this.animationId,
    this.playing = true,
    this.speed = 1.0,
    this.drawBackground = true,
    this.clipToArtboard = true,
    this.onCompleted,
    this.errorBuilder,
  })  : document = null,
        assert(speed > 0, 'speed must be positive');

  /// The decoded document, when the caller already had one.
  final Document? document;

  /// The undecoded export, when the caller did not.
  final String? source;

  /// Which animation to play. Falls back to the document's default, then to its
  /// first, then to the rest pose — each of which is a defined render, not an
  /// error (docs/v3/01 §11).
  final AnimationId? animationId;

  /// Whether the clock runs. Flipping it to false holds the current frame
  /// rather than resetting, so it reads as pause, not stop.
  final bool playing;

  /// Wall-clock multiplier. 2.0 plays twice as fast; the authored
  /// `durationSeconds` and loop mode are otherwise untouched.
  final double speed;

  /// Fill the artboard rect with the document's authored background first.
  ///
  /// A fully transparent background is legal and draws nothing, which is how an
  /// icon sits on a coloured surface without punching a hole in it.
  final bool drawBackground;

  /// Clip geometry at the artboard edge, as the export preview does
  /// (AC-1.1.3). Off, off-board geometry spills into the surrounding layout.
  final bool clipToArtboard;

  /// Called once when a [LoopMode.once] animation reaches `t == 1`.
  final VoidCallback? onCompleted;

  /// Shown when [AnimPlayer.fromJson] cannot decode its input.
  ///
  /// Default is an empty `SizedBox`: a malformed icon should leave a hole in
  /// the layout, not take the host app down. The exception is still handed over
  /// so a caller that wants to log or surface it can.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<AnimPlayer> createState() => _AnimPlayerState();
}

class _AnimPlayerState extends State<AnimPlayer>
    with SingleTickerProviderStateMixin {
  /// Identity is stable for the widget's lifetime; only its value changes —
  /// the painter holds it as its `repaint` listenable.
  final ValueNotifier<double> _playhead = ValueNotifier<double>(0.0);

  late Ticker _ticker;

  /// Seconds of *animation* time, already scaled by [AnimPlayer.speed]. Kept
  /// separately from the ticker's own elapsed so a speed change does not jump
  /// the playhead backwards.
  double _elapsed = 0.0;

  /// Nullable, and deliberately not a `Duration.zero` sentinel: a `Ticker`'s
  /// FIRST callback arrives with `elapsed == Duration.zero`, so a zero sentinel
  /// never clears and every delta stays 0 — the animation renders its first
  /// frame forever. Null means "no previous tick"; zero means "the tick at
  /// time zero", and they are different facts.
  Duration? _lastTick;

  Document? _document;
  Object? _decodeError;
  bool _completedNotified = false;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = createTicker(_onTick);
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(AnimPlayer old) {
    super.didUpdateWidget(old);

    // Re-decode only when the input actually changed. Comparing the source
    // string is cheap next to `Document.fromJson`, and a parent that rebuilds
    // every frame is the common case, not the exotic one.
    if (widget.source != old.source || !identical(widget.document, old.document)) {
      _load();
      _elapsed = 0.0;
      _completedNotified = false;
      _playhead.value = 0.0;
    }
    if (widget.animationId != old.animationId) _completedNotified = false;

    if (widget.playing != old.playing) {
      if (widget.playing) {
        // Drop the stale timestamp so the paused interval is not charged to
        // the playhead as one huge delta on the next tick.
        _lastTick = null;
        _ticker.start();
      } else {
        _ticker.stop();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _playhead.dispose();
    super.dispose();
  }

  /// Decode, or record why not. The `catch` is deliberate and belongs here:
  /// this is the widget boundary the evaluator's totality rule defers guards to
  /// (docs/v3/08 §1), and there *is* a user to tell.
  void _load() {
    final source = widget.source;
    if (source == null) {
      _document = widget.document;
      _decodeError = null;
      return;
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('expected a JSON object at the top level');
      }
      _document = Document.fromJson(decoded);
      _decodeError = null;
    } catch (e) {
      _document = null;
      _decodeError = e;
    }
  }

  /// The animation the playhead is a position within, or null for the rest
  /// pose — all three fallbacks are defined renders.
  anim.Animation? get _animation {
    final doc = _document;
    if (doc == null || doc.animations.isEmpty) return null;
    final wanted = widget.animationId;
    if (wanted != null) {
      for (final a in doc.animations) {
        if (a.id == wanted) return a;
      }
      // A named animation that is not in the document is stale data, not a
      // crash — same rule `Document.defaultAnimation` applies one level up.
    }
    return doc.defaultAnimation ?? doc.animations.first;
  }

  void _onTick(Duration now) {
    // The ticker's elapsed is monotonic from *its* start, so take deltas: a
    // stop/start pair must not teleport the playhead by the paused interval.
    final previous = _lastTick;
    final delta = previous == null ? Duration.zero : now - previous;
    _lastTick = now;
    _elapsed += delta.inMicroseconds / Duration.microsecondsPerSecond *
        widget.speed;

    final a = _animation;
    if (a == null) {
      _playhead.value = 0.0;
      return;
    }
    final t = normalizedTime(a, _elapsed);
    _playhead.value = t;

    if (a.loop == LoopMode.once && t >= 1.0 && !_completedNotified) {
      _completedNotified = true;
      widget.onCompleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _decodeError;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ?? const SizedBox.shrink();
    }
    final doc = _document;
    if (doc == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        // An unbounded axis has no artboard to letterbox into; fall back to the
        // authored size so the player is usable inside a Column or a ListView
        // without the caller wrapping it in a SizedBox.
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : doc.artboard.x,
          constraints.hasBoundedHeight ? constraints.maxHeight : doc.artboard.y,
        );
        final fit = artboardFit(doc.artboard, size);

        return SizedBox.fromSize(
          size: size,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _BackgroundFill(
                enabled: widget.drawBackground,
                artboard: doc.artboard,
                background: doc.background,
                fit: fit,
              ),
              foregroundPainter: ArtboardPainter(
                document: doc,
                playhead: _playhead,
                animation: _animation?.id,
                fit: fit,
                mode: widget.clipToArtboard
                    ? RenderMode.exportPreview
                    : RenderMode.editor,
              ),
              size: size,
            ),
          ),
        );
      },
    );
  }
}

/// The document's authored background, and nothing else.
///
/// Deliberately not `BackgroundPainter`: that one also draws the editor's board
/// outline from a themed `edge` colour, which is chrome a consuming app must
/// never inherit. One rect, one colour.
class _BackgroundFill extends CustomPainter {
  const _BackgroundFill({
    required this.enabled,
    required this.artboard,
    required this.background,
    required this.fit,
  });

  final bool enabled;
  final Vec2 artboard;
  final Rgba background;
  final Affine fit;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || background.a <= 0) return;
    final origin = fit.apply(Vec2.zero);
    final corner = fit.apply(artboard);
    canvas.drawRect(
      Rect.fromPoints(
        Offset(origin.x, origin.y),
        Offset(corner.x, corner.y),
      ),
      Paint()..color = toUiColor(background, 1.0),
    );
  }

  @override
  bool shouldRepaint(_BackgroundFill old) =>
      old.enabled != enabled ||
      old.background != background ||
      old.artboard != artboard ||
      old.fit != fit;
}
