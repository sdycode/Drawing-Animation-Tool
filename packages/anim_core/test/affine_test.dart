/// Developer-local coverage for `Affine` / `Transform2` — **not** a gate.
///
/// The hand-computed goldens that docs/v3/01 §2 makes mandatory (identity,
/// rotation about a non-origin pivot, non-uniform scale, skew, the `invert()`
/// round-trip and the `decompose(toAffine(x)) == x` property, all on the
/// 450.2 × 250.4 artboard) used to live here. They now live in exactly one
/// place, `transform_gate_test.dart`, so that the gate is one identifiable test
/// target rather than coverage scattered across two files where either could be
/// silently weakened. Do not re-add them here.
///
/// What is left is the behaviour around the edges of the golden: the
/// point-vs-direction distinction, the total (never-throwing) response to a
/// collapsed matrix, the unbounded-rotation invariant, and JSON.
library;

import 'dart:math' as math;

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The artboard from docs/v3/01 §4 — deliberately lopsided, for the same reason
/// the gate uses it: legacy scaled the Y component by the *width* ratio, which
/// is invisible on a square board.
const artboard = Vec2(450.2, 250.4);

void expectVec(Vec2 actual, Vec2 expected, {double eps = 1e-9}) {
  expect(actual.x, closeTo(expected.x, eps), reason: 'x of $actual');
  expect(actual.y, closeTo(expected.y, eps), reason: 'y of $actual');
}

void main() {
  group('points versus directions', () {
    test('apply translates, applyVector does not', () {
      const m = Affine.translate(10, 20);
      expectVec(m.apply(const Vec2(1, 1)), const Vec2(11, 21));
      // Bezier tangents are directions. Translating them is how handles drift
      // under a moved parent.
      expectVec(m.applyVector(const Vec2(1, 1)), const Vec2(1, 1));
    });

    test('a pure translation leaves every direction alone', () {
      const m = Affine.translate(-450.2, 250.4);
      for (final v in <Vec2>[
        Vec2.zero,
        Vec2.one,
        artboard,
        const Vec2(0, -3)
      ]) {
        expectVec(m.applyVector(v), v);
      }
    });
  });

  group('a collapsed matrix is null, never an exception', () {
    test('invert and decompose return null when scale collapses to zero', () {
      // An animator *will* key scale to 0. The contract is null-and-render-
      // nothing, never an exception — the evaluator is total (docs/v3/01 §1
      // rule 3), and `anim_core` has no try/catch to soften a throw here.
      const t = Transform2(scale: Vec2(0, 1));
      expect(t.toAffine().invert(), isNull);
      expect(t.toAffine().decompose(), isNull);

      const both = Transform2(scale: Vec2.zero);
      expect(both.toAffine().invert(), isNull);
      expect(both.toAffine().decompose(), isNull);
    });

    test('a near-singular matrix is treated as singular', () {
      // 1e-13 is below the 1e-12 determinant epsilon: inverting it would
      // produce ~1e13-magnitude coordinates and paint garbage instead of
      // nothing.
      const t = Transform2(scale: Vec2(1e-13, 1));
      expect(t.toAffine().invert(), isNull);
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
