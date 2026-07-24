import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The "stopwatch" primitive — [PathOps.keyPose] (M4, docs/v3/03 F6.1).
///
/// It authors the FIRST path keyframe (and continues one) by snapshotting the
/// pose already on screen, without moving an anchor. Before it, the M4 exit
/// criterion "set 3 keyframes on a path's geometry" was unreachable by hand.
void main() {
  const p = NodeId('p');
  const a1 = AnchorId('a1');
  const topology = <String>['a0', 'a1', 'a2', 'a3'];

  group('PathOps.keyPose — untracked node (the first key)', () {
    test('creates a ONE-key path track holding the rest pose', () {
      final out = PathOps.keyPose(_doc(), p, 0.5);

      final track = out.defaultAnimation!.tracksFor(p).pathTrack()!;
      expect(track.keyCount, 1,
          reason: 'a stopwatch click seeds one key, not '
              'two — there is nothing to interpolate toward yet');
      expect(track.keys.single.t, 0.5);

      // The captured pose IS the node's authored rest pose.
      final anchors = track.keys.single.value.anchors;
      expect(anchors[a1]!.position, const Vec2(20, 0));
      expect(anchors[const AnchorId('a2')]!.position, const Vec2(20, 20));
      // And it poses exactly the node's topology, in order (invariant P5).
      expect(anchors.keys.map((i) => i.v).toList(), topology);
    });

    test('poses exactly the AnchorId topology even from a partial rest pose',
        () {
      // Every anchor of the square is present with zero tangents.
      final out = PathOps.keyPose(_doc(), p, 0.25);
      final track = out.defaultAnimation!.tracksFor(p).pathTrack()!;
      for (final k in track.keys) {
        expect(k.value.anchors.keys.map((i) => i.v).toList(), topology);
        expect(k.value.anchors[a1]!.inTangent, Vec2.zero);
        expect(k.value.anchors[a1]!.outTangent, Vec2.zero);
      }
    });

    test('mints the animation when the document has none', () {
      final bare = Document(
        id: 'doc',
        name: 'bare',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(
            id: const NodeId('root'), name: 'Root', children: [_node()]),
      );
      expect(bare.defaultAnimation, isNull);

      final out = PathOps.keyPose(bare, p, 0.75);
      expect(out.animations, hasLength(1));
      expect(out.defaultAnimationId, out.animations.single.id);
      expect(out.defaultAnimation!.tracksFor(p).pathTrack()!.keyCount, 1);
    });

    test('leaves the node PathData and the recipe UNTOUCHED (the ruling)', () {
      final d = _docOf(_recipeNode());
      expect((d.nodeIndex[p]! as PathNode).recipe, isNotNull);

      final out = PathOps.keyPose(d, p, 0.4);
      final node = out.nodeIndex[p]! as PathNode;
      // A pose snapshot edits no anchor, so the recipe still describes the rest
      // geometry and survives — unlike a hand anchor edit, which nulls it.
      expect(node.recipe, isNotNull,
          reason: 'keying the path edits no anchor, so the recipe stays valid');
      expect(node.path.anchors, (d.nodeIndex[p]! as PathNode).path.anchors,
          reason: 'the rest pose is byte-identical');
    });
  });

  group('PathOps.keyPose — a second key starts the animation', () {
    test('a second keyPose at a different t gives TWO keys', () {
      var d = PathOps.keyPose(_doc(), p, 0.2);
      d = PathOps.keyPose(d, p, 0.8);

      final track = d.defaultAnimation!.tracksFor(p).pathTrack()!;
      expect(track.keyCount, 2);
      expect(track.keys.map((k) => k.t).toList(), [0.2, 0.8]);
      for (final k in track.keys) {
        expect(k.value.anchors.keys.map((i) => i.v).toList(), topology);
      }
    });

    test(
        'keyPose at an existing t REPLACES — no 2nd key, no minSeparation '
        'violation', () {
      var d = PathOps.keyPose(_doc(), p, 0.5);
      // Exact-t replace.
      d = PathOps.keyPose(d, p, 0.5);
      expect(d.defaultAnimation!.tracksFor(p).pathTrack()!.keyCount, 1);

      // A near miss inside minSeparation is also a replace.
      d = PathOps.keyPose(d, p, 0.5 + TrackOps.minSeparation / 2);
      final track = d.defaultAnimation!.tracksFor(p).pathTrack()!;
      expect(track.keyCount, 1);
      for (var i = 1; i < track.keys.length; i++) {
        expect(track.keys[i].t - track.keys[i - 1].t,
            greaterThan(TrackOps.minSeparation));
      }
    });
  });

  group('PathOps.keyPose — tracked node captures the EVALUATED pose', () {
    test('keying at a new t snapshots resolveNodePose at that t (to 1e-9)', () {
      // Two keys, linear easing: rest at t = 0, shifted +20 in x with an out-
      // tangent (2,3) at t = 1.
      final k1 = PathPose({
        for (final a in _square())
          a.id: AnchorPose(Vec2(a.position.x + 20, a.position.y), Vec2.zero,
              const Vec2(2, 3)),
      });
      final d = _docWith(PathTrack([
        Keyframe(t: 0.0, value: _poseOf(_square(), 0)),
        Keyframe(t: 1.0, value: k1),
      ]));
      final node = d.nodeIndex[p]! as PathNode;
      final base = d.defaultAnimation!.tracksFor(p).pathTrack()!;

      const t = 0.3;
      final out = PathOps.keyPose(d, p, t);
      final track = out.defaultAnimation!.tracksFor(p).pathTrack()!;

      expect(track.keyCount, 3, reason: 'the new key joins the existing two');
      final captured =
          track.keys.firstWhere((k) => (k.t - t).abs() < 1e-9).value.anchors;

      // The reference: exactly the pose the canvas draws at t.
      final (b0, b1, u) = base.bracket(t);
      final reference =
          resolveNodePose(node.path, [PathBracket(b0.value, b1.value, u, 1.0)]);

      for (final ref in reference.anchors) {
        final got = captured[ref.id]!;
        expect(got.position.x, closeTo(ref.position.x, 1e-9));
        expect(got.position.y, closeTo(ref.position.y, 1e-9));
        expect(got.inTangent.x, closeTo(ref.inTangent.x, 1e-9));
        expect(got.inTangent.y, closeTo(ref.inTangent.y, 1e-9));
        expect(got.outTangent.x, closeTo(ref.outTangent.x, 1e-9));
        expect(got.outTangent.y, closeTo(ref.outTangent.y, 1e-9));
      }

      // A concrete spot-check so this is not passing by comparing a bug to
      // itself: a1 at t = 0.3 is the linear midpoint of its two poses.
      expect(captured[a1]!.position.x, closeTo(26.0, 1e-9)); // 20 + 0.3*20
      expect(captured[a1]!.position.y, closeTo(0.0, 1e-9));
      expect(captured[a1]!.outTangent.x, closeTo(0.6, 1e-9)); // 0.3*2
      expect(captured[a1]!.outTangent.y, closeTo(0.9, 1e-9)); // 0.3*3

      // Every key of the enlarged track still poses the topology (AC-4.3.6).
      for (final k in track.keys) {
        expect(k.value.anchors.keys.map((i) => i.v).toList(), topology);
      }
    });
  });

  group('PathOps.keyPose — guards and purity', () {
    test('an unknown node or a non-path (group) node throws ArgumentError', () {
      final d = _doc();
      expect(() => PathOps.keyPose(d, const NodeId('nope'), 0.5),
          throwsArgumentError);
      expect(() => PathOps.keyPose(d, const NodeId('root'), 0.5),
          throwsArgumentError,
          reason: 'a group is not a path node');
    });

    test('a t outside [0,1] or NaN throws', () {
      final d = _doc();
      expect(() => PathOps.keyPose(d, p, 1.5), throwsArgumentError);
      expect(() => PathOps.keyPose(d, p, -0.1), throwsArgumentError);
      expect(() => PathOps.keyPose(d, p, double.nan), throwsArgumentError);
    });

    test('is a pure read of its input — the input Document is unchanged', () {
      final d = _doc();
      PathOps.keyPose(d, p, 0.5);
      expect(d.defaultAnimation!.tracksFor(p).isEmpty, isTrue,
          reason: 'no model object is mutable; keyPose returns a new Document');
    });
  });

  group('PathOps.keyPose composes with moveAnchor(atT:)', () {
    test(
        'key the path, then drag an anchor at another t — two keys, both '
        'pose the topology', () {
      // Stopwatch at t = 0 seeds the rest pose…
      var d = PathOps.keyPose(_doc(), p, 0.0);
      expect(d.defaultAnimation!.tracksFor(p).pathTrack()!.keyCount, 1);

      // …and a drag at another t now animates the shape (a track already
      // exists, so moveAnchor does not re-seed).
      d = PathOps.moveAnchor(d, p, a1, const Vec2(50, 60), atT: 0.5);

      final track = d.defaultAnimation!.tracksFor(p).pathTrack()!;
      expect(track.keyCount, 2);
      expect(track.keys.map((k) => k.t).toList(), [0.0, 0.5]);

      // The two keys differ (rest a1 vs moved a1) and both pose the topology.
      expect(track.keys.first.value.anchors[a1]!.position, const Vec2(20, 0));
      expect(track.keys.last.value.anchors[a1]!.position, const Vec2(50, 60));
      for (final k in track.keys) {
        expect(k.value.anchors.keys.map((i) => i.v).toList(), topology);
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Builders (mirrors ops_test.dart)
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

/// The same node, drawn by a shape tool, so it carries the inert recipe.
PathNode _recipeNode() =>
    _node().copyWith(recipe: const RectRecipe(w: 20, h: 20));

Document _docOf(PathNode node) {
  const animation = Animation(id: AnimationId('a1'), name: 'Main');
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: [node]),
    animations: const [animation],
    defaultAnimationId: animation.id,
  );
}

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
