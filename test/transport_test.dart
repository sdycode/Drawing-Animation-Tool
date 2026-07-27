import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/canvas/widgets/canvas_view.dart';
import 'package:drawing_animation_tool/app/features/transport/providers.dart';
import 'package:drawing_animation_tool/app/features/transport/widgets/transport_bar.dart';
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, TextInputAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M6 transport — play/pause, loop mode, duration retime, and the strict split
/// between what the transport touches on the document (loop, duration) and what
/// stays ephemeral (playing, the playhead).
///
/// The load-bearing tests drive the whole [EditorShell], because the promise is
/// about the Ticker → `playhead.value` hot path reaching the canvas painter
/// *without* rebuilding the canvas (docs/v3/04 §4). Playback runs a real
/// [Ticker], so these pump explicit frames and never `pumpAndSettle` while
/// playing (a loop clip would spin forever).
void main() {
  late MemoryProjectStore store;

  const rotation = PropertyKey(PropKey.rotation);

  PathNode tri(String id, String name) => PathNode(
        id: NodeId(id),
        name: name,
        path: PathData(
          anchors: [
            Anchor(id: AnchorId('$id-a'), position: const Vec2(0, 0)),
            Anchor(id: AnchorId('$id-b'), position: const Vec2(20, 0)),
            Anchor(id: AnchorId('$id-c'), position: const Vec2(20, 20)),
          ],
          closed: true,
        ),
      );

  Document docWith(List<Node> children) {
    final d = Document.create(name: 'Sketch');
    return d.copyWith(root: d.root.copyWith(children: children));
  }

  Document rotate(Document d, NodeId node, Map<double, double> keys) {
    var doc = d;
    keys.forEach((t, v) {
      doc = KeyframeOps.keyAt(doc, node, rotation, t, v);
    });
    return doc;
  }

  String seed(Document doc) {
    final d = doc.bumpRev(); // rev 1, matching the seed shape elsewhere
    store = MemoryProjectStore({d.id: jsonEncode(d.toJson())});
    return d.id;
  }

  String seedDefault() => seed(Document.create(name: 'Sketch'));

  Future<String> raw(String id) async {
    final s = await store.load(id);
    expect(s, isNotNull, reason: 'the project must still be on disk');
    return s ?? '';
  }

  Future<Document> reload(String id) async =>
      Document.fromJson(jsonDecode(await raw(id)) as Map<String, Object?>);

  Widget shell(String id) => ProviderScope(
        overrides: [
          projectStoreProvider.overrideWithValue(store),
          toolResolverProvider.overrideWithValue(toolRegistry()),
        ],
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(TransportBar)),
          listen: false);

  /// A wide window so the transport (which lives in the centre column beneath
  /// the canvas, not full-width — see editor_shell) has room for the roomy
  /// layout and every control is on-screen and hittable. On a narrow column the
  /// bar scrolls horizontally rather than overflowing; that graceful degradation
  /// is exercised by the app's own layout, not re-asserted per test here.
  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder loopChip(LoopMode mode) =>
      find.byKey(Key('transport-loop-${mode.name}'));

  Future<void> commitField(
      WidgetTester tester, String fieldKey, String text) async {
    await tester.enterText(find.byKey(Key(fieldKey)), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  // ==========================================================================
  // AC-9.1.1 — play / pause, and the hot path
  // ==========================================================================

  testWidgets(
      'Play advances playhead.value over pumped frames WITHOUT rebuilding the '
      'canvas; Pause stops and settles EditorState.playhead', (tester) async {
    wide(tester);
    final id = seedDefault();
    await tester.pumpWidget(shell(id));
    await tester.pumpAndSettle();
    final c = containerOf(tester);

    expect(c.read(editorControllerProvider).playing, isFalse);
    expect(c.read(playheadProvider).value, 0.0);

    // Δ0 across the whole play: neither the play toggle nor a single tick may
    // rebuild the canvas — the tick is a bare `playhead.value` write (the hot
    // path, docs/v3/04 §4).
    final baseline = CanvasView.debugBuildCount;

    await tester.tap(find.byKey(const Key('transport-play')));
    await tester.pump(); // build → ref.listen → ticker.start()
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(c.read(editorControllerProvider).playing, isTrue);
    expect(c.read(playheadProvider).value, greaterThan(0.0),
        reason:
            'the Ticker feeds normalizedTime into the notifier every frame');
    expect(c.read(playheadProvider).value, lessThan(1.0));
    expect(CanvasView.debugBuildCount, baseline,
        reason: 'playback rebuilds no canvas widget (the hot path)');

    // Pause: the Ticker stops and the live value is committed once, exactly as
    // scrub-end does.
    await tester.tap(find.byKey(const Key('transport-play')));
    await tester.pump();
    final settled = c.read(playheadProvider).value;
    expect(c.read(editorControllerProvider).playing, isFalse);
    expect(c.read(editorControllerProvider).playhead, closeTo(settled, 1e-9),
        reason: 'EditorState.playhead holds the settled value on pause');

    await tester.pumpAndSettle();
  });

  testWidgets(
      'Enter toggles play/pause, and does NOT fire while a text field is focused',
      (tester) async {
    wide(tester);
    final id = seedDefault();
    await tester.pumpWidget(shell(id));
    await tester.pumpAndSettle();
    final c = containerOf(tester);

    // Canvas unfocused at mount → the shell owns Enter (docs/v3/05 §5).
    expect(c.read(editorControllerProvider).playing, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.read(editorControllerProvider).playing, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.read(editorControllerProvider).playing, isFalse);

    // Focus the duration field and press Enter: `_typingInAField` (and the
    // field consuming Enter) must keep it from toggling playback.
    await tester.tap(find.byKey(const Key('transport-duration')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.read(editorControllerProvider).playing, isFalse,
        reason: 'Enter in an EditableText must not toggle play');

    await tester.pumpAndSettle();
  });

  // ==========================================================================
  // AC-9.1.2 — LoopMode: clamp / wrap / triangle, OUTSIDE the evaluator
  // ==========================================================================

  test('transportNormalizedTime delegates to normalizedTime for every mode',
      () {
    // once clamps, loop wraps, pingPong reverses — the three behaviours diverge
    // at the same elapsed of 1.4 s over a 1.0 s clip. This is anim_core's
    // `normalizedTime`, not a reimplementation (the transport has none).
    TransportModel m(LoopMode loop) =>
        (animationId: const AnimationId('a'), loop: loop, durationSeconds: 1.0);

    expect(transportNormalizedTime(m(LoopMode.once), 1.4), closeTo(1.0, 1e-9),
        reason: 'once clamps and stops at 1');
    expect(transportNormalizedTime(m(LoopMode.loop), 1.4), closeTo(0.4, 1e-9),
        reason: 'loop wraps');
    expect(
        transportNormalizedTime(m(LoopMode.pingPong), 1.4), closeTo(0.6, 1e-9),
        reason: 'pingPong reverses past the peak');
    // pingPong peaks at 1.0 exactly at elapsed = duration.
    expect(
        transportNormalizedTime(m(LoopMode.pingPong), 1.0), closeTo(1.0, 1e-9));
    // Half-way is half-way in every mode.
    for (final mode in LoopMode.values) {
      expect(transportNormalizedTime(m(mode), 0.5), closeTo(0.5, 1e-9));
    }
  });

  testWidgets('LoopMode.once stops playback at t = 1 (playing = false)',
      (tester) async {
    wide(tester);
    final id = seedDefault();
    await tester.pumpWidget(shell(id));
    await tester.pumpAndSettle();
    final c = containerOf(tester);

    await tester.tap(loopChip(LoopMode.once));
    await tester.pumpAndSettle();
    expect((await reload(id)).defaultAnimation!.loop, LoopMode.once);

    await tester.tap(find.byKey(const Key('transport-play')));
    await tester.pump(); // ticker.start()
    await tester.pump(const Duration(milliseconds: 1)); // tick #1: elapsed 0
    await tester.pump(const Duration(seconds: 2)); // tick #2: elapsed 2 s ≥ 1 s
    await tester.pump(); // reconcile: stop + commit

    expect(c.read(editorControllerProvider).playing, isFalse,
        reason: 'once sets playing=false at the end');
    expect(c.read(playheadProvider).value, closeTo(1.0, 1e-6),
        reason: 'clamped to 1 by normalizedTime');
    expect(c.read(editorControllerProvider).playhead, closeTo(1.0, 1e-6),
        reason: 'the settled value is committed on stop');

    await tester.pumpAndSettle();
  });

  testWidgets('loop and pingPong keep playing past the end', (tester) async {
    wide(tester);
    for (final mode in [LoopMode.loop, LoopMode.pingPong]) {
      final id = seedDefault();
      await tester.pumpWidget(shell(id));
      await tester.pumpAndSettle();
      final c = containerOf(tester);

      await tester.tap(loopChip(mode));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('transport-play')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1)); // elapsed 0
      await tester
          .pump(const Duration(seconds: 2)); // elapsed 2 s, past the end

      expect(c.read(editorControllerProvider).playing, isTrue,
          reason: '$mode does not stop at the end');
      final t = c.read(playheadProvider).value;
      expect(t, greaterThanOrEqualTo(0.0));
      expect(t, lessThanOrEqualTo(1.0));

      // Pause and settle before the next iteration remounts.
      await tester.tap(find.byKey(const Key('transport-play')));
      await tester.pump();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('each loop-mode change is ONE undo entry and survives a reload',
      (tester) async {
    wide(tester);
    final id = seedDefault();
    await tester.pumpWidget(shell(id));
    await tester.pumpAndSettle();

    expect((await reload(id)).rev, 1);

    await tester.tap(loopChip(LoopMode.pingPong));
    await tester.pumpAndSettle();
    final afterPing = await reload(id);
    expect(afterPing.defaultAnimation!.loop, LoopMode.pingPong);
    expect(afterPing.rev, 2, reason: 'one command, one save');

    await tester.tap(loopChip(LoopMode.once));
    await tester.pumpAndSettle();
    final afterOnce = await reload(id);
    expect(afterOnce.defaultAnimation!.loop, LoopMode.once);
    expect(afterOnce.rev, 3, reason: 'a second independent command');
  });

  // ==========================================================================
  // AC-9.1.5 — durationSeconds retimes; NO keyframe is re-authored
  // ==========================================================================

  testWidgets(
      'setting durationSeconds 1.0→2.6 retimes the display and re-authors NO '
      'keyframe (one undo entry); a 0/negative duration clamps',
      (tester) async {
    wide(tester);
    const node = NodeId('cog');
    final id = seed(rotate(
        docWith([tri('cog', 'cog')]), node, {0.2: 0.0, 0.7: 1.0, 1.0: 2.0}));

    await tester.pumpWidget(shell(id));
    await tester.pumpAndSettle();

    final before = await reload(id);
    expect(before.defaultAnimation!.durationSeconds, 1.0);
    // The keyed tracks, serialized, are the byte-for-byte comparison anchor.
    final tracksBefore =
        jsonEncode(before.defaultAnimation!.toJson()['tracks']);

    await commitField(tester, 'transport-duration', '2.6');

    final after = await reload(id);
    expect(after.defaultAnimation!.durationSeconds, closeTo(2.6, 1e-9));
    expect(after.rev, before.rev + 1, reason: 'one retime, one save');
    expect(jsonEncode(after.defaultAnimation!.toJson()['tracks']), tracksBefore,
        reason: 'the document stores fractions t; a retime re-authors nothing');
    // Every keyframe t is untouched — only the seconds DISPLAY changed.
    expect(after.defaultAnimation!.tracksFor(node).byKey[rotation]!.keyTimes,
        before.defaultAnimation!.tracksFor(node).byKey[rotation]!.keyTimes);

    // The transport's seconds readout now divides by 2.6.
    expect(
        find.descendant(
            of: find.byType(TransportBar),
            matching: find.textContaining('/ 2.60 s')),
        findsOneWidget);

    // A 0 (and then a negative) duration clamps to a positive floor rather than
    // dividing the seconds display by zero.
    await commitField(tester, 'transport-duration', '0');
    final clamped = await reload(id);
    expect(clamped.defaultAnimation!.durationSeconds, greaterThan(0.0));
    expect(clamped.defaultAnimation!.durationSeconds,
        closeTo(SetDurationFloor.value, 1e-9));

    await commitField(tester, 'transport-duration', '-5');
    expect(
        (await reload(id)).defaultAnimation!.durationSeconds, greaterThan(0.0));
  });

  // ==========================================================================
  // Ephemeral vs persisted split (AC-2.2.7 / AC-9.1.1 / AC-9.1.2)
  // ==========================================================================

  testWidgets(
      'playing and the playhead never reach the saved JSON, but loop does',
      (tester) async {
    wide(tester);
    final id = seedDefault();
    await tester.pumpWidget(shell(id));
    await tester.pumpAndSettle();
    final c = containerOf(tester);

    // Play (sets playing=true, moves the playhead), then — WITH the ticker still
    // live — persist a loop edit, so the file is re-saved while ephemeral state
    // is in flight. Explicit pumps only: a loop clip never settles.
    await tester.tap(find.byKey(const Key('transport-play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    await tester.tap(loopChip(LoopMode.pingPong));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16)); // let the save land
    }
    expect(c.read(editorControllerProvider).playing, isTrue,
        reason: 'the save happened while playing was live');

    final json = await raw(id);
    for (final banned in ['playhead', 'playing', 'selection', 'viewport']) {
      expect(json.contains(banned), isFalse,
          reason: '"$banned" is ephemeral and must never serialize');
    }
    // loop IS persisted — it lives on the Animation.
    expect(json.contains('pingPong'), isTrue);
    expect((await reload(id)).defaultAnimation!.loop, LoopMode.pingPong);

    // Stop the ticker so the final settle (and teardown) is clean.
    await tester.tap(find.byKey(const Key('transport-play')));
    await tester.pump();
    await tester.pumpAndSettle();
  });
}

/// The command's positive-duration floor, mirrored for the test's assertion so
/// the number is stated once. Kept here rather than reaching into the command
/// class to avoid coupling the test to a private constant.
class SetDurationFloor {
  static const double value = 0.01;
}
