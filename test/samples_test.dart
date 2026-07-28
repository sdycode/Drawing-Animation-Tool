/// F11.4 — the bundled sample gallery (docs/v3/03 AC-11.4.1, AC-11.4.2).
///
/// Three things are proven here, all against [MemoryProjectStore] so no Firebase
/// is involved (the seam is String in / String out, so a `Map<String, String>`
/// is a complete implementation):
///
///   (a) at least two of the eight bundled assets — including the heavy
///       `circlebounce.json` — load and import to a clean schemaVersion-3
///       [Document] with a **fresh** id and real geometry;
///   (b) `ProjectActions.createFrom` lands that imported document in the store as
///       a NEW project (the list grows) while the bundled asset bytes are
///       untouched (AC-11.4.2 — the sample is read, never written);
///   (c) the gallery in [ProjectListScreen] lists all eight samples.
library;

import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/auth_service.dart';
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/features/projects/project_list_screen.dart';
import 'package:drawing_animation_tool/app/features/projects/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled sample whose stem matches [stem] (e.g. `HomeMenu`).
BundledSample sampleFor(String stem) =>
    bundledSamples.firstWhere((s) => s.asset.endsWith('/$stem.json'));

/// Total anchor count across every [PathNode] in [doc] — a proxy for "has real
/// geometry" that also distinguishes the heavy fixtures from the light ones.
int _anchorCount(Document doc) {
  var n = 0;
  for (final node in doc.nodeIndex.values) {
    if (node is PathNode) n += node.path.anchors.length;
  }
  return n;
}

void main() {
  // rootBundle asset loading needs a binding; widget tests bring their own, the
  // plain unit tests below do not.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('load + import (AC-11.4.1)', () {
    test('a light and a heavy fixture both import to a fresh v3 document',
        () async {
      final home = await loadSample(sampleFor('HomeMenu'));
      final bounce = await loadSample(sampleFor('circlebounce'));

      for (final doc in [home, bounce]) {
        expect(doc.schemaVersion, 3, reason: 'the importer targets v3');
        expect(doc.id, isNotEmpty);
        expect(doc.root.children, isNotEmpty, reason: 'a sample has shapes');
        expect(_anchorCount(doc), greaterThan(1));
      }

      // The heavy fixture (114 anchors × 10 keyframes) really carries its
      // geometry through import — not a truncated or empty shell.
      expect(_anchorCount(bounce), greaterThanOrEqualTo(100),
          reason: 'circlebounce.json is the heavy fixture');
    });

    test('every import mints a new id — legacy ids collide, v3 ids do not',
        () async {
      // Importing the SAME asset twice must not reuse an id (AC-11.4.2's "fresh
      // UUID"): the legacy files ship colliding project ids, so the id cannot be
      // derived from the file.
      final a = await loadSample(sampleFor('HomeMenu'));
      final b = await loadSample(sampleFor('HomeMenu'));
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
    });
  });

  group('createFrom → new project (AC-11.4.2)', () {
    test('the imported document lands in the store as a new project', () async {
      final store = MemoryProjectStore();
      final container = ProviderContainer(
        overrides: [projectStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      final sample = sampleFor('MultiPolygon');

      // The exact bytes of the bundled asset, captured before anything runs.
      final assetBefore = await rootBundle.loadString(sample.asset);

      expect(await store.list(), isEmpty, reason: 'nothing saved yet');

      final doc = await loadSample(sample);
      final newId =
          await container.read(projectActionsProvider).createFrom(doc);

      // The list grew by exactly one, and it is the imported document.
      final listed = await store.list();
      expect(listed, hasLength(1), reason: 'createFrom adds one project');
      expect(listed.single.id, newId);
      expect(newId, doc.id, reason: 'createFrom keeps the freshly-minted id');
      expect(listed.single.rev, 1,
          reason: 'rev 0 (never persisted) → generation 1 on first save');

      // What was written decodes as the same v3 document.
      final saved = Document.fromJson(
          jsonDecode((await store.load(newId))!) as Map<String, Object?>);
      expect(saved.schemaVersion, 3);
      expect(saved.id, newId);
      expect(saved.root.children, isNotEmpty);

      // The provider seam sees the new project too (the list the UI watches).
      final viaProvider = await container.read(projectListProvider.future);
      expect(viaProvider.map((p) => p.id), contains(newId));

      // The bundled asset is byte-for-byte what it was: createFrom writes the
      // store, never the asset. This is true by construction (the only read is
      // loadSample), and here it is verified.
      final assetAfter = await rootBundle.loadString(sample.asset);
      expect(assetAfter, assetBefore, reason: 'the sample asset is read-only');
    });
  });

  group('the gallery lists all eight (AC-11.4.1)', () {
    late FakeAuthService auth;
    late MemoryProjectStore store;
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

    testWidgets('all eight samples are listed for a first-time user',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // The empty-project first-time state still shows the gallery.
      expect(find.text('No projects yet'), findsOneWidget);

      expect(bundledSamples, hasLength(8), reason: 'eight bundled fixtures');
      for (final sample in bundledSamples) {
        expect(find.byKey(Key('sample-${sample.asset}')), findsOneWidget,
            reason: '${sample.name} is missing from the gallery');
        expect(find.text(sample.name), findsOneWidget);
      }
    });

    testWidgets('opening a sample saves a new project and opens THAT project',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Tap the first (left-most, on-screen) sample card. The open path is real
      // async (a `rootBundle` asset load), so it runs under `runAsync` rather
      // than the fake-async clock `pumpAndSettle` advances; poll until the
      // imported project has landed in the store.
      final home = sampleFor('HomeMenu');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('sample-${home.asset}')));
        for (var i = 0; i < 50 && (await store.list()).isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();

      // A new project exists, and the shell was asked to open exactly it — the
      // imported copy, never the sample asset.
      final listed = await store.list();
      expect(listed, hasLength(1), reason: 'opening a sample creates a project');
      expect(opened, [listed.single.id],
          reason: 'the shell opens the new project, not the sample');
    });
  });
}
