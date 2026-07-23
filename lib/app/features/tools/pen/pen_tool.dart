/// The Pen tool (`P`) — F4.1, docs/v3/05 §3's Pen row and §4.1's flow.
///
/// | Gesture | Result |
/// | --- | --- |
/// | click | a **corner** anchor (zero handles) |
/// | click-drag | a **smooth** anchor with symmetric tangents from the drag |
/// | click the first anchor | close the path, commit it, exit to Select |
/// | `Esc` / `Enter` | leave the path open, commit it, exit to Select |
/// | `Alt` while dragging | breaks the outgoing tangent (an asymmetric corner) |
/// | `Shift` | constrains the new anchor to 45° from the previous one |
///
/// It **replaces the M0 three-click affordance**, which minted a fixed triangle
/// from three taps and could not produce a curve at all. Click-drag is what
/// makes M3's exit criterion — "a closed path with at least one curved segment"
/// — reachable by hand.
///
/// ## One `PathData`, committed once
///
/// The in-progress anchors live in a **private field of this object**
/// (docs/v3/08 §2). They are not in `Document` — a document holding half a
/// gesture is a document autosave would persist and nothing could reload — and
/// not in `EditorState` — every panel watching editor state would rebuild on
/// every click. On exit the whole node is built and returned as **one**
/// [AddNodeCommand]: one undo entry, one save, one node.
///
/// ## Two rules this tool keeps structurally
///
/// 1. **The pen cannot replace a node's `PathData`** (docs/v3/05 §3 rule 1).
///    There is no branch in this file that reads an existing node, so there is
///    nothing to write back to one. Continuing an existing path and inserting on
///    a segment need `PathOps.insertAnchor`, which is **M5** and does not exist;
///    faking it with a raw path replacement would mint fresh `AnchorId`s and
///    leave the node's topology and its keyframe poses disjoint — the one state
///    v3 exists to make unrepresentable. So the pen always starts a new path,
///    and the `+` cursor over a segment is M5's to add.
/// 2. **One segment type** (AC-4.1.2). Every anchor is a cubic anchor; a
///    straight segment is the degenerate zero-handle case. There is no polyline
///    branch here to grep for.
library;

import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;

import '../../../state/command.dart';
import '../../../state/tool_controller.dart';
import '../new_path_node.dart';

final class PenTool implements ToolMode {
  PenTool();

  @override
  ToolId get id => ToolId.pen;

  /// The path being drawn, in **artboard** coordinates. Private to the tool
  /// (docs/v3/08 §2) — see the class doc for what each alternative home costs.
  final List<Anchor> _anchors = <Anchor>[];

  /// True between the pointer-down that placed the last anchor and its release:
  /// the drag that turns that anchor from a corner into a smooth one.
  bool _dragging = false;

  ToolEffect? _effect;

  @override
  ToolEffect? takeEffect() {
    final effect = _effect;
    _effect = null;
    return effect;
  }

  /// The path so far, as **geometry** — plus, during a handle drag, the anchor
  /// whose tangents the user is pulling.
  ///
  /// ### Why this is not the `markers` channel any more
  ///
  /// It used to be: anchor positions and the two handle ends, as a `List<Vec2>`
  /// the overlay drew as dots. Every point was correct and the result was
  /// wrong — the user click-dragged a curve and the canvas showed them three
  /// dots, because a list of points cannot express a cubic. That is the same
  /// class of defect as M2's "a drag shows a moving dot instead of the shape".
  /// The overlay now strokes the `PathData` itself, and the live segment
  /// following the cursor comes from the canvas, which is the only thing that
  /// knows where the pointer is between events.
  ///
  /// **The overlay, not the artboard layer** (docs/v3/04 §5, docs/v3/08 §2). An
  /// in-progress stroke handed over as a speculative *document* would be a node
  /// in the artboard painter's draw order and in the layers panel's world, and
  /// one missed reset from being saved. Overlay geometry cannot become either.
  ///
  /// A **copy** of [_anchors], never the list itself: `_anchors` is mutated in
  /// place by the very next move event, and a `PathData` aliasing it would let
  /// a painter observe half an edit — and would hand a caller a live handle on
  /// the tool's private state, which is the leak docs/v3/08 §2 forbids.
  @override
  ToolPreview get preview {
    if (_anchors.isEmpty) return ToolPreview.none;
    return ToolPreview(
      path: PathData(anchors: List<Anchor>.of(_anchors), closed: false),
      // Only while a handle is actually being pulled. `_dragging` is true from
      // the click that placed the anchor, so its tangents may still be zero —
      // the overlay draws no line for a zero tangent, which is what keeps a
      // plain click from flashing a handle that is not there.
      liveHandle: _dragging ? _anchors.last.id : null,
    );
  }

  @override
  void cancel() {
    _anchors.clear();
    _dragging = false;
  }

  @override
  Command? onPointerDown(PointerCtx ctx) {
    // Clicking the FIRST anchor closes the path and exits (docs/v3/05 §4.1
    // step 4). Checked before anything else, and in screen pixels, so the user
    // aims at the dot they can see rather than at a document-space tolerance
    // that shrinks as they zoom out.
    if (_anchors.length >= 2 &&
        ctx.screenDistanceTo(_anchors.first.position) <=
            PointerCtx.grabRadius) {
      return _commit(ctx, closed: true);
    }

    final at = ctx.shift && _anchors.isNotEmpty
        ? _constrain45(_anchors.last.position, ctx.docPoint)
        : ctx.docPoint;

    // A fresh id per anchor, minted here and never derived from the loop index:
    // an index-derived id is the legacy defect wearing a different hat, and it
    // is what makes a keyframe pose join to the wrong anchor after an insert.
    _anchors.add(Anchor(id: AnchorId(uuidV4()), position: at));
    _dragging = true;
    return null;
  }

  /// The drag vector authors the new anchor's tangents.
  ///
  /// Plain drag → `outTangent = drag`, `inTangent = -drag`, kind
  /// [AnchorKind.symmetric]: the two handles are collinear and equal, which is
  /// what makes the segment either side of the anchor continuous. `Alt` →
  /// **breaks the outgoing tangent**: the incoming handle stays zero and the
  /// kind becomes [AnchorKind.corner], so the curve leaves the anchor in the
  /// dragged direction and arrives at it in a straight line.
  @override
  Command? onPointerMove(PointerCtx ctx) {
    if (!_dragging || _anchors.isEmpty) return null;
    final anchor = _anchors.last;
    final drag = ctx.docPoint - anchor.position;
    _anchors[_anchors.length - 1] = ctx.alt
        ? anchor.copyWith(
            inTangent: Vec2.zero,
            outTangent: drag,
            kind: AnchorKind.corner,
          )
        : anchor.copyWith(
            inTangent: drag * -1.0,
            outTangent: drag,
            kind: AnchorKind.symmetric,
          );
    return null; // nothing is committed until the path is finished
  }

  @override
  Command? onPointerUp(PointerCtx ctx) {
    _dragging = false;
    return null;
  }

  /// `Esc` and `Enter` both **leave the path open and exit** (docs/v3/05 §3's
  /// Pen row). §5's table says `Enter` closes; §3 wins — see [ToolKey].
  @override
  Command? onKey(ToolKey key, PointerCtx ctx) {
    // Nothing in progress: `Esc` falls through to the canvas, where it means
    // deselect (docs/v3/05 §5).
    if (_anchors.isEmpty) return null;
    return _commit(ctx, closed: false);
  }

  /// Build the node, hand back **one** command, and reset.
  ///
  /// Fewer than two anchors is not a shape: it has no segment, renders nothing
  /// (invariant P2) and cannot be clicked, so committing it would put an
  /// invisible, unselectable node in the layers panel and an undo entry in the
  /// history for a gesture the user abandoned. The anchors are dropped instead —
  /// which is exactly what "a half-drawn path never reaches the document" means.
  Command? _commit(PointerCtx ctx, {required bool closed}) {
    final anchors = List<Anchor>.of(_anchors);
    cancel();
    if (anchors.length < 2) return null;

    final node = newPathNode(
      name: 'Path ${ctx.doc.root.children.length + 1}',
      path: PathData(anchors: anchors, closed: closed),
    );
    // Selected and exited to Select, as docs/v3/05 §4.1 step 4 specifies: the
    // thing the user just drew is the thing they are about to move or restyle.
    _effect = ToolEffect(
      selection: ToolSelection.replace(<ScenePath>{ScenePath(node.id)}),
      activate: ToolId.select,
    );
    return AddNodeCommand(node);
  }

  /// [p] projected onto the nearest of the eight 45° rays from [from].
  ///
  /// Projection rather than an angle snap with the raw length: the component
  /// along the chosen ray is kept, so the anchor lands under the part of the
  /// pointer's motion that agrees with the constraint and does not leap away
  /// when the pointer is nearly perpendicular to it.
  static Vec2 _constrain45(Vec2 from, Vec2 p) {
    final d = p - from;
    if (d.x == 0 && d.y == 0) return p;
    const step = math.pi / 4;
    final snapped = (math.atan2(d.y, d.x) / step).roundToDouble() * step;
    final axis = Vec2(math.cos(snapped), math.sin(snapped));
    final along = d.x * axis.x + d.y * axis.y;
    return from + axis * along;
  }
}
