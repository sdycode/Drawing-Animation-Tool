import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The M4 track-level mutation API (docs/v3/01 §12; docs/v3/03 F6.2, F7.1).
void main() {
  group('TrackOps.moveKeyframe', () {
    test(
        'is index-addressed: grabbing index 0 and dragging it past index 1 '
        'lands the grabbed value where it was dragged (AC-6.2.1)', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.2, value: 1.0, easing: CubicEasing.backIn),
        const Keyframe(t: 0.5, value: 2.0),
      ]);

      // Grab index 0 (the key holding 1.0) and drag it to 0.8 — past index 1.
      final next = TrackOps.moveKeyframe(track, 0, 0.8);

      expect(next, isA<ScalarTrack>());
      expect(next.keys.map((k) => k.t).toList(), [0.5, 0.8],
          reason: 'the list re-sorts and stays strictly increasing (T2)');
      // The grabbed key kept its value and easing and now sits at 0.8.
      expect(next.keys[1].value, 1.0);
      expect(next.keys[1].easing, CubicEasing.backIn);
      // Its former neighbour is untouched.
      expect(next.keys[0].value, 2.0);
      for (var n = 1; n < next.keys.length; n++) {
        expect(next.keys[n].t, greaterThan(next.keys[n - 1].t));
      }
    });

    test('a plain move preserves value and easing', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.2, value: 1.0),
        const Keyframe(t: 0.5, value: 2.0, easing: CubicEasing.easeInOut),
        const Keyframe(t: 0.8, value: 3.0),
      ]);
      final next = TrackOps.moveKeyframe(track, 1, 0.55);

      expect(next.keys.map((k) => k.t).toList(), [0.2, 0.55, 0.8]);
      expect(next.keys[1].value, 2.0);
      expect(next.keys[1].easing, CubicEasing.easeInOut);
    });

    test('a move within minSeparation of ANOTHER key is rejected (AC-6.2.2)',
        () {
      final track = ScalarTrack([
        const Keyframe(t: 0.2, value: 1.0),
        const Keyframe(t: 0.5, value: 2.0),
      ]);
      // Exactly onto the neighbour, and a near miss inside minSeparation.
      expect(() => TrackOps.moveKeyframe(track, 0, 0.5), throwsArgumentError);
      expect(
          () =>
              TrackOps.moveKeyframe(track, 0, 0.5 - TrackOps.minSeparation / 2),
          throwsArgumentError);
      // Moving onto its OWN position is not a self-collision.
      expect(TrackOps.moveKeyframe(track, 0, 0.2).keys[0].t, 0.2);
    });

    test('newT is clamped to [0,1] (T3), and NaN throws', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.3, value: 1.0),
        const Keyframe(t: 0.6, value: 2.0),
      ]);
      expect(TrackOps.moveKeyframe(track, 1, 1.5).keys.last.t, 1.0);
      expect(TrackOps.moveKeyframe(track, 0, -0.5).keys.first.t, 0.0);
      expect(() => TrackOps.moveKeyframe(track, 0, double.nan),
          throwsArgumentError);
    });

    test('an out-of-range index throws', () {
      final track = ScalarTrack([const Keyframe(t: 0.0, value: 0.0)]);
      expect(() => TrackOps.moveKeyframe(track, 1, 0.5), throwsArgumentError);
      expect(() => TrackOps.moveKeyframe(track, -1, 0.5), throwsArgumentError);
    });

    test('a moved Vec2 key keeps its spatial tangents (motion path survives)',
        () {
      // The adversarial case for the copyWith override: a plain reconstruct
      // would drop these and silently straighten the arc.
      final track = Vec2Track([
        const Vec2Keyframe(t: 0.0, value: Vec2(0, 0)),
        const Vec2Keyframe(
          t: 0.5,
          value: Vec2(10, 10),
          inTangent: Vec2(-5, 0),
          outTangent: Vec2(5, 0),
          easing: CubicEasing.easeIn,
        ),
      ]);
      final next = TrackOps.moveKeyframe(track, 1, 0.8);
      final k = next.keys[1] as Vec2Keyframe;
      expect(k.t, 0.8);
      expect(k.value, const Vec2(10, 10));
      expect(k.inTangent, const Vec2(-5, 0));
      expect(k.outTangent, const Vec2(5, 0));
      expect(k.easing, CubicEasing.easeIn);
    });

    test(
        'the sampler never sees a zero span — enforced at mutation like upsert',
        () {
      // Squares.json's three-keys-at-one-t defect cannot form through a move.
      final track = ScalarTrack([
        const Keyframe(t: 0.2, value: 1.0),
        const Keyframe(t: 0.4, value: 2.0),
        const Keyframe(t: 0.6, value: 3.0),
      ]);
      expect(() => TrackOps.moveKeyframe(track, 0, 0.4), throwsArgumentError);
      expect(() => TrackOps.moveKeyframe(track, 2, 0.4), throwsArgumentError);
    });
  });

  group('TrackOps.removeKeyframeAt', () {
    test('removes the addressed key', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.2, value: 1.0),
        const Keyframe(t: 0.5, value: 2.0),
        const Keyframe(t: 0.8, value: 3.0),
      ]);
      final next = TrackOps.removeKeyframeAt(track, 1);
      expect(next.keys.map((k) => k.t).toList(), [0.2, 0.8]);
      expect(next.keys.map((k) => k.value).toList(), [1.0, 3.0]);
    });

    test('removing the LAST remaining key throws, naming the fix', () {
      final track = ScalarTrack([const Keyframe(t: 0.4, value: 1.0)]);
      expect(
          () => TrackOps.removeKeyframeAt(track, 0),
          throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message',
              contains('KeyframeOps.removeKey'))));
    });

    test('an out-of-range index throws', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 1.0, value: 1.0),
      ]);
      expect(() => TrackOps.removeKeyframeAt(track, 2), throwsArgumentError);
      expect(() => TrackOps.removeKeyframeAt(track, -1), throwsArgumentError);
    });
  });

  group('TrackOps.setEasing', () {
    test('eases the segment LEAVING the key, index-addressed (AC-7.1.1)', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 0.5, value: 10.0),
        const Keyframe(t: 1.0, value: 20.0),
      ]);
      final next = TrackOps.setEasing(track, 0, const HoldEasing());
      expect(next.keys[0].easing, const HoldEasing());
      // Only segment 0 changed: value and time are untouched, and the other
      // segment still interpolates linearly.
      expect(next.keys.map((k) => k.t).toList(), [0.0, 0.5, 1.0]);
      expect(next.keys.map((k) => k.value).toList(), [0.0, 10.0, 20.0]);
      expect(next.keys[1].easing, const LinearEasing());
    });

    test(
        'a HoldEasing segment STEPS: holds the left value, then jumps (AC-7.1.4)',
        () {
      final track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 0.5, value: 10.0),
        const Keyframe(t: 1.0, value: 20.0),
      ]);
      final held = TrackOps.setEasing(track, 0, const HoldEasing());

      // Across segment 0 the value holds the left key…
      expect(held.sampleAt(0.25), 0.0);
      expect(held.sampleAt(0.49), 0.0);
      // …then jumps at the next key.
      expect(held.sampleAt(0.5), 10.0);
      // Segment 1 was not touched: it still lerps.
      expect(held.sampleAt(0.75), 15.0);
    });

    test('each segment eases independently (AC-7.1.1)', () {
      TypedTrack<double> track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 0.5, value: 10.0),
        const Keyframe(t: 1.0, value: 20.0),
      ]);
      track = TrackOps.setEasing(track, 0, const HoldEasing());
      track = TrackOps.setEasing(track, 1, CubicEasing.easeIn);
      expect(track.keys[0].easing, const HoldEasing());
      expect(track.keys[1].easing, CubicEasing.easeIn);
      expect(track.keys[2].easing, const LinearEasing());
    });

    test('the last key stores its easing losslessly though it governs nothing',
        () {
      final track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 1.0, value: 10.0),
      ]);
      final next = TrackOps.setEasing(track, 1, CubicEasing.backIn);
      expect(next.keys.last.easing, CubicEasing.backIn);
      // No outgoing segment, so sampling is unchanged.
      expect(next.sampleAt(0.5), 5.0);
    });

    test('an out-of-range index throws', () {
      final track = ScalarTrack([const Keyframe(t: 0.0, value: 0.0)]);
      expect(() => TrackOps.setEasing(track, 1, const HoldEasing()),
          throwsArgumentError);
    });
  });

  group('TrackOps.pinEndpoints', () {
    test('moves the first key to 0 and the last to 1, preserving values', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.4, value: 5.0, easing: CubicEasing.backIn),
        const Keyframe(t: 0.6, value: 7.0),
        const Keyframe(t: 0.8, value: 9.0),
      ]);
      final next = TrackOps.pinEndpoints(track);
      expect(next.keys.map((k) => k.t).toList(), [0.0, 0.6, 1.0]);
      expect(next.keys.map((k) => k.value).toList(), [5.0, 7.0, 9.0]);
      expect(next.keys.first.easing, CubicEasing.backIn);
    });

    test('a single-key track is expanded to hold across [0,1]', () {
      final track = ScalarTrack([const Keyframe(t: 0.4, value: 5.0)]);
      final next = TrackOps.pinEndpoints(track);
      expect(next.keys.map((k) => k.t).toList(), [0.0, 1.0]);
      expect(next.keys.map((k) => k.value).toList(), [5.0, 5.0]);
    });

    test('a track already spanning [0,1] is returned unchanged', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 1.0, value: 10.0),
      ]);
      expect(identical(TrackOps.pinEndpoints(track), track), isTrue);
    });

    test(
        'pinning is NEVER automatic: a track starting at t = 0.4 stays at 0.4 '
        'through decode and every other op (AC-6.2.4, T6)', () {
      // Decode.
      final decoded = Track.fromJson(<String, Object?>{
        'type': 'scalar',
        'keys': <Object?>[
          <String, Object?>{'t': 0.4, 'value': 1.0},
          <String, Object?>{'t': 0.8, 'value': 2.0},
        ],
      })! as ScalarTrack;
      expect(decoded.firstT, 0.4, reason: 'decode does not pin');

      // upsert.
      TypedTrack<double> t =
          TrackOps.upsertKeyframe(decoded, const Keyframe(t: 0.6, value: 1.5));
      expect(t.firstT, 0.4);

      // setEasing.
      t = TrackOps.setEasing(t, 0, CubicEasing.easeIn);
      expect(t.firstT, 0.4);

      // move the interior key.
      t = TrackOps.moveKeyframe(t, 1, 0.55);
      expect(t.firstT, 0.4);

      // remove one.
      t = TrackOps.removeKeyframeAt(t, 1);
      expect(t.firstT, 0.4);

      // Only the explicit affordance pins it.
      expect(TrackOps.pinEndpoints(t).firstT, 0.0);
    });
  });
}
