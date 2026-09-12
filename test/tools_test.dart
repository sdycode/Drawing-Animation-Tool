import 'dart:convert';
import 'dart:io';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart' show OverlayPainter, composedFit;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/canvas/commands.dart'
    show CanvasCommands;
import 'package:drawing_animation_tool/app/features/canvas/providers.dart'
    show canvasSelectionProvider;
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

  testWidgets(
      'a shape drag previews the OUTLINE as stroked geometry, not dots — and '
      'nothing reaches the document mid-drag', (tester) async {
    // The shape tools used to feed the overlay's `pending` markers channel, so
    // dragging out an ellipse showed FOUR DOTS and a polygon N dots — never the
    // outline. The pen was upgraded from dots to a stroked `DraftPath`; the
    // shapes now ride the same in-progress-geometry channel.
    final t = await open(tester);
    activate(t.c, ToolId.ellipse);
    await tester.pumpAndSettle();

    OverlayPainter overlay() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<OverlayPainter>()
        .single;

    // A drag held mid-gesture: a press and one move, no release.
    final g = await tester.startGesture(toScreen(tester, const Vec2(100, 60)));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveTo(toScreen(tester, const Vec2(220, 180)));
    await tester.pump(const Duration(milliseconds: 16));

    // The in-progress geometry reaches the overlay as a closed PATH — the
    // ellipse outline, four κ cubics — through the same channel the pen uses,
    // not as marker dots.
    final draft = overlay().draft;
    expect(draft, isNotNull);
    expect(draft?.path.closed, isTrue, reason: 'a shape is a closed outline');
    expect(draft?.path.anchors, hasLength(4),
        reason: 'ellipse: four κ cubics, not a scatter of dots');
    expect(overlay().pending, isEmpty,
        reason: 'the shape tools no longer speak in dots');

    // Recorded canvas ops: the outline is STROKED, and NOT one dot is drawn.
    final painter = overlay();
    final size = canvasRect(tester).size;
    expect((Canvas canvas) => painter.paint(canvas, size),
        paints..path(style: PaintingStyle.stroke));
    expect((Canvas canvas) => painter.paint(canvas, size),
        paintsExactlyCountTimes(#drawCircle, 0),
        reason: 'the drag preview is the shape outline, not corner dots');

    // And none of it is in the document the painters are handed, nor committed.
    expect(overlay().document.root.children, isEmpty);
    expect(docOf(t.c, t.id).root.children, isEmpty);

    await g.up();
    await tester.pumpAndSettle();

    // On release it commits ONE node, so this really was a live drag preview.
    expect(docOf(t.c, t.id).root.children, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'disposing the canvas cancels the active tool — no stale draft, no '
      'append on remount', (tester) async {
    // `toolControllerProvider` is a plain (non-autoDispose) provider at the app
    // root, so a PenTool with anchors in flight outlives the CanvasView.
    // Navigating back to the project list disposed the canvas but not the tool,
    // so reopening a project showed the stale half-path and the next click
    // appended to it — eventually committing a node built half from the previous
    // session into the NEW document.
    final t = await open(tester);
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    OverlayPainter overlay() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<OverlayPainter>()
        .single;

    // Two anchors placed: the pen's private `_anchors` holds a half-path.
    await click(tester, const Vec2(80, 80));
    await click(tester, const Vec2(240, 80));
    expect(overlay().draft?.path.anchors, hasLength(2),
        reason: 'two clicks, a two-anchor draft in flight');

    // Navigate away: pump a DIFFERENT widget over the SAME container, so the
    // tool (a root-scope Notifier) survives while the CanvasView is disposed —
    // exactly what returning to the project list mid-stroke does.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: t.c,
      child: const MaterialApp(home: SizedBox.expand()),
    ));
    await tester.pumpAndSettle();

    // Reopen the project: a fresh CanvasView.
    await tester.pumpWidget(harness(t.c, t.id));
    await tester.pumpAndSettle();

    // The half-path is gone — dispose cancelled the tool — and the pen is still
    // the active tool.
    expect(t.c.read(toolControllerProvider).id, ToolId.pen);
    expect(overlay().draft, isNull,
        reason: 'the stale draft did not survive the canvas being disposed');

    // A fresh click starts a NEW path, not an append to the two stale anchors.
    await click(tester, const Vec2(300, 200));
    final drawn = overlay().draft;
    expect(drawn?.path.anchors, hasLength(1),
        reason: 'one anchor: a brand-new path, not the stale two plus one');
    expect(drawn?.path.anchors.first.position.x, closeTo(300, 0.5));
    expect(drawn?.path.anchors.first.position.y, closeTo(200, 0.5));
    expect(docOf(t.c, t.id).root.children, isEmpty,
        reason: 'still nothing committed');
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

  /// Seed a document whose `sq` node carries a **3-key path track** authored
  /// through `PathOps` (so every keyframe poses exactly the topology), then mount
  /// the editor over it. Key 0/1/2 move `sq-0` to a distinct position each.
  Future<({ProviderContainer c, String id, MemoryProjectStore store})>
      openTrackedSquare(WidgetTester tester) async {
    final base = Document.create(name: 'Sketch', artboard: artboard);
    var doc = base.copyWith(
      root: GroupNode(
        id: base.root.id,
        name: base.root.name,
        children: [square('sq', const Vec2(80, 60), 90)],
      ),
    );
    const node = NodeId('sq');
    const anchor = AnchorId('sq-0');
    doc = PathOps.moveAnchor(doc, node, anchor, const Vec2(80, 60), atT: 0.0);
    doc = PathOps.moveAnchor(doc, node, anchor, const Vec2(120, 100), atT: 0.5);
    doc = PathOps.moveAnchor(doc, node, anchor, const Vec2(160, 140), atT: 1.0);
    doc = doc.bumpRev();
    final store = MemoryProjectStore({doc.id: jsonEncode(doc.toJson())});
    final c = containerFor(store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, doc.id));
    await tester.pumpAndSettle();
    return (c: c, id: doc.id, store: store);
  }

  testWidgets(
      'AC-4.2.3: a pose edit on a node with NO path track edits the REST pose '
      'and seeds NO track — and a kind cycle never creates one either',
      (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();

    expect(t.c.read(playheadProvider).value, 0.0, reason: 'at rest, t = 0');
    expect(pathTrackOf(docOf(t.c, t.id), const NodeId('sq')), isNull,
        reason: 'a static shape starts with no track');

    // Drag a corner at playhead 0.0.
    await dragFrom(tester, const Vec2(80, 60), const Vec2(120, 100));

    final saved = await reload(t.store, t.id);
    // NO animation/track was created (AC-4.2.3): the single default animation
    // stays empty, and there is no path track for the node anywhere.
    expect(pathTrackOf(saved, const NodeId('sq')), isNull,
        reason: 'AC-4.2.3: no silent auto-seed on a static shape');
    for (final animation in saved.animations) {
      expect(animation.tracks, isEmpty,
          reason: 'the default animation holds no tracks after a rest edit');
    }
    // The REST pose changed instead — the drag really happened.
    final moved = onlyPath(saved)
        .path
        .anchors
        .firstWhere((a) => a.id == const AnchorId('sq-0'));
    expect(moved.position.x, closeTo(120, 1.0));
    expect(moved.position.y, closeTo(100, 1.0));

    // Alt+click cycles AnchorKind — a non-animatable hint that lives on PathData
    // document-wide — and must NEVER seed an animation by itself.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await click(tester, const Vec2(120, 100)); // sq-0's new rest position
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    final afterKind = await reload(t.store, t.id);
    final kinded = onlyPath(afterKind)
        .path
        .anchors
        .firstWhere((a) => a.id == const AnchorId('sq-0'));
    expect(kinded.kind, AnchorKind.smooth,
        reason: 'corner → smooth, written onto PathData document-wide');
    expect(pathTrackOf(afterKind, const NodeId('sq')), isNull,
        reason: 'AC-4.2.3: cycling a kind creates no animation');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'edit-at-keyframe (AC-4.2.1, AC-6.2.6): with a 3-key path track, select '
      'key 2 and drag an anchor — only key 2 changes, keys 1 and 3 '
      'byte-identical', (tester) async {
    final t = await openTrackedSquare(tester);
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();

    const node = NodeId('sq');
    const anchor = AnchorId('sq-0');
    const pathKey = PropertyKey(PropKey.path);

    final before = pathTrackOf(docOf(t.c, t.id), node)!;
    expect(before.keyCount, 3);
    final key0Before = jsonEncode(before.keys[0].value.toJson());
    final key1Before = jsonEncode(before.keys[1].value.toJson());
    final key2Before = jsonEncode(before.keys[2].value.toJson());

    // Select key index 1 (t = 0.5) exactly as the timeline does — snapping the
    // playhead to the key. The canvas is now editing that key.
    t.c.read(editorControllerProvider.notifier).selectKeyframe(
          node,
          pathKey,
          1,
          snapT: before.keys[1].t,
        );
    await tester.pumpAndSettle();
    expect(t.c.read(playheadProvider).value, closeTo(0.5, 1e-9));

    // At t = 0.5 `sq-0` is posed at (120,100). Grab it there and drag.
    await dragFrom(tester, const Vec2(120, 100), const Vec2(150, 130));

    final after = pathTrackOf(await reload(t.store, t.id), node)!;
    expect(after.keyCount, 3,
        reason: 'no new key — an existing key was edited');
    expect(jsonEncode(after.keys[0].value.toJson()), key0Before,
        reason: 'AC-4.2.1: keyframe 1 (t = 0) is byte-identical');
    expect(jsonEncode(after.keys[2].value.toJson()), key2Before,
        reason: 'AC-4.2.1: keyframe 3 (t = 1) is byte-identical');
    expect(jsonEncode(after.keys[1].value.toJson()), isNot(key1Before),
        reason: 'only the selected keyframe 2 (t = 0.5) changed');

    final movedPose = after.keys[1].value.anchors[anchor]!;
    expect(movedPose.position.x, closeTo(150, 1.0));
    expect(movedPose.position.y, closeTo(130, 1.0));

    // The anchor SEQUENCE is untouched by a pose edit.
    final topology = (docOf(t.c, t.id).nodeIndex[node]! as PathNode)
        .path
        .anchors
        .map((a) => a.id.v)
        .toSet();
    for (final key in after.keys) {
      expect(key.value.anchors.keys.map((a) => a.v).toSet(), topology);
    }
  });

  testWidgets(
      'direct select drags a HANDLE on an untracked node — REST pose, no track '
      '(AC-4.2.3)', (tester) async {
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();

    // `sq-2` sits at (170,150) with an out-handle at (170,170).
    await dragFrom(tester, const Vec2(170, 170), const Vec2(210, 180));

    final node = (await reload(t.store, t.id)).nodeIndex[const NodeId('sq')]!
        as PathNode;
    expect(pathTrackOf(await reload(t.store, t.id), const NodeId('sq')), isNull,
        reason: 'AC-4.2.3: the tangents landed on the rest pose, no auto-seed');

    final anchor =
        node.path.anchors.firstWhere((a) => a.id == const AnchorId('sq-2'));
    expect(anchor.outTangent.x, closeTo(40, 0.5),
        reason: 'the handle followed the pointer, in NODE-LOCAL units');
    expect(anchor.position, const Vec2(170, 150),
        reason: 'a handle drag never moves the anchor');
    // `kind` is topology, not pose: untouched by a plain (no-Alt) handle drag.
    expect(anchor.kind, AnchorKind.symmetric);
  });

  testWidgets(
      'Alt+drag on a handle breaks symmetry — AnchorKind.corner on the REST '
      'pose (AC-4.2.3)', (tester) async {
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
        reason: 'docs/v3/05 §3: Alt+drag a handle BREAKS SYMMETRY, '
            'document-wide on PathData');
    expect(anchor.outTangent.x, closeTo(40, 0.5));
    expect(anchor.inTangent, const Vec2(0, -20),
        reason: 'a corner stores its handles verbatim — the opposite one is '
            'left exactly where its author put it, NOT zeroed, because the '
            'kind arrived together with a handle');
    expect(pathTrackOf(await reload(t.store, t.id), const NodeId('sq')), isNull,
        reason: 'AC-4.2.3: a rest-pose corner break seeds no track');
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
      'AC-4.1.5: regenerating a recipe on a path-TRACKED node ROUTES THROUGH '
      'retopologize — rewrites every keyframe, no refusal, no crash',
      (tester) async {
    final t = await openTrackedSquare(tester);
    const node = NodeId('sq');

    final tracked = pathTrackOf(docOf(t.c, t.id), node)!;
    expect(tracked.keyCount, 3);

    // A square (4 anchors) → a 6-point star (12 anchors): a topology change the
    // old in-place regeneration could not represent on a tracked node. It now
    // routes through PathOps.retopologize (arc-length correspondence).
    final message = await commandsFor(t.id).regenerateRecipe(
      node,
      const PolygonRecipe(sides: 6, radius: 60, star: true, innerRatio: 0.4),
    );
    await tester.pumpAndSettle();

    expect(message, isNull,
        reason: 'a tracked node no longer refuses — it retopologizes');
    expect(tester.takeException(), isNull);

    final after = pathTrackOf(await reload(t.store, t.id), node)!;
    final topology =
        (docOf(t.c, t.id).nodeIndex[node]! as PathNode).path.anchors;
    expect(topology, hasLength(12),
        reason: 'the node now carries the star topology (2 × 6 anchors)');

    // AC-4.3.6 on the NEW id set: every keyframe poses exactly the topology's
    // AnchorId sequence, in order — the disjoint-id-set state never reached the
    // evaluator.
    final ids = topology.map((a) => a.id.v).toList();
    expect(after.keyCount, 3,
        reason: 'the three keyframes survive the rewrite');
    for (final key in after.keys) {
      expect(key.value.anchors.keys.map((a) => a.v).toList(), ids,
          reason: 'AC-4.3.6: identical AnchorId sequence at every keyframe');
    }

    // The recipe is cleared (a retopologise is a manual topology edit no recipe
    // can regenerate) — so the shape section is now gone.
    expect((docOf(t.c, t.id).nodeIndex[node]! as PathNode).recipe, isNull);
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

  // ==========================================================================
  // M5 — PEN INSERT (AC-4.3.1), the headline flow, BY HAND
  // ==========================================================================

  /// Select [node] the way a user does — click its filled interior with the
  /// Select tool. The pen's insert affordance is offered only on a SELECTED path.
  Future<void> selectByClick(
      WidgetTester tester, ProviderContainer c, Vec2 interiorPoint) async {
    activate(c, ToolId.select);
    await tester.pumpAndSettle();
    await click(tester, interiorPoint);
  }

  testWidgets(
      'M5 EXIT BY HAND (docs/v3/00 §5 crit 3): insert an anchor at keyframe 1 of '
      'a 3-key path track, scrub 0→1 — no crash, no vanish, keyframes 2 & 3 '
      'PIXEL-IDENTICAL (≤1e-9)', (tester) async {
    final t = await openTrackedSquare(tester);
    const node = NodeId('sq');

    // Keyframes 2 & 3 (t = 0.5, t = 1.0), captured BEFORE the insert.
    final docBefore = docOf(t.c, t.id);
    final before05 = _geomAt(docBefore, node, 0.5);
    final before10 = _geomAt(docBefore, node, 1.0);
    final beforeIds = (docBefore.nodeIndex[node]! as PathNode)
        .path
        .anchors
        .map((a) => a.id)
        .toSet();
    expect(beforeIds, hasLength(4));

    // Return to keyframe 1 (t = 0.0) — openTrackedSquare starts there — and
    // SELECT the node by clicking its interior (Select tool).
    expect(t.c.read(playheadProvider).value, 0.0,
        reason: 'keyframe 1 is t = 0');
    await selectByClick(tester, t.c, const Vec2(125, 100));
    expect(
        t.c.read(canvasSelectionProvider).map((p) => p.nodeId).toSet(), {node});

    // Activate Pen and click the MID-POINT of the top edge (sq-0 → sq-1), which
    // at keyframe 1 runs (80,60) → (170,60). The click lands ON the segment.
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();
    await click(tester, const Vec2(125, 60));

    final docAfter = docOf(t.c, t.id);
    final afterNode = docAfter.nodeIndex[node]! as PathNode;
    expect(afterNode.path.anchors, hasLength(5),
        reason: 'ONE anchor was inserted mid-segment');

    // The pen did NOT replace the PathData: every original id survives and
    // exactly ONE fresh id was minted (a replacement re-mints all four).
    final afterIds = afterNode.path.anchors.map((a) => a.id).toSet();
    expect(afterIds.containsAll(beforeIds), isTrue,
        reason: 'existing ids are preserved — no raw path replacement');
    final newIds = afterIds.difference(beforeIds);
    expect(newIds, hasLength(1), reason: 'exactly one minted AnchorId');
    final newId = newIds.single;

    // It sits WHERE THE USER CLICKED at keyframe 1 (the AC-4.3.1 "u" landed).
    final geo0 = _geomAt(docAfter, node, 0.0);
    final newPose0 = geo0.anchors.firstWhere((a) => a.id == newId).position;
    expect(newPose0.x, closeTo(125, 1e-6));
    expect(newPose0.y, closeTo(60, 1e-6));

    // Recover the parameter u the op used (the same across every keyframe) from
    // keyframe 1, so the reconstruction below is exact.
    final bi0 = geo0.anchors.indexWhere((a) => a.id == const AnchorId('sq-0'));
    // geo0 already carries the new anchor; use the BEFORE geometry's segment.
    final before0 = _geomAt(docBefore, node, 0.0);
    final u = _projectU(
        before0.segment(
            before0.anchors.indexWhere((a) => a.id == const AnchorId('sq-0'))),
        newPose0);
    expect(u, closeTo(0.5, 1e-6), reason: 'the midpoint of the top edge');
    expect(bi0, greaterThanOrEqualTo(0));

    // --- Keyframes 2 & 3 are PIXEL-IDENTICAL -------------------------------
    // Mirror anim_core's insert golden: the two sub-cubics must reproduce the
    // original, and every OTHER segment is byte-identical.
    for (final (frameT, before) in <(double, PathData)>[
      (0.5, before05),
      (1.0, before10),
    ]) {
      final after = _geomAt(docAfter, node, frameT);
      final bi =
          before.anchors.indexWhere((a) => a.id == const AnchorId('sq-0'));
      final ai =
          after.anchors.indexWhere((a) => a.id == const AnchorId('sq-0'));
      expect(after.anchors[(ai + 1) % after.anchors.length].id, newId,
          reason: 'the new anchor is spliced immediately after sq-0');

      final cBefore = before.segment(bi);
      final cLeft = after.segment(ai);
      final cRight = after.segment((ai + 1) % after.segmentCount);
      var worst = 0.0;
      for (var i = 0; i <= 400; i++) {
        final w = i / 400.0;
        final expected = _cubicAt(cBefore, w);
        final actual = w <= u
            ? _cubicAt(cLeft, w / u)
            : _cubicAt(cRight, (w - u) / (1.0 - u));
        final e = (actual - expected).length;
        if (e > worst) worst = e;
      }
      expect(worst, lessThan(1e-9),
          reason: 't=$frameT: keyframe pixel-identical (worst $worst)');

      // Every other segment is untouched.
      _expectSegment(after.segment((ai + 2) % after.segmentCount),
          before.segment((bi + 1) % before.segmentCount));
      _expectSegment(after.segment((ai + 3) % after.segmentCount),
          before.segment((bi + 2) % before.segmentCount));
    }

    // --- Scrub the full range: no crash, no vanish, no freeze --------------
    for (var i = 0; i <= 20; i++) {
      final frameT = i / 20.0;
      t.c.read(playheadProvider).value = frameT;
      await tester.pump();
      final geo = _geomAt(docAfter, node, frameT);
      expect(geo.anchors, hasLength(5),
          reason: 'topology stays stable across the scrub');
      for (final a in geo.anchors) {
        expect(a.position.x.isFinite && a.position.y.isFinite, isTrue,
            reason: 'no NaN at t=$frameT');
      }
    }
    // Present at t = 1.0 (legacy's vanishing shape is gone).
    expect(_geomAt(docAfter, node, 1.0).segmentCount, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AC-4.3.3: the pen insert is ONE command / ONE undo entry, reverts cleanly',
      (tester) async {
    final t = await openTrackedSquare(tester);
    const node = NodeId('sq');
    // The topology and every keyframe pose, before the insert (rev is excluded:
    // the insert saves and the undo re-saves, so rev legitimately bumps — the
    // claim is that the GEOMETRY reverts as one entry).
    String snapshot() {
      final n = docOf(t.c, t.id).nodeIndex[node]! as PathNode;
      final keys = pathTrackOf(docOf(t.c, t.id), node)!
          .keys
          .map((k) => k.value.toJson())
          .toList();
      return jsonEncode(<String, Object?>{
        'anchors': n.path.anchors.map((a) => a.id.v).toList(),
        'keys': keys,
      });
    }

    final before = snapshot();

    await selectByClick(tester, t.c, const Vec2(125, 100));
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();
    await click(tester, const Vec2(125, 60));

    expect((docOf(t.c, t.id).nodeIndex[node]! as PathNode).path.anchors,
        hasLength(5));

    // ONE undo reverts the whole document-wide insert.
    final controller = t.c.read(documentControllerProvider(t.id).notifier);
    expect(controller.canUndo, isTrue);
    await controller.undo();
    await tester.pumpAndSettle();

    expect(snapshot(), before,
        reason: 'one undo restores the topology and every touched keyframe');
  });

  testWidgets(
      'the pen inserts only on a SELECTED path; a click on empty space starts a '
      'new path instead of inserting', (tester) async {
    final t = await openTrackedSquare(tester);
    const node = NodeId('sq');

    // Pen active but NOTHING selected: a click far from the square is an ordinary
    // first anchor of a NEW path, never an insert on the (unselected) square.
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();
    await click(tester, const Vec2(300, 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect((docOf(t.c, t.id).nodeIndex[node]! as PathNode).path.anchors,
        hasLength(4),
        reason: 'the square is untouched — insert needs a selected path');
  });

  testWidgets(
      'AC-4.3.1: the pen draws the insert `+` on HOVER over a selected path '
      'segment — and NOT while Space pans, nor mid-drawing a new path',
      (tester) async {
    // The exit test drives the CLICK insert; nothing proved the visible `+`
    // renders on hover, so a refactor could drop the affordance and the suite
    // would stay green (the M2/M4 "affordance unproven" shape).
    final t =
        await open(tester, children: [square('sq', const Vec2(80, 60), 90)]);
    const node = NodeId('sq');

    // The live OverlayPainter (layer 3 of three). A headless raster is blank, so
    // the assertions read the RECORDED canvas ops: the `+` is two crossed
    // `drawLine`s, and nothing else on a pen hover records a line (handle lines
    // belong to Direct select's `showAnchors`, off here).
    OverlayPainter overlay() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<OverlayPainter>()
        .single;
    final size = canvasRect(tester).size;

    // Select the path (Select tool, click its interior) and arm the Pen.
    await selectByClick(tester, t.c, const Vec2(125, 100));
    expect(
        t.c.read(canvasSelectionProvider).map((p) => p.nodeId).toSet(), {node});
    activate(t.c, ToolId.pen);
    await tester.pumpAndSettle();

    // Hover the midpoint of the top edge sq-0 → sq-1 ((80,60) → (170,60)). No
    // tool is handed a hover, so the canvas tracks the pointer itself.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: toScreen(tester, const Vec2(80, 60)));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(toScreen(tester, const Vec2(125, 60)));
    await tester.pumpAndSettle();

    expect(overlay().insertCursor, isNotNull,
        reason: 'the `+` sits on the hovered segment');
    expect((Canvas c) => overlay().paint(c, size),
        paintsExactlyCountTimes(#drawLine, 2),
        reason: 'the `+` is drawn — two crossed lines, recorded on the canvas');

    // Fix 3: a Space-held click PANS and inserts nothing (`_onTapUp` returns on
    // `_panArmed`), so advertising the `+` would promise an edit the click will
    // not make. `HardwareKeyboard` reads the held Space, the same gate.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await mouse.moveTo(toScreen(tester, const Vec2(126, 60)));
    await tester.pumpAndSettle();
    expect(overlay().insertCursor, isNull,
        reason: 'Space arms the pan — the insert `+` is suppressed');
    expect((Canvas c) => overlay().paint(c, size),
        paintsExactlyCountTimes(#drawLine, 0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await mouse.moveTo(toScreen(tester, const Vec2(125, 60)));
    await tester.pumpAndSettle();
    expect(overlay().insertCursor, isNotNull,
        reason: 'Space released — the `+` returns');

    // Mid-drawing a NEW path: place a first anchor far from the square, and the
    // pen is now building geometry — the insert `+` must not compete with the
    // live rubber band.
    await click(tester, const Vec2(300, 200));
    await mouse.moveTo(toScreen(tester, const Vec2(125, 60)));
    await tester.pumpAndSettle();
    expect(overlay().insertCursor, isNull,
        reason: 'mid-drawing, the pen builds a path — no insert affordance');
  });

  // ==========================================================================
  // M5 — DELETE ANCHOR (AC-4.3.5), Del / Backspace with Direct select
  // ==========================================================================

  testWidgets(
      'AC-4.3.5: Del removes the selected anchor from the topology AND every '
      'keyframe; ONE undo entry; no crash afterwards', (tester) async {
    final t = await openTrackedSquare(tester);
    const node = NodeId('sq');

    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();
    // Grab sq-0 at its keyframe-1 pose (80,60) → selects the node AND the anchor.
    await click(tester, const Vec2(80, 60));
    expect(t.c.read(editorControllerProvider).selectedAnchors,
        {const AnchorId('sq-0')});

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    final after = docOf(t.c, t.id).nodeIndex[node]! as PathNode;
    expect(after.path.anchors.map((a) => a.id.v), ['sq-1', 'sq-2', 'sq-3'],
        reason: 'sq-0 removed from the topology');

    final track = pathTrackOf(docOf(t.c, t.id), node)!;
    expect(track.keyCount, 3, reason: 'the keyframes survive');
    for (final key in track.keys) {
      expect(key.value.anchors.containsKey(const AnchorId('sq-0')), isFalse,
          reason: 'sq-0 removed from every keyframe pose');
      expect(key.value.anchors.keys.map((a) => a.v).toList(),
          ['sq-1', 'sq-2', 'sq-3'],
          reason: 'AC-4.3.6 holds on the reduced id set');
    }

    // The anchor selection is cleared, and a repaint after the delete does not
    // crash on the (now absent) id.
    expect(t.c.read(editorControllerProvider).selectedAnchors, isEmpty);
    t.c.read(playheadProvider).value = 0.7;
    await tester.pump();
    expect(tester.takeException(), isNull);

    // ONE undo restores the anchor into the topology and every keyframe.
    await t.c.read(documentControllerProvider(t.id).notifier).undo();
    await tester.pumpAndSettle();
    final restored = docOf(t.c, t.id).nodeIndex[node]! as PathNode;
    expect(restored.path.anchors, hasLength(4));
    expect(
        pathTrackOf(docOf(t.c, t.id), node)!
            .keys
            .first
            .value
            .anchors
            .containsKey(const AnchorId('sq-0')),
        isTrue);
  });

  testWidgets('Del does NOT fire while a text field has focus', (tester) async {
    final t = await openTrackedSquare(tester);
    const node = NodeId('sq');

    activate(t.c, ToolId.directSelect);
    await tester.pumpAndSettle();
    await click(tester, const Vec2(80, 60)); // select node + anchor sq-0
    expect(t.c.read(editorControllerProvider).selectedAnchors,
        {const AnchorId('sq-0')});

    // Focus an inspector number field — now typing owns the keyboard.
    await tester.tap(find.byKey(const Key('inspector-position-x')));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect((docOf(t.c, t.id).nodeIndex[node]! as PathNode).path.anchors,
        hasLength(4),
        reason: 'the field ate the Backspace — the anchor is NOT deleted');
  });

  testWidgets(
      'Del with only a NODE selected (Select tool) deletes the NODE, not an '
      'anchor — and ONE Ctrl+Z brings it back with its tracks', (tester) async {
    final t = await openTrackedSquare(tester);
    const node = NodeId('sq');

    await selectByClick(tester, t.c, const Vec2(125, 100)); // Select tool
    expect(t.c.read(canvasSelectionProvider), isNotEmpty);
    expect(t.c.read(editorControllerProvider).selectedAnchors, isEmpty);
    expect(pathTrackOf(docOf(t.c, t.id), node), isNotNull,
        reason: 'the square is animated, so the delete has tracks to prune');

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    // The one key, resolved to its node-level meaning: no anchor was selected,
    // so this is not a DeleteAnchorCommand at all.
    expect(docOf(t.c, t.id).root.children, isEmpty,
        reason: 'Del with a node selected removes the node (F2.2)');
    expect(docOf(t.c, t.id).nodeIndex[node], isNull);
    expect(pathTrackOf(docOf(t.c, t.id), node), isNull,
        reason: 'its tracks go with it — no orphan keyframes in the save');
    expect(t.c.read(canvasSelectionProvider), isEmpty,
        reason: 'the selection does not outlive the node it pointed at');

    // ONE undo, because it was ONE command — tree and tracks return together.
    await t.c.read(documentControllerProvider(t.id).notifier).undo();
    await tester.pumpAndSettle();
    final back = docOf(t.c, t.id);
    expect(back.root.children, hasLength(1));
    expect((back.nodeIndex[node]! as PathNode).path.anchors, hasLength(4));
    expect(pathTrackOf(back, node), isNotNull,
        reason: 'undo restores the pruned tracks, not just the tree');
  });

  // ==========================================================================
  // M5 — structural: the pen reaches topology ONLY through PathOps
  // ==========================================================================

  test(
      'the pen tool cannot replace a PathData — its only topology reach is '
      'InsertAnchorCommand', () {
    final source =
        File('lib/app/features/tools/pen/pen_tool.dart').readAsStringSync();
    expect(source.contains('InsertAnchorCommand'), isTrue,
        reason: 'insert is reachable');
    // No raw path replacement of an existing node, and no other topology op.
    expect(source.contains('.copyWith(path:'), isFalse);
    expect(source.contains('RetopologizeCommand'), isFalse);
    expect(source.contains('DeleteAnchorCommand'), isFalse);
    expect(source.contains('PathData.trusted'), isFalse);
  });
}

/// The node's posed geometry at [t] (stages 1–8), for the pixel-identity checks.
PathData _geomAt(Document d, NodeId n, double t) {
  final scene =
      evaluate(d, <AnimationMix>[AnimationMix(d.defaultAnimation!.id, t)]);
  return scene.byPath[ScenePath(n)]!.geometry!;
}

Vec2 _cubicAt((Vec2, Vec2, Vec2, Vec2) seg, double u) {
  final (p0, p1, p2, p3) = seg;
  final v = 1.0 - u;
  return p0 * (v * v * v) +
      p1 * (3 * v * v * u) +
      p2 * (3 * v * u * u) +
      p3 * (u * u * u);
}

Vec2 _cubicDeriv((Vec2, Vec2, Vec2, Vec2) seg, double u) {
  final (p0, p1, p2, p3) = seg;
  final v = 1.0 - u;
  return (p1 - p0) * (3 * v * v) +
      (p2 - p1) * (6 * v * u) +
      (p3 - p2) * (3 * u * u);
}

Vec2 _cubicDeriv2((Vec2, Vec2, Vec2, Vec2) seg, double u) {
  final (p0, p1, p2, p3) = seg;
  final v = 1.0 - u;
  return (p2 - p1 * 2.0 + p0) * (6 * v) + (p3 - p2 * 2.0 + p1) * (6 * u);
}

/// The parameter on [seg] nearest [q] — dense sample then Newton, for recovering
/// the op's `u` from a point known to lie on the curve (to machine precision).
double _projectU((Vec2, Vec2, Vec2, Vec2) seg, Vec2 q) {
  var bestU = 0.0;
  var bestDist = double.infinity;
  for (var i = 0; i <= 1000; i++) {
    final u = i / 1000.0;
    final d = (_cubicAt(seg, u) - q).length;
    if (d < bestDist) {
      bestDist = d;
      bestU = u;
    }
  }
  var u = bestU;
  for (var it = 0; it < 40; it++) {
    final b = _cubicAt(seg, u);
    final d1 = _cubicDeriv(seg, u);
    final d2 = _cubicDeriv2(seg, u);
    final ex = b.x - q.x;
    final ey = b.y - q.y;
    final f1 = ex * d1.x + ey * d1.y;
    final f2 = d1.x * d1.x + d1.y * d1.y + ex * d2.x + ey * d2.y;
    if (f2 == 0) break;
    final next = (u - f1 / f2).clamp(0.0, 1.0);
    if ((next - u).abs() < 1e-15) {
      u = next;
      break;
    }
    u = next;
  }
  return u;
}

void _expectSegment(
    (Vec2, Vec2, Vec2, Vec2) actual, (Vec2, Vec2, Vec2, Vec2) expected) {
  for (final (a, e) in <(Vec2, Vec2)>[
    (actual.$1, expected.$1),
    (actual.$2, expected.$2),
    (actual.$3, expected.$3),
    (actual.$4, expected.$4),
  ]) {
    expect((a - e).length, lessThan(1e-9));
  }
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
