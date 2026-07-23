/// Layer 3 of three: the editor overlay (docs/v3/04 §5).
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'draft_path.dart';
import 'group_clip.dart';
import 'path_geometry.dart';
import 'render_faults.dart';

/// Draws the editing affordances: authored anchors, the in-progress geometry a
/// tool is building, and a gesture's pending click markers.
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
    required this.fit,
    required this.mode,
    required this.showAnchors,
    this.draft,
    this.pending = const <Vec2>[],
    this.selected = const <NodeId>{},
    this.selectedPaths = const <ScenePath>{},
    this.selectionColor,
  }) : super(repaint: playhead);

  final Document document;

  /// The composed `viewport ∘ artboardFit` the canvas built once (docs/v3/05 §3).
  ///
  /// **Required, and never null**, for the reason the other two painters carry
  /// verbatim: an optional `fit` meant three independent fallbacks to
  /// `artboardFit(...)`, and forgetting one of the three produced a silently
  /// un-panned layer with no compile error and no failing test (AC-3.1.4).
  final Affine fit;

  /// Editor or export preview. The overlay clips exactly when the geometry
  /// layer does — same [artboardClipRect], so handles can never survive a clip
  /// that erased the shape they belong to (AC-1.1.3).
  final RenderMode mode;

  /// The nodes the Select tool has selected, keyed by [ScenePath] (docs/v3/01
  /// §11 — never by [NodeId], so instancing does not collide later). Each gets a
  /// **world-space AABB outline**. This is the M2 selection affordance; authored
  /// anchor *handles* belong to Direct-select at M3. **Resolved, never
  /// repaired** (docs/v3/08 §2): a path whose node was deleted simply matches
  /// nothing this frame, and undo restoring the node restores its outline for
  /// free — nothing is scrubbed from `EditorState`.
  final Set<ScenePath> selectedPaths;

  /// The outline colour, or null to draw none (the golden-test path).
  final Color? selectionColor;

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
  ///
  /// **Points only, and that is the whole of what this channel can say.** A
  /// gesture whose feedback is a *shape* — the pen's half-drawn path — goes
  /// through [draft] instead; see [DraftPath] for the defect that split them.
  final List<Vec2> pending;

  /// The path a tool is building right now, or null when no tool is building
  /// one. Stroked, never filled, in the same composed [fit] space as everything
  /// else this painter draws.
  ///
  /// This is a **rendering** channel and not a place to park state: the anchors
  /// themselves stay a private field of the tool (docs/v3/08 §2), and what
  /// arrives here is a copy the tool hands out once per paint.
  final DraftPath? draft;

  /// Whether authored anchor handles are drawn **at all**.
  ///
  /// **Required, and separate from [selected], because conflating the two was a
  /// live defect.** Anchor handles belong to Direct select (docs/v3/05 §3), so
  /// every other tool wants none — and with [selected]'s "empty means every
  /// node" convention there was no set that meant *none*. The canvas said it by
  /// passing the one id guaranteed to exist and to have no geometry: the
  /// document **root**. That sentinel reads as a bug at the call site, reads as
  /// a bug here, and would have been "cleaned up" into `const {}` — which means
  /// the exact opposite — by the first person to touch either end.
  ///
  /// So the question is asked directly. `false` draws no anchor dot anywhere;
  /// selection outlines are a different affordance and are unaffected (they are
  /// governed by [selectedPaths] and [selectionColor]), which is what keeps
  /// Select showing node outlines while offering no handles.
  final bool showAnchors;

  /// *Which* path nodes get anchors, when [showAnchors] is on. Empty means
  /// every one of them.
  ///
  /// Empty-means-all is safe here and was not safe as a way to say "none": this
  /// set only ever narrows an affordance [showAnchors] has already turned on.
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

  /// Screen-space too, and for the same reason: a preview stroke that scaled
  /// with the zoom would be a hairline at 25% — invisible at exactly the zoom
  /// where the user is placing anchors across the whole board.
  static const double draftWidth = 1.5;

  /// The dot on the far end of a tangent handle. Smaller than an anchor,
  /// because it is the thing you drag and not the thing you aim at to close.
  static const double handleRadius = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final anim = animation;
    final mix = anim == null
        ? const <AnimationMix>[]
        : <AnimationMix>[AnimationMix(anim, _clampT(playhead.value))];

    // Stages 1–3 as a `Scene`, so the selection outline can ask
    // [selectionBounds] the very question the hit-test asks — one answer, so
    // the box the user sees is the area that answers a click.
    final frame =
        composeWorldA(resolvePose(sampleTracks(document, mix))).toScene();

    // The editor clips nothing (AC-1.1.3); the export preview clips to the same
    // rect the geometry layer does. The clip wraps the whole overlay, so a
    // handle can never outlive the shape it belongs to.
    final clip = artboardClipRect(mode, document.artboard, fit);
    if (clip != null) {
      canvas.save();
      canvas.clipRect(clip);
    }

    // A clipping group clips the overlay exactly as it clips the geometry, for
    // the reason the artboard clip is shared one line above: a handle must
    // never outlive the shape it belongs to. `base` is the fit because this
    // painter draws in SCREEN space — it never puts the fit on the canvas, it
    // maps each point through it — so the window has to be mapped the same way
    // or the handles would be clipped by a window in the wrong place.
    final clips = GroupClipStack.forCanvas(canvas, document, frame, base: fit);

    final fillPaint = Paint()..color = anchor;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = anchorBorder;
    final outlineColor = selectionColor;
    final outlinePaint = outlineColor == null
        ? null
        : (Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = outlineColor);

    // Per item, inside the loop — same rule as the artboard painter. A node
    // whose handles cannot be placed loses its handles, not the whole overlay,
    // and certainly not the artboard underneath it.
    for (final node in frame.drawOrder) {
      try {
        clips.enter(canvas, node.path);
        if (showAnchors) _drawHandles(canvas, node, fillPaint, borderPaint);
        if (outlinePaint != null && selectedPaths.contains(node.path)) {
          _drawSelection(canvas, frame, node, outlinePaint);
        }
      } catch (error, stack) {
        canvas.restoreToCount(clips.floor);
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

    // Before the draft and the pending markers, never after: an in-progress
    // gesture is tool state, not a child of any group, so it must not inherit
    // the last group's window — and it must not be drawn into a clip nothing
    // will close.
    clips.closeAll(canvas);

    // The draft is one item, so it gets one guard — the same shape the loop's
    // per-item catch has, for the same reason. Without it a throw here would
    // skip the `restore` below and leak the export preview's artboard clip into
    // whatever paints next, which is invisible on the layer that caused it.
    final sketch = draft;
    if (sketch != null) {
      final floor = canvas.getSaveCount();
      try {
        _drawDraft(canvas, sketch);
      } catch (error, stack) {
        canvas.restoreToCount(floor);
        final watched = RenderFaults.report(RenderFault(
          stage: 'drawDraft',
          error: error,
          stack: stack,
        ));
        assert(watched, 'anim_render: unreported draft fault');
      }
    }

    for (final p in pending) {
      canvas.drawCircle(
        _offset(fit.apply(p)),
        pendingRadius,
        Paint()..color = pendingColor,
      );
    }

    if (clip != null) canvas.restore();
  }

  /// The in-progress path: the curve so far, the segment chasing the cursor,
  /// the anchors placed, and the handle being pulled.
  ///
  /// ### Screen space, mapped — never a second matrix on the canvas
  ///
  /// Like every other mark this painter makes, the draft is mapped **through**
  /// [fit] rather than drawn under it: `canvas.transform(fit)` would scale the
  /// stroke width and the handle dots with the zoom, and this layer's whole
  /// convention is that affordances are a constant physical size. [fit] is the
  /// one composed `viewport ∘ artboardFit` the canvas built (AC-3.1.4) — the
  /// same object the artboard layer under it is drawn with, so the preview
  /// cannot land anywhere the committed shape would not.
  ///
  /// `Path.transform` maps the already-built cubics, so the curve here comes
  /// out of the very same [buildPath] the artboard layer commits through. A
  /// second cubic emitter for previews is how a preview ends up disagreeing
  /// with what lands.
  void _drawDraft(Canvas canvas, DraftPath sketch) {
    final data = sketch.path;
    if (data.anchors.isEmpty) return;

    // Early return, never `invert()!` (docs/v3/08 §4). A collapsed camera has
    // nowhere on screen to put the draft, and `Path.transform` with a NaN
    // poisons the layer rather than this one item.
    if (!isPlaceable(fit)) return;
    final toScreen = affineToMatrix4(fit);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = draftWidth
      ..color = pendingColor;

    // **Stroked, never filled.** The path is open and half-authored; filling it
    // would show the user a solid blob whose boundary is a segment they have
    // not drawn yet — `ui.Path` closes an open contour implicitly to fill it.
    if (data.segmentCount > 0) {
      canvas.drawPath(buildPath(data).transform(toScreen), strokePaint);
    }

    // The live segment. Built as a cubic like every other segment (AC-4.1.2 —
    // there is no polyline branch anywhere): it leaves the last anchor along
    // that anchor's own outgoing tangent, so what the user sees is what the
    // next click commits, and arrives at the cursor straight because the anchor
    // that will own the incoming tangent does not exist yet.
    final cursor = sketch.cursor;
    final last = data.anchors.last;
    if (cursor != null && sketch.handle == null) {
      final out = last.position + last.outTangent;
      final live = Path()
        ..moveTo(last.position.x, last.position.y)
        ..cubicTo(out.x, out.y, cursor.x, cursor.y, cursor.x, cursor.y);
      canvas.drawPath(live.transform(toScreen), strokePaint);
    }

    // The anchors placed so far. Same dot the `pending` channel drew before
    // this type existed — the first anchor is the target the user aims at to
    // close the path, so it has to stay visible and stay the same size.
    final dot = Paint()..color = pendingColor;
    for (final a in data.anchors) {
      final at = _offset(fit.apply(a.position));
      if (!at.dx.isFinite || !at.dy.isFinite) continue;
      canvas.drawCircle(at, pendingRadius, dot);
    }

    _drawDraftHandle(canvas, sketch, dot);
  }

  /// The tangent handles of the anchor currently being dragged.
  ///
  /// Kept, and deliberately: a line from the anchor to each tangent end with a
  /// dot on it is the pen convention every vector editor shares, and it is the
  /// only feedback that says *how far* the curve will bulge before the user
  /// releases. It is the one thing the old markers channel got right.
  ///
  /// A zero tangent draws nothing. `Alt` leaves the incoming handle at zero on
  /// purpose (an asymmetric corner), and a zero-length line under a dot that
  /// sits exactly on the anchor would read as a handle the user could grab.
  void _drawDraftHandle(Canvas canvas, DraftPath sketch, Paint dot) {
    final live = sketch.handle;
    if (live == null) return;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = pendingColor;

    for (final a in sketch.path.anchors) {
      if (a.id != live) continue; // ids join, never indices (docs/v3/01 §5)
      final from = _offset(fit.apply(a.position));
      if (!from.dx.isFinite || !from.dy.isFinite) return;
      for (final tangent in <Vec2>[a.outTangent, a.inTangent]) {
        if (tangent.x == 0 && tangent.y == 0) continue;
        final to = _offset(fit.apply(a.position + tangent));
        if (!to.dx.isFinite || !to.dy.isFinite) continue;
        canvas.drawLine(from, to, linePaint);
        canvas.drawCircle(to, handleRadius, dot);
      }
      return; // ids are unique (invariant P1): there is no second match
    }
  }

  /// The selected node's **world-space AABB**, stroked in screen space.
  ///
  /// The box comes from [selectionBounds] — the same function `hitTestScene`
  /// uses — so the outline the user sees is exactly the region that answers a
  /// click. Two independent bounds is how an outline ends up somewhere the node
  /// is not, and it is why a **group** gets an outline here at all: it has no
  /// geometry of its own, so its box is the union of its descendants'. A group
  /// that could be selected in the layers panel but showed nothing on the canvas
  /// and could not be dragged made the tree's own container nodes second-class.
  ///
  /// The bound is axis-aligned in *world* space (so a rotated node gets an
  /// upright box around where it actually is), then mapped to screen through the
  /// composed [fit].
  void _drawSelection(
    Canvas canvas,
    Scene frame,
    ResolvedNode node,
    Paint outlinePaint,
  ) {
    if (node.path.nodeId == document.root.id) return; // the root is not a node
    final bounds = selectionBounds(frame, document, node.path);
    if (bounds == null) return; // an empty group encloses nothing to outline

    canvas.drawRect(
      Rect.fromPoints(
        _offset(fit.apply(Vec2(bounds.left, bounds.top))),
        _offset(fit.apply(Vec2(bounds.right, bounds.bottom))),
      ),
      outlinePaint,
    );
  }

  void _drawHandles(
    Canvas canvas,
    ResolvedNode node,
    Paint fillPaint,
    Paint borderPaint,
  ) {
    // Whether handles are drawn at all is [showAnchors]'s question, asked at
    // the call site. This one only narrows: empty is every node.
    if (selected.isNotEmpty && !selected.contains(node.path.nodeId)) return;
    final geometry = node.geometry;
    if (geometry == null) return; // a group has no anchors to offer

    // Early return, never `invert()!` (docs/v3/08 §4). A node collapsed to a
    // point has no meaningful handle positions; drawing them all stacked at the
    // origin would invite a drag that means nothing. `isPlaceable` is the
    // package's one definition of that question — the geometry layer and the
    // selection bounds ask it too, and three copies could drift.
    if (!isPlaceable(node.world)) return;

    final toScreen = fit.mul(node.world);
    for (final a in geometry.anchors) {
      final at = _offset(toScreen.apply(a.position));
      if (!at.dx.isFinite || !at.dy.isFinite) continue;
      canvas.drawCircle(at, anchorRadius, fillPaint);
      canvas.drawCircle(at, anchorRadius, borderPaint);
    }
  }

  static double _clampT(double t) => t.isNaN ? 0.0 : t.clamp(0.0, 1.0);

  static Offset _offset(Vec2 v) => Offset(v.x, v.y);

  /// Identity on the document, value equality on the ephemeral bits.
  ///
  /// [pending] is compared element-wise because it is a short list rebuilt by
  /// the tool on every click; identity would miss a mutation-in-place and the
  /// marker for the click the user just made would not appear until the next
  /// unrelated repaint. [draft] carries value equality for the same reason —
  /// the pen mints a fresh `PathData` per paint, so identity would say "changed"
  /// on every rebuild and "unchanged" never.
  @override
  bool shouldRepaint(OverlayPainter old) =>
      !identical(old.document, document) ||
      !identical(old.playhead, playhead) ||
      old.animation != animation ||
      old.anchor != anchor ||
      old.anchorBorder != anchorBorder ||
      old.pendingColor != pendingColor ||
      old.selectionColor != selectionColor ||
      old.mode != mode || // editor ↔ export preview changes the clip
      old.fit != fit ||
      old.showAnchors != showAnchors ||
      old.draft != draft ||
      !setEquals(old.selected, selected) ||
      !setEquals(old.selectedPaths, selectedPaths) ||
      !listEquals(old.pending, pending);
}
