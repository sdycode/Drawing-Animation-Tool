/// Property tracks, keyframes and poses (docs/v3/01 §7, docs/v3/02 §3.9–3.10).
library;

import 'decode.dart';
import 'easing.dart';
import 'json.dart';
import 'primitives.dart';

/// What a **path keyframe** stores for one anchor. No id — the map key is the
/// id (docs/v3/01 §5).
final class AnchorPose {
  const AnchorPose(this.position, this.inTangent, this.outTangent);

  final Vec2 position;
  final Vec2 inTangent;
  final Vec2 outTangent;

  static AnchorPose lerp(AnchorPose a, AnchorPose b, double u) => AnchorPose(
        Vec2.lerp(a.position, b.position, u),
        Vec2.lerp(a.inTangent, b.inTangent, u),
        Vec2.lerp(a.outTangent, b.outTangent, u),
      );

  factory AnchorPose.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return AnchorPose(
      Vec2.fromJson(m['position']),
      opt(m, 'inTangent', Vec2.fromJson, Vec2.zero),
      opt(m, 'outTangent', Vec2.fromJson, Vec2.zero),
    );
  }

  /// The **total** read (docs/v3/08 §2). See [Vec2.tryFromJson].
  static AnchorPose? tryFromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final position = Vec2.tryFromJson(j['position']);
    if (position == null) return null;
    final into = j.containsKey('inTangent')
        ? Vec2.tryFromJson(j['inTangent'])
        : Vec2.zero;
    final out = j.containsKey('outTangent')
        ? Vec2.tryFromJson(j['outTangent'])
        : Vec2.zero;
    if (into == null || out == null) return null;
    return AnchorPose(position, into, out);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'position': position.toJson(),
        'inTangent': inTangent.toJson(),
        'outTangent': outTangent.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is AnchorPose &&
      other.position == position &&
      other.inTangent == inTangent &&
      other.outTangent == outTangent;

  @override
  int get hashCode => Object.hash(position, inTangent, outTangent);

  @override
  String toString() => 'AnchorPose($position)';
}

/// The value of a path keyframe: **poses only**.
///
/// Not a list, not an anchor count, not `closed`. Which anchors exist is a
/// property of the shape and lives on the node; a keyframe varies only where
/// those anchors sit. That split is what makes a mismatched anchor set
/// unrepresentable, and it is the entire reason v3 exists (docs/v3/01 §1).
final class PathPose {
  const PathPose(this.anchors);

  final Map<AnchorId, AnchorPose> anchors;

  static const empty = PathPose(<AnchorId, AnchorPose>{});

  factory PathPose.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    final raw = opt(m, 'anchors', (v) => v! as Map<String, Object?>,
        const <String, Object?>{});
    return PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
      for (final e in raw.entries)
        AnchorId(e.key): AnchorPose.fromJson(e.value),
    }));
  }

  /// The **total** read (docs/v3/08 §2). One unreadable anchor pose degrades
  /// the whole pose — and therefore the whole track — to preserved-verbatim,
  /// because a keyframe posing *some* of its anchors is not a partial success,
  /// it is a keyframe that would silently snap the missing ones to rest.
  static PathPose? tryFromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    if (!j.containsKey('anchors')) return empty;
    final raw = j['anchors'];
    if (raw is! Map<String, Object?>) return null;
    final poses = <AnchorId, AnchorPose>{};
    for (final e in raw.entries) {
      final pose = AnchorPose.tryFromJson(e.value);
      if (pose == null) return null;
      poses[AnchorId(e.key)] = pose;
    }
    return PathPose(Map.unmodifiable(poses));
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'anchors': <String, Object?>{
          for (final e in anchors.entries) e.key.v: e.value.toJson(),
        },
      };

  @override
  String toString() => 'PathPose(${anchors.length} poses)';
}

class Keyframe<T> {
  const Keyframe({
    required this.t,
    required this.value,
    this.easing = const LinearEasing(),
  });

  /// **Normalized 0..1**, and the only ordering key. There is no `frameNo` in
  /// v3 — legacy's was a meaningless insertion tag that got used as an array
  /// subscript anyway.
  final double t;

  final T value;

  /// Governs the segment **leaving** this key.
  ///
  /// The default is linear — the identity of the operation. `easeInOut` is the
  /// *pen/keyframe UI* default and never the model default: a non-identity
  /// model default silently curves every programmatically created key, breaks
  /// bit-identical legacy import, and is invisible until someone diffs a render.
  final Easing easing;

  /// The same key at a different [t] or [easing], **preserving [value]** — and,
  /// covariantly on [Vec2Keyframe], its spatial tangents.
  ///
  /// [TrackOps.moveKeyframe] and [TrackOps.setEasing] rebuild through this
  /// rather than `Keyframe(t: …, value: k.value, …)` for one reason: a plain
  /// reconstruct drops a [Vec2Keyframe]'s `inTangent`/`outTangent`, silently
  /// straightening a motion path the moment its key is dragged in time. `value`
  /// is deliberately absent — these ops never change it, and a `T? value` cannot
  /// tell "omitted" from "set to null" when `T` is nullable.
  Keyframe<T> copyWith({double? t, Easing? easing}) => Keyframe<T>(
        t: t ?? this.t,
        value: value,
        easing: easing ?? this.easing,
      );

  /// Keyframe-level `unknownKeys` (docs/v3/02 §7) are deliberately not modelled
  /// yet: the reserved keys that exist today (`pins`) sit at track level, and
  /// doc 01 §7 writes this type with exactly three fields.
  Map<String, Object?> toJson() => <String, Object?>{
        't': t,
        'value': _encodeValue(value),
        'easing': easing.toJson(),
      };

  @override
  String toString() => 'Keyframe(t: $t, $value)';
}

/// Vec2 keys additionally carry **spatial** tangents — curved motion paths.
///
/// `easing` shapes TIME along the segment; these shape SPACE. The two are
/// orthogonal and both are needed for a ball that arcs *and* accelerates. Null
/// means straight-line lerp, which is the unchanged fast path.
final class Vec2Keyframe extends Keyframe<Vec2> {
  const Vec2Keyframe({
    required super.t,
    required super.value,
    super.easing,
    this.inTangent,
    this.outTangent,
  });

  /// Relative to [value].
  final Vec2? inTangent;
  final Vec2? outTangent;

  /// Carries the spatial tangents across a time/easing edit — see
  /// [Keyframe.copyWith]. Without this override, moving a motion-path key in
  /// time would return a plain [Keyframe] and lose its curve.
  @override
  Vec2Keyframe copyWith({double? t, Easing? easing}) => Vec2Keyframe(
        t: t ?? this.t,
        value: value,
        easing: easing ?? this.easing,
        inTangent: inTangent,
        outTangent: outTangent,
      );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        't': t,
        'value': value.toJson(),
        if (inTangent != null) 'inTangent': inTangent!.toJson(),
        if (outTangent != null) 'outTangent': outTangent!.toJson(),
        'easing': easing.toJson(),
      };
}

Object? _encodeValue(Object? v) => switch (v) {
      final Vec2 x => x.toJson(),
      final Rgba x => x.toJson(),
      final PathPose x => x.toJson(),
      _ => v,
    };

/// Non-generic facade.
///
/// The evaluator and the decoder deal in this type; a raw `Track<Object?>`
/// never escapes a [TrackSet]. Dart generics are covariant, so an untyped view
/// is an unsound call waiting to happen.
sealed class Track {
  const Track();

  int get keyCount;
  double get firstT;
  double get lastT;

  /// Every key's `t`, in order — the timeline's dot positions as a **pure read**
  /// (AC-6.2.5), type-agnostic so a `byKey` loop can draw every property row
  /// without downcasting to each track type. Derived from the one key list, not
  /// a stored parallel array (invariant T4).
  List<double> get keyTimes;

  /// The type-erased read. [PathTrack] returns null here **on purpose** —
  /// see its override.
  Object? sampleDynamic(double t);

  Map<String, Object?> toJson();

  /// The keys this decoder claims. Everything else on a track object is
  /// preserved (docs/v3/02 §7) — `pins` on a path track is the reserved key
  /// that exists today.
  static const _known = <String>{'type', 'keys'};

  /// Null for a track type this build does not know, for one whose keys
  /// violate T1/T2/T3, **and for one whose key values this build cannot read**.
  ///
  /// Returning null rather than throwing is what lets [TrackSet] preserve the
  /// raw JSON verbatim (docs/v3/02 §7) without `anim_core` growing a `try` —
  /// which docs/v3/08 §1 forbids outright. The T1/T2/T3 pre-check exists
  /// because those violations are *real* in shipped data: legacy's Squares.json
  /// has three keyframes at exactly the same position, and constructing that
  /// track would throw `ArgumentError` out of the middle of a document decode.
  ///
  /// The **value** side has to degrade the same way, and by the same route: a
  /// blind `(v as num)` on one keyframe of one track would unwind out of
  /// `Document.fromJson` and cost the user every node in the file, when the
  /// surrounding code already knows how to ride that one track through
  /// untouched. Hence the `try*` decoders rather than the throwing factories —
  /// degrade at the leaf, preserve at the container.
  static Track? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final raw = j['keys'];
    if (raw is! List<Object?> || !_wellFormedKeys(raw)) return null;
    final unknown = unknownKeysOf(j, _known);
    return switch (j['type']) {
      'scalar' => _typed(raw, _tryScalar, (k) => ScalarTrack(k, unknown)),
      'vec2' => _vec2Track(raw, unknown),
      'color' => _typed(raw, Rgba.tryFromJson, (k) => ColorTrack(k, unknown)),
      'bool' => _typed(raw, _tryBool, (k) => BoolTrack(k, unknown)),
      'path' => _typed(raw, PathPose.tryFromJson, (k) => PathTrack(k, unknown)),
      _ => null,
    };
  }

  static bool _wellFormedKeys(List<Object?> raw) {
    if (raw.isEmpty) return false;
    var previous = double.negativeInfinity;
    for (final entry in raw) {
      if (entry is! Map<String, Object?>) return false;
      final t = entry['t'];
      if (t is! num) return false;
      final v = t.toDouble();
      if (v.isNaN || v < 0.0 || v > 1.0 || v <= previous) return false;
      previous = v;
    }
    return true;
  }

  static double? _tryScalar(Object? v) => v is num ? v.toDouble() : null;

  static bool? _tryBool(Object? v) => v is bool ? v : null;

  /// Absent easing is linear; **unreadable** easing degrades the whole track.
  ///
  /// Not "unreadable easing degrades to linear": an unrecognised `kind` is
  /// already modelled as [UnknownEasing] and rides through, so anything
  /// reaching the null here is structurally wrong JSON, and silently retiming a
  /// segment is the one repair that renders plausibly and is therefore never
  /// noticed.
  static Easing? _tryEasing(Map<String, Object?> m) {
    if (!m.containsKey('easing')) return const LinearEasing();
    final e = m['easing'];
    if (e is! Map<String, Object?>) return null;
    return Easing.fromJson(e);
  }

  /// Builds a typed track, or null if **any** key is unreadable.
  ///
  /// All-or-nothing per track, never per key: dropping the unreadable key would
  /// leave a track that samples plausibly and has silently lost timing the user
  /// authored, and [TrackSet] can only preserve what it was handed whole.
  static Track? _typed<T>(
    List<Object?> raw,
    T? Function(Object? v) value,
    Track Function(List<Keyframe<T>> keys) build,
  ) {
    final keys = <Keyframe<T>>[];
    for (final e in raw) {
      // `_wellFormedKeys` already proved every entry is a map with a legal `t`.
      final m = e! as Map<String, Object?>;
      final v = value(m['value']);
      final easing = _tryEasing(m);
      if (v == null || easing == null) return null;
      keys.add(Keyframe<T>(t: d(m['t']), value: v, easing: easing));
    }
    return build(keys);
  }

  static Track? _vec2Track(List<Object?> raw, Map<String, Object?> unknown) {
    final keys = <Vec2Keyframe>[];
    for (final e in raw) {
      final m = e! as Map<String, Object?>;
      final v = Vec2.tryFromJson(m['value']);
      final easing = _tryEasing(m);
      if (v == null || easing == null) return null;
      final into =
          m.containsKey('inTangent') ? Vec2.tryFromJson(m['inTangent']) : null;
      final out = m.containsKey('outTangent')
          ? Vec2.tryFromJson(m['outTangent'])
          : null;
      // A tangent key that is present and unreadable is not "no tangent" —
      // straightening an authored arc is a silent geometry change.
      if (m.containsKey('inTangent') && into == null) return null;
      if (m.containsKey('outTangent') && out == null) return null;
      keys.add(Vec2Keyframe(
        t: d(m['t']),
        value: v,
        easing: easing,
        inTangent: into,
        outTangent: out,
      ));
    }
    return Vec2Track(keys, unknown);
  }
}

sealed class TypedTrack<T> extends Track {
  const TypedTrack._(this.keys, this.wireType, this.unknownKeys);

  final List<Keyframe<T>> keys;

  /// `scalar` | `vec2` | `color` | `bool` | `path` (docs/v3/02 §3.10).
  final String wireType;

  /// Track-level forward-compat passthrough (docs/v3/02 §7).
  ///
  /// `pins` — the reserved key for a path track's pinned endpoints (F7.3, M6) —
  /// is the one key the format declares at this level today, and dropping it
  /// would be exactly the loss rule 6 exists to prevent: a build that authors
  /// pins writes them, a stale tab running this build opens the document,
  /// scrubs, drags one anchor, and autosaves them away for good.
  ///
  /// Carried through [withKeys] rather than reset by it, because every op goes
  /// that way — an op that rebuilds a track's keys has not been told anything
  /// about a key it cannot read.
  final Map<String, Object?> unknownKeys;

  T interpolateKeys(Keyframe<T> k0, Keyframe<T> k1, double u);

  /// The same track with a different key list, **preserving the runtime type**.
  ///
  /// Covariantly overridden by every subclass, which is what lets `TrackOps`
  /// hand a `PathTrack` back to a caller that gave it a `PathTrack` without a
  /// `as` and without a five-arm switch at every mutation site. The returned
  /// keys go through [_validated], so an op cannot smuggle a coincident pair
  /// past T2 — enforcement stays at mutation, never in the sampler.
  TypedTrack<T> withKeys(List<Keyframe<T>> keys);

  @override
  int get keyCount => keys.length;

  @override
  double get firstT => keys.first.t;

  @override
  double get lastT => keys.last.t;

  @override
  List<double> get keyTimes =>
      List<double>.unmodifiable(<double>[for (final k in keys) k.t]);

  @override
  Object? sampleDynamic(double t) => sampleAt(t);

  /// TOTAL. Never throws, never divides by zero, never returns NaN.
  ///
  /// This is the ONE sampler; every track type shares it. HOLD LAST is the
  /// explicit fix for "the shape disappears at 100%": legacy wrapped
  /// interpolation in `if (frames.length > preFrameNo + 1)`, so past the last
  /// keyframe the body never ran and the section rendered as nothing.
  T sampleAt(double t) {
    final (k0, k1, u) = bracket(t);
    return identical(k0, k1) ? k0.value : interpolateKeys(k0, k1, u);
  }

  /// The bracketing pair and the **eased** segment-local `u`, per doc 01 §9.
  ///
  /// Split out of [sampleAt] rather than duplicated because `resolvePose` needs
  /// the two *keyframes*, not a value: a path key's value is a pose map that the
  /// node's topology must drive the read of. Two bracketing routines is two
  /// places for hold-last to be wrong in, and only one of them would be covered
  /// by the scalar tests.
  ///
  /// Outside the key range, and for a single-key track, both halves of the pair
  /// are the **same object** — [sampleAt] tests that with `identical`, which is
  /// what keeps [PathTrack]'s unreachable `interpolateKeys` unreachable.
  (Keyframe<T>, Keyframe<T>, double) bracket(double t) {
    if (keys.length == 1 || t <= keys.first.t) {
      return (keys.first, keys.first, 0.0);
    }
    if (t >= keys.last.t) return (keys.last, keys.last, 0.0);
    final i = _lowerBound(keys, t);
    final k0 = keys[i];
    final k1 = keys[i + 1];
    final span = k1.t - k0.t;
    // T2 makes this unreachable, but the guard is what makes the divide below
    // provably safe rather than merely likely — legacy's NaN coordinates came
    // from exactly this subtraction.
    if (span <= 1e-9) return (k1, k1, 0.0);
    return (k0, k1, applyEasing(k0.easing, (t - k0.t) / span));
  }

  @override
  Map<String, Object?> toJson() => withUnknown(unknownKeys, <String, Object?>{
        'type': wireType,
        'keys': keys.map((k) => k.toJson()).toList(growable: false),
      });
}

/// The last index whose `t` is `<= t`.
///
/// Called only from the bracketed middle of [TypedTrack.sampleAt], where
/// `keys.first.t < t < keys.last.t`, so the result is always a valid left key
/// and `i + 1` is always in range. One list, one lookup — there is no parallel
/// sorted position array in v3 to desync from it (invariant T4).
int _lowerBound<T>(List<Keyframe<T>> keys, double t) {
  var lo = 0;
  var hi = keys.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (keys[mid].t <= t) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// T1 (non-empty), T2 (`t` strictly increasing), T3 (`t` in `[0,1]`).
///
/// T6 is the deliberate omission: the first key is **not** pinned to 0 and the
/// last is **not** pinned to 1. Hold-first/hold-last makes pinning unnecessary,
/// and pinning would corrupt a track that legitimately starts at `t = 0.3`.
List<Keyframe<T>> _validated<T>(List<Keyframe<T>> keys) {
  if (keys.isEmpty) {
    throw ArgumentError.value(keys, 'keys', 'a track needs at least one key');
  }
  for (var n = 0; n < keys.length; n++) {
    final t = keys[n].t;
    if (t.isNaN || t < 0.0 || t > 1.0) {
      throw ArgumentError.value(t, 'keys[$n].t', 'must lie in [0,1]');
    }
    if (n > 0 && t <= keys[n - 1].t) {
      throw ArgumentError.value(t, 'keys[$n].t',
          'must be strictly greater than keys[${n - 1}].t (${keys[n - 1].t})');
    }
  }
  return List.unmodifiable(keys);
}

final class ScalarTrack extends TypedTrack<double> {
  ScalarTrack(List<Keyframe<double>> keys,
      [Map<String, Object?> unknownKeys = const <String, Object?>{}])
      : super._(_validated(keys), 'scalar', unknownKeys);

  @override
  double interpolateKeys(Keyframe<double> k0, Keyframe<double> k1, double u) =>
      k0.value + (k1.value - k0.value) * u;

  @override
  ScalarTrack withKeys(List<Keyframe<double>> keys) =>
      ScalarTrack(keys, unknownKeys);
}

final class Vec2Track extends TypedTrack<Vec2> {
  /// Takes `Keyframe<Vec2>`, not `Vec2Keyframe`: a `List<Vec2Keyframe>` is
  /// already a subtype so every existing call site is unaffected, while an op
  /// that rebuilds the track through [withKeys] is not forced to invent spatial
  /// tangents for keys that never had any.
  Vec2Track(List<Keyframe<Vec2>> keys,
      [Map<String, Object?> unknownKeys = const <String, Object?>{}])
      : super._(_validated(keys), 'vec2', unknownKeys);

  /// Spatial tangents are read through `is`, never `k0 as Vec2Keyframe` — the
  /// blind cast is one of the recurring frame-enders named in docs/v3/08 §4,
  /// and a plain `Keyframe<Vec2>` reaching here (from a future op, or a test)
  /// must degrade to the straight-line fast path rather than throw.
  @override
  Vec2 interpolateKeys(Keyframe<Vec2> k0, Keyframe<Vec2> k1, double u) {
    final out = k0 is Vec2Keyframe ? k0.outTangent : null;
    final into = k1 is Vec2Keyframe ? k1.inTangent : null;
    if (out == null && into == null) return Vec2.lerp(k0.value, k1.value, u);

    final p0 = k0.value;
    final p1 = p0 + (out ?? Vec2.zero);
    final p3 = k1.value;
    final p2 = p3 + (into ?? Vec2.zero);
    return _cubicAt(p0, p1, p2, p3, u);
  }

  @override
  Vec2Track withKeys(List<Keyframe<Vec2>> keys) => Vec2Track(keys, unknownKeys);
}

Vec2 _cubicAt(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final v = 1.0 - u;
  final a = v * v * v;
  final b = 3.0 * v * v * u;
  final c = 3.0 * v * u * u;
  final e = u * u * u;
  return Vec2(
    a * p0.x + b * p1.x + c * p2.x + e * p3.x,
    a * p0.y + b * p1.y + c * p2.y + e * p3.y,
  );
}

final class ColorTrack extends TypedTrack<Rgba> {
  ColorTrack(List<Keyframe<Rgba>> keys,
      [Map<String, Object?> unknownKeys = const <String, Object?>{}])
      : super._(_validated(keys), 'color', unknownKeys);

  @override
  Rgba interpolateKeys(Keyframe<Rgba> k0, Keyframe<Rgba> k1, double u) =>
      Rgba.lerp(k0.value, k1.value, u);

  @override
  ColorTrack withKeys(List<Keyframe<Rgba>> keys) =>
      ColorTrack(keys, unknownKeys);
}

/// Always stepped: the FROM key's value holds for the whole segment.
final class BoolTrack extends TypedTrack<bool> {
  BoolTrack(List<Keyframe<bool>> keys,
      [Map<String, Object?> unknownKeys = const <String, Object?>{}])
      : super._(_validated(keys), 'bool', unknownKeys);

  @override
  bool interpolateKeys(Keyframe<bool> k0, Keyframe<bool> k1, double u) =>
      k0.value;

  @override
  BoolTrack withKeys(List<Keyframe<bool>> keys) => BoolTrack(keys, unknownKeys);
}

final class PathTrack extends TypedTrack<PathPose> {
  PathTrack(List<Keyframe<PathPose>> keys,
      [Map<String, Object?> unknownKeys = const <String, Object?>{}])
      : super._(_validated(keys), 'path', unknownKeys);

  /// Returns **null**, and that is the fix, not a stub (docs/v3/08 §1).
  ///
  /// A path track is sampled through `SceneEvaluator.resolvePose`, which needs
  /// the node's topology to drive the loop. Without this override a generic
  /// `byKey` loop over a `TrackSet` would call [sampleAt], reach
  /// [interpolateKeys]' `StateError`, and blank the entire canvas on the first
  /// path-animated node.
  @override
  Object? sampleDynamic(double t) => null;

  /// Unreachable by construction — deliberately **not** wrapped in a guard.
  ///
  /// Wrapping it would convert "the evaluator called the wrong entry point"
  /// into a silently frozen shape, which is precisely the class of defect
  /// docs/v3/08 §1 exists to prevent. [sampleDynamic] and [resolvePose] are the
  /// only two doors, and neither leads here.
  @override
  PathPose interpolateKeys(
          Keyframe<PathPose> k0, Keyframe<PathPose> k1, double u) =>
      throw StateError('PathTrack is sampled through resolvePose');

  @override
  PathTrack withKeys(List<Keyframe<PathPose>> keys) =>
      PathTrack(keys, unknownKeys);
}

/// The closed set of animatable channels.
///
/// An enum, not a string path, so switches are exhaustive and typos are compile
/// errors. Persisted **by name** so v2 can add members; unknown names are
/// preserved-not-evaluated on decode.
///
/// **Fifteen members, not sixteen.** docs/v3/03 AC-6.1.3 says "16-member" and
/// docs/v3/02 §3.9 lists `pivot` in the `vec2` row. Both are the bug: doc 01 §4
/// (authoritative) states that row is wrong and that `pivot` is **not**
/// animatable in v1, because `pivot` appears twice with opposite sign in
/// `Transform2.toAffine()`, so keying it while `scale != 1` *translates* the
/// node — a ball animated from centre- to bottom-pivot at the impact frame
/// visibly jumps. Do not "fix" this by adding `pivot`. The wire *type* stays
/// `vec2` so enabling it later is additive.
enum PropKey {
  position,
  scale,
  rotation,
  skewX,
  opacity,
  visible,
  path,
  fillColor,
  fillOpacity,
  strokeColor,
  strokeOpacity,
  strokeWidth,
  trimStart,
  trimEnd,
  trimOffset,
}

/// Addresses ONE channel on ONE node.
///
/// `subjectId` is null in v1 for everything except paint channels: `fillColor`
/// alone cannot say *which* fill. Wire form: `"rotation"` | `"fillColor:p-body"`.
final class PropertyKey {
  const PropertyKey(this.prop, [this.subjectId]);

  final PropKey prop;

  /// `PaintId` | `StopId` | null.
  final String? subjectId;

  String get wire => subjectId == null ? prop.name : '${prop.name}:$subjectId';

  /// Null for a property name this build does not know — the caller preserves
  /// the raw entry rather than dropping it.
  static PropertyKey? tryParse(String wire) {
    final split = wire.indexOf(':');
    final name = split < 0 ? wire : wire.substring(0, split);
    final subject = split < 0 ? null : wire.substring(split + 1);
    final prop = PropKey.values.asNameMap()[name];
    if (prop == null) return null;
    return PropertyKey(prop, subject);
  }

  @override
  bool operator ==(Object other) =>
      other is PropertyKey &&
      other.prop == prop &&
      other.subjectId == subjectId;

  @override
  int get hashCode => Object.hash(prop, subjectId);

  @override
  String toString() => 'PropertyKey($wire)';
}

/// ONE table. Used by the decoder and the mutation API. **Nowhere else casts.**
const Map<PropKey, Type> kExpectedTrackType = <PropKey, Type>{
  PropKey.position: Vec2Track,
  PropKey.scale: Vec2Track,
  PropKey.rotation: ScalarTrack,
  PropKey.skewX: ScalarTrack,
  PropKey.opacity: ScalarTrack,
  PropKey.visible: BoolTrack,
  PropKey.path: PathTrack,
  PropKey.fillColor: ColorTrack,
  PropKey.strokeColor: ColorTrack,
  PropKey.fillOpacity: ScalarTrack,
  PropKey.strokeOpacity: ScalarTrack,
  PropKey.strokeWidth: ScalarTrack,
  PropKey.trimStart: ScalarTrack,
  PropKey.trimEnd: ScalarTrack,
  PropKey.trimOffset: ScalarTrack,
};

final class TrackSet {
  const TrackSet(this.byKey, {this.unknownKeys = const {}});

  final Map<PropertyKey, Track> byKey;

  /// Unknown property names, unknown track types, and tracks whose type does
  /// not match [kExpectedTrackType]: preserved, never evaluated, re-emitted
  /// verbatim on save (docs/v3/02 §7).
  final Map<String, Object?> unknownKeys;

  static const empty = TrackSet(<PropertyKey, Track>{});

  bool get isEmpty => byKey.isEmpty && unknownKeys.isEmpty;

  // Typed accessors. They return null on type mismatch — never throw, never
  // blind-cast. A malformed stored document must not crash the paint loop, and
  // the evaluator's fallback for a missing track is already defined: the node's
  // pose value.
  ScalarTrack? scalar(PropKey p, [String? s]) => _as<ScalarTrack>(p, s);
  Vec2Track? vec2(PropKey p, [String? s]) => _as<Vec2Track>(p, s);
  ColorTrack? color(PropKey p, [String? s]) => _as<ColorTrack>(p, s);
  BoolTrack? boolean(PropKey p, [String? s]) => _as<BoolTrack>(p, s);
  PathTrack? pathTrack() => _as<PathTrack>(PropKey.path, null);

  X? _as<X extends Track>(PropKey p, String? s) {
    final t = byKey[PropertyKey(p, s)];
    return t is X ? t : null;
  }

  /// Total below this point: every entry either becomes a typed [Track] or is
  /// preserved raw in [unknownKeys]. [path] is used only to locate a `tracks`
  /// value that is not an object at all — see [DocumentException].
  factory TrackSet.fromJson(Object? j, [String path = '']) {
    final m = reqObject(j, path);
    final byKey = <PropertyKey, Track>{};
    final unknown = <String, Object?>{};

    for (final entry in m.entries) {
      final key = PropertyKey.tryParse(entry.key);
      final track = key == null ? null : Track.fromJson(entry.value);
      // T5: the decoder is one of the two places the property→track-type table
      // is consulted. A `rotation` holding a `vec2` track is not coerced and
      // not dropped; it rides through untouched so the client that understands
      // it still can.
      if (key == null ||
          track == null ||
          track.runtimeType != kExpectedTrackType[key.prop]) {
        unknown[entry.key] = entry.value;
        continue;
      }
      byKey[key] = track;
    }

    return TrackSet(Map.unmodifiable(byKey),
        unknownKeys: Map.unmodifiable(unknown));
  }

  Map<String, Object?> toJson() => withUnknown(unknownKeys, <String, Object?>{
        for (final e in byKey.entries) e.key.wire: e.value.toJson(),
      });

  @override
  String toString() => 'TrackSet(${byKey.length} tracks)';
}
