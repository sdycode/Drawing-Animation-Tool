/// Fills, strokes and paint sources (docs/v3/01 §6).
library;

import 'decode.dart';
import 'json.dart';
import 'primitives.dart';

enum FillRule { nonZero, evenOdd }

enum StrokeCap { butt, round, square }

enum StrokeJoin { miter, round, bevel }

/// Enums persist by `.name`. An unrecognised value falls back rather than
/// throwing — the document is still renderable, just with a default join.
T _byName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
    values.asNameMap()[raw] ?? fallback;

/// Sealed **now** so gradients are additive later.
///
/// Adding a variant is a source break (exhaustive switches stop compiling) but
/// never a data break, because `type` is an open string and an unrecognised one
/// lands in [UnknownPaint] rather than failing the decode.
sealed class PaintSource {
  const PaintSource();

  Map<String, Object?> toJson();

  /// An **unknown** `type` degrades to [UnknownPaint]; a **known** one with a
  /// broken body throws with a path.
  ///
  /// The asymmetry is the boundary on [DocumentException] applied here: a paint
  /// type this build has never heard of is forward-compatibility and rides
  /// through verbatim, but `{"type":"solid","color":"red"}` is a paint this
  /// build claims to understand and cannot, and quietly substituting black
  /// would be legacy's `?? defaultValue` habit turning a broken document into a
  /// plausible-but-wrong one.
  factory PaintSource.fromJson(Object? j, [String path = '']) {
    final m = reqObject(j, path);
    return switch (m['type']) {
      'solid' => SolidPaint(reqRgba(m['color'], jsonChild(path, 'color'))),
      'linearGradient' => LinearGradientPaint(
          start: reqVec2(m['start'], jsonChild(path, 'start')),
          end: reqVec2(m['end'], jsonChild(path, 'end')),
          stops: _stops(m['stops'], jsonChild(path, 'stops')),
        ),
      'radialGradient' => RadialGradientPaint(
          center: reqVec2(m['center'], jsonChild(path, 'center')),
          radius: reqDouble(m['radius'], jsonChild(path, 'radius')),
          stops: _stops(m['stops'], jsonChild(path, 'stops')),
        ),
      _ => UnknownPaint(Map.unmodifiable(m)),
    };
  }

  static List<GradientStop> _stops(Object? v, String path) {
    final raw = reqArray(v, path);
    return <GradientStop>[
      for (var k = 0; k < raw.length; k++)
        GradientStop.fromJson(raw[k], jsonIndex(path, k)),
    ];
  }
}

final class SolidPaint extends PaintSource {
  const SolidPaint(this.color);

  final Rgba color;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'type': 'solid', 'color': color.toJson()};

  @override
  bool operator ==(Object other) => other is SolidPaint && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

final class GradientStop {
  const GradientStop({
    required this.id,
    required this.offset,
    required this.color,
  });

  /// Stable, so a stop stays individually animatable and reorder-safe.
  final StopId id;

  /// 0..1.
  final double offset;

  final Rgba color;

  factory GradientStop.fromJson(Object? j, [String path = '']) {
    final m = reqObject(j, path);
    return GradientStop(
      id: StopId(reqString(m['id'], jsonChild(path, 'id'))),
      offset: reqDouble(m['offset'], jsonChild(path, 'offset')),
      color: reqRgba(m['color'], jsonChild(path, 'color')),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.v,
        'offset': offset,
        'color': color.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is GradientStop &&
      other.id == id &&
      other.offset == offset &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, offset, color);
}

/// Rendered in v1, but **not authorable** — there is no gradient UI.
///
/// CanvasKit gradients are ~20 lines; the authoring UI is the week-long part.
/// Rendering what a file already contains avoids the "stub that reads as a bug"
/// trap without buying the expensive half.
final class LinearGradientPaint extends PaintSource {
  const LinearGradientPaint({
    required this.start,
    required this.end,
    required this.stops,
  });

  /// Node-local coordinates.
  final Vec2 start;
  final Vec2 end;
  final List<GradientStop> stops;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'linearGradient',
        'start': start.toJson(),
        'end': end.toJson(),
        'stops': stops.map((s) => s.toJson()).toList(growable: false),
      };
}

final class RadialGradientPaint extends PaintSource {
  const RadialGradientPaint({
    required this.center,
    required this.radius,
    required this.stops,
  });

  final Vec2 center;
  final double radius;
  final List<GradientStop> stops;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'radialGradient',
        'center': center.toJson(),
        'radius': radius,
        'stops': stops.map((s) => s.toJson()).toList(growable: false),
      };
}

/// Preserve-and-skip-render for an unrecognised `paint.type`.
///
/// The renderer draws nothing for it and the encoder writes it back verbatim,
/// so a paint type this build has never heard of survives an autosave.
final class UnknownPaint extends PaintSource {
  const UnknownPaint(this.raw);

  final Map<String, Object?> raw;

  @override
  Map<String, Object?> toJson() => Map<String, Object?>.from(raw);
}

final class Fill {
  const Fill({
    required this.id,
    required this.paint,
    this.rule = FillRule.nonZero,
    this.opacity = 1.0,
    this.visible = true,
  });

  /// The track's subject id, so it survives reordering.
  ///
  /// v1 authors at most one fill, but `PropKey.fillColor` alone cannot say
  /// *which* fill. Retrofitting a subject id once documents exist is a schema
  /// break; it costs nothing now, and instance overrides will need it anyway.
  final PaintId id;

  final PaintSource paint;
  final FillRule rule;
  final double opacity;
  final bool visible;

  factory Fill.fromJson(Object? j, [String path = '']) {
    final m = reqObject(j, path);
    return Fill(
      id: PaintId(reqString(m['id'], jsonChild(path, 'id'))),
      paint: PaintSource.fromJson(m['paint'], jsonChild(path, 'paint')),
      rule: opt(m, 'rule', (v) => _byName(FillRule.values, v, FillRule.nonZero),
          FillRule.nonZero),
      opacity: opt(
          m, 'opacity', (v) => reqDouble(v, jsonChild(path, 'opacity')), 1.0),
      visible: opt(
          m, 'visible', (v) => reqBool(v, jsonChild(path, 'visible')), true),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.v,
        'paint': paint.toJson(),
        'rule': rule.name,
        'opacity': opacity,
        'visible': visible,
      };
}

final class Stroke {
  const Stroke({
    required this.id,
    required this.paint,
    this.width = 1.0,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
    this.miterLimit = 4.0,
    this.opacity = 1.0,
    this.visible = true,
  });

  final PaintId id;
  final PaintSource paint;
  final double width;
  final StrokeCap cap;
  final StrokeJoin join;
  final double miterLimit;
  final double opacity;
  final bool visible;

  /// No `dash`/`dashOffset` in v1: dash-as-trim needs the authored total arc
  /// length, mis-renders on closed and multi-subpath geometry, and puts a
  /// derived geometric quantity into an authored field. `PathTrim` is the
  /// correct primitive for draw-on.
  factory Stroke.fromJson(Object? j, [String path = '']) {
    final m = reqObject(j, path);
    return Stroke(
      id: PaintId(reqString(m['id'], jsonChild(path, 'id'))),
      paint: PaintSource.fromJson(m['paint'], jsonChild(path, 'paint')),
      width:
          opt(m, 'width', (v) => reqDouble(v, jsonChild(path, 'width')), 1.0),
      cap: opt(m, 'cap', (v) => _byName(StrokeCap.values, v, StrokeCap.butt),
          StrokeCap.butt),
      join: opt(
          m,
          'join',
          (v) => _byName(StrokeJoin.values, v, StrokeJoin.miter),
          StrokeJoin.miter),
      miterLimit: opt(m, 'miterLimit',
          (v) => reqDouble(v, jsonChild(path, 'miterLimit')), 4.0),
      opacity: opt(
          m, 'opacity', (v) => reqDouble(v, jsonChild(path, 'opacity')), 1.0),
      visible: opt(
          m, 'visible', (v) => reqBool(v, jsonChild(path, 'visible')), true),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.v,
        'paint': paint.toJson(),
        'width': width,
        'cap': cap.name,
        'join': join.name,
        'miterLimit': miterLimit,
        'opacity': opacity,
        'visible': visible,
      };
}
