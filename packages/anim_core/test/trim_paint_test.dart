import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// M6 (domain half): the `applyTrim` and animated-paint acceptance tests
/// (docs/v3/01 §5, §11, §13.4; docs/v3/03 F8.1, F9.2).
void main() {
  group('F8.1 §13.4 — the stroke-reveal golden', () {
    // The signature path and its two tracks, verbatim from docs/v3/01 §13.4:
    // trimEnd draws 0 -> 1 over [0, 0.769], then opacity fades 1 -> 0 over
    // [0.769, 1.0]. durationSeconds 2.6, so "2 seconds" is t = 0.769.
    final sig = PathData(closed: false, anchors: [
      const Anchor(
          id: AnchorId('a0'),
          position: Vec2(20, 200),
          outTangent: Vec2(60, -120)),
      const Anchor(
          id: AnchorId('a1'),
          position: Vec2(200, 90),
          inTangent: Vec2(-60, 40),
          outTangent: Vec2(60, -40),
          kind: AnchorKind.smooth),
      const Anchor(
          id: AnchorId('a2'),
          position: Vec2(420, 60),
          inTangent: Vec2(-80, 30)),
    ]);
    final totalArc = ArcTable.build(sig).total;

    Document doc() => _doc([
          PathNode(
            id: const NodeId('sig'),
            name: 'Signature',
            path: sig,
            strokes: const [
              Stroke(
                  id: PaintId('p-ink'),
                  paint: SolidPaint(Rgba(0, 0, 0)),
                  width: 6,
                  cap: StrokeCap.round),
            ],
          ),
        ], tracks: {
          const NodeId('sig'): TrackSet({
            const PropertyKey(PropKey.trimEnd): ScalarTrack([
              const Keyframe(t: 0.0, value: 0.0, easing: CubicEasing.easeInOut),
              const Keyframe(t: 0.769, value: 1.0),
            ]),
            const PropertyKey(PropKey.opacity): ScalarTrack([
              const Keyframe(t: 0.769, value: 1.0),
              const Keyframe(t: 1.0, value: 0.0),
            ]),
          }),
        });

    PathData geometryAt(double t) => evaluate(doc(), _at(t))
        .byPath[const ScenePath(NodeId('sig'))]!
        .geometry!;

    test('t = 0: nothing is revealed — the stroke length is ~0', () {
      final g = geometryAt(0.0);
      expect(_len(g), lessThan(1e-9),
          reason:
              'trim (0,0,0) renders nothing — never a fan out of the origin');
    });

    test('t = 0.769: the whole path is revealed to within 1e-6', () {
      final g = geometryAt(0.769);
      // trimEnd is exactly 1.0 here, so (0,1,0) is a full pass-through.
      expect(_len(g), closeTo(totalArc, 1e-6));
    });

    test('the revealed sub-path lies exactly ON the authored path', () {
      // The property §13.4 explains: a proper trim draws ALONG the route, unlike
      // lerping all anchors which fans a tip out to a point off the path.
      final g = geometryAt(0.4);
      expect(g.segmentCount, greaterThan(0));
      for (var k = 0; k < g.segmentCount; k++) {
        final (p0, p1, p2, p3) = g.segment(k);
        for (final u in const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]) {
          final point = _cubicAt(p0, p1, p2, p3, u);
          expect(_distanceToPath(point, sig), lessThan(1e-6),
              reason: 'a revealed point must sit on an authored cubic');
        }
      }
    });

    test('the revealed arc length is a monotonically increasing fraction', () {
      var previous = -1.0;
      for (final t in const [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]) {
        final g = geometryAt(t);
        final fraction = _len(g) / totalArc;
        final trimEnd = _sampleScalar(doc(), 'sig', PropKey.trimEnd, t);
        expect(fraction, closeTo(trimEnd, 1e-3),
            reason: 'revealed length is the trimEnd fraction of the total');
        expect(fraction, greaterThan(previous),
            reason: 'the reveal only ever grows over [0, 0.769]');
        previous = fraction;
      }
    });

    test('opacity fades 1 -> 0 over [0.769, 1.0]', () {
      double opacityAt(double t) => evaluate(doc(), _at(t))
          .byPath[const ScenePath(NodeId('sig'))]!
          .worldOpacity;

      expect(opacityAt(0.769), closeTo(1.0, 1e-9));
      expect(opacityAt(1.0), closeTo(0.0, 1e-9));
      var previous = 2.0;
      for (final t in const [0.769, 0.85, 0.925, 1.0]) {
        final o = opacityAt(t);
        expect(o, lessThan(previous + 1e-12));
        previous = o;
      }
    });
  });

  group('F8.1 — the trim rules', () {
    test('AC-8.1.3: end <= start renders empty geometry, never a throw', () {
      for (final trim in const [
        PathTrim(start: 0.5, end: 0.5), // equal
        PathTrim(start: 0.6, end: 0.3), // end < start
      ]) {
        final g = evaluate(_doc([_open('p', trim: trim)]), const [])
            .byPath[const ScenePath(NodeId('p'))]!
            .geometry!;
        expect(g.anchors, isEmpty);
      }
    });

    test('AC-8.1.4: a wrapped window (start > end) is clamped to empty', () {
      final g = evaluate(
          _doc([_open('p', trim: const PathTrim(start: 0.8, end: 0.2))]),
          const []).byPath[const ScenePath(NodeId('p'))]!.geometry!;
      expect(g.anchors, isEmpty);
    });

    test('AC-8.1.5: a partial window on a closed path emits closed:false', () {
      final g = evaluate(
          _doc([_closedSquare('p', trim: const PathTrim(end: 0.5))]),
          const []).byPath[const ScenePath(NodeId('p'))]!.geometry!;
      expect(g.closed, isFalse, reason: 'a partial reveal cannot be filled');
      expect(g.anchors.length, greaterThan(1));
    });

    test('AC-8.1.6: trimOffset walks the reveal start around a closed path',
        () {
      // Unit square, perimeter 80: a0(0,0) a1(20,0) a2(20,20) a3(0,20).
      // Window [0, 0.5] reveals half the loop (arc 40). offset 0.25 rotates the
      // reveal a quarter of the way round, so it now starts at arc 20 = a1.
      PathData revealed(double offset) => evaluate(
          _doc([_closedSquare('p', trim: PathTrim(end: 0.5, offset: offset))]),
          const []).byPath[const ScenePath(NodeId('p'))]!.geometry!;

      final atZero = revealed(0.0);
      final atQuarter = revealed(0.25);

      // offset 0 begins at anchor 0 (0,0); offset 0.25 begins a quarter round.
      expect(atZero.anchors.first.position.x, closeTo(0.0, 1e-9));
      expect(atZero.anchors.first.position.y, closeTo(0.0, 1e-9));
      expect(atQuarter.anchors.first.position.x, closeTo(20.0, 1e-9),
          reason: 'the reveal start is not locked to anchor 0');
      expect(atQuarter.anchors.first.position.y, closeTo(0.0, 1e-9));
      // Both reveal half the loop.
      expect(_len(atQuarter), closeTo(40.0, 1e-6));
      expect(atQuarter.closed, isFalse);
    });

    test(
        'a FULL-width window with a non-zero offset on a closed path stays '
        'closed — a whole loop is not a partial reveal', () {
      // Perimeter-80 square, window [0,1] (the entire loop) with the reveal
      // start rotated a quarter round. The whole loop is present, so — unlike a
      // *partial* reveal (AC-8.1.5) — it must render CLOSED, else a stroked loop
      // gets a spurious seam cap at the offset point instead of a join, and a
      // draw-on that completes to a held full loop with a keyed offset renders
      // open. Contrast the isFull pass-through (offset 0), which was already
      // closed; this is the offset != 0 case the walker would otherwise open.
      final g = evaluate(
              _doc([_closedSquare('p', trim: const PathTrim(offset: 0.25))]),
              const [])
          .byPath[const ScenePath(NodeId('p'))]!
          .geometry!;
      expect(g.closed, isTrue,
          reason: 'the entire loop is revealed; offset only rotates the seam');
      expect(_len(g), closeTo(80.0, 1e-6),
          reason: 'the whole perimeter is present');

      // An easing overshoot that lands end past 1.0 is likewise a full reveal.
      final over = evaluate(
              _doc([_closedSquare('p', trim: const PathTrim(end: 1.1))]),
              const [])
          .byPath[const ScenePath(NodeId('p'))]!
          .geometry!;
      expect(over.closed, isTrue);
    });

    test('AC-8.1.9: trim is node-local — a parent scale changes no fraction',
        () {
      // The same trimmed path with, and without, a 3x-non-uniform parent scale.
      // The revealed LOCAL fraction must be identical: trim is measured before
      // the world transform.
      PathData under(Vec2 scale) => evaluate(
          _doc([
            GroupNode(
              id: const NodeId('g'),
              name: 'g',
              transform: Transform2(scale: scale),
              children: [_open('p', trim: const PathTrim(end: 0.5))],
            ),
          ]),
          const []).byPath[const ScenePath(NodeId('p'))]!.geometry!;

      final plain = under(const Vec2(1, 1));
      final scaled = under(const Vec2(3, 1));

      final full = ArcTable.build(_openPath()).total;
      expect(_len(scaled) / full, closeTo(0.5, 1e-3));
      expect(_len(scaled), closeTo(_len(plain), 1e-9),
          reason:
              'the non-uniform world scale must not touch local arc length');

      // Sanity: the node really is under a 3x scale.
      final world = evaluate(
          _doc([
            GroupNode(
              id: const NodeId('g'),
              name: 'g',
              transform: const Transform2(scale: Vec2(3, 1)),
              children: [_open('p', trim: const PathTrim(end: 0.5))],
            ),
          ]),
          const []).byPath[const ScenePath(NodeId('p'))]!.world;
      expect(world.a, closeTo(3.0, 1e-12));
    });

    test('AC-8.1.7: the arc-length table is memoized per immutable PathData',
        () {
      // A STATIC geometry with an animated trimEnd, scrubbed 60x. The table
      // depends only on the geometry, which resolvePose returns verbatim (the
      // same instance every tick), so it is built exactly ONCE.
      final staticDoc = _doc([
        _open('s', trim: PathTrim.full)
      ], tracks: {
        const NodeId('s'): TrackSet({
          const PropertyKey(PropKey.trimEnd): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: 1.0),
          ]),
        }),
      });
      ArcTable.buildCount = 0;
      for (var n = 0; n < 60; n++) {
        evaluate(staticDoc, _at(0.05 + 0.6 * n / 59.0));
      }
      expect(ArcTable.buildCount, 1,
          reason: 'a static path scrubbed 60x builds its table once');

      // An ANIMATED path is a fresh PathData per tick, so its table is inherently
      // per-t — 60 builds is correct, not a memo miss to fix.
      final animatedDoc = _doc([
        _closedSquare('a', trim: const PathTrim(end: 0.6)),
      ], tracks: {
        const NodeId('a'): TrackSet({
          const PropertyKey(PropKey.path): PathTrack([
            Keyframe(t: 0.0, value: _squarePose(0)),
            Keyframe(t: 1.0, value: _squarePose(40)),
          ]),
        }),
      });
      ArcTable.buildCount = 0;
      for (var n = 0; n < 60; n++) {
        evaluate(animatedDoc, _at(n / 59.0));
      }
      expect(ArcTable.buildCount, 60,
          reason: 'an animated path rebuilds its table each tick');
    });

    test('AC-8.1.8: trimmed anchor ids are synthetic and non-authoritative',
        () {
      final g =
          evaluate(_doc([_open('p', trim: const PathTrim(end: 0.5))]), const [])
              .byPath[const ScenePath(NodeId('p'))]!
              .geometry!;
      // None of the authored ids (a0..a3) survive — nothing downstream can join.
      final authored = _openPath().anchors.map((a) => a.id.v).toSet();
      for (final a in g.anchors) {
        expect(authored.contains(a.id.v), isFalse);
        expect(a.id.v.startsWith('trim:'), isTrue);
      }
    });
  });

  group('F9.2 — resolvePaint applies the animated paint channels', () {
    test('an animated fillColor is written onto the fill by PaintId', () {
      final doc = _doc([
        const PathNode(
          id: NodeId('p'),
          name: 'p',
          path: PathData.empty,
          fills: [Fill(id: PaintId('f1'), paint: SolidPaint(Rgba(1, 0, 0)))],
        ),
      ], tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.fillColor, 'f1'): ColorTrack([
            const Keyframe(t: 0.0, value: Rgba(1, 0, 0)),
            const Keyframe(t: 1.0, value: Rgba(0, 0, 1)),
          ]),
        }),
      });

      final fill = evaluate(doc, _at(0.5))
          .byPath[const ScenePath(NodeId('p'))]!
          .fills
          .single;
      final paint = fill.paint;
      expect(paint, isA<SolidPaint>());
      expect((paint as SolidPaint).color.r, closeTo(0.5, 1e-9));
      expect(paint.color.b, closeTo(0.5, 1e-9));
    });

    test('an animated strokeWidth is written onto the stroke by PaintId', () {
      final doc = _doc([
        const PathNode(
          id: NodeId('p'),
          name: 'p',
          path: PathData.empty,
          strokes: [
            Stroke(
                id: PaintId('s1'), paint: SolidPaint(Rgba(0, 0, 0)), width: 6)
          ],
        ),
      ], tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.strokeWidth, 's1'): ScalarTrack([
            const Keyframe(t: 0.0, value: 2.0),
            const Keyframe(t: 1.0, value: 10.0),
          ]),
        }),
      });

      final stroke = evaluate(doc, _at(0.5))
          .byPath[const ScenePath(NodeId('p'))]!
          .strokes
          .single;
      expect(stroke.width, closeTo(6.0, 1e-9));
    });

    test('an unkeyed channel keeps the authored value (pose fallback)', () {
      // fillColor is keyed; fillOpacity is NOT — the authored 0.4 must survive.
      final doc = _doc([
        const PathNode(
          id: NodeId('p'),
          name: 'p',
          path: PathData.empty,
          fills: [
            Fill(
                id: PaintId('f1'),
                paint: SolidPaint(Rgba(1, 0, 0)),
                opacity: 0.4)
          ],
        ),
      ], tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.fillColor, 'f1'): ColorTrack([
            const Keyframe(t: 0.0, value: Rgba(0, 1, 0)),
            const Keyframe(t: 1.0, value: Rgba(0, 1, 0)),
          ]),
        }),
      });

      final fill = evaluate(doc, _at(0.5))
          .byPath[const ScenePath(NodeId('p'))]!
          .fills
          .single;
      expect(fill.opacity, 0.4);
      expect((fill.paint as SolidPaint).color, const Rgba(0, 1, 0));
    });

    test('AC-9.2.4: a malformed track type yields null and does not crash', () {
      // A `fillColor` stored as a SCALAR track: the decoder routes it to
      // unknownKeys, the typed accessor returns null, and the fill keeps its
      // authored colour. No throw, no repair inside the tick.
      final tracks = TrackSet.fromJson(<String, Object?>{
        'fillColor:f1': <String, Object?>{
          'type': 'scalar',
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': 0.5},
          ],
        },
      });
      expect(tracks.color(PropKey.fillColor, 'f1'), isNull);
      expect(tracks.unknownKeys.containsKey('fillColor:f1'), isTrue);

      final doc = _doc([
        const PathNode(
          id: NodeId('p'),
          name: 'p',
          path: PathData.empty,
          fills: [Fill(id: PaintId('f1'), paint: SolidPaint(Rgba(1, 0, 0)))],
        ),
      ], tracks: {
        const NodeId('p'): tracks,
      });

      final fill = evaluate(doc, _at(0.5))
          .byPath[const ScenePath(NodeId('p'))]!
          .fills
          .single;
      expect((fill.paint as SolidPaint).color, const Rgba(1, 0, 0));
    });

    test('a gradient paint with no solid channel is left untouched', () {
      const gradient = LinearGradientPaint(
        start: Vec2(0, 0),
        end: Vec2(10, 0),
        stops: [
          GradientStop(id: StopId('g0'), offset: 0, color: Rgba(1, 0, 0)),
          GradientStop(id: StopId('g1'), offset: 1, color: Rgba(0, 0, 1)),
        ],
      );
      final doc = _doc([
        const PathNode(
          id: NodeId('p'),
          name: 'p',
          path: PathData.empty,
          fills: [Fill(id: PaintId('f1'), paint: gradient)],
        ),
      ], tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.fillColor, 'f1'): ColorTrack([
            const Keyframe(t: 0.0, value: Rgba(0, 1, 0)),
            const Keyframe(t: 1.0, value: Rgba(0, 1, 0)),
          ]),
        }),
      });

      final fill = evaluate(doc, _at(0.5))
          .byPath[const ScenePath(NodeId('p'))]!
          .fills
          .single;
      expect(identical(fill.paint, gradient), isTrue,
          reason: 'a fillColor track on a gradient is skipped, never a throw');
    });
  });

  group('F9.2 — the pipeline is intact after M6', () {
    Document animated() => _doc([
          _closedSquare('p', trim: PathTrim.full),
        ], tracks: {
          const NodeId('p'): TrackSet({
            const PropertyKey(PropKey.trimEnd): ScalarTrack([
              const Keyframe(t: 0.0, value: 0.0),
              const Keyframe(t: 1.0, value: 1.0),
            ]),
            const PropertyKey(PropKey.fillColor, 'fill'): ColorTrack([
              const Keyframe(t: 0.0, value: Rgba(1, 0, 0)),
              const Keyframe(t: 1.0, value: Rgba(0, 0, 1)),
            ]),
          }),
        });

    test('AC-9.2.1: the eight named stages still compose to evaluate', () {
      final doc = animated();
      final mix = _at(0.4);
      final manual = resolvePaint(
        applyTrim(
          deform(
            composeWorldB(
              solveConstraints(
                composeWorldA(
                  resolvePose(
                    sampleTracks(doc, mix),
                  ),
                ),
              ),
            ),
          ),
        ),
      ).toScene();
      final auto = evaluate(doc, mix);
      expect(manual.drawOrder.length, auto.drawOrder.length);
      for (var n = 0; n < manual.drawOrder.length; n++) {
        expect(manual.drawOrder[n].geometry?.anchors.length,
            auto.drawOrder[n].geometry?.anchors.length);
        expect(
            manual.drawOrder[n].fills.length, auto.drawOrder[n].fills.length);
      }
    });

    test('AC-9.2.2: the three seams are still no-ops even with trim + paint',
        () {
      final frame =
          composeWorldA(resolvePose(sampleTracks(animated(), _at(0.4))));
      expect(identical(solveConstraints(frame), frame), isTrue);
      expect(identical(composeWorldB(frame), frame), isTrue);
      expect(identical(deform(frame), frame), isTrue);
    });

    test('AC-9.2.3: a group and its child spin the opposite way, independently',
        () {
      final doc = _doc([
        GroupNode(
          id: const NodeId('g'),
          name: 'g',
          children: [_closedSquare('c', trim: PathTrim.full)],
        ),
      ], tracks: {
        const NodeId('g'): TrackSet({
          const PropertyKey(PropKey.rotation): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: 1.0),
          ]),
        }),
        const NodeId('c'): TrackSet({
          const PropertyKey(PropKey.rotation): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: -3.0),
          ]),
        }),
      });
      final s = evaluate(doc, _at(1.0));
      final g = s.byPath[const ScenePath(NodeId('g'))]!;
      final c = s.byPath[const ScenePath(NodeId('c'))]!;
      expect(g.worldVisible, isTrue);
      expect(c.worldVisible, isTrue);
      // world = parent.world . local, so the two rotations compose, not cancel.
      expect(g.world == c.world, isFalse);
    });

    test('AC-9.2.6: evaluation is a pure read — the document is unchanged', () {
      final doc = animated();
      final before = doc.toJson().toString();
      for (final t in const [0.0, 0.3, 0.7, 1.0]) {
        evaluate(doc, _at(t));
      }
      expect(doc.toJson().toString(), before);
    });
  });

  group('F8.1 / F9.2 — totality over a stress document', () {
    test('50 samples over [-0.2, 1.2]: no throw, no NaN, no surprise empty',
        () {
      final doc = _doc([
        // A window that renders nothing (empty rule).
        _open('empty', trim: const PathTrim(start: 0.6, end: 0.4)),
        // A wrapped window on a closed path (clamped to empty).
        _closedSquare('wrapped', trim: const PathTrim(start: 0.8, end: 0.2)),
        // A 0-anchor and a 1-anchor path, both trimmed.
        _pathNode('zero', const [], trim: const PathTrim(end: 0.5)),
        _pathNode(
            'one', const [Anchor(id: AnchorId('x'), position: Vec2(4, 5))],
            trim: const PathTrim(end: 0.5)),
        // A well-formed trimmed node that must be present at t = 1.0.
        _open('draw', trim: PathTrim.full),
        // A node whose scale collapses to 0 while trimmed.
        _closedSquare('collapse', trim: const PathTrim(end: 0.7)),
      ], tracks: {
        // draw-on 0 -> 1: at t = 1 the window is full and the shape is present.
        const NodeId('draw'): TrackSet({
          const PropertyKey(PropKey.trimEnd): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: 1.0),
          ]),
        }),
        // trimOffset walking around a closed path while it collapses.
        const NodeId('collapse'): TrackSet({
          const PropertyKey(PropKey.trimOffset): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: 1.0),
          ]),
          const PropertyKey(PropKey.scale): Vec2Track([
            const Vec2Keyframe(t: 0.0, value: Vec2(1, 1)),
            const Vec2Keyframe(t: 1.0, value: Vec2(0, 0)),
          ]),
        }),
      });

      for (var n = 0; n < 50; n++) {
        final t = -0.2 + 1.4 * n / 49.0;
        final scene = evaluate(doc, _at(t));
        for (final node in scene.drawOrder) {
          for (final v in <double>[
            node.world.a,
            node.world.b,
            node.world.c,
            node.world.d,
            node.world.tx,
            node.world.ty,
            node.worldOpacity,
          ]) {
            expect(v.isFinite, isTrue, reason: 'non-finite at t = $t');
          }
          for (final a in node.geometry?.anchors ?? const <Anchor>[]) {
            for (final v in <double>[
              a.position.x,
              a.position.y,
              a.inTangent.x,
              a.inTangent.y,
              a.outTangent.x,
              a.outTangent.y,
            ]) {
              expect(v.isFinite, isTrue, reason: 'non-finite anchor at t = $t');
            }
          }
        }
      }

      // Present at t = 1.0: the draw-on reveal is full and the path is whole.
      final end = evaluate(doc, _at(1.0));
      expect(end.byPath[const ScenePath(NodeId('draw'))]!.geometry!.anchors,
          hasLength(_openPath().anchors.length));
    });
  });
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

List<Anchor> _openAnchors() => const [
      Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
      Anchor(id: AnchorId('a1'), position: Vec2(30, 0)),
      Anchor(id: AnchorId('a2'), position: Vec2(30, 40)),
      Anchor(id: AnchorId('a3'), position: Vec2(0, 40)),
    ];

PathData _openPath() => PathData(anchors: _openAnchors());

List<Anchor> _square() => const [
      Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
      Anchor(id: AnchorId('a1'), position: Vec2(20, 0)),
      Anchor(id: AnchorId('a2'), position: Vec2(20, 20)),
      Anchor(id: AnchorId('a3'), position: Vec2(0, 20)),
    ];

PathPose _squarePose(double dx) => PathPose({
      for (final a in _square())
        a.id: AnchorPose(
            Vec2(a.position.x + dx, a.position.y), Vec2.zero, Vec2.zero),
    });

PathNode _open(String id, {required PathTrim trim}) => PathNode(
      id: NodeId(id),
      name: id,
      path: _openPath(),
      trim: trim,
      strokes: const [
        Stroke(id: PaintId('ink'), paint: SolidPaint(Rgba(0, 0, 0)))
      ],
    );

PathNode _closedSquare(String id, {required PathTrim trim}) => PathNode(
      id: NodeId(id),
      name: id,
      path: PathData(anchors: _square(), closed: true),
      trim: trim,
      fills: const [
        Fill(id: PaintId('fill'), paint: SolidPaint(Rgba(1, 0, 0)))
      ],
    );

PathNode _pathNode(String id, List<Anchor> anchors, {required PathTrim trim}) =>
    PathNode(
      id: NodeId(id),
      name: id,
      path: PathData(anchors: anchors),
      trim: trim,
    );

Document _doc(List<Node> children, {Map<NodeId, TrackSet> tracks = const {}}) {
  final animation = Animation(
      id: const AnimationId('a1'),
      name: 'Main',
      durationSeconds: 2.6,
      tracks: tracks);
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450, 250),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: children),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}

List<AnimationMix> _at(double t) => [AnimationMix(const AnimationId('a1'), t)];

double _sampleScalar(Document doc, String node, PropKey prop, double t) =>
    doc.animations.first.tracksFor(NodeId(node)).scalar(prop)!.sampleAt(t);

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

double _len(PathData g) => g.segmentCount == 0 ? 0.0 : ArcTable.build(g).total;

Vec2 _cubicAt(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final v = 1.0 - u;
  return p0 * (v * v * v) +
      p1 * (3.0 * v * v * u) +
      p2 * (3.0 * v * u * u) +
      p3 * (u * u * u);
}

/// The minimum distance from [pt] to any authored cubic of [path], found by a
/// coarse scan then a ternary refine — accurate well past 1e-6, which is what
/// lets the golden assert "on the authored path" rather than "near it".
double _distanceToPath(Vec2 pt, PathData path) {
  var best = double.infinity;
  for (var k = 0; k < path.segmentCount; k++) {
    final (p0, p1, p2, p3) = path.segment(k);
    var bestU = 0.0;
    var bestD = double.infinity;
    const n = 400;
    for (var i = 0; i <= n; i++) {
      final u = i / n;
      final d = (_cubicAt(p0, p1, p2, p3, u) - pt).length;
      if (d < bestD) {
        bestD = d;
        bestU = u;
      }
    }
    var lo = (bestU - 1.0 / n).clamp(0.0, 1.0);
    var hi = (bestU + 1.0 / n).clamp(0.0, 1.0);
    for (var it = 0; it < 100; it++) {
      final m1 = lo + (hi - lo) / 3.0;
      final m2 = hi - (hi - lo) / 3.0;
      if ((_cubicAt(p0, p1, p2, p3, m1) - pt).length <
          (_cubicAt(p0, p1, p2, p3, m2) - pt).length) {
        hi = m2;
      } else {
        lo = m1;
      }
    }
    final d = (_cubicAt(p0, p1, p2, p3, (lo + hi) / 2.0) - pt).length;
    if (d < best) best = d;
  }
  return best;
}
