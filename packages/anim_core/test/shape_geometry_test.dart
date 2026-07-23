import 'dart:math' as math;

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// Recipe → geometry (docs/v3/01 §5, AC-4.1.4).
///
/// The adversarial half of these tests is the point: a shape tool drags through
/// zero size, past a clamped corner radius and through `sides = 0` on its way to
/// a real shape, once per pointer move, and `anim_core` has no `try` to land in
/// (docs/v3/08 §1).
void main() {
  group('EllipseRecipe → four real cubics at κ = 0.5523', () {
    test('exactly four anchors, closed, tangents ±κ·r along the axis', () {
      final p = const EllipseRecipe(rx: 30, ry: 20).toPath();

      expect(p.anchors, hasLength(4),
          reason: 'legacy polygonised circles into 114 straight segments');
      expect(p.closed, isTrue);
      expect(p.segmentCount, 4);
      expect(kKappa, 0.5523);

      const kx = 30 * kKappa; // 16.569
      const ky = 20 * kKappa; // 11.046
      expect(p.anchors[0].position, const Vec2(30, 0));
      expect(p.anchors[0].outTangent, const Vec2(0, ky));
      expect(p.anchors[0].inTangent, const Vec2(0, -ky));
      expect(p.anchors[1].position, const Vec2(0, 20));
      expect(p.anchors[1].inTangent, const Vec2(kx, 0));
      expect(p.anchors[1].outTangent, const Vec2(-kx, 0));
      expect(p.anchors[2].position, const Vec2(-30, 0));
      expect(p.anchors[3].position, const Vec2(0, -20));
    });

    test('every anchor is symmetric, and its stored tangents actually are', () {
      final p = const EllipseRecipe(rx: 30, ry: 20).toPath();
      for (final a in p.anchors) {
        expect(a.kind, AnchorKind.symmetric);
        // The hint is only worth storing if the geometry under it agrees.
        expect(a.inTangent.x, closeTo(-a.outTangent.x, 1e-12));
        expect(a.inTangent.y, closeTo(-a.outTangent.y, 1e-12));
      }
    });

    test('sampled points lie on the true ellipse to better than 1e-3·r', () {
      const rx = 30.0;
      const ry = 20.0;
      final p = const EllipseRecipe(rx: rx, ry: ry).toPath();

      var worst = 0.0;
      for (var k = 0; k < p.segmentCount; k++) {
        final (p0, p1, p2, p3) = p.segment(k);
        for (final u in const [0.1, 0.2, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9]) {
          final q = _cubic(p0, p1, p2, p3, u);
          // Implicit ellipse: (x/rx)² + (y/ry)² == 1 exactly on the curve.
          final r =
              math.sqrt((q.x / rx) * (q.x / rx) + (q.y / ry) * (q.y / ry));
          worst = math.max(worst, (r - 1.0).abs());
        }
      }
      expect(worst, lessThan(1e-3),
          reason: 'κ = 0.5523 is exact enough to be indistinguishable');
    });

    test('NO segment is a straight line — the polygonisation defect', () {
      const rx = 30.0;
      const ry = 20.0;
      final p = const EllipseRecipe(rx: rx, ry: ry).toPath();

      for (var k = 0; k < p.segmentCount; k++) {
        final (p0, p1, p2, p3) = p.segment(k);
        expect(p1, isNot(p0), reason: 'a zero out-handle is a straight cubic');
        expect(p2, isNot(p3), reason: 'a zero in-handle is a straight cubic');
        // A quarter arc bulges from its chord by r·(1 − cos 45°) ≈ 0.29·r. A
        // polygonised "curve" would measure zero here.
        final bulge = _distanceFromChord(p0, p3, _cubic(p0, p1, p2, p3, 0.5));
        expect(bulge, greaterThan(0.2 * math.min(rx, ry)));
      }
    });

    test('a zero, negative, NaN or infinite radius yields empty, never throws',
        () {
      for (final r in const <EllipseRecipe>[
        EllipseRecipe(rx: 0, ry: 20),
        EllipseRecipe(rx: 30, ry: 0),
        EllipseRecipe(rx: -30, ry: 20),
        EllipseRecipe(rx: double.nan, ry: 20),
        EllipseRecipe(rx: double.infinity, ry: 20),
      ]) {
        final p = r.toPath();
        expect(p.anchors, isEmpty);
        expect(p.isEmpty, isTrue, reason: 'P2: renders nothing, never throws');
      }
    });
  });

  group('RectRecipe → 4 anchors, or 8 with real corner cubics', () {
    test('cornerRadius 0 gives four zero-handle anchors', () {
      final p = const RectRecipe(w: 100, h: 40).toPath();

      expect(p.anchors, hasLength(4));
      expect(p.closed, isTrue);
      expect(p.anchors.map((a) => a.position).toList(), const <Vec2>[
        Vec2(-50, -20),
        Vec2(50, -20),
        Vec2(50, 20),
        Vec2(-50, 20),
      ]);
      for (final a in p.anchors) {
        expect(a.inTangent, Vec2.zero);
        expect(a.outTangent, Vec2.zero);
        expect(a.kind, AnchorKind.corner);
      }
    });

    test(
        'a positive cornerRadius gives 8 anchors: 4 cubic corners, 4 straight '
        'edges', () {
      const r = 8.0;
      final p = const RectRecipe(w: 100, h: 40, cornerRadius: r).toPath();
      expect(p.anchors, hasLength(8));
      expect(p.segmentCount, 8);

      const k = r * kKappa;
      // Segment 0 is the top edge: straight, by zero handles, not by a branch.
      final (e0, e1, e2, e3) = p.segment(0);
      expect(e1, e0);
      expect(e2, e3);
      expect(e0, const Vec2(-42, -20));
      expect(e3, const Vec2(42, -20));

      // Segment 1 is the top-right corner: a real cubic whose handles point
      // into the corner at ±κ·radius.
      final (c0, c1, c2, c3) = p.segment(1);
      expect(c0, const Vec2(42, -20));
      expect(c1, const Vec2(42 + k, -20));
      expect(c2, const Vec2(50, -20 + r - k));
      expect(c3, const Vec2(50, -12));
      expect(_distanceFromChord(c0, c3, _cubic(c0, c1, c2, c3, 0.5)),
          greaterThan(0.2 * r),
          reason: 'a corner approximated by line segments is the same defect '
              'as the polygonised circle, just less obvious');

      // Alternating: every second segment is an edge, every other a corner.
      for (var s = 0; s < 8; s += 2) {
        final (a, b, c, dd) = p.segment(s);
        expect(b, a);
        expect(c, dd);
      }
    });

    test('a radius larger than half the short side clamps rather than inverts',
        () {
      final p = const RectRecipe(w: 100, h: 40, cornerRadius: 999).toPath();
      expect(p.anchors, hasLength(8));

      // Clamped to min(w,h)/2 = 20: a stadium. Nothing leaves the bounds and
      // no edge runs backwards (the bow-tie an unclamped offset would make).
      for (final a in p.anchors) {
        expect(a.position.x.abs(), lessThanOrEqualTo(50.0 + 1e-12));
        expect(a.position.y.abs(), lessThanOrEqualTo(20.0 + 1e-12));
      }
      expect(
          p.anchors[0].position.x, lessThanOrEqualTo(p.anchors[1].position.x),
          reason: 'the top edge still runs left to right');
      expect(p.anchors[2].position, const Vec2(50, 0));
      expect(p.anchors[3].position, const Vec2(50, 0),
          reason: 'the right edge collapses to a point — degenerate, not '
              'inverted');
      // And the corner handles clamp with it.
      expect(p.anchors[2].inTangent, const Vec2(0, -20 * kKappa));
    });

    test('a negative or NaN corner radius is treated as square, not inverted',
        () {
      for (final r in const [-4.0, double.nan, double.infinity]) {
        final p = RectRecipe(w: 100, h: 40, cornerRadius: r).toPath();
        expect(p.anchors, hasLength(4));
        expect(p.anchors.every((a) => a.outTangent == Vec2.zero), isTrue);
      }
    });

    test('a zero or negative side yields empty, never throws', () {
      for (final r in const <RectRecipe>[
        RectRecipe(w: 0, h: 40),
        RectRecipe(w: 100, h: 0),
        RectRecipe(w: -100, h: 40),
        RectRecipe(w: double.nan, h: 40),
      ]) {
        expect(r.toPath().anchors, isEmpty);
      }
    });
  });

  group('PolygonRecipe → corner anchors with zero tangents', () {
    test('a triangle has three vertices, the first pointing up', () {
      final p = const PolygonRecipe(sides: 3, radius: 10).toPath();
      expect(p.anchors, hasLength(3));
      expect(p.closed, isTrue);

      expect(p.anchors[0].position.x, closeTo(0, 1e-12));
      expect(p.anchors[0].position.y, closeTo(-10, 1e-12));
      expect(p.anchors[1].position.x, closeTo(10 * math.sqrt(3) / 2, 1e-12));
      expect(p.anchors[1].position.y, closeTo(5, 1e-12));
      expect(p.anchors[2].position.x, closeTo(-10 * math.sqrt(3) / 2, 1e-12));
      expect(p.anchors[2].position.y, closeTo(5, 1e-12));

      for (final a in p.anchors) {
        expect(a.inTangent, Vec2.zero);
        expect(a.outTangent, Vec2.zero);
        expect(a.kind, AnchorKind.corner);
        // A straight side is the degenerate cubic; there is no polyline branch
        // (AC-4.1.2).
        expect(a.position.length, closeTo(10, 1e-12));
      }
    });

    test('a 5-point star alternates outer and inner radius over 10 anchors',
        () {
      final p =
          const PolygonRecipe(sides: 5, radius: 50, star: true, innerRatio: 0.4)
              .toPath();
      expect(p.anchors, hasLength(10));
      for (var k = 0; k < 10; k++) {
        expect(p.anchors[k].position.length, closeTo(k.isEven ? 50 : 20, 1e-9));
      }
    });

    test('innerRatio 0 and 1 are legal geometry, not throws', () {
      final spike =
          const PolygonRecipe(sides: 5, radius: 50, star: true, innerRatio: 0)
              .toPath();
      expect(spike.anchors, hasLength(10));
      for (var k = 1; k < 10; k += 2) {
        expect(spike.anchors[k].position.length, closeTo(0, 1e-9));
      }

      final flat =
          const PolygonRecipe(sides: 5, radius: 50, star: true, innerRatio: 1)
              .toPath();
      expect(flat.anchors, hasLength(10));
      for (final a in flat.anchors) {
        expect(a.position.length, closeTo(50, 1e-9),
            reason: 'innerRatio 1 is a regular 10-gon');
      }

      // Out of range clamps instead of inverting the star.
      final over =
          const PolygonRecipe(sides: 5, radius: 50, star: true, innerRatio: 4)
              .toPath();
      expect(over.anchors.every((a) => a.position.length < 50 + 1e-9), isTrue);
    });

    test('sides < 3 or radius <= 0 yields empty, never throws', () {
      for (final r in const <PolygonRecipe>[
        PolygonRecipe(sides: 2, radius: 50),
        PolygonRecipe(sides: 0, radius: 50),
        PolygonRecipe(sides: -7, radius: 50),
        PolygonRecipe(sides: 5, radius: 0),
        PolygonRecipe(sides: 5, radius: -50),
        PolygonRecipe(sides: 5, radius: double.nan),
      ]) {
        expect(r.toPath().anchors, isEmpty);
      }
    });

    test('an absurd side count clamps instead of allocating', () {
      final p = const PolygonRecipe(sides: 100000000, radius: 50).toPath();
      expect(p.anchors, hasLength(kMaxPolygonSides));
    });
  });

  group('anchor ids', () {
    test('every generated id is unique and uuid-shaped', () {
      final all = <String>[];
      for (final r in <ShapeRecipe>[
        const RectRecipe(w: 100, h: 40),
        const RectRecipe(w: 100, h: 40, cornerRadius: 8),
        const EllipseRecipe(rx: 30, ry: 20),
        const PolygonRecipe(sides: 7, radius: 50),
        const PolygonRecipe(sides: 5, radius: 50, star: true),
      ]) {
        all.addAll(r.toPath().anchors.map((a) => a.id.v));
      }

      expect(all, hasLength(4 + 8 + 4 + 7 + 10));
      expect(all.toSet(), hasLength(all.length));
      final uuid =
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
              r'[0-9a-f]{12}$');
      for (final id in all) {
        expect(uuid.hasMatch(id), isTrue, reason: '$id is not a uuid v4');
      }
    });

    test('regenerating twice yields DIFFERENT ids but identical geometry', () {
      const recipe = EllipseRecipe(rx: 30, ry: 20);
      final a = recipe.toPath();
      final b = recipe.toPath();

      final idsA = a.anchors.map((x) => x.id.v).toSet();
      final idsB = b.anchors.map((x) => x.id.v).toSet();
      expect(idsA.intersection(idsB), isEmpty,
          reason: 'ids are freshly minted, never derived from the parameters '
              'or the loop index');

      expect(a.closed, b.closed);
      expect(a.anchors.length, b.anchors.length);
      for (var k = 0; k < a.anchors.length; k++) {
        expect(a.anchors[k].position, b.anchors[k].position);
        expect(a.anchors[k].inTangent, b.anchors[k].inTangent);
        expect(a.anchors[k].outTangent, b.anchors[k].outTangent);
        expect(a.anchors[k].kind, b.anchors[k].kind);
      }
    });
  });

  test('an UnknownRecipe generates nothing — it is preserve-and-ignore', () {
    final r = ShapeRecipe.fromJson(const {'type': 'spiral', 'turns': 3});
    expect(r, isA<UnknownRecipe>());
    expect(r.toPath().anchors, isEmpty);
  });
}

Vec2 _cubic(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final v = 1 - u;
  final a = v * v * v;
  final b = 3 * v * v * u;
  final c = 3 * v * u * u;
  final e = u * u * u;
  return Vec2(
    a * p0.x + b * p1.x + c * p2.x + e * p3.x,
    a * p0.y + b * p1.y + c * p2.y + e * p3.y,
  );
}

/// Perpendicular distance from [q] to the chord `a → b` — zero for any point on
/// a straight segment, which is exactly what a polygonised curve would measure.
double _distanceFromChord(Vec2 a, Vec2 b, Vec2 q) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return (q - a).length;
  return ((q.x - a.x) * dy - (q.y - a.y) * dx).abs() / len;
}
