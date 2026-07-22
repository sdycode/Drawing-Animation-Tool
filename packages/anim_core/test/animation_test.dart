import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

Animation clip(LoopMode loop, {double duration = 2.0}) => Animation(
      id: const AnimationId('anim-main'),
      name: 'Main',
      durationSeconds: duration,
      loop: loop,
    );

void main() {
  group('normalizedTime (docs/v3/01 §10)', () {
    test('once clamps at both ends', () {
      final a = clip(LoopMode.once);
      expect(normalizedTime(a, 0.0), 0.0);
      expect(normalizedTime(a, 1.0), 0.5);
      expect(normalizedTime(a, 2.0), 1.0);
      expect(normalizedTime(a, 9.0), 1.0, reason: 'past the end holds');
      expect(normalizedTime(a, -3.0), 0.0);
    });

    test('loop wraps, forwards and backwards', () {
      final a = clip(LoopMode.loop);
      expect(normalizedTime(a, 0.5), 0.25);
      expect(normalizedTime(a, 2.0), 0.0);
      expect(normalizedTime(a, 2.5), closeTo(0.25, 1e-12));
      expect(normalizedTime(a, 11.0), closeTo(0.5, 1e-12));
      // A scrub can run backwards past zero; wrapping must not go negative.
      expect(normalizedTime(a, -0.5), closeTo(0.75, 1e-12));
      expect(normalizedTime(a, -2.5), closeTo(0.75, 1e-12));
    });

    test('pingPong is a triangle: 0 -> 1 -> 0', () {
      final a = clip(LoopMode.pingPong);
      expect(normalizedTime(a, 0.0), 0.0);
      expect(normalizedTime(a, 1.0), closeTo(0.5, 1e-12));
      expect(normalizedTime(a, 2.0), closeTo(1.0, 1e-12));
      expect(normalizedTime(a, 3.0), closeTo(0.5, 1e-12), reason: 'returning');
      expect(normalizedTime(a, 4.0), closeTo(0.0, 1e-12));
      expect(normalizedTime(a, 6.0), closeTo(1.0, 1e-12));
      expect(normalizedTime(a, -1.0), closeTo(0.5, 1e-12));
    });

    test('the result is always in [0,1] for every mode and every input', () {
      for (final mode in LoopMode.values) {
        final a = clip(mode);
        for (var n = -400; n <= 400; n++) {
          final t = normalizedTime(a, n / 7.0);
          expect(t.isNaN, isFalse, reason: '$mode');
          expect(t, inInclusiveRange(0.0, 1.0), reason: '$mode');
        }
      }
    });

    test('a zero or negative duration cannot divide by zero', () {
      // Hand-authorable in a stored document. Infinity here would reach every
      // track in the tick.
      for (final mode in LoopMode.values) {
        expect(normalizedTime(clip(mode, duration: 0.0), 1.0), 0.0);
        expect(normalizedTime(clip(mode, duration: -1.0), 1.0), 0.0);
      }
      expect(normalizedTime(clip(LoopMode.loop), double.infinity), 0.0);
      expect(normalizedTime(clip(LoopMode.loop), double.nan), 0.0);
    });
  });

  group('shape', () {
    test('defaults match docs/v3/02 §3.8', () {
      const a = Animation(id: AnimationId('a'), name: '');
      expect(a.durationSeconds, 1.0);
      expect(a.fps, 60);
      expect(a.loop, LoopMode.loop);
      expect(a.tracks, isEmpty);
    });

    test('tracks are sparse and per-node — a node absent is fully static', () {
      // Legacy populated its derived list only for the CURRENTLY SELECTED
      // section, so every other section rendered frozen at keyframe 0.
      final a = Animation(
        id: const AnimationId('a'),
        name: 'sparse',
        tracks: {
          const NodeId('n-sq'): TrackSet({
            const PropertyKey(PropKey.rotation): ScalarTrack([
              const Keyframe<double>(t: 0, value: 0),
              const Keyframe<double>(t: 1, value: 12.5664),
            ]),
          }),
        },
      );

      expect(a.tracksFor(const NodeId('n-sq')).scalar(PropKey.rotation),
          isNotNull);
      expect(a.tracksFor(const NodeId('n-sig')), same(TrackSet.empty),
          reason: 'never null, so no caller has a reason to reach for `!`');
      expect(
          a.tracksFor(const NodeId('n-sig')).scalar(PropKey.rotation), isNull);
    });

    test('copyWith keeps the id and the passthrough map', () {
      const a = Animation(
        id: AnimationId('a'),
        name: 'Main',
        unknownKeys: {'markers': <Object?>[]},
      );
      final b = a.copyWith(durationSeconds: 2.6, loop: LoopMode.once);

      expect(b.id, a.id);
      expect(b.name, 'Main');
      expect(b.durationSeconds, 2.6);
      expect(b.loop, LoopMode.once);
      expect(b.unknownKeys, a.unknownKeys);
    });
  });

  group('wire format (docs/v3/02 §3.8)', () {
    test('a fully populated animation survives encode -> text -> decode', () {
      final a = Animation(
        id: const AnimationId('anim-main'),
        name: 'Main',
        durationSeconds: 2.6,
        fps: 24,
        loop: LoopMode.once,
        tracks: {
          const NodeId('n-sig'): TrackSet({
            const PropertyKey(PropKey.trimEnd): ScalarTrack([
              const Keyframe<double>(
                  t: 0, value: 0, easing: CubicEasing.easeInOut),
              const Keyframe<double>(t: 0.769, value: 1),
            ]),
          }),
          const NodeId('n-sq'): TrackSet({
            const PropertyKey(PropKey.fillColor, 'p-body'): ColorTrack([
              const Keyframe<Rgba>(t: 0, value: Rgba(0.9, 0.24, 0.19)),
              const Keyframe<Rgba>(t: 1, value: Rgba(0.16, 0.42, 0.92)),
            ]),
            const PropertyKey(PropKey.position): Vec2Track([
              const Vec2Keyframe(
                  t: 0, value: Vec2(0, 0), outTangent: Vec2(90, -30)),
              const Vec2Keyframe(t: 1, value: Vec2(340, 120)),
            ]),
          }),
        },
      );

      final back = Animation.fromJson(
          jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>);

      expect(back.id, a.id);
      expect(back.name, 'Main');
      expect(back.durationSeconds, 2.6);
      expect(back.fps, 24);
      expect(back.loop, LoopMode.once);
      expect(back.tracks.keys.map((k) => k.v).toSet(), {'n-sig', 'n-sq'});
      expect(
          back
              .tracksFor(const NodeId('n-sq'))
              .color(PropKey.fillColor, 'p-body')
              ?.sampleAt(0.5)
              .r,
          closeTo(0.53, 1e-9));
      expect(jsonEncode(back.toJson()), jsonEncode(a.toJson()));
    });

    test('optional fields fall back to their declared defaults', () {
      final back = Animation.fromJson(<String, Object?>{'id': 'anim-bare'});
      expect(back.name, '');
      expect(back.durationSeconds, 1.0);
      expect(back.fps, 60);
      expect(back.loop, LoopMode.loop);
      expect(back.tracks, isEmpty);
    });

    test('fps reads through i() and duration through d()', () {
      final back = Animation.fromJson(<String, Object?>{
        'id': 'anim-int',
        'durationSeconds': 3,
        'fps': 30,
      });
      expect(back.durationSeconds, 3.0);
      expect(back.fps, 30);
    });

    test('an unknown loop mode falls back rather than failing the document',
        () {
      final back = Animation.fromJson(
          <String, Object?>{'id': 'anim-x', 'loop': 'bounceForever'});
      expect(back.loop, LoopMode.loop);
    });

    test('unknown animation keys are re-emitted verbatim', () {
      final source = <String, Object?>{
        'id': 'anim-fwd',
        'name': 'from a newer editor',
        'markers': <Object?>[
          <String, Object?>{'t': 0.5, 'name': 'impact'},
        ],
      };
      expect(Animation.fromJson(source).toJson()['markers'], source['markers']);
    });
  });
}
