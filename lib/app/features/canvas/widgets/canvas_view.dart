import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter/gestures.dart'
    show
        DragStartBehavior,
        PointerHoverEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/command.dart';
import '../../../state/editor_controller.dart';
import '../../../state/tool_controller.dart';
import '../commands.dart';
import '../providers.dart';

/// The canvas panel: three stacked painters, the board's pan/zoom, and **the one
/// place a pointer becomes a tool event**.
///
/// ## What M3 changes, and why it is the milestone's first task
///
/// M2 left the tool layer a dead seam: `SelectTool`'s pointer handlers were
/// never invoked, `PointerCtx` was never constructed anywhere, and this file
/// re-implemented select, move, the pen and the anchor drag inline while reading
/// only `tool.id`. Four more tools arriving at that design would have been four
/// more branches in these handlers — every tool coupled to every other, and to
/// this widget.
///
/// Now there is one dispatch: build a [PointerCtx], hand it to whatever
/// [ToolMode] is active, and act on what comes back — a [Command] to run through
/// the command gate, a [ToolEffect] for the things a tool may not write itself
/// (selection, a refusal, the pen exiting to Select), and a [ToolPreview] to
/// paint. **This file names no tool.** It cannot: `features/canvas` may not
/// import `features/tools` (docs/v3/08 §3), so the vocabulary comes from
/// `state/tool_controller.dart` and the implementations are injected at
/// composition.
///
/// A tap is dispatched as a **down immediately followed by an up** at the same
/// point, so click-to-select and drag-to-move — or the pen's click versus its
/// click-drag — are one code path in each tool rather than two that can disagree
/// about what was hit.
///
/// **One composed matrix, and only one.** `composedFit(viewport, artboard,
/// size)` is computed once per build and is the single place the pan/zoom is
/// combined with the letterbox (AC-3.1.4). Its result is handed to all three
/// painters as their `fit`, ridden into every [PointerCtx], and inverted for
/// every hit-test — so a click can never land where the shape is not. There is
/// no second matrix and no per-axis scale helper anywhere.
///
/// **The viewport mutates nothing the document owns.** A pan or a zoom writes
/// only `EditorState.viewportTransform`; it pushes no command, bumps no `rev`,
/// and undo never restores it (docs/v3/04 §6 — "nothing is more disorienting
/// than undo moving the camera").
class CanvasView extends ConsumerStatefulWidget {
  const CanvasView({required this.projectId, super.key});

  final String projectId;

  /// Incremented once per `build`, for the test that proves scrubbing the
  /// playhead rebuilds **nothing** (docs/v3/04 §4). A pan/zoom or a selection
  /// change legitimately does rebuild — those are not the hot path — but a live
  /// scrub through `playheadProvider` must not.
  @visibleForTesting
  static int debugBuildCount = 0;

  @override
  ConsumerState<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends ConsumerState<CanvasView> {
  /// True while a viewport pan (Space-drag or middle-drag) is in flight. A pan
  /// writes only `EditorState.viewportTransform`, so there is nothing to commit
  /// on release — the flag just routes `onPanUpdate` away from the tool.
  bool _panning = false;

  /// Space is held: the Pan tool is armed and the cursor is a grab (docs/v3/05
  /// §3). Tracked for the cursor only; the pan decision re-reads
  /// [HardwareKeyboard] at gesture time so a key released mid-frame cannot strand
  /// the flag.
  bool _spaceHeld = false;

  /// The buttons of the current pointer, from the raw [Listener]. Lets the pan
  /// gesture tell a middle-drag from a left-drag — [GestureDetector]'s pan does
  /// not carry the button.
  int _pointerButtons = 0;

  /// The last laid-out canvas size, so the keyboard zoom shortcuts (which fire
  /// outside the [LayoutBuilder]) can find the cursor-independent focus — the
  /// canvas centre — and the fit scale for 100%.
  Size _lastSize = Size.zero;

  /// THE composed matrix, cached from the last build.
  ///
  /// Cached rather than recomputed in each handler, and that is the point: a
  /// handler that called `composedFit` itself would be a second call site for
  /// the one mapping AC-3.1.4 says must have exactly one, and the two would
  /// drift the first time a gutter or a min-zoom clamp appeared.
  Affine _fit = Affine.identity;

  /// Where the pointer was last seen, in canvas-local pixels. A drag end and a
  /// key event have no position of their own, and a tool asked to finish a
  /// gesture at `(0,0)` would close a pen path against the artboard's corner.
  Offset _lastLocal = Offset.zero;

  /// The active tool as of the last [build], cached so [dispose] can cancel its
  /// in-progress gesture without touching `ref` — flutter_riverpod disposes the
  /// element's ref before `State.dispose` runs. `build` watches the tool, so
  /// this is always the tool active at teardown. Cached the same way [_fit] and
  /// [_lastSize] are, for the same reason: a handler (here, `dispose`) that
  /// cannot reach the live provider reads the last value the build saw.
  ToolMode? _activeTool;

  /// True between [_onPanStart] and the end (or cancel) that closes it.
  ///
  /// **`onPanCancel` fires on every tap.** The tap and pan recognizers both
  /// track the pointer; the tap wins the arena, the pan is rejected, and
  /// `GestureDetector` reports that rejection as a cancel — even though no drag
  /// ever began. Cancelling the tool there wiped the pen's anchors after every
  /// single click, so no path could ever reach a second anchor. The flag makes
  /// the cancel mean what it says: *this drag* is being abandoned.
  bool _dragLive = false;

  final FocusNode _focus = FocusNode(debugLabel: 'canvas');

  @override
  void dispose() {
    // Cancel the active tool's in-progress gesture as the canvas goes away.
    // `toolControllerProvider` is a plain (non-autoDispose) provider at the app
    // root, so the tool instance and its private gesture state outlive this
    // widget: pick Pen, place two anchors, navigate back to the project list
    // (this dispose), reopen a project — and without this the stale half-path
    // renders immediately and the next click appends to it, eventually
    // committing an `AddNodeCommand` for a node built half from the previous
    // session into the NEW document. `cancel()` already fires on tool switch and
    // on pointer-cancel; binding it to the canvas's lifetime closes the third
    // door.
    //
    // Read off [_activeTool] rather than `ref`: flutter_riverpod disposes the
    // element's ref before `State.dispose` runs, so `ref.read` here throws. The
    // field is the tool the last `build` saw — and `build` watches the tool, so
    // it is the tool active at teardown.
    _activeTool?.cancel();
    _focus.dispose();
    super.dispose();
  }

  EditorController get _editor => ref.read(editorControllerProvider.notifier);

  ToolMode get _tool => ref.read(toolControllerProvider);

  /// The playhead, normalised into the range every op and mix requires. One
  /// definition, used by the hit-test, the preview and the commit.
  double _playheadT() {
    final t = ref.read(playheadProvider).value;
    return t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
  }

  // --- The one dispatch ----------------------------------------------------

  /// Everything a tool may read, for the pointer at [local].
  ///
  /// Null when there is no document yet or the composed matrix is singular — an
  /// **early return**, never `invert()!` (docs/v3/08 §1, §4). A degenerate
  /// camera means there is nowhere on the artboard the click could have landed,
  /// and inventing one is how a drag ends up somewhere the pointer is not.
  PointerCtx? _ctx(Offset local) {
    final doc = ref.read(canvasDocumentProvider(widget.projectId));
    if (doc == null) return null;
    final inverse = _fit.invert();
    if (inverse == null) return null;

    final animation = ref.read(activeAnimationProvider(widget.projectId));
    final t = _playheadT();
    final screen = Vec2(local.dx, local.dy);
    final keyboard = HardwareKeyboard.instance;
    return PointerCtx(
      docPoint: inverse.apply(screen),
      screenPoint: screen,
      fit: _fit,
      scene: evaluate(
        doc,
        animation == null
            ? const <AnimationMix>[]
            : <AnimationMix>[AnimationMix(animation, t)],
      ),
      doc: doc,
      editor: ref.read(editorControllerProvider),
      animation: animation,
      playhead: t,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
    );
  }

  /// Perform what the tool asked for, and say whether it asked for anything.
  ///
  /// The order is fixed here rather than per tool: the effect (selection, a
  /// refusal, a tool switch) first, then the document edit. A selection applied
  /// after the command would briefly point at the document the edit replaced.
  bool _emit(ToolMode tool, Command? command) {
    var acted = false;

    final effect = tool.takeEffect();
    if (effect != null) {
      acted = true;
      final selection = effect.selection;
      if (selection != null) _applySelection(selection);
      final activate = effect.activate;
      if (activate != null) {
        ref.read(toolControllerProvider.notifier).activate(activate);
      }
      _report(effect.message);
    }

    if (command != null) {
      acted = true;
      // Carry the editing keyframe so undo returns the user to the key they were
      // editing (docs/v3/04 §6). Null for a rest-pose edit — the snapshot reads
      // that as "carried none", never as "clear the selection".
      final keyframe = ref.read(editorControllerProvider).selectedKeyframe;
      _run(CanvasCommands(ref, widget.projectId)
          .run(command, keyframe: keyframe));
    }
    return acted;
  }

  /// Selection is `EditorState`, so the **canvas** writes it and the tool only
  /// asks (docs/v3/08 §2). Null fields mean "leave that half alone", which is
  /// what lets a handle grab select its node without an anchor click wiping the
  /// node selection out from under the inspector.
  void _applySelection(ToolSelection selection) {
    final nodes = selection.nodes;
    if (nodes != null) {
      if (selection.add) {
        for (final node in nodes) {
          _editor.addToSelection(node);
        }
      } else if (nodes.isEmpty) {
        _editor.clearSelection();
      } else {
        _editor.selectNode(nodes.first);
        for (final node in nodes.skip(1)) {
          _editor.addToSelection(node);
        }
      }
    }
    if (selection.setsAnchor) _editor.selectAnchor(selection.anchor);
  }

  /// Report the outcome **without awaiting it**.
  ///
  /// A gesture handler never `await`s the store (docs/v3/08 §2, last row): the
  /// command is handed to the serialised chain in [DocumentController] and the
  /// handler returns immediately, so a Firestore hiccup cannot freeze drawing.
  /// `onError` is a net under the command gate's own catch — a rejected edit
  /// must not escape as an unhandled async error.
  void _run(Future<String?> pending) {
    pending.then(
      _report,
      onError: (Object _, StackTrace __) => _report(kRejectedEditMessage),
    );
  }

  void _report(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Keyboard: pan arming, zoom shortcuts, Esc/Enter ---------------------

  bool get _cmdOrCtrl =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// True when the Pan tool is armed: Space is held, or the middle button is
  /// down (docs/v3/05 §3).
  ///
  /// **Every document gesture asks this first, not just the drag.** The Pan tool
  /// "Mutates via: *Nothing. Ephemeral only.*", and a tap is a document gesture:
  /// while this gated `onPanStart` alone, a click with Space held fell through
  /// to the drawing affordance and authored geometry with the camera.
  /// [HardwareKeyboard] is re-read at gesture time so a key released mid-frame
  /// cannot strand [_spaceHeld] armed.
  bool get _panArmed =>
      _spaceHeld ||
      HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space) ||
      _pointerButtons & kMiddleMouseButton != 0;

  /// Zoom shortcuts, Space-arming, and the tool's two keys. Requires a focused
  /// `FocusNode` — CanvasKit drops shortcuts without one (docs/v3/05 §5), which
  /// is why every canvas pointer-down re-requests focus.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final held = event is! KeyUpEvent;
      if (held != _spaceHeld) setState(() => _spaceHeld = held);
      // Not "handled": Space must still bubble for anything else that wants it.
      return KeyEventResult.ignored;
    }

    if (event is KeyUpEvent) return KeyEventResult.ignored;

    // `Esc` / `Enter` reach the active tool — the pen finishes its path with
    // them (docs/v3/05 §3). They are answered here rather than in the shell's
    // shortcut scope because they need a [PointerCtx], and the canvas is the
    // only place that exists.
    if (!_cmdOrCtrl) {
      final key = switch (event.logicalKey) {
        LogicalKeyboardKey.escape => ToolKey.escape,
        LogicalKeyboardKey.enter ||
        LogicalKeyboardKey.numpadEnter =>
          ToolKey.enter,
        _ => null,
      };
      if (key == null) return KeyEventResult.ignored;
      return _onToolKey(key);
    }

    final size = _lastSize;
    if (size.isEmpty) return KeyEventResult.ignored;
    final centre = Vec2(size.width / 2, size.height / 2);

    switch (event.logicalKey) {
      case LogicalKeyboardKey.digit0:
        _editor.fitArtboard(); // Cmd/Ctrl+0
        return KeyEventResult.handled;
      case LogicalKeyboardKey.digit1:
        final doc = ref.read(canvasDocumentProvider(widget.projectId));
        if (doc == null) return KeyEventResult.handled;
        // The fit's uniform scale, read **off the seam** rather than recomputed
        // here. `zoom100` cancels it, so one document unit is one screen pixel.
        // This used to be a local helper that took `min(w/x, h/y)` itself — a
        // second per-axis scale computation, which is literally what AC-3.1.4
        // says a grep must not find, and which would silently desync from any
        // future padding, gutter or min-zoom clamp inside `artboardFit`.
        _editor.zoom100(artboardFit(doc.artboard, size).a, centre); // Cmd+1
        return KeyEventResult.handled;
      case LogicalKeyboardKey.equal:
      case LogicalKeyboardKey.add:
        _editor.zoomAround(centre, 1.1); // Cmd/Ctrl+=
        return KeyEventResult.handled;
      case LogicalKeyboardKey.minus:
      case LogicalKeyboardKey.numpadSubtract:
        _editor.zoomAround(centre, 1 / 1.1); // Cmd/Ctrl+-
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// `Esc` with nothing in progress **deselects** (docs/v3/05 §5). With a pen
  /// path in progress the tool answers instead — which is why the fallback is
  /// conditioned on the tool having done nothing, rather than on this file
  /// knowing which tool is active.
  KeyEventResult _onToolKey(ToolKey key) {
    final ctx = _ctx(_lastLocal);
    if (ctx == null) return KeyEventResult.ignored;
    final tool = _tool;
    final acted = _emit(tool, tool.onKey(key, ctx));
    if (!acted && key == ToolKey.escape) _editor.clearSelection();
    setState(() {});
    return KeyEventResult.handled;
  }

  // --- Raw pointer: scroll-zoom + middle-drag pan --------------------------

  void _onPointerDown(PointerDownEvent event) {
    _pointerButtons = event.buttons;
    _lastLocal = event.localPosition;
    _focus.requestFocus();
  }

  /// The cursor moving with no button down.
  ///
  /// Tracked for exactly one reason: the pen's live segment has to follow the
  /// pointer *between* clicks, and a tool is only handed a `PointerCtx` on an
  /// event of its own. So the canvas keeps the position and hands it to the
  /// overlay as [DraftPath.cursor] — inverted through THE composed matrix, not
  /// a second one.
  ///
  /// **The repaint is gated on there being a draft in flight.** A `setState` per
  /// mouse move with nothing in progress is the rebuild storm docs/v3/04 §4
  /// exists to prevent, and it would run on every hover over the canvas for the
  /// whole session.
  void _onPointerHover(PointerHoverEvent event) {
    _lastLocal = event.localPosition;
    // Repaint when a draft is in flight (the pen's live segment follows the
    // cursor) OR the pen is hovering a selected path for its insert `+`
    // (docs/v3/05 §3). Both need the live pointer at paint time. Nothing else
    // repaints on a bare hover, so the whole-session hover storm docs/v3/04 §4
    // warns about stays gated — the `+` mode is only ever true with the pen
    // active over a single selected path node.
    if (_tool.preview.path != null || _penInsertActive()) {
      setState(() {});
    }
  }

  /// The pen is active over exactly one selected path node — the state that shows
  /// an insert `+` on hover. A cheap gate on the hover repaint; whether the hover
  /// is actually near a segment (and where the `+` sits) is decided in `build` by
  /// [_penInsertCursor].
  bool _penInsertActive() {
    final tool = _tool;
    if (tool.id != ToolId.pen || tool.preview.path != null) return false;
    final selection = ref.read(canvasSelectionProvider);
    if (selection.length != 1) return false;
    final doc = ref.read(canvasDocumentProvider(widget.projectId));
    return doc?.nodeIndex[selection.first.nodeId] is PathNode;
  }

  /// The document-space point a pen click would insert an anchor at, or null.
  ///
  /// Non-null only with the Pen active, not mid-drawing ([previewPath] null),
  /// exactly one selected path node, and the hover within a screen grab radius of
  /// one of that node's posed segments. The heavy lifting is [insertionCandidate]
  /// (anim_render) — the same call the pen tool commits through — so the mark the
  /// user sees and the point the click lands on are one computation. A singular
  /// camera yields a null inverse and therefore no `+`: an early return, never
  /// `invert()!` (docs/v3/08 §4).
  ///
  /// **Suppressed while a pan is armed**, the same [_panArmed] gate `_onTapUp`
  /// returns on: a Space-held (or middle-button) click pans and inserts nothing,
  /// so painting the `+` would advertise an edit the click will not make.
  Vec2? _penInsertCursor({
    required ToolMode tool,
    required PathData? previewPath,
    required Document doc,
    required AnimationId? animation,
    required Set<ScenePath> selection,
    required Affine fit,
  }) {
    if (_panArmed) return null;
    if (tool.id != ToolId.pen || previewPath != null) return null;
    if (selection.length != 1) return null;
    final nodeId = selection.first.nodeId;
    if (doc.nodeIndex[nodeId] is! PathNode) return null;

    final inverse = fit.invert();
    if (inverse == null) return null;
    final screen = Vec2(_lastLocal.dx, _lastLocal.dy);
    final hoverDoc = inverse.apply(screen);
    final mix = animation == null
        ? const <AnimationMix>[]
        : <AnimationMix>[AnimationMix(animation, _playheadT())];

    final hit = insertionCandidate(doc, mix, nodeId, hoverDoc);
    if (hit == null) return null;
    final at = fit.apply(hit.world);
    if (!at.x.isFinite || !at.y.isFinite) return null;
    if ((at - screen).length > PointerCtx.grabRadius) return null;
    return hit.world;
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointerButtons = event.buttons;
    _lastLocal = event.localPosition;
    // Middle-drag pans (docs/v3/05 §3). Left-drag is left to the GestureDetector
    // (the tool, or the Space-pan), so the two never both fire.
    if (event.buttons & kMiddleMouseButton != 0) {
      _editor.panBy(Vec2(event.delta.dx, event.delta.dy));
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_cmdOrCtrl) return; // only Cmd/Ctrl+scroll zooms (docs/v3/05 §3)
    // Scroll up (negative dy) zooms in. About the cursor, so the point under the
    // pointer stays put.
    final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
    _editor.zoomAround(
      Vec2(event.localPosition.dx, event.localPosition.dy),
      factor,
    );
  }

  // --- Tool gestures -------------------------------------------------------

  /// A tap is a **down and an up at the same point**, so a tool never has to
  /// implement clicking twice.
  void _onTapUp(TapUpDetails details) {
    _focus.requestFocus();
    if (_panArmed) return; // the camera authors nothing

    final ctx = _ctx(details.localPosition);
    if (ctx == null) return;
    _lastLocal = details.localPosition;

    final tool = _tool;
    _emit(tool, tool.onPointerDown(ctx));
    _emit(tool, tool.onPointerUp(ctx));
    setState(() {});
  }

  void _onPanStart(DragStartDetails details) {
    _focus.requestFocus();

    // The viewport pan wins whenever Space is held or the middle button drags.
    // Ephemeral: it mutates nothing the document owns.
    if (_panArmed) {
      _panning = true;
      return;
    }

    final ctx = _ctx(details.localPosition);
    if (ctx == null) return;
    _lastLocal = details.localPosition;
    _dragLive = true;

    final tool = _tool;
    _emit(tool, tool.onPointerDown(ctx));
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_panning) {
      _editor.panBy(Vec2(details.delta.dx, details.delta.dy));
      return;
    }

    final ctx = _ctx(details.localPosition);
    if (ctx == null) return;
    _lastLocal = details.localPosition;

    final tool = _tool;
    _emit(tool, tool.onPointerMove(ctx));
    setState(() {});
  }

  void _onPanEnd(DragEndDetails details) {
    if (_panning) {
      _panning = false; // viewport already written live; nothing to commit
      return;
    }

    _dragLive = false;

    // The end carries no position of its own, so the gesture finishes where the
    // last move left it.
    final ctx = _ctx(_lastLocal);
    if (ctx == null) return;

    final tool = _tool;
    _emit(tool, tool.onPointerUp(ctx));
    setState(() {});
  }

  /// A cancelled gesture (the pointer left, the app lost focus) drops the tool's
  /// in-flight state and its preview. Nothing was committed, so there is nothing
  /// to undo.
  void _onPanCancel() {
    if (_panning) {
      _panning = false;
      return;
    }
    // Only a drag that really started may be cancelled — see [_dragLive].
    if (!_dragLive) return;
    _dragLive = false;
    _tool.cancel();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    CanvasView.debugBuildCount++;

    // Named slices only (docs/v3/08 §2). The playhead is absent from every one
    // of these, which is why a live scrub rebuilds nothing here. The viewport
    // and selection slices *do* rebuild the canvas when they change — that is
    // correct, they are not the 60 fps path, and neither touches the Document.
    final doc = ref.watch(canvasDocumentProvider(widget.projectId));
    final board = ref.watch(canvasBackgroundProvider(widget.projectId));
    final nodes = ref.watch(canvasNodeCountProvider(widget.projectId));
    final animation = ref.watch(activeAnimationProvider(widget.projectId));
    final playhead = ref.watch(playheadProvider);
    final viewport = ref.watch(canvasViewportProvider);
    final selection = ref.watch(canvasSelectionProvider);
    // The active tool — watched, so switching tools repaints the affordances
    // that belong to it. Its in-flight gesture state is private to the tool and
    // reaches the painters only through [ToolPreview], which the pointer
    // handlers pick up with `setState`.
    final tool = ref.watch(toolControllerProvider);
    // Cache the live tool so `dispose` can cancel its in-flight gesture without
    // `ref` (see [_activeTool]).
    _activeTool = tool;
    final selectActive = tool.id == ToolId.select;

    if (doc == null || board == null) return const SizedBox.expand();
    final scheme = Theme.of(context).colorScheme;

    final preview = tool.preview;

    // WHAT THE PAINTERS SEE. During a drag this is the speculative document, so
    // the whole shape follows the anchor/node live. It is the committed document
    // at every other moment, and it is never the thing that gets saved.
    final painted = preview.document ?? doc;

    // A pose preview may mint an `Animation` on a document that had none, and
    // the painters must then name *that* id or they would render the rest pose
    // while the drag moves. The resolved id wins whenever there is one, so an
    // editor override is never overruled by a speculative default.
    final paintedAnimation = animation ?? preview.document?.defaultAnimationId;

    final cursor = _panning
        ? SystemMouseCursors.grabbing
        : (_spaceHeld ? SystemMouseCursors.grab : MouseCursor.defer);

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              _lastSize = size;

              // THE ONE composed matrix: viewport ∘ artboardFit, built once,
              // handed to all three painters, to every PointerCtx, and inverted
              // for every hit-test.
              final full = composedFit(viewport, doc.artboard, size);
              _fit = full;

              // The in-progress geometry channel: the tool supplies the path it
              // is building, the canvas supplies where the pointer is. Null when
              // no tool is building one, which is every moment between strokes.
              //
              // The cursor rides the inverse of `full` — the same matrix the
              // painters are handed and the same one every hit-test inverts
              // (AC-3.1.4). A singular camera yields a null inverse and
              // therefore no live segment: an EARLY RETURN, never `invert()!`
              // (docs/v3/08 §4). The placed anchors still draw, because they do
              // not need the inverse.
              final drawing = preview.path;
              final draft = drawing == null
                  ? null
                  : DraftPath(
                      path: drawing,
                      cursor: full
                          .invert()
                          ?.apply(Vec2(_lastLocal.dx, _lastLocal.dy)),
                      handle: preview.liveHandle,
                    );

              // The pen's `+` insert affordance (docs/v3/05 §3, AC-4.3.1): when
              // the pen is active over a SEGMENT of the one selected path node,
              // mark the nearest point a click would split. Computed here — only
              // the canvas holds the live hover position (`_lastLocal`) and THE
              // composed `full` — and drawn on the overlay, never in the document.
              // This file names the pen by `tool.id`, exactly as it does one line
              // below for `showAnchors`; the geometry itself lives in
              // `insertionCandidate` (anim_render), shared with the pen tool so
              // the hover mark and the click land on the same point.
              final insertCursor = _penInsertCursor(
                tool: tool,
                previewPath: drawing,
                doc: painted,
                animation: paintedAnimation,
                selection: selection,
                fit: full,
              );

              return Focus(
                focusNode: _focus,
                onKeyEvent: _onKey,
                child: MouseRegion(
                  cursor: cursor,
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerHover: _onPointerHover,
                    onPointerSignal: _onPointerSignal,
                    child: GestureDetector(
                      key: const Key('canvas'),
                      behavior: HitTestBehavior.opaque,
                      // Grab by what was under the pointer on DOWN, before the
                      // touch slop drifts it 20 px along the gesture.
                      dragStartBehavior: DragStartBehavior.down,
                      onTapUp: _onTapUp,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      onPanCancel: _onPanCancel,
                      // Three painters, and they stay three (docs/v3/08 §2),
                      // each in its own RepaintBoundary. All three take the same
                      // composed `full`, so the board, the geometry and the
                      // overlay never disagree about where the artboard is.
                      child: Stack(
                        children: [
                          RepaintBoundary(
                            child: CustomPaint(
                              size: size,
                              painter: BackgroundPainter(
                                artboard: board.$1,
                                background: board.$2,
                                edge: scheme.outlineVariant,
                                fit: full,
                              ),
                            ),
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              size: size,
                              painter: ArtboardPainter(
                                document: painted,
                                playhead: playhead,
                                animation: paintedAnimation,
                                fit: full,
                                // The editor never clips (AC-1.1.3):
                                // off-artboard geometry is legal, it draws, and
                                // it is selectable. The board's edge is drawn by
                                // layer 1, not enforced by a clip — a clip here
                                // hid shapes the hit-test and the overlay still
                                // happily answered for.
                                mode: RenderMode.editor,
                              ),
                            ),
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              size: size,
                              painter: OverlayPainter(
                                document: painted,
                                playhead: playhead,
                                animation: paintedAnimation,
                                anchor: scheme.surface,
                                anchorBorder: scheme.primary,
                                pendingColor: scheme.tertiary,
                                // The in-progress gesture: the shape tools' drag
                                // preview and direct select's grabbed point.
                                // Drawn over the document rather than inserted
                                // into it — a document that contains half a
                                // gesture cannot be reloaded, and autosave would
                                // persist it.
                                pending: preview.markers,
                                // The same gesture when it is a *shape* rather
                                // than a set of points: the pen's half-drawn
                                // path, stroked, with the segment that follows
                                // the cursor and the handle being pulled. Dots
                                // could not say any of that, which is the defect
                                // this channel closes.
                                draft: draft,
                                // The pen's insert `+`, or null when the pen is
                                // not hovering a selected path's segment.
                                insertCursor: insertCursor,
                                fit: full,
                                // Same mode as layer 2, always: handles must
                                // never outlive the geometry they belong to.
                                mode: RenderMode.editor,
                                // Anchor handles are Direct select's affordance
                                // (docs/v3/05 §3), so they are drawn for that
                                // tool and no other — a dot the active tool
                                // cannot grab is an invitation to a gesture that
                                // does nothing.
                                //
                                // Said outright. This used to be expressed by
                                // handing `selected` the geometry-less **root
                                // id**, leaning on the painter's "an empty set
                                // means every node" convention to make one
                                // impossible id mean "no node at all". It read
                                // as a bug at both ends, and simplifying it to
                                // `const {}` — the obvious tidy-up — would have
                                // meant the exact opposite.
                                showAnchors: tool.id == ToolId.directSelect,
                                // Node selection is shown only for Select.
                                selectedPaths:
                                    selectActive ? selection : const {},
                                selectionColor: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _ToolHint(tool: tool.id, nodes: nodes),
      ],
    );
  }
}

/// One sentence, naming the active tool and what it does next.
///
/// It is the only on-canvas discoverability the editor has: the tools are modal,
/// so a user who pressed a key by accident needs to be told which mode they are
/// in before they wonder why clicking does something else.
class _ToolHint extends StatelessWidget {
  const _ToolHint({required this.tool, required this.nodes});

  final ToolId tool;
  final int nodes;

  /// A map with a `?? ` fallback, not an exhaustive `switch` (docs/v3/08 §2): a
  /// tool added in v2 gets a generic hint, not a compile error in the canvas.
  static const Map<ToolId, String> _hints = <ToolId, String>{
    ToolId.select: 'Select · click a shape to select it, drag to move it',
    ToolId.directSelect: 'Direct select · drag an anchor or a handle · '
        'Alt+drag a handle breaks symmetry, Alt+click an anchor cycles its kind',
    ToolId.pen: 'Pen · click for a corner, click-drag for a curve, click the '
        'first anchor to close · Esc or Enter leaves it open',
    ToolId.rect: 'Rectangle · drag a box · Shift for a square, Alt from centre',
    ToolId.ellipse:
        'Ellipse · drag a box · Shift for a circle, Alt from centre',
    ToolId.polygon:
        'Polygon · drag a box · Shift to square it, Alt from centre',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: scheme.surfaceContainerHighest,
      child: Text(
        '${_hints[tool] ?? 'Tool'} · '
        '$nodes shape${nodes == 1 ? '' : 's'} in this document',
        key: const Key('tool-hint'),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
