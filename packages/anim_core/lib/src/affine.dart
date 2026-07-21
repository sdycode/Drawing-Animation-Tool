/// The one transform type, and the pose that produces it (docs/v3/01 §2, §4).
library;

import 'dart:math' as math;

import 'json.dart';
import 'primitives.dart';

/// Matrix layout `[a c tx ; b d ty ; 0 0 1]`.
///
/// **Every** coordinate mapping routes through this type: parent→child,
/// document→screen, zoom/pan, hit-test, export. There is no hand-rolled
/// per-axis scaling anywhere in v3 — legacy scaled the Y component by the
/// *width* ratio, which drifts on any non-square artboard and is why the golden
/// test uses a deliberately lopsided 450.2 × 250.4 board.
final class Affine {
  const Affine(this.a, this.b, this.c, this.d, this.tx, this.ty);

  final double a, b, c, d, tx, ty;

  static const identity = Affine(1, 0, 0, 1, 0, 0);

  const Affine.translate(double x, double y) : this(1, 0, 0, 1, x, y);
  const Affine.scale(double sx, double sy) : this(sx, 0, 0, sy, 0, 0);

  factory Affine.rotate(double r) {
    final cs = math.cos(r), sn = math.sin(r);
    return Affine(cs, sn, -sn, cs, 0, 0);
  }

  factory Affine.skewX(double k) => Affine(1, 0, math.tan(k), 1, 0, 0);

  /// `this ∘ o` — apply [o] first, then `this`.
  Affine mul(Affine o) => Affine(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.tx + c * o.ty + tx,
        b * o.tx + d * o.ty + ty,
      );

  /// Points — anchor positions. Translation applies.
  Vec2 apply(Vec2 p) => Vec2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty);

  /// Directions — bezier tangents are directions, **not** points, so
  /// translation must not apply. Using [apply] here is the classic way to make
  /// handles drift under a translated parent.
  Vec2 applyVector(Vec2 v) => Vec2(a * v.x + c * v.y, b * v.x + d * v.y);

  double get determinant => a * d - b * c;

  /// Null when singular — an animator *will* key scale to 0.
  ///
  /// Callers handle null by rendering nothing, never by throwing: the evaluator
  /// is total (docs/v3/01 §1 rule 3).
  Affine? invert() {
    final det = determinant;
    if (det.abs() < 1e-12) return null;
    final id = 1.0 / det;
    return Affine(d * id, -b * id, -c * id, a * id, (c * ty - d * tx) * id,
        (b * tx - a * ty) * id);
  }

  /// QR decomposition back into authorable components about [pivot].
  ///
  /// Needed by world-preserving reparent (docs/v3/01 §12): dropping a node into
  /// a new parent must not move it on screen, which means solving for the pose
  /// that reproduces its old world matrix under the new parent. Surjective for
  /// `det != 0` even with `skewY` omitted, because a Y-skew is expressible as
  /// rotation + X-skew + non-uniform scale.
  ///
  /// Null exactly when [invert] is null — a collapsed matrix has no pose.
  Transform2? decompose({Vec2 pivot = Vec2.zero}) {
    final det = determinant;
    if (det.abs() < 1e-12) return null;

    // Column one is R·S applied to x̂, untouched by the skew term, so rotation
    // and scale.x fall straight out of it.
    final sx = math.sqrt(a * a + b * b);
    if (sx < 1e-12) return null;
    final rotation = math.atan2(b, a);
    final sy = det / sx;

    final cs = a / sx, sn = b / sx;
    // Column two is sy·(R·[tan k, 1]); projecting it back onto the rotation
    // frame leaves tan(skewX) alone.
    final skewX = math.atan((c * cs + d * sn) / sy);

    // local = T(pos)·T(pivot)·M·T(-pivot) puts `pos + pivot - M·pivot` in the
    // translation slot, so the pose position is the residual after adding the
    // pivot's displacement back.
    final linear = Affine(a, b, c, d, 0, 0);
    final moved = linear.applyVector(pivot);
    final position = Vec2(tx - pivot.x + moved.x, ty - pivot.y + moved.y);

    return Transform2(
      position: position,
      scale: Vec2(sx, sy),
      pivot: pivot,
      rotation: rotation,
      skewX: skewX,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Affine &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.tx == tx &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  @override
  String toString() => 'Affine($a, $b, $c, $d, $tx, $ty)';
}

/// A node's authored pose. Tracks override this per-property at sample time.
final class Transform2 {
  const Transform2({
    this.position = Vec2.zero,
    this.scale = Vec2.one,
    this.pivot = Vec2.zero,
    this.rotation = 0.0,
    this.skewX = 0.0,
  });

  /// Artboard-relative document units.
  final Vec2 position;

  /// `(1,1)` is identity.
  final Vec2 scale;

  /// A point in the node's **own untransformed local space**.
  ///
  /// Authored once at creation (the geometry's AABB centre, set by the create
  /// command) and never keyframed in v1: it appears twice in [toAffine] with
  /// opposite sign, so animating it while `scale != 1` *translates* the node —
  /// a centre-to-bottom pivot tween at a bounce impact makes the ball jump.
  final Vec2 pivot;

  /// **Radians, unbounded, lerped raw.** No wrapping, no shortest-arc
  /// normalisation, ever: `-12.5664` means two full reverse turns and must play
  /// as two turns. Shortest-arc is the "helpful" fix that silently collapses
  /// every multi-turn spin, so it is a written invariant with a test.
  final double rotation;

  final double skewX;

  static const identity = Transform2();

  /// `local = T(position)·T(pivot)·R(rotation)·SkewX(skewX)·S(scale)·T(-pivot)`
  ///
  /// Composed from named [Affine] factories, deliberately **not** hand-inlined
  /// trig: the legacy equivalent of this exact function produced the y-rescale
  /// bug. A faster inlined form may be substituted only behind the golden test.
  Affine toAffine() => Affine.translate(position.x, position.y)
      .mul(Affine.translate(pivot.x, pivot.y))
      .mul(Affine.rotate(rotation))
      .mul(Affine.skewX(skewX))
      .mul(Affine.scale(scale.x, scale.y))
      .mul(Affine.translate(-pivot.x, -pivot.y));

  Transform2 copyWith({
    Vec2? position,
    Vec2? scale,
    Vec2? pivot,
    double? rotation,
    double? skewX,
  }) =>
      Transform2(
        position: position ?? this.position,
        scale: scale ?? this.scale,
        pivot: pivot ?? this.pivot,
        rotation: rotation ?? this.rotation,
        skewX: skewX ?? this.skewX,
      );

  static const _known = {'position', 'scale', 'pivot', 'rotation', 'skewX'};

  factory Transform2.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return Transform2(
      position: opt(m, 'position', Vec2.fromJson, Vec2.zero),
      scale: opt(m, 'scale', Vec2.fromJson, Vec2.one),
      pivot: opt(m, 'pivot', Vec2.fromJson, Vec2.zero),
      rotation: opt(m, 'rotation', d, 0.0),
      skewX: opt(m, 'skewX', d, 0.0),
    );
  }

  /// Every field always, even at identity: `Transform2` is small and a partial
  /// object makes hand-inspecting a stored document ambiguous.
  Map<String, Object?> toJson() => <String, Object?>{
        'position': position.toJson(),
        'scale': scale.toJson(),
        'pivot': pivot.toJson(),
        'rotation': rotation,
        'skewX': skewX,
      };

  /// Exposed so [Transform2.fromJson] and the node decoder agree on which keys
  /// are claimed here rather than each maintaining its own copy.
  static Set<String> get knownKeys => _known;

  @override
  bool operator ==(Object other) =>
      other is Transform2 &&
      other.position == position &&
      other.scale == scale &&
      other.pivot == pivot &&
      other.rotation == rotation &&
      other.skewX == skewX;

  @override
  int get hashCode => Object.hash(position, scale, pivot, rotation, skewX);

  @override
  String toString() => 'Transform2(pos: $position, scale: $scale, '
      'pivot: $pivot, rot: $rotation, skewX: $skewX)';
}
