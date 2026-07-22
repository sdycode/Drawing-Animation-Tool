/// The Select tool (`V`) — the one tool M2 ships (docs/v3/05 §3).
///
/// Behaviour, once the canvas gesture layer wires it (phase 3): click a node to
/// select it, drag to move it, drag a handle to scale/rotate about the pivot,
/// marquee to multi-select. This file owns only the *tool* half of that — the
/// gesture bookkeeping and the [Command] a completed move emits. The other half —
/// hit-testing a click to a `ScenePath` and writing the selection onto
/// `EditorState` — is the canvas's job, because **selection is `EditorState`, not
/// a [Command]** (docs/v3/08 §2): a tool signals a pure selection by returning
/// null and lets the canvas apply it through `EditorController`.
library;

import 'package:anim_core/anim_core.dart' hide Animation;

import '../../../state/command.dart';
import '../../../state/tool_controller.dart';

final class SelectTool implements ToolMode {
  SelectTool();

  @override
  ToolId get id => ToolId.select;

  /// The document-space point the current drag started at, or null when no drag
  /// is in flight. **Private to the tool** (docs/v3/08 §2): a move mid-drag lives
  /// here and nowhere the document or the editor state can see it, so a
  /// half-finished drag is never autosaved and never survives an undo.
  Vec2? _dragStart;

  /// True between a pointer-down and its matching up. The overlay layer reads this
  /// to show a move affordance without the drag ever touching `Document` or
  /// `EditorState`.
  bool get isDragging => _dragStart != null;

  @override
  Command? onPointerDown(PointerCtx ctx) {
    // Record where the drag began. Selection itself is not returned as a Command;
    // the canvas hit-tests this same point to a ScenePath and applies it through
    // EditorController (docs/v3/08 §2).
    _dragStart = ctx.docPoint;
    return null;
  }

  @override
  Command? onPointerMove(PointerCtx ctx) {
    final from = _dragStart;
    if (from == null) return null;
    // The seam phase 3 completes: the drag delta `ctx.docPoint - from`, mapped
    // through the dragged node's parent-world inverse, becomes a
    // [SetTransformCommand] on the node's `Transform2` (docs/v3/05 §3 — a
    // `Transform2` write, keyframed if the node has a transform track, else onto
    // the static transform). It stays inert until the canvas resolves which node
    // the gesture owns; inventing a target here would be guessing.
    return null;
  }

  @override
  Command? onPointerUp(PointerCtx ctx) {
    _dragStart = null;
    return null;
  }
}
