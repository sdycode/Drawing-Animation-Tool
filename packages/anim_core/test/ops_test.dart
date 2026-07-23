import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The M0 mutation API (docs/v3/01 §12; docs/v3/03 AC-6.2.7).
void main() {
  group('TrackOps.upsertKeyframe', () {
    test('replaces at an existing t and never produces a second key there', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 0.5, value: 10.0),
        const Keyframe(t: 1.0, value: 20.0),
      ]);

      final next =
          TrackOps.upsertKeyframe(track, const Keyframe(t: 0.5, value: 99.0));

      expect(next, isA<ScalarTrack>());
      expect(next.keyCount, 3);
      expect(next.keys.where((k) => k.t == 0.5), hasLength(1));
      expect(next.sampleAt(0.5), 99.0);
    });

    test('inserts in order when nothing is near t', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 1.0, value: 20.0),
      ]);
      final next =
          TrackOps.upsertKeyframe(track, const Keyframe(t: 0.25, value: 7.0));

      expect(next.keys.map((k) => k.t).toList(), [0.0, 0.25, 1.0]);
      expect(next.sampleAt(0.25), 7.0);
    });

    test('a key landing within minSeparation collapses onto one key', () {
      final track = ScalarTrack([
        const Keyframe(t: 0.2, value: 1.0),
        const Keyframe(t: 0.5, value: 2.0),
      ]);
      final next = TrackOps.upsertKeyframe(
          track, Keyframe(t: 0.5 + TrackOps.minSeparation / 2, value: 3.0));

      // Coincident keys are impossible BY CONSTRUCTION: the near-miss replaces
      // rather than adding a neighbour the sampler would have to divide by.
      expect(next.keyCount, 2);
      expect(next.keys[1].value, 3.0);
      for (var n = 1; n < next.keys.length; n++) {
        expect(next.keys[n].t - next.keys[n - 1].t,
            greaterThan(TrackOps.minSeparation));
      }
    });

    test('preserves the concrete track type without a cast', () {
      final track = PathTrack([
        Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
      ]);
      final next = TrackOps.upsertKeyframe(
          track, Keyframe(t: 1.0, value: _poseOf(_square(), 10)));
      expect(next, isA<PathTrack>());
      expect(next.keyCount, 2);
    });

    test('a t outside [0,1] throws — ops throw loudly', () {
      final track = ScalarTrack([const Keyframe(t: 0.0, value: 0.0)]);
      expect(
          () => TrackOps.upsertKeyframe(
              track, const Keyframe(t: 1.5, value: 0.0)),
          throwsArgumentError);
      expect(
          () => TrackOps.upsertKeyframe(
              track, Keyframe(t: double.nan, value: 0.0)),
          throwsArgumentError);
    });
  });

  group('PathOps.moveAnchor — rest pose (atT == null)', () {
    test('edits the node PathData and touches no track', () {
      final d = _doc();
      final out = PathOps.moveAnchor(
          d, const NodeId('p'), const AnchorId('a1'), const Vec2(77, 88));

      final node = out.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.path.anchors[1].position, const Vec2(77, 88));
      expect(
          out.defaultAnimation!.tracksFor(const NodeId('p')).isEmpty, isTrue);
      // The input is untouched: no model object is mutable.
      expect(
          (d.nodeIndex[const NodeId('p')]! as PathNode)
              .path
              .anchors[1]
              .position,
          const Vec2(20, 0));
    });

    test('an unknown node or anchor throws ArgumentError', () {
      final d = _doc();
      expect(
          () => PathOps.moveAnchor(
              d, const NodeId('nope'), const AnchorId('a1'), Vec2.zero),
          throwsArgumentError);
      expect(
          () => PathOps.moveAnchor(
              d, const NodeId('root'), const AnchorId('a1'), Vec2.zero),
          throwsArgumentError,
          reason: 'a group is not a path node');
      expect(
          () => PathOps.moveAnchor(
              d, const NodeId('p'), const AnchorId('ghost'), Vec2.zero),
          throwsArgumentError);
    });
  });

  group('PathOps.moveAnchor — keyframe-local (atT != null)', () {
    test('the first drag creates the track AND seeds t = 0, giving two keys',
        () {
      final out = PathOps.moveAnchor(
          _doc(), const NodeId('p'), const AnchorId('a1'), const Vec2(50, 60),
          atT: 0.5);

      final track =
          out.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;
      expect(track.keyCount, 2);
      expect(track.keys[0].t, 0.0);
      expect(track.keys[1].t, 0.5);

      // The two keys DIFFER — that is the whole point of the seed.
      expect(track.keys[0].value.anchors[const AnchorId('a1')]!.position,
          const Vec2(20, 0));
      expect(track.keys[1].value.anchors[const AnchorId('a1')]!.position,
          const Vec2(50, 60));

      // And the node's rest pose is untouched: a pose edit is keyframe-local.
      final node = out.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.path.anchors[1].position, const Vec2(20, 0));
    });

    test('a drag at t = 0.0 replaces the seed rather than duplicating it', () {
      final out = PathOps.moveAnchor(
          _doc(), const NodeId('p'), const AnchorId('a1'), const Vec2(5, 5),
          atT: 0.0);
      final track =
          out.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;
      expect(track.keyCount, 1);
      expect(track.keys[0].value.anchors[const AnchorId('a1')]!.position,
          const Vec2(5, 5));
    });

    test('a second drag at another t leaves the other anchors where they were',
        () {
      var d = PathOps.moveAnchor(
          _doc(), const NodeId('p'), const AnchorId('a1'), const Vec2(50, 60),
          atT: 1.0);
      d = PathOps.moveAnchor(
          d, const NodeId('p'), const AnchorId('a2'), const Vec2(-4, -4),
          atT: 1.0);

      final track =
          d.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;
      expect(track.keyCount, 2);
      final last = track.keys.last.value.anchors;
      expect(last[const AnchorId('a1')]!.position, const Vec2(50, 60));
      expect(last[const AnchorId('a2')]!.position, const Vec2(-4, -4));
    });

    test('the animation is created when the document has none', () {
      final bare = Document(
        id: 'doc',
        name: 'bare',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(
          id: const NodeId('root'),
          name: 'Root',
          children: [_node()],
        ),
      );
      expect(bare.defaultAnimation, isNull);

      final out = PathOps.moveAnchor(
          bare, const NodeId('p'), const AnchorId('a0'), const Vec2(1, 2),
          atT: 0.75);

      expect(out.animations, hasLength(1));
      expect(out.defaultAnimation, isNotNull);
      expect(out.defaultAnimationId, out.animations.single.id);
      expect(
          out.defaultAnimation!
              .tracksFor(const NodeId('p'))
              .pathTrack()!
              .keyCount,
          2);
    });

    test('a pose edit at an existing key does not retime it', () {
      // docs/v3/01 §1 rule 1: a pose edit is keyframe-LOCAL, and easing is not
      // part of a pose (§8 — it belongs to the key it leaves). `Keyframe`'s
      // model default is linear, so an upsert that builds the replacement key
      // without carrying the displaced easing across silently straightens the
      // whole segment leaving t, with no warning and nothing to undo.
      final d = _docWith(PathTrack([
        Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
        Keyframe(
            t: 0.5,
            value: _poseOf(_square(), 10),
            easing: CubicEasing.easeInOut),
      ]));

      final out = PathOps.moveAnchor(
          d, const NodeId('p'), const AnchorId('a2'), const Vec2(3, 4),
          atT: 0.5);
      final track =
          out.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;

      expect(track.keys.map((k) => k.easing).toList(),
          <Easing>[const LinearEasing(), CubicEasing.easeInOut]);
      // The edit itself still landed — this is not passing by doing nothing.
      expect(track.keys.last.value.anchors[const AnchorId('a2')]!.position,
          const Vec2(3, 4));
    });

    test('the easing carried across is the one the upsert displaces', () {
      // A near miss inside `minSeparation` is a replace, so it is that key's
      // easing that must survive — resolved by the same rule the upsert uses,
      // never by a second copy of it at the call site.
      final d = _docWith(PathTrack([
        Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
        Keyframe(
            t: 0.5, value: _poseOf(_square(), 10), easing: CubicEasing.backIn),
      ]));

      final out = PathOps.moveAnchor(
          d, const NodeId('p'), const AnchorId('a2'), const Vec2(3, 4),
          atT: 0.5 + TrackOps.minSeparation / 2);
      final track =
          out.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;

      expect(track.keyCount, 2);
      expect(track.keys.last.easing, CubicEasing.backIn);
    });

    test('a key authored where none existed is linear, not inherited', () {
      final d = _docWith(PathTrack([
        Keyframe(
            t: 0.0, value: _poseOf(_square(), 0), easing: CubicEasing.backIn),
      ]));

      final out = PathOps.moveAnchor(
          d, const NodeId('p'), const AnchorId('a2'), const Vec2(3, 4),
          atT: 0.9);
      final track =
          out.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;

      expect(track.keys.map((k) => k.easing).toList(),
          <Easing>[CubicEasing.backIn, const LinearEasing()],
          reason: 'the untouched key keeps its curve; the new key is the '
              'identity, because a non-identity model default silently curves '
              'every programmatically created key');
    });

    test('an atT outside [0,1] throws', () {
      expect(
          () => PathOps.moveAnchor(
              _doc(), const NodeId('p'), const AnchorId('a0'), Vec2.zero,
              atT: 1.5),
          throwsArgumentError);
    });

    test(
        'after N pose edits at any t, EVERY keyframe of the path track holds '
        'the identical AnchorId SEQUENCE as the node topology', () {
      var d = _doc();
      final ids = ['a0', 'a1', 'a2', 'a3'];
      final times = [0.5, 0.2, 0.9, 0.5, 0.05, 1.0, 0.2, 0.61];

      for (var n = 0; n < times.length; n++) {
        d = PathOps.moveAnchor(
          d,
          const NodeId('p'),
          AnchorId(ids[n % ids.length]),
          Vec2(n.toDouble(), -n.toDouble()),
          atT: times[n],
        );
      }

      final node = d.nodeIndex[const NodeId('p')]! as PathNode;
      final topology = node.path.anchors.map((a) => a.id.v).toList();
      final track =
          d.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;

      expect(track.keyCount, greaterThan(1));
      for (final k in track.keys) {
        expect(k.value.anchors.keys.map((i) => i.v).toList(), topology,
            reason: 'keyframe at t = ${k.t} drifted from the topology');
      }
      // And T2 still holds after every insert-or-replace.
      for (var n = 1; n < track.keys.length; n++) {
        expect(track.keys[n].t, greaterThan(track.keys[n - 1].t));
      }
    });

    test('an existing keyframe with a partial pose is backfilled, not broken',
        () {
      // A decoded document may legitimately hold a pose missing an id; the
      // evaluator reads that as "rest", so backfilling it with rest is
      // render-identical and makes the commit invariant green.
      final partial = PathTrack([
        Keyframe(
            t: 0.0,
            value: PathPose({
              const AnchorId('a0'):
                  const AnchorPose(Vec2(0, 0), Vec2.zero, Vec2.zero),
            })),
      ]);
      final animation = Animation(
        id: const AnimationId('a1'),
        name: 'Main',
        tracks: {
          const NodeId('p'): TrackSet({
            const PropertyKey(PropKey.path): partial,
          }),
        },
      );
      final d = Document(
        id: 'doc',
        name: 'partial',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(
            id: const NodeId('root'), name: 'Root', children: [_node()]),
        animations: [animation],
        defaultAnimationId: animation.id,
      );

      final out = PathOps.moveAnchor(
          d, const NodeId('p'), const AnchorId('a3'), const Vec2(9, 9),
          atT: 0.4);
      final track =
          out.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;

      for (final k in track.keys) {
        expect(k.value.anchors.keys.map((i) => i.v).toList(),
            ['a0', 'a1', 'a2', 'a3']);
      }
      // The backfilled t = 0 key still renders exactly as it did.
      expect(track.keys[0].value.anchors[const AnchorId('a2')]!.position,
          const Vec2(20, 20));
    });
  });

  group('PathOps.setTangents — rest pose (atT == null)', () {
    test('writes the handles onto the node and touches no track', () {
      final out = PathOps.setTangents(
          _doc(), const NodeId('p'), const AnchorId('a1'),
          inT: const Vec2(-5, 0), outT: const Vec2(5, 0));

      final node = out.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.path.anchors[1].inTangent, const Vec2(-5, 0));
      expect(node.path.anchors[1].outTangent, const Vec2(5, 0));
      expect(out.defaultAnimation!.tracksFor(const NodeId('p')).isEmpty, isTrue,
          reason: 'AC-4.2.3: no track is silently created');
    });

    test('the AnchorId sequence is untouched (AC-4.2.2)', () {
      final before = _doc();
      final out = PathOps.setTangents(
          before, const NodeId('p'), const AnchorId('a2'),
          outT: const Vec2(3, 3), kind: AnchorKind.symmetric);

      List<String> ids(Document d) =>
          (d.nodeIndex[const NodeId('p')]! as PathNode)
              .path
              .anchors
              .map((a) => a.id.v)
              .toList();
      expect(ids(out), ids(before));
      expect(ids(out), ['a0', 'a1', 'a2', 'a3']);
    });

    test('a manual handle edit NULLS the recipe (docs/v3/01 §5 authority)', () {
      final d = _docOf(_recipeNode());
      expect((d.nodeIndex[const NodeId('p')]! as PathNode).recipe, isNotNull);

      final out = PathOps.setTangents(
          d, const NodeId('p'), const AnchorId('a1'),
          outT: const Vec2(4, 0));
      expect((out.nodeIndex[const NodeId('p')]! as PathNode).recipe, isNull,
          reason: 'a hand-curved corner is no longer regenerable from w and h');
    });

    test('a call supplying nothing is a no-op and keeps the recipe', () {
      final d = _docOf(_recipeNode());
      final out =
          PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'));
      expect(identical(out, d), isTrue);
      expect((out.nodeIndex[const NodeId('p')]! as PathNode).recipe, isNotNull);
    });

    test(
        'unknown node, group node, unknown anchor and a non-finite handle all '
        'throw', () {
      final d = _doc();
      expect(
          () => PathOps.setTangents(
              d, const NodeId('nope'), const AnchorId('a1'),
              outT: Vec2.zero),
          throwsArgumentError);
      expect(
          () => PathOps.setTangents(
              d, const NodeId('root'), const AnchorId('a1'),
              outT: Vec2.zero),
          throwsArgumentError,
          reason: 'a group is not a path node');
      expect(
          () => PathOps.setTangents(
              d, const NodeId('p'), const AnchorId('ghost'),
              outT: Vec2.zero),
          throwsArgumentError);
      expect(
          () => PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'),
              outT: const Vec2(double.nan, 0)),
          throwsArgumentError);
      expect(
          () => PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'),
              inT: const Vec2(0, double.infinity)),
          throwsArgumentError);
      expect(
          () => PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'),
              outT: Vec2.zero, atT: 1.5),
          throwsArgumentError);
    });
  });

  group('AnchorKind is baked into the STORED tangents (AC-4.1.3)', () {
    Anchor edited(Document d) =>
        (d.nodeIndex[const NodeId('p')]! as PathNode).path.anchors[1];

    test('corner zeroes both handles', () {
      var d = PathOps.setTangents(
          _doc(), const NodeId('p'), const AnchorId('a1'),
          inT: const Vec2(-9, -2),
          outT: const Vec2(9, 2),
          kind: AnchorKind.symmetric);
      d = PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'),
          kind: AnchorKind.corner);

      expect(edited(d).kind, AnchorKind.corner);
      expect(edited(d).inTangent, Vec2.zero);
      expect(edited(d).outTangent, Vec2.zero,
          reason: 'the segment must render straight, as the degenerate cubic');
    });

    test('smooth keeps the follower length and re-aims it opposite the driver',
        () {
      // in is 10 long pointing left; dragging `out` up must leave `in` 10 long
      // pointing down, not mirror its length.
      var d = PathOps.setTangents(
          _doc(), const NodeId('p'), const AnchorId('a1'),
          inT: const Vec2(-10, 0), kind: AnchorKind.smooth);
      d = PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'),
          outT: const Vec2(0, 4));

      final a = edited(d);
      expect(a.kind, AnchorKind.smooth);
      expect(a.outTangent, const Vec2(0, 4));
      expect(a.inTangent.x, closeTo(0, 1e-12));
      expect(a.inTangent.y, closeTo(-10, 1e-12));
      // Collinear and opposed, independent lengths.
      expect(_cross(a.inTangent, a.outTangent), closeTo(0, 1e-12));
      expect(_dot(a.inTangent, a.outTangent), lessThan(0));
      expect(a.inTangent.length, isNot(closeTo(a.outTangent.length, 1e-9)));
    });

    test('symmetric stores the exact negation, whichever handle drives', () {
      var d = PathOps.setTangents(
          _doc(), const NodeId('p'), const AnchorId('a1'),
          inT: const Vec2(-10, 0),
          outT: const Vec2(1, 7),
          kind: AnchorKind.symmetric);
      // Both supplied: `out` drives, `in` is corrected — not stored verbatim.
      expect(edited(d).outTangent, const Vec2(1, 7));
      expect(edited(d).inTangent, const Vec2(-1, -7));

      d = PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'),
          inT: const Vec2(2, 2));
      expect(edited(d).inTangent, const Vec2(2, 2));
      expect(edited(d).outTangent, const Vec2(-2, -2));
    });

    test('a bare kind change re-aims the handles it finds', () {
      var d = PathOps.setTangents(
          _doc(), const NodeId('p'), const AnchorId('a1'),
          inT: const Vec2(-3, 1), outT: const Vec2(6, 6));
      // Stored as authored while the anchor is a corner-kind free-for-all…
      expect(edited(d).inTangent, const Vec2(-3, 1));

      // …and reconciled the moment the anchor claims to be symmetric.
      d = PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'),
          kind: AnchorKind.symmetric);
      expect(edited(d).outTangent, const Vec2(6, 6));
      expect(edited(d).inTangent, const Vec2(-6, -6));
    });

    test(
        'a zero-length driver leaves both handles zero rather than inventing '
        'an angle', () {
      final d = PathOps.setTangents(
          _doc(), const NodeId('p'), const AnchorId('a1'),
          outT: Vec2.zero, inT: const Vec2(-5, 0), kind: AnchorKind.smooth);
      expect(edited(d).outTangent, Vec2.zero);
      expect(edited(d).inTangent, Vec2.zero);
    });
  });

  group('PathOps.setTangents — keyframe-local (atT != null)', () {
    test(
        'only that keyframe changes; the others stay byte-identical '
        '(AC-4.2.1/2)', () {
      final d = _docWith(PathTrack([
        Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
        Keyframe(t: 0.5, value: _poseOf(_square(), 10)),
        Keyframe(t: 1.0, value: _poseOf(_square(), 20)),
      ]));
      final before =
          d.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;

      final out = PathOps.setTangents(
          d, const NodeId('p'), const AnchorId('a2'),
          outT: const Vec2(0, 6), kind: AnchorKind.symmetric, atT: 0.5);
      final track =
          out.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;

      expect(track.keyCount, 3);
      for (final t in const [0.0, 1.0]) {
        final a = before.keys.firstWhere((k) => k.t == t).value.anchors;
        final b = track.keys.firstWhere((k) => k.t == t).value.anchors;
        expect(b.length, a.length);
        for (final id in a.keys) {
          expect(b[id]!.position, a[id]!.position);
          expect(b[id]!.inTangent, a[id]!.inTangent);
          expect(b[id]!.outTangent, a[id]!.outTangent);
        }
      }

      final keyed = track.keys[1].value.anchors[const AnchorId('a2')]!;
      expect(keyed.outTangent, const Vec2(0, 6));
      expect(keyed.inTangent, const Vec2(0, -6));
      expect(keyed.position, const Vec2(30, 20),
          reason: 'the pose at t is preserved; only the handles moved');
    });

    test('every keyframe still holds the identical AnchorId SEQUENCE', () {
      var d = _docWith(PathTrack([
        Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
        Keyframe(t: 1.0, value: _poseOf(_square(), 20)),
      ]));
      for (final t in const [0.5, 0.25, 0.9, 0.5]) {
        d = PathOps.setTangents(d, const NodeId('p'), const AnchorId('a1'),
            outT: Vec2(t * 10, 0), kind: AnchorKind.symmetric, atT: t);
      }

      final node = d.nodeIndex[const NodeId('p')]! as PathNode;
      final topology = node.path.anchors.map((a) => a.id.v).toList();
      final track =
          d.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;
      for (final k in track.keys) {
        expect(k.value.anchors.keys.map((i) => i.v).toList(), topology);
      }
    });

    test(
        'kind lands on the topology document-wide; the handle correction stays '
        'keyframe-local', () {
      final d = _docWith(PathTrack([
        Keyframe(
            t: 0.0,
            value: PathPose({
              for (final a in _square())
                a.id:
                    AnchorPose(a.position, const Vec2(-7, 0), const Vec2(7, 0))
            })),
        Keyframe(t: 1.0, value: _poseOf(_square(), 20)),
      ]));

      final out = PathOps.setTangents(
          d, const NodeId('p'), const AnchorId('a1'),
          kind: AnchorKind.corner, atT: 1.0);

      // Document-wide: the hint is not animatable and has nowhere else to live.
      final node = out.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.path.anchors[1].kind, AnchorKind.corner);
      // Keyframe-local: t = 0 keeps the handles its author gave it. Retro-
      // actively zeroing them would deform a keyframe nobody was looking at.
      final track =
          out.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;
      expect(track.keys[0].value.anchors[const AnchorId('a1')]!.outTangent,
          const Vec2(7, 0));
      expect(track.keys[1].value.anchors[const AnchorId('a1')]!.outTangent,
          Vec2.zero);
    });

    test('the node rest pose keeps its tangents, and the recipe is nulled', () {
      final d = _docOf(
        _recipeNode(),
        PathTrack([
          Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
          Keyframe(t: 1.0, value: _poseOf(_square(), 20)),
        ]),
      );

      final out = PathOps.setTangents(
          d, const NodeId('p'), const AnchorId('a1'),
          outT: const Vec2(0, 9), atT: 1.0);

      final node = out.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.path.anchors[1].outTangent, Vec2.zero,
          reason: 'a pose edit is keyframe-local');
      expect(node.recipe, isNull);
    });
  });

  group('PathOps.regenerateRecipe', () {
    test('an untracked node is replaced cleanly and stores the recipe', () {
      final out = PathOps.regenerateRecipe(
          _doc(), const NodeId('p'), const EllipseRecipe(rx: 30, ry: 20));

      final node = out.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.recipe, const EllipseRecipe(rx: 30, ry: 20));
      expect(node.path.anchors, hasLength(4));
      expect(node.path.closed, isTrue);
      expect(node.path.anchors[0].outTangent, const Vec2(0, 20 * kKappa));
      // Fresh ids: none of the square's four survive.
      expect(
          node.path.anchors
              .map((a) => a.id.v)
              .toSet()
              .intersection({'a0', 'a1', 'a2', 'a3'}),
          isEmpty);
    });

    test('regenerating twice in a row is legal and re-mints every id', () {
      var d = PathOps.regenerateRecipe(
          _doc(), const NodeId('p'), const PolygonRecipe(sides: 5, radius: 50));
      final first = (d.nodeIndex[const NodeId('p')]! as PathNode)
          .path
          .anchors
          .map((a) => a.id.v)
          .toSet();

      d = PathOps.regenerateRecipe(
          d,
          const NodeId('p'),
          const PolygonRecipe(
              sides: 5, radius: 50, star: true, innerRatio: 0.4));
      final node = d.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.path.anchors, hasLength(10));
      expect(node.path.anchors.map((a) => a.id.v).toSet().intersection(first),
          isEmpty);
    });

    test('a node with path keyframes is REFUSED, naming M5 (the ruling)', () {
      final d = _docWith(PathTrack([
        Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
        Keyframe(t: 1.0, value: _poseOf(_square(), 20)),
      ]));

      expect(
        () => PathOps.regenerateRecipe(
            d, const NodeId('p'), const EllipseRecipe(rx: 30, ry: 20)),
        throwsA(isA<ArgumentError>()
            .having((e) => '${e.message}', 'message', contains('retopologize'))
            .having((e) => '${e.message}', 'message', contains('M5'))),
        reason: 'a raw replacement would leave the topology and its keyframes '
            'disjoint — the one state v3 exists to make unrepresentable',
      );
    });

    test('a track under a NON-default animation refuses just as loudly', () {
      final base = _doc();
      final other = Animation(
        id: const AnimationId('a2'),
        name: 'Second',
        tracks: {
          const NodeId('p'): TrackSet({
            const PropertyKey(PropKey.path): PathTrack([
              Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
            ]),
          }),
        },
      );
      final d = base.copyWith(animations: [...base.animations, other]);

      expect(
          () => PathOps.regenerateRecipe(
              d, const NodeId('p'), const EllipseRecipe(rx: 5, ry: 5)),
          throwsArgumentError);
    });

    test(
        'the refusal never leaves a keyframe posing an anchor the topology '
        'lacks (the M5 invariant)', () {
      var d = _docWith(PathTrack([
        Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
        Keyframe(t: 1.0, value: _poseOf(_square(), 20)),
      ]));

      expect(
          () => d = PathOps.regenerateRecipe(
              d, const NodeId('p'), const PolygonRecipe(sides: 5, radius: 50)),
          throwsArgumentError);

      final node = d.nodeIndex[const NodeId('p')]! as PathNode;
      final topology = node.path.anchors.map((a) => a.id.v).toList();
      expect(topology, ['a0', 'a1', 'a2', 'a3']);
      for (final animation in d.animations) {
        final track = animation.tracksFor(const NodeId('p')).pathTrack();
        if (track == null) continue;
        for (final k in track.keys) {
          expect(k.value.anchors.keys.map((i) => i.v).toList(), topology,
              reason:
                  'AC-4.3.6 holds across every keyframe of every animation');
        }
      }
    });

    test('an untracked regeneration leaves no orphan pose behind', () {
      // The node has tracks — just not a PATH track — so the op must proceed
      // and must not disturb them.
      final base = _doc();
      final animation = base.defaultAnimation!.copyWith(tracks: {
        const NodeId('p'): TrackSet({
          const PropertyKey(PropKey.rotation): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: 3.0),
          ]),
        }),
      });
      final d = base.copyWith(animations: [animation]);

      final out = PathOps.regenerateRecipe(
          d, const NodeId('p'), const RectRecipe(w: 10, h: 10));
      final tracks = out.defaultAnimation!.tracksFor(const NodeId('p'));
      expect(tracks.pathTrack(), isNull);
      expect(tracks.scalar(PropKey.rotation)!.keyCount, 2);
      expect((out.nodeIndex[const NodeId('p')]! as PathNode).path.anchors,
          hasLength(4));
    });

    test('an unknown node, a group, and an UnknownRecipe all throw', () {
      final d = _doc();
      expect(
          () => PathOps.regenerateRecipe(
              d, const NodeId('nope'), const RectRecipe(w: 1, h: 1)),
          throwsArgumentError);
      expect(
          () => PathOps.regenerateRecipe(
              d, const NodeId('root'), const RectRecipe(w: 1, h: 1)),
          throwsArgumentError);
      expect(
          () => PathOps.regenerateRecipe(d, const NodeId('p'),
              ShapeRecipe.fromJson(const {'type': 'spiral'})),
          throwsArgumentError,
          reason: 'regenerating from a recipe this build cannot read would '
              'replace the artwork with nothing');
    });

    test('a degenerate recipe empties the geometry without throwing', () {
      // The shape tool passes through this on the first frame of every drag.
      final out = PathOps.regenerateRecipe(
          _doc(), const NodeId('p'), const RectRecipe(w: 0, h: 0));
      final node = out.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.path.anchors, isEmpty);
      expect(node.path.isEmpty, isTrue);
      expect(node.recipe, const RectRecipe(w: 0, h: 0));
    });
  });

  group('rotation stays unbounded', () {
    test('0 → -12.5664 plays two full reverse turns, never shortest-arc', () {
      const twoTurns = -12.5664;
      final track = ScalarTrack([
        const Keyframe(t: 0.0, value: 0.0),
        const Keyframe(t: 1.0, value: twoTurns),
      ]);

      expect(track.sampleAt(0.25), closeTo(twoTurns * 0.25, 1e-12));
      expect(track.sampleAt(0.5), closeTo(twoTurns * 0.5, 1e-12));
      expect(track.sampleAt(1.0), twoTurns);
      // Shortest-arc normalisation would have collapsed this to ~0 and the spin
      // would silently disappear.
      expect(track.sampleAt(1.0).abs(), greaterThan(12.0));

      final animation = Animation(
        id: const AnimationId('a1'),
        name: 'Main',
        tracks: {
          const NodeId('p'): TrackSet({
            const PropertyKey(PropKey.rotation): track,
          }),
        },
      );
      final d = Document(
        id: 'doc',
        name: 'spin',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(
            id: const NodeId('root'), name: 'Root', children: [_node()]),
        animations: [animation],
        defaultAnimationId: animation.id,
      );

      // Through the evaluator: the raw radians reach `Transform2`, so a
      // half-turn at t = 0.25 is a genuine π rotation and not the identity.
      final world = evaluate(d, [const AnimationMix(AnimationId('a1'), 0.25)])
          .byPath[const ScenePath(NodeId('p'))]!
          .world;
      expect(world.a, closeTo(Affine.rotate(twoTurns * 0.25).a, 1e-9));
      expect(world.b, closeTo(Affine.rotate(twoTurns * 0.25).b, 1e-9));
    });
  });
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

List<Anchor> _square() => const [
      Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
      Anchor(id: AnchorId('a1'), position: Vec2(20, 0)),
      Anchor(id: AnchorId('a2'), position: Vec2(20, 20)),
      Anchor(id: AnchorId('a3'), position: Vec2(0, 20)),
    ];

PathPose _poseOf(List<Anchor> anchors, double dx) => PathPose({
      for (final a in anchors)
        a.id: AnchorPose(
            Vec2(a.position.x + dx, a.position.y), Vec2.zero, Vec2.zero),
    });

PathNode _node() => PathNode(
      id: const NodeId('p'),
      name: 'p',
      path: PathData(anchors: _square()),
    );

/// The same node, but drawn by the (M3) shape tool — so it carries the inert
/// recipe the authority rule has to null.
PathNode _recipeNode() =>
    _node().copyWith(recipe: const RectRecipe(w: 20, h: 20));

/// A one-node document holding [node], optionally already carrying [track].
Document _docOf(PathNode node, [PathTrack? track]) {
  final animation = Animation(
    id: const AnimationId('a1'),
    name: 'Main',
    tracks: track == null
        ? const <NodeId, TrackSet>{}
        : <NodeId, TrackSet>{
            node.id: TrackSet({const PropertyKey(PropKey.path): track}),
          },
  );
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: [node]),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}

double _cross(Vec2 a, Vec2 b) => a.x * b.y - a.y * b.x;

double _dot(Vec2 a, Vec2 b) => a.x * b.x + a.y * b.y;

/// The same document, already carrying [track] on node `p`.
Document _docWith(PathTrack track) {
  final animation = Animation(
    id: const AnimationId('a1'),
    name: 'Main',
    tracks: {
      const NodeId('p'): TrackSet({const PropertyKey(PropKey.path): track}),
    },
  );
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450.2, 250.4),
    root:
        GroupNode(id: const NodeId('root'), name: 'Root', children: [_node()]),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}

Document _doc() {
  const animation = Animation(id: AnimationId('a1'), name: 'Main');
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450.2, 250.4),
    root:
        GroupNode(id: const NodeId('root'), name: 'Root', children: [_node()]),
    animations: const [animation],
    defaultAnimationId: animation.id,
  );
}
