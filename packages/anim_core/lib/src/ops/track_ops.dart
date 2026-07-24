/// Track-level keyframe mutations (docs/v3/01 §12; docs/v3/03 F6.2, F7.1).
///
/// Every method here is `TypedTrack<T> → TypedTrack<T>`: pure, total, and the
/// place the track invariants (T1–T3) are enforced. The **document-level**
/// routes the timeline command layer actually wraps — "key this property on
/// this node", "move key N of (node, property)" — live in `keyframe_ops.dart`
/// and delegate here, because an op is where an invariant is enforced and a
/// `moveKeyframe` that forwarded to a rebuild without the `minSeparation`
/// rejection would ship coincident keys the sampler is then expected to paper
/// over. It never will, because the enforcement lives here (docs/v3/08 §1: ops
/// throw loudly, the command layer catches).
///
/// Ops are the only route to a `Document` change. No model object is mutable
/// and the UI never edits one; it issues a command that returns a new
/// `Document`. Legacy mutated the document from inside `itemBuilder`, so merely
/// rendering the timeline edited the user's file.
library;

import '../easing.dart';
import '../track.dart';

abstract final class TrackOps {
  /// Two keys closer than this in `t` are the same key.
  ///
  /// Coincident keys are impossible **by construction** (AC-6.2.7), enforced at
  /// mutation and never patched in the sampler. `TypedTrack.bracket`'s
  /// `span <= 1e-9` guard is a proof aid, not a repair: it makes the divide
  /// provably safe, and this constant is what makes it unreachable.
  static const double minSeparation = 1e-4;

  /// Insert or **replace** at [t].
  ///
  /// Every existing key within [minSeparation] of [t] is dropped and the new
  /// key takes its place, so an exact `t` match is a replace, a near miss is a
  /// replace, and the result is strictly increasing with every neighbour more
  /// than [minSeparation] away. There is no branch that can produce a second
  /// key at one `t` (AC-6.2.7).
  ///
  /// The return type is the caller's concrete track type, reached through
  /// [TypedTrack.withKeys]' covariant override rather than a cast — a blind
  /// `as` on a track is one of the recurring frame-enders named in
  /// docs/v3/08 §4. The `is` test below can only fail if a future subclass
  /// breaks that override, and failing loudly at the mutation boundary is
  /// exactly where that belongs.
  ///
  /// Throws [ArgumentError] when [t] is outside `[0,1]` or is NaN — T3 is a
  /// model invariant and a caller that violates it has a bug, not a document
  /// with bad data.
  static X upsertKeyframe<X extends TypedTrack<T>, T>(
      X track, Keyframe<T> key) {
    final t = key.t;
    if (t.isNaN || t < 0.0 || t > 1.0) {
      throw ArgumentError.value(t, 'key.t', 'must lie in [0,1]');
    }

    final keys = <Keyframe<T>>[];
    var inserted = false;
    for (final k in track.keys) {
      if ((k.t - t).abs() <= minSeparation) continue;
      if (!inserted && k.t > t) {
        keys.add(key);
        inserted = true;
      }
      keys.add(k);
    }
    if (!inserted) keys.add(key);

    final next = track.withKeys(keys);
    if (next is X) return next;
    throw StateError(
        '${track.runtimeType}.withKeys did not preserve its runtime type');
  }

  /// The easing of the key [upsertKeyframe] would **displace** at [t], or
  /// linear when it would displace none.
  ///
  /// A *value* edit at an existing key is keyframe-local (docs/v3/01 §1,
  /// governing rule 1) and easing is not part of a value: re-authoring a pose
  /// at `t` must not retime the segment leaving `t`. `Keyframe`'s easing
  /// defaults to linear — correctly, since a non-identity model default curves
  /// every programmatic key — so a caller building the replacement key has to
  /// carry the displaced easing across deliberately, and it must decide "which
  /// key is displaced" by the *same* [minSeparation] rule the upsert uses.
  /// That is why this lives here and not at the call site: two copies of the
  /// rule is one place for the pose edit and the timeline to disagree about
  /// which key they are touching.
  static Easing easingAt<T>(TypedTrack<T> track, double t) {
    for (final k in track.keys) {
      if ((k.t - t).abs() <= minSeparation) return k.easing;
    }
    return const LinearEasing();
  }

  /// Move the key at [index] to [newT], keeping its value and easing (AC-6.2.1).
  ///
  /// ## The index-after-cross contract
  ///
  /// [index] addresses the key in the track **handed in** — resolved once, at
  /// command construction, never re-derived from a float mid-drag (AC-6.2.1).
  /// The op grabs *that* key, gives it [newT], and returns a **freshly sorted**
  /// track. When the drag carries a key past a neighbour the list re-sorts and
  /// T2 still holds, but the grabbed key now sits at a *different* index: the
  /// key you grabbed keeps its value and easing and ends up wherever [newT] puts
  /// it in order. A caller that keeps dragging re-derives the index from the
  /// returned track (it is one op per committed move, so there is no live index
  /// to invalidate) — the value it dragged is at [newT], which is all it needs
  /// to find it again.
  ///
  /// ## Rejection, not an ε-nudge
  ///
  /// A [newT] landing within [minSeparation] of **another** key is **rejected**
  /// with [ArgumentError] (AC-6.2.2). Rejecting matches [upsertKeyframe]'s
  /// "coincident keys are impossible by construction" and, unlike an ε-nudge,
  /// never silently plants the key somewhere the user did not drag it. The
  /// grabbed key is excluded from the check — a zero-distance move onto its own
  /// position is a no-op, not a self-collision.
  ///
  /// [newT] is **clamped** to `[0,1]` (T3): a drag past either end pins to the
  /// end rather than throwing, the same choice paint widths make for a field
  /// that accepts out-of-range keystrokes. A NaN [newT] is not out of range, it
  /// is a non-value, and throws — as [upsertKeyframe] rejects a NaN `t`.
  ///
  /// Throws [ArgumentError] for an [index] out of range, a NaN [newT], or a
  /// collision.
  ///
  /// The return type is `TypedTrack<T>` but the **runtime** type is the caller's
  /// concrete track: [TypedTrack.withKeys] is covariantly overridden, so a
  /// `ScalarTrack` in is a `ScalarTrack` out. `T` is inferred from the track
  /// argument rather than from a separate `X` bound, which is what keeps that
  /// inference from collapsing to `dynamic` when there is no key argument to pin
  /// it (as [upsertKeyframe] has).
  static TypedTrack<T> moveKeyframe<T>(
      TypedTrack<T> track, int index, double newT) {
    final keys = track.keys;
    _checkIndex(index, keys.length);
    if (newT.isNaN) {
      throw ArgumentError.value(newT, 'newT', 'must be a number');
    }
    final t = newT < 0.0 ? 0.0 : (newT > 1.0 ? 1.0 : newT);

    for (var n = 0; n < keys.length; n++) {
      if (n == index) continue;
      if ((keys[n].t - t).abs() <= minSeparation) {
        throw ArgumentError.value(
            newT,
            'newT',
            'would land within minSeparation ($minSeparation) of the key at '
                't = ${keys[n].t}; coincident keys are impossible by '
                'construction (AC-6.2.2), so the move is rejected rather than '
                'silently nudged');
      }
    }

    final moved = keys[index].copyWith(t: t);
    final next = <Keyframe<T>>[
      for (var n = 0; n < keys.length; n++)
        if (n != index) keys[n],
      moved,
    ]..sort((a, b) => a.t.compareTo(b.t));
    return track.withKeys(next);
  }

  /// Remove the key at [index] (AC-6.2.5's delete).
  ///
  /// Removing the **last remaining** key is not representable at the track
  /// level: T1 requires `keys.isNotEmpty`, and a zero-key track cannot be
  /// constructed. So this throws [ArgumentError] naming the fix — at the
  /// document level that is `KeyframeOps.removeKey`, which drops the whole track
  /// from the `TrackSet` (and the node entry if it empties). This op never
  /// invents an empty track and never silently keeps the key.
  ///
  /// Throws [ArgumentError] for an [index] out of range or a one-key track.
  static TypedTrack<T> removeKeyframeAt<T>(TypedTrack<T> track, int index) {
    final keys = track.keys;
    _checkIndex(index, keys.length);
    if (keys.length == 1) {
      throw ArgumentError.value(
          index,
          'index',
          'cannot remove the last remaining key: T1 requires keys.isNotEmpty '
              'and a zero-key track is unrepresentable. Remove the whole track '
              'from the TrackSet instead — at the document level that is '
              'KeyframeOps.removeKey');
    }
    return track.withKeys(<Keyframe<T>>[
      for (var n = 0; n < keys.length; n++)
        if (n != index) keys[n],
    ]);
  }

  /// Set the easing on the segment **leaving** the key at [index] (AC-7.1.1).
  ///
  /// The value and time are untouched. The **last** key has no outgoing segment,
  /// so its easing governs nothing — but it is still stored losslessly here, so
  /// a document authored with an easing on its last key (or one that had a key
  /// appended after) round-trips rather than having it dropped.
  ///
  /// Throws [ArgumentError] for an [index] out of range.
  static TypedTrack<T> setEasing<T>(
      TypedTrack<T> track, int index, Easing easing) {
    final keys = track.keys;
    _checkIndex(index, keys.length);
    return track.withKeys(<Keyframe<T>>[
      for (var n = 0; n < keys.length; n++)
        if (n == index) keys[n].copyWith(easing: easing) else keys[n],
    ]);
  }

  /// Move the first key to `t = 0` and the last to `t = 1` (AC-6.2.4).
  ///
  /// **UX sugar, never an invariant, and never automatic.** T6 is explicit that
  /// a track is *not* auto-pinned: `sampleAt`'s hold-first/hold-last already
  /// makes a track that legitimately starts at `t = 0.4` correct everywhere, so
  /// pinning buys nothing for correctness and would *corrupt* such a track by
  /// stretching its authored timing. This exists only for the timeline's
  /// explicit "pin endpoints" affordance — it must be reachable *only* by a user
  /// action, never from decode, a build method, or another op. A track already
  /// spanning `[0,1]` is returned unchanged.
  ///
  /// A single-key track has no distinct first and last, so it is expanded into
  /// two keys — the same value held at `0` and at `1` — which is the "or inserts
  /// them" half of the affordance and is render-identical to the one key under
  /// hold-first/hold-last.
  static TypedTrack<T> pinEndpoints<T>(TypedTrack<T> track) {
    final keys = track.keys;
    if (keys.first.t == 0.0 && keys.last.t == 1.0) return track;
    if (keys.length == 1) {
      final only = keys.single;
      return track.withKeys(
          <Keyframe<T>>[only.copyWith(t: 0.0), only.copyWith(t: 1.0)]);
    }
    final last = keys.length - 1;
    return track.withKeys(<Keyframe<T>>[
      for (var n = 0; n < keys.length; n++)
        if (n == 0)
          keys[n].copyWith(t: 0.0)
        else if (n == last)
          keys[n].copyWith(t: 1.0)
        else
          keys[n],
    ]);
  }

  static void _checkIndex(int index, int length) {
    if (index < 0 || index >= length) {
      throw ArgumentError.value(
          index, 'index', 'out of range for a $length-key track');
    }
  }
}
