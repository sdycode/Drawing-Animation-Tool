/// Path mutations (docs/v3/01 §12).
///
/// **The M0 subset: [PathOps.moveAnchor] and nothing else.**
///
/// `setTangents` is M1 (the pen tool's handle drag). `insertAnchor`,
/// `deleteAnchor` and `retopologize` — the **topology** edits, which are
/// document-wide for the node — are **M5** and are deliberately absent. They
/// are not one-liners waiting to be filled in: each has to write into every
/// keyframe of every path track for that node across every animation, in one
/// transaction and one undo entry, with `insertAnchor` computing each backfilled
/// pose by de Casteljau splitting *that keyframe's own* cubic at `u` so every
/// existing keyframe stays pixel-identical. A stub that edits the node's
/// `PathData` and leaves the tracks alone would produce exactly the mismatched
/// anchor set v3 exists to make unrepresentable, and it would do it silently.
///
/// Structural enforcement, not convention: `PathData`'s const constructor is
/// private and this class is the only route to a topology change, so the pen
/// tool has **no** way to call a node-level path replacement on a tracked node.
///
/// Ops throw loudly; the command layer catches (docs/v3/08 §1).
library;

import '../animation.dart';
import '../document.dart';
import '../eval/evaluate.dart';
import '../node.dart';
import '../path.dart';
import '../primitives.dart';
import '../track.dart';
import '../uuid.dart';
import 'track_ops.dart';

abstract final class PathOps {
  /// **POSE edit: keyframe-local** (docs/v3/01 §1, governing rule 1).
  ///
  /// [atT] `null` edits the node's rest pose in its `PathData` and touches no
  /// track at all. That is the pen tool's edit and the only one that exists
  /// before a document is animated.
  ///
  /// [atT] non-null writes into the `PathTrack` keyframe at that `t` on the
  /// document's **default animation**, creating the `Animation`, the `TrackSet`
  /// and the `PathTrack` if they are absent. The node's rest pose is left
  /// untouched — that is what "keyframe-local" means.
  ///
  /// When the `PathTrack` is created, a key at `t = 0.0` holding the node's
  /// **full rest pose** is seeded first. Without the seed the first drag at
  /// `t > 0` yields a one-key track, which hold-first/hold-last correctly makes
  /// constant everywhere — the shape would jump to its new pose and then refuse
  /// to animate, and the author would have no way to tell that from a broken
  /// evaluator. With the seed the first drag produces **two keys that differ**,
  /// which is the thin M0 slice of F4.2 + F6.1 and what makes M0's exit
  /// criterion reachable by hand. (A drag at exactly `t = 0.0` replaces the
  /// seed and leaves one key, which is correct: there is nothing to interpolate
  /// between.)
  ///
  /// The pose written at [atT] is the **full pose map for every anchor in the
  /// node's topology**, not just the dragged one, and every pre-existing
  /// keyframe is backfilled the same way. Every keyframe of the track therefore
  /// ends up posing exactly the node's `AnchorId` set, in topology order — the
  /// invariant M5's topology transactions will depend on, asserted verbatim in
  /// `ops_test.dart`. Backfilling from the rest anchor is render-identical to
  /// leaving the entry missing, because that is precisely what
  /// [resolveNodePose] does with a missing entry.
  ///
  /// **Both branches null the node's [PathNode.recipe]** — docs/v3/01 §5's
  /// authority rule: the recipe regenerates `path`, so any manual anchor edit
  /// nulls it. Without that line, a user who draws a rectangle, drags one
  /// corner, then nudges the rectangle's width in the (M3) shape inspector
  /// silently loses the drag, because regeneration overwrites the geometry from
  /// four numbers that never heard about it. The rule is enforced here, at the
  /// only mutation that can create the divergence, rather than trusted to the
  /// UI that will read the recipe two milestones from now.
  ///
  /// The keyframe-local branch nulls it too, deliberately. A pose edit does not
  /// change the topology the recipe would regenerate, so keeping the recipe is
  /// *arguably* safe — but "arguably safe" is how a wrong-shape bug gets
  /// shipped, and the cost of being wrong in this direction is one re-editable
  /// rectangle, while the cost of being wrong in the other is a keyframe the
  /// user authored disappearing on a width nudge.
  ///
  /// Regenerating a recipe onto a node that already has a `PathTrack` is the
  /// *other* half of the rule and it is **not** here: it must route through
  /// `PathOps.retopologize` (M5), which rewrites the node's topology and every
  /// keyframe's pose map onto the new id set by arc-length correspondence. A
  /// raw path replacement mints fresh `AnchorId`s, giving the node and its
  /// keyframes disjoint id sets — the exact state v3 exists to make
  /// unrepresentable. There is no partial version of that op worth shipping, so
  /// there is none.
  ///
  /// Throws [ArgumentError] for an unknown node, a node that is not a
  /// [PathNode], an unknown anchor, or an [atT] outside `[0,1]`.
  static Document moveAnchor(
    Document d,
    NodeId n,
    AnchorId a,
    Vec2 to, {
    double? atT,
  }) {
    final found = d.nodeIndex[n];
    if (found is! PathNode) {
      throw ArgumentError.value(
          n.v, 'node', found == null ? 'no such node' : 'is not a path node');
    }
    final node = found;
    if (!node.path.anchors.any((x) => x.id == a)) {
      throw ArgumentError.value(
          a.v, 'anchor', 'not in the topology of node "${n.v}"');
    }

    if (atT == null) {
      final moved = <Anchor>[
        for (final x in node.path.anchors)
          if (x.id == a) x.copyWith(position: to) else x,
      ];
      return d.copyWith(
        root: _replacePath(
            d.root,
            n,
            (p) => p.copyWith(
                  path: PathData(anchors: moved, closed: p.path.closed),
                  clearRecipe: true,
                )),
      );
    }

    final t = atT;
    if (t.isNaN || t < 0.0 || t > 1.0) {
      throw ArgumentError.value(t, 'atT', 'must lie in [0,1]');
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

    final tracks = animation.tracksFor(n);
    // The seed is the whole reason a first drag produces two keys. It is built
    // from the topology's rest pose, never from the dragged value.
    final seeded = tracks.pathTrack() ??
        PathTrack(<Keyframe<PathPose>>[
          Keyframe<PathPose>(t: 0.0, value: _restPose(node.path)),
        ]);

    // What the shape already looks like at `t` — so dragging one anchor does
    // not snap the other anchors back to rest.
    final (k0, k1, u) = seeded.bracket(t);
    final current = resolveNodePose(
      node.path,
      <PathBracket>[PathBracket(k0.value, k1.value, u, 1.0)],
    );
    final pose = PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
      for (final x in current.anchors)
        x.id: x.id == a
            ? AnchorPose(to, x.inTangent, x.outTangent)
            : AnchorPose(x.position, x.inTangent, x.outTangent),
    }));

    // The displaced key's easing rides across. A pose edit is keyframe-local
    // and easing is not part of a pose (docs/v3/01 §1 rule 1, §8): re-authoring
    // the shape at `t` must not silently retime the segment leaving `t` back to
    // linear, which is what `Keyframe`'s model default would do to a key an
    // easing UI, another client or an importer had already curved.
    final track = _backfilled(
      TrackOps.upsertKeyframe(
        seeded,
        Keyframe<PathPose>(
          t: t,
          value: pose,
          easing: TrackOps.easingAt(seeded, t),
        ),
      ),
      node.path,
    );

    final updated = animation.copyWith(
      tracks: Map.unmodifiable(<NodeId, TrackSet>{
        ...animation.tracks,
        n: TrackSet(
          Map.unmodifiable(<PropertyKey, Track>{
            ...tracks.byKey,
            const PropertyKey(PropKey.path): track,
          }),
          unknownKeys: tracks.unknownKeys,
        ),
      }),
    );

    return doc.copyWith(
      root: _replacePath(doc.root, n, (p) => p.copyWith(clearRecipe: true)),
      animations: <Animation>[
        for (final x in doc.animations)
          if (x.id == updated.id) updated else x,
      ],
    );
  }
}

/// Every anchor of [topology] at its authored rest position.
PathPose _restPose(PathData topology) =>
    PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
      for (final x in topology.anchors)
        x.id: AnchorPose(x.position, x.inTangent, x.outTangent),
    }));

/// Rewrites every keyframe to pose exactly [topology]'s `AnchorId` sequence.
///
/// Missing entries are filled from the rest anchor and orphan entries — poses
/// for ids the node no longer has — are dropped, which is the same repair
/// `Document.fromJson` applies (invariant P6). Doing it on every pose edit is
/// what keeps the "poses == topology" commit invariant green without a
/// document-wide sweep.
PathTrack _backfilled(PathTrack track, PathData topology) =>
    track.withKeys(<Keyframe<PathPose>>[
      for (final k in track.keys)
        Keyframe<PathPose>(
          t: k.t,
          easing: k.easing,
          value: PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
            for (final x in topology.anchors)
              x.id: k.value.anchors[x.id] ??
                  AnchorPose(x.position, x.inTangent, x.outTangent),
          })),
        ),
    ]);

/// Rebuilds the tree with one [PathNode] replaced.
///
/// Typed on [PathNode] rather than [Node] so there is no `as` on the way in and
/// no way to swap a node for one of a different kind by accident.
GroupNode _replacePath(
        GroupNode root, NodeId id, PathNode Function(PathNode) edit) =>
    root.copyWith(children: <Node>[
      for (final child in root.children)
        switch (child) {
          final PathNode p when p.id == id => edit(p),
          final GroupNode g => _replacePath(g, id, edit),
          _ => child,
        },
    ]);
