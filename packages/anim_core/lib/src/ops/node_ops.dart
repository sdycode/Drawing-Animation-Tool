/// Tree-structure mutations (docs/v3/01 §3, §4, §12; F2.1).
///
/// **Pure document surgery.** Every method is `Document → Document`, throws
/// loudly on a precondition violation, and knows nothing about selection, hover,
/// the viewport, or any other editor concept — those live in `EditorState` and
/// reach `anim_core` through nothing at all (docs/v3/08 §1, §2). In particular
/// an op here NEVER clears `EditorState.selectedNodes` "to be safe": a dangling
/// selection id is legal and is filtered at every read site, and reaching for
/// the editor's types from here would grow `anim_core` a dependency it exists to
/// forbid. Selection is resolved, never repaired.
///
/// These are the three ops M2's undo wraps into single [CommandStack] entries
/// (the wrapper is the app's, phase 2): a [duplicateSubtree] that re-mints a
/// hundred ids is still ONE undo entry, which is only possible because the op
/// returns one whole new `Document` rather than mutating in place.
///
/// Ops throw; the command layer catches (docs/v3/08 §1). Match `PathOps`'
/// `abstract final class` + tree-rebuild style.
library;

import 'dart:math' as math;

import '../affine.dart';
import '../animation.dart';
import '../document.dart';
import '../eval/evaluate.dart';
import '../eval/scene.dart';
import '../node.dart';
import '../path.dart';
import '../primitives.dart';
import '../track.dart';
import '../uuid.dart';

abstract final class NodeOps {
  /// Wrap [members] in a fresh [GroupNode] without moving a single pixel
  /// (AC-2.1.3, F2.1).
  ///
  /// **Precondition 1:** every member is a **sibling** — a direct child of one
  /// shared parent — in v1. Grouping across parents is a reparent *and* a group,
  /// two world-preserving transforms, and doing them implicitly here is how a
  /// "group these" gesture silently teleports half the selection. Violating it
  /// throws [ArgumentError] rather than picking a parent.
  ///
  /// **Precondition 2 — the members are CONTIGUOUS in `parent.children`.**
  /// The members keep their existing draw order and become the group's
  /// children; the group takes the slot of the back-most member so the group as
  /// a whole occupies the z-range its contents used to. That sentence is only
  /// true when nothing else sits between them: for `[M1, MID, M2]`, grouping
  /// `M1` and `M2` yields the draw order `[group(M1, M2), MID]`, which pushes
  /// `MID` *behind* both — every member's own `ResolvedNode` stays
  /// bit-identical (AC-2.1.3 is about the members) while the composite render
  /// changes, silently, for a node the user did not even select. Preserving the
  /// composite is not available: a group's children are drawn contiguously by
  /// construction, so no placement of a group containing `M1` and `M2` can keep
  /// `MID` between them. The only honest options are "reject" and "reorder
  /// someone else's z", so this throws [ArgumentError] and lets the caller
  /// decide (docs/v3/08 §1 — loud failure is the product).
  ///
  /// Because a `GroupNode` with an identity `transform` composes to the
  /// identity `Affine` **regardless of its pivot** (pivot appears twice with
  /// opposite sign in `Transform2.toAffine` and cancels when rotation/scale/skew
  /// are all identity), `world(member)` is unchanged and every member renders
  /// pixel-identically. The scene digest before and after is equal on every
  /// member — asserted, because "grouping moved my shapes" is the first thing an
  /// animator would notice.
  ///
  /// The group's **pivot** is the centre of the union AABB of the members'
  /// geometry, expressed in the group's own (== the parent's) local space — NOT
  /// `Vec2.zero`. `Vec2.zero` is the artboard's top-left corner in
  /// artboard-relative space, so a group pivoted there would rotate about the
  /// corner the moment anyone keyed its rotation. The AABB is measured from each
  /// member subtree's **evaluated** geometry (through the real evaluator, at the
  /// rest pose) and each cubic is bounded **exactly** — see
  /// [_accumulateGeometry], which replaced a 16-sample polyline that under-bound
  /// every curve's bulge and so placed the pivot off the AABB centre AC-2.1.3
  /// names.
  static Document createGroup(Document d, List<NodeId> members) {
    if (members.isEmpty) {
      throw ArgumentError.value(members, 'members', 'need at least one member');
    }

    // ONE index build and ONE parent walk per call, hoisted out of the member
    // loops below: `Document.nodeIndex` re-walks the whole tree on every access
    // (docs/v3/08 §4 forbids caching it *on* `Document`, so the fix is here).
    final nodes = d.nodeIndex;
    final parents = _parentIndex(d.root);
    final parent = _requireCommonParent(parents, members);
    final memberSet = members.toSet();
    _requireContiguous(parent, memberSet);

    // Rest-pose scene: reuses composeWorldA for the world matrices and
    // resolvePose for the posed geometry. No private world walk lives here.
    final scene = evaluate(d, const <AnimationMix>[]);
    final parentWorld = _worldOf(scene, parent.id, 'members');
    final pivot = _unionPivot(nodes, scene, parentWorld, members);

    final group = GroupNode(
      id: NodeId(uuidV4()),
      name: 'Group',
      transform: Transform2(pivot: pivot),
      // Existing draw order, filtered to the members.
      children: <Node>[
        for (final c in parent.children)
          if (memberSet.contains(c.id)) c,
      ],
    );

    return d.copyWith(
      root: _editGroup(d.root, parent.id, (g) {
        final next = <Node>[];
        var placed = false;
        for (final c in g.children) {
          if (memberSet.contains(c.id)) {
            if (!placed) {
              next.add(group);
              placed = true;
            }
            continue; // the member now lives inside `group`
          }
          next.add(c);
        }
        return g.copyWith(children: next);
      }),
    );
  }

  /// Move [n] under [newParent] at [index] **without moving it on screen**
  /// (AC-2.1.4, docs/v3/05 §4.5).
  ///
  /// World-preserving: `newLocal = newParent.world.invert() · oldWorld`, then
  /// `Affine.decompose` back into a `Transform2` about the node's existing
  /// pivot. Without the decompose step a reparent either visually teleports the
  /// node (keeping its old local transform under a new parent) or bakes a wrong
  /// matrix it can no longer author — both are the legacy "drag a layer into a
  /// group and watch it jump" defect.
  ///
  /// **What "world-preserving" is preserving.** The solve runs on the REST pose
  /// (`evaluate(d, const [])`), and it writes the answer into the node's rest
  /// `Transform2`. That is exact only while the rendered pose *is* the rest
  /// pose. A track OVERWRITES its property at sample time (see `sampleTracks`),
  /// so on a node carrying a `position`/`scale`/`rotation`/`skewX` track the
  /// rewritten pose value is discarded for that channel at every playhead and
  /// the node teleports — measured at 156.2 document units on a 450.2×250.4
  /// artboard, 35% of the board, for a single `Vec2Track` on `position`. The
  /// same is true when the *frame change itself* is animated: `C(t) =
  /// newParentWorld(t)⁻¹ · oldParentWorld(t)` is only constant when nothing
  /// between the two parents' lowest common ancestor and each of them is
  /// transform-animated (a shared ancestor cancels out of `C` and is fine).
  ///
  /// **Decision — refuse, do not approximate (option (a)).** Fixing this
  /// properly means rewriting every transform keyframe as well as the pose, and
  /// that rewrite cannot be made exact: `newLocal(t) = C · local(t)` re-enters
  /// the pose parameterisation through `decompose`, whose rotation/scale/skew
  /// are *non-linear* in the sampled channel values unless `C` is a similarity
  /// (rotation + uniform scale + translation). For a non-uniform `C` the only
  /// achievable result is "exact at each keyframe, drifting in between", and it
  /// would additionally have to mint `scale`/`skewX`/`position` tracks the user
  /// never authored on a node that only had `rotation`. Per-keyframe rewriting
  /// lands with M4, where transform-track authoring lands and where the
  /// trade-off is a product decision with a UI to explain it. Until then a loud
  /// [ArgumentError] is the product (docs/v3/08 §1); a silent 156-unit teleport
  /// is not. M2 has no transform-track authoring, so this refusal is
  /// unreachable from the shipped UI.
  ///
  /// Refusals, all [ArgumentError] rather than a silent teleport:
  /// - [n] is the root, or is unknown;
  /// - [newParent] is unknown or is not a [GroupNode] (only groups hold
  ///   children);
  /// - [newParent] is [n] itself or a **descendant** of [n] — a cycle, which
  ///   would detach the subtree from the document entirely;
  /// - [n] carries a transform track in ANY animation, or the frame change
  ///   between the two parents is itself transform-animated (above);
  /// - `newParent.world.invert()` is null — a collapsed new parent has no
  ///   coordinate frame to drop into, and that is the ONE singular case with no
  ///   solution at all.
  ///
  /// A singular **source** world is NOT a refusal (see [_solvePose]): a node
  /// under a group whose scale is keyed to 0, or one legitimately flattened to
  /// `scale (1,0)`, is representable exactly as `scale.x == 0` / `scale.y == 0`
  /// and must stay rescuable — refusing there made a collapsed group a one-way
  /// trap whose children could not be dragged out, not even to the root, and it
  /// blamed [n] for its ancestor's matrix.
  ///
  /// [index] clamps into [newParent]'s child list (measured after [n] is
  /// removed, so reordering within one parent addresses the post-removal slots).
  static Document reparent(Document d, NodeId n, NodeId newParent, int index) {
    if (n == d.root.id) {
      throw ArgumentError.value(n.v, 'n', 'the root cannot be reparented');
    }
    // ONE index build per call — `Document.nodeIndex` re-walks the tree on
    // every access and this op used to read it twice (defect: O(n·m)).
    final nodes = d.nodeIndex;
    final node = nodes[n];
    if (node == null) {
      throw ArgumentError.value(n.v, 'n', 'no such node');
    }
    final target = nodes[newParent];
    if (target is! GroupNode) {
      throw ArgumentError.value(newParent.v, 'newParent',
          target == null ? 'no such node' : 'is not a group');
    }
    // Cycle: dropping a node inside its own subtree orphans that subtree.
    if (_subtreeIds(node).contains(newParent)) {
      throw ArgumentError.value(newParent.v, 'newParent',
          'is $n or one of its descendants (a cycle)');
    }
    _requireStaticFrames(d, n, newParent);

    final scene = evaluate(d, const <AnimationMix>[]);
    final oldWorld = _worldOf(scene, n, 'n');
    final newParentWorld = _worldOf(scene, newParent, 'newParent');

    final inv = newParentWorld.invert();
    if (inv == null) {
      throw ArgumentError.value(newParent.v, 'newParent',
          'has a singular world matrix — a reparent into it would teleport $n');
    }
    final newLocal = inv.mul(oldWorld);
    // Solve about the node's existing pivot: pivot is authored once and is not
    // animatable (docs/v3/01 §4), so reparent carries it across rather than
    // re-deriving it. `decompose` is surjective for a non-singular matrix, so
    // any pivot reproduces `newLocal`; keeping the node's own is the honest one.
    final solved = _solvePose(newLocal, node.transform);
    if (solved == null) {
      throw ArgumentError.value(
          newParent.v,
          'newParent',
          'newParent⁻¹ · world(${n.v}) is singular along neither axis alone — '
              'an ancestor collapses one axis of a rotated frame, which no '
              'Transform2 expresses. The singularity is in the transform '
              'chain, not in ${n.v}\'s own transform');
    }

    final moved = _withTransform(node, solved);
    final removed = _removeNode(d.root, n);
    return d.copyWith(
      root: _editGroup(removed, newParent, (g) {
        final at = index.clamp(0, g.children.length);
        final kids = <Node>[...g.children];
        kids.insert(at, moved);
        return g.copyWith(children: kids);
      }),
    );
  }

  /// Deep-copy the subtree at [n] under **fresh ids**, inserted as [n]'s next
  /// sibling (AC-2.1.5, F2.1).
  ///
  /// Re-mints every [NodeId] and every [AnchorId] in the subtree and deep-copies
  /// the matching `TrackSet` entries — across **every** animation — under the
  /// new ids, so that animating the copy leaves the original untouched. Without
  /// this, copy/paste of a group yields two subtrees sharing `NodeId`s, both
  /// driven by the same `TrackSet`, with no way to animate them apart — the
  /// exact defect docs/v3/01 §12 names.
  ///
  /// The remap is built as one `Map<NodeId,NodeId>` and one
  /// `Map<AnchorId,AnchorId>` over the whole subtree **first**, then applied to
  /// (a) the node tree, (b) every `AnchorId` inside each `PathData`, and (c)
  /// every `Animation`'s tracks — both the `NodeId` key of each `TrackSet` and
  /// every `AnchorId` inside every `PathPose` of every `PathTrack`. A `PathPose`
  /// that posed an old anchor id the remap missed would be a silent orphan the
  /// decoder drops on the next load; the [PathData] validating factory and the
  /// remapped poses together make every copy keyframe pose exactly the copy's
  /// own anchor ids.
  ///
  /// **Decision — `PaintId`s are NOT re-minted.** `PropertyKey.subjectId` can
  /// carry a `PaintId` (a fill/stroke channel), and the copy's fills and strokes
  /// keep their original `PaintId`s. A `PaintId` is unique only *within a node*,
  /// and the copy is a different `NodeId`, so there is no collision to fix.
  /// Re-minting them would additionally strand every `fillColor:p-…` /
  /// `strokeWidth:p-…` track key, which addresses paint by that id. This is
  /// deliberate; do not "fix" it.
  ///
  /// **Decision — `TrackSet.unknownKeys` IS remapped.** A track this build could
  /// not type (an unknown property name, an unknown track kind, a type
  /// mismatch) is preserved raw and re-emitted verbatim on save (docs/v3/02 §7).
  /// Copied byte-for-byte onto the duplicate it would be the last shared-id path
  /// left between original and copy: a raw path track on the COPY still naming
  /// the ORIGINAL's `AnchorId`s, invisible to decode's orphan-pose repair (which
  /// only inspects typed `PathTrack`s) and therefore permanent across every save
  /// and reload. So the remap is applied *inside* the raw blob, by exact string
  /// match on the anchor ids this op just re-minted, over map keys and string
  /// values alike — a v4 uuid cannot collide with an unrelated string, and the
  /// substitution is a no-op for a raw entry that never mentions one. This is
  /// the same trade [_cloneNode] already makes for `UnknownNode.raw['id']`:
  /// verbatim preservation stops exactly where it would resurrect an id that
  /// belongs to another node. What is NOT rewritten is the raw entry's shape,
  /// its keys, or anything else — an unrecognised structure survives untouched.
  ///
  /// [n] must not be the root (the root has no sibling slot).
  static Document duplicateSubtree(Document d, NodeId n) {
    if (n == d.root.id) {
      throw ArgumentError.value(n.v, 'n', 'the root has no sibling to copy to');
    }
    // The parent walk answers "does it exist" and "where does the copy go" in
    // one pass, so `Document.nodeIndex` is never built here at all.
    final parent = _parentIndex(d.root)[n];
    if (parent == null) {
      throw ArgumentError.value(n.v, 'n', 'no such node');
    }
    final source = parent.children.firstWhere((c) => c.id == n);

    // One remap over the whole subtree, built before anything is rewritten so
    // the tree, the anchors and the tracks all agree on the new ids.
    final nodeMap = <NodeId, NodeId>{};
    final anchorMap = <AnchorId, AnchorId>{};
    _buildRemap(source, nodeMap, anchorMap);

    final copy = _cloneNode(source, nodeMap, anchorMap);

    final root = _editGroup(d.root, parent.id, (g) {
      final kids = <Node>[...g.children];
      final at = kids.indexWhere((c) => c.id == n);
      kids.insert(at + 1, copy);
      return g.copyWith(children: kids);
    });

    final animations = <Animation>[
      for (final a in d.animations) _cloneTracks(a, nodeMap, anchorMap),
    ];

    return d.copyWith(root: root, animations: animations);
  }

  /// Overwrite [n]'s [Transform2] wholesale — the transform-authoring write
  /// (F3.1, docs/v3/01 §4).
  ///
  /// The inspector's position / scale / pivot / rotation / skewX fields commit
  /// through here as one `Document → Document`. Unlike [reparent] this is **not**
  /// world-preserving: it is a direct authored write, so typing a rotation or
  /// dragging a gizmo moves the node exactly as asked rather than inverting a
  /// parent frame. Selecting *where* the write lands (a track keyframe vs the
  /// static pose) is the caller's job (docs/v3/05 §3) — this op only replaces
  /// the node's own rest `Transform2`.
  ///
  /// Throws [ArgumentError] on an unknown node, or on an [UnknownNode] (whose
  /// verbatim raw-JSON re-emit would silently drop a typed transform — the same
  /// reason [reparent] refuses one).
  static Document setTransform(Document d, NodeId n, Transform2 t) {
    final node = d.nodeIndex[n];
    if (node == null) {
      throw ArgumentError.value(n.v, 'n', 'no such node');
    }
    return d.copyWith(
      root: node.id == d.root.id
          ? _withTransform(d.root, t) as GroupNode
          : _replaceNode(d.root, n, (x) => _withTransform(x, t)),
    );
  }

  /// Rename [n] — the layers-panel rename (F2.2, docs/v3/05 §2).
  ///
  /// `name` is structural, not visual, state (docs/v3/01 §7 lists it under "not
  /// animatable"), so it is a plain field write with no track backfill. Throws
  /// [ArgumentError] on an unknown node, or on an [UnknownNode] whose name lives
  /// in raw JSON and would not survive the typed write.
  static Document setName(Document d, NodeId n, String name) {
    final node = d.nodeIndex[n];
    if (node == null) {
      throw ArgumentError.value(n.v, 'n', 'no such node');
    }
    return d.copyWith(
      root: node.id == d.root.id
          ? _withName(d.root, name) as GroupNode
          : _replaceNode(d.root, n, (x) => _withName(x, name)),
    );
  }

  /// Set [n]'s authored `visible` flag — the layers-panel eye toggle (F2.2,
  /// docs/v3/05 §2, AC-2.2.4).
  ///
  /// `visible` is **authored and persisted** and ANDs down the tree at
  /// evaluation, so a group hidden here hides every descendant regardless of the
  /// descendant's own `visible` or `BoolTrack` (docs/v3/01 §3). This op only
  /// writes the one field; the AND is the evaluator's, and there is no second
  /// "effective visibility" copy stored beside it to desync — the exact class of
  /// derived-state bug docs/v3/08 §4 forbids. Idempotent: writing the value a
  /// node already holds returns the same document.
  ///
  /// Throws [ArgumentError] on an unknown node, or on an [UnknownNode] whose flag
  /// lives in raw JSON and would be dropped by a typed write (as [setName] does).
  static Document setVisible(Document d, NodeId n, bool visible) {
    final node = d.nodeIndex[n];
    if (node == null) {
      throw ArgumentError.value(n.v, 'n', 'no such node');
    }
    if (node.visible == visible) return d; // idempotent no-op
    return d.copyWith(
      root: node.id == d.root.id
          ? _withVisible(d.root, visible) as GroupNode
          : _replaceNode(d.root, n, (x) => _withVisible(x, visible)),
    );
  }

  /// Set [n]'s authored `opacity` — the inspector's opacity field (F2.2,
  /// AC-2.2.5).
  ///
  /// Writes **one node's own** value. The PRODUCT down the ancestor chain is the
  /// evaluator's (docs/v3/01 §3), computed per frame in `composeWorldA`, so
  /// there is no derived "effective opacity" anywhere to keep in sync — storing
  /// one would be the docs/v3/08 §4 antipattern, and it is exactly the shape of
  /// desync legacy shipped.
  ///
  /// Clamped to `0..1` **here, at the mutation**, not at read: the evaluator
  /// clamps the *sampled* value because a track may legitimately overshoot
  /// through an easing curve, but an authored 1.7 is a bad write and belongs
  /// rejected at the moment it is made. Idempotent, and it refuses an
  /// [UnknownNode] for the same reason [setName] does — that node re-emits its
  /// raw JSON verbatim, so a typed `opacity` written here would silently vanish.
  static Document setOpacity(Document d, NodeId n, double opacity) {
    final node = d.nodeIndex[n];
    if (node == null) {
      throw ArgumentError.value(n.v, 'n', 'no such node');
    }
    if (opacity.isNaN) {
      throw ArgumentError.value(opacity, 'opacity', 'must be a number');
    }
    final next = opacity.clamp(0.0, 1.0);
    if (node.opacity == next) return d; // idempotent no-op
    return d.copyWith(
      root: node.id == d.root.id
          ? _withOpacity(d.root, next) as GroupNode
          : _replaceNode(d.root, n, (x) => _withOpacity(x, next)),
    );
  }

  /// Set [n]'s authored `PathTrim` — the inspector's Trim fields (F8.1,
  /// AC-8.1.1).
  ///
  /// Writes **one `PathNode`'s own** `trim`. The evaluator's `applyTrim` (stage
  /// 7) reads it and reveals the geometry per frame (docs/v3/01 §5); this op only
  /// replaces the field, and there is no derived "effective trim" stored anywhere
  /// to desync (docs/v3/08 §4).
  ///
  /// Each of `start`/`end`/`offset` is clamped to `0..1` **here, at the
  /// mutation** — a fraction of total arc length outside `[0,1]` is a bad
  /// authored write, the same lesson [setOpacity] and `PaintOps.setStrokeWidth`
  /// learn — while a *sampled* track value the evaluator handles separately.
  /// `end <= start` is left as authored: it is not out of range, it renders
  /// nothing (docs/v3/01 §5), and clamping it would silently rewrite the user's
  /// window. Idempotent: writing the trim a node already holds returns the same
  /// document.
  ///
  /// Throws [ArgumentError] on an unknown node, on a **non-`PathNode`** (only a
  /// `PathNode` has a `trim` — a group or the root has nothing to reveal, and
  /// AC-8.1.10 is per-`PathNode`), and on an [UnknownNode] whose trim lives in
  /// raw JSON and would be dropped by a typed write (as [setOpacity] does).
  static Document setTrim(Document d, NodeId n, PathTrim trim) {
    final node = d.nodeIndex[n];
    if (node == null) {
      throw ArgumentError.value(n.v, 'n', 'no such node');
    }
    if (node is! PathNode) {
      throw ArgumentError.value(
          n.v, 'n', 'only a PathNode has a trim (AC-8.1.10 is per-PathNode)');
    }
    final next = PathTrim(
      start: trim.start.clamp(0.0, 1.0).toDouble(),
      end: trim.end.clamp(0.0, 1.0).toDouble(),
      offset: trim.offset.clamp(0.0, 1.0).toDouble(),
    );
    if (node.trim == next) return d; // idempotent no-op
    return d.copyWith(
      root:
          _replaceNode(d.root, n, (x) => (x as PathNode).copyWith(trim: next)),
    );
  }

  /// Set [n]'s authored `locked` flag — the layers-panel lock toggle (F2.2,
  /// docs/v3/05 §2, AC-2.2.6).
  ///
  /// `locked` is **editor-only** — persisted so it survives reload (unlike
  /// selection and hover), but **never read by the evaluator at any depth**
  /// (docs/v3/01 §3). It is a hit-test gate, so writing it changes what the
  /// canvas will select, not one pixel of playback. Idempotent, and it refuses
  /// an [UnknownNode] for the same reason [setName] does: that node re-emits its
  /// raw JSON verbatim on save, so a typed `locked` written here would silently
  /// vanish, and pretending the lock took is worse than throwing.
  static Document setLocked(Document d, NodeId n, bool locked) {
    final node = d.nodeIndex[n];
    if (node == null) {
      throw ArgumentError.value(n.v, 'n', 'no such node');
    }
    if (node.locked == locked) return d; // idempotent no-op
    return d.copyWith(
      root: node.id == d.root.id
          ? _withLocked(d.root, locked) as GroupNode
          : _replaceNode(d.root, n, (x) => _withLocked(x, locked)),
    );
  }

  /// Move the child at [oldIndex] to [newIndex] inside [parent]'s child list —
  /// the layers-panel drag-reorder within one parent (F2.2, docs/v3/05 §4.5,
  /// AC-2.2.2).
  ///
  /// **A pure child-list splice, and deliberately NOT a same-parent
  /// [reparent].** Z-order *is* child order (docs/v3/01 §3), so reordering must
  /// touch only the parent's `children` list and must leave the moved node's
  /// own `Transform2` byte-identical — a reorder is not a move. A same-parent
  /// [reparent] would reach the same *visible* result (`newLocal =
  /// parentWorld⁻¹ · parentWorld · local` is `local`), but it gets there by
  /// evaluating the scene, inverting the parent's world matrix and running
  /// `Affine.decompose` — which (a) **throws** when the parent's world is
  /// singular (an animator keyed its scale to 0), refusing a reorder that has
  /// nothing to do with that scale, and (b) round-trips the transform through
  /// decompose, perturbing the stored numbers and bloating the save diff for an
  /// edit that changed only list order. So this splice does none of that: no
  /// evaluate, no matrix, no transform touched, minimal diff. There is still no
  /// derived order array anywhere — the splice edits the one authoritative list.
  ///
  /// [newIndex] is **clamped** into the child list; [oldIndex] out of range, an
  /// unknown [parent], or a non-group [parent] each throw [ArgumentError], like
  /// the other ops. A move to the index it already occupies is a no-op and
  /// returns the same document (idempotent).
  static Document reorderChild(
      Document d, NodeId parent, int oldIndex, int newIndex) {
    final group = d.nodeIndex[parent];
    if (group is! GroupNode) {
      throw ArgumentError.value(parent.v, 'parent',
          group == null ? 'no such node' : 'is not a group');
    }
    final count = group.children.length;
    if (oldIndex < 0 || oldIndex >= count) {
      throw ArgumentError.value(
          oldIndex, 'oldIndex', 'out of range for $count children');
    }
    // The target is the final resting index in the resulting list, clamped so a
    // drop past either end pins to the end rather than throwing — a scrub bar
    // that leaves the rail pins, and a layer dragged past the top pins too.
    final target = newIndex.clamp(0, count - 1);
    if (target == oldIndex) return d;

    return d.copyWith(
      root: _editGroup(d.root, parent, (g) {
        final kids = <Node>[...g.children];
        final moved = kids.removeAt(oldIndex);
        kids.insert(target, moved);
        return g.copyWith(children: kids);
      }),
    );
  }
}

/// The world matrix [scene] resolved for [id], or a located [ArgumentError].
///
/// Exists to keep `scene.byPath[ScenePath(id)]!` out of this file. That bare
/// `!` is one of the five recurring frame-enders docs/v3/08 §4 names, and the
/// objection to it is not that it can fire here — every id reaching these call
/// sites is validated against `nodeIndex` first, and `composeWorldA` emits every
/// node reachable from the root, so the lookup is total. The objection is that
/// *the proof lives a traversal away from the call site*: it holds only while
/// both of those remain true, neither is local, and the day one changes the
/// failure is a `Null check operator used on a null value` with no id in it.
///
/// Throwing loudly with the id is the same contract every other precondition in
/// this file keeps (docs/v3/08 §1 — ops throw, the command layer catches).
Affine _worldOf(Scene scene, NodeId id, String argName) {
  final resolved = scene.byPath[ScenePath(id)];
  if (resolved == null) {
    throw ArgumentError.value(
        id.v, argName, 'is not present in the evaluated scene');
  }
  return resolved.world;
}

// ---------------------------------------------------------------------------
// createGroup — geometry
// ---------------------------------------------------------------------------

/// The single parent shared by every member, or an [ArgumentError].
///
/// Takes the prebuilt [parents] map rather than walking per member: the walk is
/// O(n) and doing it inside the member loop made grouping O(n·m) for no reason.
GroupNode _requireCommonParent(
    Map<NodeId, GroupNode> parents, List<NodeId> members) {
  GroupNode? parent;
  for (final m in members) {
    final p = parents[m];
    if (p == null) {
      throw ArgumentError.value(
          m.v, 'members', 'no such node (or it is the root)');
    }
    if (parent == null) {
      parent = p;
    } else if (parent.id != p.id) {
      throw ArgumentError.value(members.map((x) => x.v).toList(), 'members',
          'must be siblings under one parent (v1 precondition)');
    }
  }
  return parent!;
}

/// Refuses a member set with a non-member wedged between two members.
///
/// See [NodeOps.createGroup]: the group's children are drawn contiguously, so
/// there is no slot that keeps the interleaved non-member's z-position. The
/// members' own `ResolvedNode`s would still be bit-identical, which is why this
/// has to be a precondition and not an assertion on the members.
void _requireContiguous(GroupNode parent, Set<NodeId> memberSet) {
  final kids = parent.children;
  final first = kids.indexWhere((c) => memberSet.contains(c.id));
  final last = kids.lastIndexWhere((c) => memberSet.contains(c.id));
  if (last - first + 1 == memberSet.length) return;
  final between = <String>[
    for (var k = first + 1; k < last; k++)
      if (!memberSet.contains(kids[k].id)) kids[k].id.v,
  ];
  throw ArgumentError.value(
      memberSet.map((x) => x.v).toList(),
      'members',
      'are not contiguous in "${parent.name}" — ${between.join(", ")} sits '
          'between them and grouping would push it behind every member, '
          'changing the composite render of a node that was not selected');
}

/// The centre of the union AABB of every member subtree's evaluated geometry,
/// in the parent's local space (which is the new group's local space).
///
/// `parentWorld.invert() · world(descendant)` maps a descendant's local
/// geometry into the group's frame; the geometry itself and the world matrices
/// both come from [scene], so there is one world walk in this file and it is the
/// evaluator's.
///
/// [nodes] is the caller's ONE `Document.nodeIndex` build. Reading `d.nodeIndex`
/// inside the member loop re-walked the whole tree per member — the getter is
/// not memoised and (docs/v3/08 §4) must not be.
Vec2 _unionPivot(Map<NodeId, Node> nodes, Scene scene, Affine parentWorld,
    List<NodeId> members) {
  final pInv = parentWorld.invert();
  if (pInv == null) {
    // A collapsed parent has no usable frame; the pivot cannot be meaningfully
    // placed, so it falls back to the frame origin. The members still render
    // identically (the group is identity), so nothing is lost visually.
    return Vec2.zero;
  }

  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  var any = false;

  void add(Vec2 p) {
    any = true;
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }

  for (final m in members) {
    final memberNode = nodes[m]!;
    for (final node in _subtree(memberNode)) {
      if (node is! PathNode) continue;
      final resolved = scene.byPath[ScenePath(node.id)];
      final geometry = resolved?.geometry;
      if (geometry == null || geometry.anchors.isEmpty) continue;
      // descendant-local -> document -> group-local.
      final toGroup = pInv.mul(resolved!.world);
      _accumulateGeometry(geometry, toGroup, add);
    }
  }

  if (!any) return Vec2.zero;
  return Vec2((minX + maxX) / 2, (minY + maxY) / 2);
}

/// Grows the AABB accumulator by [geometry], mapped through [m].
///
/// Each cubic is bounded **exactly**, by the closed-form extrema of its
/// derivative: one quadratic per axis, roots kept only inside `(0,1)`, plus the
/// two endpoints. AC-2.1.3 says the group pivot *is* the union-AABB centre, and
/// the 16-sample polyline this replaced always under-bounds a curve's bulge (up
/// to 0.2610 doc units of centre error measured, ~0.52 units of content
/// displacement once the group is rotated 180°), so every later rotation or
/// scale keyed on the group pivoted about the wrong point.
///
/// The control points are mapped through [m] **first**: an affine image of a
/// cubic is the cubic of the mapped control points, so the extrema solved below
/// are the real curve's in the group's frame — not a polyline's, and not a box
/// grown in the wrong space. A `corner` anchor has zero tangents, which makes
/// its segment the degenerate cubic of a straight line and its derivative
/// linear, handled by the same solver.
void _accumulateGeometry(PathData geometry, Affine m, void Function(Vec2) add) {
  final anchors = geometry.anchors;
  if (anchors.length == 1) {
    add(m.apply(anchors.first.position));
    return;
  }
  for (var k = 0; k < geometry.segmentCount; k++) {
    final (q0, q1, q2, q3) = geometry.segment(k);
    final p0 = m.apply(q0),
        p1 = m.apply(q1),
        p2 = m.apply(q2),
        p3 = m.apply(q3);
    add(p0);
    add(p3);
    for (final u in _cubicExtrema(p0.x, p1.x, p2.x, p3.x)) {
      add(_cubicPoint(p0, p1, p2, p3, u));
    }
    for (final u in _cubicExtrema(p0.y, p1.y, p2.y, p3.y)) {
      add(_cubicPoint(p0, p1, p2, p3, u));
    }
  }
}

/// The parameters in `(0,1)` where one axis of the cubic `v0..v3` turns.
///
/// `B'(u)/3 = A·u² + B·u + C` with `A = -v0 + 3v1 - 3v2 + v3`,
/// `B = 2v0 - 4v1 + 2v2`, `C = v1 - v0`. A degenerate `A` is the linear case (a
/// straight or symmetric segment), not an error, and a negative discriminant
/// means the axis is monotone — both return nothing and leave the endpoints,
/// which [_accumulateGeometry] already added, as the bound.
List<double> _cubicExtrema(double v0, double v1, double v2, double v3) {
  final a = -v0 + 3 * v1 - 3 * v2 + v3;
  final b = 2 * v0 - 4 * v1 + 2 * v2;
  final c = v1 - v0;
  final out = <double>[];
  void keep(double u) {
    if (u > 0.0 && u < 1.0) out.add(u);
  }

  if (a.abs() < 1e-12) {
    if (b.abs() >= 1e-12) keep(-c / b);
    return out;
  }
  final disc = b * b - 4 * a * c;
  if (disc < 0.0) return out;
  final root = math.sqrt(disc);
  keep((-b + root) / (2 * a));
  keep((-b - root) / (2 * a));
  return out;
}

Vec2 _cubicPoint(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
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

// ---------------------------------------------------------------------------
// reparent — world preservation
// ---------------------------------------------------------------------------

/// The transform channels a track can OVERWRITE at sample time.
///
/// `opacity`, `visible`, `path` and the paint channels are not here on purpose:
/// none of them feeds `Transform2.toAffine`, so none of them can undo a solved
/// pose. `pivot` is not animatable at all (docs/v3/01 §4).
const Set<PropKey> _transformProps = <PropKey>{
  PropKey.position,
  PropKey.scale,
  PropKey.rotation,
  PropKey.skewX,
};

/// Whether any animation keys a transform channel on [id].
///
/// Only **typed** tracks count: an entry preserved raw in `TrackSet.unknownKeys`
/// is never evaluated (docs/v3/02 §7), so it cannot overwrite a solved pose in
/// this build and must not cost the user a refusal.
bool _isTransformAnimated(Document d, NodeId id) {
  for (final animation in d.animations) {
    for (final key in animation.tracksFor(id).byKey.keys) {
      if (_transformProps.contains(key.prop)) return true;
    }
  }
  return false;
}

/// Refuses a reparent whose world preservation would be solved on a pose the
/// evaluator is about to overwrite — see [NodeOps.reparent]'s decision note.
///
/// Two conditions, both required for `world(n)` to be stable at EVERY playhead
/// and not merely at the rest pose the solve reads:
///  1. [n] itself carries no transform track, so its rewritten pose is what
///     composes; and
///  2. `C(t) = newParentWorld(t)⁻¹ · oldParentWorld(t)` is constant, which holds
///     when nothing strictly between the two parents' lowest common ancestor and
///     each of them is transform-animated. Everything at or above the LCA
///     cancels out of `C` algebraically and is deliberately not checked — a
///     spinning root would otherwise block every reparent in the document.
void _requireStaticFrames(Document d, NodeId n, NodeId newParent) {
  if (_isTransformAnimated(d, n)) {
    throw ArgumentError.value(
        n.v,
        'n',
        'carries a transform track (position/scale/rotation/skewX), and a '
            'world-preserving reparent of a transform-animated node needs every '
            'keyframe rewritten, not just the rest pose — the pose this op '
            'would solve is overwritten by the track at every playhead and the '
            'node teleports. Per-keyframe rewriting lands with M4 '
            '(transform-track authoring)');
  }
  final parents = _parentIndex(d.root);
  final oldParent = parents[n];
  if (oldParent == null) return; // unreachable: the caller rejected the root
  for (final frame in _framesBetween(parents, oldParent.id, newParent)) {
    if (!_isTransformAnimated(d, frame)) continue;
    throw ArgumentError.value(
        newParent.v,
        'newParent',
        'the frame change is itself animated: "${frame.v}" lies between the two '
            'parents and carries a transform track, so newParent⁻¹ · oldParent '
            'is not the constant matrix a rest-pose solve assumes and ${n.v} '
            'would move at every playhead but t where the solve ran');
  }
}

/// The nodes whose local transforms make up `newParentWorld⁻¹ · oldParentWorld`
/// — the two root-relative chains with their common prefix removed.
List<NodeId> _framesBetween(
    Map<NodeId, GroupNode> parents, NodeId a, NodeId b) {
  final chainA = _chain(parents, a);
  final chainB = _chain(parents, b);
  var shared = 0;
  while (shared < chainA.length &&
      shared < chainB.length &&
      chainA[shared] == chainB[shared]) {
    shared++;
  }
  return <NodeId>[...chainA.skip(shared), ...chainB.skip(shared)];
}

/// [id] and its ancestors, root first.
List<NodeId> _chain(Map<NodeId, GroupNode> parents, NodeId id) {
  final out = <NodeId>[id];
  var cursor = parents[id];
  while (cursor != null) {
    out.add(cursor.id);
    cursor = parents[cursor.id];
  }
  return out.reversed.toList();
}

/// The `Transform2` that reproduces [local] about [previous]'s pivot.
///
/// Two departures from a bare `Affine.decompose`, each fixing a defect:
///
/// **Collapsed frames are solved, not refused.** `decompose` returns null for
/// any singular matrix, which made a group scaled to 0 a one-way trap: its
/// children could not be reparented anywhere, not even rescued to the root,
/// because the *ancestor's* singularity travelled into `newLocal`. Most of those
/// matrices are exactly representable — a collapsed first column IS
/// `scale.x == 0`, a collapsed second column IS `scale.y == 0` — so
/// [_decomposeCollapsed] solves them and only a singular matrix with **both**
/// columns non-zero (an ancestor flattening one axis of a rotated frame, which
/// the `R·SkewX·S` pose family genuinely cannot express) returns null.
///
/// **The rotation branch is preserved.** `atan2` lands rotation on `(-π, π]` and
/// `atan` lands skewX on `(-π/2, π/2)`, so a node authored at `rotation: 4π`
/// came back at `-4.9e-16`: same matrix, same pixels at rest, two full turns
/// destroyed — and destroyed permanently, because any keyframe later taken from
/// that pose inherits the collapse. Docs/v3/01 §4 makes unbounded radians a
/// written invariant. Adding `2πk` to rotation and `πk` to skewX leaves
/// `Affine.rotate` and `Affine.skewX` bit-identical (`tan` has period π), so
/// re-branching to the turn nearest the node's previous authored value is free.
Transform2? _solvePose(Affine local, Transform2 previous) {
  final pivot = previous.pivot;
  final solved =
      local.decompose(pivot: pivot) ?? _decomposeCollapsed(local, pivot);
  if (solved == null) return null;
  return solved.copyWith(
    rotation: _nearestBranch(solved.rotation, previous.rotation, 2 * math.pi),
    skewX: _nearestBranch(solved.skewX, previous.skewX, math.pi),
  );
}

/// [value] shifted by whole [period]s onto the branch nearest [previous].
double _nearestBranch(double value, double previous, double period) {
  final turns = ((previous - value) / period).roundToDouble();
  // NaN/infinite inputs propagate rather than being clamped (docs/v3/08 §1):
  // the shift is simply skipped, the matrix is unchanged either way.
  if (!turns.isFinite || turns == 0.0) return value;
  return value + turns * period;
}

/// The pose for a singular [m] whose collapse is on one axis, or null.
///
/// `R·SkewX·S` puts `sx·R·x̂` in column one and `sy·R·(tan k, 1)` in column two,
/// so a zero column means that axis' scale is zero and the OTHER column alone
/// fixes the rotation (skew is unconstrained when `sy == 0`, and stays 0). A
/// singular matrix with two non-zero columns has both of them parallel and
/// neither expressible this way — that one returns null and the caller throws.
Transform2? _decomposeCollapsed(Affine m, Vec2 pivot) {
  const eps = 1e-12;
  final col1 = math.sqrt(m.a * m.a + m.b * m.b);
  final col2 = math.sqrt(m.c * m.c + m.d * m.d);

  final double rotation, sx, sy;
  if (col1 <= eps && col2 <= eps) {
    rotation = 0.0;
    sx = 0.0;
    sy = 0.0;
  } else if (col1 <= eps) {
    // scale.x == 0: column two is sy·R·ŷ = sy·(-sin r, cos r).
    rotation = math.atan2(-m.c, m.d);
    sx = 0.0;
    sy = col2;
  } else if (col2 <= eps) {
    rotation = math.atan2(m.b, m.a);
    sx = col1;
    sy = 0.0;
  } else {
    return null;
  }

  // Same residual as `Affine.decompose`: `T(pos)·T(pivot)·M·T(-pivot)` leaves
  // `pos + pivot - M·pivot` in the translation slot.
  final moved = Affine(m.a, m.b, m.c, m.d, 0, 0).applyVector(pivot);
  return Transform2(
    position: Vec2(m.tx - pivot.x + moved.x, m.ty - pivot.y + moved.y),
    scale: Vec2(sx, sy),
    pivot: pivot,
    rotation: rotation,
  );
}

// ---------------------------------------------------------------------------
// duplicateSubtree — remap
// ---------------------------------------------------------------------------

/// Mints a fresh id for every node and every anchor in [n]'s subtree.
void _buildRemap(
    Node n, Map<NodeId, NodeId> nodeMap, Map<AnchorId, AnchorId> anchorMap) {
  for (final node in _subtree(n)) {
    nodeMap[node.id] = NodeId(uuidV4());
    if (node is PathNode) {
      for (final anchor in node.path.anchors) {
        anchorMap[anchor.id] = AnchorId(uuidV4());
      }
    }
  }
}

/// Deep-copies [n] onto the remapped ids. Unknown nodes have their raw `id`
/// rewritten too, so the verbatim JSON they re-emit does not resurrect the
/// original `NodeId` and trip the document's uniqueness check.
Node _cloneNode(
    Node n, Map<NodeId, NodeId> nodeMap, Map<AnchorId, AnchorId> anchorMap) {
  final newId = nodeMap[n.id]!;
  return switch (n) {
    GroupNode g => GroupNode(
        id: newId,
        name: g.name,
        children: <Node>[
          for (final c in g.children) _cloneNode(c, nodeMap, anchorMap),
        ],
        clipChildren: g.clipChildren,
        transform: g.transform,
        opacity: g.opacity,
        visible: g.visible,
        locked: g.locked,
        unknownKeys: g.unknownKeys,
      ),
    PathNode p => PathNode(
        id: newId,
        name: p.name,
        path: _remapPath(p.path, anchorMap),
        fills: p.fills,
        strokes: p.strokes,
        recipe: p.recipe,
        trim: p.trim,
        transform: p.transform,
        opacity: p.opacity,
        visible: p.visible,
        locked: p.locked,
        unknownKeys: p.unknownKeys,
      ),
    UnknownNode u => UnknownNode(
        id: newId,
        name: u.name,
        rawType: u.rawType,
        raw: Map<String, Object?>.unmodifiable(<String, Object?>{
          ...u.raw,
          'id': newId.v,
        }),
      ),
  };
}

/// Rebuilds a [PathData] on the remapped anchor ids, through the validating
/// factory — a remap bug that collided two anchors would throw here rather than
/// silently animate one anchor with another's pose.
PathData _remapPath(PathData path, Map<AnchorId, AnchorId> anchorMap) =>
    PathData(
      closed: path.closed,
      anchors: <Anchor>[
        for (final a in path.anchors)
          Anchor(
            id: anchorMap[a.id] ?? a.id,
            position: a.position,
            inTangent: a.inTangent,
            outTangent: a.outTangent,
            kind: a.kind,
          ),
      ],
    );

/// Adds a deep copy of every remapped node's `TrackSet` to [animation], leaving
/// the originals in place.
///
/// A path track's poses are re-keyed onto the copy's anchor ids; every other
/// track type is immutable and carries no anchor identity, so it is shared as-is
/// (a `PropertyKey`'s `PaintId` subject is deliberately kept — see
/// [NodeOps.duplicateSubtree]). Tracks preserved raw in `unknownKeys` keep their
/// shape and get the same anchor-id substitution by exact string match, which is
/// the only thing about them this build can safely claim to understand — see
/// the decision note on [NodeOps.duplicateSubtree].
Animation _cloneTracks(Animation animation, Map<NodeId, NodeId> nodeMap,
    Map<AnchorId, AnchorId> anchorMap) {
  final additions = <NodeId, TrackSet>{};
  for (final entry in animation.tracks.entries) {
    final newNode = nodeMap[entry.key];
    if (newNode == null) continue; // not part of the duplicated subtree
    additions[newNode] = _remapTrackSet(entry.value, anchorMap);
  }
  if (additions.isEmpty) return animation;
  return animation.copyWith(
      tracks: Map<NodeId, TrackSet>.unmodifiable(
    <NodeId, TrackSet>{...animation.tracks, ...additions},
  ));
}

TrackSet _remapTrackSet(TrackSet tracks, Map<AnchorId, AnchorId> anchorMap) =>
    TrackSet(
      Map<PropertyKey, Track>.unmodifiable(<PropertyKey, Track>{
        for (final e in tracks.byKey.entries)
          e.key: switch (e.value) {
            final PathTrack t => t.withKeys(<Keyframe<PathPose>>[
                for (final k in t.keys)
                  Keyframe<PathPose>(
                    t: k.t,
                    easing: k.easing,
                    value: PathPose(Map<AnchorId, AnchorPose>.unmodifiable(
                      <AnchorId, AnchorPose>{
                        for (final pose in k.value.anchors.entries)
                          (anchorMap[pose.key] ?? pose.key): pose.value,
                      },
                    )),
                  ),
              ]),
            final Track t => t,
          },
      }),
      unknownKeys: _remapRaw(tracks.unknownKeys, anchorMap),
    );

/// The raw blob with every string that IS one of the re-minted anchor ids
/// replaced by its copy, over map keys and string values alike.
///
/// Structure-blind on purpose: it does not guess which key holds poses, so an
/// unknown track shape survives untouched and only the ids this op just minted
/// move. A v4 uuid appearing anywhere in the copy's own track blob means that
/// anchor and nothing else, which is what makes the substitution safe without
/// understanding the schema. Returns the same map when nothing matched.
Map<String, Object?> _remapRaw(
    Map<String, Object?> raw, Map<AnchorId, AnchorId> anchorMap) {
  if (raw.isEmpty || anchorMap.isEmpty) return raw;
  final ids = <String, String>{
    for (final e in anchorMap.entries) e.key.v: e.value.v,
  };
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final e in raw.entries)
      (ids[e.key] ?? e.key): _remapRawValue(e.value, ids),
  });
}

Object? _remapRawValue(Object? v, Map<String, String> ids) {
  if (v is String) return ids[v] ?? v;
  if (v is List) {
    return List<Object?>.unmodifiable(
        <Object?>[for (final e in v) _remapRawValue(e, ids)]);
  }
  if (v is Map) {
    final out = <String, Object?>{};
    for (final e in v.entries) {
      final k = '${e.key}';
      out[ids[k] ?? k] = _remapRawValue(e.value, ids);
    }
    return Map<String, Object?>.unmodifiable(out);
  }
  return v;
}

// ---------------------------------------------------------------------------
// Shared tree walks and rebuilds
// ---------------------------------------------------------------------------

/// [n] and every descendant, pre-order.
Iterable<Node> _subtree(Node n) sync* {
  yield n;
  if (n is GroupNode) {
    for (final c in n.children) {
      yield* _subtree(c);
    }
  }
}

Set<NodeId> _subtreeIds(Node n) => {for (final x in _subtree(n)) x.id};

/// `NodeId` → the group that holds it as a direct child, in **one** walk.
///
/// The root is absent (it has no parent), which is the same "null means absent
/// or root" contract the per-node search this replaced had — built once per op
/// call instead of once per member, so grouping and reparenting are O(n) rather
/// than O(n·m). It is a local, never a field on [Document]: derived state stored
/// on the document is the antipattern docs/v3/08 §4 names.
Map<NodeId, GroupNode> _parentIndex(GroupNode root) {
  final out = <NodeId, GroupNode>{};
  void visit(GroupNode g) {
    for (final c in g.children) {
      out[c.id] = g;
      if (c is GroupNode) visit(c);
    }
  }

  visit(root);
  return out;
}

/// Rebuilds the tree with the group [targetId] replaced by `edit(it)`.
GroupNode _editGroup(
    GroupNode root, NodeId targetId, GroupNode Function(GroupNode) edit) {
  if (root.id == targetId) return edit(root);
  return root.copyWith(children: <Node>[
    for (final c in root.children)
      if (c is GroupNode) _editGroup(c, targetId, edit) else c,
  ]);
}

/// Rebuilds the tree with the node [id] replaced by `edit(it)`, wherever it
/// sits.
///
/// Unlike [_editGroup] the target may be **any** node, not only a group — it is
/// how [NodeOps.setTransform] and [NodeOps.setName] reach a leaf. The caller
/// guarantees [id] is not the root (the root has no parent slot to rebuild).
GroupNode _replaceNode(GroupNode root, NodeId id, Node Function(Node) edit) =>
    root.copyWith(children: <Node>[
      for (final c in root.children)
        if (c.id == id)
          edit(c)
        else if (c is GroupNode)
          _replaceNode(c, id, edit)
        else
          c,
    ]);

/// The same node with a new [name].
///
/// An [UnknownNode] is refused for the same reason [_withTransform] refuses one:
/// it re-emits its raw JSON verbatim on save, so the typed `name` written here
/// would be dropped, and pretending the rename worked is worse than throwing.
Node _withName(Node n, String name) => switch (n) {
      GroupNode g => g.copyWith(name: name),
      PathNode p => p.copyWith(name: name),
      UnknownNode _ => throw ArgumentError.value(
          n.id.v, 'n', 'an unknown node cannot be renamed'),
    };

/// The same node with a new `visible` flag. Refuses an [UnknownNode] for the
/// same reason [_withName] does — its flag lives in raw JSON, not the typed
/// field, so a typed write here would be silently dropped on save.
Node _withVisible(Node n, bool visible) => switch (n) {
      GroupNode g => g.copyWith(visible: visible),
      PathNode p => p.copyWith(visible: visible),
      UnknownNode _ => throw ArgumentError.value(
          n.id.v, 'n', 'an unknown node has no editable visibility'),
    };

/// The same node with a new `opacity`. Refuses an [UnknownNode] for the same
/// reason [_withName] does.
Node _withOpacity(Node n, double opacity) => switch (n) {
      GroupNode g => g.copyWith(opacity: opacity),
      PathNode p => p.copyWith(opacity: opacity),
      UnknownNode _ => throw ArgumentError.value(
          n.id.v, 'n', 'an unknown node has no editable opacity'),
    };

/// The same node with a new `locked` flag. Refuses an [UnknownNode] for the same
/// reason [_withName] does.
Node _withLocked(Node n, bool locked) => switch (n) {
      GroupNode g => g.copyWith(locked: locked),
      PathNode p => p.copyWith(locked: locked),
      UnknownNode _ => throw ArgumentError.value(
          n.id.v, 'n', 'an unknown node has no editable lock'),
    };

/// Rebuilds the tree with the node [id] removed wherever it sits.
GroupNode _removeNode(GroupNode root, NodeId id) =>
    root.copyWith(children: <Node>[
      for (final c in root.children)
        if (c.id != id)
          if (c is GroupNode) _removeNode(c, id) else c,
    ]);

/// The same node with a new [Transform2].
///
/// An [UnknownNode] is refused: it re-emits raw JSON verbatim, so a typed
/// transform written onto it would be dropped on save — reparenting one is not a
/// meaningful operation and pretending it worked is worse than throwing.
Node _withTransform(Node n, Transform2 t) => switch (n) {
      GroupNode g => g.copyWith(transform: t),
      PathNode p => p.copyWith(transform: t),
      UnknownNode _ => throw ArgumentError.value(
          n.id.v, 'n', 'an unknown node cannot be reparented'),
    };
