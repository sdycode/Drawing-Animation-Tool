import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter/gestures.dart'
    show
        DragStartBehavior,
        PointerScrollEvent,
        PointerSignalEvent,
        kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_controller.dart';
import '../../../state/tool_controller.dart';
import '../commands.dart';
import '../providers.dart';

/// The canvas panel: three stacked painters, the Select tool, and the board's
/// pan/zoom.
///
/// **What M2 adds to the M0 canvas.** The pen (three clicks) and the anchor drag
/// stay exactly as they were — they are the drawing affordance until M3 splits
/// them into the Pen and Direct-select tools — and layered on top are: node
/// selection and move for the Select tool (F3.1), and an *ephemeral* board
/// pan/zoom (owner decision, docs/v3/05 §3).
///
/// **One composed matrix, and only one.** `composedFit(viewport, artboard,
/// size)` is computed once per build and is the single place the pan/zoom is
/// combined with the letterbox (AC-3.1.4). Its result is handed to all three
/// painters as their `fit`, and its inverse maps every pointer back to document
/// space — the pen click, the anchor grab, the node hit-test and the move drag
/// all invert the *same* matrix, so a click can never land where the shape is
/// not. There is no second matrix and no per-axis scale helper anywhere.
///
/// **The viewport mutates nothing the document owns.** A pan or a zoom writes
/// only `EditorState.viewportTransform`; it pushes no command, bumps no `rev`,
/// and undo never restores it (docs/v3/04 §6 — "nothing is more disorienting
/// than undo moving the camera"). A pan/zoom *may* rebuild this subtree — it is
/// not the 60 fps path — but it never touches the `Document`.
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

/// An anchor drag in flight (the M0 pose edit).
///
/// Private to the tool, exactly as docs/v3/08 §2 requires: never in `Document`
/// (a document holding half a gesture cannot be reloaded, and autosave would
/// persist it) and never in `EditorState` (every panel watching editor state
/// would then rebuild 60 times a second while the pointer moves).
@immutable
class _AnchorDrag {
  const _AnchorDrag({
    required this.node,
    required this.anchor,
    required this.base,
    required this.screenToArtboard,
    required this.worldToLocal,
    required this.position,
  });

  final NodeId node;
  final AnchorId anchor;

  /// The document the gesture started from, captured once, so the preview is a
  /// function of what the user grabbed rather than of whatever arrives
  /// underneath the pointer mid-drag.
  final Document base;

  /// Captured once, at drag start, from the *same* composed matrix the painters
  /// used. Recomputing it per pointer event would be a second mapping, and two
  /// mappings is how a drag lands where the pointer is not.
  final Affine screenToArtboard;

  /// The node's world matrix, inverted. `PathOps.moveAnchor` writes a **local**
  /// position, so the artboard-space pointer has to come back through the node's
  /// own transform.
  final Affine worldToLocal;

  /// Live pointer position in **document** space.
  final Vec2 position;

  _AnchorDrag at(Vec2 next) => _AnchorDrag(
        node: node,
        anchor: anchor,
        base: base,
        screenToArtboard: screenToArtboard,
        worldToLocal: worldToLocal,
        position: next,
      );
}

/// A node move in flight — the Select tool's drag (docs/v3/05 §3, F3.1).
///
/// Private to the tool for the same reason [_AnchorDrag] is: an unfinished move
/// must never reach `Document` (autosave) or `EditorState` (undo). The move
/// translates the node's [Transform2.position] by the pointer's document-space
/// delta mapped through the node's **parent-world inverse**, so the geometry
/// follows the cursor exactly whatever the ancestor chain does to it.
@immutable
class _NodeDrag {
  const _NodeDrag({
    required this.node,
    required this.path,
    required this.base,
    required this.original,
    required this.current,
    required this.parentInverse,
    required this.screenToDoc,
    required this.startDoc,
  });

  final NodeId node;
  final ScenePath path;
  final Document base;

  /// The node's transform when the drag began, and the transform as posed by the
  /// live delta. Only [current] is committed, and only on release.
  final Transform2 original;
  final Transform2 current;

  /// `parentWorld⁻¹`, inverted from the parent's **evaluated** world.
  ///
  /// Its **linear part** (via `applyVector`) maps a document-space delta into
  /// the parent's coordinate space, which is where [Transform2.position] lives —
  /// so adding the mapped delta to `position` moves the node by exactly the
  /// document-space delta, at any nesting depth.
  ///
  /// It is read off the parent's `ResolvedNode` rather than derived as
  /// `authoredLocal · world⁻¹`: that identity only holds while the node's own
  /// local transform is the authored one, so for a node carrying a
  /// position/rotation/scale track the derived matrix was the wrong one and the
  /// shape did not follow the pointer. The parent's evaluated world never
  /// depends on the dragged node at all.
  final Affine parentInverse;

  final Affine screenToDoc;
  final Vec2 startDoc;

  _NodeDrag movedTo(Vec2 docNow) {
    final delta = parentInverse.applyVector(docNow - startDoc);
    return _NodeDrag(
      node: node,
      path: path,
      base: base,
      original: original,
      current: original.copyWith(position: original.position + delta),
      parentInverse: parentInverse,
      screenToDoc: screenToDoc,
      startDoc: startDoc,
    );
  }
}

class _CanvasViewState extends ConsumerState<CanvasView> {
  /// Artboard-space clicks collected so far. Ephemeral by construction.
  final List<Vec2> _pending = [];

  _AnchorDrag? _anchorDrag;
  _NodeDrag? _nodeDrag;

  /// True while a viewport pan (Space-drag or middle-drag) is in flight. A pan
  /// writes only `EditorState.viewportTransform`, so there is nothing to commit
  /// on release — the flag just routes `onPanUpdate` away from the document
  /// gestures.
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

  /// The document as it *would* be if the in-flight drag were released now.
  ///
  /// Ephemeral and speculative: painted, never saved, thrown away on release.
  /// Produced by the *same* op the release commits (`PathOps.moveAnchor` for an
  /// anchor, `NodeOps.setTransform` for a node), so the preview cannot drift from
  /// the result — a second "preview-only" geometry path would be a second
  /// evaluator (docs/v3/08 §4).
  Document? _preview;

  final FocusNode _focus = FocusNode(debugLabel: 'canvas');

  static const int _clicksPerShape = 3;

  /// Screen-space grab radius for anchors. Generous on purpose.
  static const double _grabRadius = 14.0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  EditorController get _editor => ref.read(editorControllerProvider.notifier);

  /// The playhead, normalised into the range every op and mix requires. One
  /// definition, used by the hit-test, the preview and the commit.
  double _playheadT() {
    final t = ref.read(playheadProvider).value;
    return t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
  }

  List<AnimationMix> _mix(AnimationId? animation) {
    final anim = animation;
    if (anim == null) return const <AnimationMix>[];
    return <AnimationMix>[AnimationMix(anim, _playheadT())];
  }

  // --- Locked / lookup helpers (hit-test gates) ----------------------------

  /// The set of nodes that are locked, directly or through a locked ancestor.
  ///
  /// Locked is a **hit-test gate, not a render gate** (docs/v3/01 §3), so it
  /// lives here and not on the evaluated `Scene`. A locked group protects its
  /// children, so lock inherits down the tree.
  Set<NodeId> _lockedIds(Document doc) {
    final out = <NodeId>{};
    void walk(Node node, bool inheritedLock) {
      final locked = inheritedLock || node.locked;
      if (locked) out.add(node.id);
      if (node is GroupNode) {
        for (final child in node.children) {
          walk(child, locked);
        }
      }
    }

    for (final child in doc.root.children) {
      walk(child, false);
    }
    return out;
  }

  /// The id of [id]'s parent, or null when [id] is the root or is not in [doc].
  ///
  /// Hierarchy comes from the document's own tree — the `Scene` flattens it and
  /// `ScenePath.instancePath` is empty in v1, so there is nothing to read it
  /// off. Only the *ancestry* is taken from here; every coordinate still comes
  /// from the evaluated scene.
  NodeId? _parentIdOf(Document doc, NodeId id) {
    for (final node in doc.walk()) {
      if (node is! GroupNode) continue;
      for (final child in node.children) {
        if (child.id == id) return node.id;
      }
    }
    return null;
  }

  /// Whether [node] has a **transform** track — position, scale, rotation or
  /// skewX — in the active animation.
  ///
  /// Any of the four masks the static `Transform2` the Select tool's move
  /// writes, so a drag on such a node is refused rather than silently
  /// overwriting a value the user cannot see the effect of (see
  /// [_startNodeDrag]). The typed accessors are the right test: a malformed
  /// stored track returns null, is not evaluated either, and so does not mask
  /// anything.
  bool _hasTransformTrack(Document doc, NodeId node, AnimationId? animation) {
    final id = animation;
    if (id == null) return false;
    for (final anim in doc.animations) {
      if (anim.id != id) continue;
      final tracks = anim.tracksFor(node);
      return tracks.vec2(PropKey.position) != null ||
          tracks.vec2(PropKey.scale) != null ||
          tracks.scalar(PropKey.rotation) != null ||
          tracks.scalar(PropKey.skewX) != null;
    }
    return false;
  }

  // --- Previews ------------------------------------------------------------

  /// Speculatively applies an anchor [drag]. The catch is at the **widget
  /// boundary** (docs/v3/08 §1); losing the preview for one frame if a delete
  /// landed mid-drag is the right cost, and the `assert` keeps it loud in debug.
  Document? _previewOfAnchor(_AnchorDrag drag) {
    try {
      return PathOps.moveAnchor(
        drag.base,
        drag.node,
        drag.anchor,
        drag.worldToLocal.apply(drag.position),
        atT: _playheadT(),
      );
    } on ArgumentError catch (e) {
      assert(false, 'anchor drag preview rejected by an op: $e');
      return null;
    }
  }

  /// Speculatively applies a node move — the same `NodeOps.setTransform` the
  /// release commits, so the moving shape cannot disagree with what lands.
  Document? _previewOfNode(_NodeDrag drag) {
    try {
      return NodeOps.setTransform(drag.base, drag.node, drag.current);
    } on ArgumentError catch (e) {
      assert(false, 'node move preview rejected by an op: $e');
      return null;
    }
  }

  void _report(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Keyboard: pan arming + zoom shortcuts -------------------------------

  bool get _cmdOrCtrl =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// True when the Pan tool is armed: Space is held, or the middle button is
  /// down (docs/v3/05 §3).
  ///
  /// **Every document gesture asks this first, not just the drag.** The Pan tool
  /// "Mutates via: *Nothing. Ephemeral only.*", and a tap is a document gesture:
  /// while this gated `onPanStart` alone, a click with Space held fell through
  /// to `clearSelection()` *and* deposited a pen point, so three of them minted
  /// a node, bumped `rev` and pushed an undo entry — the camera authoring
  /// geometry. [HardwareKeyboard] is re-read at gesture time so a key released
  /// mid-frame cannot strand [_spaceHeld] armed.
  bool get _panArmed =>
      _spaceHeld ||
      HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space) ||
      _pointerButtons & kMiddleMouseButton != 0;

  /// Zoom shortcuts and Space-arming. Requires a focused `FocusNode` — CanvasKit
  /// drops shortcuts without one (docs/v3/05 §5), which is why every canvas
  /// pointer-down re-requests focus.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final held = event is! KeyUpEvent;
      if (held != _spaceHeld) setState(() => _spaceHeld = held);
      // Not "handled": Space must still bubble for anything else that wants it.
      return KeyEventResult.ignored;
    }

    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (!_cmdOrCtrl) return KeyEventResult.ignored;

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

  // --- Raw pointer: scroll-zoom + middle-drag pan --------------------------

  void _onPointerDown(PointerDownEvent event) {
    _pointerButtons = event.buttons;
    _focus.requestFocus();
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointerButtons = event.buttons;
    // Middle-drag pans (docs/v3/05 §3). Left-drag is left to the GestureDetector
    // (anchor / node / Space-pan), so the two never both fire.
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

  // --- Tap: pen click (M0) + node selection (M2) ---------------------------

  Future<void> _onTapUp(
    TapUpDetails details,
    Document doc,
    AnimationId? animation,
    Affine full,
  ) async {
    _focus.requestFocus();

    // The Pan tool mutates nothing, and a tap is a mutation (it clears the
    // selection and feeds the pen). Same gate `_onPanStart` uses, asked in the
    // same order — a click that ends a Space-drag must not deposit a point.
    if (_panArmed) return;

    final inverse = full.invert();
    if (inverse == null) return; // degenerate: nothing to draw into
    final docPoint = inverse.apply(_vec(details.localPosition));

    // Hit-test the front-most visible, unlocked node under the cursor.
    final locked = _lockedIds(doc);
    final scene = evaluate(doc, _mix(animation));
    final hit =
        hitTestScene(scene, doc, docPoint, (p) => !locked.contains(p.nodeId));

    if (hit != null) {
      // A node: select it (Shift adds). Selection is `EditorState`, not a
      // Command (docs/v3/08 §2) — the canvas applies it through the controller,
      // and a tap on a node is never a pen click.
      if (HardwareKeyboard.instance.isShiftPressed) {
        _editor.addToSelection(hit);
      } else {
        _editor.selectNode(hit);
      }
      return;
    }

    // Empty space: clear the selection, and (M0 drawing affordance) drop a pen
    // point. Both are honest — clicking away deselects, and the pen still draws.
    _editor.clearSelection();

    setState(() => _pending.add(docPoint));
    if (_pending.length < _clicksPerShape) return;

    final points = List<Vec2>.from(_pending);
    setState(_pending.clear);
    _report(await CanvasCommands(ref, widget.projectId).addPath(points));
  }

  // --- Pan gestures: viewport / anchor / node ------------------------------

  void _onPanStart(
    DragStartDetails details,
    Document doc,
    AnimationId? animation,
    Set<ScenePath> selection,
    Affine full,
  ) {
    _focus.requestFocus();

    // 1. Viewport pan wins whenever Space is held or the middle button drags.
    //    Ephemeral: it mutates nothing the document owns.
    if (_panArmed) {
      _panning = true;
      return;
    }

    final inverse = full.invert();
    if (inverse == null) return; // never `invert()!`
    final docPoint = inverse.apply(_vec(details.localPosition));

    // 2. Anchor drag (M0) — proximity to a handle wins over a node body, because
    //    the handle is the finer target the user is aiming at.
    if (_startAnchorDrag(details, doc, animation, full, inverse)) return;

    // 3. Node move (Select tool). A drag on empty space still mutates nothing
    //    (M0/M1), but a press-drag on a node moves it whether or not it was
    //    already selected.
    _startNodeDrag(doc, animation, selection, inverse, docPoint);
  }

  bool _startAnchorDrag(
    DragStartDetails details,
    Document doc,
    AnimationId? animation,
    Affine full,
    Affine inverse,
  ) {
    // Stages 1–3 only, matching [OverlayPainter] exactly — the handles the user
    // is aiming at are drawn from this frame, so the hit-test is drawn from it.
    final frame =
        composeWorldA(resolvePose(sampleTracks(doc, _mix(animation))));

    _AnchorDrag? best;
    var bestDistance = _grabRadius;

    for (final node in frame.nodes) {
      final geometry = node.geometry;
      if (geometry == null) continue;
      final worldToLocal = node.world.invert();
      if (worldToLocal == null) continue;

      final toScreen = full.mul(node.world);
      for (final anchor in geometry.anchors) {
        final at = toScreen.apply(anchor.position);
        if (!at.x.isFinite || !at.y.isFinite) continue;
        final distance = (Offset(at.x, at.y) - details.localPosition).distance;
        if (distance >= bestDistance) continue;
        bestDistance = distance;
        best = _AnchorDrag(
          node: node.path.nodeId,
          anchor: anchor.id,
          base: doc,
          screenToArtboard: inverse,
          worldToLocal: worldToLocal,
          position: inverse.apply(_vec(details.localPosition)),
        );
      }
    }

    final started = best;
    if (started == null) return false;
    setState(() {
      _anchorDrag = started;
      _preview = _previewOfAnchor(started);
    });
    return true;
  }

  /// Begins the Select tool's move on whatever is under the press.
  ///
  /// **A press-drag selects and moves in one gesture.** This used to require
  /// `selection.contains(hit)`, so the first press-drag on any shape was
  /// silently inert and the user had to click, release, then drag — the exact
  /// opposite of every editor's muscle memory, on the one gesture M2 exists to
  /// deliver. Selection is still `EditorState`, never a command.
  ///
  /// A **group** is moved like any other node: `hitTestScene` gives it the hit
  /// area the overlay outlines, and `NodeOps.setTransform` writes a group's
  /// transform as readily as a leaf's.
  bool _startNodeDrag(
    Document doc,
    AnimationId? animation,
    Set<ScenePath> selection,
    Affine inverse,
    Vec2 docPoint,
  ) {
    final locked = _lockedIds(doc);
    final scene = evaluate(doc, _mix(animation));
    final hit =
        hitTestScene(scene, doc, docPoint, (p) => !locked.contains(p.nodeId));
    if (hit == null) return false; // empty space: a drag there mutates nothing

    final node = doc.nodeIndex[hit.nodeId];
    if (node == null) return false; // resolved, never repaired

    // A node whose transform is driven by a track: the static `Transform2` this
    // drag writes is masked by that track at every `t`, so the move would be
    // invisible while still costing an undo entry and a `rev` bump. Refuse it
    // out loud instead — a legal document property is not a programming error,
    // so it is never an `assert` (docs/v3/08 §1). At M4 this same branch keys
    // the move at the playhead through `TrackOps.upsertKeyframe(atT:)`
    // (docs/v3/05 §3, Select row) and the refusal goes away.
    if (_hasTransformTrack(doc, hit.nodeId, animation)) {
      _editor.selectNode(hit); // selecting it is still honest
      _report(kAnimatedTransformMessage);
      return false;
    }

    // A press-drag on an unselected node selects it and moves it in the same
    // gesture. An already-selected node keeps the rest of the selection.
    if (!selection.contains(hit)) _editor.selectNode(hit);

    // parentWorld⁻¹, from the parent's EVALUATED world — never from the dragged
    // node's authored local (see [_NodeDrag.parentInverse]).
    final parentId = _parentIdOf(doc, hit.nodeId);
    if (parentId == null) return false; // the root is not draggable
    final parent = scene.byPath[ScenePath(parentId)];
    if (parent == null) return false;
    final parentInverse = parent.world.invert();
    if (parentInverse == null) return false; // collapsed: nothing to grab

    final drag = _NodeDrag(
      node: hit.nodeId,
      path: hit,
      base: doc,
      original: node.transform,
      current: node.transform,
      parentInverse: parentInverse,
      screenToDoc: inverse,
      startDoc: docPoint,
    );
    setState(() {
      _nodeDrag = drag;
      _preview =
          null; // delta is zero at start: the base document already shows
    });
    return true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_panning) {
      _editor.panBy(Vec2(details.delta.dx, details.delta.dy));
      return;
    }

    final anchor = _anchorDrag;
    if (anchor != null) {
      final moved =
          anchor.at(anchor.screenToArtboard.apply(_vec(details.localPosition)));
      setState(() {
        _anchorDrag = moved;
        _preview = _previewOfAnchor(moved);
      });
      return;
    }

    final node = _nodeDrag;
    if (node != null) {
      final moved =
          node.movedTo(node.screenToDoc.apply(_vec(details.localPosition)));
      setState(() {
        _nodeDrag = moved;
        _preview = _previewOfNode(moved);
      });
    }
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_panning) {
      _panning = false; // viewport already written live; nothing to commit
      return;
    }

    final anchor = _anchorDrag;
    if (anchor != null) {
      setState(() {
        _anchorDrag = null;
        _preview = null;
      });
      // ONE command, on release, at the live playhead (F4.2 + F6.1, thin).
      _report(await CanvasCommands(ref, widget.projectId).moveAnchorAt(
        anchor.node,
        anchor.anchor,
        anchor.worldToLocal.apply(anchor.position),
        atT: _playheadT(),
      ));
      return;
    }

    final node = _nodeDrag;
    if (node != null) {
      setState(() {
        _nodeDrag = null;
        _preview = null;
      });
      // A click that never moved leaves position unchanged; committing it would
      // be an empty undo entry, so skip it.
      if (node.current.position == node.original.position) return;

      // Nothing is re-checked here: a node with a transform track never starts a
      // drag (see [_startNodeDrag]), so the commit has exactly one path. The
      // check that used to live here was an `assert` on a legal document
      // property — it threw out of this handler in debug and discarded the
      // edit, and in release wrote a static transform the track masks.

      // ONE SetTransformCommand → ONE undo entry (docs/v3/04 §6).
      _report(await CanvasCommands(ref, widget.projectId)
          .setTransform(node.node, node.current));
    }
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
    // The active tool. Only Select exists at M2 (pen/shape fall back to it), so
    // node selection/move is always live; watching keeps the seam honest for M3.
    final tool = ref.watch(toolControllerProvider);
    final selectActive = tool.id == ToolId.select;

    if (doc == null || board == null) return const SizedBox.expand();
    final scheme = Theme.of(context).colorScheme;

    final preview = _preview;

    // WHAT THE PAINTERS SEE. During a drag this is the speculative document, so
    // the whole shape follows the anchor/node live. It is the committed document
    // at every other moment, and it is never the thing that gets saved.
    final painted = preview ?? doc;

    // Only the anchor-drag preview mints its own `Animation` (when the document
    // had none), so only it needs to name that minted id; the node-move preview
    // keeps the document's animations, so it keeps the resolved `animation`.
    final paintedAnimation = (_anchorDrag != null && preview != null)
        ? preview.defaultAnimationId
        : animation;

    final markers = <Vec2>[
      ..._pending,
      // The grabbed anchor keeps a marker on top of the moved geometry: it says
      // *which* anchor the gesture owns, which the geometry alone cannot.
      if (_anchorDrag case final drag?) drag.position,
    ];

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
              // handed to all three painters and inverted for every hit-test.
              final full = composedFit(viewport, doc.artboard, size);

              return Focus(
                focusNode: _focus,
                onKeyEvent: _onKey,
                child: MouseRegion(
                  cursor: cursor,
                  child: Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: _onPointerMove,
                    onPointerSignal: _onPointerSignal,
                    child: GestureDetector(
                      key: const Key('canvas'),
                      behavior: HitTestBehavior.opaque,
                      // Grab by what was under the pointer on DOWN, before the
                      // touch slop drifts it 20 px along the gesture.
                      dragStartBehavior: DragStartBehavior.down,
                      onTapUp: (d) => _onTapUp(d, doc, animation, full),
                      onPanStart: (d) =>
                          _onPanStart(d, doc, animation, selection, full),
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
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
                                pending: markers,
                                fit: full,
                                // Same mode as layer 2, always: handles must
                                // never outlive the geometry they belong to.
                                mode: RenderMode.editor,
                                // Node selection is shown only for the Select
                                // tool; anchor handles are the M3 direct-select
                                // affordance (docs/v3/05 §3).
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
        _ToolHint(remaining: _clicksPerShape - _pending.length, nodes: nodes),
      ],
    );
  }

  static Vec2 _vec(Offset o) => Vec2(o.dx, o.dy);
}

class _ToolHint extends StatelessWidget {
  const _ToolHint({required this.remaining, required this.nodes});

  final int remaining;
  final int nodes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: scheme.surfaceContainerHighest,
      child: Text(
        'Click $remaining more time${remaining == 1 ? '' : 's'} to add a '
        'triangle, click a shape to select it, or drag it to move · '
        '$nodes shape${nodes == 1 ? '' : 's'} in this document',
        key: const Key('tool-hint'),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
