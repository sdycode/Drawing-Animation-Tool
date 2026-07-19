# 01 — Domain Model (v3)

**What this doc is:** the authoritative specification of the v3 domain layer — every Dart type, every invariant, the mutation API that enforces them, and the evaluator. Pure Dart: no `dart:ui`, no Flutter imports, no `BuildContext`, no pixels. Everything below is unit-testable in a plain `test()`. It also has **zero persistence imports** — no `cloud_firestore`, no `http` — persistence reaches the domain only through the `ProjectStore` seam (String in / String out), defined in doc 04 (architecture).

**What it is not:** the product scope (see [00_vision_and_scope.md](00_vision_and_scope.md)), the wire format (see [02_file_format.md](02_file_format.md)), the renderer, or the UI. **If this doc and doc 02 disagree, this doc wins and doc 02 is the bug.**

---

## 1. The one insight

> **Every anchor has a stable, opaque string ID. Keyframes match anchors BY ID. Never by array index.**

The legacy app tweened vertices by array position:

```dart
// legacy: get_animatedpoints.dart:68-79
for (var i = 0; i < frames[preFrameNo].points.length; i++) {   // bound from the FROM-frame only
  animated.add(lerp(frames[preFrameNo].points[i], frames[preFrameNo + 1].points[i], t));
}
```

Consequences, all of which shipped:

| Legacy behaviour | Cause |
| --- | --- |
| Adding a node in one keyframe mis-pairs every subsequent vertex | index correspondence |
| `RangeError` swallowed per-point, spawning a modal dialog **per frame** | loop bound taken from the FROM-frame |
| Animation silently *stops* after a node edit | the 2-frame engine gated on `points.length ==` |
| The format structurally cannot express a node added mid-animation | point counts are constant in every section of every shipped sample — that is the contract being obeyed, not a coincidence |

**Node editing was impossible. That single defect is the reason v3 exists.**

The v3 answer is stronger than "match by ID": in v3 a mismatched anchor set is **not a representable state**.

| Where identity lives | Rule |
| --- | --- |
| `PathNode.path` (`PathData`) | The **authoritative** anchor set, draw order, and `closed` flag. One per node. |
| `PathTrack` keyframes (`PathPose`) | `Map<AnchorId, AnchorPose>` — **poses only**. No anchor list, no count, no order, no `closed`. |

Which anchors exist is a property of the *shape*, constant over time. Keyframes vary only where those anchors sit. Interpolation is a dictionary lookup driven by the node's topology — there is no index join anywhere in the evaluator, and no `points.length` comparison to fail.

### The three governing rules

1. **TOPOLOGY edits are DOCUMENT-WIDE for a node; POSE edits are KEYFRAME-LOCAL.** Inserting an anchor mints one `AnchorId`, adds it to the node's `PathData`, and backfills a pose into every keyframe of every path track for that node **across every animation**.
2. **`AnchorId` is unique within a `PathData`; `NodeId` is unique within a `Document`.** Enforced by validating factories and re-checked at decode. The whole ID join rests on this.
3. **The evaluator is TOTAL and CONTINUOUS.** Never throws, never returns NaN, never returns unexpected empty geometry — *and* the rendered output at `u = 1e-6` is within ε of the output at `u = 0`. Totality alone was never sufficient: a shape that collapses to a point on the first frame is total and wrong.

---

## 2. Identity and primitives

```dart
// Zero-cost typed wrappers. A NodeId can never be passed where an AnchorId is wanted.
// Values are UUID v4 (or short opaque strings for anchors — see doc 02 §9).
// Minted once at creation. NEVER reused. NEVER derived from list position or order.
extension type const NodeId(String v) {}
extension type const AnchorId(String v) {}
extension type const PaintId(String v) {}
extension type const StopId(String v) {}
extension type const AnimationId(String v) {}
```

**Decision: no `KeyframeId`.** Keyframes are addressed by their `t` at *command-construction* time and by list index thereafter; a keyframe is not referenced from anywhere else in the model, so an ID buys nothing. `TrackOps.moveKeyframe` takes an index, never a float (§12).

```dart
@immutable
final class Vec2 {
  final double x, y;
  const Vec2(this.x, this.y);
  static const zero = Vec2(0, 0);
  static const one  = Vec2(1, 1);

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);
  double get length => math.sqrt(x * x + y * y);

  static Vec2 lerp(Vec2 a, Vec2 b, double u) =>
      Vec2(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u);

  @override bool operator ==(Object o) => o is Vec2 && o.x == x && o.y == y;
  @override int get hashCode => Object.hash(x, y);
}
```

```dart
/// Straight (non-premultiplied) sRGB, doubles 0..1.
/// Decision: doubles, not a hex string and not a packed int — legacy stored
/// 'ffeee2dd' next to 'FFFFC0CB' and had to string-parse to render.
@immutable
final class Rgba {
  final double r, g, b, a;
  const Rgba(this.r, this.g, this.b, [this.a = 1.0]);
  static const transparent = Rgba(0, 0, 0, 0);
  static const black = Rgba(0, 0, 0);

  factory Rgba.fromArgb32(int v) => Rgba(
      ((v >> 16) & 0xFF) / 255, ((v >> 8) & 0xFF) / 255,
      (v & 0xFF) / 255, ((v >> 24) & 0xFF) / 255);

  /// Component-wise. Decision: straight sRGB lerp, not OKLab — slightly muddy
  /// through some hue transitions, and a `space` field is additive if it matters.
  static Rgba lerp(Rgba x, Rgba y, double u) => Rgba(
      x.r + (y.r - x.r) * u, x.g + (y.g - x.g) * u,
      x.b + (y.b - x.b) * u, x.a + (y.a - x.a) * u);
}
```

### `Affine` — the only transform type in the codebase

```dart
/// Matrix layout: [a c tx ; b d ty ; 0 0 1]
///
/// EVERY coordinate mapping routes through this type: parent→child, document→
/// screen, zoom/pan, hit-test, export. There is no hand-rolled per-axis scaling
/// anywhere in v3 — legacy scaled the Y component by the WIDTH ratio
/// (cast_control_points.dart), which drifts on any non-square artboard.
@immutable
final class Affine {
  final double a, b, c, d, tx, ty;
  const Affine(this.a, this.b, this.c, this.d, this.tx, this.ty);

  static const identity = Affine(1, 0, 0, 1, 0, 0);
  const Affine.translate(double x, double y) : this(1, 0, 0, 1, x, y);
  const Affine.scale(double sx, double sy)   : this(sx, 0, 0, sy, 0, 0);

  factory Affine.rotate(double r) {
    final cs = math.cos(r), sn = math.sin(r);
    return Affine(cs, sn, -sn, cs, 0, 0);
  }
  factory Affine.skewX(double k) => Affine(1, 0, math.tan(k), 1, 0, 0);

  /// this ∘ o — apply `o` first, then `this`.
  Affine mul(Affine o) => Affine(
        a * o.a + c * o.b,        b * o.a + d * o.b,
        a * o.c + c * o.d,        b * o.c + d * o.d,
        a * o.tx + c * o.ty + tx, b * o.tx + d * o.ty + ty,
      );

  /// Points (anchor positions).
  Vec2 apply(Vec2 p) => Vec2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty);

  /// Directions (bezier tangents are directions, NOT points — no translation).
  Vec2 applyVector(Vec2 v) => Vec2(a * v.x + c * v.y, b * v.x + d * v.y);

  double get determinant => a * d - b * c;

  /// null when singular (an animator WILL key scale to 0).
  /// Callers must handle null by rendering nothing — never by throwing.
  Affine? invert() {
    final det = determinant;
    if (det.abs() < 1e-12) return null;
    final id = 1.0 / det;
    return Affine(d * id, -b * id, -c * id, a * id,
        (c * ty - d * tx) * id, (b * tx - a * ty) * id);
  }

  /// QR decomposition back into transform components, for a given pivot.
  /// Required by world-preserving reparent (§12). Surjective for det != 0 even
  /// with skewY omitted. Round-trip property test: decompose(x.toAffine()) == x.
  Transform2? decompose({Vec2 pivot = Vec2.zero});
}
```

**Mandatory golden test:** identity, pure rotation about a non-origin pivot, non-uniform scale, and skew, each asserted against hand-computed points on a deliberately **450.2 × 250.4** artboard — the exact aspect ratio that exposed the legacy y-rescale bug. Plus an `invert()` round-trip and a `decompose(toAffine(x)) == x` property test.

---

## 3. Scene graph

```dart
sealed class Node {
  final NodeId id;
  final String name;
  final Transform2 transform;   // the POSE. Tracks override per-property.
  final double opacity;         // 0..1, multiplies down the tree
  final bool visible;           // authored; ANDs down the tree
  final bool locked;            // EDITOR ONLY. The evaluator never reads it.
  final Map<String, Object?> unknownKeys;   // forward-compat passthrough

  const Node({
    required this.id, required this.name,
    this.transform = Transform2.identity,
    this.opacity = 1.0, this.visible = true, this.locked = false,
    this.unknownKeys = const {},
  });
}

/// Container. Also the artboard root.
final class GroupNode extends Node {
  /// Z-ORDER **IS** THIS LIST. index 0 is painted FIRST (back-most).
  /// The layers panel displays it reversed. There is no zIndex field, so there
  /// is nothing to desync — the exact bug class that produced legacy's worst
  /// latent defect (a derived sorted array beside an unsorted authoritative one).
  final List<Node> children;
  final bool clipChildren;
  const GroupNode({required super.id, required super.name,
    this.children = const [], this.clipChildren = false, super.transform,
    super.opacity, super.visible, super.locked, super.unknownKeys});
}

/// The only leaf in v1.
final class PathNode extends Node {
  final PathData path;          // AUTHORITATIVE topology + rest pose
  final List<Fill> fills;       // painted in list order, first = bottom
  final List<Stroke> strokes;   // painted after all fills
  final ShapeRecipe? recipe;    // inert re-edit metadata; NEVER animated
  final PathTrim trim;          // draw-on / reveal
  const PathNode({required super.id, required super.name, required this.path,
    this.fills = const [], this.strokes = const [], this.recipe,
    this.trim = PathTrim.full, super.transform, super.opacity, super.visible,
    super.locked, super.unknownKeys});
}

/// FORWARD COMPATIBILITY, not a feature. A decoder meeting an unrecognized
/// node `type` keeps the raw JSON and re-emits it verbatim on save. Renders
/// nothing, unselectable, not hit-testable.
/// Without this, a v1 client opening a v2 (bones/instancing) document from
/// Firestore silently destroys it on autosave.
final class UnknownNode extends Node {
  final String rawType;
  final Map<String, Object?> raw;
  const UnknownNode({required super.id, required super.name,
    required this.rawType, required this.raw});
}
```

| Decision | Reason |
| --- | --- |
| **Nested tree** (`GroupNode.children`), not a flat `Map<NodeId, Node>` + `parentId` | One source of truth for hierarchy. A flat map plus child lists is dual bookkeeping needing a consistency pass at decode. |
| A `Map<NodeId, Node>` index is built **once per document mutation**, never per tick | O(1) track lookup and cross-tree reference (bones later) without the dual-bookkeeping cost. Derived, never persisted. |
| **Z-order is child-list order** | No index/order desync is possible. Reordering is a list splice. |
| `locked` is **authored and persisted**, but never read by the evaluator | It survives reload (unlike selection/hover, which are ephemeral). It is a hit-test gate only. |
| **No `includeInPlayback` field** — deleted | Legacy's `iconSectionIndexesToInclude` leaking into a clean schema. Two overlapping visibility booleans is two sources of truth. `visible` carries the meaning; a `BoolTrack` on `visible` animates it. |
| `Rect`/`ellipse`/`star`/`polygon` are **creation tools, not node types** | They emit anchors. `ShapeRecipe` keeps them re-editable at near-zero cost. A `ParametricShapeNode` is an additive sealed variant if it ever earns its place. |

**Visibility / opacity composition, stated once so it cannot drift:**

```
worldVisible = AND over the ancestor chain of the *sampled* `visible` value
worldOpacity = PRODUCT over the ancestor chain of the *sampled* `opacity` value
locked       = never read by the evaluator, at any depth
```

A hidden group hides all descendants regardless of their own tracks. **Test it.**

---

## 4. Transform

```dart
@immutable
final class Transform2 {
  final Vec2 position;    // artboard-relative document units
  final Vec2 scale;       // (1,1) = identity
  final Vec2 pivot;       // point in the node's OWN untransformed local space
  final double rotation;  // RADIANS, UNBOUNDED
  final double skewX;     // RADIANS

  const Transform2({
    this.position = Vec2.zero, this.scale = Vec2.one, this.pivot = Vec2.zero,
    this.rotation = 0.0, this.skewX = 0.0,
  });
  static const identity = Transform2();

  /// local = T(position) · T(pivot) · R(rotation) · SkewX(skewX) · S(scale) · T(-pivot)
  ///
  /// Composed from named Affine factories, NOT hand-inlined trig — this is the
  /// exact function whose legacy equivalent produced the y-rescale bug. The
  /// fast inlined form may be substituted only behind the golden test below.
  Affine toAffine() => Affine.translate(position.x, position.y)
      .mul(Affine.translate(pivot.x, pivot.y))
      .mul(Affine.rotate(rotation))
      .mul(Affine.skewX(skewX))
      .mul(Affine.scale(scale.x, scale.y))
      .mul(Affine.translate(-pivot.x, -pivot.y));

  Transform2 copyWith({Vec2? position, Vec2? scale, Vec2? pivot,
      double? rotation, double? skewX});
}
```

```
world(node) = world(parent) · local(node)
world(root) = Affine.identity        // artboard space IS document space
```

| Decision | Reason |
| --- | --- |
| **Rotation is unbounded raw radians, lerped raw.** No wrapping, no shortest-arc normalization, ever. | `-12.5664` means two full reverse turns and must *play* as two turns. Shortest-arc is exactly the "helpful" fix an implementer adds later that silently collapses every multi-turn spin. **Written invariant with a test.** |
| **`skewY` omitted** | `skewX` + rotation + non-uniform scale covers every skew the v1 UI will expose. One field and one term to add later. |
| **`pivot` is authored once at creation, never keyframed in v1** | It appears twice in `toAffine()` with opposite sign, so keying it while `scale != 1` *translates* the node — animating centre-pivot→bottom-pivot at a bounce impact makes the ball visibly jump. |
| Pivot default: **AABB centre of the node's geometry at creation time**, set by the create command — *not* `Vec2.zero`, and *not* derived thereafter | `Vec2.zero` in artboard-relative space is the artboard's top-left corner, so a freshly created group would rotate about the corner. A *derived* pivot would silently change meaning the moment a path track animates the geometry. `CreateGroupCommand` sets it to the union-AABB centre of its children. |

> ⚠ **`pivot` is NOT in the v1 animatable property list** (§7). Doc 02 §3.9 lists `pivot` in the `vec2` row; that row is wrong and doc 02 is the bug (per the header rule). The wire *type* stays `vec2` so enabling it later is additive.

---

## 5. Path geometry

```dart
/// Authoring hint ONLY. The renderer and the evaluator NEVER read it — they
/// read inTangent/outTangent verbatim. This keeps the evaluator total and makes
/// `kind` safe to change without re-tweening.
enum AnchorKind { corner, smooth, symmetric }

@immutable
final class Anchor {
  final AnchorId id;      // STABLE. Survives moves, reorders, keyframes, undo.
  final Vec2 position;
  final Vec2 inTangent;   // RELATIVE to position (Lottie `i` convention)
  final Vec2 outTangent;  // RELATIVE to position (Lottie `o` convention)
  final AnchorKind kind;
  const Anchor({required this.id, required this.position,
    this.inTangent = Vec2.zero, this.outTangent = Vec2.zero,
    this.kind = AnchorKind.corner});

  Anchor copyWith({Vec2? position, Vec2? inTangent, Vec2? outTangent, AnchorKind? kind});
}

/// TOPOLOGY + REST POSE. Lives on the node. Constant over time.
@immutable
final class PathData {
  final List<Anchor> anchors;   // DRAW ORDER — load-bearing (see invariants)
  final bool closed;            // lives ONLY here; cannot vary per keyframe

  const PathData._(this.anchors, this.closed);
  static const empty = PathData._(<Anchor>[], false);

  /// The ONLY public constructor. Const construction is private specifically so
  /// the invariants below cannot be bypassed (legacy's public const ctors
  /// enforced nothing).
  factory PathData({required List<Anchor> anchors, bool closed = false}) {
    final seen = <AnchorId>{};
    for (final a in anchors) {
      if (!seen.add(a.id)) {
        throw ArgumentError('duplicate AnchorId ${a.id.v}');
      }
    }
    return PathData._(List.unmodifiable(anchors), closed);
  }

  int get segmentCount => anchors.length < 2 ? 0 : (closed ? anchors.length : anchors.length - 1);
}
```

**Segment `k` is always the cubic** — there is one segment type, no polyline/curve branching:

```
P0 = a[k].position                     P1 = a[k].position   + a[k].outTangent
P3 = a[k+1].position                   P2 = a[k+1].position + a[k+1].inTangent
```

A `corner` anchor simply has zero tangents, making a straight line the degenerate cubic.

```dart
/// What a PATH KEYFRAME stores for one anchor. No id — the map key is the id.
@immutable
final class AnchorPose {
  final Vec2 position, inTangent, outTangent;
  const AnchorPose(this.position, this.inTangent, this.outTangent);

  static AnchorPose lerp(AnchorPose a, AnchorPose b, double u) => AnchorPose(
      Vec2.lerp(a.position,   b.position,   u),
      Vec2.lerp(a.inTangent,  b.inTangent,  u),
      Vec2.lerp(a.outTangent, b.outTangent, u));
}

/// The VALUE of a path keyframe. NOT a list. NOT an anchor count. NOT `closed`.
@immutable
final class PathPose {
  final Map<AnchorId, AnchorPose> anchors;
  const PathPose(this.anchors);
}
```

### Path invariants

| # | Invariant | Enforced by |
| --- | --- | --- |
| P1 | `AnchorId` unique within a `PathData` | validating factory + decoder |
| P2 | 0 or 1 anchor **renders nothing**, never throws | evaluator; the pen tool produces this on the first click |
| P3 | `closed` lives only on `PathData`, never per-keyframe | type shape |
| P4 | Anchor **sequence** (not just set) is the topology and is load-bearing for insert | `PathOps` is the only mutator |
| P5 | Every keyframe of every path track for a node poses a **subset** of that node's anchor ids | `PathOps` backfills; decoder validates |
| P6 | A pose entry for an id not in the topology is **dropped at decode** with a warning | orphan poses are the only way stale data survives |

### Primitives → paths

```dart
sealed class ShapeRecipe { const ShapeRecipe(); }
final class RectRecipe    extends ShapeRecipe { final double w, h, cornerRadius; }
final class EllipseRecipe extends ShapeRecipe { final double rx, ry; }
final class PolygonRecipe extends ShapeRecipe {
  final int sides; final double radius; final bool star; final double innerRatio;
}
```

| Rule | Statement |
| --- | --- |
| Recipes are **inert metadata**, never animated | Parametric-shape animation is a written non-goal. Promoting recipe params to properties later is additive. |
| Authority | The recipe **regenerates** `path`. Any manual anchor edit **nulls** the recipe. Without this rule, re-editing a rectangle silently discards manual edits. |
| **Regenerating a recipe on a node that has a path track routes through `PathOps.retopologize`** | A raw path replacement mints fresh ids ⇒ disjoint anchor sets ⇒ the whole model breaks. "Draw a square, change it to a star" is the single most likely user action in the headline demo, and this is the rule that makes it legal. |
| Ellipses are real cubics (4 anchors, κ = 0.5523) | Legacy polygonized circles into 114 straight segments. |

### `PathTrim`

```dart
@immutable
final class PathTrim {
  final double start, end, offset;   // fractions of TOTAL ARC LENGTH, 0..1
  const PathTrim({this.start = 0.0, this.end = 1.0, this.offset = 0.0});
  static const full = PathTrim();
}
```

| Rule | Statement |
| --- | --- |
| `end <= start` | Renders nothing. Empty geometry, never a throw, never a null deref. |
| Partial window on a `closed: true` path | Emits `closed: false`. You cannot fill a partially-revealed shape. |
| `start > end` (wrapped window) | **Clamped.** Wrapped windows are a written non-goal. |
| `offset` | Required, not optional — without it a closed path cannot start its reveal anywhere but anchor 0. |
| Arc-length table | Adaptive flattening per segment, cumulative table, **memoized per immutable `PathData`**. Rebuilding it per tick is the only real perf hazard in the model. |
| Output anchor ids | **Synthetic and non-authoritative.** Trim splits cubics and discards anchors. See §11. |

**Decision: no `Stroke.dash` / `dashOffset` in v1.** Dash-as-trim needs the authored total arc length, mis-renders on closed and multi-subpath geometry, and puts a derived geometric quantity into an authored field. Trim is the correct primitive.

---

## 6. Paint

```dart
enum FillRule   { nonZero, evenOdd }
enum StrokeCap  { butt, round, square }
enum StrokeJoin { miter, round, bevel }

/// Sealed NOW so gradients are additive later — adding a variant is a SOURCE
/// break (exhaustive switches) but never a DATA break, because `type` is an
/// open string with preserve-and-skip-render for unknown values.
sealed class PaintSource { const PaintSource(); }

final class SolidPaint extends PaintSource {
  final Rgba color;
  const SolidPaint(this.color);
}

@immutable
final class GradientStop {
  final StopId id;       // stable ⇒ individually animatable, reorder-safe
  final double offset;   // 0..1
  final Rgba color;
  const GradientStop({required this.id, required this.offset, required this.color});
}

final class LinearGradientPaint extends PaintSource {
  final Vec2 start, end;                 // node-local coordinates
  final List<GradientStop> stops;
  const LinearGradientPaint({required this.start, required this.end, required this.stops});
}

final class RadialGradientPaint extends PaintSource {
  final Vec2 center; final double radius;
  final List<GradientStop> stops;
  const RadialGradientPaint({required this.center, required this.radius, required this.stops});
}

@immutable
final class Fill {
  final PaintId id;      // the track's subjectId — survives reordering
  final PaintSource paint;
  final FillRule rule;
  final double opacity;
  final bool visible;
  const Fill({required this.id, required this.paint,
    this.rule = FillRule.nonZero, this.opacity = 1.0, this.visible = true});
}

@immutable
final class Stroke {
  final PaintId id;
  final PaintSource paint;
  final double width;
  final StrokeCap cap;
  final StrokeJoin join;
  final double miterLimit;
  final double opacity;
  final bool visible;
  const Stroke({required this.id, required this.paint, this.width = 1.0,
    this.cap = StrokeCap.butt, this.join = StrokeJoin.miter,
    this.miterLimit = 4.0, this.opacity = 1.0, this.visible = true});
}
```

| Decision | Reason |
| --- | --- |
| `fills` / `strokes` are **lists**; the v1 UI caps each at length 0 or 1 | Widening to multiple paints is additive rather than a schema break. |
| Every paint carries a stable **`PaintId`** even though v1 has at most one | `PropKey.fillColor` alone cannot say *which* fill. Retrofitting the subject id after documents exist is a schema break; it is free now, and it is also exactly what instance overrides will need. |
| Gradient types are **declared and rendered** in v1; **no gradient authoring UI** | CanvasKit gradients are ~20 lines; the *authoring UI* is the week-long part. Rendering-but-not-authoring avoids the "stub that reads as a bug" trap. Gradient stop channels are declared property names but are not exposed. |
| No `StrokeAlign`, no `BlendMode` in v1 | The UI will not expose them; both are additive optional fields. |

---

## 7. Property tracks

```
Animation ──> Map<NodeId, TrackSet> ──> Map<PropertyKey, Track>
```

**Decision: tracks hang off `Animation`, not off `Node`.** This is the single most important structural choice in the model, and it costs v1 nothing. It is what makes multiple clips, blending, and the state machine additive instead of a rewrite. It also preserves legacy's one genuinely correct property — **per-object independent timelines** — and generalizes it to per-property: each node owns its own keyframe positions, there is no global keyframe grid, and no derived parallel position array exists anywhere.

```dart
/// The closed set of animatable channels. An enum, not a string path, so
/// switches are exhaustive and typos are compile errors. Persisted BY NAME so
/// v2 can add members; unknown names are preserved-not-evaluated on decode.
enum PropKey {
  position, scale, rotation, skewX, opacity, visible,   // any node
  path,                                                 // path node
  fillColor, fillOpacity,                               // subjectId = PaintId
  strokeColor, strokeOpacity, strokeWidth,              // subjectId = PaintId
  trimStart, trimEnd, trimOffset,                       // path node
}

/// Addresses ONE channel on ONE node. `subjectId` is null in v1 for everything
/// except paint channels. Wire form: "rotation" | "fillColor:p-body".
@immutable
final class PropertyKey {
  final PropKey prop;
  final String? subjectId;      // PaintId | StopId | null
  const PropertyKey(this.prop, [this.subjectId]);

  @override bool operator ==(Object o) =>
      o is PropertyKey && o.prop == prop && o.subjectId == subjectId;
  @override int get hashCode => Object.hash(prop, subjectId);
}
```

### v1 animatable properties — exhaustive

| `PropKey` | Track type | Applies to | Interpolation |
| --- | --- | --- | --- |
| `position` | `Vec2Track` | any node | lerp, **or cubic when spatial tangents present** |
| `scale` | `Vec2Track` | any node | lerp |
| `rotation` | `ScalarTrack` | any node | raw unbounded radian lerp |
| `skewX` | `ScalarTrack` | any node | lerp |
| `opacity` | `ScalarTrack` | any node | lerp, clamped 0..1 at read |
| `visible` | `BoolTrack` | any node | **always stepped** |
| `path` | `PathTrack` | `PathNode` | per-`AnchorId` pose lerp |
| `fillColor`, `strokeColor` | `ColorTrack` | `PathNode` (`subjectId` = `PaintId`) | per-channel lerp |
| `fillOpacity`, `strokeOpacity`, `strokeWidth` | `ScalarTrack` | `PathNode` (`subjectId` = `PaintId`) | lerp |
| `trimStart`, `trimEnd`, `trimOffset` | `ScalarTrack` | `PathNode` | lerp, clamped 0..1 |

**NOT animatable in v1 — decided, not overlooked:**

| Not animatable | Reason |
| --- | --- |
| `pivot` | Appears twice with opposite sign in `toAffine()`; keying it while `scale != 1` translates the node. |
| `closed`, `AnchorKind`, anchor *existence* | Topology is constant over time by construction. This is what makes morphing well-defined at all. |
| `ShapeRecipe` params | Inert metadata. |
| `children` order / z-order, `name`, `locked` | Structural, not visual state. |
| `artboard` size, `background` | Document-level. |
| Gradient stop offset/color | Type exists; no authoring UI in v1. |
| Per-anchor independent tracks | Whole-path keyframes only. |

### Keyframes

```dart
class Keyframe<T> {
  final double t;        // NORMALIZED 0..1. The ONLY ordering key. No frameNo.
  final T value;
  /// Governs the segment LEAVING this key. Decision: default is LINEAR — the
  /// identity of the operation. A non-identity default breaks bit-identical
  /// legacy import and silently curves every programmatically-created key.
  /// `easeInOut` is the *pen/keyframe UI* default, never the model default.
  final Easing easing;
  const Keyframe({required this.t, required this.value,
    this.easing = const LinearEasing()});
}

/// Vec2 keys additionally carry SPATIAL tangents — curved motion paths.
/// `easing` shapes TIME along the segment; these shape SPACE. Orthogonal.
/// null == straight-line lerp (the unchanged fast path).
final class Vec2Keyframe extends Keyframe<Vec2> {
  final Vec2? inTangent;   // relative to `value`
  final Vec2? outTangent;  // relative to `value`
  const Vec2Keyframe({required super.t, required super.value,
    super.easing = const LinearEasing(), this.inTangent, this.outTangent});
}
```

### Tracks

```dart
/// Non-generic facade. The evaluator and the decoder deal in this type; a raw
/// `Track<Object?>` never escapes a TrackSet (Dart generics are covariant, so
/// an untyped view is an unsound call waiting to happen).
sealed class Track {
  const Track();
  int get keyCount;
  double get firstT;
  double get lastT;
  Object? sampleDynamic(double t);
}

sealed class TypedTrack<T> extends Track {
  final List<Keyframe<T>> keys;
  const TypedTrack._(this.keys);

  T interpolateKeys(Keyframe<T> k0, Keyframe<T> k1, double u);

  @override int get keyCount => keys.length;
  @override double get firstT => keys.first.t;
  @override double get lastT  => keys.last.t;
  @override Object? sampleDynamic(double t) => sampleAt(t);

  /// TOTAL. Never throws, never divides by zero, never returns NaN.
  /// This is the ONE sampler. Every track type shares it.
  T sampleAt(double t) {
    if (keys.length == 1 || t <= keys.first.t) return keys.first.value;  // HOLD FIRST
    if (t >= keys.last.t) return keys.last.value;                        // HOLD LAST
    final i = _lowerBound(keys, t);          // binary search, ONE list
    final k0 = keys[i], k1 = keys[i + 1];
    final span = k1.t - k0.t;
    if (span <= 1e-9) return k1.value;       // zero-span rule; the divide is never reached
    final u = applyEasing(k0.easing, (t - k0.t) / span);   // segment-local remap
    return interpolateKeys(k0, k1, u);
  }
}
```

> **HOLD LAST is the explicit fix for "the shape disappears at 100%".** Legacy wrapped interpolation in `if (frames.length > preFrameNo + 1)`, so past the last keyframe the body never ran and the section rendered as nothing.

```dart
final class ScalarTrack extends TypedTrack<double> {
  ScalarTrack(List<Keyframe<double>> keys) : super._(_validated(keys));
  @override double interpolateKeys(Keyframe<double> a, Keyframe<double> b, double u) =>
      a.value + (b.value - a.value) * u;
}

final class Vec2Track extends TypedTrack<Vec2> {
  Vec2Track(List<Vec2Keyframe> keys) : super._(_validated(keys));
  @override Vec2 interpolateKeys(Keyframe<Vec2> a, Keyframe<Vec2> b, double u) {
    final k0 = a as Vec2Keyframe, k1 = b as Vec2Keyframe;
    if (k0.outTangent == null && k1.inTangent == null) {
      return Vec2.lerp(k0.value, k1.value, u);            // fast path, unchanged
    }
    final p0 = k0.value;
    final p1 = p0 + (k0.outTangent ?? Vec2.zero);
    final p3 = k1.value;
    final p2 = p3 + (k1.inTangent ?? Vec2.zero);
    return _cubicAt(p0, p1, p2, p3, u);
  }
}

final class ColorTrack extends TypedTrack<Rgba> {
  ColorTrack(List<Keyframe<Rgba>> keys) : super._(_validated(keys));
  @override Rgba interpolateKeys(Keyframe<Rgba> a, Keyframe<Rgba> b, double u) =>
      Rgba.lerp(a.value, b.value, u);
}

final class BoolTrack extends TypedTrack<bool> {
  BoolTrack(List<Keyframe<bool>> keys) : super._(_validated(keys));
  @override bool interpolateKeys(Keyframe<bool> a, Keyframe<bool> b, double u) => a.value;
}

final class PathTrack extends TypedTrack<PathPose> {
  PathTrack(List<Keyframe<PathPose>> keys) : super._(_validated(keys));
  /// Pose-map lerp is NOT done here — it needs the node's topology to drive the
  /// loop. See SceneEvaluator.resolvePose (§9). This method is unreachable and
  /// asserts if called.
  @override PathPose interpolateKeys(Keyframe<PathPose> a, Keyframe<PathPose> b, double u) =>
      throw StateError('PathTrack is sampled through resolvePose');
}
```

> Note `interpolateKeys` takes **keyframes, not values**. Spatial tangents live on the keyframe; deciding this signature after the sampler is written is a break through every subclass *and* through the **new core runtime package** (this doc's model + serializer + evaluator, published as its own pub package). The old `annimation` v0.0.2 is **not** that package — it is legacy-format-only, is not a dependency, and cannot read a v3 document; the break is clean, not a version bump.

### `TrackSet` — the only cast site in the codebase

```dart
/// ONE table. Used by the decoder AND the mutation API. Nowhere else casts.
const Map<PropKey, Type> kExpectedTrackType = {
  PropKey.position: Vec2Track,   PropKey.scale: Vec2Track,
  PropKey.rotation: ScalarTrack, PropKey.skewX: ScalarTrack,
  PropKey.opacity: ScalarTrack,  PropKey.visible: BoolTrack,
  PropKey.path: PathTrack,
  PropKey.fillColor: ColorTrack, PropKey.strokeColor: ColorTrack,
  PropKey.fillOpacity: ScalarTrack, PropKey.strokeOpacity: ScalarTrack,
  PropKey.strokeWidth: ScalarTrack,
  PropKey.trimStart: ScalarTrack, PropKey.trimEnd: ScalarTrack,
  PropKey.trimOffset: ScalarTrack,
};

@immutable
final class TrackSet {
  final Map<PropertyKey, Track> byKey;
  /// Unknown property names from a newer client: preserved, never evaluated,
  /// re-emitted verbatim on save.
  final Map<String, Object?> unknownKeys;
  const TrackSet(this.byKey, {this.unknownKeys = const {}});
  static const empty = TrackSet({});

  // TYPED ACCESSORS. Return null on type mismatch — never throw, never blind-cast.
  // A malformed Firestore document must not crash the paint loop.
  ScalarTrack? scalar(PropKey p, [String? s]) => _as<ScalarTrack>(PropertyKey(p, s));
  Vec2Track?   vec2  (PropKey p, [String? s]) => _as<Vec2Track>(PropertyKey(p, s));
  ColorTrack?  color (PropKey p, [String? s]) => _as<ColorTrack>(PropertyKey(p, s));
  BoolTrack?   boolean(PropKey p, [String? s]) => _as<BoolTrack>(PropertyKey(p, s));
  PathTrack?   pathTrack() => _as<PathTrack>(const PropertyKey(PropKey.path));

  X? _as<X extends Track>(PropertyKey k) { final t = byKey[k]; return t is X ? t : null; }
}
```

### Track invariants

| # | Invariant | Enforced by |
| --- | --- | --- |
| T1 | `keys.isNotEmpty` | `_validated` in the public factory |
| T2 | `t` **strictly increasing** | `_validated` + `TrackOps` (ε-nudge `1e-4` or reject) |
| T3 | every `t` ∈ `[0,1]` | `_validated` (clamped on insert) |
| T4 | exactly **one** ordered list; lookup and value-read from the same object | type shape — no parallel derived array exists in v3 |
| T5 | track type matches `kExpectedTrackType[prop]` | decoder + typed accessors |
| T6 | first key is **not** pinned to 0, last is **not** pinned to 1 | deliberate: hold-first/hold-last makes pinning unnecessary, and pinning would corrupt a track that legitimately starts late |

> T2 is the fix for legacy's divide-by-zero NaN: `Squares.json` section 3 has three keyframes at exactly `20.34722169240316`, giving `(p[i+1] - p[i]) == 0` and NaN coordinates.
> T4 is the fix for the sorted-percent-list vs unsorted-frames desync that made `circlebounce.json` read geometry from the wrong keyframe.

---

## 8. Easing

```dart
/// ONE concept covers easing AND stepped interpolation. There is no separate
/// `interpolation` enum — hold IS an easing, and falls out of the same code path.
/// Easing belongs to the key it LEAVES (outgoing). No in/out pairs to keep consistent.
sealed class Easing { const Easing(); }

final class LinearEasing extends Easing { const LinearEasing(); }
final class HoldEasing   extends Easing { const HoldEasing(); }   // u -> 0.0

/// CSS-style cubic-bezier, endpoints pinned at (0,0) and (1,1).
/// x1,x2 clamped 0..1 (time must be monotonic); y UNCLAMPED (overshoot/anticipation).
final class CubicEasing extends Easing {
  final double x1, y1, x2, y2;
  const CubicEasing(this.x1, this.y1, this.x2, this.y2);

  // Named presets are CONSTANTS, persisted as their four numbers. The wire
  // format never has to know the preset vocabulary; a preset tweaked into a
  // custom curve is not a type change.
  static const ease      = CubicEasing(0.25, 0.10, 0.25, 1.00);
  static const easeIn    = CubicEasing(0.42, 0.00, 1.00, 1.00);
  static const easeOut   = CubicEasing(0.00, 0.00, 0.58, 1.00);
  static const easeInOut = CubicEasing(0.42, 0.00, 0.58, 1.00);
  static const backIn    = CubicEasing(0.36, 0.00, 0.66, -0.56);
  static const backOut   = CubicEasing(0.34, 1.56, 0.64, 1.00);
}

/// Pure, total, testable. Newton-Raphson (8 iterations) then bisection fallback.
double applyEasing(Easing e, double u) {
  final c = u.clamp(0.0, 1.0);
  return switch (e) {
    HoldEasing()   => 0.0,
    LinearEasing() => c,
    CubicEasing(:final x1, :final y1, :final x2, :final y2) =>
        _solveCubicBezier(x1, y1, x2, y2, c),
  };
}
```

**Decision: easing is applied inside the segment-local remap**, exactly where legacy left a bare linear `u`. This is the one place easing belongs, and the reason `sampleAt` has a single shared implementation.

---

## 9. Interpolation rules

### Scalar / Vec2 / Color / Bool

Handled entirely by `TypedTrack.sampleAt` (§7). Restated as a decision table:

| Condition | Result |
| --- | --- |
| `keys.length == 1` | that value |
| `t <= keys.first.t` | `keys.first.value` (**HOLD FIRST**) |
| `t >= keys.last.t` | `keys.last.value` (**HOLD LAST**) |
| `span <= 1e-9` | `keys[i+1].value` (zero-span rule; the divide is never reached) |
| otherwise | `interpolateKeys(k0, k1, applyEasing(k0.easing, (t - k0.t) / span))` |
| track absent from the `TrackSet` | the node's **pose** value — never zero, never skipped |

### Path

**The pose map is never iterated. The node's topology drives the loop.** There is no `points.length` from a "from" frame anywhere in v3.

```dart
/// Stage 2 of the pipeline. `topology` is PathNode.path — the authority.
PathData resolvePose(PathData topology, PathTrack? track, double t) {
  if (track == null) return topology;                     // fully static
  final (k0, k1, u) = track.bracket(t);                   // hold-first/hold-last applied
  final poseA = k0.value.anchors, poseB = k1.value.anchors;

  final out = <Anchor>[];
  for (final a in topology.anchors) {                     // TOPOLOGY drives the loop
    final rest = AnchorPose(a.position, a.inTangent, a.outTangent);
    final pa = poseA[a.id] ?? rest;                       // THE one missing-pose rule
    final pb = poseB[a.id] ?? rest;
    final p  = AnchorPose.lerp(pa, pb, u);
    out.add(a.copyWith(position: p.position,
        inTangent: p.inTangent, outTangent: p.outTangent));
  }
  return PathData(anchors: out, closed: topology.closed);  // closed is NEVER interpolated
}
```

| Aspect | Rule |
| --- | --- |
| Matching | **Map lookup by `AnchorId`.** Anchor order, anchor count, and insertion history are all irrelevant to *correctness of interpolation*. |
| Differing anchor sets between keyframes | **Not representable.** Topology is on the node; `PathOps` backfills every keyframe of every path track for that node in one transaction. |
| Missing pose entry | **Exactly one rule:** fall back to the node's rest anchor. No `AnchorMatchRule`, no `collapseToNeighbor`, no synthesized ghosts, no LCS, no arc-length resampling in the evaluator. |
| Anchor **count** changing over time | Impossible. Adding an anchor mid-track is a topology transaction, not a keyframe difference. |
| `closed` | Taken from topology. Cannot vary over time, so there is nothing to pop at `u = 0⁺`. |
| `AnchorKind` | Taken from topology. The renderer never reads it. |

### What is NOT interpolatable — decided

| Not interpolatable | Behaviour |
| --- | --- |
| `visible`, any `bool` | **Stepped.** Holds the FROM key's value for the whole segment. |
| `closed`, `AnchorKind`, anchor existence | Constant over time by construction. |
| `children` order, `name`, `locked`, `recipe` | Not animatable at all. |
| `Easing` itself | A key's easing is a discrete authored value. |

### Continuity — a first-class invariant, not a corollary of totality

```
For every adjacent key pair (k0, k1) of every track:
    render(sample(k0.t + 1e-6))  ≈  render(sample(k0.t))   within epsilon
    render(sample(k1.t - 1e-6))  ≈  render(sample(k1.t))   within epsilon
```

**Test it over all 8 legacy fixtures and every authored fixture.** A shape that collapses to a point on the first frame after `t=0` is total, produces no NaN, throws nothing, and is completely wrong. That is precisely the class of defect that shipped in the legacy app.

---

## 10. Time model

| Aspect | Decision | Reason |
| --- | --- | --- |
| Unit | **Normalized `double` 0..1** of the animation | The one legacy decision that was unambiguously right (`framePosition` 0..100). A document plays at any duration, any resolution; the evaluator needs no `BuildContext`, no screen width, no fps. |
| Ordering key | `t`, and only `t` | Legacy's `frameNo` was a meaningless insertion tag and was used as an array subscript anyway. There is no `frameNo` in v3. |
| `durationSeconds` | Playback hint on `Animation` | Changing it retimes everything proportionally and re-authors nothing. |
| `fps` | Preview/export hint only | **Nothing in the model is quantized to frames.** |
| Playhead | Unitless normalized double in `EditorState` | Legacy stored it as `timeLinePointerXPosition` in **logical pixels** and converted via screen width from `BuildContext`, making the engine resolution-dependent and untestable without a widget tree. Pixels exist only inside the timeline widget's paint and hit-test. |
| Absolute-duration authoring | **Out of scope.** The timeline UI displays seconds and writes `t = seconds / durationSeconds`. | Otherwise the owner hand-computes `2.0 / 2.6 = 0.769` and gets it wrong. |

```dart
enum LoopMode { once, loop, pingPong }

@immutable
final class Animation {
  final AnimationId id;
  final String name;
  final double durationSeconds;
  final int fps;
  final LoopMode loop;
  /// PER-NODE, PER-PROPERTY, SPARSE. A node absent here is fully static.
  /// Nodes may have wildly different key counts at wildly different positions.
  /// There is no shared keyframe grid and no cache keyed by selection —
  /// legacy populated its derived list only for the CURRENTLY SELECTED section,
  /// so every other section rendered FROZEN at keyframe 0 during playback.
  final Map<NodeId, TrackSet> tracks;
  final Map<String, Object?> unknownKeys;
  const Animation({required this.id, required this.name,
    this.durationSeconds = 1.0, this.fps = 60, this.loop = LoopMode.loop,
    this.tracks = const {}, this.unknownKeys = const {}});
}

/// Wall-clock → normalized t. Lives OUTSIDE the evaluator so the evaluator
/// stays a pure sampler.
double normalizedTime(Animation a, double elapsedSeconds) {
  final x = elapsedSeconds / a.durationSeconds;
  return switch (a.loop) {
    LoopMode.once     => x.clamp(0.0, 1.0),
    LoopMode.loop     => x - x.floorToDouble(),
    LoopMode.pingPong => _triangle(x),          // 0→1→0
  };
}
```

**Global scrub → per-track local `t`:** one normalized playhead value feeds every node's independent track in the same tick. Within a track the bracketing pair is found by binary search and remapped to segment-local `u = (t - k0.t) / (k1.t - k0.t)`, then eased. This is legacy's correct multi-track model, minus the `controller.value → pixels → percent → segment-t` round trip.

---

## 11. Document and evaluation

```dart
@immutable
final class Document {
  static const int currentSchemaVersion = 3;

  final int schemaVersion;
  final String id;               // UUID v4
  final String name;
  final Vec2 artboard;           // document units; origin = top-left, y-down
  final Rgba background;
  final GroupNode root;
  /// LIST FROM DAY ONE. v1 creates exactly ONE and the UI hides the concept.
  /// This is the state-machine seam and it costs v1 nothing.
  final List<Animation> animations;
  /// Never `animations.first` — twenty call sites doing that is twenty crashes
  /// on an empty list.
  final AnimationId? defaultAnimationId;
  /// Monotonic save counter. Incremented by exactly 1 on every PERSISTED save,
  /// never by an in-memory edit. NEVER read or interpreted by the evaluator —
  /// it is persisted document METADATA, not animation state and not ephemeral
  /// editor state. v1 writes it and ignores it; v1.1 turns it into optimistic
  /// concurrency (reject a save whose `rev` is not the stored `rev`), which is
  /// what detects the two-tab clobber.
  final int rev;
  final Map<String, Object?> unknownKeys;

  const Document({this.schemaVersion = currentSchemaVersion,
    required this.id, required this.name, required this.artboard,
    this.background = Rgba.transparent, required this.root,
    this.animations = const [], this.defaultAnimationId, this.rev = 0,
    this.unknownKeys = const {}});
}
```

**v1 document invariants:** exactly one `Animation`; `defaultAnimationId` references it; `NodeId` unique within the document; every path-track pose id exists in its node's topology; `rev` is non-negative and never decreases.

**Three-way classification of state — every field belongs to exactly one column:**

| Persisted (in `Document`) | Derived (rebuilt, never stored) | Ephemeral (in `EditorState`, never serialized) |
|---|---|---|
| topology, poses, tracks, paint, `locked`, `rev` | `Map<NodeId, Node>` index, AABBs, sampled `Scene` | playhead, `playing`, selection, hover, viewport transform |

`rev` is the only persisted field the evaluator never reads: it is save metadata, so it sits in `Document` (it must survive reload) but outside every evaluation stage.

### Evaluator entry point

```dart
/// A weighted sample of one animation. v1 ALWAYS passes exactly one entry at
/// weight 1.0. Deciding this signature now is the difference between the state
/// machine being additive and being a signature break through every call site
/// and through the new core runtime package (NOT the legacy `annimation`
/// v0.0.2, which is not a dependency and cannot read a v3 document).
@immutable
final class AnimationMix {
  final AnimationId animation;
  final double t;        // normalized position within that animation
  final double weight;   // 0..1, normalized across the list
  const AnimationMix(this.animation, this.t, {this.weight = 1.0});
}

/// Identity of a node IN THE EVALUATED SCENE. `instancePath` is const [] in v1.
/// Ephemeral, never serialized — so making this change now is a rename, and
/// making it later is a refactor through hit-testing, selection, the layers
/// panel and the transform gizmo.
@immutable
final class ScenePath {
  final List<NodeId> instancePath;
  final NodeId nodeId;
  const ScenePath(this.nodeId, {this.instancePath = const []});
  // value equality + hashCode
}

@immutable
final class ResolvedNode {
  final ScenePath path;
  final Affine world;
  final double worldOpacity;
  final bool worldVisible;
  /// Posed + trimmed geometry, in the node's LOCAL space.
  /// WARNING: after the trim stage the anchor ids here are SYNTHETIC and
  /// NON-AUTHORITATIVE. No downstream stage, exporter, or future skinning pass
  /// may join by them.
  final PathData? geometry;
  final List<Fill> fills;
  final List<Stroke> strokes;
  const ResolvedNode({...});
}

@immutable
final class Scene {
  final List<ResolvedNode> drawOrder;          // flattened, back-to-front
  final Map<ScenePath, ResolvedNode> byPath;   // NOT keyed by NodeId
  const Scene(this.drawOrder, this.byPath);
}

/// THE single entry point. Pure function. No BuildContext, no pixels, no dialogs.
Scene evaluate(Document doc, List<AnimationMix> mix);
```

**`evaluate(doc, const [])` is defined: it returns the static rest pose** (every node's authored `Transform2`, `PathData`, and paint). This is not an edge case to leave undefined — it is how bones later get their inverse-bind matrices for free, and it is how the editor renders a document with no animation.

### The named pipeline

Stages are **named functions**, not an inlined walk. Two are no-ops in v1 and exist so bones land as a fill-in rather than a re-plumb.

| # | Stage | v1 |
| --- | --- | --- |
| 1 | `sampleTracks` | one pass over `Map<NodeId, TrackSet>`; blends the mix list into a per-node property bag |
| 2 | `resolvePose` | pose maps → posed `PathData` in local space (§9) |
| 3 | `composeWorldA` | pre-order traversal; `world = parent.world · local` |
| 4 | `solveConstraints` | **NO-OP.** IK writes solved rotations back into the property bag. |
| 5 | `composeWorldB` | **NO-OP.** Re-composes only the subtrees stage 4 touched. |
| 6 | `deform` | **NO-OP.** Skinning; needs bone world matrices from stage 3/5. |
| 7 | `applyTrim` | arc-length window → split cubics, discard outside |
| 8 | `resolvePaint` | apply animated paint channels |

**Ordering decisions, each with its reason:**

- `deform` comes **after** `composeWorld`, not before — it consumes bone world matrices that `composeWorld` produces. The naive linear ordering `deform → composeWorld` is unbuildable, and discovering that after `evaluate` is written as one non-reentrant pre-order walk is expensive.
- `applyTrim` comes **after** `deform` — trim destroys authored `AnchorId`s that skinning joins on.
- `applyTrim` comes **before** `composeWorldB`'s output is consumed by the renderer, and trim is measured in **node-local space** (AE/Lottie semantics) — measuring after a non-uniform scale would make trim percentage depend on the transform.
- A skinned node whose world matrix is **singular** (`invert()` returns null, e.g. an animator keys scale to 0) renders nothing. Never throws.

### Blend contract for `List<AnimationMix>`

Written now even though v1 always passes one entry at weight 1.0 — it is one paragraph now versus a rewrite later.

| Type | Blend |
| --- | --- |
| Scalar / Vec2 / Color | weighted sum |
| `rotation`, `skewX` | weighted sum of **raw unbounded radians**. No normalization, no shortest arc. |
| `bool` / `visible` | **highest-weight contributor wins**; ties broken by list order. Never lerped. |
| `path` | per-`AnchorId` weighted sum of poses. Works precisely because poses are ID-keyed maps and not positional lists. |
| **A mix entry whose animation lacks a track for property P** | contributes the node's **pose** value at that weight — **never zero, never a skipped/renormalized weight.** This one rule is the difference between a smooth transition and a pop. |

---

## 12. Mutation API — where the invariants actually live

**No model object is mutable. The UI never edits a model object; it issues a command that returns a new `Document`.** Build methods are pure reads — legacy mutated the document from inside `itemBuilder`, so merely rendering the timeline edited the user's file.

```dart
abstract final class TrackOps {
  static const double minSeparation = 1e-4;

  /// Insert or REPLACE at t. Coincident keys are impossible by construction.
  static T upsertKeyframe<T extends Track>(T track, double t, Object value, Easing e);
  static T removeKeyframeAt<T extends Track>(T track, int index);
  /// Addresses by INDEX resolved at command-construction time, never re-derived
  /// from a float. Rejects a move that would collide within `minSeparation`.
  static T moveKeyframe<T extends Track>(T track, int index, double newT);
  static T setEasing<T extends Track>(T track, int index, Easing e);
}

abstract final class PathOps {
  // ---- POSE edits: keyframe-local ----------------------------------------
  static Document moveAnchor(Document d, NodeId n, AnchorId a, Vec2 to, {double? atT});
  static Document setTangents(Document d, NodeId n, AnchorId a,
      {Vec2? inT, Vec2? outT, AnchorKind? kind, double? atT});

  // ---- TOPOLOGY edits: DOCUMENT-WIDE for that node ------------------------
  /// Mints ONE AnchorId, inserts it into the node's PathData at the correct
  /// draw position, AND writes an AnchorPose into EVERY keyframe of EVERY path
  /// track for that node, ACROSS EVERY ANIMATION — each computed by de
  /// Casteljau splitting THAT keyframe's own cubic at `u`. The split is exact,
  /// so every existing keyframe is pixel-identical afterwards.
  /// ONE command, ONE undo entry.
  static (Document, AnchorId) insertAnchor(Document d, NodeId n,
      {required AnchorId after, required double u});

  static Document deleteAnchor(Document d, NodeId n, AnchorId a);

  /// The ONLY other way an anchor set may change. Rewrites the node's topology
  /// AND every keyframe pose onto the new id set by arc-length correspondence.
  /// Recipe regeneration, paste-replace-geometry, and importer repair all route
  /// here. Runs once per edit, never in the tick.
  static Document retopologize(Document d, NodeId n, PathData newTopology);
}

abstract final class NodeOps {
  /// Re-mints EVERY NodeId and EVERY AnchorId in the subtree AND deep-copies
  /// the corresponding TrackSet entries under the new ids, as ONE command.
  /// Without this, copy/paste of a group yields two subtrees sharing NodeIds,
  /// both driven by the same TrackSet, with no way to animate them separately.
  static Document duplicateSubtree(Document d, NodeId n);

  /// World-preserving reparent: newLocal = newParent.world.invert() · oldWorld,
  /// then Affine.decompose back into Transform2. Without decompose, reparenting
  /// either visually teleports the node or silently bakes a wrong transform.
  static Document reparent(Document d, NodeId n, NodeId newParent, int index);

  /// Sets pivot to the union-AABB centre of the children at group time.
  static Document createGroup(Document d, List<NodeId> members);
}
```

**Structural enforcement, not convention:** `PathData`'s const constructor is private and `PathOps` is the only route to a topology change. The pen tool has **no** way to call a node-level path replacement on a tracked node. Assert it:

```dart
test('after N pen edits at any keyframe, every keyframe of every path track '
     'for the node holds the identical AnchorId SEQUENCE', () { ... });
```

**Endpoint pinning is an editor operation, not a model invariant.** Legacy needed first-at-0 / last-at-100 for correctness *and* enforced it from inside `build()` on an unsorted list, stamping the wrong keyframes. `sampleAt`'s hold-first/hold-last is strictly stronger; `TrackOps.pinEndpoints` remains as a UX affordance.

### Ephemeral editor state — never serialized

```dart
/// NOT part of Document. NOT persisted. Legacy persisted the mouse cursor
/// (`hoverPoint`), the current segment selection (`controlPointAdjecntPair`),
/// a never-overridden `boxSize` constant, a recomputable AABB
/// (`cornerBoxPoints`), and the drawing board's SCREEN offset (`position`).
final class EditorState {
  final double playhead;                  // normalized 0..1, unitless
  final bool playing;
  final Set<ScenePath> selectedNodes;
  final Set<AnchorId> selectedAnchors;
  final (NodeId, PropertyKey, int)? selectedKeyframe;  // edit-at-keyframe UX
  final Affine viewportTransform;         // zoom/pan: document → screen
  final AnimationId activeAnimation;
  const EditorState({...});
}
```

---

## 13. Worked examples — the model's acceptance tests

### 13.1 Square (4 anchors) → 5-point star (10 anchors)

**The model's answer: anchor counts differing between keyframes is not a representable state, and reaching the result never requires it.**

```dart
// t=0: square. Four corner anchors, zero tangents.
final square = PathData(closed: true, anchors: [
  Anchor(id: AnchorId('sq-a'), position: Vec2(0,   0)),
  Anchor(id: AnchorId('sq-b'), position: Vec2(100, 0)),
  Anchor(id: AnchorId('sq-c'), position: Vec2(100, 100)),
  Anchor(id: AnchorId('sq-d'), position: Vec2(0,   100)),
]);

// Track with two keys, both posing the same four ids.
PathTrack([
  Keyframe(t: 0.0, value: PathPose({...4 poses}), easing: CubicEasing.easeInOut),
  Keyframe(t: 1.0, value: PathPose({...4 poses}), easing: const LinearEasing()),
]);

// Six pen clicks at t=1.0. Each is ONE command, ONE undo entry.
var (d1, x0) = PathOps.insertAnchor(doc, n1, after: AnchorId('sq-a'), u: 0.5);
var (d2, x1) = PathOps.insertAnchor(d1,  n1, after: AnchorId('sq-b'), u: 0.5);
// ... x2 .. x5
```

After the six inserts:

| Fact | Value |
| --- | --- |
| `PathNode.path.anchors` | 10 ids: `[sq-a, x0, sq-b, x1, sq-c, x2, sq-d, x3, x4, x5]` |
| Key `t=0.0` pose map | those same 10 ids — six of them sitting exactly on the square's edges |
| Rendered `t=0.0` before vs after the insert | **pixel-identical** (each split is exact de Casteljau) |
| Key `t=1.0` pose map | those same 10 ids, dragged into star positions |

Evaluation at `t=0.5` iterates `topology.anchors` and looks each id up in both pose maps. Nothing compared `points.length`, nothing indexed `frames[i].points[j]`, no keyframe was read from a sorted parallel array.

**The other route — the star came from the shape tool, minting 10 fresh ids:**

```dart
doc = PathOps.retopologize(doc, n1, starTopology);
```

`retopologize` rewrites the node's topology **and every keyframe's pose map** onto the new id set by arc-length correspondence. The disjoint-set case never reaches the evaluator. This is why "draw a square, change the recipe to a star" — the most obvious way a user attempts this demo — is legal.

> **Honest limitation:** this is anchor-correspondence morphing, not automatic shape matching. Route 1 costs six pen clicks. What the model buys is that those clicks are legal, cheap, non-destructive to existing keyframes, and undoable.

### 13.2 Bouncing ball — curved motion path + squash & stretch

```dart
PathNode(
  id: NodeId('ball'), name: 'Ball',
  path: circlePath,                                    // centred on local (0,0)
  transform: Transform2(position: Vec2(40, 60),
                        pivot: Vec2(0, 20)),           // BOTTOM of the ball
  fills: [Fill(id: PaintId('p-ball'), paint: SolidPaint(Rgba(0.9, 0.2, 0.2)))],
)
```

Two independent tracks on one node, with independent key positions:

```dart
NodeId('ball'): TrackSet({
  // MOTION — five keys, spatial tangents carry the arc, easing carries the speed.
  const PropertyKey(PropKey.position): Vec2Track([
    Vec2Keyframe(t: 0.00, value: Vec2( 40,  60),
        outTangent: Vec2( 90, -30), easing: CubicEasing.easeIn),
    Vec2Keyframe(t: 0.60, value: Vec2(300, 240),                    // IMPACT
        inTangent: Vec2(-70, -95), outTangent: Vec2(45, -80),
        easing: CubicEasing.easeOut),
    Vec2Keyframe(t: 0.78, value: Vec2(380, 190),                    // apex 1
        inTangent: Vec2(-30, 0), outTangent: Vec2(30, 0),
        easing: CubicEasing.easeIn),
    Vec2Keyframe(t: 0.92, value: Vec2(430, 240),                    // IMPACT 2
        inTangent: Vec2(-25, -35), outTangent: Vec2(18, -22),
        easing: CubicEasing.easeOut),
    Vec2Keyframe(t: 1.00, value: Vec2(455, 240), inTangent: Vec2(-15, -4)),
  ]),

  // SQUASH — its own key positions, aligned to the impact times by hand.
  const PropertyKey(PropKey.scale): Vec2Track([
    Vec2Keyframe(t: 0.00, value: Vec2(1.00, 1.00)),
    Vec2Keyframe(t: 0.55, value: Vec2(0.88, 1.14), easing: CubicEasing.easeIn),
    Vec2Keyframe(t: 0.60, value: Vec2(1.35, 0.62), easing: CubicEasing.easeOut),
    Vec2Keyframe(t: 0.68, value: Vec2(0.94, 1.06), easing: CubicEasing.easeOut),
    Vec2Keyframe(t: 0.76, value: Vec2(1.00, 1.00)),
  ]),
})
```

| Why it works | |
| --- | --- |
| Curved trajectory | Spatial `inTangent`/`outTangent` on the position keys make the segment a cubic. Five keys, not twenty-two baked polyline samples. |
| Ease and shape are orthogonal | `easing` reshapes **time** along the segment; the tangents shape **space**. Retiming the impact is dragging one dot; re-easing does not re-bake the path. |
| x/y easing conflict dissolves | The shape lives in the control points, so the shared segment easing only carries speed. |
| Squash reads correctly | `pivot = (0, 20)` is the contact point, and `toAffine()` bakes it in, so scaling Y pins the bottom. |
| Pivot is static | `pivot` is not animatable in v1 (§7). Animating centre-pivot → bottom-pivot at impact would make the ball jump. |

**Known cut:** no auto-orient-along-path. A diagonal squash needs a hand-keyed `rotation` track. Written non-goal.

### 13.3 Group rotates while children spin independently

```
GroupNode 'wheel'  (pivot = hub)
 ├── PathNode 'sq'    (pivot = its own centre)
 ├── PathNode 'tri'   (pivot = its own centre)
 └── PathNode 'star'  (pivot = its own centre)
```

```dart
tracks: {
  NodeId('wheel'): TrackSet({ const PropertyKey(PropKey.rotation): ScalarTrack([
      Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: 6.2832)]) }),

  NodeId('sq'): TrackSet({ const PropertyKey(PropKey.rotation): ScalarTrack([
      Keyframe(t: 0.0, value: 0.0, easing: CubicEasing.easeInOut),
      Keyframe(t: 0.6, value: -6.2832),
      Keyframe(t: 1.0, value: -12.5664)]) }),          // TWO full reverse turns

  // This track does NOT span [0,1]. Hold-first before 0.2, hold-last after 0.9.
  NodeId('tri'): TrackSet({ const PropertyKey(PropKey.rotation): ScalarTrack([
      Keyframe(t: 0.2, value: 0.0), Keyframe(t: 0.9, value: 25.1327)]) }),

  NodeId('star'): TrackSet({
      const PropertyKey(PropKey.rotation): ScalarTrack([
          Keyframe(t: 0.0, value: 0.0), Keyframe(t: 1.0, value: -3.1416)]),
      const PropertyKey(PropKey.fillColor, 'p-star'): ColorTrack([
          Keyframe(t: 0.0, value: red), Keyframe(t: 0.5, value: blue),
          Keyframe(t: 1.0, value: red)]) }),
}
```

Trace at `t = 0.25`, one pass:

| Node | Segment | `u` | Eased | Result |
| --- | --- | --- | --- | --- |
| `wheel` | `[0, 1]` | 0.25 | linear | `+1.5708` rad |
| `sq` | `[0, 0.6]` | 0.4167 | easeInOut ≈ 0.387 | `≈ -2.432` rad |
| `tri` | `[0.2, 0.9]` | 0.0714 | linear | `+1.795` rad |
| `star` | `[0, 1]` / `[0, 0.5]` | 0.25 / 0.5 | linear | `-0.7854` rad / half red→blue |

```
world(wheel) = identity · local(wheel)      // rotate about the hub
world(sq)    = world(wheel) · local(sq)     // its own spin about its own pivot
```

Because each pivot is baked inside its own `toAffine()` and composition is strictly `parent.world · local`, `sq` **orbits** the hub while **spinning** about its own centre. The two rotations multiply; neither track knows the other exists.

Four independent key counts (2 / 3 / 2 / 2+3), four different key-position sets, one track not spanning `[0,1]`, one unrelated colour track — **no shared keyframe grid anywhere.** That is legacy's one correct property, preserved.

> `-12.5664` and `+25.1327` survive **only** because rotation is unbounded raw radians. A shortest-arc "fix" collapses both to nearly nothing. Invariant + test.

### 13.4 Stroke draws itself on, then fades out

```dart
PathNode(
  id: NodeId('sig'), name: 'Signature',
  path: PathData(closed: false, anchors: [
    Anchor(id: AnchorId('a0'), position: Vec2(20, 200),  outTangent: Vec2(60, -120)),
    Anchor(id: AnchorId('a1'), position: Vec2(200, 90),
        inTangent: Vec2(-60, 40), outTangent: Vec2(60, -40), kind: AnchorKind.smooth),
    Anchor(id: AnchorId('a2'), position: Vec2(420, 60),  inTangent: Vec2(-80, 30)),
  ]),
  strokes: [Stroke(id: PaintId('p-ink'), paint: SolidPaint(Rgba(0, 0, 0)),
      width: 6, cap: StrokeCap.round)],
  trim: PathTrim.full,
)
```

```dart
// Animation.durationSeconds = 2.6  →  "2 seconds" is t = 2.0 / 2.6 = 0.769.
NodeId('sig'): TrackSet({
  const PropertyKey(PropKey.trimEnd): ScalarTrack([
    Keyframe(t: 0.0,   value: 0.0, easing: CubicEasing.easeInOut),
    Keyframe(t: 0.769, value: 1.0),
  ]),
  const PropertyKey(PropKey.opacity): ScalarTrack([
    Keyframe(t: 0.769, value: 1.0),      // hold-first covers everything before
    Keyframe(t: 1.0,   value: 0.0),
  ]),
})
```

| Why this and not the alternatives | |
| --- | --- |
| Why not animate `path` so the shape "grows"? | Lerping all anchors by one `u` puts the tip at `(50, 50)` at 50% on an L-shaped path — a point **not on the authored path at all**. It fans out of the origin instead of drawing along its route. |
| Why not bake one keyframe per anchor arrival? | The tip lerps along each cubic's **chord**, not the cubic; speed is per-anchor not per-arc-length; one global ease across N segments is unrepresentable; and `insertAnchor` silently breaks the baked timing. |
| Why not `dash` / `dashOffset`? | Needs the authored total arc length, breaks on closed and multi-subpath geometry, and stores a derived quantity as authored data. |
| Cost of doing it properly | Arc-length table (~40 lines, memoized per `PathData`) + de Casteljau splitter that `insertAnchor` already needs. ~150 lines and two golden tests. Two days for the single most-used effect in this product category. |

The `0.769` magic number is exactly why the timeline UI **must** display seconds and author `t = seconds / durationSeconds`.

### 13.5 Insert an anchor at keyframe 1 of a 3-keyframe path animation

Setup: `PathNode n1`, closed square, anchors `[a1, a2, a3, a4]`, one `PathTrack` with keys at `t = 0.0 / 0.5 / 1.0`. User sits at `t = 0.5` and pen-clicks the `a2→a3` edge at `u = 0.5`.

```dart
final (doc2, a5) = PathOps.insertAnchor(doc, NodeId('n1'),
    after: AnchorId('a2'), u: 0.5);
```

**What happens to keyframes 2 and 3: nothing visible.**

| Step | Effect |
| --- | --- |
| 1 | Mint one `AnchorId` `a5`. |
| 2 | Insert it into `n1.path.anchors` between `a2` and `a3` — the topology now has 5 anchors, in **all** animations, for **all** time. |
| 3 | For **each** of the three keyframes, de Casteljau split *that keyframe's own* `a2→a3` cubic at `u = 0.5`, and write `a5`'s pose plus the two rewritten neighbour tangents. |
| 4 | One command, one undo entry. |

For the flat `t=0.0` segment `P0=(100,0) → P3=(100,100)`:

```
Q0=(100,0)  Q1=(100,50)  Q2=(100,100)      R0=(100,25)  R1=(100,75)      S=(100,50)
a5 = { position: (100,50), inTangent: (0,-25), outTangent: (0,25) }
a2.outTangent := Q0 - P0 = (0,0)     a3.inTangent := Q2 - P3 = (0,0)
```

Every keyframe is **pixel-identical** afterwards — the split is exact. Keyframes 2 and 3 gain a pass-through anchor the user can now drag independently, at any keyframe, forever.

> **Write this down or the pen tool breaks the demo:** the inserted anchor is `AnchorKind.smooth` with **non-zero** collinear handles (`(0,-25)` / `(0,25)` above), not a zero-handle corner. Pen-tool code that zeroes the new anchor's handles visibly deforms the shape at every keyframe on insert.
>
> **Documented approximation:** `u` is the parameter on the *authoring* keyframe's cubic and is reused verbatim on the others. The split lands at the same *parametric*, not the same *arc-length*, position on differently-curved keyframes. This is deliberate and cheap; nobody should "fix" it into an arc-length solve.

Acceptance test:

```dart
test('insert at any keyframe leaves every keyframe pixel-identical', () {
  final before = {for (final k in tr.keys) k.t: rasterize(node, k.value)};
  final (d2, _) = PathOps.insertAnchor(doc, n1, after: AnchorId('a2'), u: 0.5);
  final tr2 = d2.pathTrackFor(n1)!;

  // ONE distinct id SEQUENCE across all keyframes and the topology.
  final seqs = tr2.keys.map((k) => orderedIds(d2, n1, k.value)).toSet();
  expect(seqs.length, 1);
  expect(seqs.single, d2.node(n1).path.anchors.map((a) => a.id).toList());

  for (final k in tr2.keys) {
    expect(rasterize(d2.node(n1), k.value), matchesGolden(before[k.t]));
  }
});
```

---

## 14. Deferred seams

All three are **additive against schemaVersion 3**: new sealed variants are a *source* break (exhaustive switches) and never a *data* break, because `type` is an open string and unknown keys are preserved.

| Seam | Where it attaches | Pre-paid in v1 |
| --- | --- | --- |
| **Bones / IK** | `final class BoneNode extends Node { double length; List<Node> children; }` — a bone is just a node; it animates through the existing `rotation`/`position` tracks with **no new track type**.<br>`PathNode.skin` → `Map<AnchorId, List<BoneWeight>>?`, null in v1.<br>`BoneNode.ik` → `IkConstraint?`. | Stage 4 `solveConstraints` and stage 6 `deform` are declared no-ops in **dependency order** (§11). `SkinBinding` keys off `AnchorId` — the stable-ID decision is the single hardest skinning prerequisite and it is already done. Inverse-bind matrices are free because `evaluate(doc, [])` is defined as the rest pose. |
| **State machine** | `Document.stateMachines: List<StateMachine>`, default `const []`. States reference `AnimationId`s; transitions reuse `Easing` verbatim as the blend curve and `LoopMode` as-is. An ephemeral `SmRuntime` reduces wall-clock + inputs to the `List<AnimationMix>` the evaluator **already accepts**. | `animations` is a `List` with `defaultAnimationId` from day one. `evaluate(Document, List<AnimationMix>)` blends **sampled values pre-compose** — blending two fully-composed `Scene`s is wrong for rotation and for path poses. The blend contract (§11) is written. Tracks hang off `Animation`, not `Node`; had they hung off `Node` this seam would be a full rewrite. |
| **Components / instancing** | `Document.components: Map<ComponentId, ComponentDef>`, default `const {}`. `final class InstanceNode extends Node { ComponentId componentId; List<AnimationMix> localMix; Map<OverrideKey, Object?> overrides; }` where `OverrideKey = (List<NodeId> innerPath, PropertyKey property)` — **structured, never a parsed `"inner/child.fillColor"` string**, because ids are opaque. | `ScenePath` already identifies scene nodes (`instancePath` const `[]` in v1) so six expansions of one master do not collide — `Scene.byPath`, not `Scene.byId`. `PropertyKey.subjectId` is already the right granularity for paint overrides. `AnimationMix` already exists as a type for `localMix`. Ids are unique **within a Document or ComponentDef**, never globally — stated now so nesting introduces no collision-rule change. |

**Additional rules to write down now so they are not discovered later:**

- A `ComponentDef` may not transitively contain an instance of itself. Acyclicity check at decode.
- Per-instance override of *geometry* is coarse in v1's shape: `PropKey.path` carries a whole pose map. Per-anchor overrides need `PropKey.anchorPosition` with `subjectId = AnchorId` — additive, and covered by the unknown-property-name preservation rule.
- A `schemaVersion` greater than `currentSchemaVersion` opens the document **read-only**. Key preservation protects *syntax*, not *semantics*: a v3 client cannot know that a v4 `skin` field must stay consistent with the anchors it just let the user delete.

**Forbidden in v1 — these would each cost a migration:**

| Forbidden | What it would break |
| --- | --- |
| Storing path keyframes as positional lists | morphing, skinning, and instance overrides, all at once |
| Indexing fills/strokes/stops by position in the property key | override addressing |
| `evaluate()` taking a single `double t` | forces a signature break through the whole render path for the state machine |
| Collapsing the no-op stages out of the pipeline | forces bones to be retrofitted through the transform stage |
| Keying any ephemeral structure by `NodeId` instead of `ScenePath` | instancing collides silently |
| Switching on a global ambient render-mode flag instead of node type | instancing |

---

## Cross-links

- [00_vision_and_scope.md](00_vision_and_scope.md) — v1 scope, the written non-goals, success criteria.
- **01_domain_model.md** — this document. Authoritative.
- [02_file_format.md](02_file_format.md) — the wire contract, forward-compat rules, legacy importer.
