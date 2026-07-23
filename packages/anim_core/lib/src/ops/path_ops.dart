/// Path mutations (docs/v3/01 §12).
///
/// **The M3 subset: [PathOps.moveAnchor], [PathOps.setTangents] and
/// [PathOps.regenerateRecipe].**
///
/// The first two are **pose** edits and are keyframe-local. The third is a
/// **topology replacement** and is document-wide for the node — which is why it
/// refuses the one case it cannot do correctly yet (see its doc comment) rather
/// than doing it wrong quietly.
///
/// `insertAnchor`, `deleteAnchor` and `retopologize` — the remaining topology
/// edits — are **M5** and are deliberately absent. They are not one-liners
/// waiting to be filled in: each has to write into every keyframe of every path
/// track for that node across every animation, in one transaction and one undo
/// entry, with `insertAnchor` computing each backfilled pose by de Casteljau
/// splitting *that keyframe's own* cubic at `u` so every existing keyframe stays
/// pixel-identical. A stub that edits the node's `PathData` and leaves the
/// tracks alone would produce exactly the mismatched anchor set v3 exists to
/// make unrepresentable, and it would do it silently.
///
/// Structural enforcement, not convention: `PathData`'s const constructor is
/// private and this class is the only route to a topology change, so the pen
/// tool has **no** way to call a node-level path replacement on a tracked node.
/// `boundary_test.dart` asserts it at source level (AC-4.3.8).
///
/// Ops throw loudly; the command layer catches (docs/v3/08 §1).
library;

import '../animation.dart';
import '../document.dart';
import '../eval/evaluate.dart';
import '../node.dart';
import '../path.dart';
import '../primitives.dart';
import '../recipe.dart';
import '../shape_geometry.dart';
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

    return _poseEditAt(
      d,
      n,
      node,
      a,
      atT,
      (x) => AnchorPose(to, x.inTangent, x.outTangent),
    );
  }

  /// **POSE edit: keyframe-local**, exactly like [moveAnchor] — the pen tool's
  /// handle drag (AC-4.2.2, F4.2).
  ///
  /// [atT] `null` edits the node's `PathData` rest pose and touches no track;
  /// [atT] non-null writes the tangents into that keyframe alone, seeding and
  /// backfilling the `PathTrack` by the same rules [moveAnchor] documents at
  /// length. **The `AnchorId` sequence is untouched by both branches** — this op
  /// cannot change the topology, only where handles point.
  ///
  /// ## Where each piece lands, and why they land in different places
  ///
  /// [inT] / [outT] are **pose**: they vary per keyframe, they are what
  /// `AnchorPose` stores, and they are what the evaluator lerps.
  ///
  /// [kind] is **not** pose. `AnchorPose` has no field for it, `PropKey` has no
  /// channel for it, and docs/v3/01 §7 lists `AnchorKind` under "not animatable
  /// — decided, not overlooked". So it is written to the anchor in the node's
  /// `PathData`, document-wide, in **both** branches. That is the only place it
  /// can live, and living there is what makes it safe to flip without
  /// re-tweening (docs/v3/01 §5).
  ///
  /// The consequence is deliberate and worth stating plainly: **the kind is
  /// document-wide, the handle correction it implies is keyframe-local.**
  /// Flipping an anchor to [AnchorKind.corner] at `t = 0.5` zeroes the handles
  /// *in that keyframe's pose*; keyframes 1 and 3 keep the exact tangents their
  /// author gave them. The alternative — rewriting every keyframe's tangents to
  /// satisfy the new hint — is a document-wide geometry rewrite disguised as a
  /// hint toggle, and it would silently deform keyframes the user is not even
  /// looking at, which is the precise failure AC-4.2.1/2 exist to forbid. The
  /// renderer and the evaluator never read `kind` (docs/v3/01 §5), so a stored
  /// `kind` that disagrees with an old keyframe's tangents costs a UI affordance
  /// on the next handle drag and not one wrong pixel.
  ///
  /// ## The kind invariants are baked into the STORED tangents (AC-4.1.3)
  ///
  /// Enforced here, at the moment handles are set — never at render, because
  /// nothing at render reads `kind` to enforce it with:
  ///
  /// - [AnchorKind.corner] — **independent** handles, stored verbatim. Passing
  ///   `kind: corner` *by itself* zeroes both, because that is the inspector's
  ///   "straighten this" button and the segments must then render as the
  ///   degenerate straight cubic. Passing it **together with** a handle does
  ///   not: that call is one drag authoring an asymmetric corner, and a rounded
  ///   rectangle's corner anchors are exactly that shape — one zero handle
  ///   along the edge, one κ handle into the arc. A rule that zeroed on every
  ///   corner-anchor edit would make those un-editable and would delete the
  ///   handle the caller passed in the same breath.
  /// - [AnchorKind.smooth] — handles collinear and opposed, lengths independent.
  ///   The follower keeps its own length and is re-aimed opposite the driver.
  /// - [AnchorKind.symmetric] — collinear *and* equal length: the follower
  ///   becomes the exact negation of the driver.
  ///
  /// **The driver** is the handle the caller actually supplied: [outT] if given,
  /// otherwise [inT], otherwise (a bare [kind] change) whichever existing handle
  /// is non-zero, preferring `out`. When both are supplied, [outT] drives and
  /// [inT] is corrected — a UI that hands over both is describing one drag, and
  /// storing the pair verbatim would leave a `symmetric` anchor whose stored
  /// tangents are not symmetric, which is a lie the next drag would have to
  /// discover. A zero-length driver leaves both handles zero: there is no
  /// direction to be collinear with, and inventing one would rotate the
  /// follower to an arbitrary angle.
  ///
  /// **Nulls the node's [PathNode.recipe]** in both branches, per docs/v3/01
  /// §5's authority rule and for the reasons spelled out on [moveAnchor]: a
  /// hand-curved rectangle corner is no longer regenerable from `w`, `h` and a
  /// corner radius, and letting a later width nudge overwrite it is the
  /// wrong-shape bug that rule exists to prevent.
  ///
  /// A call supplying none of [inT], [outT] or [kind] is a no-op and returns [d]
  /// unchanged — including the recipe, because nothing was edited by hand.
  ///
  /// Throws [ArgumentError] for an unknown node, a node that is not a
  /// [PathNode], an unknown anchor, a non-finite tangent component, or an [atT]
  /// outside `[0,1]`.
  static Document setTangents(
    Document d,
    NodeId n,
    AnchorId a, {
    Vec2? inT,
    Vec2? outT,
    AnchorKind? kind,
    double? atT,
  }) {
    final found = d.nodeIndex[n];
    if (found is! PathNode) {
      throw ArgumentError.value(
          n.v, 'node', found == null ? 'no such node' : 'is not a path node');
    }
    final node = found;
    final index = node.path.anchors.indexWhere((x) => x.id == a);
    if (index < 0) {
      throw ArgumentError.value(
          a.v, 'anchor', 'not in the topology of node "${n.v}"');
    }
    _finite(inT, 'inT');
    _finite(outT, 'outT');
    if (inT == null && outT == null && kind == null) return d;

    final anchor = node.path.anchors[index];
    final effective = kind ?? anchor.kind;
    // `kind` is topology-adjacent: it goes onto the node's PathData whichever
    // branch the tangents take. Null means "unchanged", so the rest-pose branch
    // below still gets a fresh PathData while the keyframe branch gets none.
    final rekinded = kind == null
        ? null
        : PathData(
            closed: node.path.closed,
            anchors: <Anchor>[
              for (final x in node.path.anchors)
                if (x.id == a) x.copyWith(kind: kind) else x,
            ],
          );

    if (atT == null) {
      final (nextIn, nextOut) = _enforceKind(
          effective, kind, anchor.inTangent, anchor.outTangent, inT, outT);
      return d.copyWith(
        root: _replacePath(
            d.root,
            n,
            (p) => p.copyWith(
                  path: PathData(
                    closed: p.path.closed,
                    anchors: <Anchor>[
                      for (final x in p.path.anchors)
                        if (x.id == a)
                          x.copyWith(
                              inTangent: nextIn,
                              outTangent: nextOut,
                              kind: effective)
                        else
                          x,
                    ],
                  ),
                  clearRecipe: true,
                )),
      );
    }

    return _poseEditAt(
      d,
      n,
      node,
      a,
      atT,
      (x) {
        final (nextIn, nextOut) =
            _enforceKind(effective, kind, x.inTangent, x.outTangent, inT, outT);
        return AnchorPose(x.position, nextIn, nextOut);
      },
      topology: rekinded,
    );
  }

  /// **TOPOLOGY replacement.** Regenerate [n]'s geometry from [recipe] and store
  /// [recipe] as the node's new inert metadata (AC-4.1.4, AC-4.1.5).
  ///
  /// This is the **one route** by which a recipe parameter edit reaches
  /// geometry. A shape inspector that nudged `w` and then assigned
  /// `PathNode.path` itself would be the bypass AC-4.1.5 forbids; it cannot,
  /// because `PathData`'s const constructor is private and this class is the
  /// only route to a topology change (AC-4.3.8, asserted at source level in
  /// `boundary_test.dart`).
  ///
  /// ## The ruling on a node that already has a path track
  ///
  /// AC-4.1.5 says the edit "routes through `PathOps.retopologize`". docs/v3/06
  /// schedules `retopologize` — anchor correspondence by **arc length** — at
  /// **M5**, not M3. Both are right, and the honest resolution is to split the
  /// case rather than to pick one document over the other:
  ///
  /// - **No path track: plain replacement.** There is no keyframe posing the
  ///   old ids, so there is no correspondence to compute; the new anchor set is
  ///   simply the node's anchor set. This is every shape the tool has just drawn
  ///   and every shape nobody has animated yet — the entire M3 use case — and it
  ///   is implemented here, now. ("No track" is the whole of that case: a track
  ///   with zero keyframes is unrepresentable, because `PathTrack` rejects an
  ///   empty key list.)
  ///
  /// - **A path track with keyframes: refused, loudly, naming M5.** Every
  ///   keyframe poses the *old* ids; the recipe mints *fresh* ones. Writing the
  ///   new geometry and leaving the poses alone gives the node and its keyframes
  ///   disjoint id sets — the single state v3 exists to make unrepresentable
  ///   (docs/v3/01 §5, §13.1). Backfilling the new ids from the rest pose would
  ///   be worse: it type-checks, satisfies AC-4.3.6, and silently deletes every
  ///   keyframe the user authored. The correct answer is arc-length
  ///   correspondence over the old and new outlines, it is a real piece of work,
  ///   and shipping a cheap approximation of it under the same name is how the
  ///   next milestone inherits a bug it cannot see. So this throws
  ///   [ArgumentError] until `retopologize` exists, and the command layer turns
  ///   that into a visible refusal (docs/v3/08 §1) instead of a wrong document.
  ///
  /// The UI consequence is precise and worth handing to the inspector: the shape
  /// parameter fields are editable on an un-animated node and must be disabled,
  /// with M5 named, on a node that has path keyframes. That is a smaller lie
  /// than a slider that destroys an animation.
  ///
  /// An [UnknownRecipe] is refused too. It is preserve-and-ignore metadata from
  /// a build that knows shapes this one does not (docs/v3/02 §7); regenerating
  /// from it would replace real geometry with [PathData.empty] — the user's
  /// artwork silently vanishing on a re-edit, which is exactly the forward-compat
  /// failure `UnknownRecipe` exists to prevent.
  ///
  /// Throws [ArgumentError] for an unknown node, a node that is not a
  /// [PathNode], an [UnknownRecipe], or a node carrying path keyframes.
  static Document regenerateRecipe(Document d, NodeId n, ShapeRecipe recipe) {
    final found = d.nodeIndex[n];
    if (found is! PathNode) {
      throw ArgumentError.value(
          n.v, 'node', found == null ? 'no such node' : 'is not a path node');
    }
    if (recipe is UnknownRecipe) {
      throw ArgumentError.value(
          recipe.toString(),
          'recipe',
          'this build cannot read the recipe, so regenerating from it would '
              'replace the node geometry with nothing');
    }

    // Every animation, not just the default one: a track under a second clip
    // poses the same node's anchors and would be orphaned just as thoroughly.
    for (final animation in d.animations) {
      final track = animation.tracksFor(n).pathTrack();
      if (track != null) {
        throw ArgumentError.value(
            n.v,
            'node',
            'has ${track.keyCount} path keyframes in animation '
                '"${animation.id.v}". Regenerating a recipe onto a tracked node '
                'requires PathOps.retopologize (arc-length correspondence), '
                'which is M5 (docs/v3/06); a raw replacement would mint fresh '
                'AnchorIds and leave the topology and its keyframes disjoint');
      }
    }

    return d.copyWith(
      root: _replacePath(
          d.root, n, (p) => p.copyWith(path: recipe.toPath(), recipe: recipe)),
    );
  }
}

/// The keyframe-local half of a pose edit, shared by [PathOps.moveAnchor] and
/// [PathOps.setTangents] — one copy, so the two edits cannot disagree about
/// seeding, backfilling, easing or recipe nulling.
///
/// [edit] receives the anchor **as it is resolved at [t]** — not the rest anchor
/// — and returns its replacement pose. [topology] optionally replaces the node's
/// `PathData` in the same document (this is how `setTangents` writes a
/// document-wide `AnchorKind` while the tangents stay keyframe-local); `null`
/// leaves the topology byte-identical.
///
/// See [PathOps.moveAnchor] for why the track is seeded at `t = 0` with the full
/// rest pose, and why the displaced key's easing rides across.
Document _poseEditAt(
  Document d,
  NodeId n,
  PathNode node,
  AnchorId a,
  double t,
  AnchorPose Function(Anchor resolved) edit, {
  PathData? topology,
}) {
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

  // What the shape already looks like at `t` — so editing one anchor does not
  // snap the other anchors back to rest.
  final (k0, k1, u) = seeded.bracket(t);
  final current = resolveNodePose(
    node.path,
    <PathBracket>[PathBracket(k0.value, k1.value, u, 1.0)],
  );
  final pose = PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
    for (final x in current.anchors)
      x.id: x.id == a
          ? edit(x)
          : AnchorPose(x.position, x.inTangent, x.outTangent),
  }));

  // The displaced key's easing rides across. A pose edit is keyframe-local and
  // easing is not part of a pose (docs/v3/01 §1 rule 1, §8): re-authoring the
  // shape at `t` must not silently retime the segment leaving `t` back to
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
    root: _replacePath(
        doc.root, n, (p) => p.copyWith(path: topology, clearRecipe: true)),
    animations: <Animation>[
      for (final x in doc.animations)
        if (x.id == updated.id) updated else x,
    ],
  );
}

/// The [AnchorKind] contract, applied to the tangents about to be **stored**
/// (AC-4.1.3). See [PathOps.setTangents] for the driver rule and its rationale.
(Vec2, Vec2) _enforceKind(
  AnchorKind kind,
  AnchorKind? requested,
  Vec2 baseIn,
  Vec2 baseOut,
  Vec2? inT,
  Vec2? outT,
) {
  switch (kind) {
    case AnchorKind.corner:
      // Handles are INDEPENDENT: nothing to reconcile, so they store verbatim.
      // The one exception is a bare `kind: corner` — the inspector's "make this
      // straight" button — which zeroes both, because zero handles are what
      // make the degenerate cubic render as a line. There is no polyline branch
      // to switch to instead.
      if (requested == AnchorKind.corner && inT == null && outT == null) {
        return (Vec2.zero, Vec2.zero);
      }
      return (inT ?? baseIn, outT ?? baseOut);
    case AnchorKind.smooth:
    case AnchorKind.symmetric:
      final wantIn = inT ?? baseIn;
      final wantOut = outT ?? baseOut;
      final outDrives = outT != null || (inT == null && baseOut != Vec2.zero);
      return outDrives
          ? (_follow(wantOut, wantIn, kind), wantOut)
          : (wantIn, _follow(wantIn, wantOut, kind));
  }
}

/// The corrected follower handle: opposite [driver], keeping [follower]'s own
/// length for [AnchorKind.smooth] and taking [driver]'s for
/// [AnchorKind.symmetric].
Vec2 _follow(Vec2 driver, Vec2 follower, AnchorKind kind) {
  if (kind == AnchorKind.symmetric) return Vec2(-driver.x, -driver.y);
  final length = driver.length;
  final want = follower.length;
  // No direction to oppose, or nothing to aim: both leave the follower at zero
  // rather than inventing an angle out of a degenerate handle.
  if (length == 0.0 || want == 0.0) return Vec2.zero;
  return Vec2(-driver.x / length * want, -driver.y / length * want);
}

/// Ops throw loudly (docs/v3/08 §1). A NaN handle poisons every arithmetic
/// result downstream of it and an infinite one reaches the rasteriser as an
/// infinite control point — both are caller bugs, not documents with bad data.
void _finite(Vec2? v, String name) {
  if (v == null) return;
  if (!v.x.isFinite || !v.y.isFinite) {
    throw ArgumentError.value(v.toString(), name, 'must be finite');
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
