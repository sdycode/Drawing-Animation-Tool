/// Layer 2 of three: the evaluated scene (docs/v3/04 §5).
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'paint_translation.dart';
import 'path_geometry.dart';
import 'render_faults.dart';

/// Draws an **already-evaluated** [Scene].
///
/// Top-level and free of `CustomPainter`, `Size` and `BuildContext` on purpose:
/// this is the function the golden tests call with a hand-built `Scene`, and
/// every one of the interesting failure modes (degenerate path, unknown paint
/// source, collapsed matrix) is reachable from a three-line test rather than
/// from a pumped widget.
///
/// It draws what the [Scene] says and asks the [Document] nothing. A painter
/// that reaches into the document to decide what to draw is a second evaluator
/// that will disagree with the real one (docs/v3/08 §4), and the disagreement
/// surfaces as "the canvas is right until you scrub".
///
/// [fit] is the document→screen transform, normally [artboardFit]. It is a
/// parameter rather than something computed here because hit-testing must
/// invert the *same* matrix; computing the fit twice is how a click lands where
/// the shape is not.
void paintScene(Canvas canvas, Scene scene, {Affine fit = Affine.identity}) {
  canvas.save();
  canvas.transform(affineToMatrix4(fit));

  // The guard is INSIDE the loop, never around it (docs/v3/08 §1). One bad
  // node vanishes; the other 113 render. A try around the whole loop is the
  // same defect as legacy's per-frame modal wearing a quieter coat: it erases
  // the artboard the user needs in order to recover from the bug.
  for (final node in scene.drawOrder) {
    final depth = canvas.getSaveCount();
    try {
      _drawNode(canvas, node);
    } catch (error, stack) {
      // A throw between `save` and `restore` leaves the canvas transformed for
      // every *subsequent* node, so the failure would smear across nodes that
      // are individually fine. Unwinding to the depth recorded before the item
      // is what keeps "one node vanishes" literally true.
      canvas.restoreToCount(depth);
      final watched = RenderFaults.report(RenderFault(
        stage: 'drawNode',
        path: node.path,
        error: error,
        stack: stack,
      ));
      assert(watched, 'anim_render: unreported paint fault on ${node.path}');
    }
  }

  canvas.restore();
}

void _drawNode(Canvas canvas, ResolvedNode node) {
  // `worldVisible` already ANDs every ancestor and `worldOpacity` already
  // multiplies them (docs/v3/01 §3). Re-deriving either here would be the
  // second evaluator.
  if (!node.worldVisible) return;
  if (!(node.worldOpacity > 0)) return; // also rejects NaN, unlike `<= 0`

  final geometry = node.geometry;
  if (geometry == null) return; // a group, or a node type this build shrugs at

  // A collapsed matrix draws nothing and never throws. The evaluator is total
  // (docs/v3/01 §1 rule 3) and the renderer must not reintroduce the crash the
  // evaluator was built to prevent — so this is an early return, never
  // `invert()!` (docs/v3/08 §4, the recurring five).
  if (!_isDrawable(node.world)) return;

  if (node.fills.isEmpty && node.strokes.isEmpty) return;

  final path = buildPath(geometry); // 0 or 1 anchor yields an empty ui.Path

  canvas.save();
  canvas.transform(affineToMatrix4(node.world));

  for (final fill in node.fills) {
    if (!fill.visible) continue;
    final paint = paintFor(fill.paint, node.worldOpacity * fill.opacity);
    if (paint == null) continue; // unknown source: preserved on disk, not drawn
    paint
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.srcOver;
    path.fillType = toUiFillType(fill.rule);
    canvas.drawPath(path, paint);
  }

  // Strokes paint after every fill, always. The order is fixed rather than
  // authorable because per-item z-order between fills and strokes is a feature
  // nobody asked for and a diff nobody can review.
  for (final stroke in node.strokes) {
    if (!stroke.visible) continue;
    final paint = paintFor(stroke.paint, node.worldOpacity * stroke.opacity);
    if (paint == null) continue;
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width
      ..strokeCap = toUiCap(stroke.cap)
      ..strokeJoin = toUiJoin(stroke.join)
      ..strokeMiterLimit = stroke.miterLimit;
    canvas.drawPath(path, paint);
  }

  canvas.restore();
}

/// True when [m] maps area to area and carries no NaN.
///
/// [Affine.invert] alone is not enough: its singularity test is
/// `determinant.abs() < 1e-12`, and every comparison against NaN is false, so a
/// matrix full of NaNs inverts "successfully" into more NaNs. `Canvas.transform`
/// with a NaN then poisons the whole layer, not just this node.
bool _isDrawable(Affine m) =>
    m.a.isFinite &&
    m.b.isFinite &&
    m.c.isFinite &&
    m.d.isFinite &&
    m.tx.isFinite &&
    m.ty.isFinite &&
    m.invert() != null;

/// The `CustomPainter` that owns layer 2.
///
/// **The playhead never enters `build()`.** It arrives as a `ValueNotifier`
/// handed to `super(repaint:)`, so a tick calls `paint()` directly and rebuilds
/// no widget at all. Routing it through a provider instead is a named
/// antipattern (docs/v3/08 §4): it couples every panel to the frame budget, and
/// one slow inspector makes scrubbing unusable app-wide. Legacy round-tripped
/// the playhead through pixels and a `BuildContext`; this constructor is the
/// structural reason that cannot happen again.
///
/// [evaluate] runs **inside** `paint()`. That is what keeps the tick out of the
/// widget tree, and at the docs/v3/00 §6 budget (114 anchors × 10 keyframes) a
/// full pass is free. The `Scene` and the `PathData → ui.Path` conversion are
/// deliberately **not** cached: a cache keyed on mutable geometry is a
/// stale-render bug that looks exactly like an evaluator bug, and it costs days
/// in the wrong package (docs/v3/08 §4).
class ArtboardPainter extends CustomPainter {
  ArtboardPainter({
    required this.document,
    required this.playhead,
    required this.animation,
  }) : super(repaint: playhead);

  final Document document;

  /// Identity is stable for the app's lifetime; only its value changes.
  final ValueNotifier<double> playhead;

  /// Which animation the playhead is a position *within*.
  ///
  /// Null renders the rest pose, which is a defined result and not an edge
  /// case: `evaluate(doc, const [])` is how a document with no animation draws
  /// (docs/v3/01 §11).
  final AnimationId? animation;

  @override
  void paint(Canvas canvas, Size size) {
    final anim = animation;
    final mix = anim == null
        ? const <AnimationMix>[]
        : <AnimationMix>[AnimationMix(anim, _clampT(playhead.value))];

    final scene = evaluate(document, mix);
    final fit = artboardFit(document.artboard, size);

    // The artboard clips: geometry outside it is off-camera, and letting it
    // paint over the surrounding chrome makes the board's edge a lie. Clipped
    // in screen space because [artboardFit] is translate+uniform-scale only, so
    // the board's rect maps to a rect exactly.
    canvas.save();
    canvas.clipRect(Rect.fromPoints(
      _offset(fit.apply(Vec2.zero)),
      _offset(fit.apply(document.artboard)),
    ));
    paintScene(canvas, scene, fit: fit);
    canvas.restore();
  }

  /// The painter boundary is where a bad playhead stops.
  ///
  /// `TypedTrack.bracket` is honest about NaN — it produces a NaN `u` and
  /// therefore NaN geometry — because clamping inside the evaluator would be a
  /// NaN rescue, which docs/v3/08 §1 forbids. Guards belong out here instead,
  /// at the layer that has a frame to draw and a user to show it to.
  static double _clampT(double t) => t.isNaN ? 0.0 : t.clamp(0.0, 1.0);

  static Offset _offset(Vec2 v) => Offset(v.x, v.y);

  /// Identity, never deep equality.
  ///
  /// [Document] is immutable, so a new object *is* the change signal.
  /// Deep-comparing 114 anchors every frame to avoid a paint that costs less
  /// than the comparison is backwards (docs/v3/04 §5). The playhead is absent
  /// from this test on purpose: it repaints through `super(repaint:)` without a
  /// rebuild, so it can never reach here.
  @override
  bool shouldRepaint(ArtboardPainter old) =>
      !identical(old.document, document) ||
      !identical(old.playhead, playhead) ||
      old.animation != animation;
}
