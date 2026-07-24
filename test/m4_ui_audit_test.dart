import 'dart:convert';
import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart' show composedFit;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/canvas/widgets/canvas_view.dart';
import 'package:drawing_animation_tool/app/features/inspector/widgets/inspector_panel.dart';
import 'package:drawing_animation_tool/app/features/timeline/widgets/timeline_bar.dart';
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The M4 audit — UI half (findings A–F). Everything here is driven **by hand**
/// through the real widget tree, on the lopsided 450.2 × 250.4 artboard so a
/// per-axis mapping bug cannot hide.
void main() {
  const Vec2 artboard = Vec2(450.2, 250.4);
  const node = NodeId('sq');
  const pathKey = PropertyKey(PropKey.path);
  const rotation = PropertyKey(PropKey.rotation);

  PathNode square({
    bool fill = true,
    List<Stroke> strokes = const [],
  }) =>
      PathNode(
        id: node,
        name: 'sq',
        path: PathData(
          anchors: [
            const Anchor(id: AnchorId('sq-0'), position: Vec2(80, 60)),
            const Anchor(id: AnchorId('sq-1'), position: Vec2(170, 60)),
            const Anchor(
              id: AnchorId('sq-2'),
              position: Vec2(170, 150),
              inTangent: Vec2(0, -20),
              outTangent: Vec2(0, 20),
              kind: AnchorKind.symmetric,
            ),
            const Anchor(id: AnchorId('sq-3'), position: Vec2(80, 150)),
          ],
          closed: true,
        ),
        fills: fill
            ? const [
                Fill(
                    id: PaintId('f'),
                    paint: SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0))),
              ]
            : const [],
        strokes: strokes,
      );

  ({MemoryProjectStore store, String id}) seed(Document doc) {
    final d = doc.bumpRev();
    return (
      store: MemoryProjectStore({d.id: jsonEncode(d.toJson())}),
      id: d.id,
    );
  }

  Document docWith(List<Node> children) {
    final base = Document.create(name: 'Sketch', artboard: artboard);
    return base.copyWith(
      root:
          GroupNode(id: base.root.id, name: base.root.name, children: children),
    );
  }

  ProviderContainer containerFor(MemoryProjectStore store) => ProviderContainer(
        overrides: [
          projectStoreProvider.overrideWithValue(store),
          toolResolverProvider.overrideWithValue(toolRegistry()),
        ],
      );

  Widget shell(ProviderContainer c, String id) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  // A canvas + inspector + a TALL timeline, so the path row's easing segments
  // are comfortably hittable (the shell fixes the timeline at 84 px).
  Widget bench(ProviderContainer c, String id) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 400,
                  child: Row(
                    children: [
                      Expanded(child: CanvasView(projectId: id)),
                      SizedBox(
                          width: 280, child: InspectorPanel(projectId: id)),
                    ],
                  ),
                ),
                SizedBox(height: 300, child: TimelineBar(projectId: id)),
              ],
            ),
          ),
        ),
      );

  Document docOf(ProviderContainer c, String id) =>
      c.read(documentControllerProvider(id)).requireValue;

  Future<Document> reload(MemoryProjectStore store, String id) async =>
      Document.fromJson(
          jsonDecode((await store.load(id))!) as Map<String, Object?>);

  PathTrack? pathTrackOf(Document doc) {
    for (final animation in doc.animations) {
      final track = animation.tracksFor(node).pathTrack();
      if (track != null) return track;
    }
    return null;
  }

  ScalarTrack? rotationTrackOf(Document doc) =>
      doc.defaultAnimation?.tracksFor(node).scalar(PropKey.rotation);

  ScalarTrack? widthTrackOf(Document doc) =>
      doc.defaultAnimation?.tracksFor(node).scalar(PropKey.strokeWidth, 's');

  Rect canvasRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('canvas')));

  Offset toScreen(WidgetTester tester, Vec2 p) {
    final box = canvasRect(tester);
    final at = composedFit(Affine.identity, artboard, box.size).apply(p);
    return box.topLeft + Offset(at.x, at.y);
  }

  void seekTo(ProviderContainer c, double t) {
    c.read(editorControllerProvider.notifier).commitPlayhead(t);
    c.read(playheadProvider).value = t;
  }

  Future<void> dragFrom(WidgetTester tester, Vec2 from, Vec2 to) async {
    final g = await tester.startGesture(toScreen(tester, from));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveTo(toScreen(tester, to));
    await tester.pump(const Duration(milliseconds: 16));
    await g.up();
    await tester.pumpAndSettle();
  }

  Future<Finder> reveal(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    if (target.evaluate().isNotEmpty) return target;
    final list = find
        .descendant(
          of: find.byKey(const Key('inspector-transform')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(target, 80, scrollable: list);
    await tester.pumpAndSettle();
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

  // =========================================================================
  // A [BLOCKER] — the exit-criterion click path (v1 criterion 2, F6.1)
  // =========================================================================

  testWidgets(
      'A: draw → path diamond (key 1) → scrub+drag (key 2) → scrub+drag '
      '(key 3) → an easing per segment: 3 path keys at fractional t, distinct '
      'CubicEasings, reloaded from the store', (tester) async {
    // A tall surface so the canvas + inspector row and the timeline both fit
    // without a RenderFlex overflow.
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = seed(docWith([square()]));
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(bench(c, s.id));
    await tester.pumpAndSettle();

    // The node is drawn; select it and pick Direct Select for the anchor drags.
    c.read(editorControllerProvider.notifier).selectNode(const ScenePath(node));
    c.read(toolControllerProvider.notifier).activate(ToolId.directSelect);
    await tester.pumpAndSettle();

    expect(pathTrackOf(docOf(c, s.id)), isNull, reason: 'starts static');

    // 1. Scrub to a fractional t and click the PATH diamond — the first key,
    //    seeded from the rest pose (this is the affordance the audit found
    //    missing; a plain drag on a static node now edits the rest pose).
    seekTo(c, 0.25);
    await tester.pumpAndSettle();
    await tester.tap(await reveal(tester, 'kf-path'));
    await tester.pumpAndSettle();
    expect(pathTrackOf(docOf(c, s.id))!.keyCount, 1,
        reason: 'exactly ONE key from the first diamond click');

    // 2. Scrub and drag sq-0 → key 2 (keyframe-local, the track now exists).
    seekTo(c, 0.5);
    await tester.pumpAndSettle();
    await dragFrom(tester, const Vec2(80, 60), const Vec2(120, 100));
    expect(pathTrackOf(docOf(c, s.id))!.keyCount, 2);

    // 3. Scrub and drag again → key 3. At t = 0.75 sq-0 is held at key 2's pose.
    seekTo(c, 0.75);
    await tester.pumpAndSettle();
    await dragFrom(tester, const Vec2(120, 100), const Vec2(150, 130));
    expect(pathTrackOf(docOf(c, s.id))!.keyCount, 3);

    // 4. Timeline: expand the node and set a DIFFERENT easing on each segment.
    //    Three keys make two segments — a different CubicEasing on each.
    await tester.tap(find.byKey(const Key('node-sq')));
    await tester.pumpAndSettle();

    Future<void> ease(int segment, String presetId) async {
      await tester.tap(find.byKey(Key('seg-sq-${pathKey.wire}-$segment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('easing-$presetId')));
      await tester.pumpAndSettle();
    }

    await ease(0, 'easeIn');
    await ease(1, 'easeOut');

    // --- Reloaded from the store ---------------------------------------------
    final saved = await reload(s.store, s.id);
    final track = pathTrackOf(saved)!;
    expect(track.keyCount, 3);

    final times = track.keys.map((k) => k.t).toList();
    expect(
        times, [closeTo(0.25, 1e-9), closeTo(0.5, 1e-9), closeTo(0.75, 1e-9)],
        reason: 'three keys, every one at a FRACTIONAL time');
    for (final t in times) {
      expect(t > 0.0 && t < 1.0, isTrue, reason: 'no endpoint keys');
    }

    // A distinct CubicEasing leaving each of the two segments (AC-7.1.2: the
    // preset lowered to its four numbers, no symbol). The last key's outgoing
    // easing governs no segment and stays the linear default (AC-7.1.3).
    expect(track.keys[0].easing, CubicEasing.easeIn);
    expect(track.keys[1].easing, CubicEasing.easeOut);
    expect(track.keys[2].easing, const LinearEasing());
    final cubics = {track.keys[0].easing, track.keys[1].easing};
    expect(cubics, hasLength(2), reason: 'two distinct curves');
    for (final e in cubics) {
      expect(e, isA<CubicEasing>());
    }

    // --- Scrub and see it ease -----------------------------------------------
    // Evaluated between key 0 (0.25) and key 1 (0.5), sq-0 sits strictly between
    // its two keyed positions — the shape animates, it is not frozen. A
    // `PathTrack` is sampled through `resolvePose`, so read the posed geometry
    // off the evaluated scene rather than the track directly.
    final anim = saved.defaultAnimation!.id;
    final posed = evaluate(saved, [AnimationMix(anim, 0.375)])
        .byPath[const ScenePath(node)]!
        .geometry!
        .anchors
        .firstWhere((a) => a.id == const AnchorId('sq-0'))
        .position;
    expect(posed.x, greaterThan(80.0));
    expect(posed.x, lessThan(120.0));
    expect(tester.takeException(), isNull);
  });

  // =========================================================================
  // B [MEDIUM] — a stale path selectedKeyframe must not re-seed a track
  // =========================================================================

  testWidgets(
      'B: delete the selected path key → selection clears and the track is '
      'gone; a later anchor drag edits the REST pose and re-seeds NOTHING, even '
      'with a stale key still selected (AC-4.2.3 2nd route)', (tester) async {
    // Seed one path key by hand, then mount.
    var doc = docWith([square()]);
    doc = PathOps.keyPose(doc, node, 0.0);
    final s = seed(doc);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(shell(c, s.id));
    await tester.pumpAndSettle();

    c.read(editorControllerProvider.notifier).selectNode(const ScenePath(node));
    c.read(toolControllerProvider.notifier).activate(ToolId.directSelect);
    await tester.pumpAndSettle();
    expect(pathTrackOf(docOf(c, s.id))!.keyCount, 1);

    // Select the key (edit-at-keyframe), then delete it via the filled diamond.
    c
        .read(editorControllerProvider.notifier)
        .selectKeyframe(node, pathKey, 0, snapT: 0.0);
    await tester.pumpAndSettle();
    expect(
        c.read(editorControllerProvider).selectedKeyframe, (node, pathKey, 0));

    await tester.tap(await reveal(tester, 'kf-path'));
    await tester.pumpAndSettle();

    expect(pathTrackOf(docOf(c, s.id)), isNull,
        reason: 'the last key went, so the track is dropped');
    expect(c.read(editorControllerProvider).selectedKeyframe, isNull,
        reason: 'removing the selected key clears the highlight');

    // Re-inject a STALE selection: a highlight naming a key on a track that no
    // longer exists — the exact dangling state the old disjunct trusted.
    c
        .read(editorControllerProvider.notifier)
        .selectKeyframe(node, pathKey, 0, snapT: 0.0);
    await tester.pumpAndSettle();

    // A plain anchor drag on the now-static node.
    await dragFrom(tester, const Vec2(80, 60), const Vec2(120, 100));

    final saved = await reload(s.store, s.id);
    expect(pathTrackOf(saved), isNull,
        reason: 'routing is _hasPathTrack alone — a stale selection cannot '
            're-seed a track (AC-4.2.3)');
    final moved = (saved.nodeIndex[node]! as PathNode)
        .path
        .anchors
        .firstWhere((a) => a.id == const AnchorId('sq-0'));
    expect(moved.position.x, closeTo(120, 1.0),
        reason: 'the REST pose was edited instead');
    expect(moved.position.y, closeTo(100, 1.0));
    expect(tester.takeException(), isNull);
  });

  // =========================================================================
  // C [MEDIUM] — a tracked field is WYSIWYG at the playhead (AC-6.2.6)
  // =========================================================================

  testWidgets(
      'C: rotation keyed 0°→170° at 0/0.5 — scrub to 0.5 shows 170 (not 0), '
      'typing 175 keys 175 (no 165° jump), and a scrub rebuilds NO panel',
      (tester) async {
    var doc = docWith([square()]);
    doc = KeyframeOps.keyAt(doc, node, rotation, 0.0, 0.0);
    doc = KeyframeOps.keyAt(doc, node, rotation, 0.5, 170 * math.pi / 180);
    final s = seed(doc);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(shell(c, s.id));
    await tester.pumpAndSettle();

    c.read(editorControllerProvider.notifier).selectNode(const ScenePath(node));
    await tester.pumpAndSettle();

    // At the settled playhead (t = 0) the field samples key 0 → 0°.
    expect(fieldText(tester, 'inspector-rotation'), '0');

    // Scrub to the second key. Only the field's text updates — no panel rebuild.
    final baseline = InspectorPanel.debugBuildCount;
    seekTo(c, 0.5);
    await tester.pump();
    expect(fieldText(tester, 'inspector-rotation'), '170',
        reason: 'the field shows the value the CANVAS shows at 0.5, not the '
            'static rest pose (0°)');
    expect(InspectorPanel.debugBuildCount, baseline,
        reason: 'a scrub writes only playhead.value — the panel does not '
            'rebuild, only the leaf field text does (AC-13.3)');

    // Type 175 — it writes to the key at the playhead (0.5), not a 165° jump
    // from a displayed 0.
    await commitField(tester, 'inspector-rotation', '175');
    final track = rotationTrackOf(docOf(c, s.id))!;
    expect(track.keyCount, 2, reason: 'the key at 0.5 was replaced, not added');
    expect(track.keys[1].value, closeTo(175 * math.pi / 180, 1e-9),
        reason: 'the KEY at 0.5 became 175°');
    expect(track.keys[0].value, closeTo(0.0, 1e-12),
        reason: 'the key at 0 is untouched');
    // The static pose never moved through any of this.
    expect(docOf(c, s.id).nodeIndex[node]!.transform.rotation, 0.0);
    expect(tester.takeException(), isNull);
  });

  // =========================================================================
  // D [LOW] — keying a tracked stroke width honours the op's clamp
  // =========================================================================

  testWidgets(
      'D: keying a tracked stroke width -2 stores 0 (clamped), and miter 0.5 '
      'stores 1 — no assertion on legal user data', (tester) async {
    var doc = docWith([
      square(strokes: const [
        Stroke(id: PaintId('s'), paint: SolidPaint(Rgba.black), width: 3),
      ]),
    ]);
    // A stroke-width track, so the field routes through keyValue (the path with
    // no op-level clamp) rather than PaintOps.setStrokeWidth.
    doc = KeyframeOps.keyAt(
        doc, node, const PropertyKey(PropKey.strokeWidth, 's'), 0.0, 3.0);
    final s = seed(doc);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(shell(c, s.id));
    await tester.pumpAndSettle();

    c.read(editorControllerProvider.notifier).selectNode(const ScenePath(node));
    await tester.pumpAndSettle();

    // Tracked: -2 must be pre-clamped to 0 before it reaches the keyframe.
    await commitField(tester, 'inspector-stroke-width', '-2');
    final width = widthTrackOf(docOf(c, s.id))!;
    expect(width.keys.single.value, 0.0,
        reason:
            'a negative width is pinned to 0 IN THE KEYFRAME, not stored raw');

    // Miter is not an animatable channel, so its only path is the static op,
    // which already clamps below-1 up to 1.
    await commitField(tester, 'inspector-stroke-miter', '0.5');
    expect(
        (docOf(c, s.id).nodeIndex[node]! as PathNode).strokes.single.miterLimit,
        1.0);
    expect(tester.takeException(), isNull,
        reason: 'clamping means no ArgumentError, so the command gate never '
            'asserts on legal user data (docs/v3/08 §1)');
  });

  // =========================================================================
  // F [MINOR] — undo restores the editing keyframe (docs/v3/04 §6)
  // =========================================================================

  testWidgets(
      'F: edit key A then key B, undo → key B reverts AND the selection returns '
      'to key A, where the user was editing before', (tester) async {
    var doc = docWith([square()]);
    doc = KeyframeOps.keyAt(doc, node, rotation, 0.0, 10 * math.pi / 180);
    doc = KeyframeOps.keyAt(doc, node, rotation, 0.5, 90 * math.pi / 180);
    final s = seed(doc);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(shell(c, s.id));
    await tester.pumpAndSettle();

    final editor = c.read(editorControllerProvider.notifier);
    editor.selectNode(const ScenePath(node));
    await tester.pumpAndSettle();
    final originalB = rotationTrackOf(docOf(c, s.id))!.keys[1].value;

    // Edit key A (index 0): this command CARRIES keyframe A, so the stack's
    // editing keyframe advances to A — undo of a later edit returns here.
    editor.selectKeyframe(node, rotation, 0, snapT: 0.0);
    await tester.pumpAndSettle();
    await commitField(tester, 'inspector-rotation', '40');
    expect(rotationTrackOf(docOf(c, s.id))!.keys[0].value,
        closeTo(40 * math.pi / 180, 1e-9));

    // Then edit key B (index 1) — this command carries B.
    editor.selectKeyframe(node, rotation, 1, snapT: 0.5);
    await tester.pumpAndSettle();
    await commitField(tester, 'inspector-rotation', '120');
    expect(rotationTrackOf(docOf(c, s.id))!.keys[1].value,
        closeTo(120 * math.pi / 180, 1e-9));
    expect(
        c.read(editorControllerProvider).selectedKeyframe, (node, rotation, 1));

    // Undo the B edit through the shell button (it restores the captured
    // keyframe): B's value reverts, and the selection returns to A.
    await tester.tap(find.byKey(const Key('editor-undo')));
    await tester.pumpAndSettle();

    expect(rotationTrackOf(docOf(c, s.id))!.keys[1].value,
        closeTo(originalB, 1e-12),
        reason: 'the B edit reverted');
    expect(
        c.read(editorControllerProvider).selectedKeyframe, (node, rotation, 0),
        reason: 'undo returned the user to key A, where they were editing '
            'before the B edit (command_stack restores the pre-edit keyframe)');
    expect(tester.takeException(), isNull);
  });
}
