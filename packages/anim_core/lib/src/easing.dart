/// Easing (docs/v3/01 §8, docs/v3/02 §3.11).
library;

import 'json.dart';

/// One concept covers easing **and** stepped interpolation.
///
/// There is deliberately no separate `interpolation` enum: hold *is* an easing
/// and falls out of the same code path, so there is no second field that can
/// disagree with this one. Easing belongs to the key it **leaves** (outgoing),
/// which is why there are no in/out pairs to keep consistent.
sealed class Easing {
  const Easing();

  Map<String, Object?> toJson();

  /// Two shapes only (docs/v3/02 §3.11). An unrecognised `kind` is preserved,
  /// not rejected — see [UnknownEasing].
  factory Easing.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return switch (m['kind']) {
      'linear' => const LinearEasing(),
      'hold' => const HoldEasing(),
      'cubic' => _cubicFromJson(m),
      _ => UnknownEasing(Map.unmodifiable(m)),
    };
  }

  /// A `cubic` whose `p` is not four numbers is malformed, and rewriting it as
  /// a plausible curve is exactly the `?? defaultValue` habit that turned
  /// legacy's broken documents into wrong-but-renderable ones. It rides through
  /// verbatim instead.
  static Easing _cubicFromJson(Map<String, Object?> m) {
    final p = m['p'];
    if (p is! List<Object?> || p.length != 4 || p.any((v) => v is! num)) {
      return UnknownEasing(Map.unmodifiable(m));
    }
    return CubicEasing(d(p[0]), d(p[1]), d(p[2]), d(p[3]));
  }
}

final class LinearEasing extends Easing {
  const LinearEasing();

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': 'linear'};

  @override
  bool operator ==(Object other) => other is LinearEasing;

  @override
  int get hashCode => (LinearEasing).hashCode;

  @override
  String toString() => 'LinearEasing()';
}

/// `u -> 0.0`: the segment holds the value it leaves from, for its whole span.
final class HoldEasing extends Easing {
  const HoldEasing();

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': 'hold'};

  @override
  bool operator ==(Object other) => other is HoldEasing;

  @override
  int get hashCode => (HoldEasing).hashCode;

  @override
  String toString() => 'HoldEasing()';
}

/// CSS-style cubic-bezier with endpoints pinned at (0,0) and (1,1).
///
/// `x1`/`x2` are clamped to 0..1 at solve time because time must stay
/// monotonic; `y1`/`y2` are **not** clamped, which is the whole point —
/// overshoot and anticipation are authored as y outside 0..1.
final class CubicEasing extends Easing {
  const CubicEasing(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// Named presets are **constants persisted as their four numbers**, never as
  /// a name (docs/v3/02 §3.11). The wire format therefore never has to know the
  /// preset vocabulary, and nudging a preset into a custom curve is not a type
  /// change — it is four different doubles in the same field.
  static const ease = CubicEasing(0.25, 0.10, 0.25, 1.00);
  static const easeIn = CubicEasing(0.42, 0.00, 1.00, 1.00);
  static const easeOut = CubicEasing(0.00, 0.00, 0.58, 1.00);
  static const easeInOut = CubicEasing(0.42, 0.00, 0.58, 1.00);
  static const backIn = CubicEasing(0.36, 0.00, 0.66, -0.56);
  static const backOut = CubicEasing(0.34, 1.56, 0.64, 1.00);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': 'cubic',
        'p': <Object?>[x1, y1, x2, y2],
      };

  @override
  bool operator ==(Object other) =>
      other is CubicEasing &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);

  @override
  String toString() => 'CubicEasing($x1, $y1, $x2, $y2)';
}

/// Preserve-and-evaluate-as-linear for an unrecognised `easing.kind`.
///
/// Mirrors `UnknownPaint`: a v4 easing (a spring, say) authored by a newer
/// client must survive this build's autosave. Evaluating it as linear keeps the
/// segment playing — a document that opens with one frozen property is a far
/// better failure than one that will not open, and far better than one that
/// silently loses the curve on save.
final class UnknownEasing extends Easing {
  const UnknownEasing(this.raw);

  final Map<String, Object?> raw;

  @override
  Map<String, Object?> toJson() => Map<String, Object?>.from(raw);

  @override
  String toString() => 'UnknownEasing(${raw['kind']})';
}

/// Pure and total. The segment-local remap, applied exactly where legacy left a
/// bare linear `u` — this is the one place easing belongs, and the reason
/// `TypedTrack.sampleAt` has a single shared implementation.
double applyEasing(Easing e, double u) {
  final c = u.clamp(0.0, 1.0);
  return switch (e) {
    HoldEasing() => 0.0,
    LinearEasing() => c,
    UnknownEasing() => c,
    CubicEasing(:final x1, :final y1, :final x2, :final y2) =>
      _solveCubicBezier(x1, y1, x2, y2, c),
  };
}

/// One coordinate of a unit cubic bezier with endpoints pinned at 0 and 1.
double _axis(double a1, double a2, double u) {
  final v = 1.0 - u;
  return 3.0 * v * v * u * a1 + 3.0 * v * u * u * a2 + u * u * u;
}

double _slope(double a1, double a2, double u) {
  final v = 1.0 - u;
  return 3.0 * v * v * a1 + 6.0 * v * u * (a2 - a1) + 3.0 * u * u * (1.0 - a2);
}

/// Newton-Raphson (8 iterations) with a bisection fallback.
///
/// Newton alone is not enough: a curve with a near-flat x segment (`backIn`
/// territory) drives the derivative to ~0 and the step to infinity, which would
/// hand NaN to every downstream lerp. Bisection cannot diverge, so the solver
/// is total for every representable pair of control points.
double _solveCubicBezier(double x1, double y1, double x2, double y2, double x) {
  if (x <= 0.0) return 0.0;
  if (x >= 1.0) return 1.0;

  // Time must be monotonic, so x is clamped; y is left alone so overshoot and
  // anticipation survive.
  final cx1 = x1.clamp(0.0, 1.0);
  final cx2 = x2.clamp(0.0, 1.0);

  var u = x;
  for (var n = 0; n < 8; n++) {
    final err = _axis(cx1, cx2, u) - x;
    if (err.abs() < 1e-7) return _axis(y1, y2, u);
    final dx = _slope(cx1, cx2, u);
    if (dx.abs() < 1e-7) break;
    u -= err / dx;
    if (u < 0.0 || u > 1.0) break;
  }

  var lo = 0.0;
  var hi = 1.0;
  u = x;
  for (var n = 0; n < 48; n++) {
    final err = _axis(cx1, cx2, u) - x;
    if (err.abs() < 1e-7) break;
    if (err < 0.0) {
      lo = u;
    } else {
      hi = u;
    }
    u = (lo + hi) * 0.5;
  }
  return _axis(y1, y2, u);
}
