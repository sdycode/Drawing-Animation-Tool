/// Document-level keyframe routing (docs/v3/01 §12; docs/v3/03 F6.1, F6.2, F7.1).
///
/// The **one sanctioned `Document → Document` route** the timeline command layer
/// wraps to key an arbitrary property on a node, and to move / delete / re-ease
/// an existing key by index. [TrackOps] enforces the track invariants
/// (T1–T3); this file resolves the `(node, property)` address to the right
/// track — creating the `Animation`, `TrackSet` and `Track` when they are
/// absent, with the runtime track type dictated by [kExpectedTrackType] — and
/// delegates the actual key edit to [TrackOps].
///
/// ## Which animation
///
/// Like `PathOps`, these ops target the document's **default animation**,
/// creating it if the document has none (v1 has exactly one animation and the
/// UI hides the concept — docs/v3/01 §10). The `(AnimationId, NodeId,
/// PropertyKey)` addressing of docs/v3/01 §12 is satisfied by
/// `defaultAnimationId`; an explicit-animation overload is additive when the
/// state machine lands and is deliberately not built now.
///
/// ## The path seam
///
/// [keyAt] **refuses** `PropKey.path`: a path keyframe's value is a [PathPose]
/// that must pose exactly the node's topology `AnchorId` set, and
/// `PathOps.moveAnchor` / `PathOps.setTangents` (with `atT:`) already own that
/// transaction — they seed `t = 0` with the rest pose, backfill every keyframe
/// to the topology, and null the recipe. Routing a raw [PathPose] through
/// [keyAt] would bypass that backfill and could plant the mismatched anchor set
/// v3 exists to make unrepresentable (P5, AC-4.3.6). The **time / easing / index**
/// ops ([moveKey], [removeKey], [setKeyEasing]) do work on a path track: they
/// touch `t`, easing and key count, never a pose, so the topology invariant is
/// untouched.
///
/// No editor concepts reach here — no `EditorState`, no selection, no playhead.
/// Ops throw [ArgumentError] loudly; the command layer catches (docs/v3/08 §1).
library;

import '../animation.dart';
import '../document.dart';
import '../easing.dart';
import '../primitives.dart';
import '../track.dart';
import '../uuid.dart';
import 'track_ops.dart';

abstract final class KeyframeOps {
  /// Upsert a keyframe at [t] on `(node, property)` holding [value] — the
  /// timeline's **K** action (AC-6.1.1, AC-6.2.7).
  ///
  /// The caller samples the node's evaluated value at the playhead and passes it
  /// in; this op does not evaluate. The track is created with the type
  /// [kExpectedTrackType] dictates for [property] when absent, and the value's
  /// runtime type **must** match that track type — a mismatch throws
  /// [ArgumentError] rather than being coerced (AC-6.1.3). Keying at a `t` where
  /// a key already exists **replaces** it (AC-6.2.7, via [TrackOps.upsertKeyframe])
  /// and the displaced key's easing rides across, so re-keying a value never
  /// silently straightens the segment leaving `t` (docs/v3/01 §1 rule 1).
  ///
  /// Scalar channels accept any `num` (an `int` from a Firestore round-trip is
  /// widened, matching the decoder's `d`); every other channel demands its exact
  /// value type.
  ///
  /// Throws [ArgumentError] for an unknown [node], a `PropKey.path` [property]
  /// (see the library doc — path keyframes route through `PathOps`), a [value]
  /// whose type does not match the track, or a [t] outside `[0,1]`.
  static Document keyAt(
      Document d, NodeId node, PropertyKey property, double t, Object? value) {
    if (d.nodeIndex[node] == null) {
      throw ArgumentError.value(node.v, 'node', 'no such node');
    }
    if (property.prop == PropKey.path) {
      throw ArgumentError.value(
          property.wire,
          'property',
          'path keyframes are authored through PathOps.moveAnchor / '
              'PathOps.setTangents (atT:), which pose the node topology and '
              'backfill every keyframe; keyAt does not write PathPose values');
    }
    if (t.isNaN || t < 0.0 || t > 1.0) {
      throw ArgumentError.value(t, 't', 'must lie in [0,1]');
    }

    var doc = d;
    var animation = doc.defaultAnimation;
    if (animation == null) {
      animation = Animation(id: AnimationId(uuidV4()), name: 'Main');
      doc = doc.copyWith(
        animations: <Animation>[...doc.animations, animation],
        defaultAnimationId: animation.id,
      );
    }

    final tracks = animation.tracksFor(node);
    final next = _upsertValue(property, tracks.byKey[property], t, value);
    return _writeTrack(doc, animation, node, tracks, property, next);
  }

  /// Move key [index] of `(node, property)` to [newT] (AC-6.2.1), delegating to
  /// [TrackOps.moveKeyframe] — value and easing preserved, a collision within
  /// [TrackOps.minSeparation] rejected, [newT] clamped to `[0,1]`.
  ///
  /// Throws [ArgumentError] for an unknown [node], a missing track, an [index]
  /// out of range, or a collision.
  static Document moveKey(Document d, NodeId node, PropertyKey property,
          int index, double newT) =>
      _replaceTrack(d, node, property, (t) => _moved(t, index, newT));

  /// Set the easing on the segment leaving key [index] of `(node, property)`
  /// (AC-7.1.1), delegating to [TrackOps.setEasing].
  ///
  /// Throws [ArgumentError] for an unknown [node], a missing track, or an
  /// [index] out of range.
  static Document setKeyEasing(Document d, NodeId node, PropertyKey property,
          int index, Easing easing) =>
      _replaceTrack(d, node, property, (t) => _eased(t, index, easing));

  /// Remove key [index] of `(node, property)`.
  ///
  /// Removing the track's **last** key removes the whole track from the node's
  /// `TrackSet` — the document-level answer to [TrackOps.removeKeyframeAt]'s
  /// boundary (a zero-key track is unrepresentable under T1). If that empties
  /// the node's `TrackSet` (no tracks and no preserved unknown keys), the node's
  /// entry is dropped from `Animation.tracks` too: a node with no tracks is
  /// fully static, and an empty `TrackSet` left behind is dead weight every save
  /// carries. The **`Animation` itself is kept** even when it ends up with no
  /// tracks — the v1 invariant is exactly one animation referenced by
  /// `defaultAnimationId` (docs/v3/01 §11), an empty animation is the legal
  /// "everything static" state (it is what `Document.create` produces), and
  /// deleting it would orphan `defaultAnimationId`.
  ///
  /// Throws [ArgumentError] for an unknown [node], a missing track, or an
  /// [index] out of range.
  static Document removeKey(
      Document d, NodeId node, PropertyKey property, int index) {
    final (animation, tracks, track) = _locate(d, node, property);
    if (index < 0 || index >= track.keyCount) {
      throw ArgumentError.value(
          index, 'index', 'out of range for a ${track.keyCount}-key track');
    }

    if (track.keyCount > 1) {
      return _writeTrack(
          d, animation, node, tracks, property, _removed(track, index));
    }

    // Last key: drop the whole track, and the node entry if it empties.
    final keptByKey = <PropertyKey, Track>{
      for (final e in tracks.byKey.entries)
        if (e.key != property) e.key: e.value,
    };
    final nextTracks = <NodeId, TrackSet>{...animation.tracks};
    if (keptByKey.isEmpty && tracks.unknownKeys.isEmpty) {
      nextTracks.remove(node);
    } else {
      nextTracks[node] = TrackSet(Map.unmodifiable(keptByKey),
          unknownKeys: tracks.unknownKeys);
    }
    return _commit(d, animation.copyWith(tracks: Map.unmodifiable(nextTracks)));
  }

  /// The key times of `(node, property)`, in order, as a **pure read** for the
  /// timeline (AC-6.2.5) — empty when the node has no such track. Resolves the
  /// default animation so the caller does not have to; from here the widget
  /// reads [Track.keyTimes] / the typed track's `keys` directly. No state is
  /// invented: this is a projection of the one key list.
  static List<double> keyTimes(Document d, NodeId node, PropertyKey property) {
    final animation = d.defaultAnimation;
    if (animation == null) return const <double>[];
    return animation.tracksFor(node).byKey[property]?.keyTimes ??
        const <double>[];
  }
}

/// Build (or upsert into) the typed track for [property], validating [value]'s
/// runtime type against [kExpectedTrackType] (AC-6.1.3).
///
/// The displaced key's easing rides across via [TrackOps.easingAt], which
/// returns linear when nothing is displaced — so a fresh key is linear (the
/// model identity) and a replace keeps the segment's authored curve.
Track _upsertValue(
    PropertyKey property, Track? existing, double t, Object? value) {
  switch (property.prop) {
    case PropKey.position:
    case PropKey.scale:
      final cur = existing is Vec2Track ? existing : null;
      final key = Keyframe<Vec2>(
          t: t,
          value: _vec2(value, property),
          easing:
              cur == null ? const LinearEasing() : TrackOps.easingAt(cur, t));
      return cur == null
          ? Vec2Track(<Keyframe<Vec2>>[key])
          : TrackOps.upsertKeyframe(cur, key);

    case PropKey.rotation:
    case PropKey.skewX:
    case PropKey.opacity:
    case PropKey.fillOpacity:
    case PropKey.strokeOpacity:
    case PropKey.strokeWidth:
    case PropKey.trimStart:
    case PropKey.trimEnd:
    case PropKey.trimOffset:
      final cur = existing is ScalarTrack ? existing : null;
      final key = Keyframe<double>(
          t: t,
          value: _scalar(value, property),
          easing:
              cur == null ? const LinearEasing() : TrackOps.easingAt(cur, t));
      return cur == null
          ? ScalarTrack(<Keyframe<double>>[key])
          : TrackOps.upsertKeyframe(cur, key);

    case PropKey.visible:
      final cur = existing is BoolTrack ? existing : null;
      final key = Keyframe<bool>(
          t: t,
          value: _boolean(value, property),
          easing:
              cur == null ? const LinearEasing() : TrackOps.easingAt(cur, t));
      return cur == null
          ? BoolTrack(<Keyframe<bool>>[key])
          : TrackOps.upsertKeyframe(cur, key);

    case PropKey.fillColor:
    case PropKey.strokeColor:
      final cur = existing is ColorTrack ? existing : null;
      final key = Keyframe<Rgba>(
          t: t,
          value: _rgba(value, property),
          easing:
              cur == null ? const LinearEasing() : TrackOps.easingAt(cur, t));
      return cur == null
          ? ColorTrack(<Keyframe<Rgba>>[key])
          : TrackOps.upsertKeyframe(cur, key);

    case PropKey.path:
      // Unreachable: keyAt refuses path before it gets here.
      throw ArgumentError.value(property.wire, 'property',
          'path keyframes route through PathOps, not keyAt');
  }
}

Vec2 _vec2(Object? value, PropertyKey p) =>
    value is Vec2 ? value : throw _mismatch(p, 'Vec2', value);

double _scalar(Object? value, PropertyKey p) =>
    value is num ? value.toDouble() : throw _mismatch(p, 'num', value);

bool _boolean(Object? value, PropertyKey p) =>
    value is bool ? value : throw _mismatch(p, 'bool', value);

Rgba _rgba(Object? value, PropertyKey p) =>
    value is Rgba ? value : throw _mismatch(p, 'Rgba', value);

ArgumentError _mismatch(PropertyKey p, String want, Object? got) =>
    ArgumentError.value('${got.runtimeType}', 'value',
        'property "${p.wire}" expects a $want value, not this (AC-6.1.3)');

/// Locate the `(default animation, node's TrackSet, track for property)` triple,
/// throwing [ArgumentError] if the node is unknown or the track is absent.
(Animation, TrackSet, Track) _locate(
    Document d, NodeId node, PropertyKey property) {
  if (d.nodeIndex[node] == null) {
    throw ArgumentError.value(node.v, 'node', 'no such node');
  }
  final animation = d.defaultAnimation;
  final tracks = animation?.tracksFor(node) ?? TrackSet.empty;
  final track = tracks.byKey[property];
  if (animation == null || track == null) {
    throw ArgumentError.value(
        property.wire, 'property', 'no such track on node "${node.v}"');
  }
  return (animation, tracks, track);
}

Document _replaceTrack(
    Document d, NodeId node, PropertyKey property, Track Function(Track) edit) {
  final (animation, tracks, track) = _locate(d, node, property);
  return _writeTrack(d, animation, node, tracks, property, edit(track));
}

/// Write [next] back under [property], mirroring `PathOps`' write path.
Document _writeTrack(Document d, Animation animation, NodeId node,
    TrackSet tracks, PropertyKey property, Track next) {
  final updated = animation.copyWith(
    tracks: Map.unmodifiable(<NodeId, TrackSet>{
      ...animation.tracks,
      node: TrackSet(
        Map.unmodifiable(<PropertyKey, Track>{...tracks.byKey, property: next}),
        unknownKeys: tracks.unknownKeys,
      ),
    }),
  );
  return _commit(d, updated);
}

Document _commit(Document d, Animation updated) => d.copyWith(
      animations: <Animation>[
        for (final a in d.animations)
          if (a.id == updated.id) updated else a,
      ],
    );

// The `Track → Track` delegations. The switch is exhaustive over the sealed
// `Track` hierarchy, so each arm infers the concrete type the generic
// `TrackOps` op needs — there is no blind `as` (docs/v3/08 §4).

Track _moved(Track track, int index, double newT) => switch (track) {
      final ScalarTrack t => TrackOps.moveKeyframe(t, index, newT),
      final Vec2Track t => TrackOps.moveKeyframe(t, index, newT),
      final ColorTrack t => TrackOps.moveKeyframe(t, index, newT),
      final BoolTrack t => TrackOps.moveKeyframe(t, index, newT),
      final PathTrack t => TrackOps.moveKeyframe(t, index, newT),
    };

Track _eased(Track track, int index, Easing easing) => switch (track) {
      final ScalarTrack t => TrackOps.setEasing(t, index, easing),
      final Vec2Track t => TrackOps.setEasing(t, index, easing),
      final ColorTrack t => TrackOps.setEasing(t, index, easing),
      final BoolTrack t => TrackOps.setEasing(t, index, easing),
      final PathTrack t => TrackOps.setEasing(t, index, easing),
    };

Track _removed(Track track, int index) => switch (track) {
      final ScalarTrack t => TrackOps.removeKeyframeAt(t, index),
      final Vec2Track t => TrackOps.removeKeyframeAt(t, index),
      final ColorTrack t => TrackOps.removeKeyframeAt(t, index),
      final BoolTrack t => TrackOps.removeKeyframeAt(t, index),
      final PathTrack t => TrackOps.removeKeyframeAt(t, index),
    };
