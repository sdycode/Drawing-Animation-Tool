/// Paints a document's rest pose (docs/v3/04 §5).
library;

import 'dart:ui' as ui;

// `StrokeCap`/`StrokeJoin` exist in both worlds with the same names and
// different meanings: ours is authored data, dart:ui's is a paint setting. The
// hide-plus-alias keeps both spellable, so the switch below reads as the
// translation it is rather than as a cast.
import 'package:anim_core/anim_core.dart' hide StrokeCap, StrokeJoin;
import 'package:anim_core/anim_core.dart' as anim;
import 'package:flutter/rendering.dart';

import 'path_geometry.dart';

/// Draws a [Document] at its rest pose, with no sampling.
///
/// M0 scope, and deliberately named for it: once tracks exist this takes an
/// evaluated `Scene` instead of a `Document`, because a painter that reaches
/// into the document to decide what to draw is a second evaluator that will
/// disagree with the real one (docs/v3/08 §4).
///
/// Composition rules are stated once in docs/v3/01 §3 and implemented once
/// here: `visible` ANDs down the tree, `opacity` multiplies down it, and
/// `locked` is never read — it is a hit-test gate for the editor, not a render
/// input.
class DocumentPainter extends CustomPainter {
  const DocumentPainter({
    required this.document,
    this.fit = true,
    this.showArtboard = true,
  });

  final Document document;

  /// Letterbox the artboard into the available size, preserving aspect.
  ///
  /// Non-uniform fit is what let legacy scale Y by the width ratio; a single
  /// uniform factor makes that class of drift unrepresentable.
  final bool fit;

  final bool showArtboard;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    if (fit) {
      // The same Affine the editor inverts to turn a click into artboard
      // coordinates. Computing it twice is how a click lands where the shape
      // is not.
      canvas.transform(affineToMatrix4(artboardFit(document.artboard, size)));
    }

    final board = Rect.fromLTWH(0, 0, document.artboard.x, document.artboard.y);
    if (showArtboard) {
      final bg = document.background;
      if (bg.a > 0) {
        canvas.drawRect(board, Paint()..color = _color(bg, 1.0));
      }
    }

    // The artboard clips: geometry outside it is off-camera, and letting it
    // paint over the surrounding chrome makes the board's edge a lie.
    canvas.save();
    canvas.clipRect(board);
    _paintNode(canvas, document.root, opacity: 1.0);
    canvas.restore();

    canvas.restore();
  }

  void _paintNode(Canvas canvas, Node node, {required double opacity}) {
    // `visible` ANDs down the tree: a hidden group hides every descendant
    // regardless of that descendant's own value.
    if (!node.visible) return;
    final inherited = opacity * node.opacity;
    if (inherited <= 0) return;

    canvas.save();
    canvas.transform(affineToMatrix4(node.transform.toAffine()));

    switch (node) {
      case GroupNode():
        if (node.clipChildren) {
          canvas.clipRect(
              Rect.fromLTWH(0, 0, document.artboard.x, document.artboard.y));
        }
        // Index 0 is back-most, so painting in list order is z-order. There is
        // no sort here because there is no zIndex field to sort by.
        for (final child in node.children) {
          _paintNode(canvas, child, opacity: inherited);
        }
      case PathNode():
        _paintPath(canvas, node, inherited);
      case UnknownNode():
        // Renders nothing, by contract. It exists to survive a round trip.
        break;
    }

    canvas.restore();
  }

  void _paintPath(Canvas canvas, PathNode node, double opacity) {
    if (node.path.isEmpty) return; // 0 or 1 anchor draws nothing, never throws
    final geometry = buildPath(node.path);

    for (final fill in node.fills) {
      if (!fill.visible) continue;
      final paint = _paintFor(fill.paint, opacity * fill.opacity);
      if (paint == null) continue; // unknown source: preserve, skip render
      paint
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver;
      geometry.fillType = fill.rule == FillRule.evenOdd
          ? PathFillType.evenOdd
          : PathFillType.nonZero;
      canvas.drawPath(geometry, paint);
    }

    // Strokes paint after every fill, always.
    for (final stroke in node.strokes) {
      if (!stroke.visible) continue;
      final paint = _paintFor(stroke.paint, opacity * stroke.opacity);
      if (paint == null) continue;
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width
        ..strokeCap = switch (stroke.cap) {
          anim.StrokeCap.butt => StrokeCap.butt,
          anim.StrokeCap.round => StrokeCap.round,
          anim.StrokeCap.square => StrokeCap.square,
        }
        ..strokeJoin = switch (stroke.join) {
          anim.StrokeJoin.miter => StrokeJoin.miter,
          anim.StrokeJoin.round => StrokeJoin.round,
          anim.StrokeJoin.bevel => StrokeJoin.bevel,
        }
        ..strokeMiterLimit = stroke.miterLimit;
      canvas.drawPath(geometry, paint);
    }
  }

  /// Null for a paint source this build does not understand — the caller skips
  /// the draw while the encoder still writes the source back verbatim.
  Paint? _paintFor(PaintSource source, double opacity) {
    switch (source) {
      case SolidPaint():
        return Paint()..color = _color(source.color, opacity);
      case LinearGradientPaint():
        if (source.stops.isEmpty) return null;
        return Paint()
          ..shader = ui.Gradient.linear(
            Offset(source.start.x, source.start.y),
            Offset(source.end.x, source.end.y),
            [for (final s in source.stops) _color(s.color, opacity)],
            [for (final s in source.stops) s.offset],
          );
      case RadialGradientPaint():
        if (source.stops.isEmpty || source.radius <= 0) return null;
        return Paint()
          ..shader = ui.Gradient.radial(
            Offset(source.center.x, source.center.y),
            source.radius,
            [for (final s in source.stops) _color(s.color, opacity)],
            [for (final s in source.stops) s.offset],
          );
      case UnknownPaint():
        return null;
    }
  }

  /// Straight (non-premultiplied) sRGB doubles in, Flutter `Color` out.
  static Color _color(Rgba c, double opacity) => Color.fromARGB(
        (_clamp01(c.a * opacity) * 255).round(),
        (_clamp01(c.r) * 255).round(),
        (_clamp01(c.g) * 255).round(),
        (_clamp01(c.b) * 255).round(),
      );

  static double _clamp01(double v) => v.isNaN ? 0.0 : v.clamp(0.0, 1.0);

  @override
  bool shouldRepaint(DocumentPainter old) =>
      !identical(old.document, document) ||
      old.fit != fit ||
      old.showArtboard != showArtboard;
}
