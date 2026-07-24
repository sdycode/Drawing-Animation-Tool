import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The M4 document-level keyframe route (docs/v3/01 §12; docs/v3/03 F6.1, F6.2).
void main() {
  group('KeyframeOps.keyAt', () {
    test('creates the track with the type kExpectedTrackType dictates', () {
      // Scalar channel.
      var d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.5, 1.57);
      final rot = d.defaultAnimation!
          .tracksFor(const NodeId('p'))
          .byKey[const PropertyKey(PropKey.rotation)];
      expect(rot, isA<ScalarTrack>());
      expect(rot!.keyCount, 1);
      expect((rot as ScalarTrack).sampleAt(0.5), 1.57);

      // Vec2 channel.
      d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.position), 0.3, const Vec2(4, 5));
      expect(
          d.defaultAnimation!
              .tracksFor(const NodeId('p'))
              .vec2(PropKey.position),
          isA<Vec2Track>());

      // Bool channel.
      d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.visible), 0.3, false);
      expect(
          d.defaultAnimation!
              .tracksFor(const NodeId('p'))
              .boolean(PropKey.visible),
          isA<BoolTrack>());

      // Colour channel with a paint subjectId.
      d = KeyframeOps.keyAt(
          _doc(),
          const NodeId('p'),
          const PropertyKey(PropKey.fillColor, 'p-body'),
          0.3,
          const Rgba(1, 0, 0));
      expect(
          d.defaultAnimation!
              .tracksFor(const NodeId('p'))
              .color(PropKey.fillColor, 'p-body'),
          isA<ColorTrack>());
    });

    test('rejects a value whose runtime type does not match (AC-6.1.3)', () {
      final d = _doc();
      // Vec2 into a scalar channel.
      expect(
          () => KeyframeOps.keyAt(d, const NodeId('p'),
              const PropertyKey(PropKey.rotation), 0.5, const Vec2(1, 2)),
          throwsArgumentError);
      // double into a Vec2 channel.
      expect(
          () => KeyframeOps.keyAt(d, const NodeId('p'),
              const PropertyKey(PropKey.position), 0.5, 3.0),
          throwsArgumentError);
      // int into a bool channel.
      expect(
          () => KeyframeOps.keyAt(
              d, const NodeId('p'), const PropertyKey(PropKey.visible), 0.5, 1),
          throwsArgumentError);
      // A scalar channel does accept an int (widened like the decoder's `d`).
      expect(
          KeyframeOps.keyAt(d, const NodeId('p'),
                  const PropertyKey(PropKey.opacity), 0.5, 1)
              .defaultAnimation!
              .tracksFor(const NodeId('p'))
              .scalar(PropKey.opacity)!
              .sampleAt(0.5),
          1.0);
    });

    test('replaces at an existing t — no second key (AC-6.2.7)', () {
      var d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.5, 1.0);
      d = KeyframeOps.keyAt(
          d, const NodeId('p'), const PropertyKey(PropKey.rotation), 0.5, 2.0);
      final track = d.defaultAnimation!
          .tracksFor(const NodeId('p'))
          .scalar(PropKey.rotation)!;
      expect(track.keyCount, 1);
      expect(track.sampleAt(0.5), 2.0);
    });

    test('re-keying a value at an existing key does not retime it', () {
      // The displaced key's easing rides across, exactly as PathOps does.
      var d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.0, 0.0);
      d = KeyframeOps.keyAt(
          d, const NodeId('p'), const PropertyKey(PropKey.rotation), 0.5, 10.0);
      d = KeyframeOps.setKeyEasing(d, const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0, CubicEasing.backIn);

      // Re-key the VALUE at t = 0.0 — the easing must survive.
      d = KeyframeOps.keyAt(
          d, const NodeId('p'), const PropertyKey(PropKey.rotation), 0.0, 3.0);
      final track = d.defaultAnimation!
          .tracksFor(const NodeId('p'))
          .scalar(PropKey.rotation)!;
      expect(track.keys[0].value, 3.0);
      expect(track.keys[0].easing, CubicEasing.backIn);
    });

    test('a fresh key is linear (the model identity), not inherited', () {
      final d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.5, 1.0);
      expect(
          d.defaultAnimation!
              .tracksFor(const NodeId('p'))
              .scalar(PropKey.rotation)!
              .keys[0]
              .easing,
          const LinearEasing());
    });

    test('creates the animation when the document has none', () {
      final bare = Document(
        id: 'doc',
        name: 'bare',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(
            id: const NodeId('root'), name: 'Root', children: [_node('p')]),
      );
      expect(bare.defaultAnimation, isNull);

      final out = KeyframeOps.keyAt(bare, const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.5, 1.0);
      expect(out.animations, hasLength(1));
      expect(out.defaultAnimationId, out.animations.single.id);
    });

    test('refuses PropKey.path — the path seam routes through PathOps', () {
      expect(
          () => KeyframeOps.keyAt(_doc(), const NodeId('p'),
              const PropertyKey(PropKey.path), 0.5, PathPose.empty),
          throwsA(isA<ArgumentError>()
              .having((e) => '${e.message}', 'message', contains('PathOps'))));
    });

    test('an unknown node throws, and a t outside [0,1] throws', () {
      expect(
          () => KeyframeOps.keyAt(_doc(), const NodeId('nope'),
              const PropertyKey(PropKey.rotation), 0.5, 1.0),
          throwsArgumentError);
      expect(
          () => KeyframeOps.keyAt(_doc(), const NodeId('p'),
              const PropertyKey(PropKey.rotation), 1.5, 1.0),
          throwsArgumentError);
    });
  });

  group('KeyframeOps.moveKey / setKeyEasing / removeKey', () {
    Document seeded() {
      var d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.2, 1.0);
      d = KeyframeOps.keyAt(
          d, const NodeId('p'), const PropertyKey(PropKey.rotation), 0.5, 2.0);
      return KeyframeOps.keyAt(
          d, const NodeId('p'), const PropertyKey(PropKey.rotation), 0.8, 3.0);
    }

    ScalarTrack rotOf(Document d) => d.defaultAnimation!
        .tracksFor(const NodeId('p'))
        .scalar(PropKey.rotation)!;

    test('moveKey delegates to the track op and rejects a collision', () {
      final d = KeyframeOps.moveKey(seeded(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 1, 0.55);
      expect(rotOf(d).keys.map((k) => k.t).toList(), [0.2, 0.55, 0.8]);
      // minSeparation is enforced at the document level too (via the track op).
      expect(
          () => KeyframeOps.moveKey(seeded(), const NodeId('p'),
              const PropertyKey(PropKey.rotation), 0, 0.5),
          throwsArgumentError);
    });

    test('setKeyEasing delegates to the track op', () {
      final d = KeyframeOps.setKeyEasing(seeded(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0, const HoldEasing());
      expect(rotOf(d).keys[0].easing, const HoldEasing());
    });

    test('removeKey drops a non-last key', () {
      final d = KeyframeOps.removeKey(
          seeded(), const NodeId('p'), const PropertyKey(PropKey.rotation), 1);
      expect(rotOf(d).keys.map((k) => k.t).toList(), [0.2, 0.8]);
    });

    test('removeKey on the LAST key drops the whole track and the node entry',
        () {
      final one = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.5, 1.0);
      final out = KeyframeOps.removeKey(
          one, const NodeId('p'), const PropertyKey(PropKey.rotation), 0);

      // The track is gone…
      expect(
          out.defaultAnimation!
              .tracksFor(const NodeId('p'))
              .scalar(PropKey.rotation),
          isNull);
      // …and because it was the node's only track, the node entry is dropped.
      expect(
          out.defaultAnimation!.tracks.containsKey(const NodeId('p')), isFalse);
      // The animation itself survives (v1: exactly one, referenced by default).
      expect(out.animations, hasLength(1));
      expect(out.defaultAnimationId, isNotNull);
    });

    test(
        'removeKey on the last key of one track keeps the node when another '
        'track remains', () {
      var d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.5, 1.0);
      d = KeyframeOps.keyAt(d, const NodeId('p'),
          const PropertyKey(PropKey.position), 0.2, const Vec2(0, 0));
      d = KeyframeOps.keyAt(d, const NodeId('p'),
          const PropertyKey(PropKey.position), 0.8, const Vec2(9, 9));

      final out = KeyframeOps.removeKey(
          d, const NodeId('p'), const PropertyKey(PropKey.rotation), 0);
      final tracks = out.defaultAnimation!.tracksFor(const NodeId('p'));
      expect(tracks.scalar(PropKey.rotation), isNull);
      expect(tracks.vec2(PropKey.position)!.keyCount, 2);
      expect(
          out.defaultAnimation!.tracks.containsKey(const NodeId('p')), isTrue);
    });

    test('move/remove/setEasing on an unknown node or missing track throw', () {
      final d = seeded();
      expect(
          () => KeyframeOps.moveKey(d, const NodeId('nope'),
              const PropertyKey(PropKey.rotation), 0, 0.1),
          throwsArgumentError);
      expect(
          () => KeyframeOps.moveKey(
              d, const NodeId('p'), const PropertyKey(PropKey.scale), 0, 0.1),
          throwsArgumentError,
          reason: 'no scale track exists on this node');
      expect(
          () => KeyframeOps.removeKey(
              d, const NodeId('p'), const PropertyKey(PropKey.rotation), 9),
          throwsArgumentError,
          reason: 'index out of range');
    });
  });

  group('the time/easing/index ops DO work on a path track (topology safe)',
      () {
    Document withPath() {
      // Two keyframes, both posing the node's whole anchor set.
      final track = PathTrack([
        Keyframe(t: 0.2, value: _pose(0)),
        Keyframe(t: 0.8, value: _pose(10)),
      ]);
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
        root: GroupNode(
            id: const NodeId('root'), name: 'Root', children: [_node('p')]),
        animations: [animation],
        defaultAnimationId: animation.id,
      );
    }

    PathTrack pathOf(Document d) =>
        d.defaultAnimation!.tracksFor(const NodeId('p')).pathTrack()!;

    test('moveKey retimes a path key; setKeyEasing eases its segment', () {
      var d = KeyframeOps.moveKey(withPath(), const NodeId('p'),
          const PropertyKey(PropKey.path), 0, 0.4);
      expect(pathOf(d).keys.map((k) => k.t).toList(), [0.4, 0.8]);
      d = KeyframeOps.setKeyEasing(d, const NodeId('p'),
          const PropertyKey(PropKey.path), 0, const HoldEasing());
      expect(pathOf(d).keys[0].easing, const HoldEasing());
      // The AnchorId sequence is untouched by a time/easing edit.
      for (final k in pathOf(d).keys) {
        expect(k.value.anchors.keys.map((i) => i.v).toList(),
            ['a0', 'a1', 'a2', 'a3']);
      }
    });

    test('removeKey drops a non-last path key without disturbing topology', () {
      final d = KeyframeOps.removeKey(
          withPath(), const NodeId('p'), const PropertyKey(PropKey.path), 0);
      expect(pathOf(d).keyCount, 1);
      expect(pathOf(d).keys[0].value.anchors.keys.map((i) => i.v).toList(),
          ['a0', 'a1', 'a2', 'a3']);
    });
  });

  group('AC-6.1.5 — four nodes keyed independently sample independently', () {
    test('no shared keyframe grid: each track samples off its own keys', () {
      var d = _fourNodeDoc();
      // Four nodes, different properties, different key counts and positions.
      d = KeyframeOps.keyAt(
          d, const NodeId('n0'), const PropertyKey(PropKey.rotation), 0.0, 0.0);
      d = KeyframeOps.keyAt(d, const NodeId('n0'),
          const PropertyKey(PropKey.rotation), 1.0, 10.0);

      d = KeyframeOps.keyAt(d, const NodeId('n1'),
          const PropertyKey(PropKey.rotation), 0.13, 0.0);
      d = KeyframeOps.keyAt(d, const NodeId('n1'),
          const PropertyKey(PropKey.rotation), 0.77, 100.0);

      d = KeyframeOps.keyAt(
          d, const NodeId('n2'), const PropertyKey(PropKey.opacity), 0.5, 0.25);

      d = KeyframeOps.keyAt(
          d, const NodeId('n3'), const PropertyKey(PropKey.rotation), 0.2, 5.0);
      d = KeyframeOps.keyAt(
          d, const NodeId('n3'), const PropertyKey(PropKey.rotation), 0.4, 6.0);
      d = KeyframeOps.keyAt(
          d, const NodeId('n3'), const PropertyKey(PropKey.rotation), 0.9, 9.0);

      final anim = d.defaultAnimation!;
      double rot(String id, double t) =>
          anim.tracksFor(NodeId(id)).scalar(PropKey.rotation)!.sampleAt(t);

      // n0: linear 0→10 over [0,1] → 5 at 0.5.
      expect(rot('n0', 0.5), closeTo(5.0, 1e-12));
      // n1: [0.13,0.77] → (0.5-0.13)/(0.77-0.13)*100.
      expect(rot('n1', 0.5), closeTo(0.37 / 0.64 * 100.0, 1e-9));
      // n2: opacity only, one key → holds 0.25 everywhere; no rotation track.
      expect(
          anim.tracksFor(const NodeId('n2')).scalar(PropKey.rotation), isNull);
      expect(
          anim
              .tracksFor(const NodeId('n2'))
              .scalar(PropKey.opacity)!
              .sampleAt(0.5),
          0.25);
      // n3: three keys, hold-first before 0.2.
      expect(rot('n3', 0.1), 5.0);

      // Key counts differ per node — there is no global grid.
      expect(
          anim.tracksFor(const NodeId('n0')).scalar(PropKey.rotation)!.keyCount,
          2);
      expect(
          anim.tracksFor(const NodeId('n3')).scalar(PropKey.rotation)!.keyCount,
          3);
    });
  });

  group('KeyframeOps.keyTimes — pure read for the timeline (AC-6.2.5)', () {
    test('returns the key times, and empty when the track is absent', () {
      var d = KeyframeOps.keyAt(_doc(), const NodeId('p'),
          const PropertyKey(PropKey.rotation), 0.2, 1.0);
      d = KeyframeOps.keyAt(
          d, const NodeId('p'), const PropertyKey(PropKey.rotation), 0.7, 2.0);
      expect(
          KeyframeOps.keyTimes(
              d, const NodeId('p'), const PropertyKey(PropKey.rotation)),
          [0.2, 0.7]);
      expect(
          KeyframeOps.keyTimes(
              d, const NodeId('p'), const PropertyKey(PropKey.scale)),
          isEmpty);
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

PathPose _pose(double dx) => PathPose({
      for (final a in _square())
        a.id: AnchorPose(
            Vec2(a.position.x + dx, a.position.y), Vec2.zero, Vec2.zero),
    });

PathNode _node(String id) =>
    PathNode(id: NodeId(id), name: id, path: PathData(anchors: _square()));

Document _doc() {
  const animation = Animation(id: AnimationId('a1'), name: 'Main');
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(
        id: const NodeId('root'), name: 'Root', children: [_node('p')]),
    animations: const [animation],
    defaultAnimationId: animation.id,
  );
}

Document _fourNodeDoc() {
  const animation = Animation(id: AnimationId('a1'), name: 'Main');
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
      _node('n0'),
      _node('n1'),
      _node('n2'),
      _node('n3'),
    ]),
    animations: const [animation],
    defaultAnimationId: animation.id,
  );
}
