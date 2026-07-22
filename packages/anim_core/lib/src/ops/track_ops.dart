/// Keyframe mutations (docs/v3/01 §12).
///
/// **The M0 subset: [TrackOps.upsertKeyframe] and nothing else.**
///
/// `moveKeyframe`, `removeKeyframeAt`, `setEasing` and `pinEndpoints` arrive at
/// **M4** with the timeline's drag/delete/easing UI. They are absent rather
/// than stubbed on purpose: an op is where an invariant is enforced, so a stub
/// is not a placeholder but a hole in the invariant — a `moveKeyframe` that
/// forwards to a rebuild without the `minSeparation` rejection ships coincident
/// keys, and the sampler is then expected to paper over them. It never will,
/// because the enforcement lives here (docs/v3/08 §1: ops throw loudly, the
/// command layer catches).
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
}
