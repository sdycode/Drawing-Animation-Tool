import 'dart:convert';
import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// M2 phase 4 — the Transform2 inspector (F3.1, docs/v3/05 §2).
///
/// The inspector owns numeric/typed editing of the selected node's values. These
/// tests pin F3.1's criteria: every field writes through `SetTransformCommand`
/// as **one undo entry**, rotation is stored as **unbounded radians** behind a
/// degrees display (AC-3.1.2), a pivot edit leaves the untransformed geometry
/// alone (AC-3.1.3), and every field **releases focus on commit** so the next
/// `Cmd/Ctrl+Z` reaches the editor's undo rather than the browser's text-field
/// undo (docs/v3/05 §5).
void main() {
  const Vec2 artboard = Vec2(400, 400);

  PathNode square(String id) => PathNode(
        id: NodeId(id),
        name: id,
        path: PathData(
          anchors: const [
            Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
            Anchor(id: AnchorId('a1'), position: Vec2(40, 0)),
            Anchor(id: AnchorId('a2'), position: Vec2(40, 40)),
            Anchor(id: AnchorId('a3'), position: Vec2(0, 40)),
          ],
          closed: true,
        ),
        fills: const [
          Fill(
              id: PaintId('p-fill'),
              paint: SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0))),
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

  Widget harness(ProviderContainer container, String id) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  Document docOf(ProviderContainer c, String id) =>
      c.read(documentControllerProvider(id)).requireValue;

  Transform2 transformOf(ProviderContainer c, String id, String node) =>
      docOf(c, id).nodeIndex[NodeId(node)]!.transform;

  /// Pump the editor with one node already selected, so the inspector shows the
  /// transform editor rather than its summary state.
  Future<({ProviderContainer c, String id, MemoryProjectStore store})> open(
      WidgetTester tester) async {
    final s = seed([square('sq')]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();
    c
        .read(editorControllerProvider.notifier)
        .selectNode(const ScenePath(NodeId('sq')));
    await tester.pumpAndSettle();
    return (c: c, id: s.id, store: s.store);
  }

  /// Type into a field and commit it the way a user does — Enter.
  Future<void> commitField(
      WidgetTester tester, String fieldKey, String text) async {
    await tester.enterText(find.byKey(Key(fieldKey)), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  EditableText editableOf(WidgetTester tester, String fieldKey) =>
      tester.widget<EditableText>(find.descendant(
        of: find.byKey(Key(fieldKey)),
        matching: find.byType(EditableText),
      ));

  // --- AC-3.1.1 — every transform channel authors ---------------------------

  testWidgets(
      'position, scale and pivot fields each write Transform2 through a command '
      '(AC-3.1.1)', (tester) async {
    final t = await open(tester);
    expect(find.byKey(const Key('inspector-panel')), findsOneWidget);
    expect(find.byKey(const Key('inspector-transform')), findsOneWidget);

    await commitField(tester, 'inspector-position-x', '120');
    await commitField(tester, 'inspector-position-y', '-45.5');
    expect(transformOf(t.c, t.id, 'sq').position, const Vec2(120, -45.5));

    await commitField(tester, 'inspector-scale-x', '2.5');
    await commitField(tester, 'inspector-scale-y', '0.5');
    expect(transformOf(t.c, t.id, 'sq').scale, const Vec2(2.5, 0.5));

    await commitField(tester, 'inspector-pivot-x', '20');
    await commitField(tester, 'inspector-pivot-y', '20');
    expect(transformOf(t.c, t.id, 'sq').pivot, const Vec2(20, 20));

    // Composition order stays anim_core's — the panel wrote fields, and the
    // matrix is whatever `toAffine()` composes from them (golden-tested there).
    final expected = const Transform2(
      position: Vec2(120, -45.5),
      scale: Vec2(2.5, 0.5),
      pivot: Vec2(20, 20),
    ).toAffine();
    final actual = transformOf(t.c, t.id, 'sq').toAffine();
    expect(actual.a, closeTo(expected.a, 1e-12));
    expect(actual.d, closeTo(expected.d, 1e-12));
    expect(actual.tx, closeTo(expected.tx, 1e-12));
    expect(actual.ty, closeTo(expected.ty, 1e-12));
  });

  testWidgets('skewX is shown in degrees and stored in radians',
      (tester) async {
    final t = await open(tester);
    await commitField(tester, 'inspector-skewx', '30');
    expect(transformOf(t.c, t.id, 'sq').skewX, closeTo(math.pi / 6, 1e-12),
        reason: '30° is stored as radians, not as 30');
  });

  // --- AC-3.1.2 — rotation is unbounded radians -----------------------------

  testWidgets(
      'rotation past 360° stores UNBOUNDED radians — no wrap, no shortest-arc '
      '(AC-3.1.2)', (tester) async {
    final t = await open(tester);

    await commitField(tester, 'inspector-rotation', '720');
    final twoTurns = transformOf(t.c, t.id, 'sq').rotation;
    expect(twoTurns, closeTo(4 * math.pi, 1e-9));
    expect(twoTurns, greaterThan(2 * math.pi),
        reason: 'two full turns must not collapse into [0, 2π)');

    // The field reads the stored value back as degrees, still unwrapped.
    expect(editableOf(tester, 'inspector-rotation').controller.text, '720');

    // And the negative multi-turn case — legacy is 13.3's -12.5664.
    await commitField(tester, 'inspector-rotation', '-720');
    final reverse = transformOf(t.c, t.id, 'sq').rotation;
    expect(reverse, closeTo(-4 * math.pi, 1e-9));
    expect(reverse, lessThan(-2 * math.pi),
        reason: 'a reverse multi-turn spin is not normalised either');
  });

  // --- AC-3.1.3 — a pivot edit does not move the geometry -------------------

  testWidgets(
      'a pivot edit re-poses the node about the new pivot and leaves the '
      'untransformed geometry untouched (AC-3.1.3)', (tester) async {
    final t = await open(tester);

    List<Vec2> anchorsOf() =>
        (docOf(t.c, t.id).nodeIndex[const NodeId('sq')]! as PathNode)
            .path
            .anchors
            .map((a) => a.position)
            .toList();

    final before = anchorsOf();

    // Rotate first, so the pivot demonstrably matters to the composed matrix.
    await commitField(tester, 'inspector-rotation', '90');
    final worldOriginPivot = evaluate(docOf(t.c, t.id), const <AnimationMix>[])
        .byPath[const ScenePath(NodeId('sq'))]!
        .world;

    await commitField(tester, 'inspector-pivot-x', '20');
    await commitField(tester, 'inspector-pivot-y', '20');

    // The authored path — the untransformed geometry — is byte-identical.
    expect(anchorsOf(), before,
        reason: 'pivot is a transform field; it never rewrites PathData');

    // ...but the node is now posed about the new pivot, so the world matrix
    // genuinely changed. Pivot is not a no-op, it is a re-pose.
    final worldNewPivot = evaluate(docOf(t.c, t.id), const <AnimationMix>[])
        .byPath[const ScenePath(NodeId('sq'))]!
        .world;
    expect(
        (worldNewPivot.tx - worldOriginPivot.tx).abs() +
            (worldNewPivot.ty - worldOriginPivot.ty).abs(),
        greaterThan(1e-6),
        reason: 'rotating about a different pivot places the node differently');

    expect(transformOf(t.c, t.id, 'sq').pivot, const Vec2(20, 20));
  });

  // --- One field edit == one undo entry -------------------------------------

  testWidgets('one field commit is ONE undo entry, and undo reverts it',
      (tester) async {
    final t = await open(tester);
    final controller = t.c.read(documentControllerProvider(t.id).notifier);

    expect(controller.canUndo, isFalse, reason: 'a fresh open has no history');
    final original = transformOf(t.c, t.id, 'sq');

    await commitField(tester, 'inspector-position-x', '77');
    expect(transformOf(t.c, t.id, 'sq').position.x, 77);
    expect(controller.canUndo, isTrue);

    await controller.undo();
    await tester.pumpAndSettle();

    expect(transformOf(t.c, t.id, 'sq'), original,
        reason: 'undo restores the whole Transform2');
    expect(controller.canUndo, isFalse,
        reason: 'the edit was a single entry — Enter must not commit twice');

    // The field follows the document back.
    expect(editableOf(tester, 'inspector-position-x').controller.text, '0');
  });

  testWidgets('committing an unchanged value writes no undo entry',
      (tester) async {
    final t = await open(tester);
    final controller = t.c.read(documentControllerProvider(t.id).notifier);

    // Position starts at 0; retyping 0 and pressing Enter changes nothing, so
    // it must not leave an empty step in the history.
    await commitField(tester, 'inspector-position-x', '0');
    expect(controller.canUndo, isFalse);
  });

  // --- docs/v3/05 §5 — release focus on commit ------------------------------

  testWidgets(
      'a number field RELEASES FOCUS on commit — the Cmd/Ctrl+Z trap '
      '(docs/v3/05 §5)', (tester) async {
    final t = await open(tester);

    await tester.enterText(find.byKey(const Key('inspector-position-x')), '55');
    await tester.pump();
    expect(
        editableOf(tester, 'inspector-position-x').focusNode.hasFocus, isTrue,
        reason: 'typing focuses the field');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
        editableOf(tester, 'inspector-position-x').focusNode.hasFocus, isFalse,
        reason: 'a focused DOM input would swallow the next Cmd/Ctrl+Z');
    expect(transformOf(t.c, t.id, 'sq').position.x, 55);
  });

  testWidgets('blurring a field commits it too', (tester) async {
    final t = await open(tester);

    await tester.enterText(find.byKey(const Key('inspector-position-y')), '31');
    await tester.pump();
    // Move focus elsewhere without pressing Enter — a click on the canvas.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(transformOf(t.c, t.id, 'sq').position.y, 31,
        reason: 'committing only on Enter silently discards the edit');
  });

  // --- Rejection and the calm 0/many states ---------------------------------

  testWidgets('a non-numeric entry is rejected and reverts, never NaN',
      (tester) async {
    final t = await open(tester);

    await commitField(tester, 'inspector-scale-x', 'abc');
    final scale = transformOf(t.c, t.id, 'sq').scale;
    expect(scale.x, 1.0, reason: 'the document keeps its last good value');
    expect(scale.x.isNaN, isFalse);
    expect(editableOf(tester, 'inspector-scale-x').controller.text, '1',
        reason: 'the field snaps back to what is actually in force');
    expect(t.c.read(documentControllerProvider(t.id).notifier).canUndo, isFalse,
        reason: 'a rejected entry is not an edit');
  });

  testWidgets('0 or >1 selected shows a calm summary, never a crash',
      (tester) async {
    final s = seed([square('a'), square('b')]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    // Nothing selected.
    expect(find.byKey(const Key('inspector-summary')), findsOneWidget);
    expect(find.byKey(const Key('inspector-transform')), findsNothing);

    // Two selected.
    c.read(editorControllerProvider.notifier)
      ..selectNode(const ScenePath(NodeId('a')))
      ..addToSelection(const ScenePath(NodeId('b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inspector-summary')), findsOneWidget);
    expect(find.byKey(const Key('inspector-transform')), findsNothing);

    // Exactly one -> the editor appears.
    c
        .read(editorControllerProvider.notifier)
        .selectNode(const ScenePath(NodeId('a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inspector-transform')), findsOneWidget);
  });

  // --- The shell's undo affordances (docs/v3/05 §5) -------------------------

  testWidgets("the shell's undo button reverts an inspector edit",
      (tester) async {
    final t = await open(tester);
    final original = transformOf(t.c, t.id, 'sq');

    await commitField(tester, 'inspector-position-x', '99');
    expect(transformOf(t.c, t.id, 'sq').position.x, 99);

    final undo = find.byKey(const Key('editor-undo'));
    expect(undo, findsOneWidget);
    expect(tester.widget<IconButton>(undo).onPressed, isNotNull,
        reason: 'the button enables once there is something to undo');

    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(transformOf(t.c, t.id, 'sq'), original);

    // ...and redo replays it.
    await tester.tap(find.byKey(const Key('editor-redo')));
    await tester.pumpAndSettle();
    expect(transformOf(t.c, t.id, 'sq').position.x, 99);
  });

  testWidgets('Cmd/Ctrl+Z undoes through the shell shortcut scope',
      (tester) async {
    final t = await open(tester);
    final original = transformOf(t.c, t.id, 'sq');

    await commitField(tester, 'inspector-position-x', '64');
    expect(transformOf(t.c, t.id, 'sq').position.x, 64);

    // The shortcut needs a focused node inside the shell's scope; clicking the
    // canvas is what restores editor focus in the real app (docs/v3/05 §5).
    await tester.tap(find.byKey(const Key('canvas')));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(transformOf(t.c, t.id, 'sq'), original,
        reason: 'Cmd/Ctrl+Z must reach the editor undo, not the browser');
  });

  // --- AC-2.2.5 — opacity is authorable, and the PRODUCT is observable ------

  testWidgets('the opacity field writes 0..1 from a percent display',
      (tester) async {
    final t = await open(tester);
    final controller = t.c.read(documentControllerProvider(t.id).notifier);

    expect(editableOf(tester, 'inspector-opacity').controller.text, '100',
        reason: 'a fresh node is fully opaque, shown as percent');

    await commitField(tester, 'inspector-opacity', '40');
    expect(docOf(t.c, t.id).nodeIndex[const NodeId('sq')]!.opacity,
        closeTo(0.4, 1e-12),
        reason: '40% is stored as 0.4, not as 40');

    // ONE undo entry per commit, and undo puts the value back.
    expect(controller.canUndo, isTrue);
    await controller.undo();
    await tester.pumpAndSettle();
    expect(docOf(t.c, t.id).nodeIndex[const NodeId('sq')]!.opacity, 1.0);
    expect(controller.canUndo, isFalse,
        reason: 'the edit was a single entry — Enter must not commit twice');
    expect(editableOf(tester, 'inspector-opacity').controller.text, '100',
        reason: 'the field follows the document back');
  });

  testWidgets(
      'an out-of-range opacity is clamped at the mutation, never stored raw',
      (tester) async {
    final t = await open(tester);
    await commitField(tester, 'inspector-opacity', '250');
    expect(docOf(t.c, t.id).nodeIndex[const NodeId('sq')]!.opacity, 1.0);
    await commitField(tester, 'inspector-opacity', '-30');
    expect(docOf(t.c, t.id).nodeIndex[const NodeId('sq')]!.opacity, 0.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AC-2.2.5 IS NOW OBSERVABLE IN THE PRODUCT: a group set to 50% holding a '
      'child set to 50% evaluates to 0.25 effective', (tester) async {
    // Both factors are typed into the inspector — neither is constructed in the
    // fixture. Before this field existed, M2 claimed the `opacity` PRODUCT with
    // no control anywhere able to set either one of them.
    final s = seed([
      GroupNode(
        id: const NodeId('grp'),
        name: 'grp',
        children: [square('kid')],
      ),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final editor = c.read(editorControllerProvider.notifier);

    editor.selectNode(const ScenePath(NodeId('grp')));
    await tester.pumpAndSettle();
    await commitField(tester, 'inspector-opacity', '50');

    editor.selectNode(const ScenePath(NodeId('kid')));
    await tester.pumpAndSettle();
    expect(editableOf(tester, 'inspector-opacity').controller.text, '100',
        reason: 'the field shows the CHILD\'S OWN opacity, never an effective '
            'product — a derived value beside the authored one is the '
            'docs/v3/08 §4 desync');
    await commitField(tester, 'inspector-opacity', '50');

    final doc = docOf(c, s.id);
    expect(doc.nodeIndex[const NodeId('grp')]!.opacity, closeTo(0.5, 1e-12));
    expect(doc.nodeIndex[const NodeId('kid')]!.opacity, closeTo(0.5, 1e-12));

    final scene = evaluate(doc, const <AnimationMix>[]);
    expect(scene.byPath[const ScenePath(NodeId('kid'))]!.worldOpacity,
        closeTo(0.25, 1e-12),
        reason: 'worldOpacity is a PRODUCT over the ancestor chain, computed '
            'by the evaluator from two authored values the user typed');

    // ...and it survives a reload, because opacity is authored, not ephemeral.
    final raw = (await s.store.load(s.id))!;
    final reloaded = Document.fromJson(jsonDecode(raw) as Map<String, Object?>);
    expect(
        reloaded.nodeIndex[const NodeId('kid')]!.opacity, closeTo(0.5, 1e-12));
  });

  // --- The not-yet-built editors read as English, not as roadmap codes ------

  testWidgets(
      'the seam rows name themselves in plain language — no milestone codes '
      '(docs/v3/00 §5)', (tester) async {
    await open(tester);

    // The seams sit below the transform, appearance, paint and shape rows, so
    // scroll them into the viewport first — a `ListView` builds only what is
    // visible. `scrollUntilVisible` rather than a fixed drag: M3 added the fill
    // and stroke sections between the two, and a hard-coded 300 px stopped
    // reaching the rows this test is about.
    await tester.scrollUntilVisible(
      find.byKey(const Key('inspector-seams')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('inspector-transform')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    // "Fill / M3" tells the stranger who runs the ship gate nothing: is the
    // tool broken, or is the editor unfinished? The row has to say.
    expect(find.byKey(const Key('inspector-seams')), findsOneWidget);
    expect(find.textContaining('not yet available'), findsWidgets);
    expect(find.text('M3'), findsNothing);
    expect(find.text('M4'), findsNothing);

    // They stay non-interactive: no stub command hides behind them.
    expect(
        find.descendant(
            of: find.byKey(const Key('inspector-transform')),
            matching: find.byType(IconButton)),
        findsNothing);
  });

  testWidgets(
      'after a field releases focus, Cmd/Ctrl+Z STILL reaches the editor undo '
      'without clicking anything (docs/v3/05 §5)', (tester) async {
    final t = await open(tester);
    final original = transformOf(t.c, t.id, 'sq');

    await commitField(tester, 'inspector-position-x', '88');
    expect(transformOf(t.c, t.id, 'sq').position.x, 88);
    expect(
        editableOf(tester, 'inspector-position-x').focusNode.hasFocus, isFalse);

    // No canvas click in between. `unfocus()` hands focus to the nearest
    // enclosing scope, and the shell owns one — without it the released focus
    // lands on the app's root scope and the next shortcut reaches nothing at
    // all, which looks exactly like an unbound key.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(transformOf(t.c, t.id, 'sq'), original);
  });

  testWidgets('a selection pointing at a deleted node degrades to the summary',
      (tester) async {
    final t = await open(tester);
    // Selection is resolved, never repaired (docs/v3/08 §2): point it at a node
    // that does not exist and the panel must show the calm state, not throw.
    t.c
        .read(editorControllerProvider.notifier)
        .selectNode(const ScenePath(NodeId('ghost')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inspector-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
