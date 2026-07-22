import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/auth_service.dart';
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/features/projects/project_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The M0 vertical slice, minus the canvas: create a real `Document`, encode
/// it, store it, list it, read it back and decode it.
///
/// Runs against [MemoryProjectStore] rather than Firestore because the seam is
/// String in / String out — a `Map<String, String>` is a complete and honest
/// implementation of it, so this needs no emulator and no network.
void main() {
  late FakeAuthService auth;
  late MemoryProjectStore store;

  /// What the shell would navigate to. The list itself must not know how — a
  /// feature reaching into a sibling feature is what check_boundaries rejects.
  late List<String> opened;

  setUp(() {
    auth = FakeAuthService();
    store = MemoryProjectStore();
    opened = <String>[];
  });
  tearDown(() => auth.dispose());

  Widget harness() => ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          projectStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: ProjectListScreen(onOpen: opened.add),
        ),
      );

  Future<void> createProject(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('new-project')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.byKey(const Key('new-project-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('creating a project stores a decodable v3 document',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('No projects yet'), findsOneWidget);

    await createProject(tester, 'Signature Reveal');

    expect(find.text('Signature Reveal'), findsOneWidget);
    // rev 0 means "never persisted"; the first save is generation 1.
    expect(find.text('rev 1'), findsOneWidget);

    // The bytes actually in the store are a v3 document, not just any JSON.
    final id = (await store.list()).single.id;
    final doc = Document.fromJson(
        jsonDecode((await store.load(id))!) as Map<String, Object?>);

    expect(doc.schemaVersion, 3);
    expect(doc.id, id, reason: 'the store key is the document id');
    expect(doc.name, 'Signature Reveal');
    expect(doc.artboard, const Vec2(450.2, 250.4));
    expect(doc.rev, 1);
    expect(doc.root.children, isEmpty);
    expect(doc.isReadOnly, isFalse);
  });

  testWidgets('two projects get distinct ids', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await createProject(tester, 'One');
    await createProject(tester, 'Two');

    final ids = (await store.list()).map((p) => p.id).toSet();
    expect(ids, hasLength(2),
        reason: 'legacy derived ids from a name and collided across samples');
  });

  testWidgets('tapping a project asks the shell to open it', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await createProject(tester, 'Round Trip');

    await tester.tap(find.text('Round Trip'));
    await tester.pumpAndSettle();

    // The list reports *which* project; routing to the editor is the shell's
    // job, so this feature stays deletable without touching the other one.
    expect(opened, [(await store.list()).single.id]);
  });

  testWidgets('deleting returns the list to empty', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await createProject(tester, 'Doomed');

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('No projects yet'), findsOneWidget);
    expect(await store.list(), isEmpty);
  });

  testWidgets('a store failure on save surfaces inline, not as a crash',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    store.failNext = StoreFailure.network;
    await createProject(tester, 'Offline');

    expect(find.text(StoreFailure.network.message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
