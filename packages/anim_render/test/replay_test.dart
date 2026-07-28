/// AC-11.2.2 — an exported `.json` replays correctly at 50 sampled `t` in a
/// plain app that depends only on `anim_core` (+ `anim_render`).
///
/// This test lives in **`anim_render`**, a package whose *only* dependency is
/// `anim_core` (see `pubspec.yaml`). That placement is the proof: a green run
/// here is the "an external consumer replays it" guarantee, because everything
/// the replay path touches is reached through the one published barrel,
/// `package:anim_core/anim_core.dart`, plus `dart:convert`/`dart:io`. No
/// internal `src/` import, no persistence layer, no editor code is in scope.
///
/// `anim_render` itself is deliberately **not used** for the replay: `evaluate`
/// is `anim_core`, so the runtime is pure Dart and the Flutter rendering layer
/// is irrelevant to whether a document ticks. (`flutter_test` below is only the
/// test harness — it drives `test`/`expect`, never the replay.) That is the
/// whole point of AC-11.2.1's zero-Flutter boundary: the format replays with no
/// `dart:ui` in the loop.
///
/// The shape of the proof (docs/v3/03 F11.2):
///   1. Build an "exported .json": import a legacy fixture and serialize it
///      **exactly as export does** — `jsonEncode(doc.toJson())` (the same call
///      `editor_shell.dart` makes on the Export button). That string *is* the
///      file a user downloads.
///   2. Reload it purely through the published API:
///      `Document.fromJson(jsonDecode(bytes))`.
///   3. Replay at 50 sampled `t`: assert every world-transform component and
///      every anchor coordinate `.isFinite` (no NaN), and that at `t = 1.0` no
///      path node has empty geometry (the shape is present). This mirrors the
///      no-NaN totality sweep in `anim_core/test/trim_paint_test.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter_test/flutter_test.dart';

/// `assets/library/` lives at the **repo root**, two levels above this package.
/// `Directory.current` is `packages/anim_render` when its tests run, so the
/// fixture resolves through `../../`.
String get _libraryDir => '${Directory.current.path}/../../assets/library';

void main() {
  group('AC-11.2.2 — exported .json replays at 50 sampled t', () {
    test('circlebounce: import → export → reload → replay, all finite', () {
      // --- 1. Construct an "exported .json" ------------------------------------
      // A legacy fixture, imported through the published one-way importer, then
      // serialized exactly as the Export button does.
      final assetPath = '$_libraryDir/circlebounce.json';
      expect(File(assetPath).existsSync(), isTrue,
          reason: 'fixture must resolve from packages/anim_render: $assetPath');

      final legacyJson =
          jsonDecode(File(assetPath).readAsStringSync()) as Map<String, Object?>;
      final imported = LegacyImporter.import(legacyJson);

      // THIS string is the exported file — same serializer persistence uses,
      // no export-only path (AC-11.1.3).
      final exportedBytes = jsonEncode(imported.toJson());

      // --- 2. Reload purely through the published API --------------------------
      // Only `package:anim_core/anim_core.dart` + dart:convert are used here; a
      // consumer needs nothing from the package's internal `src/`.
      final doc = Document.fromJson(
          jsonDecode(exportedBytes) as Map<String, Object?>);

      // The reload landed a real v3 document with something to play.
      expect(doc.schemaVersion, kSchemaVersion);
      expect(doc.defaultAnimationId, isNotNull,
          reason: 'the importer mints a default animation to replay');

      // --- 3. Replay at 50 sampled t ------------------------------------------
      // k = 0..50 spans t ∈ [0, 1], endpoints included. Every world component
      // and every anchor coordinate must be finite — no NaN reaches the Scene.
      final animId = doc.defaultAnimationId!;
      for (var k = 0; k <= 50; k++) {
        final t = k / 50.0;
        final scene = evaluate(doc, [AnimationMix(animId, t)]);
        expect(scene.drawOrder, isNotEmpty,
            reason: 'the document has nodes to replay at t = $t');

        for (final node in scene.drawOrder) {
          for (final v in <double>[
            node.world.a,
            node.world.b,
            node.world.c,
            node.world.d,
            node.world.tx,
            node.world.ty,
            node.worldOpacity,
          ]) {
            expect(v.isFinite, isTrue,
                reason: 'non-finite world component at t = $t');
          }
          for (final a in node.geometry?.anchors ?? const <Anchor>[]) {
            for (final v in <double>[
              a.position.x,
              a.position.y,
              a.inTangent.x,
              a.inTangent.y,
              a.outTangent.x,
              a.outTangent.y,
            ]) {
              expect(v.isFinite, isTrue,
                  reason: 'non-finite anchor coordinate at t = $t');
            }
          }
        }
      }

      // --- t = 1.0: the shape is present, no path node is empty ---------------
      // A group has null geometry; a path node does not. Every path node must
      // still carry anchors at the end of the timeline (AC-11.2.2 / AC-11.3.2).
      final end = evaluate(doc, [AnimationMix(animId, 1.0)]);
      final pathNodes =
          end.drawOrder.where((n) => n.geometry != null).toList();
      expect(pathNodes, isNotEmpty,
          reason: 'the imported document has at least one path node');
      for (final n in pathNodes) {
        expect(n.geometry!.anchors, isNotEmpty,
            reason: 'path node ${n.path} has empty geometry at t = 1.0');
      }
    });
  });
}
