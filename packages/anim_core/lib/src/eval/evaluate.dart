/// The evaluator: `Document` + playhead → `Scene` (docs/v3/01 §9, §11; F9.2).
///
/// **This file contains no `try`, no `catch`, and no NaN clamp, and it never
/// will.** Totality is a proof obligation discharged by construction, not a
/// runtime rescue (docs/v3/08 §1). A `catch` here would turn a wrong-pixels bug
/// into an invisibly frozen shape and blind the golden tests to the exact class
/// of defect this rewrite exists to remove. Guards belong at the widget,
/// painter, command and IO boundary — three layers up, where there is a user to
/// tell.
///
/// The one clamp in this file is `opacity`'s 0..1 at read, which is *specified*
/// (docs/v3/01 §7) rather than defensive — see [_clamp01], which is careful to
/// let NaN through for exactly the reason above.
///
/// Evaluation is a **pure read**: the [Document] handed in is never modified
/// and nothing derived is written back onto it (AC-9.2.6).
library;

import '../affine.dart';
import '../animation.dart';
import '../document.dart';
import '../node.dart';
import '../path.dart';
import '../primitives.dart';
import '../track.dart';
import 'scene.dart';

/// One animation's contribution to one node's path at one instant.
///
/// Deliberately the bracketing *keyframe pair* rather than a blended pose: the
/// pose maps must not be iterated, because the node's topology — not the
/// keyframe — decides which anchors exist (docs/v3/01 §9). Carrying the pair
/// this far is what lets [resolveNodePose] apply the one missing-pose rule
/// per contributor.
final class PathBracket {
  const PathBracket(this.from, this.to, this.u, this.weight);

  final PathPose from;
  final PathPose to;

  /// Already eased. `0.0` when the bracket is degenerate (hold-first,
  /// hold-last, single key), in which case [from] and [to] are the same pose.
  final double u;

  final double weight;
}

/// The per-node property bag produced by stage 1.
///
/// A *bag*, not a `Node`: stage 1 must be able to say "position came from a
/// track, rotation came from the pose" without inventing a half-authored node,
/// and stages 4–6 will later write solved values back into it.
final class NodeSample {
  const NodeSample({
    required this.transform,
    required this.opacity,
    required this.visible,
    this.path = const [],
  });

  /// The blended pose. `pivot` is copied from the authored [Transform2] and is
  /// never sampled — it is not in `PropKey` (docs/v3/01 §4).
  final Transform2 transform;

  final double opacity;
  final bool visible;

  /// Empty when no animation in the mix keys this node's path at all, which is
  /// the signal for "fully static geometry" — distinct from a mix in which
  /// *some* entries lack the track and contribute the rest pose at their weight.
  final List<PathBracket> path;
}

/// The state threaded through the eight stages.
///
/// The stages are functions over this type rather than closures inside one walk
/// precisely so each is individually callable and individually testable
/// (AC-9.2.1). An inlined walk is how the naive `deform → composeWorld`
/// ordering gets discovered too late to fix cheaply.
final class EvalFrame {
  const EvalFrame({
    required this.doc,
    required this.samples,
    this.geometry = const {},
    this.nodes = const [],
  });

  final Document doc;

  /// Stage 1 output.
  final Map<NodeId, NodeSample> samples;

  /// Stage 2 output: posed geometry in node-local space.
  ///
  /// Keyed by [NodeId] because v1 has exactly one instance of every node. When
  /// instancing lands this becomes `ScenePath`-keyed; nothing else about the
  /// stage changes.
  final Map<NodeId, PathData> geometry;

  /// Stage 3 output onwards, already in **draw order** (back to front).
  final List<ResolvedNode> nodes;

  EvalFrame copyWith({
    Map<NodeId, NodeSample>? samples,
    Map<NodeId, PathData>? geometry,
    List<ResolvedNode>? nodes,
  }) =>
      EvalFrame(
        doc: doc,
        samples: samples ?? this.samples,
        geometry: geometry ?? this.geometry,
        nodes: nodes ?? this.nodes,
      );

  Scene toScene() => Scene(
        List.unmodifiable(nodes),
        Map.unmodifiable(<ScenePath, ResolvedNode>{
          for (final n in nodes) n.path: n,
        }),
      );
}

/// THE single entry point. Pure function. No `BuildContext`, no pixels, no
/// dialogs.
///
/// `evaluate(doc, const [])` is **defined**: it returns the static rest pose —
/// every node's authored `Transform2`, `PathData` and paint. That is not an
/// edge case left undefined, it is how the editor renders a document with no
/// animation and how bones will later get their inverse-bind matrices for free.
Scene evaluate(Document doc, List<AnimationMix> mix) => resolvePaint(
      applyTrim(
        deform(
          composeWorldB(
            solveConstraints(
              composeWorldA(
                resolvePose(
                  sampleTracks(doc, mix),
                ),
              ),
            ),
          ),
        ),
      ),
    ).toScene();

// ---------------------------------------------------------------------------
// Stage 1 — sampleTracks
// ---------------------------------------------------------------------------

/// One pass over `Map<NodeId, TrackSet>`, blending the mix list into a per-node
/// property bag.
///
/// Every read goes through the **typed accessors**, so a malformed stored track
/// yields null and the node falls back to its pose value instead of crashing
/// the tick (AC-9.2.4). Validation happens at load and at mutation; there is
/// none here.
///
/// Blend contract (docs/v3/01 §11), written now because it is one paragraph now
/// and a rewrite later:
///
/// | type | blend |
/// | --- | --- |
/// | scalar / `Vec2` / color | weighted sum |
/// | `rotation`, `skewX` | weighted sum of **raw unbounded radians** — no
/// normalization, no shortest arc. `-12.5664` means two full reverse turns and
/// must play as two turns. |
/// | `bool` / `visible` | **highest weight wins**, ties by list order. Never
/// lerped. |
/// | `path` | per-`AnchorId` weighted sum, which works only because poses are
/// id-keyed maps and not positional lists. |
///
/// A mix entry whose animation lacks a track for property P contributes the
/// node's **pose** value at that weight — never zero, never a renormalized
/// weight. That one rule is the difference between a smooth transition and a
/// pop, and it is why an animation missing from [Document.animations] entirely
/// still consumes its weight rather than being skipped.
EvalFrame sampleTracks(Document doc, List<AnimationMix> mix) {
  final byId = <AnimationId, Animation>{
    for (final a in doc.animations) a.id: a,
  };
  return EvalFrame(
    doc: doc,
    samples: <NodeId, NodeSample>{
      for (final n in doc.walk()) n.id: _sampleNode(n, mix, byId),
    },
  );
}

NodeSample _sampleNode(
    Node node, List<AnimationMix> mix, Map<AnimationId, Animation> byId) {
  final pose = node.transform;
  // The empty mix is the rest pose, exactly. Weights would sum to zero and a
  // weighted sum would collapse every node onto the origin, so this is a real
  // branch and not a shortcut.
  if (mix.isEmpty) {
    return NodeSample(
        transform: pose,
        opacity: _clamp01(node.opacity),
        visible: node.visible);
  }

  var px = 0.0, py = 0.0, sx = 0.0, sy = 0.0, rotation = 0.0, skewX = 0.0;
  var opacity = 0.0;
  var visible = node.visible;
  var bestWeight = double.negativeInfinity;
  final brackets = <PathBracket>[];
  var anyPathTrack = false;

  for (final m in mix) {
    final w = m.weight;
    final tracks = byId[m.animation]?.tracksFor(node.id) ?? TrackSet.empty;

    final position =
        tracks.vec2(PropKey.position)?.sampleAt(m.t) ?? pose.position;
    final scale = tracks.vec2(PropKey.scale)?.sampleAt(m.t) ?? pose.scale;
    px += position.x * w;
    py += position.y * w;
    sx += scale.x * w;
    sy += scale.y * w;
    rotation +=
        (tracks.scalar(PropKey.rotation)?.sampleAt(m.t) ?? pose.rotation) * w;
    skewX += (tracks.scalar(PropKey.skewX)?.sampleAt(m.t) ?? pose.skewX) * w;
    opacity += _clamp01(
            tracks.scalar(PropKey.opacity)?.sampleAt(m.t) ?? node.opacity) *
        w;

    // Strictly greater, so a tie leaves the earlier entry in place — "ties
    // broken by list order" is the written rule and `>=` would silently invert
    // it.
    if (w > bestWeight) {
      bestWeight = w;
      visible = tracks.boolean(PropKey.visible)?.sampleAt(m.t) ?? node.visible;
    }

    final track = tracks.pathTrack();
    if (track == null) {
      // The pose contribution for `path` is a pair of EMPTY pose maps: stage 2
      // resolves every missing id to the node's rest anchor, so an empty map
      // *is* the rest pose without this stage needing the topology.
      brackets.add(PathBracket(PathPose.empty, PathPose.empty, 0.0, w));
      continue;
    }
    anyPathTrack = true;
    final (k0, k1, u) = track.bracket(m.t);
    brackets.add(PathBracket(k0.value, k1.value, u, w));
  }

  return NodeSample(
    transform: Transform2(
      position: Vec2(px, py),
      scale: Vec2(sx, sy),
      pivot: pose.pivot,
      rotation: rotation,
      skewX: skewX,
    ),
    // Clamped again after the blend: the weights of a mix are not required to
    // sum to 1, so two entries at full opacity legitimately sum past it.
    opacity: _clamp01(opacity),
    visible: visible,
    path: anyPathTrack ? List.unmodifiable(brackets) : const <PathBracket>[],
  );
}

/// `opacity` is **clamped 0..1 at read** — docs/v3/01 §7, animatable property
/// table, verbatim.
///
/// It is the one channel with that rule, and the rule is load-bearing rather
/// than defensive: `CubicEasing` deliberately leaves `y` unclamped so that
/// authored back/anticipation curves overshoot and undershoot, so a perfectly
/// legal `{"kind":"cubic","p":[0.36,0,0.66,-0.56]}` on an opacity key samples
/// *negative*. Two negatives multiply positive in [composeWorldA], so a group
/// and its child both undershooting produce a small **positive** world opacity
/// with `worldVisible` true — a subtree faintly painted through a window in
/// which it should be fully transparent, and an out-of-range number handed to
/// every future exporter reading the `Scene`.
///
/// This is not the NaN rescue docs/v3/08 §1 forbids, and it is written as two
/// comparisons rather than `num.clamp` precisely to keep it from becoming one:
/// `num.clamp` orders NaN *above* its upper limit and would silently return
/// `1.0` for it, turning "the caller sampled at a NaN `t`" into a fully opaque
/// shape. Both comparisons below are false for NaN, so it propagates and stays
/// visible.
double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

// ---------------------------------------------------------------------------
// Stage 2 — resolvePose
// ---------------------------------------------------------------------------

/// Pose maps → posed `PathData` in local space, for every path node.
EvalFrame resolvePose(EvalFrame frame) {
  final geometry = <NodeId, PathData>{};
  for (final node in frame.doc.walk()) {
    if (node is! PathNode) continue;
    geometry[node.id] = resolveNodePose(
      node.path,
      frame.samples[node.id]?.path ?? const <PathBracket>[],
    );
  }
  return frame.copyWith(geometry: geometry);
}

/// **The node's topology drives the loop.** Docs/v3/01 §9, verbatim.
///
/// There is no index join, no `points.length` comparison, and no "from frame"
/// anywhere in this function — matching is a map lookup by [AnchorId], so
/// anchor order, anchor count and insertion history are all irrelevant to the
/// correctness of interpolation. That is the single defect the whole rewrite
/// exists to remove: legacy tweened by array position, so inserting one point
/// mis-paired every vertex after it.
///
/// A missing pose entry falls back to the node's **rest anchor**. That is the
/// one rule. There is no `AnchorMatchRule`, no `collapseToNeighbor`, no
/// synthesized ghost, no LCS, and no arc-length resampling in the evaluator.
///
/// `closed` and `AnchorKind` come from topology and are **never** interpolated,
/// so there is nothing to pop at `u = 0⁺`.
///
/// Returns [PathData.trusted]: the anchor list is a 1:1 map over an
/// already-validated topology, so the uniqueness scan cannot find anything, and
/// what it *could* do is throw from inside the eval path.
PathData resolveNodePose(PathData topology, List<PathBracket> brackets) {
  if (brackets.isEmpty) return topology;

  final out = <Anchor>[];
  for (final a in topology.anchors) {
    final rest = AnchorPose(a.position, a.inTangent, a.outTangent);
    var pxx = 0.0, pyy = 0.0, ixx = 0.0, iyy = 0.0, oxx = 0.0, oyy = 0.0;
    for (final b in brackets) {
      final pa = b.from.anchors[a.id] ?? rest;
      final pb = b.to.anchors[a.id] ?? rest;
      final p = AnchorPose.lerp(pa, pb, b.u);
      pxx += p.position.x * b.weight;
      pyy += p.position.y * b.weight;
      ixx += p.inTangent.x * b.weight;
      iyy += p.inTangent.y * b.weight;
      oxx += p.outTangent.x * b.weight;
      oyy += p.outTangent.y * b.weight;
    }
    out.add(a.copyWith(
      position: Vec2(pxx, pyy),
      inTangent: Vec2(ixx, iyy),
      outTangent: Vec2(oxx, oyy),
    ));
  }
  return PathData.trusted(List.unmodifiable(out), topology.closed);
}

// ---------------------------------------------------------------------------
// Stage 3 — composeWorldA
// ---------------------------------------------------------------------------

/// Pre-order traversal; `world = parent.world · local`.
///
/// `worldVisible` **ANDs** down the tree — a hidden group hides every
/// descendant regardless of that descendant's own tracks — and `worldOpacity`
/// **multiplies** down it. `locked` is never read, at any depth: it is a
/// hit-test gate, not a render gate, and reading it here is how a locked layer
/// silently disappears from an export.
///
/// A node whose world matrix is **singular** (an animator will key scale to 0)
/// renders nothing and never throws: `Affine.invert()` returning null is an
/// early return, never `invert()!`.
///
/// Groups are emitted with null geometry so the draw order is a faithful
/// pre-order flattening — a painter that needs to honour `clipChildren` later
/// needs them, and hit-testing needs them now.
EvalFrame composeWorldA(EvalFrame frame) {
  final nodes = <ResolvedNode>[];
  _compose(frame, frame.doc.root, Affine.identity, 1.0, true, nodes);
  return frame.copyWith(nodes: nodes);
}

void _compose(EvalFrame frame, Node node, Affine parentWorld,
    double parentOpacity, bool parentVisible, List<ResolvedNode> out) {
  final sample = frame.samples[node.id];
  final local = (sample?.transform ?? node.transform).toAffine();
  final world = parentWorld.mul(local);
  final opacity = parentOpacity * (sample?.opacity ?? node.opacity);
  final visible = parentVisible &&
      (sample?.visible ?? node.visible) &&
      world.invert() != null;

  out.add(ResolvedNode(
    path: ScenePath(node.id),
    world: world,
    worldOpacity: opacity,
    // An UnknownNode is forward-compat ballast: it renders nothing and is not
    // hit-testable, but it still occupies a slot so a future build's ordering
    // is recognisable in this one.
    worldVisible: visible && node is! UnknownNode,
    geometry: frame.geometry[node.id],
  ));

  if (node is GroupNode) {
    for (final child in node.children) {
      _compose(frame, child, world, opacity, visible, out);
    }
  }
}

// ---------------------------------------------------------------------------
// Stages 4, 5, 6 — the seams
// ---------------------------------------------------------------------------

/// **NO-OP in v1.** IK: writes solved rotations back into the property bag.
///
/// Present, named and ordered on purpose. Deleting it is a scope violation, not
/// a cleanup (AC-9.2.2). It sits *after* [composeWorldA] because a constraint
/// solver needs the world matrices of the chain it is solving, and *before*
/// [composeWorldB] because the subtrees it edits must be recomposed.
EvalFrame solveConstraints(EvalFrame frame) => frame;

/// **NO-OP in v1.** Re-composes only the subtrees [solveConstraints] touched.
///
/// A second full pre-order walk would be correct and wasteful; a solver that
/// composed its own results inline would be a fourth place that knows
/// `world = parent.world · local`. Deleting it is a scope violation
/// (AC-9.2.2).
EvalFrame composeWorldB(EvalFrame frame) => frame;

/// **NO-OP in v1.** Skinning.
///
/// Ordered **after** the world stages because it consumes bone world matrices
/// that they produce — the naive linear ordering `deform → composeWorld` is
/// unbuildable, and discovering that after `evaluate` has been written as one
/// non-reentrant pre-order walk is expensive. Deleting it is a scope violation
/// (AC-9.2.2).
EvalFrame deform(EvalFrame frame) => frame;

// ---------------------------------------------------------------------------
// Stage 7 — applyTrim
// ---------------------------------------------------------------------------

/// **Pass-through at M0.** The arc-length window, cubic splitting and discard
/// arrive with F7.x at **M6**.
///
/// Ordered **after** [deform] because trim destroys the authored `AnchorId`s
/// that skinning joins on, and measured in node-**local** space (AE/Lottie
/// semantics) because measuring after a non-uniform scale would make the trim
/// percentage depend on the transform.
///
/// After this stage the `AnchorId`s in `ResolvedNode.geometry` are **synthetic
/// and non-authoritative**: nothing downstream — no exporter, no future
/// skinning pass, no hit-test that wants to select an anchor — may join by
/// them. At M0 they still happen to equal the authored ids, which is exactly
/// why the rule has to be written down before anything starts relying on it.
EvalFrame applyTrim(EvalFrame frame) => frame;

// ---------------------------------------------------------------------------
// Stage 8 — resolvePaint
// ---------------------------------------------------------------------------

/// Attaches each node's **authored** fills and strokes.
///
/// A pass-through at M0 in the sense that nothing is sampled: animated paint
/// channels (`fillColor`, `strokeWidth`, gradient stop offsets) land at M4/M6
/// and will read [NodeSample] here. It is nonetheless the stage that populates
/// `fills`/`strokes` — [composeWorldA] deliberately leaves them empty — so that
/// when paint does become animatable there is exactly one place that decides
/// what a node is painted with.
EvalFrame resolvePaint(EvalFrame frame) {
  final index = frame.doc.nodeIndex;
  return frame.copyWith(nodes: <ResolvedNode>[
    for (final n in frame.nodes)
      switch (index[n.path.nodeId]) {
        final PathNode p => n.copyWith(fills: p.fills, strokes: p.strokes),
        _ => n,
      },
  ]);
}
