import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/state/command.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:drawing_animation_tool/app/features/inspector/widgets/inspector_panel.dart';
import 'package:drawing_animation_tool/app/features/layers/widgets/layers_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M2 phase 4 — the Layers panel (F2.2, docs/v3/05 §2 and §4.5).
///
/// The panel owns the tree, z-order, rename, visibility and lock. These tests
/// pin the seven acceptance criteria of F2.2 and the one rule underneath all of
/// them: **z-order IS child-list order**, so reordering is a splice of the one
/// authoritative list and no derived order array exists to desync (AC-2.2.2).
void main() {
  const Vec2 artboard = Vec2(400, 400);

  /// A closed square, `[origin, origin+s]²`, with a hittable fill.
  PathNode square(
    String id,
    Vec2 origin,
    double s, {
    bool locked = false,
    bool visible = true,
    double opacity = 1.0,
    Vec2 position = Vec2.zero,
  }) =>
      PathNode(
        id: NodeId(id),
        name: id,
        locked: locked,
        visible: visible,
        opacity: opacity,
        transform: Transform2(position: position),
        path: PathData(
          anchors: [
            Anchor(id: AnchorId('$id-0'), position: origin),
            Anchor(id: AnchorId('$id-1'), position: origin + Vec2(s, 0)),
            Anchor(id: AnchorId('$id-2'), position: origin + Vec2(s, s)),
            Anchor(id: AnchorId('$id-3'), position: origin + Vec2(0, s)),
          ],
          closed: true,
        ),
        fills: [
          Fill(
              id: PaintId('$id-fill'),
              paint: const SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0))),
        ],
      );

  ({MemoryProjectStore store, String id}) seed(List<Node> children) {
    final base = Document.create(name: 'Sketch', artboard: artboard);
    final doc = base
        .copyWith(
          root: GroupNode(
              id: base.root.id, name: base.root.name, children: children),
        )
        .bumpRev();
    return (
      store: MemoryProjectStore({doc.id: jsonEncode(doc.toJson())}),
      id: doc.id,
    );
  }

  ProviderContainer containerFor(MemoryProjectStore store) => ProviderContainer(
        overrides: [projectStoreProvider.overrideWithValue(store)],
      );

  /// A node from a newer editor: preserved verbatim, refused by every typed op
  /// (AC-1.2.4).
  UnknownNode mystery(String id) => UnknownNode(
        id: NodeId(id),
        name: id,
        rawType: 'bone',
        raw: <String, Object?>{'id': id, 'type': 'bone', 'name': id},
      );

  /// **Drag row [from] onto row [to] with a real pointer**, releasing at
  /// [fraction] of the target row's height.
  ///
  /// F2.2's headline interaction had no gesture test at all: every "drag"
  /// assertion in this file called `controller.run(ReorderChildCommand(...))`
  /// directly, so the drop handler's branch selection — the very thing that was
  /// wrong — was never executed. `fraction` picks the drop zone: the top band
  /// reorders in front of the row, the middle of a group row drops *inside* it.
  Future<void> dragRowOnto(
    WidgetTester tester,
    String from,
    String to, {
    double fraction = 0.5,
  }) async {
    final grip = find.byKey(Key('layer-drag-$from'));
    expect(grip, findsOneWidget,
        reason: 'row "$from" must offer a drag grip to be draggable at all');
    final rect = tester.getRect(find.byKey(ValueKey<String>('layer-row-$to')));
    final drop = Offset(rect.center.dx, rect.top + rect.height * fraction);

    final gesture = await tester.startGesture(tester.getCenter(grip));
    await tester.pump(const Duration(milliseconds: 20));
    // Two moves: the first lifts the drag out of the touch slop, the second
    // settles on the drop zone so `onMove` has computed it before the release.
    await gesture.moveTo(Offset(drop.dx, drop.dy + 24));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(drop);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String id,
      {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(ValueKey<String>('layer-row-$id')));
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  /// A shortcut, pressed with nothing but the keyboard.
  ///
  /// No canvas click first: the shell's own `FocusScope` holds focus from the
  /// first frame (docs/v3/05 §5), so selecting rows and pressing the key is the
  /// whole gesture — and a canvas click would clear the selection the shortcut
  /// is about to act on.
  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  List<String> childrenOf(Document d, NodeId parent) =>
      (d.nodeIndex[parent]! as GroupNode).children.map((n) => n.id.v).toList();

  Widget harness(ProviderContainer container, String id) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  Document docOf(ProviderContainer c, String id) =>
      c.read(documentControllerProvider(id)).requireValue;

  Future<Document> reload(MemoryProjectStore store, String id) async =>
      Document.fromJson(
          jsonDecode((await store.load(id))!) as Map<String, Object?>);

  /// A three-level tree:
  ///   root
  ///    ├ back      (index 0, back-most)
  ///    └ outer     (index 1)
  ///        ├ inner (index 0)
  ///        │   └ leaf
  ///        └ mid   (index 1)
  ///
  /// `outer` and `inner` carry real transforms so a reparent has something to
  /// preserve.
  List<Node> nestedTree() => [
        square('back', Vec2.zero, 40),
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
              children: [
                square('leaf', Vec2.zero, 30, position: const Vec2(4, 6))
              ],
            ),
            square('mid', Vec2.zero, 25, position: const Vec2(60, 10)),
          ],
        ),
      ];

  // --- AC-2.2.1 — the tree renders reversed ---------------------------------

  testWidgets(
      'a 3-level nested document renders REVERSED — top of the list is the '
      'front-most node (AC-2.2.1)', (tester) async {
    final s = seed(nestedTree());
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layers-panel')), findsOneWidget);

    double yOf(String id) =>
        tester.getTopLeft(find.byKey(Key('layer-name-$id'))).dy;

    // Root children are [back, outer]; displayed front-first that is
    // outer, then its children, then back.
    expect(yOf('outer'), lessThan(yOf('back')),
        reason: 'child index 1 paints in front of index 0, so it is on top');

    // Inside `outer`, children are [inner, mid]; `mid` is front-most.
    expect(yOf('mid'), lessThan(yOf('inner')),
        reason: 'each level is reversed, not only the root');

    // Nesting still reads as nesting: `leaf` sits under its group `inner`.
    expect(yOf('inner'), lessThan(yOf('leaf')));

    // ...and the whole `outer` subtree stays above `back`.
    expect(yOf('leaf'), lessThan(yOf('back')));
  });

  // --- AC-2.2.2 — reorder is a children splice ------------------------------

  testWidgets(
      'drag-reorder splices the children list and paint order follows in the '
      'same frame — no derived z-index (AC-2.2.2)', (tester) async {
    final s = seed([
      square('a', Vec2.zero, 30),
      square('b', const Vec2(40, 0), 30),
      square('c', const Vec2(80, 0), 30),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final controller = c.read(documentControllerProvider(s.id).notifier);
    final root = docOf(c, s.id).root.id;

    // Paint order before: children order exactly.
    expect(docOf(c, s.id).root.children.map((n) => n.id.v).toList(),
        ['a', 'b', 'c']);

    // Drag 'a' (back-most, index 0) to the front slot (index 2). This is the
    // command the panel's drop handler issues.
    await controller.run(ReorderChildCommand(root, 0, 2));
    await tester.pumpAndSettle();

    final after = docOf(c, s.id);
    expect(after.root.children.map((n) => n.id.v).toList(), ['b', 'c', 'a'],
        reason: 'the edit is a splice of the one authoritative child list');

    // The evaluated scene agrees — draw order IS child order, back to front.
    final drawn = evaluate(after, const <AnimationMix>[])
        .drawOrder
        .map((n) => n.path.nodeId.v)
        .where((v) => v != after.root.id.v)
        .toList();
    expect(drawn, ['b', 'c', 'a'],
        reason: 'paint order follows the splice with nothing else to update');

    // The panel redisplays it reversed, in the same frame.
    double yOf(String id) =>
        tester.getTopLeft(find.byKey(Key('layer-name-$id'))).dy;
    expect(yOf('a'), lessThan(yOf('c')));
    expect(yOf('c'), lessThan(yOf('b')));

    // Reordering moved no node: 'a' still holds its original transform.
    expect(after.nodeIndex[const NodeId('a')]!.transform,
        docOf(c, s.id).nodeIndex[const NodeId('a')]!.transform);
  });

  // --- AC-2.1.4 — reparent across groups is world-preserving ----------------

  testWidgets(
      'dropping a layer into a DIFFERENT group reparents it without moving it '
      'on screen (AC-2.1.4, docs/v3/05 §4.5)', (tester) async {
    final s = seed(nestedTree());
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final controller = c.read(documentControllerProvider(s.id).notifier);
    const leaf = ScenePath(NodeId('leaf'));

    final before =
        evaluate(docOf(c, s.id), const <AnimationMix>[]).byPath[leaf]!.world;

    // leaf: inner -> outer. Both carry rotation and non-uniform scale, so a
    // non-world-preserving implementation would visibly teleport it.
    await controller
        .run(const ReparentCommand(NodeId('leaf'), NodeId('outer'), 0));
    await tester.pumpAndSettle();

    final moved = docOf(c, s.id);
    final after = evaluate(moved, const <AnimationMix>[]).byPath[leaf]!.world;

    expect(after.a, closeTo(before.a, 1e-9));
    expect(after.b, closeTo(before.b, 1e-9));
    expect(after.c, closeTo(before.c, 1e-9));
    expect(after.d, closeTo(before.d, 1e-9));
    expect(after.tx, closeTo(before.tx, 1e-9));
    expect(after.ty, closeTo(before.ty, 1e-9));

    // It really did change parents in the tree.
    final outer = moved.nodeIndex[const NodeId('outer')]! as GroupNode;
    expect(outer.children.map((n) => n.id.v), contains('leaf'));
    final inner = moved.nodeIndex[const NodeId('inner')]! as GroupNode;
    expect(inner.children.map((n) => n.id.v), isNot(contains('leaf')));
  });

  // --- AC-2.2.3 — rename keeps the NodeId -----------------------------------

  testWidgets('renaming a layer changes name and NOT the NodeId (AC-2.2.3)',
      (tester) async {
    final s = seed([square('sq', Vec2.zero, 40)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final controller = c.read(documentControllerProvider(s.id).notifier);
    final idsBefore = docOf(c, s.id).walk().map((n) => n.id.v).toSet();

    await controller.run(const RenameNodeCommand(NodeId('sq'), 'Cog'));
    await tester.pumpAndSettle();

    final after = docOf(c, s.id);
    expect(after.nodeIndex[const NodeId('sq')]!.name, 'Cog');
    expect(after.walk().map((n) => n.id.v).toSet(), idsBefore,
        reason: 'a rename mints no id and drops none');

    // The panel shows the new name against the same row identity.
    expect((tester.widget(find.byKey(const Key('layer-name-sq'))) as Text).data,
        'Cog');
  });

  // --- AC-2.2.4 / AC-2.2.5 — visibility ANDs, opacity multiplies ------------

  testWidgets(
      'the eye toggle on a group hides every descendant — worldVisible is an '
      'AND over ancestors (AC-2.2.4)', (tester) async {
    final s = seed(nestedTree());
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // Tap the group's eye toggle — the panel's real wiring, not the op.
    await tester.tap(find.byKey(const Key('layer-visible-outer')));
    await tester.pumpAndSettle();

    final doc = docOf(c, s.id);
    expect(doc.nodeIndex[const NodeId('outer')]!.visible, isFalse);
    // The descendants' own `visible` is untouched and irrelevant...
    expect(doc.nodeIndex[const NodeId('leaf')]!.visible, isTrue);

    // ...because the evaluator ANDs down the chain.
    final scene = evaluate(doc, const <AnimationMix>[]);
    expect(scene.byPath[const ScenePath(NodeId('leaf'))]!.worldVisible, isFalse,
        reason:
            'a hidden group hides descendants regardless of their own flag');
    expect(scene.byPath[const ScenePath(NodeId('mid'))]!.worldVisible, isFalse);
    // A sibling outside the hidden group is unaffected.
    expect(scene.byPath[const ScenePath(NodeId('back'))]!.worldVisible, isTrue);
  });

  test('opacity 0.5 inside a group at 0.5 renders at 0.25 (AC-2.2.5)', () {
    final doc = Document(
      id: 'doc',
      name: 'opacity',
      artboard: artboard,
      root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
        GroupNode(
          id: const NodeId('half'),
          name: 'half',
          opacity: 0.5,
          children: [square('leaf', Vec2.zero, 20, opacity: 0.5)],
        ),
      ]),
    );

    final scene = evaluate(doc, const <AnimationMix>[]);
    expect(scene.byPath[const ScenePath(NodeId('leaf'))]!.worldOpacity,
        closeTo(0.25, 1e-12),
        reason: 'worldOpacity is a PRODUCT over the ancestor chain');
  });

  // --- AC-2.2.6 — a locked row is not selectable ----------------------------

  testWidgets('tapping a LOCKED row does not select it (AC-2.2.6)',
      (tester) async {
    final s = seed([
      square('open', Vec2.zero, 30),
      square('shut', const Vec2(60, 0), 30, locked: true),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    Set<ScenePath> selection() =>
        c.read(editorControllerProvider).selectedNodes;

    // The unlocked row selects, through the SAME slice the canvas reads.
    await tester.tap(find.byKey(const ValueKey<String>('layer-row-open')));
    await tester.pumpAndSettle();
    expect(selection(), {const ScenePath(NodeId('open'))});

    // The locked row refuses, leaving the previous selection alone.
    await tester.tap(find.byKey(const ValueKey<String>('layer-row-shut')));
    await tester.pumpAndSettle();
    expect(selection(), {const ScenePath(NodeId('open'))},
        reason: 'a locked layer is not selectable from the panel either');

    // Locked is a hit-test gate only — the evaluator never reads it, so
    // playback is untouched.
    final scene = evaluate(docOf(c, s.id), const <AnimationMix>[]);
    expect(scene.byPath[const ScenePath(NodeId('shut'))]!.worldVisible, isTrue);
  });

  testWidgets('selecting on the canvas lights the layers row — one slice',
      (tester) async {
    final s = seed([square('sq', Vec2.zero, 30)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // Write selection the way the canvas does; the panel reads the same set.
    c
        .read(editorControllerProvider.notifier)
        .selectNode(const ScenePath(NodeId('sq')));
    await tester.pumpAndSettle();

    expect(
        c.read(editorControllerProvider).selectedNodes.map((p) => p.nodeId.v),
        {'sq'});
    expect(find.byKey(const Key('layer-name-sq')), findsOneWidget);
  });

  // --- AC-2.2.7 — authored flags persist, ephemeral state does not ----------

  testWidgets(
      'locked and visible survive a reload; selection, viewport and playhead '
      'are never written (AC-2.2.7)', (tester) async {
    final s = seed([square('sq', Vec2.zero, 40)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // Toggle both flags through the panel.
    await tester.tap(find.byKey(const Key('layer-lock-sq')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('layer-visible-sq')));
    await tester.pumpAndSettle();

    // Then move every scrap of ephemeral state.
    c.read(editorControllerProvider.notifier)
      ..selectNode(const ScenePath(NodeId('sq')))
      ..panBy(const Vec2(33, -17))
      ..zoomAround(const Vec2(120, 90), 1.4)
      ..commitPlayhead(0.42);
    await tester.pumpAndSettle();

    // Authored flags round-trip through storage.
    final persisted = await reload(s.store, s.id);
    final node = persisted.nodeIndex[const NodeId('sq')]!;
    expect(node.locked, isTrue, reason: 'locked is authored and persisted');
    expect(node.visible, isFalse, reason: 'visible is authored and persisted');

    // Ephemeral state is not in the bytes — the legacy defect that made
    // documents unloadable.
    final raw = (await s.store.load(s.id))!;
    expect(raw, isNot(contains('viewportTransform')));
    expect(raw, isNot(contains('selectedNodes')));
    expect(raw, isNot(contains('selectedAnchors')));
    expect(raw, isNot(contains('playhead')));
    expect(raw, isNot(contains('selectedKeyframe')));
  });

  // --- F2.2's headline gesture, driven by a real pointer --------------------

  testWidgets(
      'DRAGGING a row onto the top of a sibling reorders the children list '
      '(AC-2.2.2, docs/v3/05 §4.5 step 2)', (tester) async {
    final s = seed([
      square('a', Vec2.zero, 30),
      square('b', const Vec2(40, 0), 30),
      square('c', const Vec2(80, 0), 30),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final root = docOf(c, s.id).root.id;
    expect(childrenOf(docOf(c, s.id), root), ['a', 'b', 'c']);

    // Display order is c, b, a (front-most first). Drop `a` on the TOP band of
    // `c`'s row — "in front of c", i.e. the front-most slot.
    await dragRowOnto(tester, 'a', 'c', fraction: 0.15);

    expect(childrenOf(docOf(c, s.id), root), ['b', 'c', 'a'],
        reason: 'a real drag reaches the same splice the command does');

    // The transform is untouched: a reorder is not a move (AC-2.2.2).
    expect(docOf(c, s.id).nodeIndex[const NodeId('a')]!.transform,
        const Transform2());

    // ...and the bottom band of the same row is the other side of it.
    await dragRowOnto(tester, 'a', 'c', fraction: 0.85);
    expect(childrenOf(docOf(c, s.id), root), ['b', 'a', 'c'],
        reason: 'dropping below a row places the layer behind it');
  });

  testWidgets(
      'DRAGGING a root layer onto a SIBLING GROUP row drops it INSIDE the '
      'group (docs/v3/05 §4.5 step 3)', (tester) async {
    // The defect: `_drop` tested `dragged.parent == target.parent` before
    // `target.isGroup`, and in a fresh document every layer is a root child —
    // so dragging a layer onto a group reordered the root instead, and an empty
    // top-level group could never be filled by any gesture at all.
    final s = seed([
      square('alpha', Vec2.zero, 30),
      GroupNode(
        id: const NodeId('box'),
        name: 'box',
        transform: const Transform2(
            position: Vec2(90, 30), rotation: 0.6, scale: Vec2(1.4, 0.7)),
        children: [square('inbox', Vec2.zero, 20)],
      ),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    const alpha = ScenePath(NodeId('alpha'));
    final before =
        evaluate(docOf(c, s.id), const <AnimationMix>[]).byPath[alpha]!.world;

    // Middle of the group row == "inside".
    await dragRowOnto(tester, 'alpha', 'box', fraction: 0.65);

    final after = docOf(c, s.id);
    expect(childrenOf(after, const NodeId('box')), contains('alpha'),
        reason: 'dropping onto a group row must put the layer IN the group');
    expect(childrenOf(after, after.root.id), isNot(contains('alpha')));

    // ...and the reparent is world-preserving: it does not visually move
    // (AC-2.1.4), even though `box` is rotated and non-uniformly scaled.
    final world = evaluate(after, const <AnimationMix>[]).byPath[alpha]!.world;
    expect(world.a, closeTo(before.a, 1e-9));
    expect(world.d, closeTo(before.d, 1e-9));
    expect(world.tx, closeTo(before.tx, 1e-9));
    expect(world.ty, closeTo(before.ty, 1e-9));
  });

  testWidgets('an EMPTY top-level group can be filled by dragging into it',
      (tester) async {
    final s = seed([
      square('loose', Vec2.zero, 30),
      const GroupNode(id: NodeId('empty'), name: 'empty', children: []),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    await dragRowOnto(tester, 'loose', 'empty', fraction: 0.65);

    expect(childrenOf(docOf(c, s.id), const NodeId('empty')), ['loose']);
  });

  testWidgets(
      'the TOP band of a group row reorders next to it instead of into it',
      (tester) async {
    final s = seed([
      square('loose', Vec2.zero, 30),
      const GroupNode(id: NodeId('grp'), name: 'grp', children: []),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // Display order is grp, loose. Dropping `loose` on grp's top band means
    // "in front of grp", which is a root reorder, not a reparent.
    await dragRowOnto(tester, 'loose', 'grp', fraction: 0.1);

    final doc = docOf(c, s.id);
    expect(childrenOf(doc, const NodeId('grp')), isEmpty,
        reason: 'the reorder band must not drop the layer inside');
    expect(childrenOf(doc, doc.root.id), ['grp', 'loose']);
  });

  testWidgets(
      'dropping a GROUP onto its own descendant is refused before it can '
      'highlight — no assertion, no lost document', (tester) async {
    final s = seed(nestedTree());
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final before = docOf(c, s.id);

    // `leaf` is a grandchild of `outer`. NodeOps refuses the cycle by design,
    // and `assert(false)` on a legal gesture would throw an unhandled
    // AssertionError in debug and show no snackbar at all (docs/v3/08 §1).
    await dragRowOnto(tester, 'outer', 'leaf', fraction: 0.65);

    expect(tester.takeException(), isNull,
        reason: 'a refused-by-design op is not a programming error');
    expect(childrenOf(docOf(c, s.id), before.root.id),
        childrenOf(before, before.root.id));
    expect(childrenOf(docOf(c, s.id), const NodeId('inner')), ['leaf'],
        reason: 'the tree is exactly as it was');
  });

  // --- A locked row rejects selection AND drag (docs/v3/05 §4.5) ------------

  testWidgets('a LOCKED row has no drag grip and cannot be reordered',
      (tester) async {
    final s = seed([
      square('free', Vec2.zero, 30),
      square('bolted', const Vec2(40, 0), 30, locked: true),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layer-drag-bolted')), findsNothing,
        reason: 'docs/v3/05 §4.5: locked rows reject selection AND drag');
    expect(find.byKey(const Key('layer-drag-locked-bolted')), findsOneWidget,
        reason: 'the grip is replaced by an explanation, not simply removed');

    // ...while a HIDDEN row still reorders — the adjacent sentence in the spec
    // gives the two states opposite treatment.
    await tester.tap(find.byKey(const Key('layer-visible-free')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layer-drag-free')), findsOneWidget);

    final root = docOf(c, s.id).root.id;
    await dragRowOnto(tester, 'free', 'bolted', fraction: 0.15);
    expect(childrenOf(docOf(c, s.id), root), ['bolted', 'free'],
        reason: 'a hidden row still reorders');
  });

  testWidgets('a LOCKED group is not a drop target for its inside',
      (tester) async {
    final s = seed([
      square('loose', Vec2.zero, 30),
      GroupNode(
        id: const NodeId('vault'),
        name: 'vault',
        locked: true,
        children: [square('held', Vec2.zero, 20)],
      ),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // Dropping INTO a group splices that group's authored `children` — the same
    // protected edit the lock refuses everywhere else. The zone is simply not
    // offered, so the row never highlights as an "inside" target and the drop
    // reorders next to it instead of failing after the fact.
    await dragRowOnto(tester, 'loose', 'vault', fraction: 0.65);

    expect(childrenOf(docOf(c, s.id), const NodeId('vault')), ['held'],
        reason: 'nothing was added to the locked group');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an op that refuses a legal gesture SAYS SO and keeps the document — no '
      'assert, no unhandled async error (docs/v3/08 §1)', (tester) async {
    final s = seed([
      square('a', Vec2.zero, 30),
      square('between', const Vec2(40, 0), 30),
      square('c', const Vec2(80, 0), 30),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // `a` and `c` are siblings — the gate the panel can check cheaply — but
    // `between` sits between them, and `NodeOps.createGroup` refuses that by
    // design. The refusal must reach the user as a sentence: it used to reach
    // an `assert(false)` inside the catch, which threw an AssertionError out of
    // the future in debug and showed no snackbar at all.
    await tapRow(tester, 'a');
    await tapRow(tester, 'c', shift: true);
    await tester.tap(find.byKey(const Key('layers-group')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
        docOf(c, s.id).root.children.map((n) => n.id.v), ['a', 'between', 'c'],
        reason: 'a rejected edit leaves the document exactly as it was');
  });

  testWidgets('a LOCKED row cannot be renamed either', (tester) async {
    final s = seed([square('bolted', Vec2.zero, 30, locked: true)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey<String>('layer-row-bolted'));
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layer-rename-bolted')), findsNothing,
        reason: 'the lock protects the name as much as the child list');
    expect(docOf(c, s.id).nodeIndex[const NodeId('bolted')]!.name, 'bolted');
  });

  testWidgets(
      'lock INHERITS down the tree in the panel, as it does on the canvas '
      '(AC-2.2.6)', (tester) async {
    final s = seed([
      GroupNode(
        id: const NodeId('grp'),
        name: 'grp',
        locked: true,
        children: [square('kid', Vec2.zero, 30)],
      ),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // The canvas refuses to hit-test `kid` because lock inherits; the panel was
    // a bypass around exactly that, handing the inspector an editable form.
    await tester.tap(find.byKey(const ValueKey<String>('layer-row-kid')));
    await tester.pumpAndSettle();
    expect(c.read(editorControllerProvider).selectedNodes, isEmpty);
    expect(find.byKey(const Key('inspector-transform')), findsNothing);

    // It is not draggable either, and its own flag is still false — the row is
    // protected by its ancestor, not by a flag someone silently wrote to it.
    expect(find.byKey(const Key('layer-drag-kid')), findsNothing);
    expect(docOf(c, s.id).nodeIndex[const NodeId('kid')]!.locked, isFalse);

    // The child's own toggle is disabled while the ancestor holds the lock:
    // writing its own flag would change nothing the user can see.
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('layer-lock-kid')))
            .onPressed,
        isNull);

    // Unlock the group and the child is free again — one rule, one source.
    await tester.tap(find.byKey(const Key('layer-lock-grp')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('layer-drag-kid')), findsOneWidget,
        reason: 'the inherited lock lifts with its ancestor');
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('layer-lock-kid')))
            .onPressed,
        isNotNull);
  });

  // --- AC-1.2.4 — a node from a newer editor opens and survives -------------

  testWidgets(
      'an UnknownNode row offers no eye/lock toggle and is not selectable '
      '(AC-1.2.4)', (tester) async {
    final s = seed([square('known', Vec2.zero, 30), mystery('alien')]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('layer-name-alien')), findsOneWidget,
        reason: 'the node opens and is listed — it is preserved, not dropped');

    // `NodeOps.setVisible`/`setLocked` throw for an UnknownNode, so a toggle
    // here could only ever fail. It is not offered.
    expect(find.byKey(const Key('layer-visible-alien')), findsNothing);
    expect(find.byKey(const Key('layer-lock-alien')), findsNothing);
    expect(find.byKey(const Key('layer-unknown-alien')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('layer-row-alien')));
    await tester.pumpAndSettle();
    expect(c.read(editorControllerProvider).selectedNodes, isEmpty,
        reason: 'an unknown node is not editable, so it is not selectable');
    expect(tester.takeException(), isNull);

    // The known sibling still works, and the raw JSON round-trips untouched.
    await tester.tap(find.byKey(const Key('layer-visible-known')));
    await tester.pumpAndSettle();
    final persisted = await reload(s.store, s.id);
    expect(persisted.nodeIndex[const NodeId('alien')], isA<UnknownNode>());
  });

  // --- A1 / A2 — group and duplicate are reachable from the UI --------------

  testWidgets(
      'Cmd/Ctrl+G groups the multi-selection, and the header button does the '
      'same (docs/v3/05 §4.5 step 4, §5)', (tester) async {
    final s = seed([
      square('a', Vec2.zero, 30),
      square('b', const Vec2(40, 0), 30),
      square('c', const Vec2(80, 0), 30),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // Nothing selected: the affordance exists, is disabled, and says why.
    final groupButton = find.byKey(const Key('layers-group'));
    expect(groupButton, findsOneWidget);
    expect(tester.widget<IconButton>(groupButton).onPressed, isNull);
    expect(tester.widget<IconButton>(groupButton).tooltip, isNotNull);

    // Select two siblings the way a user does, then press the button.
    await tapRow(tester, 'a');
    await tapRow(tester, 'b', shift: true);
    expect(tester.widget<IconButton>(groupButton).onPressed, isNotNull);

    await tester.tap(groupButton);
    await tester.pumpAndSettle();

    final doc = docOf(c, s.id);
    final root = childrenOf(doc, doc.root.id);
    expect(root, hasLength(2), reason: 'a and b now live inside one group');
    final group = doc.root.children.whereType<GroupNode>().single;
    expect(group.children.map((n) => n.id.v), ['a', 'b']);
    expect(root.last, 'c', reason: 'the group takes the back-most member slot');

    // AC-2.1.3: grouping moves nothing.
    final world = evaluate(doc, const <AnimationMix>[])
        .byPath[const ScenePath(NodeId('a'))]!
        .world;
    expect(world.tx, closeTo(0, 1e-9));
    expect(world.ty, closeTo(0, 1e-9));
  });

  testWidgets('Cmd/Ctrl+G on an ungroupable selection SAYS SO', (tester) async {
    final s = seed(nestedTree());
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // `back` is a root child, `leaf` is two levels down: no shared parent.
    c.read(editorControllerProvider.notifier)
      ..selectNode(const ScenePath(NodeId('back')))
      ..addToSelection(const ScenePath(NodeId('leaf')));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('layers-group')))
            .onPressed,
        isNull);

    await pressCtrl(tester, LogicalKeyboardKey.keyG);

    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'a shortcut that silently does nothing reads as unbound');
    expect(tester.takeException(), isNull);
    // ...and nothing was grouped.
    expect(docOf(c, s.id).root.children.map((n) => n.id.v), ['back', 'outer']);
  });

  testWidgets(
      'Cmd/Ctrl+D duplicates the selected subtree, and ONE Ctrl+Z reverts it '
      '(docs/v3/05 §5, AC-2.1.5)', (tester) async {
    final s = seed(nestedTree());
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final idsBefore = docOf(c, s.id).walk().map((n) => n.id.v).toSet();

    await tapRow(tester, 'outer');
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('layers-duplicate')))
            .onPressed,
        isNotNull);

    await pressCtrl(tester, LogicalKeyboardKey.keyD);

    final duplicated = docOf(c, s.id).walk().map((n) => n.id.v).toSet();
    expect(duplicated.length, greaterThan(idsBefore.length),
        reason: 'Cmd/Ctrl+D is bound and reached DuplicateSubtreeCommand');
    expect(idsBefore.difference(duplicated), isEmpty);

    // ONE undo entry, however many ids were re-minted.
    await pressCtrl(tester, LogicalKeyboardKey.keyZ);

    expect(docOf(c, s.id).walk().map((n) => n.id.v).toSet(), idsBefore,
        reason: 'a duplicate-subtree undoes as ONE entry');
    expect(c.read(documentControllerProvider(s.id).notifier).canUndo, isFalse);
  });

  // --- The panel does not rebuild on a geometry-only edit (AC-13.3) ---------

  testWidgets(
      'a MOUNTED layers and inspector panel do not rebuild when an unrelated '
      'edit commits (AC-13.3, docs/v3/08 §2)', (tester) async {
    // The projection test below passes on a value comparison alone — and used
    // to pass while the mounted panel rebuilt on every commit anyway, because
    // the shell handed `document` to a body that rebuilt all four panels. Only
    // a widget-level counter can see that.
    final s = seed([square('sq', Vec2.zero, 30)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    c
        .read(editorControllerProvider.notifier)
        .selectNode(const ScenePath(NodeId('sq')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inspector-transform')), findsOneWidget);

    final layersBaseline = LayersPanel.debugBuildCount;
    final inspectorBaseline = InspectorPanel.debugBuildCount;
    final revBefore = docOf(c, s.id).rev;

    // A geometry-only commit: it mints a whole new Document and bumps rev.
    await c.read(documentControllerProvider(s.id).notifier).run(
        const MoveAnchorCommand(NodeId('sq'), AnchorId('sq-0'), Vec2(9, 9)));
    await tester.pumpAndSettle();

    expect(docOf(c, s.id).rev, greaterThan(revBefore),
        reason: 'the edit really did commit and re-emit the document');
    expect(LayersPanel.debugBuildCount, layersBaseline,
        reason: 'no name, flag or order changed — there is nothing to redraw');
    expect(InspectorPanel.debugBuildCount, inspectorBaseline,
        reason: "the selected node's Transform2 did not change either");
  });

  test(
      'an anchor move projects to an EQUAL LayersView — the panel has nothing '
      'to rebuild for (AC-13.3)', () {
    // The slice is value-projected, so a document mutation that changes only
    // geometry compares equal and notifies nobody. This is the structural
    // replacement for legacy 93 blind updateUI() call sites.
    final doc = Document(
      id: 'doc',
      name: 'x',
      artboard: artboard,
      root: GroupNode(id: const NodeId('root'), name: 'Root', children: [
        square('sq', Vec2.zero, 30),
      ]),
    );
    final moved = PathOps.moveAnchor(
        doc, const NodeId('sq'), const AnchorId('sq-0'), const Vec2(9, 9));

    expect(_layersViewOf(moved), _layersViewOf(doc),
        reason: 'names, flags, depth and order are all unchanged');

    // ...while a rename does change it, so the projection is not simply blind.
    final renamed = NodeOps.setName(doc, const NodeId('sq'), 'Cog');
    expect(_layersViewOf(renamed), isNot(_layersViewOf(doc)));
  });
}

/// Builds the same projection `layersViewProvider` does, without a container —
/// the provider is a one-line `.select` over exactly this.
Object _layersViewOf(Document d) => _LayersProbe(d.root);

/// Mirrors `LayersView.of` for the equality assertion above. Kept in the test so
/// the assertion is about *observable* projection behaviour (names, flags,
/// depth, order) rather than about importing the feature's private shape.
final class _LayersProbe {
  _LayersProbe(GroupNode root) : rows = _flatten(root);

  final List<String> rows;

  static List<String> _flatten(GroupNode root) {
    final out = <String>[];
    void walk(GroupNode g, int depth) {
      for (var i = g.children.length - 1; i >= 0; i--) {
        final c = g.children[i];
        out.add('${c.id.v}|${c.name}|$depth|$i|${c.visible}|${c.locked}');
        if (c is GroupNode) walk(c, depth + 1);
      }
    }

    walk(root, 0);
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is _LayersProbe &&
      other.rows.length == rows.length &&
      List.generate(rows.length, (i) => other.rows[i] == rows[i])
          .every((x) => x);

  @override
  int get hashCode => Object.hashAll(rows);
}
