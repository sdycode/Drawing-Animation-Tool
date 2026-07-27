/// The nearest-point solve behind the pen's mid-segment insert (AC-4.3.1).
///
/// [insertionCandidate] projects a hover onto a node's posed cubics to find where
/// a click would split the outline. The maths lives in a private
/// `_projectOntoCubic`, so these tests exercise it through the one public door —
/// a one-segment path node and a query point — and assert the foot it returns is
/// the *genuinely* nearest one, not the wrong branch of a fold.
library;

import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter_test/flutter_test.dart';

/// A single **open** cubic as a two-anchor path: segment 0 is
/// `(p0, p0+out0, p3+in1, p3)`, so the tangents are chosen to hit the control
/// points [p1]/[p2] exactly.
Document _oneCubic(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3) {
  final path = PathData(
    anchors: [
      Anchor(id: const AnchorId('a'), position: p0, outTangent: p1 - p0),
      Anchor(id: const AnchorId('b'), position: p3, inTangent: p2 - p3),
    ],
  );
  final base = Document.create(name: 'probe', artboard: const Vec2(500, 400));
  return base.copyWith(
    root: GroupNode(
      id: base.root.id,
      name: base.root.name,
      children: [PathNode(id: const NodeId('c'), name: 'c', path: path)],
    ),
  );
}

Vec2 _cubicAt(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final v = 1.0 - u;
  return p0 * (v * v * v) +
      p1 * (3 * v * v * u) +
      p2 * (3 * v * u * u) +
      p3 * (u * u * u);
}

double _dist(Vec2 a, Vec2 b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// The genuinely nearest point on the cubic, found by brute force at a resolution
/// far finer than the solve's — the ground truth the solve must match.
(double, Vec2) _bruteNearest(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, Vec2 q) {
  const n = 400000;
  var bestU = 0.0;
  var bestPt = p0;
  var bestD = double.infinity;
  for (var i = 0; i <= n; i++) {
    final u = i / n;
    final pt = _cubicAt(p0, p1, p2, p3, u);
    final d = _dist(pt, q);
    if (d < bestD) {
      bestD = d;
      bestU = u;
      bestPt = pt;
    }
  }
  return (bestU, bestPt);
}

void main() {
  // The insert candidate reads a mix; with no tracks any t resolves the rest
  // pose, and the node's identity transform makes local == world == doc space.
  List<AnimationMix> restMix(Document doc) =>
      <AnimationMix>[AnimationMix(doc.defaultAnimation!.id, 0.0)];

  group('_projectOntoCubic via insertionCandidate', () {
    test(
        'a self-crossing cubic returns the branch genuinely nearest the cursor, '
        'not the one a single-bracket solve slides into', () {
      // The audit probe: strong opposing middle tangents fold the curve so two of
      // its branches pass within ~3 px near the middle. A single coarse minimum
      // plus one Newton bracket landed up to 2.63 px along the curve onto the
      // wrong branch here.
      const p0 = Vec2(100, 200);
      const p1 = Vec2(400, 40);
      const p2 = Vec2(50, 40);
      const p3 = Vec2(350, 200);
      final doc = _oneCubic(p0, p1, p2, p3);

      // A handful of cursor points around the fold, each between the two close
      // branches — the region where the wrong-branch answer used to win.
      for (final q in const <Vec2>[
        Vec2(223, 100),
        Vec2(225, 95),
        Vec2(227, 105),
        Vec2(220, 110),
        Vec2(230, 110),
      ]) {
        final hit = insertionCandidate(doc, restMix(doc), const NodeId('c'), q);
        expect(hit, isNotNull, reason: 'the one segment always has a foot');

        final (_, truePt) = _bruteNearest(p0, p1, p2, p3, q);
        final foot = hit!.local;
        // The foot the solve chose is the genuinely nearest point: within a
        // small fraction of a pixel of the brute-force optimum, not the 2.6 px
        // wrong-branch answer.
        expect(_dist(foot, truePt), lessThan(0.25),
            reason: 'foot for q=$q landed on the wrong branch');
        // And no closer point exists: its distance matches the global minimum.
        expect(_dist(foot, q), lessThanOrEqualTo(_dist(truePt, q) + 0.01),
            reason: 'q=$q recovered a non-minimal foot');
      }
    });

    test('a normal convex cubic stays machine-exact for a query on the curve',
        () {
      // A smooth arch — one minimum, no fold — is the everyday case, and it must
      // not regress: a query taken exactly off the curve is recovered onto it.
      const p0 = Vec2(100, 300);
      const p1 = Vec2(180, 120);
      const p2 = Vec2(320, 120);
      const p3 = Vec2(400, 300);
      final doc = _oneCubic(p0, p1, p2, p3);

      for (final u in const <double>[0.13, 0.37, 0.5, 0.62, 0.86]) {
        final q = _cubicAt(p0, p1, p2, p3, u);
        final hit = insertionCandidate(doc, restMix(doc), const NodeId('c'), q);
        expect(hit, isNotNull);
        expect(_dist(hit!.local, q), lessThan(1e-6),
            reason: 'the foot of a point on the curve is the point itself');
      }
    });
  });
}
