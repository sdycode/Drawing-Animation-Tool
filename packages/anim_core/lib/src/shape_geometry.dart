/// Recipe → geometry (docs/v3/01 §5, AC-4.1.4).
///
/// The one direction of travel a [ShapeRecipe] has: parameters in, [PathData]
/// out. Nothing here reads geometry back into a recipe, because that inverse
/// does not exist — a rectangle whose corner was dragged is no longer a
/// rectangle, which is exactly why the authority rule (docs/v3/01 §5) nulls the
/// recipe on any manual edit rather than trying to re-derive one.
///
/// ## Why this is a separate file, and an extension
///
/// [ShapeRecipeGeometry.toPath] is an **extension**, not a member of
/// [ShapeRecipe]. Extensions dispatch statically and are invisible through the
/// sealed supertype, so the recipe types stay literally inert: there is no
/// virtual member for the evaluator or a painter to reach through, and a
/// `switch` in `evaluate` cannot accidentally grow a `recipe.toPath()` fast
/// path. `recipe_test.dart` asserts the evaluated output is byte-identical with
/// and without a recipe; keeping the behaviour in a file the eval path does not
/// import is what keeps that assertion true by construction rather than by
/// vigilance. The evaluator walks `PathNode.path` and nothing else.
///
/// ## Totality
///
/// Every function here is pure and **total**. A shape tool drags through
/// `w = 0`, through `radius = 0`, and through a half-built `sides = 0` spinner
/// value on its way to a real shape, and it does so once per pointer move. A
/// throw on the way is not a caught error — `anim_core` has no `try` (docs/v3/08
/// §1) — it is a dead drag. Degenerate parameters therefore produce empty or
/// minimal geometry, which invariant P2 already defines as "renders nothing,
/// never throws".
///
/// ## Ids
///
/// Every anchor gets a **freshly minted** [AnchorId] from [uuidV4]. Never
/// `'anchor-$k'`, never the loop index, never a hash of the parameters. Two
/// rectangles built from the same numbers must not share ids: ids are the join
/// between a node's topology and every keyframe pose of every path track, and a
/// derived id is the legacy index-tweening defect wearing a string.
library;

import 'dart:math' as math;

import 'path.dart';
import 'primitives.dart';
import 'recipe.dart';
import 'uuid.dart';

/// The circle-to-cubic constant, `4/3 · (√2 − 1) = 0.5522847…`, written to four
/// places exactly as docs/v3/01 §5 states it.
///
/// The truncation is deliberate: the spec names `0.5523` and a reader greps for
/// that number, so the constant matches the document rather than out-precisioning
/// it. The cost is a maximum radial error of ~2.7e-4·r — 0.03 px on a 100 px
/// circle, three orders of magnitude below the flattening tolerance any
/// rasteriser applies afterwards.
///
/// **This constant is the whole point of [ellipsePath].** Legacy drew circles by
/// polygonising them into 114 straight segments: 114 anchors that could not be
/// hand-edited, could not be morphed against anything, blew up every keyframe
/// pose map, and still looked faceted under zoom. Four real cubics are exact
/// enough to be indistinguishable and few enough to drag by hand.
const double kKappa = 0.5523;

/// The largest `sides` [polygonPath] will build.
///
/// A polygon with more sides than this is a circle with a catastrophic anchor
/// count, and the [EllipseRecipe] is the correct tool for that shape. The cap
/// exists so a spinner that arrives at `1e9` — through a paste, a bad decode, or
/// a held arrow key — clamps instead of trying to allocate two billion anchors.
/// Clamping rather than returning empty keeps the tool responsive at the top of
/// its range; the geometry stays deterministic, so a regeneration from the same
/// recipe reproduces it exactly.
const int kMaxPolygonSides = 1000;

/// The single entry point: decide the shape, build its anchors.
extension ShapeRecipeGeometry on ShapeRecipe {
  /// Fresh geometry for this recipe, centred on the node's local origin.
  ///
  /// **Centred, not corner-anchored.** The recipe carries no position; where the
  /// shape sits is the node's `Transform2`, and rotation and scale read from the
  /// node's `pivot`. A shape whose geometry started at `(0,0)` and grew right
  /// and down would rotate about its top-left corner unless every shape tool
  /// remembered to write a compensating pivot — one forgotten write and the
  /// object spins off-screen.
  ///
  /// An [UnknownRecipe] yields [PathData.empty] and, more importantly, is
  /// refused outright by `PathOps.regenerateRecipe`: a recipe this build cannot
  /// read must never be allowed to overwrite geometry it did not create.
  PathData toPath() => switch (this) {
        final RectRecipe r => rectPath(r),
        final EllipseRecipe e => ellipsePath(e),
        final PolygonRecipe p => polygonPath(p),
        UnknownRecipe() => PathData.empty,
      };
}

/// Four anchors, or **eight** when [RectRecipe.cornerRadius] is positive.
///
/// Draw order is clockwise from the top-left in a y-down space, starting at the
/// top edge. The corner arcs are real cubics at [kKappa], never a fan of short
/// straight segments: a rounded rectangle approximated by line segments is the
/// same defect as the polygonised circle, just less obvious, and it makes the
/// corner un-editable as a corner.
///
/// [RectRecipe.cornerRadius] is **clamped to `min(w, h) / 2`**. A radius larger
/// than half the shorter side has no meaning — the two arcs on one edge would
/// overlap and the offsets would cross, inverting the edge into a bow-tie. The
/// user's number is kept in the recipe verbatim and only the *geometry* clamps,
/// so dragging the radius slider past the limit parks the shape at a stadium
/// and dragging back recovers exactly, with no hysteresis.
///
/// Degenerate `w` or `h` (zero, negative, NaN, infinite) yields [PathData.empty]
/// — the state every rectangle tool passes through on its first pointer-down.
PathData rectPath(RectRecipe r) {
  if (!_positive(r.w) || !_positive(r.h)) return PathData.empty;

  final hw = r.w / 2;
  final hh = r.h / 2;
  final radius = _positive(r.cornerRadius)
      ? math.min(r.cornerRadius, math.min(hw, hh))
      : 0.0;

  if (radius == 0.0) {
    return PathData(
      closed: true,
      anchors: <Anchor>[
        _anchor(Vec2(-hw, -hh)),
        _anchor(Vec2(hw, -hh)),
        _anchor(Vec2(hw, hh)),
        _anchor(Vec2(-hw, hh)),
      ],
    );
  }

  // Each rounded-corner anchor has ONE zero handle (the straight edge it starts)
  // and one κ handle pointing INTO the corner it curves around. The two are
  // perpendicular, so the kind is `corner` — independent handles — and saying
  // `smooth` here would be a lie the first handle drag would violently correct.
  final k = radius * kKappa;
  return PathData(
    closed: true,
    anchors: <Anchor>[
      _anchor(Vec2(-hw + radius, -hh), inT: Vec2(-k, 0)),
      _anchor(Vec2(hw - radius, -hh), outT: Vec2(k, 0)),
      _anchor(Vec2(hw, -hh + radius), inT: Vec2(0, -k)),
      _anchor(Vec2(hw, hh - radius), outT: Vec2(0, k)),
      _anchor(Vec2(hw - radius, hh), inT: Vec2(k, 0)),
      _anchor(Vec2(-hw + radius, hh), outT: Vec2(-k, 0)),
      _anchor(Vec2(-hw, hh - radius), inT: Vec2(0, k)),
      _anchor(Vec2(-hw, -hh + radius), outT: Vec2(0, -k)),
    ],
  );
}

/// **Exactly four anchors**, four real cubics, tangents `±κ·r` along the axis
/// (docs/v3/01 §5).
///
/// Clockwise in y-down from `(rx, 0)`. At each anchor the curve runs parallel to
/// one axis, so the handles are axis-aligned and mirrored: `inTangent =
/// -outTangent`, which is precisely [AnchorKind.symmetric], and the kind is
/// stored to match. That is what makes an ellipse *editable* — drag one handle
/// and `PathOps.setTangents` keeps the opposite one mirrored, so the shape
/// deforms like a curve instead of developing a kink.
///
/// Four is not a tuning parameter. It is the smallest count that keeps every
/// quadrant a single cubic, it is what makes "circle → square" a four-anchor
/// morph with no retopologise at all, and it is the direct answer to legacy's
/// 114 straight segments.
///
/// A non-positive or non-finite `rx`/`ry` yields [PathData.empty] — an ellipse
/// tool reports zero radii for the whole first frame of every drag.
PathData ellipsePath(EllipseRecipe e) {
  if (!_positive(e.rx) || !_positive(e.ry)) return PathData.empty;

  final kx = e.rx * kKappa;
  final ky = e.ry * kKappa;
  return PathData(
    closed: true,
    anchors: <Anchor>[
      _anchor(Vec2(e.rx, 0),
          inT: Vec2(0, -ky), outT: Vec2(0, ky), kind: AnchorKind.symmetric),
      _anchor(Vec2(0, e.ry),
          inT: Vec2(kx, 0), outT: Vec2(-kx, 0), kind: AnchorKind.symmetric),
      _anchor(Vec2(-e.rx, 0),
          inT: Vec2(0, ky), outT: Vec2(0, -ky), kind: AnchorKind.symmetric),
      _anchor(Vec2(0, -e.ry),
          inT: Vec2(-kx, 0), outT: Vec2(kx, 0), kind: AnchorKind.symmetric),
    ],
  );
}

/// `sides` corner anchors, or `2 · sides` alternating outer/inner ones when
/// [PolygonRecipe.star].
///
/// Every anchor has **zero tangents**: a polygon is straight-sided, and a
/// straight side is the degenerate cubic (docs/v3/01 §5). There is no polyline
/// branch to take — one segment type, always, which is what AC-4.1.2 asserts by
/// inspection.
///
/// The first vertex sits at angle `-π/2`, straight **up** in the y-down artboard
/// space, so a triangle points up and a five-point star looks like a five-point
/// star instead of resting on a vertex. Winding is clockwise on screen, matching
/// [rectPath] and [ellipsePath] — mixed winding between shape tools is how a
/// `FillRule.evenOdd` document develops holes nobody authored.
///
/// [PolygonRecipe.innerRatio] is clamped to `0..1`. `0` collapses every inner
/// vertex onto the centre (a valid, if spiky, star), `1` makes the inner ring
/// coincide with the outer and yields a regular `2n`-gon. Both are legal
/// geometry and neither throws: the ratio is a live slider, and its endpoints
/// are the two values a user drags to first.
///
/// `sides < 3` yields [PathData.empty] — two "sides" is a line and one is a
/// point, and a polygon spinner passes through both while the user is typing.
PathData polygonPath(PolygonRecipe p) {
  if (p.sides < 3 || !_positive(p.radius)) return PathData.empty;

  final sides = math.min(p.sides, kMaxPolygonSides);
  final inner = p.innerRatio.isFinite ? p.innerRatio.clamp(0.0, 1.0) : 0.0;
  final count = p.star ? sides * 2 : sides;
  final step = 2 * math.pi / count;

  final anchors = <Anchor>[];
  for (var k = 0; k < count; k++) {
    final radius = p.star && k.isOdd ? p.radius * inner : p.radius;
    final angle = -math.pi / 2 + step * k;
    anchors
        .add(_anchor(Vec2(radius * math.cos(angle), radius * math.sin(angle))));
  }
  return PathData(closed: true, anchors: anchors);
}

/// One anchor with a **fresh** id. The only place this file mints one.
Anchor _anchor(
  Vec2 position, {
  Vec2 inT = Vec2.zero,
  Vec2 outT = Vec2.zero,
  AnchorKind kind = AnchorKind.corner,
}) =>
    Anchor(
      id: AnchorId(uuidV4()),
      position: position,
      inTangent: inT,
      outTangent: outT,
      kind: kind,
    );

/// Finite and greater than zero — the one usability test every parameter takes.
///
/// NaN and infinity fail it rather than propagating: an infinite half-width
/// reaches the rasteriser as an infinite control point and takes the artboard
/// with it, and NaN poisons every arithmetic result downstream of it silently.
bool _positive(double v) => v.isFinite && v > 0.0;
