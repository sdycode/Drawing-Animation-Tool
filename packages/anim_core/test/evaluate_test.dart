import 'dart:math' as math;

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The evaluator's acceptance tests (docs/v3/03 F6.1, F9.2; docs/v3/01 §9, §11).
void main() {
  group('pipeline shape (AC-9.2.1, AC-9.2.2)', () {
    test('the eight stages exist by name and run in that exact order', () {
      final doc = _doc([
        _path('p',
            anchors: _square(),
            transform: const Transform2(position: Vec2(3, 4))),
      ], tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            Vec2Keyframe(t: 0.0, value: const Vec2(0, 0)),
            Vec2Keyframe(t: 1.0, value: const Vec2(100, 50)),
          ]),
        }),
      });
      final mix = _at(0.37);

      // Applying the named stages by hand, in the order AC-9.2.1 fixes, must
      // reproduce `evaluate` exactly. If a stage were inlined into the walk,
      // or reordered, this sequence could not be written at all.
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

      _expectSameScene(manual, evaluate(doc, mix));
    });

    test('stages 4, 5 and 6 are no-op seams, not missing', () {
      final frame = composeWorldA(
          resolvePose(sampleTracks(_doc([_path('p')]), _at(0.5))));
      expect(identical(solveConstraints(frame), frame), isTrue);
      expect(identical(composeWorldB(frame), frame), isTrue);
      expect(identical(deform(frame), frame), isTrue);
    });

    test('applyTrim is a pass-through at M0 and leaves geometry untouched', () {
      final frame = composeWorldA(
          resolvePose(sampleTracks(_doc([_path('p')]), _at(0.5))));
      expect(identical(applyTrim(frame), frame), isTrue);
    });

    test('resolvePaint attaches the authored fills and strokes', () {
      const fill = Fill(id: PaintId('f1'), paint: SolidPaint(Rgba(1, 0, 0)));
      final doc = _doc([
        _path('p', fills: const [fill])
      ]);
      expect(
          evaluate(doc, const []).byPath[const ScenePath(NodeId('p'))]!.fills,
          hasLength(1));
      // Stage 3 deliberately leaves them empty — there is exactly one place
      // that decides what a node is painted with.
      final beforePaint =
          composeWorldA(resolvePose(sampleTracks(doc, const [])));
      expect(beforePaint.nodes.every((n) => n.fills.isEmpty), isTrue);
    });

    test('evaluation does not modify the document (AC-9.2.6)', () {
      final doc = _doc([_path('p', anchors: _square())]);
      final before = doc.toJson().toString();
      evaluate(doc, _at(0.5));
      expect(doc.toJson().toString(), before);
    });
  });

  group('the empty mix is the rest pose', () {
    test('evaluate(doc, const []) returns every authored value verbatim', () {
      const pose =
          Transform2(position: Vec2(12, -7), rotation: 0.4, scale: Vec2(2, 3));
      final doc = _doc([
        _path('p', anchors: _square(), transform: pose, opacity: 0.5),
      ], tracks: {
        // Tracks exist and are deliberately ignored: an empty mix samples
        // nothing.
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            Vec2Keyframe(t: 0.0, value: const Vec2(999, 999)),
          ]),
        }),
      });

      final node =
          evaluate(doc, const []).byPath[const ScenePath(NodeId('p'))]!;
      _expectAffine(node.world, pose.toAffine());
      expect(node.worldOpacity, closeTo(0.5, 1e-12));
      expect(node.worldVisible, isTrue);
      expect(node.geometry!.anchors.map((a) => a.position).toList(),
          _square().map((a) => a.position).toList());
    });
  });

  group('F6.1 — per-node, per-property tracks', () {
    test('AC-6.1.1: nodes on unrelated key grids animate independently', () {
      final doc = _doc([
        _path('a'),
        _path('b'),
      ], tracks: {
        const NodeId('a'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            Vec2Keyframe(t: 0.0, value: const Vec2(0, 0)),
            Vec2Keyframe(t: 0.5, value: const Vec2(50, 0)),
            Vec2Keyframe(t: 1.0, value: const Vec2(0, 0)),
          ]),
        }),
        const NodeId('b'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            Vec2Keyframe(t: 0.13, value: const Vec2(0, 0)),
            Vec2Keyframe(t: 0.77, value: const Vec2(64, 0)),
          ]),
        }),
      });

      // t = 0.13 is a key of b and nothing at all to a.
      final s = evaluate(doc, _at(0.13));
      expect(_worldTx(s, 'a').x, closeTo(13.0, 1e-9)); // 0.26 of the way to 50
      expect(_worldTx(s, 'b').x, closeTo(0.0, 1e-9)); // its own first key

      // t = 0.5 is a key of a and mid-segment for b.
      final s2 = evaluate(doc, _at(0.5));
      expect(_worldTx(s2, 'a').x, closeTo(50.0, 1e-9));
      expect(_worldTx(s2, 'b').x, closeTo(64.0 * (0.37 / 0.64), 1e-9));
    });

    test('AC-6.1.2: an unkeyed property holds its Transform2 pose value', () {
      const pose = Transform2(position: Vec2(1, 1), rotation: 0.9, skewX: 0.2);
      final doc = _doc([
        _path('p', transform: pose),
      ], tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            Vec2Keyframe(t: 0.0, value: const Vec2(0, 0)),
            Vec2Keyframe(t: 1.0, value: const Vec2(80, 0)),
          ]),
        }),
      });

      final world =
          evaluate(doc, _at(0.25)).byPath[const ScenePath(NodeId('p'))]!.world;
      _expectAffine(
          world, pose.copyWith(position: const Vec2(20, 0)).toAffine());
    });

    test('AC-6.1.4: a node absent from Animation.tracks is fully static', () {
      const pose = Transform2(position: Vec2(5, 6), rotation: 1.0);
      final doc = _doc([
        _path('keyed'),
        _path('static', transform: pose),
      ], tracks: {
        const NodeId('keyed'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            Vec2Keyframe(t: 0.0, value: const Vec2(0, 0)),
            Vec2Keyframe(t: 1.0, value: const Vec2(80, 0)),
          ]),
        }),
      });

      for (final t in [0.0, 0.31, 0.5, 1.0]) {
        final n =
            evaluate(doc, _at(t)).byPath[const ScenePath(NodeId('static'))]!;
        _expectAffine(n.world, pose.toAffine());
      }
    });

    test('AC-6.1.5: all four keyed nodes animate — no cache keyed by selection',
        () {
      final ids = ['n0', 'n1', 'n2', 'n3'];
      final doc = _doc([
        for (final id in ids) _path(id),
      ], tracks: {
        for (var k = 0; k < ids.length; k++)
          NodeId(ids[k]): TrackSet({
            const PropertyKey(PropKey.position): Vec2Track([
              Vec2Keyframe(t: 0.0, value: const Vec2(0, 0)),
              Vec2Keyframe(t: 1.0, value: Vec2(10.0 * (k + 1), 0)),
            ]),
          }),
      });

      final s = evaluate(doc, _at(0.5));
      for (var k = 0; k < ids.length; k++) {
        expect(_worldTx(s, ids[k]).x, closeTo(5.0 * (k + 1), 1e-9),
            reason: '${ids[k]} must animate whether or not it is selected');
      }
    });
  });

  group('F9.2 — composition', () {
    test('AC-9.2.3: a group and its child rotate independently and both show',
        () {
      final doc = _doc([
        GroupNode(
          id: const NodeId('g'),
          name: 'g',
          children: [_path('c', anchors: _square())],
        ),
      ], tracks: {
        const NodeId('g'): TrackSet({
          const PropertyKey(PropKey.rotation): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: math.pi / 2),
          ]),
        }),
        const NodeId('c'): TrackSet({
          const PropertyKey(PropKey.rotation): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: -3 * math.pi / 2),
          ]),
        }),
      });

      final s = evaluate(doc, _at(1.0));
      final g = s.byPath[const ScenePath(NodeId('g'))]!;
      final c = s.byPath[const ScenePath(NodeId('c'))]!;

      expect(g.worldVisible, isTrue);
      expect(c.worldVisible, isTrue);
      // world = parent.world · local, so the child's world rotation is the sum.
      _expectAffine(g.world, Affine.rotate(math.pi / 2));
      _expectAffine(c.world, Affine.rotate(math.pi / 2 - 3 * math.pi / 2));
      expect(c.world == g.world, isFalse);
    });

    test('AC-9.2.4: a malformed track type yields null and does not throw', () {
      // A `rotation` holding a vec2 track. The decoder routes it to unknownKeys
      // untouched; the typed accessor returns null; the node falls back to its
      // pose value. No throw, no dialog, nothing repaired inside the tick.
      final tracks = TrackSet.fromJson(<String, Object?>{
        'rotation': <String, Object?>{
          'type': 'vec2',
          'keys': <Object?>[
            <String, Object?>{
              't': 0.0,
              'value': <String, Object?>{'x': 3.0, 'y': 4.0},
            },
          ],
        },
      });
      expect(tracks.scalar(PropKey.rotation), isNull);
      expect(tracks.unknownKeys.containsKey('rotation'), isTrue);

      const pose = Transform2(rotation: 0.25);
      final doc = _doc([_path('p', transform: pose)],
          tracks: {const NodeId('p'): tracks});

      final world =
          evaluate(doc, _at(0.5)).byPath[const ScenePath(NodeId('p'))]!.world;
      _expectAffine(world, pose.toAffine());
    });

    test('AC-9.2.5: one entry at weight 1.0 equals the single-animation result',
        () {
      final doc = _doc([
        _path('p', anchors: _square()),
      ], tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            Vec2Keyframe(t: 0.0, value: const Vec2(0, 0)),
            Vec2Keyframe(t: 1.0, value: const Vec2(30, 40)),
          ]),
        }),
      });

      final one = evaluate(doc, [const AnimationMix(AnimationId('a1'), 0.5)]);
      expect(_worldTx(one, 'p'), const Vec2(15, 20));
    });

    test(
        'a mix entry lacking the track contributes the POSE value at that '
        'weight, never zero', () {
      // Two animations at half weight each. Only the first keys `position`; the
      // second must contribute the node's pose (100, 0) at 0.5, not 0.
      const pose = Transform2(position: Vec2(100, 0));
      final keyed = Animation(
        id: const AnimationId('a1'),
        name: 'keyed',
        tracks: {
          const NodeId('p'): TrackSet({
            const PropertyKey(PropKey.position): Vec2Track([
              Vec2Keyframe(t: 0.0, value: const Vec2(0, 0)),
              Vec2Keyframe(t: 1.0, value: const Vec2(0, 0)),
            ]),
          }),
        },
      );
      const bare = Animation(id: AnimationId('a2'), name: 'bare');
      final doc = Document(
        id: 'd',
        name: 'mix',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(
          id: const NodeId('root'),
          name: 'Root',
          children: [_path('p', transform: pose)],
        ),
        animations: [keyed, bare],
        defaultAnimationId: keyed.id,
      );

      final s = evaluate(doc, const [
        AnimationMix(AnimationId('a1'), 0.5, weight: 0.5),
        AnimationMix(AnimationId('a2'), 0.5, weight: 0.5),
      ]);
      expect(_worldTx(s, 'p').x, closeTo(50.0, 1e-9));
    });
  });

  group('the one insight — id join, never an index join', () {
    test('pose map ORDER is irrelevant to interpolation', () {
      final topology = PathData(anchors: [
        _anchor('A', 0, 0),
        _anchor('B', 10, 0),
        _anchor('C', 10, 10),
      ]);

      PathTrack track(bool reversedSecondKey) {
        final second = <AnchorId, AnchorPose>{};
        final entries = <(String, double, double)>[
          ('A', 100, 0),
          ('B', 110, 0),
          ('C', 110, 10),
        ];
        for (final e in reversedSecondKey ? entries.reversed : entries) {
          second[AnchorId(e.$1)] =
              AnchorPose(Vec2(e.$2, e.$3), Vec2.zero, Vec2.zero);
        }
        return PathTrack([
          Keyframe(t: 0.0, value: _poseOf(topology)),
          Keyframe(t: 1.0, value: PathPose(second)),
        ]);
      }

      List<Vec2> sample(PathTrack t) {
        final (k0, k1, u) = t.bracket(0.5);
        return resolveNodePose(
                topology, [PathBracket(k0.value, k1.value, u, 1.0)])
            .anchors
            .map((a) => a.position)
            .toList();
      }

      expect(sample(track(false)), sample(track(true)));
      expect(
          sample(track(true)), const [Vec2(50, 0), Vec2(60, 0), Vec2(60, 10)]);
    });

    test('a pose missing an id falls back to that anchor\'s REST value', () {
      final topology = PathData(anchors: [
        _anchor('A', 0, 0),
        _anchor('B', 10, 0),
        _anchor('C', 10, 10),
      ]);
      // The t = 1 key poses A and C but not B.
      final partial = PathPose({
        const AnchorId('A'):
            const AnchorPose(Vec2(100, 0), Vec2.zero, Vec2.zero),
        const AnchorId('C'):
            const AnchorPose(Vec2(110, 10), Vec2.zero, Vec2.zero),
      });
      final track = PathTrack([
        Keyframe(t: 0.0, value: _poseOf(topology)),
        Keyframe(t: 1.0, value: partial),
      ]);

      final (k0, k1, u) = track.bracket(0.5);
      final posed =
          resolveNodePose(topology, [PathBracket(k0.value, k1.value, u, 1.0)]);

      expect(posed.anchors, hasLength(3));
      expect(posed.anchors[0].position, const Vec2(50, 0));
      // B is rest at both ends, so it does not move — an index join would have
      // paired B with C's pose and dragged it.
      expect(posed.anchors[1].position, const Vec2(10, 0));
      expect(posed.anchors[2].position, const Vec2(60, 10));
      expect(posed.anchors.map((a) => a.id.v).toList(), ['A', 'B', 'C']);
    });

    test('closed comes from topology and is never interpolated', () {
      final topology = PathData(anchors: _square(), closed: true);
      final track = PathTrack([
        Keyframe(t: 0.0, value: _poseOf(topology)),
        Keyframe(t: 1.0, value: _poseOf(topology)),
      ]);
      final (k0, k1, u) = track.bracket(0.5);
      expect(
          resolveNodePose(topology, [PathBracket(k0.value, k1.value, u, 1.0)])
              .closed,
          isTrue);
    });
  });

  group('hierarchy', () {
    test(
        'a hidden group ANDs down, opacity multiplies down, locked never reads',
        () {
      final doc = _doc([
        GroupNode(
          id: const NodeId('g'),
          name: 'g',
          visible: false,
          opacity: 0.5,
          locked: true,
          children: [
            _path('c', anchors: _square(), opacity: 0.5, visible: true),
          ],
        ),
        // A locked but visible node must render exactly like an unlocked one.
        _path('locked', anchors: _square(), locked: true, opacity: 0.25),
      ]);

      final s = evaluate(doc, const []);
      expect(s.byPath[const ScenePath(NodeId('g'))]!.worldVisible, isFalse);
      expect(s.byPath[const ScenePath(NodeId('c'))]!.worldVisible, isFalse,
          reason: 'a hidden group hides every descendant');
      expect(s.byPath[const ScenePath(NodeId('c'))]!.worldOpacity,
          closeTo(0.25, 1e-12));

      final locked = s.byPath[const ScenePath(NodeId('locked'))]!;
      expect(locked.worldVisible, isTrue);
      expect(locked.worldOpacity, closeTo(0.25, 1e-12));
      expect(locked.geometry!.anchors, hasLength(4));
    });

    test('a back-eased opacity is clamped 0..1 at READ, per node', () {
      // docs/v3/01 §7 spells out `opacity ... clamped 0..1 at read`, and the
      // reason is this exact interaction: `easing.dart` deliberately leaves
      // cubic y unclamped so authored anticipation/overshoot survives, so a
      // legal back-in curve samples NEGATIVE. Two negatives multiply POSITIVE
      // in composeWorldA, so a group and its child both undershooting produce a
      // small positive worldOpacity with worldVisible true — the painter's
      // `!(worldOpacity > 0)` guard passes and the subtree is painted faintly
      // during a window in which it should be fully transparent.
      ScalarTrack fade(Easing easing) => ScalarTrack([
            Keyframe<double>(t: 0.0, value: 0.0, easing: easing),
            const Keyframe<double>(t: 1.0, value: 1.0),
          ]);

      // The test bites only if the raw sample really does leave the range.
      expect(fade(CubicEasing.backIn).sampleAt(0.2), lessThan(0.0));

      final doc = _doc([
        GroupNode(
          id: const NodeId('g'),
          name: 'g',
          children: [_path('n', anchors: _square())],
        ),
      ], tracks: {
        const NodeId('g'): TrackSet(
            {const PropertyKey(PropKey.opacity): fade(CubicEasing.backIn)}),
        const NodeId('n'): TrackSet(
            {const PropertyKey(PropKey.opacity): fade(CubicEasing.backIn)}),
      });

      for (final t in <double>[0.1, 0.2, 0.3, 0.4]) {
        final s = evaluate(doc, _at(t));
        expect(s.byPath[const ScenePath(NodeId('g'))]!.worldOpacity, 0.0,
            reason: 'undershoot clamps to fully transparent at t = $t');
        expect(s.byPath[const ScenePath(NodeId('n'))]!.worldOpacity, 0.0,
            reason: 'and two negatives never multiply back into visible');
      }
    });

    test('an overshooting opacity is clamped to 1, not left above it', () {
      // The other half of the range. A worldOpacity above 1 is invisible on
      // screen (`toUiColor` clamps) but reaches every future exporter reading
      // the Scene, and it is not what the document says.
      final over = ScalarTrack([
        const Keyframe<double>(t: 0.0, value: 1.0, easing: CubicEasing.backIn),
        const Keyframe<double>(t: 1.0, value: 0.0),
      ]);
      // A back-in curve UNDERSHOOTS in y, so a track counting DOWN from 1
      // overshoots in value — the same authored curve, the other end of the
      // range.
      expect(over.sampleAt(0.2), greaterThan(1.0));

      final doc = _doc([
        _path('n', anchors: _square()),
      ], tracks: {
        const NodeId('n'): TrackSet({const PropertyKey(PropKey.opacity): over}),
      });

      expect(
          evaluate(doc, _at(0.15))
              .byPath[const ScenePath(NodeId('n'))]!
              .worldOpacity,
          1.0);
    });

    test('a singular world matrix renders nothing and never throws', () {
      final doc = _doc([
        _path('p', anchors: _square()),
      ], tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.scale): Vec2Track([
            Vec2Keyframe(t: 0.0, value: const Vec2(1, 1)),
            Vec2Keyframe(t: 1.0, value: const Vec2(0, 0)),
          ]),
        }),
      });

      final n = evaluate(doc, _at(1.0)).byPath[const ScenePath(NodeId('p'))]!;
      expect(n.world.invert(), isNull);
      expect(n.worldVisible, isFalse);
    });

    test('drawOrder is a back-to-front pre-order flattening', () {
      final doc = _doc([
        GroupNode(
          id: const NodeId('g'),
          name: 'g',
          children: [_path('c0'), _path('c1')],
        ),
        _path('top'),
      ]);
      expect(
          evaluate(doc, const [])
              .drawOrder
              .map((n) => n.path.nodeId.v)
              .toList(),
          ['root', 'g', 'c0', 'c1', 'top']);
    });
  });

  group('totality and continuity', () {
    test('200 samples over [-0.5, 1.5] produce no throw and no NaN', () {
      final one = _anchor('only', 4, 5);
      final doc = _doc([
        _path('single', anchors: [one]),
        _path('degenerate', anchors: const []),
        _path('collapsing', anchors: _square()),
        _path('coincident', anchors: _square()),
      ], tracks: {
        const NodeId('single'): TrackSet({
          const PropertyKey(PropKey.path): PathTrack([
            Keyframe(
                t: 0.0,
                value: PathPose({
                  const AnchorId('only'):
                      const AnchorPose(Vec2(4, 5), Vec2.zero, Vec2.zero),
                })),
            Keyframe(
                t: 1.0,
                value: PathPose({
                  const AnchorId('only'):
                      const AnchorPose(Vec2(40, 50), Vec2.zero, Vec2.zero),
                })),
          ]),
        }),
        const NodeId('collapsing'): TrackSet({
          const PropertyKey(PropKey.scale): Vec2Track([
            Vec2Keyframe(t: 0.0, value: const Vec2(1, 1)),
            Vec2Keyframe(t: 0.6, value: const Vec2(0, 0)),
            Vec2Keyframe(t: 1.0, value: const Vec2(1, 1)),
          ]),
        }),
        // Two keys 1e-10 apart: legal under T2, and the zero-span rule is what
        // keeps the divide out of the NaN business.
        const NodeId('coincident'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            Vec2Keyframe(t: 0.5, value: const Vec2(0, 0)),
            Vec2Keyframe(t: 0.5 + 1e-10, value: const Vec2(9, 9)),
          ]),
        }),
      });

      for (var n = 0; n < 200; n++) {
        final t = -0.5 + 2.0 * n / 199.0;
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
              expect(v.isFinite, isTrue, reason: 'non-finite at t = $t');
            }
          }
        }
      }

      // HOLD LAST: the shape must still be there at the end of the timeline.
      // Legacy's `if (frames.length > preFrameNo + 1)` made it vanish.
      final end = evaluate(doc, _at(1.0));
      expect(
          end.byPath[const ScenePath(NodeId('coincident'))]!.geometry!.anchors,
          hasLength(4));
      expect(end.byPath[const ScenePath(NodeId('single'))]!.geometry!.anchors,
          hasLength(1));
      expect(
          end.byPath[const ScenePath(NodeId('degenerate'))]!.geometry!.anchors,
          isEmpty);
    });

    test('continuity: sampling either side of a key matches the key', () {
      final anchors = _square();
      final track = PathTrack([
        Keyframe(t: 0.0, value: _poseAt(anchors, 0)),
        Keyframe(
            t: 0.3, value: _poseAt(anchors, 40), easing: CubicEasing.easeInOut),
        Keyframe(t: 0.85, value: _poseAt(anchors, -25)),
      ]);
      final doc = _doc([
        _path('p', anchors: anchors),
      ], tracks: {
        const NodeId('p'): TrackSet({const PropertyKey(PropKey.path): track}),
      });

      List<Vec2> at(double t) => evaluate(doc, _at(t))
          .byPath[const ScenePath(NodeId('p'))]!
          .geometry!
          .anchors
          .map((a) => a.position)
          .toList();

      for (var n = 0; n < track.keys.length - 1; n++) {
        final k0 = track.keys[n];
        final k1 = track.keys[n + 1];
        _expectClose(
            at(k0.t + 1e-6),
            at(k0.t),
            'a shape that collapses on the first frame after ${k0.t} is total '
            'and completely wrong');
        _expectClose(at(k1.t - 1e-6), at(k1.t),
            'the segment must arrive at ${k1.t}, not near it');
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

Anchor _anchor(String id, double x, double y) =>
    Anchor(id: AnchorId(id), position: Vec2(x, y));

List<Anchor> _square() => [
      _anchor('a0', 0, 0),
      _anchor('a1', 20, 0),
      _anchor('a2', 20, 20),
      _anchor('a3', 0, 20),
    ];

PathData _pathOf(List<Anchor> anchors) => PathData(anchors: anchors);

PathPose _poseOf(PathData p) => PathPose({
      for (final a in p.anchors)
        a.id: AnchorPose(a.position, a.inTangent, a.outTangent),
    });

PathPose _poseAt(List<Anchor> anchors, double dx) => PathPose({
      for (final a in anchors)
        a.id: AnchorPose(
            Vec2(a.position.x + dx, a.position.y), Vec2.zero, Vec2.zero),
    });

PathNode _path(
  String id, {
  List<Anchor> anchors = const [],
  Transform2 transform = Transform2.identity,
  double opacity = 1.0,
  bool visible = true,
  bool locked = false,
  List<Fill> fills = const [],
}) =>
    PathNode(
      id: NodeId(id),
      name: id,
      path: _pathOf(anchors),
      transform: transform,
      opacity: opacity,
      visible: visible,
      locked: locked,
      fills: fills,
    );

Document _doc(List<Node> children, {Map<NodeId, TrackSet> tracks = const {}}) {
  final animation =
      Animation(id: const AnimationId('a1'), name: 'Main', tracks: tracks);
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: children),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}

List<AnimationMix> _at(double t) => [AnimationMix(const AnimationId('a1'), t)];

Vec2 _worldTx(Scene s, String id) {
  final w = s.byPath[ScenePath(NodeId(id))]!.world;
  return Vec2(w.tx, w.ty);
}

// ---------------------------------------------------------------------------
// Matchers
// ---------------------------------------------------------------------------

void _expectAffine(Affine actual, Affine expected) {
  expect(actual.a, closeTo(expected.a, 1e-9));
  expect(actual.b, closeTo(expected.b, 1e-9));
  expect(actual.c, closeTo(expected.c, 1e-9));
  expect(actual.d, closeTo(expected.d, 1e-9));
  expect(actual.tx, closeTo(expected.tx, 1e-9));
  expect(actual.ty, closeTo(expected.ty, 1e-9));
}

void _expectClose(List<Vec2> actual, List<Vec2> expected, String reason) {
  expect(actual, hasLength(expected.length), reason: reason);
  for (var n = 0; n < actual.length; n++) {
    expect(actual[n].x, closeTo(expected[n].x, 1e-3), reason: reason);
    expect(actual[n].y, closeTo(expected[n].y, 1e-3), reason: reason);
  }
}

void _expectSameScene(Scene actual, Scene expected) {
  expect(actual.drawOrder, hasLength(expected.drawOrder.length));
  for (var n = 0; n < actual.drawOrder.length; n++) {
    final x = actual.drawOrder[n];
    final y = expected.drawOrder[n];
    expect(x.path, y.path);
    _expectAffine(x.world, y.world);
    expect(x.worldOpacity, closeTo(y.worldOpacity, 1e-12));
    expect(x.worldVisible, y.worldVisible);
    expect(x.fills.length, y.fills.length);
    expect(x.strokes.length, y.strokes.length);
    expect(x.geometry?.anchors.map((a) => a.position).toList(),
        y.geometry?.anchors.map((a) => a.position).toList());
  }
}
