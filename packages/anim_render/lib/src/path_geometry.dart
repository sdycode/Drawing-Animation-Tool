/// `PathData` → `dart:ui.Path` (docs/v3/04 §5).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anim_core/anim_core.dart';

/// Builds the `ui.Path` for one node's geometry.
///
/// Every segment is emitted as a cubic, with no polyline branch: a `corner`
/// anchor has zero tangents, so `cubicTo` collapses to a straight line on its
/// own. Legacy carried separate straight/curve paths that disagreed about
/// where a segment ended.
///
/// Total by construction — a degenerate path yields an empty `ui.Path` rather
/// than throwing, because the pen tool produces exactly that on its first
/// click and a half-drawn shape must not take the canvas down.
ui.Path buildPath(PathData data) {
  final path = ui.Path();
  final anchors = data.anchors;
  if (anchors.length < 2) return path;

  path.moveTo(anchors.first.position.x, anchors.first.position.y);
  for (var k = 0; k < data.segmentCount; k++) {
    final (_, p1, p2, p3) = data.segment(k);
    path.cubicTo(p1.x, p1.y, p2.x, p2.y, p3.x, p3.y);
  }
  if (data.closed) path.close();
  return path;
}

/// The document→screen transform: letterbox the artboard into [size].
///
/// **One uniform factor, never one per axis.** Legacy scaled Y by the width
/// ratio, which is invisible on a square board and drifts on every other one.
///
/// Returned as an [Affine] rather than applied directly to a canvas so that the
/// painter and the editor's hit-testing use the *same* mapping — computing the
/// fit twice is how a click lands somewhere the shape is not.
Affine artboardFit(Vec2 artboard, ui.Size size) {
  if (artboard.x <= 0 || artboard.y <= 0) return Affine.identity;
  final scale = math.min(size.width / artboard.x, size.height / artboard.y);
  return Affine.translate(
    (size.width - artboard.x * scale) / 2,
    (size.height - artboard.y * scale) / 2,
  ).mul(Affine.scale(scale, scale));
}

/// The **whole** document→screen mapping: the editor's pan/zoom [viewport]
/// composed over [artboardFit] (owner decision, docs/v3/05 §3).
///
/// **This is the one and only place the two matrices are combined** (AC-3.1.4).
/// The canvas computes it once per frame, hands the *result* to all three
/// painters as their `fit`, and inverts the *same* result for hit-testing —
/// so a click, the geometry it lands on, and the board it lands over are all
/// governed by a single `Affine`. Composing viewport∘fit a second time
/// somewhere else is exactly how a click lands where the shape is not, and a
/// per-axis scale helper on top of it is the legacy y-scaled-by-width bug
/// (docs/v3/08 §4). `viewport` is identity by default, so the default result is
/// a plain letterbox.
///
/// `mul` is `this ∘ o` (apply `o` first): [artboardFit] maps document→fitted
/// screen, then [viewport] pans/zooms within that fitted screen.
Affine composedFit(Affine viewport, Vec2 artboard, ui.Size size) =>
    viewport.mul(artboardFit(artboard, size));

/// Who the canvas is being drawn for, and therefore whether the board clips.
///
/// AC-1.1.3 is explicit: a node outside the artboard **draws**, is selectable,
/// "and is clipped only at the artboard boundary in the export preview". An
/// editor that clips unconditionally is the defect this enum exists to name —
/// [hitTestScene] applies no clip and the overlay draws none either, so a
/// clipped geometry layer leaves the user a selection box and anchor handles
/// floating over blank canvas around a shape they cannot see but can still
/// click and drag.
enum RenderMode {
  /// The editor: nothing is clipped, so what the user can click is what the
  /// user can see.
  editor,

  /// The export preview: the artboard **is** the frame, so geometry stops at
  /// its edge — the same rect the exporter will encode.
  exportPreview,
}

/// The rect the artboard clips to under [mode], or null when nothing clips.
///
/// One definition, read by every painter that can clip, so the board, the
/// geometry and the overlay can never disagree about where the edge is — three
/// hand-rolled clips is the same defect as three hand-rolled fits, one layer
/// down. Computed in **screen** space because the composed fit is
/// translate + uniform-scale only (a pan/zoom adds no rotation), so the board's
/// rect maps to a rect exactly.
ui.Rect? artboardClipRect(RenderMode mode, Vec2 artboard, Affine fit) {
  if (mode == RenderMode.editor) return null;
  final origin = fit.apply(Vec2.zero);
  final corner = fit.apply(artboard);
  return ui.Rect.fromPoints(
    ui.Offset(origin.x, origin.y),
    ui.Offset(corner.x, corner.y),
  );
}

/// The **world-space** box a node occupies for selection, or null when it
/// encloses nothing.
///
/// For a path node this is the axis-aligned bound of its posed anchors *after*
/// the node's world matrix. For a **group** — which has no geometry of its own
/// — it is the union of its visible descendants' boxes. Without that a group is
/// second-class on the canvas: never hit-testable, and selected from the layers
/// panel with no outline to show for it, which is an odd result for a milestone
/// whose point is that the document is a real tree.
///
/// [hitTestScene] and the overlay's selection outline both read this **one**
/// function, so the box the user sees is exactly the area that answers a click.
/// Two independent bounds is how an outline ends up somewhere the node is not.
///
/// Hierarchy comes from [doc] (topology) and every coordinate comes from
/// [scene] (evaluated) — reading positions off the document here would be the
/// second evaluator docs/v3/08 §4 names. Recomputed on demand and **never
/// cached**: a stored AABB beside mutable geometry is the stale derived state
/// the same section forbids.
ui.Rect? selectionBounds(Scene scene, Document doc, ScenePath path) {
  final node = scene.byPath[path];
  if (node == null) return null; // resolved, never repaired: undo deleted it

  final geometry = node.geometry;
  if (geometry != null) return _geometryBounds(node, geometry);

  final subtree = doc.nodeIndex[path.nodeId];
  if (subtree == null) return null;

  ui.Rect? union;
  for (final descendant in _subtree(subtree)) {
    if (descendant.id == path.nodeId) continue;
    final resolved = scene.byPath[ScenePath(descendant.id)];
    if (resolved == null) continue;
    // A hidden descendant draws nothing, so it contributes no area to click:
    // otherwise the group's box would cover blank canvas.
    if (!resolved.worldVisible) continue;
    final childGeometry = resolved.geometry;
    if (childGeometry == null) continue; // a nested group: its children answer
    final box = _geometryBounds(resolved, childGeometry);
    if (box == null) continue;
    union = union == null ? box : union.expandToInclude(box);
  }
  return union;
}

/// The AABB of [geometry] posed by [node]'s world matrix, or null when it
/// cannot be placed.
///
/// Sampled from the anchor positions — enough for M2's straight-edged shapes;
/// curve-tight bounds are an M3 refinement and would only ever shrink the box,
/// never move what it encloses.
ui.Rect? _geometryBounds(ResolvedNode node, PathData geometry) {
  if (!isPlaceable(node.world)) return null;
  double? minX, minY, maxX, maxY;
  for (final a in geometry.anchors) {
    final w = node.world.apply(a.position);
    if (!w.x.isFinite || !w.y.isFinite) continue;
    minX = (minX == null || w.x < minX) ? w.x : minX;
    minY = (minY == null || w.y < minY) ? w.y : minY;
    maxX = (maxX == null || w.x > maxX) ? w.x : maxX;
    maxY = (maxY == null || w.y > maxY) ? w.y : maxY;
  }
  if (minX == null || minY == null || maxX == null || maxY == null) return null;
  return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
}

Iterable<Node> _subtree(Node node) sync* {
  yield node;
  if (node is GroupNode) {
    for (final child in node.children) {
      yield* _subtree(child);
    }
  }
}

/// True when [m] maps area to area and carries no NaN.
///
/// [Affine.invert] alone is not enough: its singularity test is
/// `determinant.abs() < 1e-12`, and every comparison against NaN is false, so a
/// matrix full of NaNs inverts "successfully" into more NaNs. `Canvas.transform`
/// with a NaN then poisons the whole layer, not just this node.
bool isPlaceable(Affine m) =>
    m.a.isFinite &&
    m.b.isFinite &&
    m.c.isFinite &&
    m.d.isFinite &&
    m.tx.isFinite &&
    m.ty.isFinite &&
    m.invert() != null;

/// The front-most node in [scene] whose posed geometry contains [docPoint], or
/// null on empty space (docs/v3/05 §3, the Select tool).
///
/// **Front-most wins** — the walk is `drawOrder.reversed`, so the last-painted
/// (top) node is tested first, matching what the user sees. **Locked and hidden
/// nodes are not hit** (AC-2.2.6): `worldVisible` is checked here, and the
/// caller supplies [isHittable] to exclude locked nodes (locked is a hit gate,
/// not a render gate, so it is not on `ResolvedNode` — docs/v3/01 §3). The point
/// is taken to node-local space through the node's **own inverted world**, the
/// very matrix the painter used, so the hit region is the pixels that were
/// drawn. A singular world (an animator keyed scale to 0) inverts to null and is
/// skipped — an early return, never `invert()!` (docs/v3/08 §4).
///
/// **A group is hittable too**, over the [selectionBounds] union of its
/// descendants — the same box the overlay outlines. Because `composeWorldA`
/// emits a group *before* its children, the reversed walk tests children first,
/// so a click on a child selects the child and only the gaps between them fall
/// through to the group. [doc] supplies that hierarchy, and it is also what
/// excludes the **root**: the root is the canvas itself, not a node the user
/// may select or drag.
///
/// `AnchorId`s are never consulted, so a synthetic-anchor trim result (M6) is
/// harmless: this tests the *filled region*, not the handles.
ScenePath? hitTestScene(
  Scene scene,
  Document doc,
  Vec2 docPoint,
  bool Function(ScenePath) isHittable,
) {
  final point = ui.Offset(docPoint.x, docPoint.y);
  for (final node in scene.drawOrder.reversed) {
    if (!node.worldVisible) continue;
    if (node.path.nodeId == doc.root.id) continue; // the root is not a node
    if (!isHittable(node.path)) continue; // locked: gated by the caller

    final geometry = node.geometry;
    if (geometry == null) {
      // A group: no fill of its own, so its hit area is the box the user sees
      // when it is selected. Null (an empty or fully hidden group) is nothing
      // to hit, which is honest — there is nothing on screen either.
      final bounds = selectionBounds(scene, doc, node.path);
      if (bounds != null && bounds.contains(point)) return node.path;
      continue;
    }

    final inverse = node.world.invert();
    if (inverse == null) continue; // collapsed: nothing to hit
    final local = inverse.apply(docPoint);
    if (buildPath(geometry).contains(ui.Offset(local.x, local.y))) {
      return node.path;
    }
  }
  return null;
}

/// Where a pen click would split a node's posed outline — the mid-segment
/// insert of docs/v3/05 §3 and AC-4.3.1.
///
/// [after] is the **left** anchor of the hit segment (the `after:` argument
/// `PathOps.insertAnchor` splices behind, respecting the closed wrap) and [u] is
/// the parameter on that segment's cubic, already clamped into the open interval
/// `(0,1)` the op requires. [local] is the projected point in the node's own
/// space; [world] is the same point through the node's world matrix, for the
/// screen-distance gate and the overlay `+`.
class PathInsertHit {
  const PathInsertHit({
    required this.after,
    required this.u,
    required this.local,
    required this.world,
  });

  final AnchorId after;
  final double u;
  final Vec2 local;
  final Vec2 world;
}

/// The nearest mid-segment insertion on [nodeId]'s **posed** geometry to
/// [docPoint], or null when the node has no path, no segment, or a collapsed
/// world.
///
/// The geometry is stages **1–3** (`composeWorldA(resolvePose(sampleTracks…))`),
/// exactly what the overlay draws and the direct-select hit-test grabs — strictly
/// pre-trim, so every `AnchorId` here is the authored one and [PathInsertHit.after]
/// is an id `PathOps.insertAnchor` will find in the topology (stage 7's synthetic
/// trim ids never reach this). The point is taken to node-local space through the
/// node's **own inverted world** — the same matrix the painter used — then
/// projected onto each cubic.
///
/// A pure read: it evaluates a frame and returns a candidate, mutating nothing.
PathInsertHit? insertionCandidate(
  Document doc,
  List<AnimationMix> mix,
  NodeId nodeId,
  Vec2 docPoint,
) {
  final frame = composeWorldA(resolvePose(sampleTracks(doc, mix)));
  for (final node in frame.nodes) {
    if (node.path.nodeId != nodeId) continue;
    final geometry = node.geometry;
    if (geometry == null || geometry.segmentCount == 0) return null;
    // Early return, never `invert()!` (docs/v3/08 §4): a node keyed to a
    // collapsed scale has nowhere on the artboard a click could land.
    final worldToLocal = node.world.invert();
    if (worldToLocal == null) return null;
    final local = worldToLocal.apply(docPoint);

    AnchorId? bestAfter;
    var bestU = 0.5;
    var bestPoint = Vec2.zero;
    var bestDist = double.infinity;
    for (var k = 0; k < geometry.segmentCount; k++) {
      final (p0, p1, p2, p3) = geometry.segment(k);
      final (u, point) = _projectOntoCubic(p0, p1, p2, p3, local);
      final dx = point.x - local.x;
      final dy = point.y - local.y;
      final dist = dx * dx + dy * dy;
      if (dist < bestDist) {
        bestDist = dist;
        bestAfter = geometry.anchors[k].id;
        bestU = u;
        bestPoint = point;
      }
    }
    if (bestAfter == null) return null;
    return PathInsertHit(
      after: bestAfter,
      u: bestU,
      local: bestPoint,
      world: node.world.apply(bestPoint),
    );
  }
  return null;
}

/// Samples for the coarse nearest-point pass. A cubic's foot-of-perpendicular
/// solve is a quintic in `u` with up to three stationary points, so a dense
/// sweep brackets **every** local minimum *before* Newton refines it — Newton
/// alone slides into whichever root it started next to.
///
/// Dense enough (was 24) that a self-crossing cubic whose two branches fold to
/// within a few px still lands one sample on each: at 48, adjacent samples are
/// ~1/48 of the arc apart, so two feet that close resolve to two separate
/// coarse minima rather than merging into one and hiding a branch.
const int _insertSamples = 48;

/// `u` is kept strictly inside `(0,1)`; `PathOps.insertAnchor` refuses the
/// endpoints (they are existing anchors, not a split).
const double _insertMinU = 1e-6;

/// The parameter and point on the cubic `[p0,p1,p2,p3]` nearest to [q].
///
/// **Every** local minimum of `|B(u)-q|²` is refined, not just the one nearest
/// coarse sample. The old single-bracket solve found one minimum and Newton'd
/// from it, which is correct on a convex/monotone cubic — but a cubic can fold so
/// two of its branches pass within ~3 px of each other (a loop drawn with strong
/// opposing tangents), and then the true foot can sit on the branch the single
/// bracket did *not* cover: measured up to 2.63 px along the curve onto the wrong
/// branch. So the coarse sweep keeps every sample that is a local min of squared
/// distance, a few Newton steps on `d/du |B(u)-q|²` — **clamped to that sample's
/// bracket** so refinement never leaves the neighbourhood the sweep chose —
/// polish each, and the global best is returned. Still accurate to machine
/// precision for a query exactly on the curve (a single minimum), the case the
/// insert test asserts on; cheap enough for a hover frame (a fixed sweep and one
/// short Newton per local min, of which a cubic has at most three).
(double, Vec2) _projectOntoCubic(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, Vec2 q) {
  double squaredDist(double u) {
    final b = _cubicAt(p0, p1, p2, p3, u);
    final dx = b.x - q.x;
    final dy = b.y - q.y;
    return dx * dx + dy * dy;
  }

  // Coarse sweep: squared distance at every sample, kept so each interior point
  // can be tested against both neighbours for a local minimum.
  final dist = List<double>.generate(
      _insertSamples + 1, (i) => squaredDist(i / _insertSamples),
      growable: false);

  const step = 1.0 / _insertSamples;
  var bestU = 0.0;
  var bestDist = double.infinity;
  for (var i = 0; i <= _insertSamples; i++) {
    // A local minimum of the coarse samples (endpoints compare only inward).
    // `<=` so a flat run still yields a seed; the global sample-min always
    // qualifies, so there is always at least one candidate to refine.
    final downLeft = i == 0 || dist[i] <= dist[i - 1];
    final downRight = i == _insertSamples || dist[i] <= dist[i + 1];
    if (!(downLeft && downRight)) continue;

    final seed = i * step;
    final lo = (seed - step).clamp(0.0, 1.0);
    final hi = (seed + step).clamp(0.0, 1.0);
    var u = seed;
    for (var iter = 0; iter < 16; iter++) {
      final b = _cubicAt(p0, p1, p2, p3, u);
      final d1 = _cubicDeriv(p0, p1, p2, p3, u);
      final d2 = _cubicDeriv2(p0, p1, p2, p3, u);
      final ex = b.x - q.x;
      final ey = b.y - q.y;
      final f1 = ex * d1.x + ey * d1.y; // ½·f'(u)
      final f2 = d1.x * d1.x + d1.y * d1.y + ex * d2.x + ey * d2.y; // ½·f''(u)
      if (f2 == 0 || !f2.isFinite) break;
      final next = (u - f1 / f2).clamp(lo, hi);
      if ((next - u).abs() < 1e-12) {
        u = next;
        break;
      }
      u = next;
    }
    final refined = squaredDist(u);
    if (refined < bestDist) {
      bestDist = refined;
      bestU = u;
    }
  }

  bestU = bestU.clamp(_insertMinU, 1.0 - _insertMinU);
  return (bestU, _cubicAt(p0, p1, p2, p3, bestU));
}

Vec2 _cubicAt(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final v = 1.0 - u;
  final a = v * v * v;
  final b = 3 * v * v * u;
  final c = 3 * v * u * u;
  final d = u * u * u;
  return Vec2(
    a * p0.x + b * p1.x + c * p2.x + d * p3.x,
    a * p0.y + b * p1.y + c * p2.y + d * p3.y,
  );
}

Vec2 _cubicDeriv(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final v = 1.0 - u;
  final a = 3 * v * v;
  final b = 6 * v * u;
  final c = 3 * u * u;
  return Vec2(
    a * (p1.x - p0.x) + b * (p2.x - p1.x) + c * (p3.x - p2.x),
    a * (p1.y - p0.y) + b * (p2.y - p1.y) + c * (p3.y - p2.y),
  );
}

Vec2 _cubicDeriv2(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final v = 1.0 - u;
  return Vec2(
    6 * v * (p2.x - 2 * p1.x + p0.x) + 6 * u * (p3.x - 2 * p2.x + p1.x),
    6 * v * (p2.y - 2 * p1.y + p0.y) + 6 * u * (p3.y - 2 * p2.y + p1.y),
  );
}

/// `Affine` → `Matrix4`-shaped storage, the only place the two conventions meet.
///
/// `Affine` is `[a c tx ; b d ty]`; `ui`/`vector_math` want a column-major 4×4.
/// Written once, here, so no call site hand-rolls the mapping and transposes it
/// by accident.
Float64List affineToMatrix4(Affine m) {
  final s = Float64List(16);
  s[0] = m.a;
  s[1] = m.b;
  s[4] = m.c;
  s[5] = m.d;
  s[10] = 1.0;
  s[12] = m.tx;
  s[13] = m.ty;
  s[15] = 1.0;
  return s;
}
