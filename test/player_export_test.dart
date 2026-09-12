/// F11.2 — the copy-in player download.
///
/// The claim this feature makes to the user is specific: *unzip this into
/// `lib/`, import one file, and your app plays the JSON with no package added*.
/// So the tests check that claim rather than the button's existence — the
/// archive is extracted with the system `unzip` and its contents are compared
/// against the generated bundle, and the entry point the README tells people to
/// import is asserted to be in there.
///
/// The download seam is overridden exactly as `export_test.dart` overrides its
/// JSON twin, so `package:web` never loads and no file is written.
library;

import 'dart:convert';
import 'dart:io';
// `Uint8List` arrives with `services.dart`, imported below.

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/export/player_bundle.dart';
import 'package:drawing_animation_tool/app/features/export/providers.dart';
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves one canned asset, so the failure paths can be provoked without
/// deleting the real one from disk.
class _StubBundle extends CachingAssetBundle {
  _StubBundle(this.contents);

  /// Null means "the asset is not there".
  final String? contents;

  @override
  Future<ByteData> load(String key) async {
    final c = contents;
    if (c == null) throw FlutterError('asset $key not found');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(c)));
  }

  /// Decode in-process, which the inherited implementation does NOT do.
  ///
  /// `CachingAssetBundle.loadString` hands anything over 50KB to `compute()` —
  /// a background isolate — and the manifest is ~240KB. Under `testWidgets`
  /// that isolate's future never completes, because the fake clock suspends
  /// real asynchrony, so the button's `await` hangs and the download seam is
  /// never called. The symptom is a silent null with no exception, which reads
  /// as a broken button rather than as a test-harness artifact. The app itself
  /// is unaffected: off the fake clock, `compute` is exactly right for a decode
  /// this size.
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final c = contents;
    if (c == null) throw FlutterError('asset $key not found');
    return c;
  }
}

bool get _hasUnzip => Process.runSync('which', ['unzip']).exitCode == 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadPlayerBundle', () {
    test('a missing asset names the generator instead of failing obscurely',
        () async {
      await expectLater(
        loadPlayerBundle(_StubBundle(null)),
        throwsA(isA<PlayerBundleException>().having(
            (e) => e.message, 'message', contains('build_player.dart'))),
      );
    });

    test('an empty manifest is rejected rather than archived', () async {
      // A 22-byte valid-but-empty zip is the worst outcome here: it downloads,
      // it opens, and the user finds out it is useless after copying it in.
      await expectLater(
        loadPlayerBundle(_StubBundle('{}')),
        throwsA(isA<PlayerBundleException>()),
      );
    });

    test('malformed JSON is reported, not swallowed', () async {
      await expectLater(
        loadPlayerBundle(_StubBundle('{oops')),
        throwsA(isA<PlayerBundleException>()),
      );
    });

    test('a non-text entry is rejected', () async {
      await expectLater(
        loadPlayerBundle(_StubBundle('{"a.dart": 7}')),
        throwsA(isA<PlayerBundleException>()),
      );
    });

    test('the real asset carries the player the README tells people to import',
        () async {
      final files = await loadPlayerBundle(rootBundle);
      expect(files, contains('anim_player.dart'));
      expect(files, contains('src/render/anim_player.dart'));
      expect(files, contains('README.md'));
      expect(files['anim_player.dart'], contains('AnimPlayer'));
      expect(files.keys.where((k) => k.endsWith('.dart')), hasLength(25),
          reason: 'the generated bundle is 25 Dart files plus the README; a '
              'change here means the generator dropped or added a source file');
    });
  });

  group('buildPlayerZip', () {
    test('every path is nested under a single anim_player/ root', () {
      // Unzipping into lib/ must not scatter 26 loose files among the user's.
      final zip = buildPlayerZip(const {'a.dart': 'x', 'src/b.dart': 'y'});
      final text = latin1.decode(zip, allowInvalid: true);
      expect(text, contains('anim_player/a.dart'));
      expect(text, contains('anim_player/src/b.dart'));
    });

    test('system unzip extracts the real bundle intact', () async {
      if (!_hasUnzip) {
        markTestSkipped('unzip not on PATH');
        return;
      }
      final files = await loadPlayerBundle(rootBundle);
      final dir = Directory.systemTemp.createTempSync('player_zip');
      try {
        final archive = File('${dir.path}/anim_player.zip')
          ..writeAsBytesSync(buildPlayerZip(files));
        final out = Directory('${dir.path}/lib')..createSync();
        final result =
            Process.runSync('unzip', ['-q', '-o', archive.path, '-d', out.path]);
        expect(result.exitCode, 0, reason: '${result.stderr}');

        files.forEach((path, contents) {
          final extracted = File('${out.path}/anim_player/$path');
          expect(extracted.existsSync(), isTrue, reason: '$path missing');
          expect(extracted.readAsStringSync(), contents, reason: '$path differs');
        });
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('the editor button', () {
    late MemoryProjectStore store;
    String? name;
    Uint8List? bytes;
    String? mime;

    setUp(() {
      name = null;
      bytes = null;
      mime = null;
    });

    String seed() {
      final doc = Document.create(name: 'Sketch', artboard: const Vec2(400, 400))
          .bumpRev();
      store = MemoryProjectStore({doc.id: jsonEncode(doc.toJson())});
      return doc.id;
    }

    /// The real manifest, read off disk with `dart:io` and served through
    /// [DefaultAssetBundle].
    ///
    /// Not `rootBundle`: that one does real asynchronous I/O, which
    /// `testWidgets` suspends under its fake clock, so the button's `await`
    /// never completes and the seam is never called — indistinguishable from a
    /// broken button. Serving the same bytes from memory keeps the assertion
    /// about the *button*, and the manifest's own contents are covered by the
    /// `loadPlayerBundle` group above.
    final manifest = File('assets/player_bundle.json').readAsStringSync();

    Widget harness(String id) => ProviderScope(
          overrides: [
            projectStoreProvider.overrideWithValue(store),
            toolResolverProvider.overrideWithValue(toolRegistry()),
            downloadBytesProvider.overrideWithValue((n, b, m) {
              name = n;
              bytes = b;
              mime = m;
            }),
          ],
          child: DefaultAssetBundle(
            bundle: _StubBundle(manifest),
            child: MaterialApp(home: EditorShell(projectId: id)),
          ),
        );

    testWidgets('downloads anim_player.zip as a zip', (tester) async {
      final id = seed();
      await tester.pumpWidget(harness(id));
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('editor-export-player'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(name, 'anim_player.zip');
      expect(mime, 'application/zip');
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(10000),
          reason: 'the bundle is ~290KB; a tiny archive means an empty manifest');
      expect(bytes!.sublist(0, 4), <int>[0x50, 0x4b, 0x03, 0x04]);
    });
  });
}
