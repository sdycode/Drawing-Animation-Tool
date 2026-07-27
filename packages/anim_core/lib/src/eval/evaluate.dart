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
import '../geom/arc_length.dart';
import '../node.dart';
import '../paint.dart';
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
    this.trim = PathTrim.full,
    this.fillColors = const {},
    this.fillOpacities = const {},
    this.strokeColors = const {},
    this.strokeOpacities = const {},
    this.strokeWidths = const {},
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

  /// The blended `trimStart`/`trimEnd`/`trimOffset`, each channel falling back to
  /// the node's authored [PathTrim] when unkeyed (the pose-value rule, never
  /// zero). [applyTrim] reads this; a full trim is a pass-through.
  final PathTrim trim;

  /// Animated paint, keyed by the fill/stroke's `PaintId` (the track subject).
  /// A `PaintId` is present only when at least one mix entry keys that channel;
  /// an unkeyed channel is absent, and [resolvePaint] then keeps the authored
  /// value. Colours are absent for gradient paints (no solid colour to write).
  final Map<PaintId, Rgba> fillColors;
  final Map<PaintId, double> fillOpacities;
  final Map<PaintId, Rgba> strokeColors;
  final Map<PaintId, double> strokeOpacities;
  final Map<PaintId, double> strokeWidths;
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
  // The node's authored trim is the pose value every unkeyed trim channel falls
  // back to. Non-path nodes have no trim; `PathTrim.full` makes applyTrim skip.
  final authoredTrim = node is PathNode ? node.trim : PathTrim.full;
  // The empty mix is the rest pose, exactly. Weights would sum to zero and a
  // weighted sum would collapse every node onto the origin, so this is a real
  // branch and not a shortcut.
  if (mix.isEmpty) {
    return NodeSample(
      transform: pose,
      opacity: _clamp01(node.opacity),
      visible: node.visible,
      // The rest pose still renders an authored partial trim — trim is a paint
      // property, not an animation, so an unanimated document trims too. Paint
      // overrides stay empty, so resolvePaint keeps the authored fills/strokes.
      trim: authoredTrim,
    );
  }

  var px = 0.0, py = 0.0, sx = 0.0, sy = 0.0, rotation = 0.0, skewX = 0.0;
  var opacity = 0.0;
  var trimStart = 0.0, trimEnd = 0.0, trimOffset = 0.0;
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

    // Node-level trim channels, blended exactly like opacity and falling back to
    // the authored trim per channel (never zero — the pose-value rule).
    trimStart += (tracks.scalar(PropKey.trimStart)?.sampleAt(m.t) ??
            authoredTrim.start) *
        w;
    trimEnd +=
        (tracks.scalar(PropKey.trimEnd)?.sampleAt(m.t) ?? authoredTrim.end) * w;
    trimOffset += (tracks.scalar(PropKey.trimOffset)?.sampleAt(m.t) ??
            authoredTrim.offset) *
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
    trim: PathTrim(start: trimStart, end: trimEnd, offset: trimOffset),
    fillColors: _blendPaintColor(node, mix, byId, PropKey.fillColor),
    fillOpacities: _blendPaintScalar(node, mix, byId, PropKey.fillOpacity),
    strokeColors: _blendPaintColor(node, mix, byId, PropKey.strokeColor),
    strokeOpacities: _blendPaintScalar(node, mix, byId, PropKey.strokeOpacity),
    strokeWidths: _blendPaintScalar(node, mix, byId, PropKey.strokeWidth),
  );
}

/// Blends one animated **colour** paint channel (`fillColor` → the node's fills,
/// `strokeColor` → its strokes) across the mix, keyed by each paint's `PaintId`.
///
/// Every read goes through the typed [TrackSet.color] accessor, so a malformed
/// stored track yields null and the paint keeps its authored colour instead of
/// crashing the tick (AC-9.2.4). A `PaintId` is entered only when at least one
/// mix entry keys it; an unkeyed subject stays out of the map so [resolvePaint]
/// leaves it authored. The per-entry fallback is the authored solid colour (the
/// pose value); a gradient has none, so its fallback is transparent and, since
/// [resolvePaint] never writes a colour onto a gradient, it is never observed.
Map<PaintId, Rgba> _blendPaintColor(Node node, List<AnimationMix> mix,
    Map<AnimationId, Animation> byId, PropKey prop) {
  if (node is! PathNode) return const <PaintId, Rgba>{};
  final out = <PaintId, Rgba>{};
  if (prop == PropKey.fillColor) {
    for (final f in node.fills) {
      final c = _blendColorFor(node.id, mix, byId, prop, f.id, _solid(f.paint));
      if (c != null) out[f.id] = c;
    }
  } else {
    for (final s in node.strokes) {
      final c = _blendColorFor(node.id, mix, byId, prop, s.id, _solid(s.paint));
      if (c != null) out[s.id] = c;
    }
  }
  return out;
}

Rgba? _blendColorFor(
    NodeId node,
    List<AnimationMix> mix,
    Map<AnimationId, Animation> byId,
    PropKey prop,
    PaintId subject,
    Rgba fallback) {
  var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
  var keyed = false;
  for (final m in mix) {
    final track = (byId[m.animation]?.tracksFor(node) ?? TrackSet.empty)
        .color(prop, subject.v);
    if (track != null) keyed = true;
    final c = track?.sampleAt(m.t) ?? fallback;
    r += c.r * m.weight;
    g += c.g * m.weight;
    b += c.b * m.weight;
    a += c.a * m.weight;
  }
  return keyed ? Rgba(r, g, b, a) : null;
}

/// Blends one animated **scalar** paint channel across the mix, per `PaintId`:
/// `fillOpacity` → fills, `strokeOpacity`/`strokeWidth` → strokes. The scalar
/// analogue of [_blendPaintColor]; the fallback is the authored opacity/width.
Map<PaintId, double> _blendPaintScalar(Node node, List<AnimationMix> mix,
    Map<AnimationId, Animation> byId, PropKey prop) {
  if (node is! PathNode) return const <PaintId, double>{};
  final out = <PaintId, double>{};
  if (prop == PropKey.fillOpacity) {
    for (final f in node.fills) {
      final v = _blendScalarFor(node.id, mix, byId, prop, f.id, f.opacity);
      if (v != null) out[f.id] = v;
    }
  } else {
    for (final s in node.strokes) {
      final fallback = prop == PropKey.strokeWidth ? s.width : s.opacity;
      final v = _blendScalarFor(node.id, mix, byId, prop, s.id, fallback);
      if (v != null) out[s.id] = v;
    }
  }
  return out;
}

double? _blendScalarFor(
    NodeId node,
    List<AnimationMix> mix,
    Map<AnimationId, Animation> byId,
    PropKey prop,
    PaintId subject,
    double fallback) {
  var acc = 0.0;
  var keyed = false;
  for (final m in mix) {
    final track = (byId[m.animation]?.tracksFor(node) ?? TrackSet.empty)
        .scalar(prop, subject.v);
    if (track != null) keyed = true;
    acc += (track?.sampleAt(m.t) ?? fallback) * m.weight;
  }
  return keyed ? acc : null;
}

Rgba _solid(PaintSource paint) => switch (paint) {
      SolidPaint(:final color) => color,
      _ => Rgba.transparent,
    };

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

/// Arc-length trim: window → split boundary cubics → discard outside (F8.1).
///
/// Ordered **after** [deform] because trim destroys the authored `AnchorId`s
/// that skinning joins on, and measured in node-**local** space (AE/Lottie
/// semantics, AC-8.1.9) — the geometry here is `resolvePose`'s output, *before*
/// the world transform, so the revealed fraction does not depend on a parent
/// scale. After this stage the `AnchorId`s in `ResolvedNode.geometry` are
/// **synthetic and non-authoritative** (AC-8.1.8): nothing downstream — no
/// exporter, no future skinning pass, no hit-test — may join by them.
///
/// A [PathTrim.full] node is a pass-through with no work, so a document with no
/// trims returns [frame] unchanged (identity), which the pipeline-shape test
/// relies on.
EvalFrame applyTrim(EvalFrame frame) {
  var changed = false;
  final nodes = <ResolvedNode>[];
  for (final n in frame.nodes) {
    final geometry = n.geometry;
    final trim = frame.samples[n.path.nodeId]?.trim ?? PathTrim.full;
    if (geometry == null || trim.isFull) {
      nodes.add(n);
      continue;
    }
    changed = true;
    nodes.add(n.copyWith(geometry: _trim(geometry, trim)));
  }
  return changed ? frame.copyWith(nodes: nodes) : frame;
}

/// The arc-length table for [posed], **memoized per immutable `PathData`**
/// (AC-8.1.7). `resolvePose` returns an untracked node's topology verbatim — the
/// same instance every tick — so a static path scrubbed 60 times builds the
/// table once and hits the memo forever after. An **animated** path's posed
/// geometry is a fresh `PathData` per t, so its table is inherently per-t: that
/// is correct, not a miss to fix. `retopologize` deliberately does **not** share
/// this memo — it rebuilds per keyframe by design (docs/v3/01 §5).
final Expando<ArcTable> _arcTables = Expando<ArcTable>('trim arc-length table');

ArcTable _arcTableFor(PathData posed) =>
    _arcTables[posed] ??= ArcTable.build(posed);

/// The posed geometry restricted to the trim window, in node-local space.
///
/// TOTAL: never throws, never NaN, and never unexpectedly empty — the only empty
/// results are the two the model specifies (an empty window, and geometry with
/// no arc to walk).
PathData _trim(PathData posed, PathTrim trim) {
  // AC-8.1.3 / AC-8.1.4: an empty base window (`end <= start`), which subsumes
  // every wrapped `start > end` window, renders nothing — never a throw.
  if (trim.end <= trim.start) return PathData.empty;
  // 0- or 1-anchor paths have no arc to walk (invariant P2).
  if (posed.segmentCount == 0) return PathData.empty;
  // A full-width window on a *closed* loop reveals the entire path; a non-zero
  // offset only rotates the seam, which is invisible on a complete loop. Return
  // the closed geometry unchanged so it still fills and strokes with a join —
  // AC-8.1.5 forces `closed:false` only for a *partial* reveal, and `_walkClosed`
  // would otherwise trace the whole loop into an *open* path with a spurious
  // seam cap. `PathTrim.full` is already a pass-through upstream (`isFull`); this
  // covers full width with a non-zero offset, and an easing overshoot that lands
  // `end - start` at or past 1.0 (a genuine 99.99% reveal stays partial → open).
  if (posed.closed && trim.end - trim.start >= 1.0) return posed;

  final table = _arcTableFor(posed);
  if (!(table.total > 0.0)) return PathData.empty;

  final width = trim.end - trim.start;
  final cubics = posed.closed
      ? _walkClosed(posed, table, trim.start + trim.offset, width)
      : _walkOpen(
          posed, table, trim.start + trim.offset, trim.end + trim.offset);
  if (cubics.isEmpty) return PathData.empty;
  // AC-8.1.5: a partial reveal of a closed path cannot be filled → closed:false.
  return PathData.trusted(_anchorsFromCubics(cubics), false);
}

/// The window on a **closed** loop. The reveal start walks *around* the path
/// (AC-8.1.6): the offset start is wrapped into `[0,1)` rather than clamped, and
/// a window that runs past the seam wraps continuously across it, because a
/// closed path is a loop and offset is meant to rotate the reveal around it.
List<(Vec2, Vec2, Vec2, Vec2)> _walkClosed(
    PathData p, ArcTable table, double startFrac, double widthFrac) {
  final total = table.total;
  final segN = p.segmentCount;
  final s = startFrac - startFrac.floorToDouble(); // into [0,1)
  final startArc = s * total;
  final spanArc = widthFrac * total;
  final endArcRaw = startArc + spanArc;
  final wrap = endArcRaw > total + 1e-9;
  final (kStart, tStart) = table.locate(startArc);
  final (kEnd, tEnd) = table.locate(wrap ? endArcRaw - total : endArcRaw);
  return _collect(p, segN, kStart, tStart, kEnd, tEnd, wrap: wrap);
}

/// The window on an **open** path. Open paths do not wrap: the offset window is
/// clamped to `[0,1]` (a wrapped window is a written non-goal, AC-8.1.4).
List<(Vec2, Vec2, Vec2, Vec2)> _walkOpen(
    PathData p, ArcTable table, double startFrac, double endFrac) {
  final total = table.total;
  final segN = p.segmentCount;
  final s = startFrac.clamp(0.0, 1.0);
  final e = endFrac.clamp(0.0, 1.0);
  if (e <= s) return const <(Vec2, Vec2, Vec2, Vec2)>[];
  final (kStart, tStart) = table.locate(s * total);
  final (kEnd, tEnd) = table.locate(e * total);
  return _collect(p, segN, kStart, tStart, kEnd, tEnd, wrap: false);
}

/// The sub-cubics from cut `(kStart, tStart)` forward to `(kEnd, tEnd)` — the
/// boundary segments split with [subCubic], the interior segments taken whole.
List<(Vec2, Vec2, Vec2, Vec2)> _collect(
    PathData p, int segN, int kStart, double tStart, int kEnd, double tEnd,
    {required bool wrap}) {
  final out = <(Vec2, Vec2, Vec2, Vec2)>[];
  if (!wrap && kStart == kEnd) {
    _addPartial(out, p, kStart, tStart, tEnd);
    return out;
  }
  _addPartial(out, p, kStart, tStart, 1.0);
  if (wrap) {
    for (var k = kStart + 1; k < segN; k++) {
      out.add(p.segment(k));
    }
    for (var k = 0; k < kEnd; k++) {
      out.add(p.segment(k));
    }
  } else {
    for (var k = kStart + 1; k < kEnd; k++) {
      out.add(p.segment(k));
    }
  }
  _addPartial(out, p, kEnd, 0.0, tEnd);
  return out;
}

void _addPartial(List<(Vec2, Vec2, Vec2, Vec2)> out, PathData p, int k,
    double t0, double t1) {
  // A zero-length cut (a boundary landing exactly on an anchor) adds no segment;
  // the neighbouring whole segment already carries that point, so continuity
  // holds and the output never gains a degenerate cubic.
  if (t1 - t0 <= 1e-12) return;
  final (p0, p1, p2, p3) = p.segment(k);
  out.add((t0 == 0.0 && t1 == 1.0)
      ? (p0, p1, p2, p3)
      : subCubic(p0, p1, p2, p3, t0, t1));
}

/// A chain of sub-cubics → an open anchor list. Consecutive cubics share an
/// endpoint (continuity is exact), so the joint anchor takes the incoming handle
/// of the segment arriving and the outgoing handle of the one leaving.
///
/// Ids are minted fresh and sequential (AC-8.1.8): they are synthetic and
/// non-authoritative, and their `trim:` prefix cannot collide with an authored
/// UUID, so nothing downstream can join a trimmed anchor back to an authored one.
List<Anchor> _anchorsFromCubics(List<(Vec2, Vec2, Vec2, Vec2)> cubics) {
  final built = <Anchor>[];
  for (final (p0, p1, p2, p3) in cubics) {
    if (built.isEmpty) {
      built.add(Anchor(id: _synth, position: p0, outTangent: p1 - p0));
    } else {
      final joint = built.removeLast();
      built.add(Anchor(
        id: _synth,
        position: joint.position,
        inTangent: joint.inTangent,
        outTangent: p1 - p0,
      ));
    }
    built.add(Anchor(id: _synth, position: p3, inTangent: p2 - p3));
  }
  return <Anchor>[
    for (var i = 0; i < built.length; i++)
      Anchor(
        id: AnchorId('trim:$i'),
        position: built[i].position,
        inTangent: built[i].inTangent,
        outTangent: built[i].outTangent,
      ),
  ];
}

/// A placeholder id for anchors mid-construction in [_anchorsFromCubics]; every
/// one is replaced by a unique `trim:$i` before the [PathData] is built, so the
/// duplicates it produces never reach `PathData.trusted`.
const AnchorId _synth = AnchorId('~trim');

// ---------------------------------------------------------------------------
// Stage 8 — resolvePaint
// ---------------------------------------------------------------------------

/// Populates each node's fills and strokes, with the animated paint channels
/// sampled in stage 1 written over the authored values (F8/F9.2).
///
/// [composeWorldA] deliberately leaves `fills`/`strokes` empty so there is
/// exactly one place that decides what a node is painted with. A sampled
/// `fillColor` replaces that fill's [SolidPaint] colour (matched by `PaintId`);
/// `fillOpacity`/`strokeOpacity`/`strokeWidth` replace their channel. An unkeyed
/// channel keeps the authored value (the pose fallback), and a colour keyed onto
/// a **gradient** paint is skipped — a gradient has no solid colour to write, and
/// gradients are rendered, not authored (it is left as-is, never a throw).
EvalFrame resolvePaint(EvalFrame frame) {
  final index = frame.doc.nodeIndex;
  return frame.copyWith(nodes: <ResolvedNode>[
    for (final n in frame.nodes)
      switch (index[n.path.nodeId]) {
        final PathNode p => n.copyWith(
            fills: _resolveFills(p.fills, frame.samples[n.path.nodeId]),
            strokes: _resolveStrokes(p.strokes, frame.samples[n.path.nodeId]),
          ),
        _ => n,
      },
  ]);
}

List<Fill> _resolveFills(List<Fill> fills, NodeSample? sample) {
  if (sample == null ||
      (sample.fillColors.isEmpty && sample.fillOpacities.isEmpty)) {
    return fills;
  }
  return <Fill>[
    for (final f in fills) _applyFill(f, sample),
  ];
}

Fill _applyFill(Fill f, NodeSample sample) {
  final color = sample.fillColors[f.id];
  final opacity = sample.fillOpacities[f.id];
  if (color == null && opacity == null) return f;
  // A colour only writes onto a solid paint; a gradient is left untouched.
  final paint =
      color != null && f.paint is SolidPaint ? SolidPaint(color) : null;
  return f.copyWith(paint: paint, opacity: opacity);
}

List<Stroke> _resolveStrokes(List<Stroke> strokes, NodeSample? sample) {
  if (sample == null ||
      (sample.strokeColors.isEmpty &&
          sample.strokeOpacities.isEmpty &&
          sample.strokeWidths.isEmpty)) {
    return strokes;
  }
  return <Stroke>[
    for (final s in strokes) _applyStroke(s, sample),
  ];
}

Stroke _applyStroke(Stroke s, NodeSample sample) {
  final color = sample.strokeColors[s.id];
  final opacity = sample.strokeOpacities[s.id];
  final width = sample.strokeWidths[s.id];
  if (color == null && opacity == null && width == null) return s;
  final paint =
      color != null && s.paint is SolidPaint ? SolidPaint(color) : null;
  return s.copyWith(paint: paint, opacity: opacity, width: width);
}
