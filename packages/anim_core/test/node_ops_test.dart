import 'dart:math' as math;

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// NodeOps — tree surgery (docs/v3/01 §3, §4, §12; F2.1).
void main() {
  group('NodeOps.createGroup', () {
    test('two siblings group pixel-identically and leave a third untouched',
        () {
      final d = _threeSquareDoc();
      final before = evaluate(d, const <AnimationMix>[]);

      final out = NodeOps.createGroup(d, const [NodeId('A'), NodeId('B')]);
      final after = evaluate(out, const <AnimationMix>[]);

      // Every leaf renders exactly where it did — grouping moved nothing.
      for (final id in const [NodeId('A'), NodeId('B'), NodeId('C')]) {
        expect(_digest(after, id), _digest(before, id),
            reason: 'node ${id.v} moved when it was grouped');
      }

      // A and B left the root; C stayed.
      final rootIds = out.root.children.map((c) => c.id.v).toList();
      expect(rootIds, isNot(contains('A')));
      expect(rootIds, isNot(contains('B')));
      expect(rootIds, contains('C'));
    });

    test('the group pivot is the union-AABB centre of its members', () {
      // A: local square (0,0)-(20,20), identity transform.
      // B: same local square, translated +100 in x  -> (100,0)-(120,20).
      // Union AABB (0,0)-(120,20), centre (60,10).
      final d = _threeSquareDoc();
      final out = NodeOps.createGroup(d, const [NodeId('A'), NodeId('B')]);

      final group = out.root.children.whereType<GroupNode>().single;
      expect(group.children.map((c) => c.id.v).toList(), ['A', 'B']);
      expect(group.transform.pivot.x, closeTo(60.0, 1e-9));
      expect(group.transform.pivot.y, closeTo(10.0, 1e-9));
      // Identity everywhere else, so the group's own local is the identity.
      expect(group.transform.rotation, 0.0);
      expect(group.transform.scale, Vec2.one);
    });

    test('grouping non-siblings throws', () {
      // A under root, B nested inside a subgroup — not siblings.
      final d = Document(
        id: 'doc',
        name: 't',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
          _square('A', const Vec2(0, 0)),
          GroupNode(id: const NodeId('g'), name: 'g', children: [
            _square('B', const Vec2(0, 0)),
          ]),
        ]),
      );
      expect(() => NodeOps.createGroup(d, const [NodeId('A'), NodeId('B')]),
          throwsArgumentError);
    });

    test('an unknown member throws', () {
      final d = _threeSquareDoc();
      expect(() => NodeOps.createGroup(d, const [NodeId('nope')]),
          throwsArgumentError);
    });

    test('a NON-CONTIGUOUS member set is refused, not silently reordered', () {
      // root children are [A, B, C]. Grouping A and C would produce the draw
      // order [group(A, C), B] — every member's own ResolvedNode still
      // bit-identical, but B pushed behind both with nothing rejected and
      // nothing warned. There is no placement that keeps B between them.
      final d = _threeSquareDoc();
      expect(
          () => NodeOps.createGroup(d, const [NodeId('A'), NodeId('C')]),
          throwsA(isA<ArgumentError>().having((e) => '$e', 'message',
              allOf(contains('contiguous'), contains('B')))));

      // The adjacent pair is untouched by the new precondition.
      final ok = NodeOps.createGroup(d, const [NodeId('B'), NodeId('C')]);
      expect(ok.root.children.map((c) => c.name).toList(), ['A', 'Group']);
      expect((ok.root.children[1] as GroupNode).children.map((c) => c.id.v),
          ['B', 'C']);
    });

    test('the pivot is the EXACT cubic AABB centre, not a sampled polyline\'s',
        () {
      // One open segment: P0 (0,0), P1 (0,90), P2 (90,30), P3 (90,0).
      //   x: B'(u) = -180u² + 180u -> extrema only at the endpoints, [0, 90].
      //   y: B'(u)/3 = 180u² - 300u + 90 -> u = (10-√28)/12 = 0.392374781489…,
      //      where y = 90u(1-u)(3-2u) = 47.53376529575356.
      // Exact AABB (0,0)-(90, 47.53376529575356), centre (45, 23.76688264787678).
      // A 16-step sample peaks at u = 6/16 with y = 47.4609375 and puts the
      // centre at 23.73046875 — 0.0364 doc units short of the AABB AC-2.1.3
      // names, and it under-bounds by construction, never over.
      final d = _bulgingCurveDoc();
      final out = NodeOps.createGroup(d, const [NodeId('curve')]);
      final group = out.root.children.whereType<GroupNode>().single;

      expect(group.transform.pivot.x, closeTo(45.0, 1e-9));
      expect(group.transform.pivot.y, closeTo(23.76688264787678, 1e-9));
      // Explicitly NOT the sampled answer.
      expect(group.transform.pivot.y, isNot(closeTo(23.73046875, 1e-4)));
    });
  });

  group('NodeOps.reparent', () {
    test('a deeply-transformed node does not move when reparented', () {
      final d = _reparentDoc();
      final before = evaluate(d, const <AnimationMix>[]);
      final wBefore = before.byPath[const ScenePath(NodeId('leaf'))]!.world;

      final out =
          NodeOps.reparent(d, const NodeId('leaf'), const NodeId('g2'), 0);
      final after = evaluate(out, const <AnimationMix>[]);
      final wAfter = after.byPath[const ScenePath(NodeId('leaf'))]!.world;

      _expectAffineClose(wAfter, wBefore, 1e-9);

      // It really did move in the tree.
      final g2 = out.nodeIndex[const NodeId('g2')]! as GroupNode;
      expect(g2.children.map((c) => c.id.v), contains('leaf'));
      final g1 = out.nodeIndex[const NodeId('g1')]! as GroupNode;
      expect(g1.children.map((c) => c.id.v), isNot(contains('leaf')));
    });

    // The test above evaluates with an EMPTY mix, which is the one case in
    // which a track cannot overwrite the pose reparent solved — the single
    // blind spot that let the rest-pose/rendered-pose defect ship green. This
    // one evaluates AT A NON-ZERO PLAYHEAD, through a mix that really is
    // driving transforms elsewhere in the document.
    test('it does not move AT A NON-ZERO PLAYHEAD either (not just at rest)',
        () {
      final d = _reparentDoc(animated: true);
      const mix = [AnimationMix(AnimationId('anim'), 0.37)];

      // The mix is a real animated evaluation: a transform-animated sibling
      // moves between rest and t=0.37, so an empty-mix look-alike would fail.
      expect(
          _digest(evaluate(d, mix), const NodeId('solo')),
          isNot(_digest(
              evaluate(d, const <AnimationMix>[]), const NodeId('solo'))));

      const leaf = ScenePath(NodeId('leaf'));
      final before = evaluate(d, mix).byPath[leaf]!;
      final out =
          NodeOps.reparent(d, const NodeId('leaf'), const NodeId('g2'), 0);
      final after = evaluate(out, mix).byPath[leaf]!;

      // World matrix, world opacity and posed geometry, all at t=0.37.
      _expectAffineClose(after.world, before.world, 1e-9);
      expect(after.worldOpacity, closeTo(before.worldOpacity, 1e-12));
      expect(_anchorDigest(after.geometry), _anchorDigest(before.geometry),
          reason: 'the reparented node moved once the playhead left zero');
    });

    test(
        'a transform-animated node is REFUSED, because the solved pose would '
        'be overwritten by its own track', () {
      final animated = _reparentDoc(positionTrackOnLeaf: true);
      expect(
          () => NodeOps.reparent(
              animated, const NodeId('leaf'), const NodeId('g2'), 0),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('transform track'))));

      // What the refusal prevents, measured: solve the pose at rest (which is
      // all the old code did), then let the position track overwrite it. The
      // node teleports across a third of a 450.2-wide artboard.
      final plain = _reparentDoc();
      final movedAtRest =
          NodeOps.reparent(plain, const NodeId('leaf'), const NodeId('g2'), 0);
      final withTrack = _withLeafPositionTrack(movedAtRest);
      const leaf = ScenePath(NodeId('leaf'));

      for (final (t, expected) in const <(double, double)>[
        (0.0, 154.9866337692615),
        (0.25, 142.5617414151618),
        (0.5, 135.61837472730488),
        (1.0, 140.8042272122819),
      ]) {
        final mix = [AnimationMix(const AnimationId('anim'), t)];
        final was = evaluate(animated, mix).byPath[leaf]!.world;
        final now = evaluate(withTrack, mix).byPath[leaf]!.world;
        final dx = now.tx - was.tx, dy = now.ty - was.ty;
        expect(math.sqrt(dx * dx + dy * dy), closeTo(expected, 1e-9),
            reason: 'the silent teleport at t=$t that the refusal prevents');
      }
      // 154.99 units is 34% of this document's 450.2-unit artboard width, at
      // t=0 — the instant the old solve claimed to be exact at.
    });

    test('an animated frame BETWEEN the two parents is refused', () {
      // g1 itself spins, so newParent⁻¹ · oldParent is not constant and a
      // rest-pose solve is only correct at the instant it was taken.
      final d = _reparentDoc(rotationTrackOnG1: true);
      expect(
          () =>
              NodeOps.reparent(d, const NodeId('leaf'), const NodeId('g2'), 0),
          throwsA(isA<ArgumentError>()
              .having((e) => '$e', 'message', contains('frame change'))));
    });

    test('a shared animated ancestor ABOVE the common parent does not block it',
        () {
      // `anc` spins, but it is the lowest common ancestor of both parents, so
      // it cancels out of newParent⁻¹ · oldParent and the reparent is exact at
      // every playhead. Over-refusing here would ban every reparent under an
      // animated root.
      final d = _sharedAnimatedAncestorDoc();
      const mix = [AnimationMix(AnimationId('anim'), 0.6)];
      final before = evaluate(d, mix).byPath[const ScenePath(NodeId('leaf'))]!;

      final out =
          NodeOps.reparent(d, const NodeId('leaf'), const NodeId('g2'), 0);
      final after = evaluate(out, mix).byPath[const ScenePath(NodeId('leaf'))]!;
      _expectAffineClose(after.world, before.world, 1e-9);
    });

    test('a cycle (into own descendant) throws', () {
      final d = _reparentDoc();
      // g1 contains leaf; reparenting g1 under leaf is a cycle.
      expect(
          () =>
              NodeOps.reparent(d, const NodeId('g1'), const NodeId('leaf'), 0),
          throwsArgumentError);
      // ...and reparenting a node into itself.
      expect(
          () => NodeOps.reparent(d, const NodeId('g1'), const NodeId('g1'), 0),
          throwsArgumentError);
    });

    test('a collapsed new parent refuses rather than teleports', () {
      final d = _reparentDoc(collapseG2: true);
      expect(
          () =>
              NodeOps.reparent(d, const NodeId('leaf'), const NodeId('g2'), 0),
          throwsArgumentError);
    });

    test('a node under a COLLAPSED ancestor can still be rescued to the root',
        () {
      // `dead` is scaled to 0, so world(trapped) is singular. That is the
      // ancestor's matrix, not the node's, and the rescue is representable:
      // newLocal = I⁻¹ · oldWorld has both columns zero, which IS scale (0,0).
      // Refusing here made a collapsed group a one-way trap.
      final d = _collapsedAncestorDoc();
      final before = evaluate(d, const <AnimationMix>[])
          .byPath[const ScenePath(NodeId('trapped'))]!;

      final out =
          NodeOps.reparent(d, const NodeId('trapped'), const NodeId('root'), 0);
      final moved = out.nodeIndex[const NodeId('trapped')]!;
      expect(moved.transform.scale.x, 0.0);
      expect(moved.transform.scale.y, 0.0);
      expect((out.nodeIndex[const NodeId('dead')]! as GroupNode).children,
          isEmpty);

      // The rescue is world-preserving too: a collapsed node stays collapsed
      // exactly where it was, so nothing pops when the ancestor is un-keyed.
      final after = evaluate(out, const <AnimationMix>[])
          .byPath[const ScenePath(NodeId('trapped'))]!;
      _expectAffineClose(after.world, before.world, 1e-9);
    });

    test('a node flattened to scale (1,0) reparents and stays flattened', () {
      // A legitimately flattened shape: its own second column is zero, which
      // Transform2 represents exactly as scale.y == 0.
      final d = _flatNodeDoc();
      final before = evaluate(d, const <AnimationMix>[])
          .byPath[const ScenePath(NodeId('flat'))]!;

      final out =
          NodeOps.reparent(d, const NodeId('flat'), const NodeId('g'), 0);
      final moved = out.nodeIndex[const NodeId('flat')]!;
      expect(moved.transform.scale.x, closeTo(1.0, 1e-12));
      expect(moved.transform.scale.y, 0.0);

      final after = evaluate(out, const <AnimationMix>[])
          .byPath[const ScenePath(NodeId('flat'))]!;
      _expectAffineClose(after.world, before.world, 1e-9);
    });

    test('unbounded rotation and skew survive the decompose round trip', () {
      // atan2 lands rotation on (-π, π] and atan lands skewX on (-π/2, π/2), so
      // a bare decompose returns 4π as -4.9e-16 and skewX 2.0 as 2-π: same
      // pixels at rest, two full turns destroyed. Docs/v3/01 §4 makes unbounded
      // radians a written invariant.
      const fourTurns = 12.566370614359172; // 4π
      for (final rotation in const [fourTurns, -fourTurns]) {
        final d = _spinDoc(rotation: rotation, skewX: 2.0);
        final out =
            NodeOps.reparent(d, const NodeId('spun'), const NodeId('g2'), 0);
        final t = out.nodeIndex[const NodeId('spun')]!.transform;
        expect(t.rotation, closeTo(rotation, 1e-9),
            reason: '$rotation collapsed onto the principal branch');
        expect(t.skewX, closeTo(2.0, 1e-9),
            reason: 'skewX 2.0 collapsed onto 2-π');
      }
    });

    test('the root and unknown targets are refused', () {
      final d = _reparentDoc();
      expect(
          () =>
              NodeOps.reparent(d, const NodeId('root'), const NodeId('g2'), 0),
          throwsArgumentError);
      expect(
          () => NodeOps.reparent(
              d, const NodeId('leaf'), const NodeId('missing'), 0),
          throwsArgumentError);
      // g2 is a group; targeting a leaf (non-group) is refused.
      expect(
          () => NodeOps.reparent(
              d, const NodeId('leaf'), const NodeId('solo'), 0),
          throwsArgumentError);
    });
  });

  group('NodeOps.duplicateSubtree', () {
    test('every node id and anchor id differs between original and copy', () {
      final d = _animatedGroupDoc();
      final out = NodeOps.duplicateSubtree(d, const NodeId('grp'));
      final copy = _nextSiblingOf(out, const NodeId('grp'));

      final originalNodeIds =
          _subtreeNodeIds(d.nodeIndex[const NodeId('grp')]!);
      final copyNodeIds = _subtreeNodeIds(copy);
      expect(originalNodeIds.intersection(copyNodeIds), isEmpty);

      final originalAnchors =
          _subtreeAnchorIds(d.nodeIndex[const NodeId('grp')]!);
      final copyAnchors = _subtreeAnchorIds(copy);
      expect(originalAnchors, isNotEmpty);
      expect(originalAnchors.intersection(copyAnchors), isEmpty);
    });

    test('the copy path tracks pose the copy anchor ids and only those', () {
      final d = _animatedGroupDoc();
      final out = NodeOps.duplicateSubtree(d, const NodeId('grp'));
      final copy = _nextSiblingOf(out, const NodeId('grp'));

      // Locate the copy's path leaf and its topology.
      final copyLeaf = copy.walkSubtree().whereType<PathNode>().single;
      final topology = copyLeaf.path.anchors.map((a) => a.id).toSet();

      final track = out.defaultAnimation!.tracksFor(copyLeaf.id).pathTrack();
      expect(track, isNotNull,
          reason: 'the copy carries its own remapped path track');
      for (final k in track!.keys) {
        expect(k.value.anchors.keys.toSet(), topology,
            reason: 'copy keyframe at t=${k.t} poses ids outside its topology');
      }
    });

    test('animating the copy leaves the original evaluated output identical',
        () {
      final d = _animatedGroupDoc();
      final leafId = const NodeId('leaf');
      final baseline =
          evaluate(d, [const AnimationMix(AnimationId('anim'), 0.5)])
              .byPath[const ScenePath(NodeId('leaf'))]!;

      final out = NodeOps.duplicateSubtree(d, const NodeId('grp'));
      final copyLeaf = _nextSiblingOf(out, const NodeId('grp'))
          .walkSubtree()
          .whereType<PathNode>()
          .single;

      // Key a fresh rotation on the COPY leaf, then evaluate: the original leaf
      // must be untouched, which is only true because the ids are disjoint.
      final anim = out.defaultAnimation!;
      final withCopySpin = anim.copyWith(tracks: <NodeId, TrackSet>{
        ...anim.tracks,
        copyLeaf.id: TrackSet({
          ...anim.tracksFor(copyLeaf.id).byKey,
          const PropertyKey(PropKey.rotation): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: 3.14159),
          ]),
        }),
      });
      final mutated = out.copyWith(animations: [
        for (final a in out.animations) a.id == anim.id ? withCopySpin : a,
      ]);

      final again =
          evaluate(mutated, [const AnimationMix(AnimationId('anim'), 0.5)])
              .byPath[ScenePath(leafId)]!;
      _expectAffineClose(again.world, baseline.world, 1e-12);
    });

    test('a 2-level group duplicates whole', () {
      final d = _animatedGroupDoc();
      final out = NodeOps.duplicateSubtree(d, const NodeId('grp'));
      final copy = _nextSiblingOf(out, const NodeId('grp'));
      expect(_subtreeNodeIds(copy).length,
          _subtreeNodeIds(d.nodeIndex[const NodeId('grp')]!).length);
      // The copy really is a 2-level group with an inner group and a path leaf.
      expect(copy, isA<GroupNode>());
      expect((copy as GroupNode).children.whereType<GroupNode>(), isNotEmpty);
    });

    test('fills and strokes keep their PaintIds by decision', () {
      final d = _animatedGroupDoc();
      final out = NodeOps.duplicateSubtree(d, const NodeId('grp'));
      final copyLeaf = _nextSiblingOf(out, const NodeId('grp'))
          .walkSubtree()
          .whereType<PathNode>()
          .single;
      expect(copyLeaf.fills.single.id.v, 'p-fill');
      expect(copyLeaf.strokes.single.id.v, 'p-stroke');
    });

    test('the root cannot be duplicated', () {
      final d = _animatedGroupDoc();
      expect(() => NodeOps.duplicateSubtree(d, const NodeId('root')),
          throwsArgumentError);
    });

    test('a RAW preserved track on the copy addresses the copy\'s anchors', () {
      // A track this build cannot type rides through in TrackSet.unknownKeys.
      // Copied verbatim it would be the last shared-id path between original
      // and copy — invisible to decode's orphan repair, which only inspects
      // typed PathTracks, and therefore permanent across save and reload.
      final d = _rawTrackDoc();
      final out = NodeOps.duplicateSubtree(d, const NodeId('grp'));
      final copyLeaf = _nextSiblingOf(out, const NodeId('grp'))
          .walkSubtree()
          .whereType<PathNode>()
          .single;
      final copyAnchors = copyLeaf.path.anchors.map((a) => a.id.v).toSet();

      final raw = out.defaultAnimation!.tracksFor(copyLeaf.id).unknownKeys;
      expect(raw.keys, contains('wobble'));
      final keys =
          ((raw['wobble']! as Map<String, Object?>)['keys']! as List<Object?>);
      final posed =
          ((keys.single as Map<String, Object?>)['v']! as Map<String, Object?>);

      expect(posed.keys.toSet(), copyAnchors,
          reason: 'the raw track still poses the ORIGINAL anchor ids');
      expect(posed.keys, isNot(contains('l0')));
      // The subject id inside a value string is remapped too, and everything
      // the substitution does not recognise survives untouched.
      expect((raw['wobble']! as Map<String, Object?>)['kind'], 'wobble');
      expect((raw['wobble']! as Map<String, Object?>)['anchor'],
          copyLeaf.path.anchors.first.id.v);

      // ...and the ORIGINAL's raw track is not disturbed.
      final origRaw =
          out.defaultAnimation!.tracksFor(const NodeId('leaf')).unknownKeys;
      expect(
          ((origRaw['wobble']! as Map<String, Object?>)['keys']!
                  as List<Object?>)
              .length,
          1);
      expect((origRaw['wobble']! as Map<String, Object?>)['anchor'], 'l0');
    });
  });

  group('Document.nodeIndex is derived, never memoised', () {
    test('every read rebuilds it, so ops hoist it into a local', () {
      // docs/v3/08 §4 names "storing anything derived on Document (id index,
      // cached AABBs…)" as the antipattern, so this getter must stay a fresh
      // walk — the fix for its O(n·m) use in NodeOps was call-site hoisting,
      // not a cache field, and the doc comment now says so.
      final d = _threeSquareDoc();
      expect(identical(d.nodeIndex, d.nodeIndex), isFalse);
      expect(d.nodeIndex.keys.map((k) => k.v).toSet(), {'root', 'A', 'B', 'C'});
    });
  });

  group('NodeOps.setVisible / setLocked', () {
    test('setVisible writes the one field and is idempotent', () {
      final d = _threeSquareDoc();
      final out = NodeOps.setVisible(d, const NodeId('A'), false);
      final a = out.nodeIndex[const NodeId('A')]!;
      expect(a.visible, isFalse);
      // Nothing else moved: B and C keep their identity and their flags.
      expect(out.nodeIndex[const NodeId('B')]!.visible, isTrue);

      // Idempotent: setting the value it already holds returns the same doc.
      expect(identical(NodeOps.setVisible(out, const NodeId('A'), false), out),
          isTrue);
    });

    test('setLocked writes the one field and is idempotent', () {
      final d = _threeSquareDoc();
      final out = NodeOps.setLocked(d, const NodeId('B'), true);
      expect(out.nodeIndex[const NodeId('B')]!.locked, isTrue);
      // Locked is editor-only: the evaluated scene is byte-identical.
      expect(_digest(evaluate(out, const <AnimationMix>[]), const NodeId('B')),
          _digest(evaluate(d, const <AnimationMix>[]), const NodeId('B')));
      expect(identical(NodeOps.setLocked(out, const NodeId('B'), true), out),
          isTrue);
    });

    test('an unknown node throws for both', () {
      final d = _threeSquareDoc();
      expect(() => NodeOps.setVisible(d, const NodeId('nope'), false),
          throwsArgumentError);
      expect(() => NodeOps.setLocked(d, const NodeId('nope'), true),
          throwsArgumentError);
    });

    test('setOpacity writes the one field and is idempotent', () {
      final d = _threeSquareDoc();
      final out = NodeOps.setOpacity(d, const NodeId('A'), 0.25);
      expect(out.nodeIndex[const NodeId('A')]!.opacity, 0.25);
      // One node's own value: the siblings are untouched, and nothing derived
      // was written anywhere — the PRODUCT is the evaluator's, per frame.
      expect(out.nodeIndex[const NodeId('B')]!.opacity, 1.0);
      expect(identical(NodeOps.setOpacity(out, const NodeId('A'), 0.25), out),
          isTrue);
    });

    test('setOpacity clamps at the mutation, and rejects NaN', () {
      final d = _threeSquareDoc();
      // An authored 1.7 is a bad write and is clamped here, at the moment it is
      // made. That is deliberately NOT the same rule as the evaluator's clamp
      // on a *sampled* value, where an easing curve may legitimately overshoot.
      expect(
          NodeOps.setOpacity(d, const NodeId('A'), 1.7)
              .nodeIndex[const NodeId('A')]!
              .opacity,
          1.0);
      expect(
          NodeOps.setOpacity(d, const NodeId('A'), -3.0)
              .nodeIndex[const NodeId('A')]!
              .opacity,
          0.0);
      expect(() => NodeOps.setOpacity(d, const NodeId('A'), double.nan),
          throwsArgumentError);
      expect(() => NodeOps.setOpacity(d, const NodeId('nope'), 0.5),
          throwsArgumentError);
    });

    test('opacity is a PRODUCT down the ancestor chain (AC-2.2.5)', () {
      // The rule the layers panel claims and the inspector now authors: a group
      // at 0.5 holding a child at 0.5 renders the child at 0.25. Asserted on the
      // evaluated scene, because a derived "effective opacity" stored anywhere
      // is the docs/v3/08 §4 antipattern this test exists to keep unnecessary.
      var d = _reparentDoc();
      d = NodeOps.setOpacity(d, const NodeId('g1'), 0.5);
      d = NodeOps.setOpacity(d, const NodeId('leaf'), 0.5);

      final scene = evaluate(d, const <AnimationMix>[]);
      final leaf = scene.byPath[const ScenePath(NodeId('leaf'))];
      expect(leaf, isNotNull);
      expect(leaf!.worldOpacity, closeTo(0.25, 1e-12));

      // And the authored values are each still their own 0.5 — the product is
      // computed, never written back onto either node.
      expect(d.nodeIndex[const NodeId('g1')]!.opacity, 0.5);
      expect(d.nodeIndex[const NodeId('leaf')]!.opacity, 0.5);
    });

    test('setTrim writes the one field, clamps each channel, and is idempotent',
        () {
      final d = _threeSquareDoc();
      final out = NodeOps.setTrim(
          d, const NodeId('A'), const PathTrim(start: 0.2, end: 0.8));
      final a = out.nodeIndex[const NodeId('A')]! as PathNode;
      expect(a.trim.start, 0.2);
      expect(a.trim.end, 0.8);
      expect(a.trim.offset, 0.0);
      // One node's own value: the siblings keep the full (default) trim.
      expect(
          (out.nodeIndex[const NodeId('B')]! as PathNode).trim, PathTrim.full);

      // Idempotent: writing the trim it already holds returns the same doc.
      expect(
          identical(
              NodeOps.setTrim(
                  out, const NodeId('A'), const PathTrim(start: 0.2, end: 0.8)),
              out),
          isTrue);

      // Out-of-range fractions clamp at the mutation, each channel independently
      // — an authored 1.7 / -0.3 is a bad write (as opacity/width are clamped).
      final clamped = NodeOps.setTrim(d, const NodeId('A'),
          const PathTrim(start: -0.3, end: 1.7, offset: 2.0));
      final ct = (clamped.nodeIndex[const NodeId('A')]! as PathNode).trim;
      expect(ct.start, 0.0);
      expect(ct.end, 1.0);
      expect(ct.offset, 1.0);
    });

    test(
        'setTrim renders the window, and end<=start renders nothing (no throw)',
        () {
      final d = _threeSquareDoc();
      // A half reveal of a closed square opens it and reveals ~half the arc.
      final half = NodeOps.setTrim(
          d, const NodeId('A'), const PathTrim(start: 0.0, end: 0.5));
      final scene = evaluate(half, const <AnimationMix>[]);
      final geo = scene.byPath[const ScenePath(NodeId('A'))]!.geometry!;
      expect(geo.closed, isFalse,
          reason: 'a partial reveal of a closed path cannot be filled');
      expect(geo.anchors, isNotEmpty);

      // end <= start renders empty geometry — never a throw, never a null deref.
      final empty = NodeOps.setTrim(
          d, const NodeId('A'), const PathTrim(start: 0.8, end: 0.3));
      final emptyScene = evaluate(empty, const <AnimationMix>[]);
      expect(emptyScene.byPath[const ScenePath(NodeId('A'))]!.geometry!.anchors,
          isEmpty);
    });

    test('setTrim refuses an unknown node and a non-PathNode', () {
      final d = _threeSquareDoc();
      expect(() => NodeOps.setTrim(d, const NodeId('nope'), PathTrim.full),
          throwsArgumentError);
      // 'root' is a GroupNode — a group has no trim (AC-8.1.10 is per-PathNode).
      expect(() => NodeOps.setTrim(d, const NodeId('root'), PathTrim.full),
          throwsArgumentError);
    });

    test('a hidden group hides every descendant regardless of their own flag',
        () {
      // group 'g' wraps a visible leaf; hiding g must hide the leaf (AC-2.2.4).
      final d = Document(
        id: 'doc',
        name: 't',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
          GroupNode(id: const NodeId('g'), name: 'g', children: [
            _square('leaf', const Vec2(0, 0)),
          ]),
        ]),
      );
      final out = NodeOps.setVisible(d, const NodeId('g'), false);
      final scene = evaluate(out, const <AnimationMix>[]);
      expect(
          scene.byPath[const ScenePath(NodeId('leaf'))]!.worldVisible, isFalse,
          reason: 'worldVisible ANDs over ancestors — a hidden group wins');
    });
  });

  group('NodeOps.deleteNodes', () {
    test('removes the subtree AND every track keyed inside it', () {
      final d = _reparentDoc(animated: true);
      expect(d.animations.single.tracks.keys.map((k) => k.v),
          containsAll(<String>['leaf', 'solo']));

      // `leaf` lives inside `g1`, so deleting the GROUP must take the child's
      // tracks with it — the case a `tracks.remove(id)` would miss.
      final out = NodeOps.deleteNodes(d, const [NodeId('g1')]);

      expect(out.nodeIndex[const NodeId('g1')], isNull);
      expect(out.nodeIndex[const NodeId('leaf')], isNull,
          reason: 'the whole subtree goes, not just the group node');
      expect(out.animations.single.tracks.containsKey(const NodeId('leaf')),
          isFalse,
          reason: 'a descendant track left behind is an invisible orphan that '
              'survives every save and reload');
      expect(out.animations.single.tracks.containsKey(const NodeId('solo')),
          isTrue,
          reason: 'an untouched node keeps every keyframe it had');

      // Untouched siblings still evaluate exactly as they did.
      final before = evaluate(d, const <AnimationMix>[]);
      final after = evaluate(out, const <AnimationMix>[]);
      expect(_digest(after, const NodeId('solo')),
          _digest(before, const NodeId('solo')));
    });

    test('the ORIGINAL document is untouched — undo has something to restore',
        () {
      final d = _reparentDoc(animated: true);
      NodeOps.deleteNodes(d, const [NodeId('g1')]);
      expect(d.nodeIndex[const NodeId('leaf')], isNotNull);
      expect(
          d.animations.single.tracks.containsKey(const NodeId('leaf')), isTrue);
    });

    test('deleting a node with NO tracks returns the same animation instance',
        () {
      final d = _reparentDoc(animated: true);
      final out = NodeOps.deleteNodes(d, const [NodeId('g2')]);
      expect(identical(out.animations.single, d.animations.single), isTrue,
          reason: 'nothing matched, so nothing is rebuilt');
    });

    test('an overlapping selection — a group AND its own child — is not an '
        'error and deletes once', () {
      final d = _reparentDoc(animated: true);
      final out =
          NodeOps.deleteNodes(d, const [NodeId('g1'), NodeId('leaf')]);
      expect(out.nodeIndex[const NodeId('g1')], isNull);
      expect(out.nodeIndex[const NodeId('leaf')], isNull);
      expect(out.root.children.map((c) => c.id.v), ['g2', 'solo']);
    });

    test('several unrelated subtrees go in ONE call — one undo entry upstream',
        () {
      final d = _threeSquareDoc();
      final out = NodeOps.deleteNodes(d, const [NodeId('A'), NodeId('C')]);
      expect(out.root.children.map((c) => c.id.v), ['B']);
    });

    test('an UnknownNode IS deletable — it is un-editable, not immortal', () {
      final d = Document(
        id: 'doc',
        name: 't',
        artboard: const Vec2(400, 400),
        root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
          _square('A', Vec2.zero),
          const UnknownNode(
              id: NodeId('future'),
              name: 'Mesh from a newer editor',
              rawType: 'mesh',
              raw: <String, Object?>{'type': 'mesh', 'id': 'future'}),
        ]),
      );
      final out = NodeOps.deleteNodes(d, const [NodeId('future')]);
      expect(out.root.children.map((c) => c.id.v), ['A'],
          reason: 'the raw blob goes with the node, so the save round-trips '
              'exactly what the screen shows');
    });

    test('an empty list, the root, and an unknown id each throw', () {
      final d = _threeSquareDoc();
      expect(() => NodeOps.deleteNodes(d, const []), throwsArgumentError);
      expect(() => NodeOps.deleteNodes(d, const [NodeId('root')]),
          throwsArgumentError);
      expect(() => NodeOps.deleteNodes(d, const [NodeId('nope')]),
          throwsArgumentError);
    });

    test('a bad id in the list leaves NOTHING half-deleted', () {
      final d = _threeSquareDoc();
      expect(() => NodeOps.deleteNodes(d, const [NodeId('A'), NodeId('nope')]),
          throwsArgumentError);
      // The op is Document -> Document, so `d` cannot have been touched — the
      // check that matters is that validation ran before the first removal and
      // no partially-edited document was ever returned.
      expect(d.root.children.map((c) => c.id.v), ['A', 'B', 'C']);
    });
  });

  group('NodeOps.reorderChild', () {
    test('splices the child list without touching the moved transform', () {
      final d = _threeSquareDoc(); // root children: [A, B, C]
      // Move C (index 2) to the front (index 0): [C, A, B].
      final out = NodeOps.reorderChild(d, const NodeId('root'), 2, 0);
      expect(out.root.children.map((c) => c.id.v).toList(), ['C', 'A', 'B']);
      // The moved node's transform is byte-identical — a reorder is not a move.
      expect(out.nodeIndex[const NodeId('C')]!.transform,
          d.nodeIndex[const NodeId('C')]!.transform);
    });

    test('newIndex is clamped into the child list', () {
      final d = _threeSquareDoc();
      // Drop A (index 0) far past the end -> pins to the last slot: [B, C, A].
      final out = NodeOps.reorderChild(d, const NodeId('root'), 0, 99);
      expect(out.root.children.map((c) => c.id.v).toList(), ['B', 'C', 'A']);
    });

    test('a move to the same index is an idempotent no-op', () {
      final d = _threeSquareDoc();
      expect(identical(NodeOps.reorderChild(d, const NodeId('root'), 1, 1), d),
          isTrue);
    });

    test('an out-of-range oldIndex, unknown parent, or non-group parent throws',
        () {
      final d = _threeSquareDoc();
      expect(() => NodeOps.reorderChild(d, const NodeId('root'), 5, 0),
          throwsArgumentError);
      expect(() => NodeOps.reorderChild(d, const NodeId('nope'), 0, 1),
          throwsArgumentError);
      // 'A' is a leaf PathNode, not a group.
      expect(() => NodeOps.reorderChild(d, const NodeId('A'), 0, 0),
          throwsArgumentError);
    });
  });

  group('property: duplicate cannot perturb the original', () {
    test('evaluate(original) is unchanged for 50 random trees', () {
      final rng = math.Random(20260722);
      for (var trial = 0; trial < 50; trial++) {
        final d = _randomDoc(rng, trial);
        // Pick a random non-root node to duplicate.
        final candidates = d.walk().where((n) => n.id != d.root.id).toList();
        final target = candidates[rng.nextInt(candidates.length)].id;

        final originalIds =
            d.walk().map((n) => n.id).where((id) => id != d.root.id).toSet();
        final mix = [AnimationMix(d.defaultAnimationId!, rng.nextDouble())];
        final before = evaluate(d, mix);

        final out = NodeOps.duplicateSubtree(d, target);
        final after = evaluate(out, mix);

        for (final id in originalIds) {
          expect(_digest(after, id), _digest(before, id),
              reason:
                  'trial $trial: duplicating ${target.v} perturbed ${id.v}');
        }
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Digests and matchers
// ---------------------------------------------------------------------------

/// A comparable fingerprint of a node's evaluated world + geometry.
String _digest(Scene scene, NodeId id) {
  final rn = scene.byPath[ScenePath(id)];
  if (rn == null) return 'absent';
  final w = rn.world;
  final geo = rn.geometry?.anchors
          .map((a) => '${a.position.x},${a.position.y};'
              '${a.inTangent.x},${a.inTangent.y};'
              '${a.outTangent.x},${a.outTangent.y}')
          .join('|') ??
      'none';
  return '${w.a},${w.b},${w.c},${w.d},${w.tx},${w.ty} '
      '${rn.worldOpacity} ${rn.worldVisible} [$geo]';
}

/// Posed anchor positions only — geometry is node-local, so a reparent must
/// leave it byte-identical whatever the playhead.
String _anchorDigest(PathData? geometry) => geometry == null
    ? 'none'
    : geometry.anchors.map((a) => '${a.position.x},${a.position.y}').join('|');

void _expectAffineClose(Affine actual, Affine expected, double eps) {
  expect(actual.a, closeTo(expected.a, eps));
  expect(actual.b, closeTo(expected.b, eps));
  expect(actual.c, closeTo(expected.c, eps));
  expect(actual.d, closeTo(expected.d, eps));
  expect(actual.tx, closeTo(expected.tx, eps));
  expect(actual.ty, closeTo(expected.ty, eps));
}

Set<NodeId> _subtreeNodeIds(Node n) => n.walkSubtree().map((x) => x.id).toSet();

Set<AnchorId> _subtreeAnchorIds(Node n) => {
      for (final x in n.walkSubtree())
        if (x is PathNode)
          for (final a in x.path.anchors) a.id,
    };

Node _nextSiblingOf(Document d, NodeId id) {
  for (final node in d.walk()) {
    if (node is GroupNode) {
      final k = node.children.indexWhere((c) => c.id == id);
      if (k >= 0) return node.children[k + 1];
    }
  }
  throw StateError('no sibling for ${id.v}');
}

extension _Walk on Node {
  Iterable<Node> walkSubtree() sync* {
    yield this;
    final self = this;
    if (self is GroupNode) {
      for (final c in self.children) {
        yield* c.walkSubtree();
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

/// A unit square in local space, offset by [origin], with corner anchors.
PathNode _square(String id, Vec2 origin, {Vec2? position}) => PathNode(
      id: NodeId(id),
      name: id,
      transform: Transform2(position: position ?? Vec2.zero),
      path: PathData(closed: true, anchors: [
        Anchor(id: AnchorId('$id-0'), position: origin),
        Anchor(id: AnchorId('$id-1'), position: origin + const Vec2(20, 0)),
        Anchor(id: AnchorId('$id-2'), position: origin + const Vec2(20, 20)),
        Anchor(id: AnchorId('$id-3'), position: origin + const Vec2(0, 20)),
      ]),
    );

/// Root holding three squares: A at origin, B translated +100x, C translated
/// +200x. A and B are the group candidates; C is the untouched control.
Document _threeSquareDoc() => Document(
      id: 'doc',
      name: 'three',
      artboard: const Vec2(450.2, 250.4),
      root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
        _square('A', const Vec2(0, 0)),
        _square('B', const Vec2(0, 0), position: const Vec2(100, 0)),
        _square('C', const Vec2(0, 0), position: const Vec2(200, 0)),
      ]),
    );

/// root
///  ├ g1  (translate + rotate + non-uniform scale)  ── leaf (own transform)
///  ├ g2  (a different transform; optionally collapsed to scale 0)
///  └ solo (a bare leaf, not a group)
///
/// [animated] adds an animation that keys NON-transform channels on `leaf`
/// (opacity + path) and a transform channel on `solo`, so a mix at a non-zero
/// playhead is a genuinely animated evaluation of this document while `leaf`
/// itself stays reparentable. [positionTrackOnLeaf] and [rotationTrackOnG1] are
/// the two shapes `reparent` must refuse.
Document _reparentDoc({
  bool collapseG2 = false,
  bool animated = false,
  bool positionTrackOnLeaf = false,
  bool rotationTrackOnG1 = false,
}) {
  final leaf = _square('leaf', const Vec2(0, 0), position: const Vec2(10, 5));
  final solo =
      _square('solo', const Vec2(0, 0), position: const Vec2(300, 100));

  final tracks = <NodeId, TrackSet>{};
  if (animated) {
    tracks[const NodeId('leaf')] = TrackSet({
      const PropertyKey(PropKey.opacity): ScalarTrack([
        const Keyframe(t: 0.0, value: 1.0),
        const Keyframe(t: 1.0, value: 0.2),
      ]),
      const PropertyKey(PropKey.path): PathTrack([
        Keyframe(t: 0.0, value: _poseOf(leaf, Vec2.zero)),
        Keyframe(t: 1.0, value: _poseOf(leaf, const Vec2(7, -4))),
      ]),
    });
    tracks[const NodeId('solo')] = TrackSet({
      const PropertyKey(PropKey.position): Vec2Track([
        const Keyframe(t: 0.0, value: Vec2(300, 100)),
        const Keyframe(t: 1.0, value: Vec2(60, 210)),
      ]),
    });
  }
  if (positionTrackOnLeaf) {
    tracks[const NodeId('leaf')] = TrackSet({
      const PropertyKey(PropKey.position): Vec2Track([
        const Keyframe(t: 0.0, value: Vec2(10, 5)),
        const Keyframe(t: 1.0, value: Vec2(140, 90)),
      ]),
    });
  }
  if (rotationTrackOnG1) {
    tracks[const NodeId('g1')] = TrackSet({
      const PropertyKey(PropKey.rotation): ScalarTrack([
        const Keyframe(t: 0.0, value: 0.7),
        const Keyframe(t: 1.0, value: 2.4),
      ]),
    });
  }

  final animation =
      Animation(id: const AnimationId('anim'), name: 'Main', tracks: tracks);
  return Document(
    id: 'doc',
    name: 'reparent',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
      GroupNode(
        id: const NodeId('g1'),
        name: 'g1',
        transform: const Transform2(
          position: Vec2(120, 40),
          rotation: 0.7,
          scale: Vec2(1.5, 0.8),
        ),
        children: [leaf],
      ),
      GroupNode(
        id: const NodeId('g2'),
        name: 'g2',
        transform: Transform2(
          position: const Vec2(-30, 90),
          rotation: -0.4,
          scale: collapseG2 ? Vec2.zero : const Vec2(0.6, 1.3),
          skewX: 0.2,
        ),
        children: const [],
      ),
      solo,
    ]),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}

/// [node]'s rest anchors, every position shifted by [by].
PathPose _poseOf(PathNode node, Vec2 by) => PathPose({
      for (final a in node.path.anchors)
        a.id: AnchorPose(a.position + by, a.inTangent, a.outTangent),
    });

/// The same document with the teleporting `position` track added to `leaf`
/// after the fact — which is exactly the document the rest-pose-only solve used
/// to produce for an already-animated node.
Document _withLeafPositionTrack(Document d) {
  final anim = d.defaultAnimation!;
  final updated = anim.copyWith(tracks: <NodeId, TrackSet>{
    ...anim.tracks,
    const NodeId('leaf'): TrackSet({
      const PropertyKey(PropKey.position): Vec2Track([
        const Keyframe(t: 0.0, value: Vec2(10, 5)),
        const Keyframe(t: 1.0, value: Vec2(140, 90)),
      ]),
    }),
  });
  return d.copyWith(animations: [
    for (final a in d.animations) a.id == anim.id ? updated : a,
  ]);
}

/// root ─ anc (rotation-keyed) ─┬ g1 ─ leaf
///                              └ g2
///
/// `anc` is the lowest common ancestor of both parents, so its animation
/// cancels out of `newParent⁻¹ · oldParent` and must NOT block the reparent.
Document _sharedAnimatedAncestorDoc() {
  final animation = Animation(
    id: const AnimationId('anim'),
    name: 'Main',
    tracks: {
      const NodeId('anc'): TrackSet({
        const PropertyKey(PropKey.rotation): ScalarTrack([
          const Keyframe(t: 0.0, value: 0.0),
          const Keyframe(t: 1.0, value: 1.9),
        ]),
      }),
    },
  );
  return Document(
    id: 'doc',
    name: 'shared-ancestor',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
      GroupNode(
        id: const NodeId('anc'),
        name: 'anc',
        transform: const Transform2(position: Vec2(70, 30)),
        children: [
          GroupNode(
            id: const NodeId('g1'),
            name: 'g1',
            transform: const Transform2(
                position: Vec2(12, 8), rotation: 0.5, scale: Vec2(1.3, 0.7)),
            children: [
              _square('leaf', const Vec2(0, 0), position: const Vec2(10, 5)),
            ],
          ),
          GroupNode(
            id: const NodeId('g2'),
            name: 'g2',
            transform: const Transform2(
                position: Vec2(-20, 60), rotation: -0.9, scale: Vec2(0.8, 1.1)),
            children: const [],
          ),
        ],
      ),
    ]),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}

/// root ─ dead (scale 0) ─ trapped. The singularity belongs to the ANCESTOR.
Document _collapsedAncestorDoc() => Document(
      id: 'doc',
      name: 'collapsed',
      artboard: const Vec2(450.2, 250.4),
      root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
        GroupNode(
          id: const NodeId('dead'),
          name: 'dead',
          transform: const Transform2(position: Vec2(80, 60), scale: Vec2.zero),
          children: [
            _square('trapped', const Vec2(0, 0), position: const Vec2(10, 5)),
          ],
        ),
      ]),
    );

/// A node whose OWN rest transform flattens it: scale (1, 0).
Document _flatNodeDoc() => Document(
      id: 'doc',
      name: 'flat',
      artboard: const Vec2(450.2, 250.4),
      root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
        PathNode(
          id: const NodeId('flat'),
          name: 'flat',
          transform: const Transform2(
              position: Vec2(40, 25), scale: Vec2(1, 0), rotation: 0.0),
          path: PathData(closed: true, anchors: const [
            Anchor(id: AnchorId('f0'), position: Vec2(0, 0)),
            Anchor(id: AnchorId('f1'), position: Vec2(20, 0)),
            Anchor(id: AnchorId('f2'), position: Vec2(20, 20)),
          ]),
        ),
        GroupNode(id: const NodeId('g'), name: 'g', children: const <Node>[]),
      ]),
    );

/// A node authored with an unbounded [rotation] and a large [skewX], plus an
/// identity group to reparent it into.
Document _spinDoc({required double rotation, required double skewX}) =>
    Document(
      id: 'doc',
      name: 'spin',
      artboard: const Vec2(450.2, 250.4),
      root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
        GroupNode(id: const NodeId('g1'), name: 'g1', children: [
          PathNode(
            id: const NodeId('spun'),
            name: 'spun',
            transform: Transform2(
              position: const Vec2(33, 21),
              rotation: rotation,
              skewX: skewX,
            ),
            path: PathData(closed: true, anchors: const [
              Anchor(id: AnchorId('s0'), position: Vec2(0, 0)),
              Anchor(id: AnchorId('s1'), position: Vec2(10, 0)),
              Anchor(id: AnchorId('s2'), position: Vec2(10, 10)),
            ]),
          ),
        ]),
        GroupNode(id: const NodeId('g2'), name: 'g2', children: const <Node>[]),
      ]),
    );

/// One open segment that bulges well past its endpoints:
/// P0 (0,0), P1 (0,90), P2 (90,30), P3 (90,0).
Document _bulgingCurveDoc() => Document(
      id: 'doc',
      name: 'curve',
      artboard: const Vec2(450.2, 250.4),
      root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
        PathNode(
          id: const NodeId('curve'),
          name: 'curve',
          path: PathData(closed: false, anchors: const [
            Anchor(
                id: AnchorId('c0'),
                position: Vec2(0, 0),
                outTangent: Vec2(0, 90),
                kind: AnchorKind.smooth),
            Anchor(
                id: AnchorId('c1'),
                position: Vec2(90, 0),
                inTangent: Vec2(0, 30),
                kind: AnchorKind.smooth),
          ]),
        ),
      ]),
    );

/// `grp > leaf`, where `leaf`'s TrackSet carries a track this build cannot type
/// — preserved raw in `unknownKeys` — that names the leaf's anchor ids.
Document _rawTrackDoc() {
  final leaf = PathNode(
    id: const NodeId('leaf'),
    name: 'leaf',
    path: PathData(closed: true, anchors: const [
      Anchor(id: AnchorId('l0'), position: Vec2(0, 0)),
      Anchor(id: AnchorId('l1'), position: Vec2(20, 0)),
      Anchor(id: AnchorId('l2'), position: Vec2(20, 20)),
    ]),
  );
  final animation = Animation(
    id: const AnimationId('anim'),
    name: 'Main',
    tracks: {
      const NodeId('leaf'): const TrackSet({}, unknownKeys: {
        'wobble': {
          'kind': 'wobble',
          'anchor': 'l0',
          'keys': [
            {
              't': 0.0,
              'v': {
                'l0': [1, 2],
                'l1': [3, 4],
                'l2': [5, 6],
              },
            },
          ],
        },
      }),
    },
  );
  return Document(
    id: 'doc',
    name: 'raw',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
      GroupNode(id: const NodeId('grp'), name: 'grp', children: [leaf]),
    ]),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}

/// A 2-level group `grp > inner > leaf` under root, with a path track and a
/// rotation track keyed on the leaf, plus fills/strokes carrying PaintIds.
Document _animatedGroupDoc() {
  final leaf = PathNode(
    id: const NodeId('leaf'),
    name: 'leaf',
    transform: const Transform2(position: Vec2(15, 15), rotation: 0.3),
    path: PathData(closed: true, anchors: const [
      Anchor(id: AnchorId('l0'), position: Vec2(0, 0)),
      Anchor(id: AnchorId('l1'), position: Vec2(30, 0)),
      Anchor(id: AnchorId('l2'), position: Vec2(30, 30)),
      Anchor(id: AnchorId('l3'), position: Vec2(0, 30)),
    ]),
    fills: const [
      Fill(id: PaintId('p-fill'), paint: SolidPaint(Rgba(1, 0, 0)))
    ],
    strokes: const [
      Stroke(id: PaintId('p-stroke'), paint: SolidPaint(Rgba(0, 0, 1))),
    ],
  );

  final grp = GroupNode(
    id: const NodeId('grp'),
    name: 'grp',
    transform: const Transform2(position: Vec2(40, 20), rotation: 0.2),
    children: [
      GroupNode(
        id: const NodeId('inner'),
        name: 'inner',
        transform:
            const Transform2(position: Vec2(5, 5), scale: Vec2(1.2, 1.2)),
        children: [leaf],
      ),
    ],
  );

  final pose0 = PathPose({
    for (final a in leaf.path.anchors)
      a.id: AnchorPose(a.position, a.inTangent, a.outTangent),
  });
  final pose1 = PathPose({
    for (final a in leaf.path.anchors)
      a.id:
          AnchorPose(a.position + const Vec2(3, 3), a.inTangent, a.outTangent),
  });

  final animation = Animation(
    id: const AnimationId('anim'),
    name: 'Main',
    tracks: {
      const NodeId('leaf'): TrackSet({
        const PropertyKey(PropKey.rotation): ScalarTrack([
          const Keyframe(t: 0.0, value: 0.0),
          const Keyframe(t: 1.0, value: 1.2),
        ]),
        const PropertyKey(PropKey.path): PathTrack([
          Keyframe(t: 0.0, value: pose0),
          Keyframe(t: 1.0, value: pose1),
        ]),
      }),
    },
  );

  return Document(
    id: 'doc',
    name: 'animated',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: [grp]),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}

/// A random small tree (depth <= 3) with one animation keying a few nodes.
Document _randomDoc(math.Random rng, int seed) {
  var nodeCounter = 0;
  var anchorCounter = 0;
  final tracked = <NodeId, TrackSet>{};

  Node makeLeaf() {
    final id = NodeId('n${seed}_${nodeCounter++}');
    final anchors = <Anchor>[
      for (var k = 0; k < 3 + rng.nextInt(2); k++)
        Anchor(
          id: AnchorId('a${seed}_${anchorCounter++}'),
          position: Vec2(rng.nextDouble() * 100, rng.nextDouble() * 100),
          outTangent: Vec2(rng.nextDouble() * 10, rng.nextDouble() * 10),
        ),
    ];
    final leaf = PathNode(
      id: id,
      name: id.v,
      transform: Transform2(
        position: Vec2(rng.nextDouble() * 50, rng.nextDouble() * 50),
        rotation: rng.nextDouble() * 2,
        scale: Vec2(0.5 + rng.nextDouble(), 0.5 + rng.nextDouble()),
      ),
      path: PathData(anchors: anchors, closed: rng.nextBool()),
    );
    if (rng.nextBool()) {
      tracked[id] = TrackSet({
        const PropertyKey(PropKey.rotation): ScalarTrack([
          const Keyframe(t: 0.0, value: 0.0),
          Keyframe(t: 1.0, value: rng.nextDouble() * 6),
        ]),
      });
    }
    return leaf;
  }

  Node makeNode(int depth) {
    if (depth <= 0 || rng.nextBool()) return makeLeaf();
    final id = NodeId('g${seed}_${nodeCounter++}');
    return GroupNode(
      id: id,
      name: id.v,
      transform: Transform2(
        position: Vec2(rng.nextDouble() * 40, rng.nextDouble() * 40),
        rotation: rng.nextDouble(),
      ),
      children: [
        for (var k = 0; k < 1 + rng.nextInt(3); k++) makeNode(depth - 1),
      ],
    );
  }

  final children = [for (var k = 0; k < 2 + rng.nextInt(2); k++) makeNode(3)];
  final animation = Animation(
    id: AnimationId('anim$seed'),
    name: 'Main',
    tracks: tracked,
  );
  return Document(
    id: 'doc$seed',
    name: 'rand',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: NodeId('root$seed'), name: 'Root', children: children),
    animations: [animation],
    defaultAnimationId: animation.id,
  );
}
