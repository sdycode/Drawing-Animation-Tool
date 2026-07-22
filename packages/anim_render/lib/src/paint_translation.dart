/// Authored paint (`anim_core`) → `dart:ui` paint (docs/v3/04 §5).
///
/// One direction, one file. Every painter in this package goes through these
/// functions rather than building a `Paint` inline, because the moment two call
/// sites translate `Rgba` themselves they disagree about premultiplication and
/// the disagreement shows up as a gradient that is subtly darker than the solid
/// fill beside it.
library;

import 'dart:ui' as ui;

// `StrokeCap`/`StrokeJoin` exist in both worlds with the same names and
// different meanings: ours is authored data, dart:ui's is a paint setting. The
// hide-plus-alias keeps both spellable, so the switches below read as the
// translation they are rather than as a cast.
import 'package:anim_core/anim_core.dart' hide Animation, StrokeCap, StrokeJoin;
import 'package:anim_core/anim_core.dart' as anim;
import 'package:flutter/rendering.dart';

/// Straight (non-premultiplied) sRGB doubles in, Flutter [Color] out.
///
/// NaN maps to 0 rather than propagating: this is the painter boundary, where
/// guards are legal (docs/v3/08 §1), and `Color.fromARGB` on a NaN `round()`
/// throws — which would turn one bad stop into a dead frame.
Color toUiColor(Rgba c, double opacity) => Color.fromARGB(
      (_clamp01(c.a * opacity) * 255).round(),
      (_clamp01(c.r) * 255).round(),
      (_clamp01(c.g) * 255).round(),
      (_clamp01(c.b) * 255).round(),
    );

double _clamp01(double v) => v.isNaN ? 0.0 : v.clamp(0.0, 1.0);

/// Null for a paint source this build does not understand.
///
/// The caller skips the draw while the encoder still writes the source back
/// verbatim — that asymmetry is the whole point of [UnknownPaint]. Returning a
/// magenta "error" fill instead would make a document authored by a newer build
/// look corrupt rather than look unsupported.
Paint? paintFor(PaintSource source, double opacity) {
  switch (source) {
    case SolidPaint():
      return Paint()..color = toUiColor(source.color, opacity);
    case LinearGradientPaint():
      if (source.stops.isEmpty) return null;
      return Paint()
        ..shader = ui.Gradient.linear(
          Offset(source.start.x, source.start.y),
          Offset(source.end.x, source.end.y),
          [for (final s in source.stops) toUiColor(s.color, opacity)],
          [for (final s in source.stops) s.offset],
        );
    case RadialGradientPaint():
      if (source.stops.isEmpty || source.radius <= 0) return null;
      return Paint()
        ..shader = ui.Gradient.radial(
          Offset(source.center.x, source.center.y),
          source.radius,
          [for (final s in source.stops) toUiColor(s.color, opacity)],
          [for (final s in source.stops) s.offset],
        );
    case UnknownPaint():
      return null;
  }
}

StrokeCap toUiCap(anim.StrokeCap cap) => switch (cap) {
      anim.StrokeCap.butt => StrokeCap.butt,
      anim.StrokeCap.round => StrokeCap.round,
      anim.StrokeCap.square => StrokeCap.square,
    };

StrokeJoin toUiJoin(anim.StrokeJoin join) => switch (join) {
      anim.StrokeJoin.miter => StrokeJoin.miter,
      anim.StrokeJoin.round => StrokeJoin.round,
      anim.StrokeJoin.bevel => StrokeJoin.bevel,
    };

PathFillType toUiFillType(FillRule rule) => switch (rule) {
      FillRule.nonZero => PathFillType.nonZero,
      FillRule.evenOdd => PathFillType.evenOdd,
    };
