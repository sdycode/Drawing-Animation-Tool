/// Animations and the time model (docs/v3/01 §10, docs/v3/02 §3.8).
library;

import 'decode.dart';
import 'json.dart';
import 'primitives.dart';
import 'track.dart';

enum LoopMode { once, loop, pingPong }

final class Animation {
  const Animation({
    required this.id,
    required this.name,
    this.durationSeconds = 1.0,
    this.fps = 60,
    this.loop = LoopMode.loop,
    this.tracks = const {},
    this.unknownKeys = const {},
  });

  final AnimationId id;
  final String name;

  /// Playback hint only. Changing it retimes everything proportionally and
  /// re-authors nothing, because every `t` is normalized.
  final double durationSeconds;

  /// Preview/export hint. **Nothing in the model is quantized to frames** — the
  /// one deliberate `int` in the format.
  final int fps;

  final LoopMode loop;

  /// PER-NODE, PER-PROPERTY, SPARSE. A node absent here is fully static.
  ///
  /// Nodes may hold wildly different key counts at wildly different positions:
  /// there is no shared keyframe grid, and no cache keyed by selection. Legacy
  /// populated its derived list only for the *currently selected* section, so
  /// every other section rendered frozen at keyframe 0 during playback.
  ///
  /// Tracks hang off the animation, not off the node. That is what makes
  /// multiple clips, blending and the state machine additive rather than a
  /// rewrite, and it costs v1 nothing.
  final Map<NodeId, TrackSet> tracks;

  final Map<String, Object?> unknownKeys;

  Animation copyWith({
    String? name,
    double? durationSeconds,
    int? fps,
    LoopMode? loop,
    Map<NodeId, TrackSet>? tracks,
  }) =>
      Animation(
        id: id,
        name: name ?? this.name,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        fps: fps ?? this.fps,
        loop: loop ?? this.loop,
        tracks: tracks ?? this.tracks,
        unknownKeys: unknownKeys,
      );

  /// The [TrackSet] for [node], or [TrackSet.empty] — never null, so a caller
  /// has no reason to reach for `!`.
  TrackSet tracksFor(NodeId node) => tracks[node] ?? TrackSet.empty;

  static const _known = <String>{
    'id',
    'name',
    'durationSeconds',
    'fps',
    'loop',
    'tracks',
  };

  factory Animation.fromJson(Object? j, [String path = '']) {
    final m = reqObject(j, path);
    return Animation(
      // Required: `defaultAnimationId` joins to it, and an animation this
      // build invented an id for would be re-saved as a different animation
      // every time the document is opened.
      id: AnimationId(reqString(m['id'], jsonChild(path, 'id'))),
      name: opt(m, 'name', (v) => reqString(v, jsonChild(path, 'name')), ''),
      durationSeconds: opt(m, 'durationSeconds',
          (v) => reqDouble(v, jsonChild(path, 'durationSeconds')), 1.0),
      fps: opt(m, 'fps', (v) => reqInt(v, jsonChild(path, 'fps')), 60),
      // An unrecognised loop mode falls back rather than throwing: it costs one
      // playback behaviour, while throwing costs the whole document.
      loop: opt(
          m,
          'loop',
          (v) => LoopMode.values.asNameMap()[v] ?? LoopMode.loop,
          LoopMode.loop),
      tracks: opt(
        m,
        'tracks',
        (v) => Map.unmodifiable(<NodeId, TrackSet>{
          for (final e in reqObject(v, jsonChild(path, 'tracks')).entries)
            NodeId(e.key): TrackSet.fromJson(
                e.value, jsonChild(jsonChild(path, 'tracks'), e.key)),
        }),
        const <NodeId, TrackSet>{},
      ),
      unknownKeys: unknownKeysOf(m, _known),
    );
  }

  Map<String, Object?> toJson() => withUnknown(unknownKeys, <String, Object?>{
        'id': id.v,
        'name': name,
        'durationSeconds': durationSeconds,
        'fps': fps,
        'loop': loop.name,
        'tracks': <String, Object?>{
          for (final e in tracks.entries) e.key.v: e.value.toJson(),
        },
      });

  @override
  String toString() => 'Animation(${id.v}, ${tracks.length} tracked nodes)';
}

/// Wall-clock → normalized `t`.
///
/// Lives **outside** the evaluator so the evaluator stays a pure sampler: it
/// takes a `t` and knows nothing about clocks, loop modes or seconds. Legacy
/// derived its playhead from a widget's pixel width via `BuildContext`, which
/// made the engine resolution-dependent and untestable without a widget tree.
double normalizedTime(Animation a, double elapsedSeconds) {
  // Total by construction: a zero or negative duration is authorable by hand in
  // a stored document, and dividing by it would hand Infinity/NaN to every
  // track in the tick.
  if (!(a.durationSeconds > 0.0) || !elapsedSeconds.isFinite) return 0.0;
  final x = elapsedSeconds / a.durationSeconds;
  return switch (a.loop) {
    LoopMode.once => x.clamp(0.0, 1.0),
    LoopMode.loop => x - x.floorToDouble(),
    LoopMode.pingPong => _triangle(x),
  };
}

/// 0 → 1 → 0 with period 2, defined for negative `x` too (a scrub can run
/// backwards past zero).
double _triangle(double x) {
  final m = x - 2.0 * (x / 2.0).floorToDouble();
  return m <= 1.0 ? m : 2.0 - m;
}
