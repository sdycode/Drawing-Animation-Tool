/// Fills, strokes and paint sources (docs/v3/01 §6).
library;

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

  factory PaintSource.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return switch (m['type']) {
      'solid' => SolidPaint(Rgba.fromJson(m['color'])),
      'linearGradient' => LinearGradientPaint(
          start: Vec2.fromJson(m['start']),
          end: Vec2.fromJson(m['end']),
          stops: _stops(m['stops']),
        ),
      'radialGradient' => RadialGradientPaint(
          center: Vec2.fromJson(m['center']),
          radius: d(m['radius']),
          stops: _stops(m['stops']),
        ),
      _ => UnknownPaint(Map.unmodifiable(m)),
    };
  }

  static List<GradientStop> _stops(Object? v) =>
      (v! as List<Object?>).map(GradientStop.fromJson).toList(growable: false);
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

  factory GradientStop.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return GradientStop(
      id: StopId(m['id']! as String),
      offset: d(m['offset']),
      color: Rgba.fromJson(m['color']),
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

  factory Fill.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return Fill(
      id: PaintId(m['id']! as String),
      paint: PaintSource.fromJson(m['paint']),
      rule: opt(m, 'rule', (v) => _byName(FillRule.values, v, FillRule.nonZero),
          FillRule.nonZero),
      opacity: opt(m, 'opacity', d, 1.0),
      visible: opt(m, 'visible', (v) => v as bool, true),
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
  factory Stroke.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return Stroke(
      id: PaintId(m['id']! as String),
      paint: PaintSource.fromJson(m['paint']),
      width: opt(m, 'width', d, 1.0),
      cap: opt(m, 'cap', (v) => _byName(StrokeCap.values, v, StrokeCap.butt),
          StrokeCap.butt),
      join: opt(
          m,
          'join',
          (v) => _byName(StrokeJoin.values, v, StrokeJoin.miter),
          StrokeJoin.miter),
      miterLimit: opt(m, 'miterLimit', d, 4.0),
      opacity: opt(m, 'opacity', d, 1.0),
      visible: opt(m, 'visible', (v) => v as bool, true),
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
