import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The x coordinate of the unit cubic bezier the easing solves against.
double bezierX(CubicEasing e, double u) {
  final v = 1.0 - u;
  return 3.0 * v * v * u * e.x1 + 3.0 * v * u * u * e.x2 + u * u * u;
}

void main() {
  const curves = <CubicEasing>[
    CubicEasing.ease,
    CubicEasing.easeIn,
    CubicEasing.easeOut,
    CubicEasing.easeInOut,
    CubicEasing.backIn,
    CubicEasing.backOut,
  ];

  group('totality', () {
    test('every easing is finite over the whole domain, and past both ends',
        () {
      final easings = <Easing>[
        const LinearEasing(),
        const HoldEasing(),
        const UnknownEasing({'kind': 'spring', 'stiffness': 400.0}),
        ...curves,
        // Degenerate control points an animator can author by dragging a
        // handle onto its neighbour.
        const CubicEasing(0, 0, 0, 0),
        const CubicEasing(1, 1, 1, 1),
        const CubicEasing(0, 1, 1, 0),
        // x outside 0..1: time must stay monotonic, so the solver clamps it.
        const CubicEasing(-4, 0, 9, 1),
      ];

      for (final e in easings) {
        for (var n = -2; n <= 102; n++) {
          final y = applyEasing(e, n / 100.0);
          expect(y.isNaN, isFalse, reason: '$e at ${n / 100}');
          expect(y.isInfinite, isFalse, reason: '$e at ${n / 100}');
        }
      }
    });

    test('u outside 0..1 is clamped, never extrapolated', () {
      expect(applyEasing(const LinearEasing(), -3.0), 0.0);
      expect(applyEasing(const LinearEasing(), 7.0), 1.0);
      expect(applyEasing(CubicEasing.backOut, -3.0), 0.0);
      expect(applyEasing(CubicEasing.backOut, 7.0), 1.0);
    });
  });

  group('the three behaviours', () {
    test('hold maps every u to 0 — the FROM value holds for the whole segment',
        () {
      for (var n = 0; n <= 100; n++) {
        expect(applyEasing(const HoldEasing(), n / 100.0), 0.0);
      }
    });

    test('linear is the identity — the model default must not curve anything',
        () {
      for (var n = 0; n <= 100; n++) {
        expect(applyEasing(const LinearEasing(), n / 100.0), n / 100.0);
      }
      // The default on a keyframe is linear, not easeInOut: a non-identity
      // model default silently curves every programmatically created key.
      expect(
          const Keyframe<double>(t: 0, value: 0).easing, const LinearEasing());
    });

    test('every preset pins both endpoints', () {
      for (final e in curves) {
        expect(applyEasing(e, 0.0), closeTo(0.0, 1e-9), reason: '$e');
        expect(applyEasing(e, 1.0), closeTo(1.0, 1e-9), reason: '$e');
      }
    });
  });

  group('cubic solve accuracy', () {
    test('solving x(u) recovers y(u) — round-trips the curve\'s own parameter',
        () {
      for (final e in curves) {
        for (var n = 0; n <= 40; n++) {
          final u = n / 40.0;
          final x = bezierX(e, u);
          final v = 1.0 - u;
          final y = 3.0 * v * v * u * e.y1 + 3.0 * v * u * u * e.y2 + u * u * u;
          expect(applyEasing(e, x), closeTo(y, 1e-4), reason: '$e at u=$u');
        }
      }
    });

    test('a near-flat x segment still solves — Newton alone would diverge', () {
      // x1 = x2 = 0 flattens the derivative at u=0; the bisection fallback is
      // what keeps this from handing NaN to every downstream lerp.
      const flat = CubicEasing(0, 0, 0, 1);
      for (var n = 0; n <= 100; n++) {
        final y = applyEasing(flat, n / 100.0);
        expect(y.isNaN, isFalse);
        expect(y, inInclusiveRange(-1e-9, 1.0 + 1e-9));
      }
    });

    test('the curve is monotonic in time for every preset', () {
      for (final e in curves) {
        var previous = -1.0;
        for (var n = 0; n <= 200; n++) {
          final x = bezierX(e, n / 200.0);
          expect(x, greaterThanOrEqualTo(previous - 1e-9), reason: '$e');
          previous = x;
        }
      }
    });
  });

  group('overshoot', () {
    test('y is NOT clamped — anticipation and overshoot are the whole point',
        () {
      // backIn dips below 0 (anticipation); backOut rises above 1 (overshoot).
      final dip = [
        for (var n = 0; n <= 100; n++) applyEasing(CubicEasing.backIn, n / 100)
      ].reduce((a, b) => a < b ? a : b);
      final peak = [
        for (var n = 0; n <= 100; n++) applyEasing(CubicEasing.backOut, n / 100)
      ].reduce((a, b) => a > b ? a : b);

      expect(dip, lessThan(-0.02));
      expect(peak, greaterThan(1.02));
    });

    test('x IS clamped — time stays monotonic however the handles are dragged',
        () {
      // Identical y control points, x dragged far outside 0..1. Clamping x
      // makes this behave as (0,0,1,1) rather than running time backwards.
      expect(applyEasing(const CubicEasing(-5, 0, 6, 1), 0.5),
          closeTo(applyEasing(const CubicEasing(0, 0, 1, 1), 0.5), 1e-6));
    });
  });

  group('wire format (docs/v3/02 §3.11)', () {
    test('the three known shapes round-trip', () {
      expect(const LinearEasing().toJson(), {'kind': 'linear'});
      expect(const HoldEasing().toJson(), {'kind': 'hold'});
      expect(CubicEasing.easeInOut.toJson(), {
        'kind': 'cubic',
        'p': [0.42, 0.0, 0.58, 1.0]
      });

      expect(Easing.fromJson({'kind': 'linear'}), const LinearEasing());
      expect(Easing.fromJson({'kind': 'hold'}), const HoldEasing());
      expect(
        Easing.fromJson({
          'kind': 'cubic',
          'p': <Object?>[0.42, 0, 0.58, 1]
        }),
        CubicEasing.easeInOut,
        reason: 'p reads through d(): Firestore hands back 0 for 0.0',
      );
    });

    test('presets are never persisted as names', () {
      // A preset nudged into a custom curve must not be a type change, and the
      // wire format must never have to know the preset vocabulary.
      for (final e in curves) {
        final json = e.toJson();
        expect(json['kind'], 'cubic');
        expect(json['p'], isA<List<Object?>>());
        expect(Easing.fromJson(json), e);
      }
    });

    test('an unknown kind evaluates as linear and re-emits verbatim', () {
      final raw = <String, Object?>{
        'kind': 'spring',
        'stiffness': 400.0,
        'damping': 30.0,
      };
      final e = Easing.fromJson(raw);

      expect(e, isA<UnknownEasing>());
      // Playing on as linear beats a frozen property, and beats a document
      // that will not open at all.
      expect(applyEasing(e, 0.25), 0.25);
      expect(e.toJson(), raw);
    });

    test('a malformed cubic is preserved, not repaired into a plausible curve',
        () {
      final raw = <String, Object?>{
        'kind': 'cubic',
        'p': <Object?>[0.42, 0.0]
      };
      final e = Easing.fromJson(raw);

      expect(e, isA<UnknownEasing>());
      expect(e.toJson(), raw);
    });
  });
}
