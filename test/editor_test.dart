import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The M0 vertical slice: draw -> persist -> reload -> the shape is still there.
void main() {
  late MemoryProjectStore store;

  /// A stored project with a known artboard, so click coordinates are
  /// predictable rather than whatever the test surface happens to be.
  String seed({Vec2 artboard = const Vec2(400, 400)}) {
    final doc = Document.create(name: 'Sketch', artboard: artboard).bumpRev();
    store = MemoryProjectStore({doc.id: jsonEncode(doc.toJson())});
    return doc.id;
  }

  /// The registry `main.dart` installs. M3 dispatches every canvas gesture
  /// through the active `ToolMode`, so without it the canvas ignores clicks.
  Widget harness(String id) => ProviderScope(
        overrides: [
          projectStoreProvider.overrideWithValue(store),
          toolResolverProvider.overrideWithValue(toolRegistry()),
        ],
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  Future<Document> reload(String id) async => Document.fromJson(
      jsonDecode((await store.load(id))!) as Map<String, Object?>);

  /// A triangle drawn with the **Pen tool** (`P`), by hand: three clicks, then
  /// a fourth on the first anchor to close and exit.
  ///
  /// M0's three-click affordance — which minted a fixed triangle from any three
  /// taps and could not express a curve — is gone; M3 replaced it with the real
  /// pen (F4.1). The assertions below are unchanged, because the *outcome* is:
  /// a closed three-anchor path with minted ids, persisted once.
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
      first, // closes the path and exits to Select
    ]) {
      await tester.tapAt(o);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('three clicks persist a closed path with stable anchor ids',
      (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();

    expect(find.text('rev 1'), findsOneWidget);

    await drawTriangle(tester);

    final doc = await reload(id);
    final node = doc.root.children.single as PathNode;

    expect(node.path.anchors, hasLength(3));
    expect(node.path.closed, isTrue);
    expect(node.path.segmentCount, 3, reason: 'closed: last wraps to first');
    expect(node.fills, hasLength(1));
    expect(node.strokes, hasLength(1));

    // The one insight: ids are minted, unique, and not derived from position.
    final ids = node.path.anchors.map((a) => a.id.v).toSet();
    expect(ids, hasLength(3));
    for (final anchorId in ids) {
      expect(anchorId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    }

    // rev advanced by exactly one persisted save.
    expect(doc.rev, 2);
    expect(find.text('rev 2'), findsOneWidget);
  });

  testWidgets('clicks land where they were made, on a lopsided artboard',
      (tester) async {
    // 450.2 x 250.4 is the ratio that exposed the legacy y-rescale bug. If the
    // screen->artboard mapping ever scales y by the x factor, the y assertions
    // below drift while x stays correct.
    final id = seed(artboard: const Vec2(450.2, 250.4));
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();

    final box = tester.getRect(find.byKey(const Key('canvas')));
    await drawTriangle(tester);

    final doc = await reload(id);
    final node = doc.root.children.single as PathNode;
    final positions = node.path.anchors.map((a) => a.position).toList();

    // Every point must be inside the artboard, and the third click — the one
    // below the other two on screen — must be below them in the document too.
    for (final p in positions) {
      expect(p.x, inInclusiveRange(0.0, 450.2));
      expect(p.y, inInclusiveRange(0.0, 250.4));
    }
    expect(positions[2].y, greaterThan(positions[0].y));
    expect(positions[0].y, closeTo(positions[1].y, 1e-9),
        reason: 'two clicks at the same screen y are at the same document y');
    expect(positions[1].x, greaterThan(positions[0].x));

    // The mapping is uniform: equal screen distances are equal document
    // distances on both axes. A per-axis fit would break this.
    final screenDx = box.width * 0.4;
    final docDx = positions[1].x - positions[0].x;
    final scale = docDx / screenDx;
    expect(scale, greaterThan(0));
    expect(450.2 / scale, closeTo(box.width, box.width * 0.5),
        reason: 'artboard maps back to roughly the letterboxed width');
  });

  testWidgets('a partial gesture never reaches the document', (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const Key('canvas')));
    await tester.tapAt(box.center);
    await tester.pumpAndSettle();

    // One click in. A document containing half a gesture is a document that
    // cannot be meaningfully reloaded, so the anchors stay in the tool.
    expect((await reload(id)).root.children, isEmpty);
    expect((await reload(id)).rev, 1, reason: 'no save, no rev bump');
    expect(find.byKey(const Key('tool-hint')), findsOneWidget);
  });

  testWidgets('a corrupt document reports as corrupt, not as a crash',
      (tester) async {
    store = MemoryProjectStore({'p-1': '{"not":"a document"}'});

    await tester.pumpWidget(harness('p-1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editor-error')), findsOneWidget);
    expect(find.text(StoreFailure.corrupt.message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing project reports notFound', (tester) async {
    store = MemoryProjectStore();

    await tester.pumpWidget(harness('ghost'));
    await tester.pumpAndSettle();

    expect(find.text(StoreFailure.notFound.message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a newer-schema document opens read-only and says so',
      (tester) async {
    // docs/v3/02 §1 rule 7: every save path is disabled. The gate itself lives
    // in `DocumentController._save`, at the one place a write happens; this is
    // the half the user can see, because a refusal you only discover by
    // dragging something and reading a snackbar is a trap.
    final doc = Document.create(name: 'Future', artboard: const Vec2(400, 400))
        .bumpRev();
    final json = jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>;
    json['schemaVersion'] = Document.currentSchemaVersion + 1;
    store = MemoryProjectStore({doc.id: jsonEncode(json)});

    await tester.pumpWidget(harness(doc.id));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editor-readonly')), findsOneWidget);

    final before = await store.load(doc.id);
    await drawTriangle(tester);

    expect(find.text(StoreFailure.readOnly.message), findsOneWidget);
    expect(await store.load(doc.id), before,
        reason: 'a v4 client must not reload its own document with the '
            'semantics stripped out');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a save failure does not lose the screen', (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();

    store.failNext = StoreFailure.network;
    await drawTriangle(tester);

    expect(find.text(StoreFailure.network.message), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The document on disk is untouched; the editor is still usable.
    expect((await reload(id)).root.children, isEmpty);
    expect(find.byKey(const Key('canvas')), findsOneWidget);
  });
}
