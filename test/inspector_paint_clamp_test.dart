import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The half the op-level test cannot cover (M3 audit, FIX 1).
///
/// `PaintOps.setStrokeWidth` / `setStrokeMiterLimit` used to THROW on a finite
/// out-of-range value. The inspector's Width and Miter fields permit a leading
/// `-` and have no minimum, so a user typing `-2` or `0.5` reached the throw,
/// the inspector command gate hit `assert(false, 'inspector command rejected by
/// an op: …')` — an assertion firing on LEGAL user data, which docs/v3/08 §1
/// forbids — and the field was left stuck showing the rejected value.
///
/// Clamping at the op fixes the whole chain: the command SUCCEEDS, the document
/// updates to the clamped value, the provider re-emits it, and
/// `CommittedNumberField.didUpdateWidget` snaps the field to the clamped value.
/// These pin exactly that end-to-end behaviour — no assertion fires, and the
/// field settles on the clamped number rather than the one the user typed.
void main() {
  const Vec2 artboard = Vec2(400, 400);
  const NodeId sq = NodeId('sq');

  PathNode square(String id, {List<Stroke> strokes = const []}) => PathNode(
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
        strokes: strokes,
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

  Widget harness(ProviderContainer container, String id) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  PathNode pathOf(ProviderContainer c, String id) =>
      c.read(documentControllerProvider(id)).requireValue.nodeIndex[sq]!
          as PathNode;

  Future<({ProviderContainer c, String id})> open(
      WidgetTester tester, List<Node> children) async {
    final s = seed(children);
    final c = ProviderContainer(
        overrides: [projectStoreProvider.overrideWithValue(s.store)]);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();
    c.read(editorControllerProvider.notifier).selectNode(const ScenePath(sq));
    await tester.pumpAndSettle();
    return (c: c, id: s.id);
  }

  /// The inspector is a `ListView`, so a row below the fold is not built at all.
  /// Scroll it into the viewport before touching it.
  Future<Finder> reveal(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    if (target.evaluate().isNotEmpty) return target;
    final list = find
        .descendant(
          of: find.byKey(const Key('inspector-transform')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(list, const Offset(0, 3000));
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 90, scrollable: list);
      await tester.pumpAndSettle();
    }
    return target;
  }

  Future<void> commitField(WidgetTester tester, String key, String text) async {
    await tester.enterText(await reveal(tester, key), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String key) => tester
      .widget<EditableText>(find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ))
      .controller
      .text;

  testWidgets(
      'typing -2 into Width CLAMPS to 0, fires no assertion, and the field '
      'settles on the clamped value (M3 audit FIX 1)', (tester) async {
    final t = await open(tester, [
      square('sq', strokes: [
        const Stroke(id: PaintId('s'), paint: SolidPaint(Rgba.black), width: 3),
      ])
    ]);

    await commitField(tester, 'inspector-stroke-width', '-2');

    expect(pathOf(t.c, t.id).strokes.single.width, 0.0,
        reason: 'a negative width is pinned to 0, an invisible legal stroke');
    expect(tester.takeException(), isNull,
        reason: 'clamping at the op means no ArgumentError, so the command '
            "gate's assert(false) never fires on legal user data (docs/v3/08 §1)");
    expect(fieldText(tester, 'inspector-stroke-width'), '0',
        reason:
            'the document re-emitted 0 and didUpdateWidget reset the field — '
            'the "stuck field showing the rejected value" is gone');
  });

  testWidgets(
      'typing 0.5 into Miter CLAMPS to 1, fires no assertion, and the field '
      'settles on the clamped value (M3 audit FIX 1)', (tester) async {
    final t = await open(tester, [
      square('sq', strokes: [
        const Stroke(id: PaintId('s'), paint: SolidPaint(Rgba.black), width: 3),
      ])
    ]);

    await commitField(tester, 'inspector-stroke-miter', '0.5');

    expect(pathOf(t.c, t.id).strokes.single.miterLimit, 1.0,
        reason:
            'below 1 is geometrically meaningless; pinned to the floor of 1');
    expect(tester.takeException(), isNull);
    expect(fieldText(tester, 'inspector-stroke-miter'), '1',
        reason: 'the field follows the document to the clamped value');
  });
}
