import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/canvas/widgets/canvas_view.dart';
import 'package:drawing_animation_tool/app/features/inspector/widgets/inspector_panel.dart';
import 'package:drawing_animation_tool/app/features/layers/widgets/layers_panel.dart';
import 'package:drawing_animation_tool/app/features/timeline/widgets/timeline_bar.dart';
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// E13 — the narrow perf pass (docs/v3/03 §390, docs/v3/06 M7).
///
/// The budget is fixed at **114 anchors × 10 keyframes × 1 node** (docs/v3/00
/// §6): allocation churn is free at that scale, so the only thing to prove is
/// that interaction stays **scoped** — a scrub or a drag on the budget document
/// repaints the canvas without rebuilding the layers panel or the inspector
/// (AC-13.1–13.4), and the per-tick paths build nothing per tick (AC-13.5).
///
/// These drive the real widget tree on the lopsided 450.2 × 250.4 artboard so a
/// per-axis mapping bug cannot hide, and read the widgets' own `debugBuildCount`
/// — the only thing that can see a rebuild a value-projection test cannot.
void main() {
  const Vec2 artboard = Vec2(450.2, 250.4);
  const node = NodeId('blob');
  const rotation = PropertyKey(PropKey.rotation);
  const opacity = PropertyKey(PropKey.opacity);

  /// The 114-anchor × 10-keyframe budget document, built in code (NOT the legacy
  /// `circlebounce.json`, which is the M8 importer's input). One closed path of
  /// 114 anchors, a `PathTrack` of 10 keyframes (the same 114 `AnchorId`s in every
  /// keyframe — AC-4.3.6), plus rotation and opacity scalar tracks so the
  /// evaluator samples more than geometry each tick.
  Document budgetDoc() {
    final anchors = <Anchor>[
      for (var i = 0; i < 114; i++)
        Anchor(
          id: AnchorId('a$i'),
          position: Vec2(
            225 + 190 * math.cos(2 * math.pi * i / 114),
            125 + 100 * math.sin(2 * math.pi * i / 114),
          ),
        ),
    ];
    final base = Document.create(name: 'Budget', artboard: artboard);
    var doc = base.copyWith(
      root: GroupNode(id: base.root.id, name: base.root.name, children: [
        PathNode(
          id: node,
          name: 'blob',
          path: PathData(anchors: anchors, closed: true),
          fills: const [
            Fill(id: PaintId('f'), paint: SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0)))
          ],
        ),
      ]),
    );
    // 10 path keyframes spanning [0,1]. keyPose captures the same 114-anchor
    // topology every time, so the id sequence is identical across all keys.
    for (var k = 0; k < 10; k++) {
      doc = PathOps.keyPose(doc, node, k / 9);
    }
    doc = KeyframeOps.keyAt(doc, node, rotation, 0.0, 0.0);
    doc = KeyframeOps.keyAt(doc, node, rotation, 1.0, math.pi / 2);
    doc = KeyframeOps.keyAt(doc, node, opacity, 0.0, 1.0);
    doc = KeyframeOps.keyAt(doc, node, opacity, 1.0, 0.5);
    return doc;
  }

  ({MemoryProjectStore store, String id}) seed(Document doc) {
    final d = doc.bumpRev();
    return (store: MemoryProjectStore({d.id: jsonEncode(d.toJson())}), id: d.id);
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

  Future<({ProviderContainer c, String id})> openSelected(
      WidgetTester tester) async {
    final s = seed(budgetDoc());
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(shell(c, s.id));
    await tester.pumpAndSettle();
    c.read(editorControllerProvider.notifier).selectNode(const ScenePath(node));
    await tester.pumpAndSettle();
    return (c: c, id: s.id);
  }

  testWidgets(
      'AC-13.2/13.4: scrubbing the 114×10 budget document rebuilds no panel and '
      'never storms', (tester) async {
    final t = await openSelected(tester);
    final playhead = t.c.read(playheadProvider);

    final canvas0 = CanvasView.debugBuildCount;
    final layers0 = LayersPanel.debugBuildCount;
    final inspector0 = InspectorPanel.debugBuildCount;

    // Drive the playhead across [0,1] in 40 steps — the pure hot path: write only
    // the notifier value, exactly as playback and the timeline scrub do.
    for (var i = 0; i <= 40; i++) {
      playhead.value = i / 40;
      await tester.pump();
    }

    expect(CanvasView.debugBuildCount, canvas0,
        reason: 'the canvas paints off the notifier — no build() per frame '
            '(AC-13.2)');
    expect(LayersPanel.debugBuildCount, layers0,
        reason: 'no rebuild storm on the layers panel (AC-13.3)');
    expect(InspectorPanel.debugBuildCount, inspector0,
        reason: 'the inspector shows the tracked value through a leaf builder, '
            'not a panel rebuild (AC-13.3)');
    expect(tester.takeException(), isNull,
        reason: 'a heavy 114×10 scrub across the full range never throws '
            '(AC-13.4 stays responsive by construction)');
  });

  testWidgets(
      'AC-13.3: a live anchor drag on the budget document is canvas-scoped — the '
      'layers and inspector panels do not rebuild', (tester) async {
    final t = await openSelected(tester);
    final controller = t.c.read(documentControllerProvider(t.id).notifier);

    final layers0 = LayersPanel.debugBuildCount;
    final inspector0 = InspectorPanel.debugBuildCount;

    // A real gesture: begin → several moves of one anchor at the playhead → commit
    // (one undo entry, one save). The panels must stay flat across the whole drag.
    unawaited(controller.beginGesture(label: 'Move'));
    for (var step = 1; step <= 8; step++) {
      unawaited(controller.moveAnchorAt(
        node,
        const AnchorId('a0'),
        Vec2(225.0 + step * 4, 125.0 + step * 3),
        atT: 0.0,
      ));
      await tester.pump();
    }
    await controller.commitGesture('Move');
    await tester.pumpAndSettle();

    expect(LayersPanel.debugBuildCount, layers0,
        reason: 'a geometry-only drag changes no name/flag/order (AC-13.3)');
    expect(InspectorPanel.debugBuildCount, inspector0,
        reason: 'moving an anchor is not a Transform2/paint change');
  });

  testWidgets(
      'AC-13.1: the timeline is wrapped in a RepaintBoundary, isolating its '
      'raster from the canvas', (tester) async {
    await openSelected(tester);

    // The canvas carries its own RepaintBoundaries; the timeline now does too, so
    // a scrub — which drives both the canvas painters and the timeline playhead
    // marker off the shared notifier — repaints each in its own layer. Assert a
    // RepaintBoundary wraps the timeline DIRECTLY (its `.child` IS the
    // TimelineBar): a bare Scaffold body already has framework RepaintBoundary
    // ancestors, so a mere `find.ancestor(... findsWidgets)` would pass even if
    // the boundary we added were deleted.
    final boundaries = find.ancestor(
      of: find.byType(TimelineBar),
      matching: find.byType(RepaintBoundary),
    );
    final wrapsTimelineDirectly = boundaries.evaluate().any((e) {
      final w = e.widget;
      return w is RepaintBoundary && w.child is TimelineBar;
    });
    expect(wrapsTimelineDirectly, isTrue,
        reason: 'the timeline is wrapped DIRECTLY in a RepaintBoundary '
            '(AC-13.1); removing that boundary must fail this test');
  });

  testWidgets(
      'AC-13.5: a full scrub of the budget document does not rebuild the '
      'evaluator index per tick', (tester) async {
    // The Map<NodeId,Node> index and the arc-length table (AC-8.1.7) are built per
    // mutation, never per tick. A scrub performs zero mutations, so a heavy scrub
    // that rebuilds no widget (asserted above) also triggers no per-tick rebuild:
    // here we pin that a long scrub leaves the document identity untouched — the
    // evaluator reads it, it never rebuilds it.
    final t = await openSelected(tester);
    final before = t.c.read(documentControllerProvider(t.id)).requireValue;
    final playhead = t.c.read(playheadProvider);

    for (var i = 0; i <= 60; i++) {
      playhead.value = i / 60;
      await tester.pump();
    }

    final after = t.c.read(documentControllerProvider(t.id)).requireValue;
    expect(identical(before, after), isTrue,
        reason: 'a scrub mutates nothing — the same Document instance is '
            'evaluated each tick, so no index or table is rebuilt (AC-13.5)');
  });
}
