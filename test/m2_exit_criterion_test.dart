import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
// `Animation` is ambiguous once Flutter is in scope (docs/v3/01 §10 names the
// core type), so it arrives under a prefix rather than shadowing Flutter's.
import 'package:anim_core/anim_core.dart' as core show Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/state/command.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, TextInputAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **The M2 exit criterion, as one end-to-end test.**
///
/// Load a real three-level document off the store, then reorder, reparent and
/// duplicate it through the same `Command` → `CommandStack` → `DocumentController`
/// → `ProjectStore` path the panels use — and assert the two properties the
/// milestone is defined by:
///
///  1. **The reparented node does not visually move.** `newLocal =
///     newParent.world⁻¹ · oldWorld` then `Affine.decompose`, so the evaluated
///     world matrix is stable to 1e-9 across a change of parent (AC-2.1.4).
///  2. **`duplicateSubtree` undoes as ONE entry**, however many `NodeId`s and
///     `AnchorId`s it re-minted, because the command produced one whole new
///     `Document` and the stack recorded exactly one snapshot before it
///     (docs/v3/04 §6).
///
/// Plus the regression that guards the whole three-way state split: **nothing
/// ephemeral is ever serialized** (docs/v3/01 §11, AC-2.2.7).
void main() {
  const Vec2 artboard = Vec2(450.2, 250.4);

  PathNode square(String id, {Vec2 position = Vec2.zero, double s = 30}) =>
      PathNode(
        id: NodeId(id),
        name: id,
        transform: Transform2(position: position),
        path: PathData(
          anchors: [
            Anchor(id: AnchorId('$id-0'), position: Vec2.zero),
            Anchor(id: AnchorId('$id-1'), position: Vec2(s, 0)),
            Anchor(id: AnchorId('$id-2'), position: Vec2(s, s)),
            Anchor(id: AnchorId('$id-3'), position: Vec2(0, s)),
          ],
          closed: true,
        ),
        fills: [
          Fill(
              id: PaintId('$id-fill'),
              paint: const SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0))),
        ],
      );

  /// root
  ///  ├ back                                    (index 0)
  ///  └ outer   translate+rotate+non-uniform    (index 1)
  ///      ├ inner  translate+rotate+scale       (index 0)
  ///      │   └ leaf   (its own transform)      — the node that must not move
  ///      └ mid                                 (index 1)
  ///
  /// `leaf` and `mid` are animated, so `duplicateSubtree` has real `TrackSet`
  /// entries to deep-copy and the undo has something substantial to reverse.
  ///
  /// **The `rotation` track lives on `mid`, not on `leaf`.** `NodeOps.reparent`
  /// refuses a *transform*-animated node by design — a rest-pose solve is
  /// overwritten by the track at every playhead, so the node would teleport, and
  /// per-keyframe rewriting lands with M4. `leaf` is the node this test
  /// reparents, so its animation is its **path** track, which reparent does not
  /// touch and which is the harder thing for `duplicateSubtree` to re-key
  /// anyway (every pose is addressed by `AnchorId`).
  Document buildNested() {
    final leaf = square('leaf', position: const Vec2(4, 6));
    final animation = core.Animation(
      id: const AnimationId('anim'),
      name: 'Main',
      tracks: {
        const NodeId('mid'): TrackSet({
          const PropertyKey(PropKey.rotation): ScalarTrack([
            const Keyframe(t: 0.0, value: 0.0),
            const Keyframe(t: 1.0, value: 1.2),
          ]),
        }),
        const NodeId('leaf'): TrackSet({
          const PropertyKey(PropKey.path): PathTrack([
            Keyframe(
                t: 0.0,
                value: PathPose({
                  for (final a in leaf.path.anchors)
                    a.id: AnchorPose(a.position, a.inTangent, a.outTangent),
                })),
            Keyframe(
                t: 1.0,
                value: PathPose({
                  for (final a in leaf.path.anchors)
                    a.id: AnchorPose(a.position + const Vec2(3, 3), a.inTangent,
                        a.outTangent),
                })),
          ]),
        }),
      },
    );

    return Document(
      id: 'm2-exit',
      name: 'M2 exit',
      artboard: artboard,
      rev: 1,
      root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
        square('back'),
        GroupNode(
          id: const NodeId('outer'),
          name: 'outer',
          transform: const Transform2(
              position: Vec2(120, 40), rotation: 0.7, scale: Vec2(1.5, 0.8)),
          children: [
            GroupNode(
              id: const NodeId('inner'),
              name: 'inner',
              transform: const Transform2(
                  position: Vec2(10, 5), rotation: -0.3, scale: Vec2(0.9, 1.4)),
              children: [leaf],
            ),
            square('mid', position: const Vec2(60, 10)),
          ],
        ),
      ]),
      animations: [animation],
      defaultAnimationId: animation.id,
    );
  }

  /// The evaluated world matrix of [id] at the rest pose.
  Affine worldOf(Document d, String id) =>
      evaluate(d, const <AnimationMix>[]).byPath[ScenePath(NodeId(id))]!.world;

  void expectAffineClose(Affine actual, Affine expected, double eps) {
    expect(actual.a, closeTo(expected.a, eps));
    expect(actual.b, closeTo(expected.b, eps));
    expect(actual.c, closeTo(expected.c, eps));
    expect(actual.d, closeTo(expected.d, eps));
    expect(actual.tx, closeTo(expected.tx, eps));
    expect(actual.ty, closeTo(expected.ty, eps));
  }

  int nodeCount(Document d) => d.walk().length;

  test(
      'M2 EXIT: a 3-level document reorders, reparents and duplicates — the '
      'reparented node does not move, and duplicate undoes as ONE entry',
      () async {
    // --- Load through the real store + controller ---------------------------
    final seeded = buildNested();
    final store = MemoryProjectStore({seeded.id: jsonEncode(seeded.toJson())});
    final c = ProviderContainer(
      overrides: [projectStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);

    final loaded = await c.read(documentControllerProvider(seeded.id).future);
    final controller = c.read(documentControllerProvider(seeded.id).notifier);
    Document doc() =>
        c.read(documentControllerProvider(seeded.id)).requireValue;

    // The document really is three levels deep and decoded intact.
    expect(loaded.nodeIndex[const NodeId('leaf')], isNotNull);
    expect(loaded.root.children.map((n) => n.id.v).toList(), ['back', 'outer']);
    expect(controller.canUndo, isFalse, reason: 'a fresh load has no history');

    // ======================================================================
    // 1. REORDER — a children splice; z-order IS child order (AC-2.2.2)
    // ======================================================================
    final leafWorldAtStart = worldOf(doc(), 'leaf');

    await controller.run(ReorderChildCommand(loaded.root.id, 0, 1));
    expect(doc().root.children.map((n) => n.id.v).toList(), ['outer', 'back'],
        reason: 'reorder is a splice of the one authoritative child list');

    // Paint order follows with nothing else to update — no derived z-index.
    final drawn = evaluate(doc(), const <AnimationMix>[])
        .drawOrder
        .map((n) => n.path.nodeId.v)
        .where((v) => v != 'root')
        .toList();
    expect(drawn.indexOf('outer'), lessThan(drawn.indexOf('back')));

    // Reordering a *sibling* moved nothing inside the other subtree.
    expectAffineClose(worldOf(doc(), 'leaf'), leafWorldAtStart, 1e-12);

    // ======================================================================
    // 2. REPARENT — world-preserving: the node does not move (AC-2.1.4)
    // ======================================================================
    final beforeReparent = worldOf(doc(), 'leaf');

    // leaf: inner -> outer. Both ancestors carry rotation and non-uniform
    // scale, so a non-world-preserving implementation teleports it visibly.
    await controller
        .run(const ReparentCommand(NodeId('leaf'), NodeId('outer'), 0));

    expectAffineClose(worldOf(doc(), 'leaf'), beforeReparent, 1e-9);

    // It genuinely changed parents rather than being left where it was.
    expect(
        (doc().nodeIndex[const NodeId('outer')]! as GroupNode)
            .children
            .map((n) => n.id.v),
        contains('leaf'));
    expect(
        (doc().nodeIndex[const NodeId('inner')]! as GroupNode)
            .children
            .map((n) => n.id.v),
        isNot(contains('leaf')));

    // ======================================================================
    // 3. DUPLICATE — one command, one entry, however many ids it re-mints
    // ======================================================================
    final beforeDuplicate = doc();
    final countBefore = nodeCount(beforeDuplicate);
    final idsBefore = beforeDuplicate.walk().map((n) => n.id.v).toSet();
    final undoDepthBefore = controller.canUndo;
    expect(undoDepthBefore, isTrue);

    // Duplicate the whole `outer` subtree — several nodes, many anchors, and a
    // path track whose poses must be re-keyed onto the copy's anchor ids.
    await controller.run(const DuplicateSubtreeCommand(NodeId('outer')));

    final duplicated = doc();
    expect(nodeCount(duplicated), greaterThan(countBefore),
        reason: 'the subtree really was copied');

    // Every id in the copy is fresh — no shared NodeId, no shared AnchorId.
    final idsAfter = duplicated.walk().map((n) => n.id.v).toSet();
    final minted = idsAfter.difference(idsBefore);
    expect(minted, isNotEmpty);
    expect(idsBefore.difference(idsAfter), isEmpty,
        reason: 'duplicating destroys nothing');

    // The copy carries its own tracks, posed on its own anchors.
    final copyRoot = duplicated.root.children
        .whereType<GroupNode>()
        .firstWhere((g) => minted.contains(g.id.v));
    final copyLeaf = copyRoot.walkAll().whereType<PathNode>().toList();
    expect(copyLeaf, isNotEmpty);

    // --- THE undo assertion: ONE entry, not one per re-minted id -----------
    final restore = await controller.undo();
    expect(restore, isNotNull);

    final afterUndo = doc();
    expect(nodeCount(afterUndo), countBefore,
        reason: 'ONE undo reverses the whole duplicate — every id it minted');
    expect(afterUndo.walk().map((n) => n.id.v).toSet(), idsBefore);

    // ...and the document is exactly the pre-duplicate one, including the
    // reparent that preceded it (undo stepped back exactly one command).
    expectAffineClose(worldOf(afterUndo, 'leaf'), beforeReparent, 1e-9);
    expect(
        (afterUndo.nodeIndex[const NodeId('outer')]! as GroupNode)
            .children
            .map((n) => n.id.v),
        contains('leaf'),
        reason: 'undo of the duplicate must not also undo the reparent');

    // Redo puts it back, still as one entry.
    await controller.redo();
    expect(nodeCount(doc()), greaterThan(countBefore));
  });

  // =========================================================================
  // The same criterion, performed BY HAND through the editor UI.
  // =========================================================================

  /// Everything above runs `controller.run(...)` directly. That is the right
  /// shape for asserting the *model* half of the criterion — and it is also how
  /// the milestone came to be unreachable for a human: `CreateGroupCommand` and
  /// `DuplicateSubtreeCommand` had **zero** call sites outside tests, so no
  /// gesture in the product could build a nested document, and the cross-parent
  /// reparent branch could never fire. This test is the criterion again, with a
  /// pointer and a keyboard and nothing else.
  group('through the UI', () {
    PathNode flat(String id, Vec2 at) => PathNode(
          id: NodeId(id),
          name: id,
          transform: Transform2(position: at),
          path: PathData(
            anchors: [
              Anchor(id: AnchorId('$id-0'), position: Vec2.zero),
              Anchor(id: AnchorId('$id-1'), position: const Vec2(20, 0)),
              Anchor(id: AnchorId('$id-2'), position: const Vec2(20, 20)),
              Anchor(id: AnchorId('$id-3'), position: const Vec2(0, 20)),
            ],
            closed: true,
          ),
          fills: [
            Fill(
                id: PaintId('$id-fill'),
                paint: const SolidPaint(Rgba(0.4, 0.6, 0.9, 1))),
          ],
        );

    ({MemoryProjectStore store, String id}) seedFlat() {
      final base = Document.create(name: 'By hand', artboard: artboard);
      final doc = base
          .copyWith(
            root: GroupNode(id: base.root.id, name: base.root.name, children: [
              flat('a', Vec2.zero),
              flat('b', const Vec2(60, 0)),
              flat('c', const Vec2(120, 0)),
            ]),
          )
          .bumpRev();
      return (
        store: MemoryProjectStore({doc.id: jsonEncode(doc.toJson())}),
        id: doc.id,
      );
    }

    Future<void> tapRow(WidgetTester tester, String id,
        {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.byKey(ValueKey<String>('layer-row-$id')));
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    Future<void> dragRowOnto(WidgetTester tester, String from, String to,
        {double fraction = 0.65}) async {
      final rect =
          tester.getRect(find.byKey(ValueKey<String>('layer-row-$to')));
      final drop = Offset(rect.center.dx, rect.top + rect.height * fraction);
      final gesture = await tester
          .startGesture(tester.getCenter(find.byKey(Key('layer-drag-$from'))));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(Offset(drop.dx, drop.dy + 24));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(drop);
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'M2 EXIT BY HAND: group → nest → reparent → duplicate → Ctrl+Z, with '
        'no call into the command layer', (tester) async {
      final s = seedFlat();
      final c = ProviderContainer(
        overrides: [projectStoreProvider.overrideWithValue(s.store)],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: EditorShell(projectId: s.id)),
      ));
      await tester.pumpAndSettle();

      Document doc() => c.read(documentControllerProvider(s.id)).requireValue;
      List<String> kids(NodeId parent) =>
          (doc().nodeIndex[parent]! as GroupNode)
              .children
              .map((n) => n.id.v)
              .toList();

      // --- 1. Group two of the three shapes (Cmd/Ctrl+G) -------------------
      await tapRow(tester, 'a');
      await tapRow(tester, 'b', shift: true);
      await pressCtrl(tester, LogicalKeyboardKey.keyG);

      final inner = doc().root.children.whereType<GroupNode>().single;
      expect(inner.children.map((n) => n.id.v), ['a', 'b']);
      expect(kids(doc().root.id), [inner.id.v, 'c']);

      // --- 2. Group again — the document is now three levels deep ----------
      await tapRow(tester, inner.id.v);
      await tapRow(tester, 'c', shift: true);
      await pressCtrl(tester, LogicalKeyboardKey.keyG);

      final outer = doc().root.children.whereType<GroupNode>().single;
      expect(outer.id, isNot(inner.id));
      expect(kids(outer.id), [inner.id.v, 'c']);
      expect(kids(inner.id), ['a', 'b'],
          reason: 'root > outer > inner > shapes is three levels of nesting');

      // --- 3. Give the inner group a real frame, from the inspector --------
      // Without a rotated, non-uniformly scaled destination, "does not visually
      // move" is not a claim about anything.
      await tapRow(tester, inner.id.v);
      await tester.enterText(find.byKey(const Key('inspector-rotation')), '35');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('inspector-scale-x')), '1.6');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // --- 4. Drag `c` out of `outer` and INTO `inner` ---------------------
      const cPath = ScenePath(NodeId('c'));
      final before = worldOf(doc(), 'c');

      await dragRowOnto(tester, 'c', inner.id.v);

      expect(kids(inner.id), contains('c'),
          reason: 'dropping onto a group row drops INTO the group');
      expect(kids(outer.id), isNot(contains('c')));
      expectAffineClose(
          evaluate(doc(), const <AnimationMix>[]).byPath[cPath]!.world,
          before,
          1e-9);

      // --- 5. Duplicate a subtree (Cmd/Ctrl+D), then undo it once ----------
      final idsBefore = doc().walk().map((n) => n.id.v).toSet();
      await tapRow(tester, inner.id.v);
      await pressCtrl(tester, LogicalKeyboardKey.keyD);

      final afterDuplicate = doc().walk().map((n) => n.id.v).toSet();
      expect(afterDuplicate.length, greaterThan(idsBefore.length + 2),
          reason: 'the whole subtree was copied, not just its root');
      expect(c.read(documentControllerProvider(s.id).notifier).undoLabel,
          'Duplicate',
          reason: 'the entry about to be undone is the duplicate itself');

      await pressCtrl(tester, LogicalKeyboardKey.keyZ);

      expect(doc().walk().map((n) => n.id.v).toSet(), idsBefore,
          reason: 'ONE Ctrl+Z reverts a duplicate-subtree as ONE entry');
      // The reparent that preceded it is still in place — undo stepped back
      // exactly one command.
      expect(kids(inner.id), contains('c'));
      expect(tester.takeException(), isNull);
    });
  });

  test(
      'M2 EXIT: the persisted JSON carries no ephemeral state — no viewport, '
      'no selection, no playhead (docs/v3/01 §11, AC-2.2.7)', () async {
    final seeded = buildNested();
    final store = MemoryProjectStore({seeded.id: jsonEncode(seeded.toJson())});
    final c = ProviderContainer(
      overrides: [projectStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);

    await c.read(documentControllerProvider(seeded.id).future);
    final controller = c.read(documentControllerProvider(seeded.id).notifier);

    // Move every scrap of ephemeral state, then force a real persisted write.
    c.read(editorControllerProvider.notifier)
      ..selectNode(const ScenePath(NodeId('leaf')))
      ..addToSelection(const ScenePath(NodeId('mid')))
      ..selectAnchor(const AnchorId('leaf-0'))
      ..panBy(const Vec2(33, -17))
      ..zoomAround(const Vec2(120, 90), 1.4)
      ..commitPlayhead(0.42);

    await controller.run(const RenameNodeCommand(NodeId('leaf'), 'Cog'));

    final raw = (await store.load(seeded.id))!;

    // The authored edit is there...
    expect(raw, contains('Cog'));

    // ...and not one byte of the ephemeral column is.
    for (final banned in const [
      'viewportTransform',
      'selectedNodes',
      'selectedAnchors',
      'selectedKeyframe',
      'playhead',
      'playing',
      'hover',
      'activeAnimation',
    ]) {
      expect(raw, isNot(contains(banned)),
          reason: '"$banned" is EditorState, and EditorState is never '
              'serialized — persisting it is what made legacy documents '
              'unloadable');
    }

    // The round trip still decodes, so the write is a real document.
    final reloaded = Document.fromJson(jsonDecode(raw) as Map<String, Object?>);
    expect(reloaded.nodeIndex[const NodeId('leaf')]!.name, 'Cog');
    expect(reloaded.animations, hasLength(1));
  });
}

extension _WalkAll on Node {
  /// This node and every descendant, pre-order.
  Iterable<Node> walkAll() sync* {
    yield this;
    final self = this;
    if (self is GroupNode) {
      for (final c in self.children) {
        yield* c.walkAll();
      }
    }
  }
}
