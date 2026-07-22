/// Shape recipes — **inert** re-edit metadata (docs/v3/01 §5, docs/v3/02 §3.7).
///
/// A recipe records the parameters a shape *tool* used to emit a node's
/// anchors, so "make that rectangle 20 units wider" stays a one-field edit
/// instead of a manual drag of four anchors. It is metadata about how the
/// geometry came to exist; it is **not** geometry, and nothing renders from it.
///
/// ## Three rules, all load-bearing
///
/// 1. **Recipes are never animated.** They are absent from [PropKey] and from
///    `kExpectedTrackType`, and parametric-shape animation is a written
///    non-goal (docs/v3/01 §7). Promoting a recipe parameter to an animatable
///    property later is additive; doing it now buys a second, disagreeing
///    source of truth for the same anchors.
/// 2. **The evaluator and the renderer never read a recipe.** `evaluate` walks
///    `PathNode.path`; the recipe is not consulted at any of the eight stages.
///    `recipe_test.dart` asserts the evaluated output is byte-identical with
///    and without one, because "inert" is a property that decays the moment
///    somebody finds it convenient to read.
/// 3. **Authority (docs/v3/01 §5): the recipe regenerates `path`, and any
///    manual anchor edit nulls the recipe.** Without that rule, re-editing a
///    rectangle silently discards every manual edit made since it was drawn.
///    `PathOps.moveAnchor` implements the nulling half today.
///
/// ## What is deliberately *not* here
///
/// The shape **tools** that mint these — rect / ellipse / polygon, with
/// `EllipseRecipe` emitting real cubics at κ = 0.5523 rather than legacy's 114
/// straight segments — are **M3** (docs/v3/06). Nothing in v1's UI writes a
/// recipe yet. These types exist now for one reason: so a rectangle authored by
/// a later build survives this build's autosave as a rectangle rather than
/// being flattened into four anonymous anchors, which is the same forward
/// -compatibility debt `UnknownNode` and `UnknownPaint` pay off.
///
/// Regeneration is likewise absent. Rewriting a recipe on a node that has a
/// `path` track must route through `PathOps.retopologize` (**M5**), never a raw
/// path replacement: a raw replacement mints fresh `AnchorId`s, which makes the
/// node's topology and its keyframe poses disjoint id sets and breaks the whole
/// model. There is no partial version of that op worth shipping, so there is
/// none.
library;

// Imported for the `[DocumentException]` doc reference below — the one place
// the required/optional decode boundary is written down.
// ignore: unused_import
import 'decode.dart';
import 'json.dart';

/// Sealed so a fourth shape is a source break (exhaustive switches stop
/// compiling) but never a data break — `type` is an open string and an
/// unrecognised one lands in [UnknownRecipe].
sealed class ShapeRecipe {
  const ShapeRecipe();

  Map<String, Object?> toJson();

  /// **Total.** Never throws, whatever the bytes say.
  ///
  /// A recipe is optional metadata with a preserve-verbatim variant, so it sits
  /// squarely on the degrading side of the boundary described on
  /// [DocumentException]: an unreadable one becomes an [UnknownRecipe] and
  /// rides through untouched. Coercing it to a plausible rectangle would be
  /// worse than dropping it — the user would see a shape whose recipe silently
  /// disagrees with its anchors, and the first re-edit would rewrite the
  /// geometry to match the wrong numbers.
  static ShapeRecipe fromJson(Object? j) {
    if (j is! Map<String, Object?>) return UnknownRecipe(const {});
    return switch (j['type']) {
          'rect' => RectRecipe.tryFromJson(j),
          'ellipse' => EllipseRecipe.tryFromJson(j),
          'polygon' => PolygonRecipe.tryFromJson(j),
          _ => null,
        } ??
        UnknownRecipe(Map.unmodifiable(j));
  }

  static double? _num(Object? v) => v is num ? d(v) : null;

  static int? _int(Object? v) => v is num ? i(v) : null;
}

/// `{"type":"rect","w":40.0,"h":40.0,"cornerRadius":0.0}`
final class RectRecipe extends ShapeRecipe {
  const RectRecipe({
    required this.w,
    required this.h,
    this.cornerRadius = 0.0,
    this.unknownKeys = const {},
  });

  final double w;
  final double h;
  final double cornerRadius;
  final Map<String, Object?> unknownKeys;

  static const _known = <String>{'type', 'w', 'h', 'cornerRadius'};

  /// Null when this build cannot read the shape's parameters, which routes the
  /// raw map to [UnknownRecipe] rather than to a default-constructed square.
  static RectRecipe? tryFromJson(Map<String, Object?> m) {
    final w = ShapeRecipe._num(m['w']);
    final h = ShapeRecipe._num(m['h']);
    if (w == null || h == null) return null;
    final r = m.containsKey('cornerRadius')
        ? ShapeRecipe._num(m['cornerRadius'])
        : 0.0;
    if (r == null) return null;
    return RectRecipe(
      w: w,
      h: h,
      cornerRadius: r,
      unknownKeys: unknownKeysOf(m, _known),
    );
  }

  @override
  Map<String, Object?> toJson() => withUnknown(unknownKeys, <String, Object?>{
        'type': 'rect',
        'w': w,
        'h': h,
        'cornerRadius': cornerRadius,
      });

  @override
  bool operator ==(Object other) =>
      other is RectRecipe &&
      other.w == w &&
      other.h == h &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(w, h, cornerRadius);

  @override
  String toString() => 'RectRecipe($w x $h, r $cornerRadius)';
}

/// `{"type":"ellipse","rx":30.0,"ry":20.0}`
final class EllipseRecipe extends ShapeRecipe {
  const EllipseRecipe({
    required this.rx,
    required this.ry,
    this.unknownKeys = const {},
  });

  final double rx;
  final double ry;
  final Map<String, Object?> unknownKeys;

  static const _known = <String>{'type', 'rx', 'ry'};

  static EllipseRecipe? tryFromJson(Map<String, Object?> m) {
    final rx = ShapeRecipe._num(m['rx']);
    final ry = ShapeRecipe._num(m['ry']);
    if (rx == null || ry == null) return null;
    return EllipseRecipe(
      rx: rx,
      ry: ry,
      unknownKeys: unknownKeysOf(m, _known),
    );
  }

  @override
  Map<String, Object?> toJson() => withUnknown(unknownKeys, <String, Object?>{
        'type': 'ellipse',
        'rx': rx,
        'ry': ry,
      });

  @override
  bool operator ==(Object other) =>
      other is EllipseRecipe && other.rx == rx && other.ry == ry;

  @override
  int get hashCode => Object.hash(rx, ry);

  @override
  String toString() => 'EllipseRecipe($rx x $ry)';
}

/// `{"type":"polygon","sides":5,"radius":50.0,"star":true,"innerRatio":0.5}`
///
/// One type covers polygons and stars: a star *is* a polygon with an alternating
/// inner radius, and two node types for one construction is two code paths for
/// every future edit to diverge across.
final class PolygonRecipe extends ShapeRecipe {
  const PolygonRecipe({
    required this.sides,
    required this.radius,
    this.star = false,
    this.innerRatio = 0.5,
    this.unknownKeys = const {},
  });

  /// The one deliberate `int` in this type — a polygon with 5.5 sides is not a
  /// shape, so the wire keeps it integral (compare `Animation.fps`).
  final int sides;

  final double radius;
  final bool star;
  final double innerRatio;
  final Map<String, Object?> unknownKeys;

  static const _known = <String>{
    'type',
    'sides',
    'radius',
    'star',
    'innerRatio',
  };

  static PolygonRecipe? tryFromJson(Map<String, Object?> m) {
    final sides = ShapeRecipe._int(m['sides']);
    final radius = ShapeRecipe._num(m['radius']);
    if (sides == null || radius == null) return null;
    final star = m.containsKey('star') ? m['star'] : false;
    if (star is! bool) return null;
    final inner =
        m.containsKey('innerRatio') ? ShapeRecipe._num(m['innerRatio']) : 0.5;
    if (inner == null) return null;
    return PolygonRecipe(
      sides: sides,
      radius: radius,
      star: star,
      innerRatio: inner,
      unknownKeys: unknownKeysOf(m, _known),
    );
  }

  @override
  Map<String, Object?> toJson() => withUnknown(unknownKeys, <String, Object?>{
        'type': 'polygon',
        'sides': sides,
        'radius': radius,
        'star': star,
        'innerRatio': innerRatio,
      });

  @override
  bool operator ==(Object other) =>
      other is PolygonRecipe &&
      other.sides == sides &&
      other.radius == radius &&
      other.star == star &&
      other.innerRatio == innerRatio;

  @override
  int get hashCode => Object.hash(sides, radius, star, innerRatio);

  @override
  String toString() =>
      'PolygonRecipe($sides sides, r $radius, star: $star, $innerRatio)';
}

/// Preserve-and-ignore for a recipe this build cannot read.
///
/// Mirrors `UnknownNode` / `UnknownPaint` / `UnknownEasing`. A v4 `spiral`
/// recipe, or a `rect` whose `w` arrived as a string, is re-emitted byte for
/// byte on the next save. Since no v1 code path reads a recipe at all, carrying
/// an unreadable one costs exactly nothing at render time and saves the user a
/// shape they would otherwise have to redraw.
final class UnknownRecipe extends ShapeRecipe {
  const UnknownRecipe(this.raw);

  final Map<String, Object?> raw;

  @override
  Map<String, Object?> toJson() => Map<String, Object?>.from(raw);

  @override
  bool operator ==(Object other) =>
      other is UnknownRecipe &&
      other.raw.length == raw.length &&
      other.raw.entries.every((e) => raw[e.key] == e.value);

  @override
  int get hashCode => raw.length.hashCode;

  @override
  String toString() => 'UnknownRecipe(${raw['type']})';
}
