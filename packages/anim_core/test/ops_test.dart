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
