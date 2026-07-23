import 'dart:convert';
import 'dart:io';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
// The refusal moved with the behaviour that raises it: M3 dispatches every
// pointer event through the active `ToolMode`, so declining to move a node
// whose transform is animated is now the Select tool's decision, and the
// sentence lives beside it. `features/canvas` may not import `features/tools`
// (docs/v3/08 §3), which is what forced — and settled — where it belongs.
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/features/tools/select/select_tool.dart'
    show kAnimatedTransformMessage;
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3 of M2: node selection, the Select tool's move, and the ephemeral
/// board pan/zoom.
///
/// These tests pin the three things phase 3 owns and the one thing it must
/// never touch. Selection lands in `EditorState` (never the document); a move is
/// **one** undo entry that undo reverts; and the pan/zoom writes only
/// `viewportTransform` — no command, no `rev` bump, never on disk. The composed
/// matrix `viewport ∘ artboardFit` is computed in exactly one place, and the
/// hit-test inverts that same matrix, so a click lands where the shape is.
void main() {
  /// **The lopsided board, everywhere.** 450.2 × 250.4 is the ratio docs/v3/00
  /// §5 and AC-1.1.2 name, and a square artboard conceals the legacy
  /// y-scaled-by-width defect completely: every assertion below — selection,
  /// front-most-wins, the locked gate, the move, the pan/zoom, the composed
  /// matrix — passes on a square board whether the mapping is right or wrong.
  /// The regression net was blind, not broken; this is what un-blinds it.
  const Vec2 artboard = Vec2(450.2, 250.4);

  /// A closed square whose fill is hittable — `[origin, origin+s]²`.
  PathNode square(String id, Vec2 origin, double s, {bool locked = false}) =>
      PathNode(
        id: NodeId(id),
        name: id,
        locked: locked,
        path: PathData(
          anchors: [
            Anchor(id: AnchorId('$id-0'), position: origin),
            Anchor(id: AnchorId('$id-1'), position: origin + Vec2(s, 0)),
            Anchor(id: AnchorId('$id-2'), position: origin + Vec2(s, s)),
            Anchor(id: AnchorId('$id-3'), position: origin + Vec2(0, s)),
          ],
          closed: true,
        ),
        fills: [
          Fill(
              id: PaintId('$id-fill'),
              paint: const SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0))),
        ],
      );

  /// A stored document whose root holds [children], on the lopsided artboard.
  ///
  /// Returns the store and the id. `rev` is bumped once (rev 1) so it loads and
  /// is not read-only, exactly like the M0 seed.
  ///
  /// [tracks] land on the document's default animation, which is how a document
  /// authored elsewhere (no M2 UI writes transform tracks) reaches the canvas.
  ({MemoryProjectStore store, String id}) seed(
    List<Node> children, {
    Map<NodeId, TrackSet> tracks = const {},
  }) {
    final base = Document.create(name: 'Sketch', artboard: artboard);
    var doc = base.copyWith(
      root: GroupNode(
        id: base.root.id,
        name: base.root.name,
        children: children,
      ),
    );
    if (tracks.isNotEmpty) {
      doc = doc.copyWith(animations: [
        for (final a in doc.animations)
          if (a.id == doc.defaultAnimationId) a.copyWith(tracks: tracks) else a,
      ]);
    }
    doc = doc.bumpRev();
    return (
      store: MemoryProjectStore({doc.id: jsonEncode(doc.toJson())}),
      id: doc.id,
    );
  }

  /// **The tool registry, installed exactly as `main.dart` installs it.**
  ///
  /// At M3 the canvas implements no direct manipulation of its own: every
  /// pointer event becomes a `PointerCtx` dispatched through the active
  /// `ToolMode`. Without this override `toolResolverProvider` resolves to the
  /// inert default — total, so nothing crashes, and a canvas that ignores every
  /// click. A fresh registry per container also keeps one test's in-progress
  /// gesture out of the next one's tool.
  ProviderContainer containerFor(MemoryProjectStore store) => ProviderContainer(
        overrides: [
          projectStoreProvider.overrideWithValue(store),
          toolResolverProvider.overrideWithValue(toolRegistry()),
        ],
      );

  Widget harness(ProviderContainer container, String id) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  Rect canvasRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('canvas')));

  /// The **same** mapping the canvas uses (`composedFit` with the identity
  /// viewport is `artboardFit`), so a document point converts to the exact
  /// screen pixel the painter drew it at.
  Offset toScreen(Vec2 doc, Rect box, {Affine viewport = Affine.identity}) {
    final s = composedFit(viewport, artboard, box.size).apply(doc);
    return box.topLeft + Offset(s.x, s.y);
  }

  EditorState editorOf(ProviderContainer c) => c.read(editorControllerProvider);

  Future<Document> reload(MemoryProjectStore store, String id) async =>
      Document.fromJson(
          jsonDecode((await store.load(id))!) as Map<String, Object?>);

  // --- Selection ------------------------------------------------------------

  testWidgets('clicking a node selects it; clicking empty clears it',
      (tester) async {
    final s = seed([square('sq', const Vec2(100, 100), 100)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final box = canvasRect(tester);
    await tester
        .tapAt(toScreen(const Vec2(150, 150), box)); // inside the square
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('sq'))});

    await tester.tapAt(toScreen(const Vec2(20, 20), box)); // empty space
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, isEmpty,
        reason: 'a click on empty clears the selection');
  });

  testWidgets('Shift+click adds a second node to the selection',
      (tester) async {
    final s = seed([
      square('a', const Vec2(50, 50), 60), // (50,50)-(110,110)
      square('b', const Vec2(250, 150), 60), // (250,150)-(310,210)
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final box = canvasRect(tester);
    await tester.tapAt(toScreen(const Vec2(80, 80), box));
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('a'))});

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(toScreen(const Vec2(280, 180), box));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(editorOf(c).selectedNodes,
        {const ScenePath(NodeId('a')), const ScenePath(NodeId('b'))},
        reason: 'Shift+click adds rather than replaces');
  });

  testWidgets('a locked node is not selectable (locked is a hit-test gate)',
      (tester) async {
    final s = seed([square('locked', const Vec2(100, 100), 100, locked: true)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final box = canvasRect(tester);
    await tester
        .tapAt(toScreen(const Vec2(150, 150), box)); // over the locked fill
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, isEmpty,
        reason: 'AC-2.2.6: a locked node is not hit-tested');
  });

  testWidgets('the front-most (last-painted) node wins when two overlap',
      (tester) async {
    // Draw order IS child order: `back` is index 0 (painted first, behind),
    // `front` is index 1 (painted last, on top). They overlap on
    // (140,100)-(180,140), and both fit the SHORT axis of the lopsided board.
    final s = seed([
      square('back', const Vec2(100, 60), 80),
      square('front', const Vec2(140, 100), 80),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final box = canvasRect(tester);
    await tester.tapAt(toScreen(const Vec2(160, 120), box)); // in the overlap
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('front'))},
        reason: 'front-most wins — the walk is drawOrder.reversed');
  });

  testWidgets('a group is clickable on the canvas, and drags like any node',
      (tester) async {
    // `a` and `b` leave a gap the group's union covers but neither square does.
    final s = seed([
      GroupNode(id: const NodeId('g'), name: 'g', children: [
        square('a', const Vec2(60, 60), 40), // (60,60)-(100,100)
        square('b', const Vec2(200, 140), 40), // (200,140)-(240,180)
      ]),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final doc = c.read(documentControllerProvider(s.id).notifier);
    final box = canvasRect(tester);
    const inTheGap = Vec2(150, 120);

    // A group used to be unhittable (null geometry) and un-outlined, so the
    // tree's own container nodes could not be operated on directly at all.
    await tester.tapAt(toScreen(inTheGap, box));
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('g'))},
        reason: 'the union of its descendants is its hit area');

    // A child still wins over its container where the two overlap.
    await tester.tapAt(toScreen(const Vec2(80, 80), box));
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('a'))});

    // And the group moves as ONE undo entry, carrying its children.
    const screenDelta = Offset(50, 30);
    await tester.dragFrom(toScreen(inTheGap, box), screenDelta);
    await tester.pumpAndSettle();

    final moved = (await reload(s.store, s.id)).root.children.single;
    expect(moved.id, const NodeId('g'));
    expect(moved.transform.position.x, greaterThan(0));
    expect(moved.transform.position.y, greaterThan(0));
    expect(
        ((moved as GroupNode).children.first as PathNode)
            .path
            .anchors
            .first
            .position,
        const Vec2(60, 60),
        reason: 'the group moved; its children are untouched geometry');
    expect(doc.canUndo, isTrue);
    await doc.undo();
    await tester.pumpAndSettle();
    expect(doc.canUndo, isFalse, reason: 'one drag, one entry');
  });

  // --- Off-artboard content (AC-1.1.3) --------------------------------------

  testWidgets(
      'a node outside the artboard is visible, selectable and draggable — '
      'the editor clips nothing', (tester) async {
    // 500 is past the board's 450.2 width. AC-1.1.3: it draws, and it is
    // clipped only in the export preview — so what the hit-test answers for is
    // what the user can see. The editor's painters are handed
    // `RenderMode.editor`, which produces no clip at all.
    final s = seed([square('off', const Vec2(500, 100), 40)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    expect(
        artboardClipRect(RenderMode.editor, artboard, Affine.identity), isNull,
        reason: 'the editor never clips the board');

    // Pan the camera until the off-board shape is over the canvas, exactly as a
    // user would, then use the SAME composed matrix to find the pixel.
    final editor = c.read(editorControllerProvider.notifier);
    editor.panBy(const Vec2(-260, 0));
    await tester.pumpAndSettle();
    final viewport = editorOf(c).viewportTransform;

    final box = canvasRect(tester);
    final at = toScreen(const Vec2(520, 120), box, viewport: viewport);
    expect(box.contains(at), isTrue, reason: 'the pan brought it into view');

    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('off'))},
        reason: 'off-artboard geometry is selectable (AC-1.1.3)');

    await tester.dragFrom(at, const Offset(-30, 20));
    await tester.pumpAndSettle();
    final moved = (await reload(s.store, s.id)).root.children.single;
    expect(moved.transform.position.x, lessThan(0),
        reason: 'and it drags, because it is really there');
  });

  // --- Move + undo ----------------------------------------------------------

  testWidgets(
      'dragging a selected node moves it as ONE undo entry; undo returns it; '
      'the disk never holds the viewport or the selection', (tester) async {
    final s = seed([square('sq', const Vec2(100, 100), 100)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final doc = c.read(documentControllerProvider(s.id).notifier);
    final editor = c.read(editorControllerProvider.notifier);
    final box = canvasRect(tester);
    final scale = artboardFit(artboard, box.size).apply(const Vec2(1, 0)).x -
        artboardFit(artboard, box.size).apply(Vec2.zero).x;

    // Select, then drag from inside the square by a clear screen delta. The
    // viewport is left at identity here so the drag geometry stays easy to
    // reason about; the pan/zoom-are-never-persisted proof comes after the
    // commit, below.
    await tester.tapAt(toScreen(const Vec2(150, 150), box));
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('sq'))});

    const screenDelta = Offset(60, 40);
    await tester.dragFrom(toScreen(const Vec2(150, 150), box), screenDelta);
    await tester.pumpAndSettle();

    // The node moved by the document-space delta (root is identity, so the
    // parent-inverse is identity and the delta is just screenDelta / scale).
    final moved =
        (await reload(s.store, s.id)).root.children.single as PathNode;
    expect(moved.transform.position.x, closeTo(screenDelta.dx / scale, 0.5));
    expect(moved.transform.position.y, closeTo(screenDelta.dy / scale, 0.5));

    // ONE undo entry: one undo reverts the whole move and empties the stack.
    expect(doc.canUndo, isTrue);
    await doc.undo();
    await tester.pumpAndSettle();
    final reverted = c
        .read(documentControllerProvider(s.id))
        .requireValue
        .root
        .children
        .single as PathNode;
    expect(reverted.transform.position, Vec2.zero,
        reason: 'undo returns the node to where it started');
    expect(doc.canUndo, isFalse, reason: 'the move was a single entry');

    // Move every scrap of ephemeral state — a panned+zoomed camera on top of the
    // live selection — and prove the saved file carries none of it. This is the
    // legacy defect (AC-2.2.7) that made documents unloadable.
    editor
      ..selectNode(const ScenePath(NodeId('sq')))
      ..panBy(const Vec2(33, -17))
      ..zoomAround(const Vec2(120, 90), 1.4);
    await tester.pumpAndSettle();
    final raw = (await s.store.load(s.id))!;
    expect(raw, isNot(contains('viewportTransform')));
    expect(raw, isNot(contains('selectedNodes')));
    expect(raw, isNot(contains('selectedAnchors')));
  });

  testWidgets(
      'the FIRST press-drag on an unselected shape selects it and moves it',
      (tester) async {
    // The owner's own "change the position of a drawn object" ask. This used to
    // require `selection.contains(hit)`, so the first press-drag was silently
    // inert and the user had to click, release, then drag — the opposite of
    // every editor's muscle memory.
    final s = seed([square('sq', const Vec2(100, 60), 60)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    expect(editorOf(c).selectedNodes, isEmpty, reason: 'nothing selected yet');

    final box = canvasRect(tester);
    await tester.dragFrom(
        toScreen(const Vec2(130, 90), box), const Offset(40, 25));
    await tester.pumpAndSettle();

    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('sq'))},
        reason: 'the press selected it');
    final moved = (await reload(s.store, s.id)).root.children.single;
    expect(moved.transform.position.x, greaterThan(0),
        reason: 'and the same gesture moved it');
    expect(moved.transform.position.y, greaterThan(0));
    expect(c.read(documentControllerProvider(s.id).notifier).canUndo, isTrue);
  });

  testWidgets(
      'a nested node follows the pointer exactly — the delta is mapped '
      'through the PARENT\'s evaluated world', (tester) async {
    // The ancestor rotates and scales non-uniformly, so a wrong parent-inverse
    // sends the shape off at an angle instead of under the cursor. The matrix
    // is read off the parent's `ResolvedNode`, never derived from the dragged
    // node's own authored local — that identity breaks the moment the node
    // carries a transform track.
    final s = seed([
      GroupNode(
        id: const NodeId('g'),
        name: 'g',
        transform: const Transform2(
            position: Vec2(60, 30), rotation: 0.6, scale: Vec2(1.4, 0.8)),
        children: [square('leaf', const Vec2(20, 20), 30)],
      ),
    ]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    Vec2 leafWorld(Document d) => evaluate(d, const <AnimationMix>[])
        .byPath[const ScenePath(NodeId('leaf'))]!
        .world
        .apply(const Vec2(35, 35)); // the square's centre, in leaf-local space

    final before = c.read(documentControllerProvider(s.id)).requireValue;
    final grabDoc = leafWorld(before);

    final box = canvasRect(tester);
    final fit = artboardFit(artboard, box.size);
    const screenDelta = Offset(45, -25);

    await tester.dragFrom(toScreen(grabDoc, box), screenDelta);
    await tester.pumpAndSettle();

    final after = leafWorld(await reload(s.store, s.id));
    // The pointer moved `screenDelta` on screen, so the shape moved exactly
    // that far in document space — `fit.a` is the one uniform scale.
    expect(after.x - grabDoc.x, closeTo(screenDelta.dx / fit.a, 0.01));
    expect(after.y - grabDoc.y, closeTo(screenDelta.dy / fit.a, 0.01));
  });

  testWidgets(
      'a node whose transform is animated refuses the drag and says so — '
      'no silent overwrite, no undo entry, no rev bump', (tester) async {
    // No M2 UI authors transform tracks, so this document comes from elsewhere
    // — and it is legal, decodable v3. The static `Transform2` a canvas drag
    // writes is masked by the track at every `t`, so committing it would record
    // an undo entry and bump `rev` for a change nobody can see. The refusal
    // used to be an `assert` on a legal document property: it threw out of
    // `_onPanEnd` in debug and silently overwrote in release.
    final s = seed(
      [square('sq', const Vec2(100, 60), 60)],
      tracks: {
        const NodeId('sq'): TrackSet({
          const PropertyKey(PropKey.position): Vec2Track([
            const Keyframe(t: 0.0, value: Vec2.zero),
            const Keyframe(t: 1.0, value: Vec2(60, 20)),
          ]),
        }),
      },
    );
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final doc = c.read(documentControllerProvider(s.id).notifier);
    final revBefore = c.read(documentControllerProvider(s.id)).requireValue.rev;
    final diskBefore = (await s.store.load(s.id))!;

    final box = canvasRect(tester);
    await tester.dragFrom(
        toScreen(const Vec2(130, 90), box), const Offset(40, 25));
    await tester.pumpAndSettle();

    expect(find.text(kAnimatedTransformMessage), findsOneWidget,
        reason: 'a refusal the user can read, not a silent no-op');
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('sq'))},
        reason: 'selecting it is still honest');
    expect(doc.canUndo, isFalse, reason: 'nothing was committed');
    expect(
        c.read(documentControllerProvider(s.id)).requireValue.rev, revBefore);
    expect(await s.store.load(s.id), diskBefore);
    expect(tester.takeException(), isNull,
        reason: 'a legal document property is never an assert');
  });

  // --- Board pan / zoom -----------------------------------------------------

  testWidgets(
      'taps with Space held mutate NOTHING — the Pan tool is ephemeral only',
      (tester) async {
    // docs/v3/05 §3, the Pan row: "Mutates via: Nothing. Ephemeral only." Only
    // `onPanStart` used to check the pan gate, so a *click* with Space held fell
    // through to `clearSelection()` and dropped a pen point — three of them
    // minted a node, bumped `rev` and pushed an undo entry. The camera was
    // authoring geometry.
    final s = seed([square('sq', const Vec2(100, 60), 60)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final doc = c.read(documentControllerProvider(s.id).notifier);
    final box = canvasRect(tester);

    // Focus the canvas the way a user does, and select something so the
    // "a Space-tap does not clear the selection either" half is observable.
    await tester.tapAt(toScreen(const Vec2(130, 90), box));
    await tester.pumpAndSettle();
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('sq'))});

    final revBefore = c.read(documentControllerProvider(s.id)).requireValue.rev;
    final diskBefore = (await s.store.load(s.id))!;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    for (final p in [
      const Vec2(20, 20),
      const Vec2(40, 30),
      const Vec2(30, 45)
    ]) {
      await tester.tapAt(toScreen(p, box));
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(c.read(documentControllerProvider(s.id)).requireValue.root.children,
        hasLength(1),
        reason: 'a Space-held click deposits no pen point');
    expect(c.read(documentControllerProvider(s.id)).requireValue.rev, revBefore,
        reason: 'the Pan tool bumps no rev');
    expect(doc.canUndo, isFalse, reason: 'and pushes nothing onto undo');
    expect(await s.store.load(s.id), diskBefore, reason: 'and writes nothing');
    expect(editorOf(c).selectedNodes, {const ScenePath(NodeId('sq'))},
        reason: 'nor does it clear the selection');

    // The gate is the pan arming, not a dead tap handler: with Space released
    // the same clicks reach the active tool and draw. (M0's three-click
    // triangle is gone — the Pen tool replaced it — so this is the same
    // property, asserted through the tool that owns drawing now.)
    c.read(toolControllerProvider.notifier).activate(ToolId.pen);
    await tester.pumpAndSettle();
    for (final p in [
      const Vec2(20, 20),
      const Vec2(40, 30),
      const Vec2(30, 45),
      const Vec2(20, 20), // back to the first anchor: closes and commits
    ]) {
      await tester.tapAt(toScreen(p, box));
      await tester.pumpAndSettle();
    }
    expect(c.read(documentControllerProvider(s.id)).requireValue.root.children,
        hasLength(2),
        reason: 'the pen still draws when the Pan tool is not armed');
  });

  testWidgets(
      'Cmd/Ctrl+1 zooms to 100% using the FIT\'s scale, read off the seam',
      (tester) async {
    // `_fitScale` used to recompute `min(w/x, h/y)` here — a second per-axis
    // scale helper, which AC-3.1.4 says a grep must not find, and which would
    // desync from any future padding or min-zoom clamp inside `artboardFit`.
    // On the lopsided board a per-axis slip lands the composed scale nowhere
    // near 1.
    final s = seed([square('sq', const Vec2(100, 60), 60)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final box = canvasRect(tester);
    await tester.tapAt(toScreen(const Vec2(130, 90), box)); // focus the canvas
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final composed =
        composedFit(editorOf(c).viewportTransform, artboard, box.size);
    expect(composed.a, closeTo(1.0, 1e-9),
        reason: '100% is one document unit per screen pixel');
    expect(composed.d, closeTo(1.0, 1e-9), reason: 'and uniformly so');
  });

  test(
      'zoom about the cursor holds the document point under the cursor — '
      'asserted through the SAME composed matrix the canvas uses', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = c.read(editorControllerProvider.notifier);
    const size = Size(800, 620);

    // Pan first — the camera is somewhere arbitrary — then resolve the document
    // point under the cursor through the SAME composed matrix the canvas uses.
    // `composedFit` is the one place viewport∘artboardFit is combined, so
    // inverting it is exactly what the hit-test does.
    const cursor = Vec2(337, 214);
    editor.panBy(const Vec2(45, -22));
    final before = composedFit(
        c.read(editorControllerProvider).viewportTransform, artboard, size);
    final docUnder = before.invert()!.apply(cursor);

    // Zoom about the cursor: the document point under it must not move.
    editor.zoomAround(cursor, 1.9);
    final after = composedFit(
        c.read(editorControllerProvider).viewportTransform, artboard, size);

    // The document point that was under the cursor is still under the cursor.
    final screenAfter = after.apply(docUnder);
    expect(screenAfter.x, closeTo(cursor.x, 1e-6));
    expect(screenAfter.y, closeTo(cursor.y, 1e-6));
  });

  test('Cmd/Ctrl+0 fits: the composed matrix collapses back to the plain fit',
      () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = c.read(editorControllerProvider.notifier);
    const size = Size(800, 620);

    editor
      ..panBy(const Vec2(80, 40))
      ..zoomAround(const Vec2(100, 100), 2.2)
      ..fitArtboard();

    final composed = composedFit(
        c.read(editorControllerProvider).viewportTransform, artboard, size);
    final fit = artboardFit(artboard, size);
    // Every field of the composed matrix equals the bare fit — identity viewport
    // IS the fit.
    expect(composed.a, closeTo(fit.a, 1e-12));
    expect(composed.d, closeTo(fit.d, 1e-12));
    expect(composed.tx, closeTo(fit.tx, 1e-12));
    expect(composed.ty, closeTo(fit.ty, 1e-12));
  });

  testWidgets(
      'any amount of panning and zooming leaves the document untouched — '
      'rev stable, nothing on the undo stack, nothing on disk', (tester) async {
    final s = seed([square('sq', const Vec2(100, 100), 100)]);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();

    final doc = c.read(documentControllerProvider(s.id).notifier);
    final editor = c.read(editorControllerProvider.notifier);
    final revBefore = c.read(documentControllerProvider(s.id)).requireValue.rev;
    final diskBefore = (await s.store.load(s.id))!;

    // Middle-mouse pan through the real Listener wiring, plus programmatic
    // zoom/fit — the viewport is a camera, not an edit.
    final box = canvasRect(tester);
    final g = await tester.startGesture(box.center,
        kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await g.moveBy(const Offset(25, 15));
    await g.moveBy(const Offset(25, 15));
    await g.up();
    await tester.pumpAndSettle();
    editor
      ..zoomAround(const Vec2(150, 120), 1.7)
      ..zoomAround(const Vec2(150, 120), 0.6)
      ..fitArtboard();
    await tester.pumpAndSettle();

    // The viewport moved (the pan wrote it), but the document did not.
    expect(c.read(documentControllerProvider(s.id)).requireValue.rev, revBefore,
        reason: 'a pan/zoom bumps no rev');
    expect(doc.canUndo, isFalse,
        reason: 'the viewport is never on the undo stack');
    expect(await s.store.load(s.id), diskBefore,
        reason: 'nothing was persisted by panning or zooming');
  });

  // --- The one composed-matrix seam ----------------------------------------

  test('viewport ∘ artboardFit is composed in exactly one place (AC-3.1.4)',
      () {
    // Structural guard: a second composition site — or a per-axis scale helper
    // on top of the fit — is exactly how a click lands where the shape is not.
    // Walk every library source and count the composition.
    final roots = [
      Directory('lib'),
      Directory('packages/anim_core/lib'),
      Directory('packages/anim_render/lib'),
    ];
    var definitions = 0;
    var compositions = 0;
    final composeRe = RegExp(r'\.mul\(\s*artboardFit\(');
    // "a grep for … a **per-axis scale helper** returns nothing" — AC-3.1.4,
    // verbatim. `_fitScale` in the canvas was exactly what this finds: a second
    // `min(size.width / artboard.x, size.height / artboard.y)`, numerically
    // identical today and silently desynced the moment `artboardFit` grows
    // padding, a gutter or a min-zoom clamp.
    final perAxisRe =
        RegExp(r'\.(width|height|maxWidth|maxHeight)\s*/\s*[\w.]+\.(x|y)\b');
    final perAxis = <String>[];
    for (final root in roots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (src.contains('Affine composedFit(')) definitions++;
        compositions += composeRe.allMatches(src).length;
        // The one legal site is `artboardFit` itself, which is *the* fit.
        if (entity.path.endsWith('path_geometry.dart')) continue;
        if (perAxisRe.hasMatch(src)) perAxis.add(entity.path);
      }
    }
    expect(definitions, 1, reason: 'composedFit is defined once');
    expect(compositions, 1,
        reason: 'viewport∘artboardFit is combined in exactly one spot');
    expect(perAxis, isEmpty,
        reason: 'the fit computes the one uniform scale; nobody re-derives it');
  });

  // --- What the overlay is asked to draw -----------------------------------

  test('the canvas says "no anchor handles" outright, never with the root id',
      () {
    // Structural guard, in the same spirit as the one above. The canvas used to
    // tell `OverlayPainter` to draw no anchors by passing the geometry-less
    // **root id** through `selected`, leaning on that painter's "an empty set
    // means every node" convention to make one impossible id mean "no node at
    // all". Nothing at either end said so; the first person to tidy it into
    // `const {}` would have turned handles on for every tool.
    //
    // A grep is the right shape of test for this because the defect is not a
    // behaviour — the pixels were correct — it is a spelling that reads as a
    // bug and invites the wrong fix.
    final source = File('lib/app/features/canvas/widgets/canvas_view.dart')
        .readAsStringSync();

    expect(source, contains('showAnchors:'),
        reason: 'the question is asked by name');
    expect(source.contains('root.id'), isFalse,
        reason: 'the sentinel is gone: the canvas has no reason to name the '
            'root when talking to the overlay');
    expect(source.contains('selected:'), isFalse,
        reason: 'and it no longer narrows the set either — narrowing was only '
            'ever the vehicle for the sentinel');
  });
}
