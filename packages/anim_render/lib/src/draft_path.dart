/// The overlay's in-progress-geometry channel (docs/v3/04 §5, layer 3).
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart' show immutable, listEquals;

/// A path a tool is **still building**, carried to the overlay as *geometry*
/// rather than as dots.
///
/// ### The defect this type exists to name
///
/// The pen used to reach the overlay through the `pending` markers channel — a
/// `List<Vec2>` of anchor positions plus the two ends of the live handle. Every
/// one of those points is real, and together they say nothing: the user drew a
/// curve and the canvas answered with three dots. A `List<Vec2>` cannot express
/// a cubic, so no amount of care at the tool end could have made that feedback
/// right — it is the same class of defect as M2's "a drag shows a moving dot
/// instead of the shape", which was already fixed once on a direct complaint.
///
/// So the overlay takes the [PathData] itself and strokes it.
///
/// ### Why it is not a speculative `Document`
///
/// The other half of the preview channel *is* a document (`ToolPreview.document`
/// — the select and direct-select drags), and this deliberately is not. A
/// half-drawn path in a document, even one that is only ever painted, is a node
/// in the artboard layer's draw order, a row in the layers panel, and one missed
/// reset away from being the thing autosave persists (docs/v3/08 §2). Geometry
/// that lives on the overlay can become none of those things: there is no code
/// path from here to `Document`.
///
/// Every coordinate is in **document** space — the same space `PointerCtx.
/// docPoint` is in and the same space the overlay's `fit` maps from — so the
/// draft rides the one composed matrix the canvas built (AC-3.1.4) and never a
/// second mapping of its own.
@immutable
final class DraftPath {
  const DraftPath({required this.path, this.cursor, this.handle});

  /// The anchors placed so far, in document space.
  ///
  /// Fewer than two is legal and common — it is what the pen holds after its
  /// first click — and strokes nothing, because [PathData.segmentCount] is 0
  /// there. The anchor *dots* still draw, so the user can see the click landed.
  final PathData path;

  /// The pointer, in document space, or null to draw no live segment.
  ///
  /// **Supplied by the canvas, not by the tool.** A tool only sees the pointer
  /// on an event it is handed; the rubber-band segment has to follow the cursor
  /// between events too, and the canvas is the one place that knows where the
  /// pointer is at paint time. It inverts THE composed matrix to get here
  /// (AC-3.1.4) — there is no second mapping.
  final Vec2? cursor;

  /// The anchor whose tangent handles the gesture is dragging right now, or
  /// null when no handle is live.
  ///
  /// Named by [AnchorId] rather than by index, for the reason every join in
  /// this codebase is by id: an index-keyed handle points at the wrong anchor
  /// the moment one is inserted before it (docs/v3/01 §5).
  ///
  /// It also suppresses the live segment: while the user is pulling a handle,
  /// the cursor *is* the handle end, and a rubber band chasing it would draw a
  /// segment to a point no anchor will ever occupy.
  final AnchorId? handle;

  /// Nothing placed yet: the tool is armed but the user has not clicked.
  bool get isEmpty => path.anchors.isEmpty;

  /// Value equality, so a rebuild that changed nothing about the draft does not
  /// repaint the overlay. [PathData] carries no `==` of its own (it is normally
  /// compared by the identity of the immutable `Document` that holds it), so
  /// the anchor list is compared element-wise here — `Anchor` does implement
  /// value equality.
  @override
  bool operator ==(Object other) =>
      other is DraftPath &&
      other.cursor == cursor &&
      other.handle == handle &&
      other.path.closed == path.closed &&
      listEquals(other.path.anchors, path.anchors);

  @override
  int get hashCode => Object.hash(
        cursor,
        handle,
        path.closed,
        Object.hashAll(path.anchors),
      );

  @override
  String toString() =>
      'DraftPath(${path.anchors.length} anchors, cursor: $cursor, '
      'handle: $handle)';
}
