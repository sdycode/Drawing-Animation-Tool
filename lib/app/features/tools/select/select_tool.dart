/// The Select tool (`V`) — click a node to select it, drag to move it
/// (docs/v3/05 §3, F3.1).
///
/// **M2 wrote this behaviour inline in the canvas; M3 moved it here, and that is
/// the point of the milestone's first task.** The audit found `SelectTool`'s
/// `onPointerDown/Move/Up` were never invoked, `PointerCtx` was never
/// constructed, and `ToolController.activate` had no call site: the tool layer
/// was a seam with nothing flowing through it, and the canvas re-implemented
/// select and move by hand while reading only `tool.id`. A seam nothing flows
/// through is not a seam, it is a comment — and the pen, shape and direct-select
/// tools would each have had to add their own branch to the same canvas
/// handlers, which is the shape docs/v3/08 §2 exists to forbid.
///
/// Now the canvas builds one [PointerCtx] and dispatches it through whatever
/// [ToolMode] is active; this file owns the whole of select-and-move and the
/// canvas owns none of it.
///
/// **Selection is still `EditorState`, never a [Command]** (docs/v3/08 §2). The
/// tool decides *what* the gesture selected — it is the only thing that knows —
/// and returns that as a [ToolSelection] inside a [ToolEffect]; the canvas
/// performs it through `EditorController`. No tool holds a controller.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart' show hitTestScene;
import 'package:flutter/foundation.dart' show immutable;

import '../../../state/command.dart';
import '../../../state/tool_controller.dart';
import '../locked_nodes.dart';

/// The message shown when the Select tool **declines** to move a node.
///
/// A node whose position / rotation / scale is driven by a track in the active
/// animation reads its transform from that track at every `t`, so the static
/// `Transform2` a canvas drag writes would be masked: the shape would not follow
/// the pointer, and the release would still record an undo entry and bump `rev`
/// for a change nobody can see.
///
/// A refusal, not an `assert`: a document carrying transform tracks is a legal
/// document, and `assert(false, …)` is for programming errors, not for user data
/// (docs/v3/08 §1). Keyframing the move at the playhead is the M4 answer
/// (docs/v3/05 §3, Select row); until then the user gets a sentence instead of a
/// silent no-op.
///
/// It lives beside the tool that raises it, not in `features/canvas`, because a
/// feature may not import a sibling feature (docs/v3/08 §3) and this sentence is
/// the Select tool's, not the canvas's.
const String kAnimatedTransformMessage =
    'This layer’s transform is animated — move it by keyframing it, not by '
    'dragging.';

/// A node move in flight.
///
/// **Private to the tool** (docs/v3/08 §2): never in `Document` (autosave would
/// persist half a gesture and the result cannot be reloaded) and never in
/// `EditorState` (every panel watching editor state would rebuild 60 times a
/// second while the pointer moves).
@immutable
final class _NodeDrag {
  const _NodeDrag({
    required this.node,
    required this.base,
    required this.original,
    required this.current,
    required this.parentInverse,
    required this.startDoc,
  });

  final NodeId node;

  /// The document the gesture started from, captured once, so the preview is a
  /// function of what the user grabbed rather than of whatever arrives
  /// underneath the pointer mid-drag.
  final Document base;

  /// The node's transform when the drag began, and the transform as posed by
  /// the live delta. Only [current] is committed, and only on release.
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

  final Vec2 startDoc;

  bool get moved => current.position != original.position;

  _NodeDrag movedTo(Vec2 docNow) => _NodeDrag(
        node: node,
        base: base,
        original: original,
        current: original.copyWith(
            position: original.position +
                parentInverse.applyVector(docNow - startDoc)),
        parentInverse: parentInverse,
        startDoc: startDoc,
      );
}

final class SelectTool implements ToolMode {
  SelectTool();

  @override
  ToolId get id => ToolId.select;

  _NodeDrag? _drag;
  ToolEffect? _effect;
  Document? _preview;

  @override
  ToolEffect? takeEffect() {
    final effect = _effect;
    _effect = null;
    return effect;
  }

  @override
  ToolPreview get preview =>
      _preview == null ? ToolPreview.none : ToolPreview(document: _preview);

  @override
  void cancel() {
    _drag = null;
    _preview = null;
  }

  @override
  Command? onKey(ToolKey key, PointerCtx ctx) => null;

  /// A press selects what is under it and arms the move.
  ///
  /// **A press-drag selects and moves in one gesture.** This used to require the
  /// node to be selected already, so the first press-drag on any shape was
  /// silently inert and the user had to click, release, then drag — the opposite
  /// of every editor's muscle memory. A tap is this handler followed immediately
  /// by [onPointerUp] with a zero delta, so click-to-select and drag-to-move are
  /// one code path and cannot disagree about what was hit.
  @override
  Command? onPointerDown(PointerCtx ctx) {
    _drag = null;
    _preview = null;

    final locked = lockedNodeIds(ctx.doc);
    final hit = hitTestScene(
      ctx.scene,
      ctx.doc,
      ctx.docPoint,
      (p) => !locked.contains(p.nodeId),
    );

    if (hit == null) {
      // Empty space deselects. A drag from here mutates nothing — marquee
      // multi-select is the part of the Select row still owed (docs/v3/05 §3).
      _effect = const ToolEffect(selection: ToolSelection.clear);
      return null;
    }

    final node = ctx.doc.nodeIndex[hit.nodeId];
    if (node == null) return null; // resolved, never repaired

    // Shift adds; a press on an already-selected node keeps the rest of the
    // selection so a multi-node drag is possible later without re-picking.
    if (ctx.shift) {
      _effect = ToolEffect(selection: ToolSelection.add(<ScenePath>{hit}));
    } else if (!ctx.editor.selectedNodes.contains(hit)) {
      _effect = ToolEffect(selection: ToolSelection.replace(<ScenePath>{hit}));
    }

    // A node whose transform is driven by a track: the static `Transform2` this
    // drag writes is masked by that track at every `t`, so the move would be
    // invisible while still costing an undo entry and a `rev` bump. Refuse it
    // out loud (see [kAnimatedTransformMessage]); selecting it is still honest.
    if (_hasTransformTrack(ctx.doc, hit.nodeId, ctx.animation)) {
      _effect = ToolEffect(
        selection: ToolSelection.replace(<ScenePath>{hit}),
        message: kAnimatedTransformMessage,
      );
      return null;
    }

    // parentWorld⁻¹, from the parent's EVALUATED world — never from the dragged
    // node's authored local (see [_NodeDrag.parentInverse]).
    final parentId = _parentIdOf(ctx.doc, hit.nodeId);
    if (parentId == null) return null; // the root is not draggable
    final parent = ctx.scene.byPath[ScenePath(parentId)];
    if (parent == null) return null;
    final parentInverse = parent.world.invert();
    if (parentInverse == null) return null; // collapsed: nothing to grab

    _drag = _NodeDrag(
      node: hit.nodeId,
      base: ctx.doc,
      original: node.transform,
      current: node.transform,
      parentInverse: parentInverse,
      startDoc: ctx.docPoint,
    );
    return null;
  }

  @override
  Command? onPointerMove(PointerCtx ctx) {
    final drag = _drag;
    if (drag == null) return null;
    final moved = drag.movedTo(ctx.docPoint);
    _drag = moved;
    _preview = _previewOf(moved);
    return null; // one command per gesture, on release
  }

  /// **ONE** [SetTransformCommand] per completed drag, on release (docs/v3/04
  /// §6). A 200-event move is one undo entry and one save, not 200 of each,
  /// because the live transform never left this object.
  @override
  Command? onPointerUp(PointerCtx ctx) {
    final drag = _drag;
    _drag = null;
    _preview = null;
    if (drag == null) return null;
    // A click that never moved leaves position unchanged; committing it would
    // be an empty undo entry.
    if (!drag.moved) return null;
    return SetTransformCommand(drag.node, drag.current);
  }

  /// Speculatively applies the move with the **same op the release commits**, so
  /// the moving shape cannot disagree with what lands. The catch is at the tool
  /// boundary (docs/v3/08 §1): losing the preview for one frame if a delete
  /// landed mid-drag is the right cost, and the `assert` keeps it loud in debug.
  Document? _previewOf(_NodeDrag drag) {
    try {
      return NodeOps.setTransform(drag.base, drag.node, drag.current);
    } on ArgumentError catch (e) {
      assert(false, 'node move preview rejected by an op: $e');
      return null;
    }
  }

  /// The id of [id]'s parent, or null when [id] is the root or is not in [doc].
  ///
  /// Hierarchy comes from the document's own tree — the `Scene` flattens it and
  /// `ScenePath.instancePath` is empty in v1, so there is nothing to read it
  /// off. Only the *ancestry* is taken from here; every coordinate still comes
  /// from the evaluated scene.
  static NodeId? _parentIdOf(Document doc, NodeId id) {
    for (final node in doc.walk()) {
      if (node is! GroupNode) continue;
      for (final child in node.children) {
        if (child.id == id) return node.id;
      }
    }
    return null;
  }

  /// Whether [node] has a **transform** track — position, scale, rotation or
  /// skewX — in the active animation. Any of the four masks the static
  /// `Transform2` a move writes. The typed accessors are the right test: a
  /// malformed stored track returns null, is not evaluated either, and so does
  /// not mask anything.
  static bool _hasTransformTrack(
    Document doc,
    NodeId node,
    AnimationId? animation,
  ) {
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
}
