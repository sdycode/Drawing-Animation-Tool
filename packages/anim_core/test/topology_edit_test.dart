/// M5 ★ — topology editing (docs/v3/01 §12, §13.5; docs/v3/03 F4.3; docs/v3/06
/// M5). The load-bearing feature: [PathOps.insertAnchor], [PathOps.deleteAnchor]
/// and [PathOps.retopologize].
///
/// This is where M5 is proven. "Pixel-identical" is a claim about **exactness**,
/// not best effort — the golden below is written to bite a nearly-correct split.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

void main() {
  const n = NodeId('n1');

  // -------------------------------------------------------------------------
  // 1. The docs/v3/01 §13.5 worked example, hand-computed to 1e-12.
  // -------------------------------------------------------------------------
  group('§13.5 worked example — insert after a2 at u=0.5', () {
    // The exact square of §13.5: the a2→a3 edge is the flat vertical segment
    // P0=(100,0) → P3=(100,100).
    List<Anchor> square135() => const <Anchor>[
          Anchor(id: AnchorId('a1'), position: Vec2(0, 0)),
          Anchor(id: AnchorId('a2'), position: Vec2(100, 0)),
          Anchor(id: AnchorId('a3'), position: Vec2(100, 100)),
          Anchor(id: AnchorId('a4'), position: Vec2(0, 100)),
        ];

    PathPose pose135(Vec2 a1, Vec2 a4) => PathPose(<AnchorId, AnchorPose>{
          const AnchorId('a1'): AnchorPose(a1, Vec2.zero, Vec2.zero),
          const AnchorId('a2'):
              const AnchorPose(Vec2(100, 0), Vec2.zero, Vec2.zero),
          const AnchorId('a3'):
              const AnchorPose(Vec2(100, 100), Vec2.zero, Vec2.zero),
          const AnchorId('a4'): AnchorPose(a4, Vec2.zero, Vec2.zero),
        });

    // Three keyframes at t = 0.0 / 0.5 / 1.0. a2 and a3 hold the flat edge in
    // every keyframe while a1/a4 animate — so the §13.5 numbers are reproduced
    // in EVERY keyframe even though the shape is not static.
    Document doc135() {
      final track = PathTrack(<Keyframe<PathPose>>[
        Keyframe<PathPose>(
            t: 0.0, value: pose135(const Vec2(0, 0), const Vec2(0, 100))),
        Keyframe<PathPose>(
            t: 0.5, value: pose135(const Vec2(-30, -20), const Vec2(-30, 120))),
        Keyframe<PathPose>(
            t: 1.0, value: pose135(const Vec2(0, 0), const Vec2(0, 100))),
      ]);
      final animation = Animation(
        id: const AnimationId('anim'),
        name: 'Main',
        tracks: <NodeId, TrackSet>{
          n: TrackSet(
              <PropertyKey, Track>{const PropertyKey(PropKey.path): track}),
        },
      );
      return Document(
        id: 'doc',
        name: 't',
        artboard: const Vec2(450.2, 250.4),
        root:
            GroupNode(id: const NodeId('root'), name: 'Root', children: <Node>[
          PathNode(
              id: n,
              name: 'p',
              path: PathData(anchors: square135(), closed: true)),
        ]),
        animations: <Animation>[animation],
        defaultAnimationId: animation.id,
      );
    }

    test('reproduces S=(100,50), inT=(0,-25), outT=(0,25); neighbours zeroed',
        () {
      final (d2, a5) = PathOps.insertAnchor(doc135(), n,
          after: const AnchorId('a2'), u: 0.5);

      // Topology: draw order is a1, a2, a5, a3, a4.
      final topo = (d2.nodeIndex[n]! as PathNode).path;
      expect(topo.anchors.map((a) => a.id.v).toList(),
          <String>['a1', 'a2', a5.v, 'a3', 'a4']);

      final restNew = topo.anchors.firstWhere((a) => a.id == a5);
      expect(restNew.kind, AnchorKind.smooth,
          reason: '§13.5: the inserted anchor is smooth with non-zero handles');
      _expectVec(restNew.position, const Vec2(100, 50));
      _expectVec(restNew.inTangent, const Vec2(0, -25));
      _expectVec(restNew.outTangent, const Vec2(0, 25));
      _expectVec(
          topo.anchors.firstWhere((a) => a.id.v == 'a2').outTangent, Vec2.zero);
      _expectVec(
          topo.anchors.firstWhere((a) => a.id.v == 'a3').inTangent, Vec2.zero);

      // The doc's numbers, in EVERY keyframe.
      final track = d2.defaultAnimation!.tracksFor(n).pathTrack()!;
      expect(track.keyCount, 3);
      for (final k in track.keys) {
        final poses = k.value.anchors;
        _expectVec(poses[a5]!.position, const Vec2(100, 50),
            reason: 't=${k.t}');
        _expectVec(poses[a5]!.inTangent, const Vec2(0, -25),
            reason: 't=${k.t}');
        _expectVec(poses[a5]!.outTangent, const Vec2(0, 25),
            reason: 't=${k.t}');
        _expectVec(poses[const AnchorId('a2')]!.outTangent, Vec2.zero,
            reason: 't=${k.t}');
        _expectVec(poses[const AnchorId('a3')]!.inTangent, Vec2.zero,
            reason: 't=${k.t}');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 2. PIXEL-IDENTICAL golden (AC-4.3.2). Curved, large asymmetric tangents,
  //    multi-key — a nearly-correct split drifts and this test catches it.
  // -------------------------------------------------------------------------
  group('AC-4.3.2 — pixel-identical after insert (the golden)', () {
    const c0 = AnchorId('c0'), c1 = AnchorId('c1'), c2 = AnchorId('c2');

    List<Anchor> curvy() => const <Anchor>[
          Anchor(
              id: c0,
              position: Vec2(0, 0),
              outTangent: Vec2(70, -12),
              kind: AnchorKind.smooth),
          Anchor(
              id: c1,
              position: Vec2(120, 30),
              inTangent: Vec2(-8, -75),
              outTangent: Vec2(40, 95),
              kind: AnchorKind.smooth),
          Anchor(
              id: c2,
              position: Vec2(60, 140),
              inTangent: Vec2(85, 6),
              outTangent: Vec2(-90, -4),
              kind: AnchorKind.smooth),
        ];

    PathPose poseC(Vec2 p0, Vec2 o0, Vec2 p1, Vec2 i1, Vec2 o1, Vec2 p2,
            Vec2 i2, Vec2 o2) =>
        PathPose(<AnchorId, AnchorPose>{
          c0: AnchorPose(p0, Vec2.zero, o0),
          c1: AnchorPose(p1, i1, o1),
          c2: AnchorPose(p2, i2, o2),
        });

    // Three keys, each with genuinely different large asymmetric handles on the
    // c0→c1 segment, so the split is a distinct computation per keyframe.
    final track = PathTrack(<Keyframe<PathPose>>[
      Keyframe<PathPose>(
          t: 0.0,
          value: poseC(
              const Vec2(0, 0),
              const Vec2(70, -12),
              const Vec2(120, 30),
              const Vec2(-8, -75),
              const Vec2(40, 95),
              const Vec2(60, 140),
              const Vec2(85, 6),
              const Vec2(-90, -4))),
      Keyframe<PathPose>(
          t: 0.45,
          value: poseC(
              const Vec2(10, -5),
              const Vec2(130, -60),
              const Vec2(150, 10),
              const Vec2(-90, -20),
              const Vec2(20, 140),
              const Vec2(40, 150),
              const Vec2(60, 40),
              const Vec2(-120, 10))),
      Keyframe<PathPose>(
          t: 1.0,
          value: poseC(
              const Vec2(-8, 8),
              const Vec2(55, -110),
              const Vec2(150, 50),
              const Vec2(-140, -10),
              const Vec2(20, 120),
              const Vec2(80, 120),
              const Vec2(150, -20),
              const Vec2(-70, -30))),
    ]);

    Document doc() {
      final animation = Animation(
        id: const AnimationId('anim'),
        name: 'Main',
        tracks: <NodeId, TrackSet>{
          n: TrackSet(
              <PropertyKey, Track>{const PropertyKey(PropKey.path): track}),
        },
      );
      return Document(
        id: 'doc',
        name: 't',
        artboard: const Vec2(450.2, 250.4),
        root:
            GroupNode(id: const NodeId('root'), name: 'Root', children: <Node>[
          PathNode(
              id: n, name: 'p', path: PathData(anchors: curvy(), closed: true)),
        ]),
        animations: <Animation>[animation],
        defaultAnimationId: animation.id,
      );
    }

    test('every keyframe samples identically (≤1e-9) on the split segment', () {
      const u = 0.37; // asymmetric, so an inexact split cannot hide
      final d0 = doc();
      final (d2, a5) = PathOps.insertAnchor(d0, n, after: c0, u: u);

      for (final t in <double>[0.0, 0.45, 1.0]) {
        final before = _geomAt(d0, n, t);
        final after = _geomAt(d2, n, t);

        final bi = before.anchors.indexWhere((a) => a.id == c0);
        final ai = after.anchors.indexWhere((a) => a.id == c0);
        expect(after.anchors[ai + 1].id, a5);

        final cBefore = before.segment(bi);
        final cLeft = after.segment(ai);
        final cRight = after.segment((ai + 1) % after.segmentCount);

        var worst = 0.0;
        for (var i = 0; i <= 400; i++) {
          final tt = i / 400.0;
          final expected = _cubic(cBefore, tt);
          final actual = tt <= u
              ? _cubic(cLeft, tt / u)
              : _cubic(cRight, (tt - u) / (1.0 - u));
          final e = (actual - expected).length;
          if (e > worst) worst = e;
        }
        expect(worst, lessThan(1e-9),
            reason:
                't=$t: the two sub-cubics must reproduce the original curve '
                'exactly; worst deviation was $worst');

        // Every OTHER segment is byte-identical — the insert touches one segment.
        _expectSegment(after.segment((ai + 2) % after.segmentCount),
            before.segment((bi + 1) % before.segmentCount));
        _expectSegment(after.segment((ai + 3) % after.segmentCount),
            before.segment((bi + 2) % before.segmentCount));
      }
    });

    test('an inexact split (zeroed new handles) WOULD fail this golden', () {
      // Prove the test bites: reconstruct with the new anchor's handles zeroed
      // — the exact defect §13.5 warns against — and show it drifts past 1e-9.
      const u = 0.37;
      final d0 = doc();
      final before = _geomAt(d0, n, 0.45);
      final bi = before.anchors.indexWhere((a) => a.id == c0);
      final (p0, p1, p2, p3) = before.segment(bi);
      final q0 = Vec2.lerp(p0, p1, u),
          q1 = Vec2.lerp(p1, p2, u),
          q2 = Vec2.lerp(p2, p3, u);
      final r0 = Vec2.lerp(q0, q1, u), r1 = Vec2.lerp(q1, q2, u);
      final s = Vec2.lerp(r0, r1, u);
      // WRONG: new anchor gets zero handles (a corner) instead of R0-S / R1-S.
      final badLeft = (p0, q0, s, s);
      final badRight = (s, s, q2, p3);
      var worst = 0.0;
      for (var i = 0; i <= 400; i++) {
        final tt = i / 400.0;
        final expected = _cubic(before.segment(bi), tt);
        final actual = tt <= u
            ? _cubic(badLeft, tt / u)
            : _cubic(badRight, (tt - u) / (1 - u));
        worst = max(worst, (actual - expected).length);
      }
      expect(worst, greaterThan(1.0),
          reason: 'a zero-handle split visibly deforms the curve — the golden '
              'must be able to see that');
    });
  });

  // -------------------------------------------------------------------------
  // 3. AC-4.3.6 — the CI invariant, as a reusable checker + property sweep.
  // -------------------------------------------------------------------------
  group('AC-4.3.6 — identical AnchorId sequence across every keyframe', () {
    test('holds after every op in random insert/delete/retopologize sequences',
        () {
      for (var seed = 0; seed < 8; seed++) {
        final rng = Random(seed);
        var d = _twoAnimationDoc(); // square, path tracks in TWO animations
        assertSequenceInvariant(d, n);

        for (var step = 0; step < 30; step++) {
          final node = d.nodeIndex[n]! as PathNode;
          final count = node.path.anchors.length;
          final roll = rng.nextInt(10);

          if (roll < 5 && node.path.segmentCount > 0) {
            final after = node.path.anchors[rng.nextInt(count)].id;
            final u = 0.05 + rng.nextDouble() * 0.9;
            d = PathOps.insertAnchor(d, n, after: after, u: u).$1;
          } else if (roll < 8 && count > 3) {
            final victim = node.path.anchors[rng.nextInt(count)].id;
            d = PathOps.deleteAnchor(d, n, victim);
          } else {
            final topo = PolygonRecipe(
              sides: 3 + rng.nextInt(6),
              radius: 30 + rng.nextDouble() * 40,
              star: rng.nextBool(),
              innerRatio: 0.4,
            ).toPath();
            d = PathOps.retopologize(d, n, topo);
          }
          assertSequenceInvariant(d, n);
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // 4. insert respects `closed` (wrapping last segment).
  // -------------------------------------------------------------------------
  group('insert on the wrapping last segment (closed)', () {
    test('appends the new anchor at the end and splits after→a0', () {
      final d = _squareDoc(withTrack: true);
      // a3 is the last anchor of the closed square; its segment wraps to a0.
      final (d2, a5) =
          PathOps.insertAnchor(d, n, after: const AnchorId('a3'), u: 0.5);

      final topo = (d2.nodeIndex[n]! as PathNode).path;
      expect(topo.anchors.map((a) => a.id.v).toList(),
          <String>['a0', 'a1', 'a2', 'a3', a5.v],
          reason: 'the wrap inserts at the very end, before a0 in draw order');

      // The a3→a0 edge runs (0,20)→(0,0); its midpoint is (0,10).
      final restNew = topo.anchors.last;
      _expectVec(restNew.position, const Vec2(0, 10));
      assertSequenceInvariant(d2, n);

      // Pixel-identical on the wrapped segment, in every keyframe.
      for (final t in <double>[0.0, 1.0]) {
        final before = _geomAt(d, n, t);
        final after = _geomAt(d2, n, t);
        final bi = before.anchors.indexWhere((a) => a.id.v == 'a3');
        final ai = after.anchors.indexWhere((a) => a.id.v == 'a3');
        final cBefore = before.segment(bi);
        final cLeft = after.segment(ai);
        final cRight = after.segment((ai + 1) % after.segmentCount);
        for (var i = 0; i <= 200; i++) {
          final tt = i / 200.0;
          final expected = _cubic(cBefore, tt);
          final actual = tt <= 0.5
              ? _cubic(cLeft, tt / 0.5)
              : _cubic(cRight, (tt - 0.5) / 0.5);
          expect((actual - expected).length, lessThan(1e-9));
        }
      }
    });

    test('u near 0 and near 1 are legal and stay exact', () {
      for (final u in <double>[0.001, 0.999]) {
        final d = _squareDoc(withTrack: true);
        final (d2, a5) =
            PathOps.insertAnchor(d, n, after: const AnchorId('a0'), u: u);
        assertSequenceInvariant(d2, n);
        final before = _geomAt(d, n, 0.0);
        final after = _geomAt(d2, n, 0.0);
        final ai = after.anchors.indexWhere((a) => a.id == a5);
        // reconstruction of the a0→a1 edge from the two sub-cubics
        final cBefore = before.segment(0);
        final cLeft = after.segment(ai - 1);
        final cRight = after.segment(ai % after.segmentCount);
        for (var i = 0; i <= 200; i++) {
          final tt = i / 200.0;
          final expected = _cubic(cBefore, tt);
          final actual = tt <= u
              ? _cubic(cLeft, tt / u)
              : _cubic(cRight, (tt - u) / (1 - u));
          expect((actual - expected).length, lessThan(1e-9), reason: 'u=$u');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // 5. deleteAnchor.
  // -------------------------------------------------------------------------
  group('deleteAnchor (AC-4.3.5)', () {
    test('removes the id from PathData AND every keyframe of every animation',
        () {
      var d = _twoAnimationDoc();
      d = PathOps.deleteAnchor(d, n, const AnchorId('a2'));

      final topo = (d.nodeIndex[n]! as PathNode).path;
      expect(
          topo.anchors.map((a) => a.id.v).toList(), <String>['a0', 'a1', 'a3']);
      for (final anim in d.animations) {
        final track = anim.tracksFor(n).pathTrack()!;
        for (final k in track.keys) {
          expect(k.value.anchors.containsKey(const AnchorId('a2')), isFalse);
          expect(k.value.anchors.keys.map((i) => i.v).toList(),
              <String>['a0', 'a1', 'a3']);
        }
      }
      assertSequenceInvariant(d, n);
    });

    test('does NOT auto-repair neighbour tangents', () {
      // Insert (which writes neighbour tangents), then delete the new anchor:
      // the neighbours keep whatever the insert left, not a re-continuity fix.
      var d = _squareDoc(withTrack: true);
      final (d2, a5) =
          PathOps.insertAnchor(d, n, after: const AnchorId('a0'), u: 0.5);
      final afterInsertA1In = (d2.nodeIndex[n]! as PathNode)
          .path
          .anchors
          .firstWhere((a) => a.id.v == 'a1')
          .inTangent;
      d = PathOps.deleteAnchor(d2, n, a5);
      final a1In = (d.nodeIndex[n]! as PathNode)
          .path
          .anchors
          .firstWhere((a) => a.id.v == 'a1')
          .inTangent;
      _expectVec(a1In, afterInsertA1In,
          reason: 'delete leaves the neighbour tangent exactly as it found it');
    });

    test('the floor is 0 — deleting every anchor yields the legal empty path',
        () {
      var d = _squareDoc(withTrack: false);
      for (final id in const <String>['a0', 'a1', 'a2', 'a3']) {
        d = PathOps.deleteAnchor(d, n, AnchorId(id));
      }
      expect((d.nodeIndex[n]! as PathNode).path.anchors, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // 6. retopologize.
  // -------------------------------------------------------------------------
  group('retopologize (AC-4.3.7)', () {
    test('square→star rewrites every pose by arc-length; AC-4.3.6 holds', () {
      final dBefore = _twoAnimationDoc(); // keyframes pose TRANSLATED squares
      final star =
          const PolygonRecipe(sides: 5, radius: 50, star: true, innerRatio: 0.4)
              .toPath();
      expect(star.anchors, hasLength(10));

      // The old outline each keyframe drew, captured before the retopologise.
      final oldOutlines = <double, PathData>{
        for (final k
            in dBefore.defaultAnimation!.tracksFor(n).pathTrack()!.keys)
          k.t: _geomAt(dBefore, n, k.t),
      };

      final d = PathOps.retopologize(dBefore, n, star);

      // Rest topology is the star, verbatim.
      final topo = (d.nodeIndex[n]! as PathNode).path;
      expect(topo.anchors.map((a) => a.id).toList(),
          star.anchors.map((a) => a.id).toList());
      for (var i = 0; i < 10; i++) {
        _expectVec(topo.anchors[i].position, star.anchors[i].position);
      }
      assertSequenceInvariant(d, n);

      // Every keyframe now poses the 10 star ids, and each position lies on THAT
      // keyframe's own old outline (arc-length correspondence, not the rest star).
      final track = d.defaultAnimation!.tracksFor(n).pathTrack()!;
      for (final k in track.keys) {
        expect(k.value.anchors.keys.toList(),
            star.anchors.map((a) => a.id).toList());
        final old = oldOutlines[k.t]!;
        var offStar = false;
        for (final pose in k.value.anchors.values) {
          expect(_onOutline(pose.position, old), isTrue,
              reason:
                  '${pose.position} is not on the resampled old outline at t=${k.t}');
          // The morph does not just plant the rest star: the points are the
          // square's, not the star's.
          if (!star.anchors
              .any((a) => (a.position - pose.position).length < 1e-6)) {
            offStar = true;
          }
        }
        expect(offStar, isTrue,
            reason: 'positions were resampled from the old shape');
      }
    });

    test('untracked node: replaces topology, touches no animation', () {
      final d = _squareDoc(withTrack: false);
      final tri = const PolygonRecipe(sides: 3, radius: 40).toPath();
      final out = PathOps.retopologize(d, n, tri);
      expect(
          (out.nodeIndex[n]! as PathNode)
              .path
              .anchors
              .map((a) => a.id)
              .toList(),
          tri.anchors.map((a) => a.id).toList());
      // No path track existed; none was invented.
      expect(out.defaultAnimation!.tracksFor(n).pathTrack(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 7. Invalid / unknown inputs throw (zero try/catch in the op).
  // -------------------------------------------------------------------------
  group('invalid inputs throw ArgumentError', () {
    test('insertAnchor', () {
      final d = _squareDoc(withTrack: true);
      expect(
          () => PathOps.insertAnchor(d, const NodeId('nope'),
              after: const AnchorId('a0'), u: 0.5),
          throwsArgumentError);
      expect(
          () => PathOps.insertAnchor(d, const NodeId('root'),
              after: const AnchorId('a0'), u: 0.5),
          throwsArgumentError,
          reason: 'a GroupNode is not a PathNode');
      expect(
          () => PathOps.insertAnchor(d, n,
              after: const AnchorId('ghost'), u: 0.5),
          throwsArgumentError);
      for (final u in <double>[0.0, 1.0, -0.1, 1.5, double.nan]) {
        expect(
            () => PathOps.insertAnchor(d, n, after: const AnchorId('a0'), u: u),
            throwsArgumentError,
            reason: 'u=$u is outside (0,1)');
      }
    });

    test('insertAnchor on the last anchor of an OPEN path', () {
      final open = _openPathDoc();
      expect(
          () => PathOps.insertAnchor(open, n,
              after: const AnchorId('o2'), u: 0.5),
          throwsArgumentError,
          reason: 'no segment leaves the last anchor of an open path');
      // But an interior anchor of the same open path is fine.
      final (out, _) =
          PathOps.insertAnchor(open, n, after: const AnchorId('o0'), u: 0.5);
      expect((out.nodeIndex[n]! as PathNode).path.anchors, hasLength(4));
    });

    test('deleteAnchor / retopologize', () {
      final d = _squareDoc(withTrack: true);
      expect(
          () => PathOps.deleteAnchor(
              d, const NodeId('nope'), const AnchorId('a0')),
          throwsArgumentError);
      expect(() => PathOps.deleteAnchor(d, n, const AnchorId('ghost')),
          throwsArgumentError);
      final tri = const PolygonRecipe(sides: 3, radius: 10).toPath();
      expect(() => PathOps.retopologize(d, const NodeId('nope'), tri),
          throwsArgumentError);
      expect(() => PathOps.retopologize(d, const NodeId('root'), tri),
          throwsArgumentError);
    });
  });

  // -------------------------------------------------------------------------
  // 8. Continuity after a mid-animation insert (AC-4.3.4).
  // -------------------------------------------------------------------------
  group('AC-4.3.4 — continuity after a mid-animation insert', () {
    test('scrub 0→1: no NaN, no vanishing, no frozen geometry', () {
      const c0 = AnchorId('c0'), c1 = AnchorId('c1'), c2 = AnchorId('c2');
      final track = PathTrack(<Keyframe<PathPose>>[
        Keyframe<PathPose>(
            t: 0.0,
            value: PathPose(<AnchorId, AnchorPose>{
              c0: const AnchorPose(Vec2(0, 0), Vec2.zero, Vec2(40, 0)),
              c1: const AnchorPose(Vec2(100, 0), Vec2(-40, 0), Vec2(0, 40)),
              c2: const AnchorPose(Vec2(100, 100), Vec2(0, -40), Vec2.zero),
            })),
        Keyframe<PathPose>(
            t: 0.5,
            value: PathPose(<AnchorId, AnchorPose>{
              c0: const AnchorPose(Vec2(20, 30), Vec2.zero, Vec2(80, -20)),
              c1: const AnchorPose(Vec2(160, 40), Vec2(-30, -50), Vec2(30, 70)),
              c2: const AnchorPose(Vec2(70, 150), Vec2(50, -20), Vec2.zero),
            })),
        Keyframe<PathPose>(
            t: 1.0,
            value: PathPose(<AnchorId, AnchorPose>{
              c0: const AnchorPose(Vec2(-10, 10), Vec2.zero, Vec2(30, -30)),
              c1: const AnchorPose(Vec2(130, 20), Vec2(-60, -10), Vec2(10, 90)),
              c2: const AnchorPose(Vec2(90, 120), Vec2(70, 5), Vec2.zero),
            })),
      ]);
      final animation = Animation(
        id: const AnimationId('anim'),
        name: 'Main',
        tracks: <NodeId, TrackSet>{
          n: TrackSet(
              <PropertyKey, Track>{const PropertyKey(PropKey.path): track}),
        },
      );
      var d = Document(
        id: 'doc',
        name: 't',
        artboard: const Vec2(450.2, 250.4),
        root:
            GroupNode(id: const NodeId('root'), name: 'Root', children: <Node>[
          PathNode(
              id: n,
              name: 'p',
              path: PathData(anchors: const <Anchor>[
                Anchor(id: c0, position: Vec2(0, 0), outTangent: Vec2(40, 0)),
                Anchor(
                    id: c1,
                    position: Vec2(100, 0),
                    inTangent: Vec2(-40, 0),
                    outTangent: Vec2(0, 40)),
                Anchor(
                    id: c2, position: Vec2(100, 100), inTangent: Vec2(0, -40)),
              ], closed: true)),
        ]),
        animations: <Animation>[animation],
        defaultAnimationId: animation.id,
      );

      // Insert at a middle keyframe's edge.
      d = PathOps.insertAnchor(d, n, after: c0, u: 0.4).$1;
      final expectedCount = (d.nodeIndex[n]! as PathNode).path.anchors.length;

      var prev = <Vec2>[];
      final bboxes = <double>[];
      for (var i = 0; i <= 200; i++) {
        final t = i / 200.0;
        final geom = _geomAt(d, n, t);
        expect(geom.anchors, hasLength(expectedCount),
            reason: 'anchor count is constant');
        var minX = double.infinity,
            minY = double.infinity,
            maxX = -double.infinity,
            maxY = -double.infinity;
        final now = <Vec2>[];
        for (final a in geom.anchors) {
          for (final v in <double>[
            a.position.x,
            a.position.y,
            a.inTangent.x,
            a.inTangent.y,
            a.outTangent.x,
            a.outTangent.y
          ]) {
            expect(v.isNaN, isFalse, reason: 't=$t produced NaN');
            expect(v.isFinite, isTrue,
                reason: 't=$t produced a non-finite value');
          }
          now.add(a.position);
          minX = min(minX, a.position.x);
          minY = min(minY, a.position.y);
          maxX = max(maxX, a.position.x);
          maxY = max(maxY, a.position.y);
        }
        bboxes.add((maxX - minX) * (maxY - minY));
        // No pop between adjacent fine samples (continuity, §9).
        if (prev.isNotEmpty) {
          for (var j = 0; j < now.length; j++) {
            expect((now[j] - prev[j]).length, lessThan(20.0),
                reason: 't=$t jumped — a pop between adjacent samples');
          }
        }
        prev = now;
      }
      // Never collapses to a point (not frozen/vanished): every frame has area.
      for (final area in bboxes) {
        expect(area, greaterThan(100.0), reason: 'the shape must stay present');
      }
      // And it genuinely moves (not frozen): first and last frame differ.
      expect(bboxes.first, isNot(closeTo(bboxes.last, 1e-6)));
    });
  });

  // -------------------------------------------------------------------------
  // 9. insertAnchor is a pure read; anim_core has zero try/catch.
  // -------------------------------------------------------------------------
  group('purity & totality guarantees', () {
    test('insertAnchor does not mutate the input Document', () {
      final d = _twoAnimationDoc();
      final snapshot = jsonEncode(d.toJson());
      final (d2, _) =
          PathOps.insertAnchor(d, n, after: const AnchorId('a1'), u: 0.5);
      expect(jsonEncode(d.toJson()), snapshot,
          reason: 'the input document is unchanged');
      expect(jsonEncode(d2.toJson()), isNot(snapshot),
          reason: 'the result is a new document');
    });

    test('anim_core lib/src contains no try/catch', () {
      final tryRe = RegExp(r'\btry\s*\{');
      final catchRe = RegExp(r'\bcatch\s*\(');
      for (final entity in Directory('lib/src').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        expect(tryRe.hasMatch(source), isFalse,
            reason: '${entity.path} has a try block');
        expect(catchRe.hasMatch(source), isFalse,
            reason: '${entity.path} has a catch');
      }
    });
  });
}

// ===========================================================================
// The reusable AC-4.3.6 invariant checker.
// ===========================================================================

/// Every keyframe of every path track for [n], across every animation, holds
/// the **identical `AnchorId` sequence** as the node's topology, in draw order
/// (AC-4.3.6). This is the named CI invariant — a real, runnable gate.
void assertSequenceInvariant(Document d, NodeId n) {
  final node = d.nodeIndex[n]! as PathNode;
  final sequence = node.path.anchors.map((a) => a.id.v).toList();
  for (final anim in d.animations) {
    final track = anim.tracksFor(n).pathTrack();
    if (track == null) continue;
    for (final k in track.keys) {
      expect(k.value.anchors.keys.map((i) => i.v).toList(), sequence,
          reason: 'animation "${anim.id.v}" keyframe t=${k.t} must pose the '
              'topology sequence exactly');
    }
  }
}

// ===========================================================================
// Fixtures & math helpers.
// ===========================================================================

const _nodeId = NodeId('n1');

List<Anchor> _square() => const <Anchor>[
      Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
      Anchor(id: AnchorId('a1'), position: Vec2(20, 0)),
      Anchor(id: AnchorId('a2'), position: Vec2(20, 20)),
      Anchor(id: AnchorId('a3'), position: Vec2(0, 20)),
    ];

PathPose _squarePose([double dx = 0]) => PathPose(<AnchorId, AnchorPose>{
      for (final a in _square())
        a.id: AnchorPose(
            Vec2(a.position.x + dx, a.position.y), Vec2.zero, Vec2.zero),
    });

Document _squareDoc({required bool withTrack}) {
  final tracks = withTrack
      ? <NodeId, TrackSet>{
          _nodeId: TrackSet(<PropertyKey, Track>{
            const PropertyKey(PropKey.path): PathTrack(<Keyframe<PathPose>>[
              Keyframe<PathPose>(t: 0.0, value: _squarePose(0)),
              Keyframe<PathPose>(t: 0.5, value: _squarePose(5)),
              Keyframe<PathPose>(t: 1.0, value: _squarePose(0)),
            ]),
          }),
        }
      : const <NodeId, TrackSet>{};
  final animation =
      Animation(id: const AnimationId('anim'), name: 'Main', tracks: tracks);
  return Document(
    id: 'doc',
    name: 't',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: <Node>[
      PathNode(
          id: _nodeId,
          name: 'p',
          path: PathData(anchors: _square(), closed: true)),
    ]),
    animations: <Animation>[animation],
    defaultAnimationId: animation.id,
  );
}

/// A closed square with a path track in TWO animations, to prove the ops reach
/// every `Animation`.
Document _twoAnimationDoc() {
  TrackSet trackSet(double d0, double d1) => TrackSet(<PropertyKey, Track>{
        const PropertyKey(PropKey.path): PathTrack(<Keyframe<PathPose>>[
          Keyframe<PathPose>(t: 0.0, value: _squarePose(d0)),
          Keyframe<PathPose>(t: 0.5, value: _squarePose((d0 + d1) / 2)),
          Keyframe<PathPose>(t: 1.0, value: _squarePose(d1)),
        ]),
      });
  final a1 = Animation(
    id: const AnimationId('anim1'),
    name: 'One',
    tracks: <NodeId, TrackSet>{_nodeId: trackSet(0, 8)},
  );
  final a2 = Animation(
    id: const AnimationId('anim2'),
    name: 'Two',
    tracks: <NodeId, TrackSet>{_nodeId: trackSet(-4, 12)},
  );
  return Document(
    id: 'doc',
    name: 't',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: <Node>[
      PathNode(
          id: _nodeId,
          name: 'p',
          path: PathData(anchors: _square(), closed: true)),
    ]),
    animations: <Animation>[a1, a2],
    defaultAnimationId: a1.id,
  );
}

/// An OPEN 3-anchor path — its last anchor has no segment leaving it.
Document _openPathDoc() {
  final animation = Animation(id: const AnimationId('anim'), name: 'Main');
  return Document(
    id: 'doc',
    name: 't',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: <Node>[
      PathNode(
          id: _nodeId,
          name: 'p',
          path: PathData(anchors: const <Anchor>[
            Anchor(id: AnchorId('o0'), position: Vec2(0, 0)),
            Anchor(id: AnchorId('o1'), position: Vec2(50, 0)),
            Anchor(id: AnchorId('o2'), position: Vec2(100, 0)),
          ])),
    ]),
    animations: <Animation>[animation],
    defaultAnimationId: animation.id,
  );
}

/// The evaluated LOCAL geometry of [n] at time [t] — through the real pipeline.
PathData _geomAt(Document d, NodeId n, double t) {
  final scene =
      evaluate(d, <AnimationMix>[AnimationMix(d.defaultAnimation!.id, t)]);
  return scene.byPath[ScenePath(n)]!.geometry!;
}

Vec2 _cubic((Vec2, Vec2, Vec2, Vec2) seg, double u) {
  final (p0, p1, p2, p3) = seg;
  final v = 1.0 - u;
  return p0 * (v * v * v) +
      p1 * (3 * v * v * u) +
      p2 * (3 * v * u * u) +
      p3 * (u * u * u);
}

void _expectVec(Vec2 a, Vec2 b, {double tol = 1e-12, String? reason}) {
  expect(a.x, closeTo(b.x, tol), reason: reason);
  expect(a.y, closeTo(b.y, tol), reason: reason);
}

void _expectSegment((Vec2, Vec2, Vec2, Vec2) a, (Vec2, Vec2, Vec2, Vec2) b) {
  _expectVec(a.$1, b.$1, tol: 1e-12);
  _expectVec(a.$2, b.$2, tol: 1e-12);
  _expectVec(a.$3, b.$3, tol: 1e-12);
  _expectVec(a.$4, b.$4, tol: 1e-12);
}

/// True when [p] lies on the outline of [geom] — the min distance from [p] to
/// any of its (straight, for the square fixture) segment chords is ~0.
bool _onOutline(Vec2 p, PathData geom) {
  var best = double.infinity;
  for (var k = 0; k < geom.segmentCount; k++) {
    final seg = geom.segment(k);
    best = min(best, _distToSegment(p, seg.$1, seg.$4));
  }
  return best < 1e-6;
}

double _distToSegment(Vec2 p, Vec2 a, Vec2 b) {
  final abx = b.x - a.x, aby = b.y - a.y;
  final len2 = abx * abx + aby * aby;
  if (len2 == 0) return (p - a).length;
  var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2;
  t = t.clamp(0.0, 1.0);
  return (p - Vec2(a.x + abx * t, a.y + aby * t)).length;
}
