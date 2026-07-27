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
/// **The M4 addition: [PathOps.keyPose]** — the "stopwatch". It authors the
/// *first* path keyframe (and continues one) by snapshotting the pose already
/// on screen, moving nothing. Without it the M4 exit criterion "set 3 keyframes
/// on a path's geometry" is unreachable by hand: the pose edits above only ever
/// create a `PathTrack` as a *side effect* of a drag, and after the AC-4.2.3
/// fix a drag on a static node edits the rest pose and touches no track at all.
///
/// **The M5 additions: [PathOps.insertAnchor], [PathOps.deleteAnchor] and
/// [PathOps.retopologize]** — the topology edits, and the reason the whole
/// rewrite exists (docs/v3/06 M5 ★). Each writes into every keyframe of every
/// path track for that node across every animation — **and** the node's rest
/// `PathData` — in one transaction and one undo entry:
///
/// - `insertAnchor` mints ONE `AnchorId` and computes each backfilled pose by de
///   Casteljau splitting *that keyframe's own* cubic at `u`, so the split is
///   exact and every existing keyframe stays **pixel-identical** (AC-4.3.2).
/// - `deleteAnchor` removes an id from the topology and every keyframe pose,
///   never auto-repairing neighbour tangents (removing a mid-curve anchor is a
///   shape change, and faking continuity would be a silent geometry edit).
/// - `retopologize` rewrites the whole anchor set onto a new id set by
///   arc-length correspondence — the only route besides insert/delete an anchor
///   set may change, run once per edit and never inside the tick.
///
/// A stub that edited the node's `PathData` and left the tracks alone would
/// produce exactly the mismatched anchor set v3 exists to make unrepresentable,
/// and it would do it silently. Every one of these leaves the invariant M5
/// depends on green: the node's topology `AnchorId` **sequence** and every
/// keyframe's pose keyset are identical afterwards (AC-4.3.6).
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
import '../easing.dart';
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

  /// **The "stopwatch": start (or continue) path animation without moving an
  /// anchor** (docs/v3/03 F6.1; the M4 exit criterion "set 3 keyframes on a
  /// path's geometry").
  ///
  /// [moveAnchor] and [setTangents] only ever create a `PathTrack` as a *side
  /// effect* of a drag, and after the AC-4.2.3 fix a drag on a static node
  /// edits the rest pose and touches no track at all. So before this op there
  /// was no way to author the *first* path keyframe: a user could draw a curve
  /// and never begin animating it. This is that affordance — it snapshots the
  /// pose the canvas is already showing at [t] into a keyframe, and moves
  /// nothing.
  ///
  /// ## What "current pose" is
  ///
  /// - **Untracked node** — the snapshot is the node's **rest pose**, its
  ///   authored anchors verbatim. The first `keyPose` therefore seeds exactly
  ///   **one** key, and that is the whole difference from [moveAnchor]'s first
  ///   drag, which seeds a `t = 0` key *and* writes the dragged one: a drag has
  ///   a second, differing pose to interpolate toward, a stopwatch click does
  ///   not. One key is constant everywhere under hold-first/hold-last, which is
  ///   correct — the shape does not move until a second, differing key exists.
  /// - **Tracked node** — the snapshot is the pose **evaluated at [t]**, via the
  ///   same [resolveNodePose]/`bracket` the canvas draws, so keying at a new
  ///   time captures the interpolated shape (AE stopwatch semantics) for the
  ///   author to then edit.
  ///
  /// A second `keyPose` at a different [t] — or a [moveAnchor]/[setTangents]
  /// drag at a different [t], which works once a track exists — yields two keys
  /// that can differ, and the shape animates. That is what makes the M4 exit
  /// criterion reachable by hand.
  ///
  /// ## Upsert, topology and easing — the same rules the drag ops use
  ///
  /// The key is **upserted** at [t] ([TrackOps.upsertKeyframe]'s rules): an
  /// existing key at [t], or within `minSeparation`, is replaced, never
  /// duplicated. The written pose maps **exactly** the node's `AnchorId`
  /// topology and every pre-existing key is backfilled the same way, so every
  /// keyframe ends up posing exactly the node's id set in topology order
  /// (invariant P5 / AC-4.3.6) — the guarantee [moveAnchor] gives. A replaced
  /// key's easing rides across ([TrackOps.easingAt]); a key authored where none
  /// existed is linear, never inherited.
  ///
  /// ## It does NOT null the recipe — the deliberate choice
  ///
  /// [moveAnchor] and [setTangents] null [PathNode.recipe] because they edit an
  /// anchor by hand, so the geometry is no longer regenerable from the recipe's
  /// parameters. **`keyPose` edits no anchor.** It changes no rest anchor, no
  /// topology and no `closed` flag — the node's `PathData` is byte-identical
  /// afterwards (there is no `root:` in the returned document, on purpose) — so
  /// the recipe still faithfully describes the rest geometry and is left intact.
  /// The wrong-shape bug the authority rule (docs/v3/01 §5) guards against needs
  /// a *hand anchor edit* that diverges from the recipe, and there is none here.
  ///
  /// The node is now tracked. Keeping the recipe lets the inspector keep naming
  /// the shape ("Rectangle") and, as of M5, keep its parameter fields editable —
  /// an edit retopologizes every keyframe onto the new recipe by arc-length
  /// correspondence. (Before M5 a tracked node's recipe edit was refused; that
  /// refusal is gone.) Degrading to an anonymous path here would throw both away.
  ///
  /// Throws [ArgumentError] for an unknown node, a node that is not a
  /// [PathNode], or a [t] outside `[0,1]`.
  static Document keyPose(Document d, NodeId n, double t) {
    final found = d.nodeIndex[n];
    if (found is! PathNode) {
      throw ArgumentError.value(
          n.v, 'node', found == null ? 'no such node' : 'is not a path node');
    }
    if (t.isNaN || t < 0.0 || t > 1.0) {
      throw ArgumentError.value(t, 't', 'must lie in [0,1]');
    }
    final node = found;

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
    final base = tracks.pathTrack();

    // The pose the canvas already shows at `t`: the rest topology when the node
    // is untracked (`resolveNodePose` returns it verbatim for an empty mix), the
    // bracketed/eased pose when it is tracked. Either way it maps exactly the
    // node's AnchorId set, so the backfill below is a no-op on the new key and
    // only repairs any pre-existing partial pose.
    final brackets = <PathBracket>[];
    if (base != null) {
      final (k0, k1, u) = base.bracket(t);
      brackets.add(PathBracket(k0.value, k1.value, u, 1.0));
    }
    final current = resolveNodePose(node.path, brackets);
    final pose = PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
      for (final x in current.anchors)
        x.id: AnchorPose(x.position, x.inTangent, x.outTangent),
    }));

    final key = Keyframe<PathPose>(
      t: t,
      value: pose,
      // A replace carries the displaced key's easing across; a first/new key is
      // linear and never inherited — the rule [moveAnchor] documents at length.
      easing: base == null ? const LinearEasing() : TrackOps.easingAt(base, t),
    );
    final track = _backfilled(
      base == null
          ? PathTrack(<Keyframe<PathPose>>[key])
          : TrackOps.upsertKeyframe(base, key),
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

    // No `root:` — the node's PathData and recipe are untouched, on purpose.
    return doc.copyWith(
      animations: <Animation>[
        for (final x in doc.animations)
          if (x.id == updated.id) updated else x,
      ],
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
  ///   [ArgumentError] on a tracked node — but as of M5 it is only an
  ///   unreachable **backstop**: [retopologize] now exists, and the command
  ///   layer routes a tracked node's recipe edit through it (`recipe_guard`'s
  ///   `hasPathTrack` → `RetopologizeCommand`) rather than here. This throw fires
  ///   only if a future call site bypasses that route with a tracked node.
  ///
  /// The UI consequence, post-M5: a tracked node's shape parameter fields are
  /// **editable**, and editing one retopologizes every keyframe onto the new
  /// recipe's anchor set by arc-length correspondence. (Before M5 they were
  /// disabled with M5 named — that is no longer the behaviour.)
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

  /// **TOPOLOGY edit: DOCUMENT-WIDE for the node** — insert one anchor mid-path
  /// (docs/v3/01 §1 rule 1, §12, §13.5; AC-4.3.1/2/3). This is the heart of M5.
  ///
  /// Mints **one** fresh [AnchorId] and splices it into [n]'s `PathData`
  /// immediately after [after], respecting the `closed` wrap when [after] is the
  /// last anchor. Then, for **every keyframe of every path track for [n] across
  /// every animation — and the node's rest `PathData`** — it de Casteljau splits
  /// *that pose's own* `after → next` cubic at parameter [u] and writes:
  ///
  /// - the new anchor's pose = the split point `S`, with `inTangent = R0 − S`,
  ///   `outTangent = R1 − S` (non-zero collinear handles — see below);
  /// - the left neighbour ([after])'s `outTangent := Q0 − P0`;
  /// - the right neighbour ([next])'s `inTangent := Q2 − P3`.
  ///
  /// where, with `P1 = after.pos + after.outTangent`, `P2 = next.pos +
  /// next.inTangent` (docs/v3/01 §5, §13.5):
  ///
  /// ```
  /// Q0=lerp(P0,P1,u) Q1=lerp(P1,P2,u) Q2=lerp(P2,P3,u)
  /// R0=lerp(Q0,Q1,u) R1=lerp(Q1,Q2,u)  S=lerp(R0,R1,u)
  /// ```
  ///
  /// The split is **exact**: the two sub-cubics `[P0,Q0,R0,S]` and `[S,R1,Q2,P3]`
  /// reproduce the original `[P0,P1,P2,P3]` by construction, so after the insert
  /// every keyframe renders **pixel-identically** to before (AC-4.3.2, the
  /// golden the risk note says a nearly-correct split fails). Because each split
  /// reads *that keyframe's own* poses, the added anchor becomes a pass-through
  /// the author can drag independently at any keyframe, forever.
  ///
  /// The inserted anchor is [AnchorKind.smooth] with the **non-zero** collinear
  /// handles above — never a zero-handle corner. docs/v3/01 §13.5's explicit
  /// warning: zeroing the new anchor's handles visibly deforms the shape at every
  /// keyframe.
  ///
  /// [u] is the parameter on the *authoring* keyframe's cubic and is reused
  /// **verbatim** on the others — the split lands at the same *parametric*, not
  /// the same *arc-length*, position on differently-curved keyframes. This is a
  /// deliberate, documented approximation (docs/v3/01 §13.5): it is cheap and it
  /// must not be "fixed" into an arc-length solve.
  ///
  /// RESULT INVARIANT (AC-4.3.6): afterwards the node's topology `AnchorId`
  /// **sequence** and every keyframe's pose keyset are identical — one sequence
  /// across all keys and the rest pose — in topology order.
  ///
  /// The insert is a **pure read**: [d] is never modified. It **nulls the node's
  /// recipe** (docs/v3/01 §5's authority rule — a spliced anchor is a manual
  /// topology edit no recipe can regenerate).
  ///
  /// Returns the new document and the minted [AnchorId].
  ///
  /// Throws [ArgumentError] for an unknown node, a node that is not a [PathNode],
  /// an [after] not in the topology, an [after] with no segment leaving it (the
  /// last anchor of an open path, or a path with fewer than two anchors), or a
  /// [u] outside the open interval `(0,1)`.
  static (Document, AnchorId) insertAnchor(
    Document d,
    NodeId n, {
    required AnchorId after,
    required double u,
  }) {
    final found = d.nodeIndex[n];
    if (found is! PathNode) {
      throw ArgumentError.value(
          n.v, 'node', found == null ? 'no such node' : 'is not a path node');
    }
    final node = found;
    final anchors = node.path.anchors;
    final afterIndex = anchors.indexWhere((x) => x.id == after);
    if (afterIndex < 0) {
      throw ArgumentError.value(
          after.v, 'after', 'not in the topology of node "${n.v}"');
    }
    // A segment leaves anchor k iff k < segmentCount. For an open path that
    // excludes the last anchor; for a path of 0/1 anchors it excludes them all.
    if (afterIndex >= node.path.segmentCount) {
      throw ArgumentError.value(
          after.v,
          'after',
          'has no segment leaving it to split (last anchor of an open path, or '
              'a path with fewer than two anchors)');
    }
    if (u.isNaN || u <= 0.0 || u >= 1.0) {
      throw ArgumentError.value(u, 'u', 'must lie in the open interval (0,1)');
    }

    final count = anchors.length;
    final nextIndex = (afterIndex + 1) % count;
    final restAfter = anchors[afterIndex];
    final restNext = anchors[nextIndex];
    final nextId = restNext.id;

    // The rest-pose split, which is what an UNTRACKED node renders after the
    // insert, and the tangents the topology carries for missing-pose fallback.
    final restSplit = _deCasteljau(
      restAfter.position,
      restAfter.position + restAfter.outTangent,
      restNext.position + restNext.inTangent,
      restNext.position,
      u,
    );
    final newId = AnchorId(uuidV4());
    final newAnchor = Anchor(
      id: newId,
      position: restSplit.pos,
      inTangent: restSplit.inT,
      outTangent: restSplit.outT,
      kind: AnchorKind.smooth,
    );

    final newRestAnchors = <Anchor>[];
    for (var i = 0; i < count; i++) {
      var x = anchors[i];
      if (i == afterIndex) x = x.copyWith(outTangent: restSplit.leftOut);
      if (i == nextIndex) x = x.copyWith(inTangent: restSplit.rightIn);
      newRestAnchors.add(x);
      // Draw position: immediately after `after`. For the closed wrap this is a
      // plain append, which is exactly `after` being the last index.
      if (i == afterIndex) newRestAnchors.add(newAnchor);
    }
    final newTopology =
        PathData(anchors: newRestAnchors, closed: node.path.closed);

    PathPose splitPose(PathPose pose) {
      // Read the cubic from THIS keyframe's own poses, falling back to the rest
      // anchor for a partial pose (invariant P5 permits a subset) — the same
      // fallback the evaluator applies, so the split matches what renders.
      final ap = pose.anchors[after] ??
          AnchorPose(
              restAfter.position, restAfter.inTangent, restAfter.outTangent);
      final np = pose.anchors[nextId] ??
          AnchorPose(
              restNext.position, restNext.inTangent, restNext.outTangent);
      final s = _deCasteljau(
        ap.position,
        ap.position + ap.outTangent,
        np.position + np.inTangent,
        np.position,
        u,
      );
      return PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
        for (final x in newTopology.anchors)
          x.id: x.id == newId
              ? AnchorPose(s.pos, s.inT, s.outT)
              : x.id == after
                  ? AnchorPose(ap.position, ap.inTangent, s.leftOut)
                  : x.id == nextId
                      ? AnchorPose(np.position, s.rightIn, np.outTangent)
                      : pose.anchors[x.id] ??
                          AnchorPose(x.position, x.inTangent, x.outTangent),
      }));
    }

    return (_rewriteTopology(d, n, newTopology, splitPose), newId);
  }

  /// **TOPOLOGY edit: DOCUMENT-WIDE for the node** — remove one anchor
  /// (AC-4.3.5).
  ///
  /// Drops [a] from [n]'s `PathData` **and** from every keyframe pose of every
  /// path track for [n], across every animation. The neighbour tangents are
  /// **not** auto-repaired: removing a mid-curve anchor changes the shape, which
  /// is expected — faking continuity would be a silent geometry edit.
  ///
  /// **The floor is 0.** Invariant P2 declares a 0- or 1-anchor path legal (it
  /// renders nothing and never throws), so there is no non-trivial minimum to
  /// refuse below — deleting the last anchor yields the legal empty path, which
  /// the pen tool's first click also produces and which undo restores. The only
  /// refusal is an anchor that is not in the topology.
  ///
  /// The result still satisfies AC-4.3.6 (identical sequence across all keys),
  /// nulls the node's recipe (a topology edit no recipe can regenerate), and is a
  /// pure read of [d].
  ///
  /// Throws [ArgumentError] for an unknown node, a node that is not a [PathNode],
  /// or an anchor not in the topology.
  static Document deleteAnchor(Document d, NodeId n, AnchorId a) {
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

    final newTopology = PathData(
      anchors: <Anchor>[
        for (final x in node.path.anchors)
          if (x.id != a) x
      ],
      closed: node.path.closed,
    );

    PathPose dropPose(PathPose pose) =>
        PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
          for (final x in newTopology.anchors)
            x.id: pose.anchors[x.id] ??
                AnchorPose(x.position, x.inTangent, x.outTangent),
        }));

    return _rewriteTopology(d, n, newTopology, dropPose);
  }

  /// **TOPOLOGY edit: DOCUMENT-WIDE for the node** — replace the whole anchor set
  /// onto a new id set by **arc-length correspondence** (AC-4.3.7).
  ///
  /// The **only** route besides [insertAnchor]/[deleteAnchor] an anchor set may
  /// change. Recipe regeneration on a tracked node, paste-replace-geometry, and
  /// the importer's per-keyframe-count repair (AC-11.3.5) all route here. Runs
  /// **once per edit, never inside the tick** — it is a mutation op called from a
  /// command, not an evaluator stage.
  ///
  /// [newTopology] becomes the node's rest `PathData` verbatim (its authored
  /// positions, tangents, ids and `closed`). For each keyframe of each path track
  /// for [n], every new anchor is repositioned by correspondence: the new
  /// anchor's arc-length **fraction** along [newTopology] is mapped to the same
  /// fraction along *that keyframe's own* old geometry (resolved from its pose
  /// over the current topology), and the point sampled there becomes the new
  /// anchor's keyframe position.
  ///
  /// **Tangent policy.** Correspondence samples *positions*; the new anchors
  /// carry [newTopology]'s rest tangents into every keyframe. This is the honest,
  /// coarse morph docs/v3/01 §13.1 describes ("anchor-correspondence morphing,
  /// not automatic shape matching") — a square whose corners are all zero-tangent
  /// resamples exactly as a polygon through the sampled points, and a curved
  /// target keeps its authored handle character along the morph. Old per-keyframe
  /// tangent detail cannot map onto a disjoint id set and is not preserved.
  ///
  /// Afterwards AC-4.3.6 holds on the new id set: every keyframe poses exactly
  /// [newTopology]'s sequence, in order. Nulls the node's recipe and is a pure
  /// read of [d].
  ///
  /// Throws [ArgumentError] for an unknown node or a node that is not a
  /// [PathNode].
  static Document retopologize(Document d, NodeId n, PathData newTopology) {
    final found = d.nodeIndex[n];
    if (found is! PathNode) {
      throw ArgumentError.value(
          n.v, 'node', found == null ? 'no such node' : 'is not a path node');
    }
    final node = found;

    // Arc-length fraction of each NEW anchor along the NEW path — computed once.
    final newFractions = _ArcTable.build(newTopology).anchorFractions();

    PathPose resample(PathPose oldPose) {
      // The old geometry THIS keyframe draws, resolved over the current topology.
      final table = _ArcTable.build(_poseGeometry(node.path, oldPose));
      return PathPose(Map.unmodifiable(<AnchorId, AnchorPose>{
        for (var i = 0; i < newTopology.anchors.length; i++)
          newTopology.anchors[i].id: AnchorPose(
            table.pointAtFraction(newFractions[i]),
            newTopology.anchors[i].inTangent,
            newTopology.anchors[i].outTangent,
          ),
      }));
    }

    return _rewriteTopology(d, n, newTopology, resample);
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

/// The shared spine of the three M5 topology edits: replace [n]'s topology with
/// [newTopology] AND rewrite every keyframe of every path track for [n], across
/// every animation, through [transform] — in one returned document, so the whole
/// edit is **one undo entry** (AC-4.3.3) and a pure read of [d].
///
/// [transform] receives one keyframe's old [PathPose] and returns the pose on
/// the new topology; each of insert/delete/retopologize supplies its own. Only
/// path tracks for [n] are touched — every other node, track and animation rides
/// through byte-identical. Nulls the recipe, because all three change the anchor
/// set no recipe can regenerate (docs/v3/01 §5).
Document _rewriteTopology(
  Document d,
  NodeId n,
  PathData newTopology,
  PathPose Function(PathPose) transform,
) =>
    d.copyWith(
      root: _replacePath(
          d.root, n, (p) => p.copyWith(path: newTopology, clearRecipe: true)),
      animations: <Animation>[
        for (final animation in d.animations)
          _rewriteAnimation(animation, n, transform),
      ],
    );

/// One animation with [n]'s path-track keyframes remapped through [transform],
/// or the animation unchanged when it has no path track for [n].
///
/// `t` and `easing` ride across untouched — a topology edit is not a retime, and
/// the key list stays strictly increasing so [PathTrack.withKeys]'s `_validated`
/// pass cannot reject it.
Animation _rewriteAnimation(
    Animation animation, NodeId n, PathPose Function(PathPose) transform) {
  final tracks = animation.tracksFor(n);
  final base = tracks.pathTrack();
  if (base == null) return animation;
  final track = base.withKeys(<Keyframe<PathPose>>[
    for (final k in base.keys)
      Keyframe<PathPose>(t: k.t, easing: k.easing, value: transform(k.value)),
  ]);
  return animation.copyWith(
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
}

/// The pieces of a de Casteljau split of the cubic [p0]..[p3] at parameter [u]
/// that a topology insert needs (docs/v3/01 §13.5).
///
/// The new anchor sits at [pos] with handles [inT]/[outT]; the left neighbour's
/// outgoing handle becomes [leftOut] and the right neighbour's incoming handle
/// [rightIn]. The two sub-cubics `[p0, p0+leftOut, pos+inT, pos]` and
/// `[pos, pos+outT, p3+rightIn, p3]` reproduce [p0]..[p3] exactly, which is why
/// the insert is pixel-identical (AC-4.3.2).
({Vec2 pos, Vec2 inT, Vec2 outT, Vec2 leftOut, Vec2 rightIn}) _deCasteljau(
    Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final q0 = Vec2.lerp(p0, p1, u);
  final q1 = Vec2.lerp(p1, p2, u);
  final q2 = Vec2.lerp(p2, p3, u);
  final r0 = Vec2.lerp(q0, q1, u);
  final r1 = Vec2.lerp(q1, q2, u);
  final s = Vec2.lerp(r0, r1, u);
  return (
    pos: s,
    inT: r0 - s,
    outT: r1 - s,
    leftOut: q0 - p0,
    rightIn: q2 - p3,
  );
}

/// A [PathData] whose anchors carry [pose]'s values (rest fallback for a missing
/// entry) — the geometry one keyframe actually draws over [topology]. Equivalent
/// to a single-bracket `resolveNodePose`, inlined here so the mutation op does
/// not depend on the evaluator's degenerate-bracket shape.
PathData _poseGeometry(PathData topology, PathPose pose) {
  final anchors = <Anchor>[];
  for (final x in topology.anchors) {
    final p =
        pose.anchors[x.id] ?? AnchorPose(x.position, x.inTangent, x.outTangent);
    anchors.add(x.copyWith(
        position: p.position,
        inTangent: p.inTangent,
        outTangent: p.outTangent));
  }
  return PathData(anchors: anchors, closed: topology.closed);
}

/// A cumulative arc-length table over an immutable [PathData], built by adaptive
/// flattening (docs/v3/01 §5). Used by [PathOps.retopologize] for arc-length
/// correspondence.
///
/// Correct, not fast: it is built once per edit (never in the tick), and rebuilt
/// per keyframe because each keyframe draws different geometry. M6's trim needs
/// the same machinery **memoised per immutable `PathData`**; hoisting this onto
/// `PathData` is that milestone's, and is why it lives as a plain helper here
/// rather than baked into a public API this milestone would have to guess at.
class _ArcTable {
  _ArcTable(this._points, this._cumulative, this._total, this._anchorArc);

  /// Flattened polyline of the whole path, in draw order.
  final List<Vec2> _points;

  /// Cumulative arc length at each entry of [_points]. `_cumulative[0] == 0`.
  final List<double> _cumulative;

  final double _total;

  /// Arc length at each anchor (the start of its outgoing segment; the final
  /// anchor of an open path sits at [_total]).
  final List<double> _anchorArc;

  /// Flatness tolerance in document units. Well below any downstream raster
  /// tolerance, so the sampled length is exact for a correspondence morph.
  static const double _tolerance = 0.01;
  static const int _maxDepth = 20;

  static _ArcTable build(PathData path) {
    final points = <Vec2>[];
    final cumulative = <double>[];
    final anchorArc = <double>[];

    if (path.segmentCount == 0) {
      // 0 or 1 anchor renders nothing (invariant P2); every fraction collapses
      // to the single point (or the origin for the empty path).
      for (final a in path.anchors) {
        anchorArc.add(0.0);
        if (points.isEmpty) {
          points.add(a.position);
          cumulative.add(0.0);
        }
      }
      return _ArcTable(points, cumulative, 0.0, anchorArc);
    }

    var length = 0.0;
    points.add(path.segment(0).$1);
    cumulative.add(0.0);
    for (var k = 0; k < path.segmentCount; k++) {
      anchorArc.add(length); // arc at anchor k (start of segment k)
      final (p0, p1, p2, p3) = path.segment(k);
      final flat = <Vec2>[];
      _flatten(p0, p1, p2, p3, 0, flat);
      for (final pt in flat) {
        length += (pt - points.last).length;
        points.add(pt);
        cumulative.add(length);
      }
    }
    // An open path has one more anchor than segments; it sits at the far end.
    if (!path.closed) anchorArc.add(length);
    return _ArcTable(points, cumulative, length, anchorArc);
  }

  /// The arc-length fraction `[0,1]` of each anchor, in topology order.
  List<double> anchorFractions() => <double>[
        for (final a in _anchorArc) _total <= 0.0 ? 0.0 : a / _total,
      ];

  /// The point at arc-length fraction [f] along the flattened path.
  Vec2 pointAtFraction(double f) {
    if (_points.isEmpty) return Vec2.zero;
    if (_points.length == 1 || _total <= 0.0) return _points.first;
    final target = f.clamp(0.0, 1.0) * _total;
    for (var i = 1; i < _cumulative.length; i++) {
      if (_cumulative[i] >= target) {
        final span = _cumulative[i] - _cumulative[i - 1];
        final t = span <= 0.0 ? 0.0 : (target - _cumulative[i - 1]) / span;
        return Vec2.lerp(_points[i - 1], _points[i], t);
      }
    }
    return _points.last;
  }

  /// Adaptive subdivision of one cubic, emitting the points **after** [p0] up to
  /// and including [p3]. The classic control-point-deviation flatness test.
  static void _flatten(
      Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, int depth, List<Vec2> out) {
    if (depth >= _maxDepth || _flatEnough(p0, p1, p2, p3)) {
      out.add(p3);
      return;
    }
    final p01 = Vec2.lerp(p0, p1, 0.5);
    final p12 = Vec2.lerp(p1, p2, 0.5);
    final p23 = Vec2.lerp(p2, p3, 0.5);
    final p012 = Vec2.lerp(p01, p12, 0.5);
    final p123 = Vec2.lerp(p12, p23, 0.5);
    final mid = Vec2.lerp(p012, p123, 0.5);
    _flatten(p0, p01, p012, mid, depth + 1, out);
    _flatten(mid, p123, p23, p3, depth + 1, out);
  }

  static bool _flatEnough(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3) {
    var ux = 3.0 * p1.x - 2.0 * p0.x - p3.x;
    ux *= ux;
    var uy = 3.0 * p1.y - 2.0 * p0.y - p3.y;
    uy *= uy;
    var vx = 3.0 * p2.x - p0.x - 2.0 * p3.x;
    vx *= vx;
    var vy = 3.0 * p2.y - p0.y - 2.0 * p3.y;
    vy *= vy;
    if (ux < vx) ux = vx;
    if (uy < vy) uy = vy;
    return ux + uy <= 16.0 * _tolerance * _tolerance;
  }
}
