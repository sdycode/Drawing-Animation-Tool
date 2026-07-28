import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/export/providers.dart';
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// F11.1 — versioned JSON export (AC-11.1.1 … AC-11.1.4).
///
/// The whole feature is exercised on the VM by overriding [downloadJsonProvider]
/// with a function that captures the bytes instead of touching a browser. The
/// real `package:web` save-as never loads here — it lives behind the conditional
/// export in `features/export/download_json.dart`, which links the throwing stub
/// off-web — so this test proves the button logic and the round-trip without a
/// download actually happening.
void main() {
  late MemoryProjectStore store;

  // What the overridden seam last received.
  String? capturedName;
  String? capturedContents;
  var downloadCount = 0;

  setUp(() {
    capturedName = null;
    capturedContents = null;
    downloadCount = 0;
  });

  String seed() {
    final doc = Document.create(name: 'Sketch', artboard: const Vec2(400, 400))
        .bumpRev();
    store = MemoryProjectStore({doc.id: jsonEncode(doc.toJson())});
    return doc.id;
  }

  Widget harness(String id) => ProviderScope(
        overrides: [
          projectStoreProvider.overrideWithValue(store),
          toolResolverProvider.overrideWithValue(toolRegistry()),
          downloadJsonProvider.overrideWithValue((name, contents) {
            downloadCount++;
            capturedName = name;
            capturedContents = contents;
          }),
        ],
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  Future<Document> reload(String id) async => Document.fromJson(
      jsonDecode((await store.load(id))!) as Map<String, Object?>);

  /// A closed three-anchor path drawn with the Pen tool, so the exported
  /// document has real geometry to round-trip, not just an empty root.
  Future<void> drawTriangle(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const Key('canvas')));
    final first =
        Offset(box.left + box.width * 0.3, box.top + box.height * 0.3);
    for (final o in [
      first,
      Offset(box.left + box.width * 0.7, box.top + box.height * 0.3),
      Offset(box.left + box.width * 0.5, box.top + box.height * 0.7),
      first,
    ]) {
      await tester.tapAt(o);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('the export button is present and enabled once a document loads',
      (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('editor-export'));
    expect(button, findsOneWidget);
    expect(
      tester.widget<TextButton>(button).onPressed,
      isNotNull,
      reason: 'AC-11.1.1: enabled when a document is loaded',
    );
  });

  testWidgets(
      'Export downloads <name>.json whose bytes reproduce the document exactly',
      (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();

    // Give the document real content, then let the autosave settle so the live
    // document and the persisted document agree.
    await drawTriangle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editor-export')));
    await tester.pumpAndSettle();

    // AC-11.1.1: exactly one .json download, named from the project.
    expect(downloadCount, 1);
    expect(capturedName, 'Sketch.json');
    expect(capturedContents, isNotNull);

    final decoded =
        Document.fromJson(jsonDecode(capturedContents!) as Map<String, Object?>);

    // AC-11.1.1: schemaVersion is mandatory and present in the bytes.
    expect(jsonDecode(capturedContents!), containsPair('schemaVersion', 3));
    expect(decoded.schemaVersion, Document.currentSchemaVersion);

    // AC-11.1.2: loaded back into the model, it reproduces the document exactly.
    // Compared through the single serializer (AC-11.1.3): the export bytes equal
    // a re-encode of the decoded document AND equal the persisted document's
    // bytes — one contract, no parallel path.
    expect(jsonEncode(decoded.toJson()), capturedContents,
        reason: 'AC-11.1.2: the exported bytes round-trip losslessly');
    final persisted = await reload(id);
    expect(jsonEncode(persisted.toJson()), capturedContents,
        reason: 'AC-11.1.3: export uses the same Document.toJson as persistence');

    // AC-11.1.4: native v3 JSON only — no SVG/Lottie shape smuggled in.
    expect(capturedName, endsWith('.json'));
    expect(capturedContents, isNot(contains('<svg')));
  });
}
