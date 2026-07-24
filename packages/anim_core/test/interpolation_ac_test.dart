import 'dart:math' as math;

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// F7.2 / F7.3 — the interpolation ACs the M0/M1 evaluator already satisfies,
/// asserted explicitly at the numbers (docs/v3/03). These VERIFY, not rewrite.
void main() {
  test('AC-7.2.2 — path interpolation is an ID join, never an array index', () {
    // Topology drives the loop; the pose maps are looked up by AnchorId. The
    // trap: the `to` pose lists its anchors in REVERSE order and the two anchors
    // move to DIFFERENT places, so an index join would mis-pair them.
    final topology = PathData(anchors: const [
      Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
      Anchor(id: AnchorId('a1'), position: Vec2(10, 0)),
    ]);
    final from = PathPose({
      const AnchorId('a0'): const AnchorPose(Vec2(0, 0), Vec2.zero, Vec2.zero),
      const AnchorId('a1'): const AnchorPose(Vec2(10, 0), Vec2.zero, Vec2.zero),
    });
    final to = PathPose({
      // a1 first on purpose.
      const AnchorId('a1'):
          const AnchorPose(Vec2(10, -30), Vec2.zero, Vec2.zero),
      const AnchorId('a0'): const AnchorPose(Vec2(0, 20), Vec2.zero, Vec2.zero),
    });

    final out = resolveNodePose(
        topology, <PathBracket>[PathBracket(from, to, 0.5, 1.0)]);

    // a0: lerp((0,0),(0,20),0.5) = (0,10). a1: lerp((10,0),(10,-30),0.5)=(10,-15).
    expect(out.anchors[0].position, const Vec2(0, 10),
        reason: 'a0 joined by id, not by the reversed to-map order');
    expect(out.anchors[1].position, const Vec2(10, -15));
  });

  test('AC-7.2.3 — a BoolTrack steps: it holds the FROM value, never lerps',
      () {
    final track = BoolTrack([
      const Keyframe(t: 0.0, value: false),
      const Keyframe(t: 1.0, value: true),
    ]);
    expect(track.sampleAt(0.0), isFalse);
    expect(track.sampleAt(0.5), isFalse, reason: 'holds the left key');
    expect(track.sampleAt(0.999), isFalse);
    expect(track.sampleAt(1.0), isTrue, reason: 'jumps at the next key');
  });

  test('AC-7.2.4 — rotation keyed 0 → 10π spins five times (no shortest arc)',
      () {
    final tenPi = 10.0 * math.pi;
    final track = ScalarTrack([
      const Keyframe(t: 0.0, value: 0.0),
      Keyframe(t: 1.0, value: tenPi),
    ]);
    expect(track.sampleAt(0.5), closeTo(5.0 * math.pi, 1e-12));
    expect(track.sampleAt(1.0), closeTo(tenPi, 1e-12));
    // Shortest-arc normalisation would collapse 10π (≡ 0 mod 2π) to ~0.
    expect(track.sampleAt(1.0), greaterThan(31.0));
  });

  test('AC-7.2.5 — hold-first / hold-last; the value is present at t = 1.0',
      () {
    // A track that spans only [0.3, 0.7] must still be defined everywhere.
    final track = ScalarTrack([
      const Keyframe(t: 0.3, value: 5.0),
      const Keyframe(t: 0.7, value: 9.0),
    ]);
    expect(track.sampleAt(0.0), 5.0, reason: 'hold-first');
    expect(track.sampleAt(0.3), 5.0);
    expect(track.sampleAt(0.7), 9.0);
    expect(track.sampleAt(1.0), 9.0,
        reason: 'hold-last: nothing vanishes at 1');
  });

  test('AC-7.3.1 — null spatial tangents give a straight-line lerp', () {
    final straight = Vec2Track([
      const Vec2Keyframe(t: 0.0, value: Vec2(0, 0)),
      const Vec2Keyframe(t: 1.0, value: Vec2(10, 10)),
    ]);
    expect(straight.sampleAt(0.5), const Vec2(5, 5));
  });

  test('AC-7.3.3 — time easing and spatial curvature are orthogonal', () {
    // Same curved segment, once with hold easing and once with linear easing.
    Vec2Track build(Easing leaving) => Vec2Track([
          Vec2Keyframe(
              t: 0.0,
              value: const Vec2(0, 0),
              outTangent: const Vec2(30, 0),
              easing: leaving),
          const Vec2Keyframe(
              t: 1.0, value: Vec2(0, 30), inTangent: Vec2(30, 0)),
        ]);

    // Hold freezes TIME at u = 0 across the whole segment: the point sits on the
    // from-key though the tangents describe a full arc.
    expect(build(const HoldEasing()).sampleAt(0.5), const Vec2(0, 0));

    // Linear lets u = 0.5 walk the identical cubic — the SPACE is unchanged,
    // only the time parameter differs.
    final curved = build(const LinearEasing()).sampleAt(0.5);
    expect(curved.x, closeTo(22.5, 1e-12));
    expect(curved.y, closeTo(15.0, 1e-12));
  });
}
