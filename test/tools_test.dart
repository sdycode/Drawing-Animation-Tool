import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart' show OverlayPainter, composedFit;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/canvas/commands.dart'
    show CanvasCommands;
import 'package:drawing_animation_tool/app/state/recipe_guard.dart'
    show kAnimatedPathRecipeMessage;
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/state/command.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M3 — the tool layer: dispatch, pen, shapes, direct select, toolbar.
///
/// Everything here is driven **by hand**, through the real widget tree, on the
/// **lopsided 450.2 × 250.4 artboard**. A square board hides the legacy
/// y-scaled-by-width defect completely: every assertion below would pass on a
/// square board whether the screen→document mapping is right or wrong, so the
/// ratio is the only thing keeping the net un-blind.
void main() {
  const Vec2 artboard = Vec2(450.2, 250.4);

  /// A stored, non-read-only document (rev 1) on the lopsided board.
  ({MemoryProjectStore store, String id}) seed(
      {List<Node> children = const []}) {
    final base = Document.create(name: 'Sketch', artboard: artboard);
    final doc = base
        .copyWith(
          root: GroupNode(
            id: base.root.id,
            name: base.root.name,
            children: children,
          ),
        )
        .bumpRev();
    return (
      store: MemoryProjectStore({doc.id: jsonEncode(doc.toJson())}),
      id: doc.id,
    );
  }

  /// **The registry `main.dart` installs.** Without it the resolver is the inert
  /// default and the canvas — which dispatches all direct manipulation through
  /// the active tool at M3 — ignores every click. A fresh registry per container
  /// also keeps one test's half-drawn path out of the next test's pen.
  ProviderContainer containerFor(MemoryProjectStore store) => ProviderContainer(
        overrides: [
          projectStoreProvider.overrideWithValue(store),
          toolResolverProvider.overrideWithValue(toolRegistry()),
        ],
      );

  /// The live [WidgetRef], captured from inside the tree by [_RefProbe].
  ///
  /// `CanvasCommands` takes one, exactly as the inspector's shape fields will,
  /// so the only honest way to test the command layer's refusal is to call it
  /// with a real ref from a real tree rather than to re-implement its check.
  WidgetRef? probeRef;

  Widget harness(ProviderContainer c, String id) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Stack(
            children: [
              EditorShell(projectId: id),
              _RefProbe((ref) => probeRef = ref),
            ],
          ),
        ),
      );

  CanvasCommands commandsFor(String id) {
    final ref = probeRef;
    expect(ref, isNotNull, reason: 'the probe never built');
    return CanvasCommands(ref!, id);
  }

  Future<({ProviderContainer c, String id, MemoryProjectStore store})> open(
    WidgetTester tester, {
    List<Node> children = const [],
  }) async {
    final s = seed(children: children);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();
    return (c: c, id: s.id, store: s.store);
  }

  Rect canvasRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('canvas')));

  /// Document point → screen pixel through the **same** composed matrix the
  /// canvas builds (`composedFit` with the identity viewport is `artboardFit`).
  /// A second hand-rolled mapping here is exactly how legacy's y-rescale bug
  /// survived its own suite.
  Offset toScreen(WidgetTester tester, Vec2 p, {Affine? viewport}) {
    final box = canvasRect(tester);
    final at =
        composedFit(viewport ?? Affine.identity, artboard, box.size).apply(p);
    return box.topLeft + Offset(at.x, at.y);
  }

  Document docOf(ProviderContainer c, String id) =>
      c.read(documentControllerProvider(id)).requireValue;

  Future<Document> reload(MemoryProjectStore store, String id) async =>
      Document.fromJson(
          jsonDecode((await store.load(id))!) as Map<String, Object?>);

  void activate(ProviderContainer c, ToolId id) =>
      c.read(toolControllerProvider.notifier).activate(id);

  Future<void> click(WidgetTester tester, Vec2 p) async {
    await tester.tapAt(toScreen(tester, p));
    await tester.pumpAndSettle();
  }

  /// A press at [from], a drag to [to], a release — the click-drag that authors
  /// a curve, and the drag that draws a shape.
  Future<void> dragFrom(
    WidgetTester tester,
    Vec2 from,
    Vec2 to, {
    List<LogicalKeyboardKey> holding = const [],
  }) async {
    for (final key in holding) {
      await tester.sendKeyDownEvent(key);
    }
    final gesture = await tester.startGesture(toScreen(tester, from));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(toScreen(tester, to));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    for (final key in holding.reversed) {
      await tester.sendKeyUpEvent(key);
    }
  }

  PathNode onlyPath(Document doc) =>
      doc.root.children.whereType<PathNode>().single;

  // ==========================================================================
  // M3's EXIT CRITERION, end to end, by hand
  // ==========================================================================

  testWidgets(
      'M3 EXIT BY HAND: click, click, click-DRAG, click the first anchor → a '
      'CLOSED path with a CURVED segment, filled and stroked', (tester) async {
    final t = await open(tester);

    // `P` through the real key binding, not through the controller: the toolbar
    // and the shortcut must reach the same `activate`.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(t.c.read(toolControllerProvider).id, ToolId.pen);

    const first = Vec2(60, 60);
    await click(tester, first); // 1. corner
    await click(tester, const Vec2(300, 60)); // 2. corner
    // 3. click-DRAG: a smooth anchor whose symmetric tangents bend the segments
    //    either side of it. This is the step M0's three-click affordance could
    //    not express, and the whole reason the criterion says "at least one
    //    curved segment".
    await dragFrom(tester, const Vec2(300, 190), const Vec2(360, 190));
    // 4. click the FIRST anchor: close and exit.
    await click(tester, first);

    // --- The document, reloaded from disk -----------------------------------
    final saved = await reload(t.store, t.id);
    final node = onlyPath(saved);

    expect(node.path.closed, isTrue,
        reason: 'clicking the first anchor closes');
    expect(node.path.anchors, hasLength(3),
        reason: 'three clicks placed three anchors; the closing click is not a '
            'fourth one');
    expect(node.path.segmentCount, 3,
        reason: 'closed: the last wraps to first');

    // Unique, minted, not derived from a loop index (AC-4.1.1).
    final ids = node.path.anchors.map((a) => a.id.v).toSet();
    expect(ids, hasLength(3));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    }

    // --- "at least one CURVED segment" --------------------------------------
    final curved = node.path.anchors
        .where((a) => a.outTangent != Vec2.zero || a.inTangent != Vec2.zero)
        .toList();
    expect(curved, hasLength(1), reason: 'exactly the click-dragged anchor');
    final smooth = curved.single;
    expect(smooth.kind, AnchorKind.symmetric);
    expect(smooth.inTangent.x, closeTo(-smooth.outTangent.x, 1e-9));
    expect(smooth.inTangent.y, closeTo(-smooth.outTangent.y, 1e-9));
    expect(smooth.outTangent.length, greaterThan(1.0));

    // A curve is not just non-zero handles: the segment must actually leave its
    // chord. Sample the cubic at u = 0.5 and compare with the chord's midpoint.
    final index = node.path.anchors.indexOf(smooth);
    final (p0, p1, p2, p3) = node.path.segment(index);
    Vec2 cubicAt(double u) {
      final v = 1 - u;
      return p0 * (v * v * v) +
          p1 * (3 * v * v * u) +
          p2 * (3 * v * u * u) +
          p3 * (u * u * u);
    }

    final chordMid = Vec2.lerp(p0, p3, 0.5);
    expect((cubicAt(0.5) - chordMid).length, greaterThan(1.0),
        reason: 'the segment deviates from its chord — it is a real curve, not '
            'a straight line wearing handles');

    // Every other segment is the degenerate zero-handle cubic. ONE segment type
    // (AC-4.1.2): there is no polyline branch to find.
    expect(
        node.path.anchors
            .where((a) => a.inTangent == Vec2.zero && a.outTangent == Vec2.zero)
            .length,
        2);

    // --- filled and stroked --------------------------------------------------
    expect(node.fills, hasLength(1));
    expect(node.strokes, hasLength(1));
    expect(node.fills.single.paint, isA<SolidPaint>());
    expect(node.strokes.single.paint, isA<SolidPaint>());
    expect(node.strokes.single.width, greaterThan(0));
    // Paint subject ids are minted per node, never a shared constant: `PaintId`
    // is what a `fillColor` track will bind to at M4.
    expect(node.fills.single.id.v, matches(RegExp(r'^[0-9a-f-]{36}$')));

    // --- and the tool exited to Select with the new node selected ------------
    expect(t.c.read(toolControllerProvider).id, ToolId.select,
        reason: 'docs/v3/05 §4.1 step 4: the tool exits to Select');
    expect(
        t.c.read(editorControllerProvider).selectedNodes, {ScenePath(node.id)});
    expect(tester.takeException(), isNull);
  });

  // ==========================================================================
  // Pen — exits, and the half-gesture that must never land
  // ==========================================================================

  for (final key in [LogicalKeyboardKey.escape, LogicalKeyboardKey.enter]) {
    testWidgets('${key.keyLabel} leaves the pen path OPEN and exits',
        (tester) async {
      final t = await open(tester);
      activate(t.c, ToolId.pen);
      await tester.pumpAndSettle();

      await click(tester, const Vec2(80, 80));
      await click(tester, const Vec2(240, 80));
      await click(tester, const Vec2(240, 200));
      expect(docOf(t.c, t.id).root.children, isEmpty,
          reason: 'nothing is committed while the path is in progress');

      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();

      final node = onlyPath(await reload(t.store, t.id));
      expect(node.path.closed, isFalse,
          reason: 'docs/v3/05 §3 Pen row: Esc AND Enter leave it open');
      expect(node.path.anchors, hasLength(3));
      expect(node.path.segmentCount, 2, reason: 'open: no wrap segment');
      expect(t.c.read(toolControllerProvider).id, ToolId.select);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a half-drawn path never reaches the document', (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    // One click in. A one-anchor path has no segment, renders nothing, and
    // cannot be clicked — committing it would put an invisible node in the
    // layers panel and an undo entry in the history for an abandoned gesture.
    await click(tester, const Vec2(120, 120));
    expect(docOf(t.c, t.id).root.children, isEmpty);
    expect(await reload(t.store, t.id), isA<Document>());
    expect((await reload(t.store, t.id)).root.children, isEmpty);
    expect((await reload(t.store, t.id)).rev, 1,
        reason: 'no save, no rev bump');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(docOf(t.c, t.id).root.children, isEmpty,
        reason: 'Esc on a one-anchor path drops it rather than minting it');
    expect((await reload(t.store, t.id)).rev, 1);
    expect(
        t.c.read(documentControllerProvider(t.id).notifier).canUndo, isFalse);
  });

  testWidgets(
      'the in-progress path reaches the OVERLAY as GEOMETRY, never the '
      'document', (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    /// The live `OverlayPainter` — layer 3 of three (docs/v3/04 §5). Reading it
    /// is the only way to assert *which layer* the in-progress gesture reaches:
    /// a preview drawn as a speculative document would show up in the artboard
    /// painter instead, one missed reset from being saved.
    OverlayPainter overlay() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<OverlayPainter>()
        .single;

    expect(overlay().draft, isNull, reason: 'nothing is being drawn yet');

    await click(tester, const Vec2(80, 80));
    await click(tester, const Vec2(240, 80));

    // A PATH, not a bag of points. The pen used to describe its half-drawn
    // shape through the `pending` markers channel, which cannot express a
    // cubic — so a click-drag showed the user dots where they had drawn a
    // curve. That channel is now empty for this tool by construction.
    final drawn = overlay().draft;
    expect(drawn, isNotNull);
    expect(drawn?.path.anchors, hasLength(2));
    expect(drawn?.path.segmentCount, 1,
        reason: 'two anchors is one real segment for the overlay to stroke');
    expect(drawn?.path.closed, isFalse);
    expect(drawn?.path.anchors.first.position.x, closeTo(80, 0.5));
    expect(drawn?.path.anchors.first.position.y, closeTo(80, 0.5));
    expect(drawn?.handle, isNull, reason: 'no handle is being pulled');
    expect(overlay().pending, isEmpty,
        reason: 'the pen no longer speaks in dots');
    expect(overlay().document.root.children, isEmpty,
        reason: 'and NONE of it is in the document the painters are handed');

    // Mid-drag: the anchor whose tangents are live is named, by ID.
    final gesture =
        await tester.startGesture(toScreen(tester, const Vec2(240, 200)));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(toScreen(tester, const Vec2(330, 200)));
    await tester.pump(const Duration(milliseconds: 16));

    final pulling = overlay().draft;
    expect(pulling?.path.anchors, hasLength(3));
    expect(pulling?.handle, pulling?.path.anchors.last.id,
        reason: 'the handle is joined by id, never by index');
    expect(pulling?.path.anchors.last.outTangent.x, greaterThan(1.0),
        reason: 'the drag really did author a tangent for it to draw');
    expect(overlay().document.root.children, isEmpty);

    // The tool's own list is NOT what the overlay holds: a preview that aliased
    // it would let the painter observe half of the next edit.
    final aliased = pulling?.path.anchors;
    await gesture.moveTo(toScreen(tester, const Vec2(400, 200)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(aliased?.last.outTangent,
        isNot(overlay().draft?.path.anchors.last.outTangent),
        reason: 'the earlier preview was a copy, frozen at its own moment');

    await gesture.up();
    await tester.pumpAndSettle();

    // Anchor handles belong to Direct select, and the overlay is now ASKED
    // that question outright rather than being handed the geometry-less root
    // id as a stand-in for "none".
    expect(overlay().showAnchors, isFalse);
    expect(overlay().selected, isEmpty,
        reason: 'the sentinel is gone: nothing is passed here at all');
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();
    expect(overlay().showAnchors, isTrue);

    // The abandoned path left with the tool switch, and nothing was written —
    // not to the in-memory document, and not to the STORED BYTES.
    expect(overlay().draft, isNull);
    expect(docOf(t.c, t.id).root.children, isEmpty);
    final bytes = (await t.store.load(t.id)) ?? '';
    expect(bytes, isNot(contains('anchors')),
        reason: 'a half-drawn path never reaches disk, in any shape');
    expect((await reload(t.store, t.id)).root.children, isEmpty);
    expect((await reload(t.store, t.id)).rev, 1, reason: 'no save, no bump');
  });

  testWidgets('the live segment follows the cursor between clicks',
      (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    OverlayPainter overlay() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<OverlayPainter>()
        .single;

    await click(tester, const Vec2(80, 80));

    // A hover, which no tool is handed: a `ToolMode` only sees events of its
    // own, so the rubber band would freeze at the last click without the canvas
    // tracking the pointer itself. It inverts THE composed matrix to do it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: toScreen(tester, const Vec2(80, 80)));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(toScreen(tester, const Vec2(300, 150)));
    await tester.pumpAndSettle();

    final cursor = overlay().draft?.cursor;
    expect(cursor, isNotNull, reason: 'the live segment has an end to reach');
    expect(cursor?.x, closeTo(300, 0.5));
    expect(cursor?.y, closeTo(150, 0.5),
        reason: 'on a LOPSIDED board, which a per-axis mapping would skew');

    await mouse.moveTo(toScreen(tester, const Vec2(120, 220)));
    await tester.pumpAndSettle();
    expect(overlay().draft?.cursor?.x, closeTo(120, 0.5));
    expect(overlay().draft?.cursor?.y, closeTo(220, 0.5));
    expect(docOf(t.c, t.id).root.children, isEmpty);
  });

  testWidgets('Alt while dragging breaks the outgoing tangent', (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    await click(tester, const Vec2(60, 60));
    await dragFrom(tester, const Vec2(240, 120), const Vec2(300, 120),
        holding: const [LogicalKeyboardKey.altLeft]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final broken = onlyPath(docOf(t.c, t.id)).path.anchors.last;
    expect(broken.kind, AnchorKind.corner, reason: 'Alt breaks the symmetry');
    expect(broken.inTangent, Vec2.zero,
        reason: 'the incoming handle is left alone — the segment ARRIVES '
            'straight and LEAVES curved');
    expect(broken.outTangent.x, greaterThan(1.0));
  });

  testWidgets('Shift constrains the new anchor to 45° from the previous one',
      (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    await click(tester, const Vec2(100, 100));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    // 60 across, 10 down: without the constraint it lands where it was clicked.
    await click(tester, const Vec2(160, 110));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final anchors = onlyPath(docOf(t.c, t.id)).path.anchors;
    final delta = anchors[1].position - anchors[0].position;
    expect(delta.y.abs(), lessThan(0.01),
        reason: 'snapped onto the horizontal ray — on a LOPSIDED board, which '
            'a per-axis mapping would skew off the 45° grid');
    expect(delta.x, greaterThan(50));
  });

  // ==========================================================================
  // Shape tools (AC-4.1.4)
  // ==========================================================================

  const shapes = <ToolId, ({int anchors, Type recipe})>{
    ToolId.rect: (anchors: 4, recipe: RectRecipe),
    // FOUR, at κ = 0.5523 — not legacy's 114 straight segments.
    ToolId.ellipse: (anchors: 4, recipe: EllipseRecipe),
    ToolId.polygon: (anchors: 5, recipe: PolygonRecipe),
  };

  for (final entry in shapes.entries) {
    testWidgets(
        '${entry.key.name} emits ${entry.value.anchors} anchors and stores its '
        'recipe as inert metadata', (tester) async {
      final t = await open(tester);
      activate(t.c, entry.key);
      await tester.pumpAndSettle();

      await dragFrom(tester, const Vec2(100, 60), const Vec2(220, 180));

      final saved = await reload(t.store, t.id);
      final node = onlyPath(saved);
      expect(node.path.anchors, hasLength(entry.value.anchors));
      expect(node.path.closed, isTrue);
      expect(node.recipe.runtimeType, entry.value.recipe);
      expect(node.fills, hasLength(1));
      expect(node.strokes, hasLength(1));

      // The recipe is INERT: it is not in any TrackSet, and it never can be —
      // `PropKey` has no channel for it (AC-4.1.4).
      for (final animation in saved.animations) {
        expect(animation.tracksFor(node.id).pathTrack(), isNull);
      }

      // Geometry is centred on the local origin and the node's transform says
      // where it sits — so it rotates about its own middle instead of about the
      // artboard corner.
      expect(node.transform.position.x, closeTo(160, 0.01));
      expect(node.transform.position.y, closeTo(120, 0.01));
      for (final anchor in node.path.anchors) {
        expect(anchor.position.x.abs(), lessThanOrEqualTo(61.0));
        expect(anchor.position.y.abs(), lessThanOrEqualTo(61.0));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Shift squares the box; Alt draws from the centre',
      (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.rect);
    await tester.pumpAndSettle();

    // Shift: a 160 × 60 drag becomes a 60 × 60 square.
    await dragFrom(tester, const Vec2(60, 60), const Vec2(220, 120),
        holding: const [LogicalKeyboardKey.shiftLeft]);
    final square = onlyPath(docOf(t.c, t.id)).recipe;
    expect(square, isA<RectRecipe>());
    if (square is RectRecipe) {
      expect(square.w, closeTo(60, 0.01));
      expect(square.h, closeTo(60, 0.01),
          reason: 'square on a LOPSIDED artboard — a per-axis mapping would '
              'make w and h disagree here and nowhere else');
    }

    // Alt: the press point is the CENTRE, so the same pointer travel describes
    // a box twice as large, centred where the drag began.
    activate(t.c, ToolId.ellipse);
    await tester.pumpAndSettle();
    await dragFrom(tester, const Vec2(200, 120), const Vec2(240, 150),
        holding: const [LogicalKeyboardKey.altLeft]);

    final ellipse = docOf(t.c, t.id).root.children.last as PathNode;
    expect(ellipse.transform.position.x, closeTo(200, 0.01),
        reason: 'centred on the press point, not on the box midpoint');
    expect(ellipse.transform.position.y, closeTo(120, 0.01));
    final recipe = ellipse.recipe;
    expect(recipe, isA<EllipseRecipe>());
    if (recipe is EllipseRecipe) {
      expect(recipe.rx, closeTo(40, 0.01));
      expect(recipe.ry, closeTo(30, 0.01));
    }
  });

  testWidgets('a shape tool click with no drag commits nothing',
      (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.rect);
    await tester.pumpAndSettle();

    await click(tester, const Vec2(150, 120));

    expect(docOf(t.c, t.id).root.children, isEmpty,
        reason: 'a degenerate box is PathData.empty — no geometry, no node, no '
            'undo entry');
    expect(
        t.c.read(documentControllerProvider(t.id).notifier).canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  // ==========================================================================
  // Direct select (`A`)
  // ==========================================================================

  /// A closed square, drawn as a path so the direct-select tests have real
  /// anchors to grab.
  PathNode square(String id, Vec2 origin, double s) => PathNode(
        id: NodeId(id),
        name: id,
        path: PathData(
          anchors: [
            Anchor(id: AnchorId('$id-0'), position: origin),
            Anchor(id: AnchorId('$id-1'), position: origin + Vec2(s, 0)),
            Anchor(
              id: AnchorId('$id-2'),
              position: origin + Vec2(s, s),
              // A real handle to grab, and a kind for Alt to break.
              inTangent: const Vec2(0, -20),
              outTangent: const Vec2(0, 20),
              kind: AnchorKind.symmetric,
            ),
            Anchor(id: AnchorId('$id-3'), position: origin + Vec2(0, s)),
          ],
          closed: true,
        ),
        fills: const [
          Fill(
            id: PaintId('f'),
            paint: SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0)),
          ),
        ],
      );

  PathTrack? pathTrackOf(Document doc, NodeId node) {
    for (final animation in doc.animations) {
      final track = animation.tracksFor(node).pathTrack();
      if (track != null) return track;
    }
    return null;
  }

  testWidgets(
      'direct select drags an anchor at a non-zero playhead — keyframe-local, '
      'the other keyframe byte-identical', (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();

    // One drag at t = 0 seeds the track (a t = 0 key from the rest pose), then
    // the playhead moves and a second drag writes a SECOND key.
    await dragFrom(tester, const Vec2(80, 60), const Vec2(170, 140));
    t.c.read(editorControllerProvider.notifier).commitPlayhead(1.0);
    t.c.read(playheadProvider).value = 1.0;
    await tester.pumpAndSettle();

    final beforeSecondDrag = pathTrackOf(docOf(t.c, t.id), const NodeId('sq'));
    expect(beforeSecondDrag, isNotNull);
    final keyAtZeroBefore =
        jsonEncode(beforeSecondDrag!.keys.first.value.toJson());

    // Grab the SAME anchor again — now at the far end of the timeline.
    await dragFrom(tester, const Vec2(170, 140), const Vec2(260, 210));

    final track = pathTrackOf(await reload(t.store, t.id), const NodeId('sq'));
    expect(track, isNotNull);
    expect(track!.keyCount, 2, reason: 't = 0.0 and t = 1.0');
    expect(track.keys.first.t, 0.0);
    expect(track.keys.last.t, 1.0);

    expect(jsonEncode(track.keys.first.value.toJson()), keyAtZeroBefore,
        reason: 'AC-4.2.1: a pose edit at one keyframe leaves every other '
            'keyframe BYTE-identical');
    expect(jsonEncode(track.keys.last.value.toJson()), isNot(keyAtZeroBefore),
        reason: 'and the edited keyframe actually changed');

    // The anchor SEQUENCE is untouched by a pose edit — the invariant M5's
    // topology transactions depend on.
    final topology =
        (docOf(t.c, t.id).nodeIndex[const NodeId('sq')]! as PathNode)
            .path
            .anchors
            .map((a) => a.id.v)
            .toList();
    for (final key in track.keys) {
      expect(key.value.anchors.keys.map((a) => a.v).toSet(), topology.toSet());
    }
  });

  testWidgets('direct select drags a HANDLE, keyframe-local', (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();

    // `sq-2` sits at (170,150) with an out-handle at (170,170).
    await dragFrom(tester, const Vec2(170, 170), const Vec2(210, 180));

    final node = (await reload(t.store, t.id)).nodeIndex[const NodeId('sq')]!
        as PathNode;
    final track = pathTrackOf(await reload(t.store, t.id), const NodeId('sq'));
    expect(track, isNotNull);

    final pose = track!.keys.first.value.anchors[const AnchorId('sq-2')];
    expect(pose, isNotNull);
    expect(pose!.outTangent.x, closeTo(40, 0.5),
        reason: 'the handle followed the pointer, in NODE-LOCAL units');
    expect(pose.position, const Vec2(170, 150),
        reason: 'a handle drag never moves the anchor');
    // `kind` is topology, not pose: it stays on the node and is untouched by a
    // plain (no-Alt) handle drag.
    expect(
        node.path.anchors
            .firstWhere((a) => a.id == const AnchorId('sq-2'))
            .kind,
        AnchorKind.symmetric);
  });

  testWidgets('Alt+drag on a handle breaks symmetry — AnchorKind.corner',
      (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();

    await dragFrom(tester, const Vec2(170, 170), const Vec2(210, 180),
        holding: const [LogicalKeyboardKey.altLeft]);

    final node = (await reload(t.store, t.id)).nodeIndex[const NodeId('sq')]!
        as PathNode;
    final anchor =
        node.path.anchors.firstWhere((a) => a.id == const AnchorId('sq-2'));
    expect(anchor.kind, AnchorKind.corner,
        reason: 'docs/v3/05 §3: Alt+drag a handle BREAKS SYMMETRY');

    final pose = pathTrackOf(docOf(t.c, t.id), const NodeId('sq'))!
        .keys
        .first
        .value
        .anchors[const AnchorId('sq-2')]!;
    expect(pose.outTangent.x, closeTo(40, 0.5));
    expect(pose.inTangent, const Vec2(0, -20),
        reason: 'a corner stores its handles verbatim — the opposite one is '
            'left exactly where its author put it, NOT zeroed, because the '
            'kind arrived together with a handle');
  });

  testWidgets('Alt+click on an anchor cycles its AnchorKind', (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();

    AnchorKind kindOf(String id) =>
        (docOf(t.c, t.id).nodeIndex[const NodeId('sq')]! as PathNode)
            .path
            .anchors
            .firstWhere((a) => a.id == AnchorId(id))
            .kind;

    expect(kindOf('sq-0'), AnchorKind.corner);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await click(tester, const Vec2(80, 60));
    expect(kindOf('sq-0'), AnchorKind.smooth, reason: 'corner → smooth');
    await click(tester, const Vec2(80, 60));
    expect(kindOf('sq-0'), AnchorKind.symmetric, reason: 'smooth → symmetric');
    await click(tester, const Vec2(80, 60));
    expect(kindOf('sq-0'), AnchorKind.corner, reason: 'symmetric → corner');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  });

  testWidgets('an anchor grab selects the anchor and its node', (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();

    await click(tester, const Vec2(80, 60));
    final editor = t.c.read(editorControllerProvider);
    expect(editor.selectedAnchors, {const AnchorId('sq-0')});
    expect(editor.selectedNodes, {const ScenePath(NodeId('sq'))});

    // Empty space drops both.
    await click(tester, const Vec2(400, 230));
    expect(t.c.read(editorControllerProvider).selectedAnchors, isEmpty);
    expect(t.c.read(editorControllerProvider).selectedNodes, isEmpty);
  });

  // ==========================================================================
  // The toolbar, the keys, and the dispatch itself
  // ==========================================================================

  testWidgets('the rail and the key bindings drive the same modal state',
      (tester) async {
    final t = await open(tester);

    final bindings = <LogicalKeyboardKey, ToolId>{
      LogicalKeyboardKey.keyA: ToolId.directSelect,
      LogicalKeyboardKey.keyP: ToolId.pen,
      LogicalKeyboardKey.keyR: ToolId.rect,
      LogicalKeyboardKey.keyO: ToolId.ellipse,
      LogicalKeyboardKey.keyG: ToolId.polygon,
      LogicalKeyboardKey.keyV: ToolId.select,
    };
    for (final entry in bindings.entries) {
      await tester.sendKeyEvent(entry.key);
      await tester.pumpAndSettle();
      expect(t.c.read(toolControllerProvider).id, entry.value,
          reason: '${entry.key.keyLabel} activates ${entry.value}');
    }

    // The rail: one button per tool, and pressing one is the same activation.
    for (final id in ToolId.values) {
      await tester.tap(find.byKey(Key('tool-${id.name}')));
      await tester.pumpAndSettle();
      expect(t.c.read(toolControllerProvider).id, id);
    }

    // Modal: exactly one active, so the last activation is the only one.
    expect(t.c.read(toolControllerProvider).id, ToolId.values.last);
  });

  testWidgets('bare G selects the polygon tool; Ctrl+G still groups',
      (tester) async {
    final t = await open(tester, children: [
      square('a', const Vec2(60, 60), 40),
      square('b', const Vec2(200, 120), 40),
    ]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(t.c.read(toolControllerProvider).id, ToolId.polygon);
    expect(docOf(t.c, t.id).root.children.whereType<GroupNode>(), isEmpty,
        reason: 'a bare G must not also group');

    // Select both and group with the modifier held — `SingleActivator` matches
    // modifiers exactly, so the two bindings cannot collide.
    t.c.read(editorControllerProvider.notifier)
      ..selectNode(const ScenePath(NodeId('a')))
      ..addToSelection(const ScenePath(NodeId('b')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(docOf(t.c, t.id).root.children.whereType<GroupNode>(), hasLength(1),
        reason: 'Ctrl+G still groups');
    expect(t.c.read(toolControllerProvider).id, ToolId.polygon,
        reason: 'and did not switch the tool a second time');
  });

  testWidgets('a tool key typed into a text field does not switch tools',
      (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    t.c
        .read(editorControllerProvider.notifier)
        .selectNode(const ScenePath(NodeId('sq')));
    await tester.pumpAndSettle();

    // The bindings are unmodified letters, and `CallbackShortcuts` sees a key
    // event travelling up from the primary focus whether or not an
    // `EditableText` is about to turn it into a character. Renaming a layer to
    // "Gear" must not also select the polygon tool.
    await tester.tap(find.byKey(const Key('inspector-position-x')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditableText>(find.descendant(
              of: find.byKey(const Key('inspector-position-x')),
              matching: find.byType(EditableText),
            ))
            .focusNode
            .hasFocus,
        isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(t.c.read(toolControllerProvider).id, ToolId.select,
        reason: 'the keystroke belongs to the field, not to the toolbar');
  });

  testWidgets('THE ACTIVE TOOL IS ACTUALLY INVOKED — down, move and up',
      (tester) async {
    // The M2 defect this pins: `SelectTool`'s handlers were never called,
    // `PointerCtx` was never constructed, and `ToolController.activate` had no
    // call site. A spy tool installed through the same seam `main.dart` uses is
    // the only way to assert the seam is live rather than decorative.
    final spy = _SpyTool();
    final s = seed();
    final c = ProviderContainer(overrides: [
      projectStoreProvider.overrideWithValue(s.store),
      toolResolverProvider.overrideWithValue((id) => spy),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    expect(spy.events, isEmpty);

    await tester.tapAt(toScreen(tester, const Vec2(200, 120)));
    await tester.pumpAndSettle();
    expect(spy.events, ['down', 'up'],
        reason: 'a tap is dispatched as a down and an up at the same point');

    spy.events.clear();
    await dragFrom(tester, const Vec2(100, 80), const Vec2(300, 160));
    expect(spy.events.first, 'down');
    expect(spy.events, contains('move'));
    expect(spy.events.last, 'up');

    // And the PointerCtx it was handed is the real one: the document, the
    // composed matrix, the playhead and the modifiers.
    final ctx = spy.last;
    expect(ctx, isNotNull);
    expect(ctx!.doc.artboard, artboard);
    expect(ctx.docPoint.x, closeTo(300, 0.5));
    expect(ctx.docPoint.y, closeTo(160, 0.5));
    expect(ctx.fit.invert(), isNotNull, reason: 'the ONE composed matrix');
    expect(ctx.playhead, 0.0);

    spy.events.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(spy.events, ['key:escape']);
  });

  testWidgets('switching tools cancels the outgoing tool\'s gesture',
      (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    await click(tester, const Vec2(80, 80));
    await click(tester, const Vec2(200, 80));

    // Two anchors in, the user picks the rectangle tool. The half path is
    // dropped: it must not reappear on the next `P`, and its two anchors must
    // never join whatever is drawn after them.
    activate(t.c, ToolId.rect);
    await tester.pumpAndSettle();
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    await click(tester, const Vec2(300, 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(docOf(t.c, t.id).root.children, isEmpty,
        reason: 'one anchor is not a path — and the abandoned two are gone');
  });

  // ==========================================================================
  // AC-4.1.5 — the recipe regeneration refusal
  // ==========================================================================

  testWidgets(
      'regenerating a recipe on a path-TRACKED node is a message, not a crash',
      (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);

    // Author a path keyframe by hand, exactly as a direct-select drag does.
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();
    await dragFrom(tester, const Vec2(80, 60), const Vec2(110, 90));
    expect(pathTrackOf(docOf(t.c, t.id), const NodeId('sq')), isNotNull);

    final before = jsonEncode(docOf(t.c, t.id).toJson());
    final message = await commandsFor(t.id).regenerateRecipe(
      const NodeId('sq'),
      const RectRecipe(w: 120, h: 40),
    );
    await tester.pumpAndSettle();

    expect(message, kAnimatedPathRecipeMessage,
        reason: 'a legal document is never an assert (docs/v3/08 §1) — the '
            'refusal names the work M5 owns');
    expect(jsonEncode(docOf(t.c, t.id).toJson()), before,
        reason: 'and the document is untouched');
    expect(tester.takeException(), isNull);
  });

  testWidgets('regenerating a recipe on an UNTRACKED node applies',
      (tester) async {
    final t = await open(tester);
    activate(t.c, ToolId.rect);
    await tester.pumpAndSettle();
    await dragFrom(tester, const Vec2(100, 60), const Vec2(200, 160));

    final node = onlyPath(docOf(t.c, t.id));
    final message = await commandsFor(t.id)
        .regenerateRecipe(node.id, const RectRecipe(w: 40, h: 20));
    await tester.pumpAndSettle();

    expect(message, isNull);
    final after = onlyPath(await reload(t.store, t.id));
    expect(after.recipe, const RectRecipe(w: 40, h: 20));
    expect(after.path.anchors, hasLength(4));
    // Fresh ids: `PathOps` is the only route to a topology change (AC-4.3.8).
    expect(
      after.path.anchors.map((a) => a.id.v).toSet(),
      isNot(node.path.anchors.map((a) => a.id.v).toSet()),
    );
  });
}

/// Hands a test the [WidgetRef] the command layer expects, from inside the
/// tree, and draws nothing.
class _RefProbe extends ConsumerWidget {
  const _RefProbe(this.onRef);

  final void Function(WidgetRef) onRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onRef(ref);
    return const SizedBox.shrink();
  }
}

/// A [ToolMode] that records what it was handed and mutates nothing.
final class _SpyTool implements ToolMode {
  final List<String> events = <String>[];
  PointerCtx? last;

  @override
  ToolId get id => ToolId.select;

  @override
  Command? onPointerDown(PointerCtx ctx) => _note('down', ctx);

  @override
  Command? onPointerMove(PointerCtx ctx) => _note('move', ctx);

  @override
  Command? onPointerUp(PointerCtx ctx) => _note('up', ctx);

  @override
  Command? onKey(ToolKey key, PointerCtx ctx) => _note('key:${key.name}', ctx);

  Command? _note(String event, PointerCtx ctx) {
    events.add(event);
    last = ctx;
    return null;
  }

  @override
  ToolEffect? takeEffect() => null;

  @override
  ToolPreview get preview => ToolPreview.none;

  @override
  void cancel() {}
}
