/// Identity and value types (docs/v3/01 §2).
library;

import 'dart:math' as math;

import 'json.dart';

/// Zero-cost typed wrappers. A [NodeId] can never be passed where an
/// [AnchorId] is wanted — the entire keyframe/topology join rests on that, and
/// a bare `String` on both sides makes the mistake invisible to the compiler.
///
/// Values are opaque. Minted once at creation, **never** reused, and **never**
/// derived from list position — deriving from position is precisely the legacy
/// defect the rewrite exists to fix (docs/v3/01 §1).
extension type const NodeId(String v) {}

extension type const AnchorId(String v) {}

extension type const PaintId(String v) {}

extension type const StopId(String v) {}

extension type const AnimationId(String v) {}

final class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  static const zero = Vec2(0, 0);
  static const one = Vec2(1, 1);

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);

  double get length => math.sqrt(x * x + y * y);

  static Vec2 lerp(Vec2 a, Vec2 b, double u) =>
      Vec2(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u);

  /// `{"x":…, "y":…}`, both int-or-double on the wire (docs/v3/02 §6).
  factory Vec2.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return Vec2(d(m['x']), d(m['y']));
  }

  /// Always emits doubles. Firestore may normalise `0.0` back to `0`; [d] on
  /// the read side is what makes that harmless.
  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec2($x, $y)';
}

/// Straight (non-premultiplied) sRGB, doubles 0..1.
///
/// Doubles rather than a hex string or packed int: legacy stored `'ffeee2dd'`
/// next to `'FFFFC0CB'` and had to string-parse on every render.
final class Rgba {
  const Rgba(this.r, this.g, this.b, [this.a = 1.0]);

  final double r;
  final double g;
  final double b;
  final double a;

  static const transparent = Rgba(0, 0, 0, 0);
  static const black = Rgba(0, 0, 0);

  factory Rgba.fromArgb32(int v) => Rgba(
        ((v >> 16) & 0xFF) / 255,
        ((v >> 8) & 0xFF) / 255,
        (v & 0xFF) / 255,
        ((v >> 24) & 0xFF) / 255,
      );

  /// Component-wise straight sRGB, not OKLab — slightly muddy through some hue
  /// transitions, and a `space` field is additive if that ever matters.
  static Rgba lerp(Rgba x, Rgba y, double u) => Rgba(
        x.r + (y.r - x.r) * u,
        x.g + (y.g - x.g) * u,
        x.b + (y.b - x.b) * u,
        x.a + (y.a - x.a) * u,
      );

  /// `[r,g,b,a]` — an array, not an object (docs/v3/02 §3.1).
  factory Rgba.fromJson(Object? j) {
    final l = j! as List<Object?>;
    return Rgba(d(l[0]), d(l[1]), d(l[2]), d(l[3]));
  }

  List<Object?> toJson() => <Object?>[r, g, b, a];

  @override
  bool operator ==(Object other) =>
      other is Rgba &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'Rgba($r, $g, $b, $a)';
}
