import 'dart:math' as math;

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The artboard from docs/v3/01 §4 — deliberately lopsided.
///
/// Legacy scaled the Y component by the *width* ratio, a bug that is invisible
/// on a square board and drifts on every other one. Every assertion below uses
/// these proportions so that class of mistake cannot pass.
const artboard = Vec2(450.2, 250.4);

void expectVec(Vec2 actual, Vec2 expected, {double eps = 1e-9}) {
  expect(actual.x, closeTo(expected.x, eps), reason: 'x of $actual');
  expect(actual.y, closeTo(expected.y, eps), reason: 'y of $actual');
}

void main() {
  group('Affine — hand-computed goldens on ${artboard.x} × ${artboard.y}', () {
    test('identity moves nothing', () {
      expectVec(Affine.identity.apply(artboard), artboard);
      expectVec(const Transform2().toAffine().apply(artboard), artboard);
    });

    test('quarter turn about the artboard centre', () {
      const pivot = Vec2(225.1, 125.2);
      final t = Transform2(pivot: pivot, rotation: math.pi / 2);

      // Right-middle edge. Offset from pivot is (225.1, 0); a +90° turn in a
      // y-down space sends x̂ to ŷ, so the offset becomes (0, 225.1).
      expectVec(
        t.toAffine().apply(Vec2(artboard.x, pivot.y)),
        const Vec2(225.1, 350.3),
        eps: 1e-9,
      );
      // The pivot itself is the fixed point. If this drifts, the pivot terms in
      // toAffine() have the wrong sign.
      expectVec(t.toAffine().apply(pivot), pivot, eps: 1e-12);
    });

    test('non-uniform scale scales each axis by its OWN factor', () {
      const t = Transform2(scale: Vec2(2, 0.5));
      expectVec(t.toAffine().apply(artboard), const Vec2(900.4, 125.2));

      // The legacy defect, stated as a negative: y must not pick up the x
      // factor. 250.4 * 2 would be 500.8.
      expect(t.toAffine().apply(artboard).y, isNot(closeTo(500.8, 1e-6)));
    });

    test('skewX shears x by y, leaving y alone', () {
      final t = Transform2(skewX: math.atan(0.5)); // tan = exactly 0.5
      expectVec(t.toAffine().apply(const Vec2(0, 100)), const Vec2(50, 100),
          eps: 1e-9);
    });

    test('apply translates, applyVector does not', () {
      const m = Affine.translate(10, 20);
      expectVec(m.apply(const Vec2(1, 1)), const Vec2(11, 21));
      // Bezier tangents are directions. Translating them is how handles drift
      // under a moved parent.
      expectVec(m.applyVector(const Vec2(1, 1)), const Vec2(1, 1));
    });
  });

  group('Affine.invert', () {
    test('round-trips a composed transform', () {
      final t = Transform2(
        position: const Vec2(37.5, -12.25),
        scale: const Vec2(2, 0.5),
        pivot: const Vec2(225.1, 125.2),
        rotation: 0.7,
        skewX: 0.3,
      ).toAffine();

      final back = t.invert();
      expect(back, isNotNull);
      expectVec(back!.apply(t.apply(artboard)), artboard, eps: 1e-9);
    });

    test('returns null instead of throwing when scale collapses to zero', () {
      // An animator *will* key scale to 0. The contract is null-and-render-
      // nothing, never an exception — the evaluator is total.
      const t = Transform2(scale: Vec2(0, 1));
      expect(t.toAffine().invert(), isNull);
      expect(t.toAffine().decompose(), isNull);
    });
  });

  group('Affine.decompose', () {
    // World-preserving reparent depends on this being exact: dropping a node
    // into a new parent must not move it on screen.
    final cases = <String, Transform2>{
      'identity': const Transform2(),
      'translation': const Transform2(position: Vec2(37.5, -12.25)),
      'rotation about a pivot': const Transform2(
        pivot: Vec2(225.1, 125.2),
        rotation: 0.7,
      ),
      'non-uniform scale': const Transform2(scale: Vec2(2, 0.5)),
      'skew + rotation + scale': const Transform2(
        position: Vec2(3, 4),
        scale: Vec2(1.5, 0.75),
        pivot: Vec2(225.1, 125.2),
        rotation: -0.4,
        skewX: 0.25,
      ),
    };

    cases.forEach((label, t) {
      test('recovers $label', () {
        final back = t.toAffine().decompose(pivot: t.pivot);
        expect(back, isNotNull, reason: label);
        expectVec(back!.position, t.position, eps: 1e-9);
        expectVec(back.scale, t.scale, eps: 1e-9);
        expect(back.rotation, closeTo(t.rotation, 1e-9));
        expect(back.skewX, closeTo(t.skewX, 1e-9));
        // The real guarantee is the matrix, not the components.
        expectVec(back.toAffine().apply(artboard), t.toAffine().apply(artboard),
            eps: 1e-9);
      });
    });
  });

  group('rotation is unbounded', () {
    test('two reverse turns survive a JSON round-trip verbatim', () {
      const twoTurnsBack = -4 * math.pi; // -12.566370614359172
      const t = Transform2(rotation: twoTurnsBack);

      final back = Transform2.fromJson(t.toJson());
      expect(back.rotation, twoTurnsBack);

      // Not normalised into [-π, π], not wrapped to 0. Shortest-arc "helpfully"
      // applied here is what silently collapses every multi-turn spin.
      expect(back.rotation, lessThan(-math.pi));
    });
  });

  group('Transform2 JSON', () {
    test('round-trips every field, defaulting an absent one', () {
      const t = Transform2(
        position: Vec2(1.5, 2.5),
        scale: Vec2(2, 0.5),
        pivot: Vec2(10, 20),
        rotation: 0.75,
        skewX: -0.25,
      );
      expect(Transform2.fromJson(t.toJson()), t);

      // Int-on-the-wire is the Firestore round-trip hazard: 1.0 written comes
      // back as 1. Every read goes through d(), so this must not throw.
      final fromInts = Transform2.fromJson(<String, Object?>{
        'position': <String, Object?>{'x': 0, 'y': 0},
        'rotation': 0,
      });
      expect(fromInts.position, Vec2.zero);
      expect(fromInts.scale, Vec2.one,
          reason: 'absent scale defaults to (1,1)');
    });
  });
}
