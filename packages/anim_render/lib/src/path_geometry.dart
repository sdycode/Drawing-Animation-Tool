/// `PathData` → `dart:ui.Path` (docs/v3/04 §5).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anim_core/anim_core.dart';

/// Builds the `ui.Path` for one node's geometry.
///
/// Every segment is emitted as a cubic, with no polyline branch: a `corner`
/// anchor has zero tangents, so `cubicTo` collapses to a straight line on its
/// own. Legacy carried separate straight/curve paths that disagreed about
/// where a segment ended.
///
/// Total by construction — a degenerate path yields an empty `ui.Path` rather
/// than throwing, because the pen tool produces exactly that on its first
/// click and a half-drawn shape must not take the canvas down.
ui.Path buildPath(PathData data) {
  final path = ui.Path();
  final anchors = data.anchors;
  if (anchors.length < 2) return path;

  path.moveTo(anchors.first.position.x, anchors.first.position.y);
  for (var k = 0; k < data.segmentCount; k++) {
    final (_, p1, p2, p3) = data.segment(k);
    path.cubicTo(p1.x, p1.y, p2.x, p2.y, p3.x, p3.y);
  }
  if (data.closed) path.close();
  return path;
}

/// The document→screen transform: letterbox the artboard into [size].
///
/// **One uniform factor, never one per axis.** Legacy scaled Y by the width
/// ratio, which is invisible on a square board and drifts on every other one.
///
/// Returned as an [Affine] rather than applied directly to a canvas so that the
/// painter and the editor's hit-testing use the *same* mapping — computing the
/// fit twice is how a click lands somewhere the shape is not.
Affine artboardFit(Vec2 artboard, ui.Size size) {
  if (artboard.x <= 0 || artboard.y <= 0) return Affine.identity;
  final scale = math.min(size.width / artboard.x, size.height / artboard.y);
  return Affine.translate(
    (size.width - artboard.x * scale) / 2,
    (size.height - artboard.y * scale) / 2,
  ).mul(Affine.scale(scale, scale));
}

/// `Affine` → `Matrix4`-shaped storage, the only place the two conventions meet.
///
/// `Affine` is `[a c tx ; b d ty]`; `ui`/`vector_math` want a column-major 4×4.
/// Written once, here, so no call site hand-rolls the mapping and transposes it
/// by accident.
Float64List affineToMatrix4(Affine m) {
  final s = Float64List(16);
  s[0] = m.a;
  s[1] = m.b;
  s[4] = m.c;
  s[5] = m.d;
  s[10] = 1.0;
  s[12] = m.tx;
  s[13] = m.ty;
  s[15] = 1.0;
  return s;
}
