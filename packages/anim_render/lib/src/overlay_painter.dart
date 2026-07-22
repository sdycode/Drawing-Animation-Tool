/// Layer 3 of three: the editor overlay (docs/v3/04 §5).
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'path_geometry.dart';
import 'render_faults.dart';

/// Draws the editing affordances: authored anchors, and the pen tool's pending
/// click markers.
///
/// **This stays a separate painter forever.** Merging it into [ArtboardPainter]
/// is a named antipattern (docs/v3/08 §2, §4): the overlay is the least-tested
/// code in the app and it dereferences paths that undo has just deleted. Merged,
/// that null takes the artboard down with it — and the artboard is the thing the
/// user needs to see in order to recover.
///
/// ### Where the anchors come from, and why it is not [Scene]
///
/// docs/v3/04 §5: *"the overlay layer draws authored anchors from `Document`,
/// never from `Scene`"*. The reason is stage 7: after `applyTrim` the
/// `AnchorId`s in `ResolvedNode.geometry` are **synthetic and
/// non-authoritative** (docs/v3/01 §11), so an overlay that read them would
/// offer the user a drag handle whose id does not exist in any keyframe — and
/// the resulting `PathOps.moveAnchor` would either throw or, worse, mint a pose
/// entry for a phantom anchor.
///
/// But an overlay pinned to the document's *rest* positions is also wrong: at
/// `t = 0.7` the shape is somewhere else, and handles that do not sit on the
/// shape make the M0 exit criterion — drag an anchor at the playhead —
/// unreachable by hand.
///
/// So this painter runs stages **1–3 only**:
///
/// ```dart
/// composeWorldA(resolvePose(sampleTracks(document, mix)))
/// ```
///
/// That is strictly pre-trim, and `resolvePose` builds its output from the
/// node's topology by construction (docs/v3/01 §9), so every `AnchorId` here is
/// the authored one. The rule's *intent* — never join by a synthetic id — is
/// satisfied exactly, and the letter of it is satisfied too: the ids come from
/// the document, only the positions are posed. When trim becomes real at M6
/// this call does not change, because trim is stage 7 and stage 7 is not in it.
class OverlayPainter extends CustomPainter {
  OverlayPainter({
    required this.document,
    required this.playhead,
    required this.animation,
    required this.anchor,
    required this.anchorBorder,
    required this.pendingColor,
    this.pending = const <Vec2>[],
    this.selected = const <NodeId>{},
  }) : super(repaint: playhead);

  final Document document;

  /// Same notifier the artboard painter uses, for the same reason: an anchor
  /// marker must land on the shape on the very frame the shape moves, and a
  /// rebuild-per-tick to achieve that is the rebuild storm docs/v3/04 §4 exists
  /// to prevent.
  final ValueNotifier<double> playhead;

  final AnimationId? animation;

  /// The in-progress gesture's click markers, in **artboard** coordinates.
  ///
  /// Pending points are drawn over the document rather than inserted into it:
  /// an unfinished shape is ephemeral editor state, and a document that
  /// contains half a gesture is a document that cannot be reloaded. It is also
  /// why they live here and not in `Document` (docs/v3/08 §2 — in-progress drag
  /// state is private to the tool).
  final List<Vec2> pending;

  /// Empty means "every path node", which is M0's behaviour because there is no
  /// selection model yet.
  ///
  /// Ids in here are **resolved, never repaired**: a dangling id is legal and is
  /// filtered at this read site rather than scrubbed out of `EditorState`, so
  /// that undo restoring a node also restores its selection for free
  /// (docs/v3/08 §2).
  final Set<NodeId> selected;

  final Color anchor;
  final Color anchorBorder;
  final Color pendingColor;

  /// Screen-space radius. Constant at every zoom on purpose: a handle that
  /// scales with the artboard becomes untargetable when zoomed out, which is
  /// the failure that makes users zoom in to click and then lose their place.
  static const double anchorRadius = 3.5;
  static const double pendingRadius = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = artboardFit(document.artboard, size);
    final anim = animation;
    final mix = anim == null
        ? const <AnimationMix>[]
        : <AnimationMix>[AnimationMix(anim, _clampT(playhead.value))];

    final frame = composeWorldA(resolvePose(sampleTracks(document, mix)));

    final fillPaint = Paint()..color = anchor;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = anchorBorder;

    // Per item, inside the loop — same rule as the artboard painter. A node
    // whose handles cannot be placed loses its handles, not the whole overlay,
    // and certainly not the artboard underneath it.
    for (final node in frame.nodes) {
      final depth = canvas.getSaveCount();
      try {
        _drawHandles(canvas, node, fit, fillPaint, borderPaint);
      } catch (error, stack) {
        canvas.restoreToCount(depth);
        final watched = RenderFaults.report(RenderFault(
          stage: 'drawHandles',
          path: node.path,
          error: error,
          stack: stack,
        ));
        assert(
            watched, 'anim_render: unreported overlay fault on ${node.path}');
      }
    }

    for (final p in pending) {
      canvas.drawCircle(
        _offset(fit.apply(p)),
        pendingRadius,
        Paint()..color = pendingColor,
      );
    }
  }

  void _drawHandles(
    Canvas canvas,
    ResolvedNode node,
    Affine fit,
    Paint fillPaint,
    Paint borderPaint,
  ) {
    if (selected.isNotEmpty && !selected.contains(node.path.nodeId)) return;
    final geometry = node.geometry;
    if (geometry == null) return; // a group has no anchors to offer

    // Early return, never `invert()!` (docs/v3/08 §4). A node collapsed to a
    // point has no meaningful handle positions; drawing them all stacked at the
    // origin would invite a drag that means nothing.
    if (!_isPlaceable(node.world)) return;

    final toScreen = fit.mul(node.world);
    for (final a in geometry.anchors) {
      final at = _offset(toScreen.apply(a.position));
      if (!at.dx.isFinite || !at.dy.isFinite) continue;
      canvas.drawCircle(at, anchorRadius, fillPaint);
      canvas.drawCircle(at, anchorRadius, borderPaint);
    }
  }

  static bool _isPlaceable(Affine m) =>
      m.a.isFinite &&
      m.b.isFinite &&
      m.c.isFinite &&
      m.d.isFinite &&
      m.tx.isFinite &&
      m.ty.isFinite &&
      m.invert() != null;

  static double _clampT(double t) => t.isNaN ? 0.0 : t.clamp(0.0, 1.0);

  static Offset _offset(Vec2 v) => Offset(v.x, v.y);

  /// Identity on the document, value equality on the ephemeral bits.
  ///
  /// [pending] is compared element-wise because it is a short list rebuilt by
  /// the tool on every click; identity would miss a mutation-in-place and the
  /// marker for the click the user just made would not appear until the next
  /// unrelated repaint.
  @override
  bool shouldRepaint(OverlayPainter old) =>
      !identical(old.document, document) ||
      !identical(old.playhead, playhead) ||
      old.animation != animation ||
      old.anchor != anchor ||
      old.anchorBorder != anchorBorder ||
      old.pendingColor != pendingColor ||
      !setEquals(old.selected, selected) ||
      !listEquals(old.pending, pending);
}
