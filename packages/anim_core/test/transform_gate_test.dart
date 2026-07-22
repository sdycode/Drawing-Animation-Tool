/// GATE 2 OF 2 — the golden transform test (docs/v3/00 §5, docs/v3/01 §2,
/// docs/v3/04 §7).
///
/// docs/v3/00 §5 defines the CI gate as exactly two things: this file, and
/// `round_trip_gate_test.dart`. Everything else in `anim_core/test` — including
/// `affine_test.dart`, which keeps the *behavioural* corners of `Affine` that
/// are not part of the golden — is developer-local coverage. **Do not add a
/// third gate.** docs/v3/04 §7 says it in as many words ("No test tracks beyond
/// these"): a third gate grows the release bar without growing the guarantee,
/// and is scope creep wearing a test's clothes.
///
/// **Why this is numeric and not an image.** docs/v3/04 §7 calls the row
/// "Scene → Canvas transform · golden". `anim_core` is pure Dart — no Flutter,
/// no `dart:ui`, so no `Canvas` to rasterise (docs/v3/04 §1). A pixel golden
/// would also be the *weaker* instrument: it fails as "17 pixels differ" and
/// gets re-baselined by whoever is unlucky enough to be on shift. So the golden
/// here is arithmetic — points asserted against values computed **by hand**,
/// with the computation written out above each expectation so a future reader
/// can audit the *expectation itself*, not merely re-derive it from the code
/// under test. When one of these fails, the number tells you which matrix cell
/// is wrong. `anim_render` translates `Affine` into `Matrix4` in one place; that
/// translation is covered there, and it consumes what this file pins down.
///
/// **Why 450.2 × 250.4.** docs/v3/01 §2 names this artboard specifically. Legacy
/// scaled the Y component by the *width* ratio. On a square artboard that bug is
/// perfectly invisible; every assertion below is on a board whose width is
/// ~1.798× its height, so a y-that-took-x's-factor lands somewhere obviously
/// wrong rather than somewhere plausible. Several cases state the wrong answer
/// explicitly as a negative assertion, so the defect cannot come back wearing a
/// different name.
///
/// **What it asserts** — the four docs/v3/01 §2 cases, each on 450.2 × 250.4:
/// identity, pure rotation about a NON-ORIGIN pivot (origin pivots hide sign
/// errors in the ±pivot terms, which cancel), non-uniform scale, and skew. Plus
/// the two properties that doc names: an `invert()` round-trip, and
/// `decompose(toAffine(x)) == x`.
///
/// **What breaks if this goes red.** Every coordinate mapping in the product:
/// parent→child composition, document→screen, zoom/pan, hit-testing, export.
/// A wrong cell here does not crash — it renders a scene that is subtly, and
/// then permanently, in the wrong place, and it is baked into every document
/// saved afterwards. Criterion 5 of 00 §5 ("what you draw is where you click")
/// is false. Do not quarantine this test, and do not "update the golden": the
/// numbers below were computed without running the code, so the code is what is
/// wrong.
library;

import 'dart:math' as math;

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The deliberately lopsided artboard of docs/v3/01 §2. `w / h == 1.7979…`.
const w = 450.2;
const h = 250.4;

/// Bottom-right corner, and the centre — the two points every case below is
/// stated in terms of, because both have a non-zero x *and* y and so cannot
/// accidentally satisfy an assertion by being on an axis.
const corner = Vec2(w, h);
const centre = Vec2(225.1, 125.2);

void expectVec(Vec2 actual, Vec2 expected, {double eps = 1e-9, String? why}) {
  // The suffix is conditional because `closeTo` reports only the one component
  // that drifted: on a y-took-x's-factor regression the reader sees
  // "y of Vec2(900.4, 500.8)" and needs the *whole* vector plus, when the call
  // site supplied one, the reason. Interpolating a null `why` unconditionally
  // appended a literal "— null" to every golden failure, which is the kind of
  // noise that trains people to skim gate output instead of reading it.
  final tail = why == null ? '' : ' — $why';
  expect(actual.x, closeTo(expected.x, eps), reason: 'x of $actual$tail');
  expect(actual.y, closeTo(expected.y, eps), reason: 'y of $actual$tail');
}

void main() {
  group('GATE — identity', () {
    test('moves nothing, from either construction', () {
      // Nothing to compute: an identity that is not identity is a matrix
      // assembled in the wrong order, and this catches it before any of the
      // arithmetic below can be blamed for it.
      expectVec(Affine.identity.apply(corner), corner);
      expectVec(const Transform2().toAffine().apply(corner), corner);
      expectVec(Affine.identity.apply(Vec2.zero), Vec2.zero);
      expectVec(Affine.identity.applyVector(corner), corner);
    });
  });

  group('GATE — pure rotation about a non-origin pivot', () {
    // An origin pivot hides sign errors: toAffine() applies T(pivot) and
    // T(-pivot), and at the origin both are identity, so a swapped sign cancels
    // and the test passes on broken code. Every case here pivots on the
    // artboard centre.

    test('half turn maps a corner onto the opposite corner exactly', () {
      const t = Transform2(pivot: centre, rotation: math.pi);

      // R(π) = [-1 0 ; 0 -1], so p ↦ 2·pivot − p.
      //   (0, 0)         ↦ (2·225.1 − 0,     2·125.2 − 0)     = (450.2, 250.4)
      //   (450.2, 250.4) ↦ (450.2 − 450.2,   250.4 − 250.4)   = (0, 0)
      // Both are exact on this artboard, which is the point: 2·125.2 is the
      // artboard *height*. Y scaled by the width ratio would put the first at
      // y = 450.2 — off the board, and off by a factor this assertion sees.
      expectVec(t.toAffine().apply(Vec2.zero), const Vec2(450.2, 250.4));
      expectVec(t.toAffine().apply(corner), Vec2.zero);
    });

    test('quarter turn: +90° in a y-down space sends x̂ to ŷ', () {
      final t = Transform2(pivot: centre, rotation: math.pi / 2);

      // R(π/2) = [0 −1 ; 1 0], so an offset (dx, dy) becomes (−dy, dx).
      // Right-middle edge (450.2, 125.2): offset from centre is (225.1, 0),
      //   becomes (0, 225.1) → world (225.1 + 0, 125.2 + 225.1) = (225.1, 350.3)
      expectVec(
        t.toAffine().apply(const Vec2(w, 125.2)),
        const Vec2(225.1, 350.3),
      );
      // Bottom-right corner (450.2, 250.4): offset (225.1, 125.2),
      //   becomes (−125.2, 225.1) → world (225.1 − 125.2, 125.2 + 225.1)
      //                            = (99.9, 350.3)
      expectVec(t.toAffine().apply(corner), const Vec2(99.9, 350.3));
    });

    test('the pivot is the fixed point of a pure rotation', () {
      // Tightest tolerance in the file, deliberately. If the ±pivot terms have
      // the wrong sign the pivot walks by twice its own offset — 450.2 units of
      // error, not a rounding artefact.
      for (final r in <double>[0.0, 0.4, -1.9, math.pi, 7 * math.pi]) {
        expectVec(
            Transform2(pivot: centre, rotation: r).toAffine().apply(centre),
            centre,
            eps: 1e-12,
            why: 'rotation $r');
      }
    });

    test('an arbitrary angle, against hand-evaluated trig', () {
      final t = Transform2(pivot: centre, rotation: math.pi / 6);

      // cos(π/6) = √3/2 = 0.8660254037844387 (to double precision)
      // sin(π/6) = 1/2
      // Right-middle edge (450.2, 125.2): offset (225.1, 0).
      //   x' = cos·225.1 = 0.8660254037844387 × 225.1
      //      = 194.85571585149870   (× 225)
      //      +   0.08660254037844   (× 0.1)
      //      = 194.94231839187715
      //   y' = sin·225.1 = 0.5 × 225.1 = 112.55
      // world = (225.1 + 194.94231839187715, 125.2 + 112.55)
      //       = (420.04231839187715, 237.75)
      expectVec(
        t.toAffine().apply(const Vec2(w, 125.2)),
        const Vec2(420.04231839187715, 237.75),
      );

      // A rotation is rigid: distance from the pivot is preserved. Stated
      // separately because a matrix that is *almost* a rotation (a stray scale
      // term) still lands near the expectation above.
      final p = t.toAffine().apply(corner);
      final before = math.sqrt(math.pow(w - centre.x, 2).toDouble() +
          math.pow(h - centre.y, 2).toDouble());
      final after = math.sqrt(math.pow(p.x - centre.x, 2).toDouble() +
          math.pow(p.y - centre.y, 2).toDouble());
      expect(after, closeTo(before, 1e-9),
          reason: 'a pure rotation must not change the radius');
    });
  });

  group('GATE — non-uniform scale', () {
    // THE legacy defect, stated four ways. Each case also asserts the wrong
    // answer is *not* produced, because "close enough" is exactly how a
    // y-scaled-by-width result reads on a board that is not this lopsided.

    test('each axis takes its own factor', () {
      const t = Transform2(scale: Vec2(2, 0.5));
      // (450.2 × 2, 250.4 × 0.5) = (900.4, 125.2)
      expectVec(t.toAffine().apply(corner), const Vec2(900.4, 125.2));
      // y with x's factor would be 250.4 × 2 = 500.8.
      expect(t.toAffine().apply(corner).y, isNot(closeTo(500.8, 1e-6)),
          reason: 'y must not pick up the x factor');
    });

    test('artboard-derived factors: the unit square maps onto the board', () {
      // sx = 450.2 / 100 = 4.502, sy = 250.4 / 100 = 2.504. The point (100, 100)
      // therefore lands exactly on the bottom-right corner — and *only* if the
      // two factors stayed apart:
      //   x = 100 × 4.502 = 450.2
      //   y = 100 × 2.504 = 250.4
      // The legacy form gives y = 100 × 4.502 = 450.2, i.e. a point 199.8 units
      // below an artboard 250.4 units tall. This is the bug, at full size.
      const t = Transform2(scale: Vec2(4.502, 2.504));
      expectVec(t.toAffine().apply(const Vec2(100, 100)), corner);
      expect(t.toAffine().apply(const Vec2(100, 100)).y,
          isNot(closeTo(450.2, 1e-6)),
          reason:
              'the legacy y-scaled-by-width result, named so it stays dead');
    });

    test('scale about a non-origin pivot', () {
      const t = Transform2(scale: Vec2(1.5, 0.25), pivot: centre);
      // offset (225.1, 125.2) ↦ (225.1 × 1.5, 125.2 × 0.25) = (337.65, 31.3)
      // world = (225.1 + 337.65, 125.2 + 31.3) = (562.75, 156.5)
      expectVec(t.toAffine().apply(corner), const Vec2(562.75, 156.5));
      // …and the pivot stays put under scale too.
      expectVec(t.toAffine().apply(centre), centre, eps: 1e-12);
    });

    test('a mirrored axis flips only that axis', () {
      const t = Transform2(scale: Vec2(-1, 1), pivot: centre);
      // offset (225.1, 125.2) ↦ (−225.1, 125.2) → world (0, 250.4)
      expectVec(t.toAffine().apply(corner), const Vec2(0, h));
      expect(t.toAffine().determinant, closeTo(-1, 1e-12),
          reason: 'one mirrored axis inverts orientation');
    });
  });

  group('GATE — skew', () {
    test('skewX shears x by y and leaves y untouched', () {
      final t = Transform2(skewX: math.atan(0.5)); // tan(skewX) == 0.5 exactly

      // SkewX(k) = [1 tan k ; 0 1], so (x, y) ↦ (x + 0.5·y, y).
      //   (0, 250.4)     ↦ (0     + 125.2, 250.4) = (125.2, 250.4)
      //   (450.2, 250.4) ↦ (450.2 + 125.2, 250.4) = (575.4, 250.4)
      expectVec(t.toAffine().apply(const Vec2(0, h)), const Vec2(125.2, h));
      expectVec(t.toAffine().apply(corner), const Vec2(575.4, h));

      // y is *exactly* untouched — not merely close. A skew that leaks into the
      // y row is the same shape of bug as the y-rescale, one cell over.
      expect(t.toAffine().apply(corner).y, h);
      expect(t.toAffine().b, 0.0, reason: 'no y-shear: skewY does not exist');
    });

    test('skew preserves area — determinant is untouched by the shear', () {
      final sheared =
          Transform2(skewX: math.atan(0.5), scale: const Vec2(2, 0.5))
              .toAffine();
      // det = sx · sy = 2 × 0.5 = 1, shear or no shear.
      expect(sheared.determinant, closeTo(1.0, 1e-12));
    });

    test('the full composition, multiplied out by hand', () {
      // local = T(pos)·T(pivot)·R(rot)·SkewX(k)·S(scale)·T(−pivot)
      // with pos = (10, 20), pivot = (225.1, 125.2), rot = π/2, tan k = 0.5,
      // scale = (2, 0.5). Columns as [a c ; b d]:
      //
      //   SkewX·S = [1 0.5 ; 0 1] · [2 0 ; 0 0.5] = [2 0.25 ; 0 0.5]
      //   R(π/2)  = [0 −1 ; 1 0]
      //   M = R·(SkewX·S) = [0 −1 ; 1 0]·[2 0.25 ; 0 0.5]
      //     = [ (0·2 + −1·0)   (0·0.25 + −1·0.5) ;
      //         (1·2 +  0·0)   (1·0.25 +  0·0.5) ]
      //     = [ 0  −0.5 ; 2  0.25 ]
      //
      // p ↦ pos + pivot + M·(p − pivot). For p = (450.2, 250.4),
      // offset = (225.1, 125.2):
      //   M·offset = (0·225.1 + −0.5·125.2,  2·225.1 + 0.25·125.2)
      //            = (−62.6,                 450.2 + 31.3 = 481.5)
      //   world    = (10 + 225.1 − 62.6,     20 + 125.2 + 481.5)
      //            = (172.5,                 626.7)
      final t = Transform2(
        position: const Vec2(10, 20),
        scale: const Vec2(2, 0.5),
        pivot: centre,
        rotation: math.pi / 2,
        skewX: math.atan(0.5),
      );
      expectVec(t.toAffine().apply(corner), const Vec2(172.5, 626.7));

      // The same matrix applied as a *direction*: x̂ ↦ (0, 2). Translation must
      // not apply — bezier tangents are directions, and translating them is how
      // handles drift under a moved parent.
      expectVec(t.toAffine().applyVector(const Vec2(1, 0)), const Vec2(0, 2));
    });
  });

  group('GATE — invert() round-trip', () {
    // Named by docs/v3/01 §2. Hit-testing runs world→local through invert(), so
    // an inverse that is not the inverse means clicks land on the wrong node —
    // 00 §5 criterion 5.

    final poses = <String, Transform2>{
      'identity': const Transform2(),
      'translation': const Transform2(position: Vec2(37.5, -12.25)),
      'rotation about the centre':
          const Transform2(pivot: centre, rotation: 0.7),
      'non-uniform scale': const Transform2(scale: Vec2(2, 0.5)),
      'artboard-derived scale': const Transform2(scale: Vec2(4.502, 2.504)),
      'everything at once': Transform2(
        position: const Vec2(37.5, -12.25),
        scale: const Vec2(2, 0.5),
        pivot: centre,
        rotation: 0.7,
        skewX: math.atan(0.5),
      ),
    };

    final probes = <Vec2>[
      Vec2.zero,
      corner,
      centre,
      const Vec2(w, 0),
      const Vec2(0, h),
      const Vec2(-37.75, 311.5), // deliberately off-board
    ];

    poses.forEach((label, pose) {
      test('$label: inverse ∘ forward is identity on every probe', () {
        final m = pose.toAffine();
        final back = m.invert();
        expect(back, isNotNull, reason: label);
        for (final p in probes) {
          expectVec(back!.apply(m.apply(p)), p, eps: 1e-9, why: '$label at $p');
        }
        // And as matrices, not merely pointwise: a composition that is identity
        // on six points but not identity is still wrong for the seventh.
        final composed = back!.mul(m);
        expect(composed.a, closeTo(1, 1e-9));
        expect(composed.b, closeTo(0, 1e-9));
        expect(composed.c, closeTo(0, 1e-9));
        expect(composed.d, closeTo(1, 1e-9));
        expect(composed.tx, closeTo(0, 1e-9));
        expect(composed.ty, closeTo(0, 1e-9));
      });
    });
  });

  group('GATE — decompose(toAffine(x)) == x', () {
    // Named by docs/v3/01 §2, and load-bearing for world-preserving reparent
    // (01 §12): dropping a node into a new parent must not move it on screen,
    // which means solving for the pose that reproduces its old world matrix.
    // Round-tripping the *components* is the readable assertion; round-tripping
    // the *matrix* is the actual guarantee, because a pose is not unique
    // (rotation ± π with a mirrored scale is the same matrix).

    final poses = <String, Transform2>{
      'identity': const Transform2(),
      'translation': const Transform2(position: Vec2(37.5, -12.25)),
      'rotation about the centre':
          const Transform2(pivot: centre, rotation: 0.7),
      'negative rotation': const Transform2(pivot: centre, rotation: -1.25),
      'non-uniform scale': const Transform2(scale: Vec2(2, 0.5)),
      'artboard-derived scale':
          const Transform2(scale: Vec2(4.502, 2.504), pivot: centre),
      'skew alone': const Transform2(skewX: 0.25),
      'skew + rotation + scale about the centre': const Transform2(
        position: Vec2(3, 4),
        scale: Vec2(1.5, 0.75),
        pivot: centre,
        rotation: -0.4,
        skewX: 0.25,
      ),
    };

    poses.forEach((label, pose) {
      test('recovers $label', () {
        final back = pose.toAffine().decompose(pivot: pose.pivot);
        expect(back, isNotNull, reason: label);

        expectVec(back!.position, pose.position, eps: 1e-9, why: '$label pos');
        expectVec(back.scale, pose.scale, eps: 1e-9, why: '$label scale');
        expect(back.rotation, closeTo(pose.rotation, 1e-9));
        expect(back.skewX, closeTo(pose.skewX, 1e-9));
        expect(back.pivot, pose.pivot);

        // The guarantee, on the lopsided board: same matrix, therefore same
        // pixels, whatever the components came back as.
        for (final p in <Vec2>[Vec2.zero, corner, centre]) {
          expectVec(back.toAffine().apply(p), pose.toAffine().apply(p),
              eps: 1e-9, why: '$label at $p');
        }
      });
    });
  });
}
