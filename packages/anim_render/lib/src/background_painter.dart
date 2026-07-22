/// Layer 1 of three: the artboard's fill and edge (docs/v3/04 §5).
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/rendering.dart';

import 'paint_translation.dart';
import 'path_geometry.dart';

/// Draws the board the document sits on — nothing else, ever.
///
/// This is the cheapest of the three painters and the one that repaints least
/// (artboard size and zoom only), which is exactly why it is separate: folding
/// it into [ArtboardPainter] would make every playhead tick redraw a rectangle
/// that has not changed since the file opened.
///
/// It takes the artboard **values** rather than the `Document` because it reads
/// two fields and the identity of the whole document changes on every anchor
/// drag. Value equality over a `Vec2` and an `Rgba` is two comparisons; identity
/// over the document would repaint this layer on every mutation for nothing.
class BackgroundPainter extends CustomPainter {
  const BackgroundPainter({
    required this.artboard,
    required this.background,
    required this.edge,
    required this.fit,
  });

  final Vec2 artboard;

  /// The composed `viewport ∘ artboardFit` the canvas built once (docs/v3/05 §3).
  ///
  /// **Required, and never null.** It was optional, and each of the three
  /// painters then fell back to its own `artboardFit(...)` — three places that
  /// could build a document→screen mapping, so passing `fit:` to two of them and
  /// forgetting the third produced one silently un-panned layer with no compile
  /// error and no failing test. One mapping, one source (AC-3.1.4).
  ///
  /// There is no `mode` here on purpose: this layer draws the board rect and
  /// nothing else, so clipping it to the board is a no-op. The clip decision
  /// belongs to the two layers that can draw *outside* the board — see
  /// [RenderMode].
  final Affine fit;

  /// The document's authored background. Fully transparent is legal and means
  /// "draw the edge only", which is how an exported PNG keeps its alpha.
  final Rgba background;

  /// Chrome colour for the board's outline, supplied by the app's theme.
  ///
  /// Passed in rather than looked up: this package must not know that
  /// `ThemeData` exists, or the render layer acquires a `BuildContext` and the
  /// golden tests acquire a widget tree.
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    // The same composed matrix the artboard painter and hit-testing use.
    // Computing the fit twice is how a click lands where the shape is not, and
    // it is also how the background ends up one pixel off the geometry.
    final board = Rect.fromPoints(
      _offset(fit.apply(Vec2.zero)),
      _offset(fit.apply(artboard)),
    );

    if (background.a > 0) {
      canvas.drawRect(board, Paint()..color = toUiColor(background, 1.0));
    }

    // Stroked in screen space, so the edge stays a hairline at every zoom
    // instead of scaling with the board and disappearing when zoomed out.
    canvas.drawRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );
  }

  static Offset _offset(Vec2 v) => Offset(v.x, v.y);

  @override
  bool shouldRepaint(BackgroundPainter old) =>
      old.artboard != artboard ||
      old.background != background ||
      old.edge != edge ||
      old.fit != fit; // a pan/zoom moves the board without touching the doc
}
