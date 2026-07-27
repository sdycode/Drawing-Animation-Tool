/// Cubic-Bézier flattening, arc-length measurement and de Casteljau splitting
/// (docs/v3/01 §5).
///
/// This is the shared geometry math the M5 topology edits ([PathOps.insertAnchor],
/// [PathOps.retopologize]) and the M6 trim stage ([applyTrim]) both need. It
/// lived as private helpers inside `ops/path_ops.dart` through M5; M6 hoisted it
/// **down** here so the evaluator can reuse it rather than duplicate it (docs/v3/01
/// §5 names the arc-length table as the one real perf hazard, and two copies of it
/// is two places for the flatness test to drift).
///
/// Nothing in this file constructs a [PathData] — it only **reads** posed cubics
/// (`segment`, `segmentCount`, `closed`) and returns points, records and tables.
/// That keeps it off `boundary_test.dart`'s `PathData` builder allowlist: the
/// trim stage that *does* mint geometry stays in the evaluator, the one file
/// docs/v3/08 §1 trusts with the unchecked constructor.
library;

import '../path.dart';
import '../primitives.dart';

/// Flatness tolerance in document units. Well below any downstream raster
/// tolerance, so the sampled length is exact for a correspondence morph and a
/// trim cut lands on the authored curve.
const double _tolerance = 0.01;
const int _maxDepth = 20;

/// The pieces of a de Casteljau split of the cubic [p0]..[p3] at parameter [u]
/// that a topology **insert** needs (docs/v3/01 §13.5).
///
/// The new anchor sits at [pos] with handles [inT]/[outT]; the left neighbour's
/// outgoing handle becomes [leftOut] and the right neighbour's incoming handle
/// [rightIn]. The two sub-cubics `[p0, p0+leftOut, pos+inT, pos]` and
/// `[pos, pos+outT, p3+rightIn, p3]` reproduce [p0]..[p3] exactly, which is why
/// the insert is pixel-identical (AC-4.3.2).
({Vec2 pos, Vec2 inT, Vec2 outT, Vec2 leftOut, Vec2 rightIn}) deCasteljauSplit(
    Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double u) {
  final q0 = Vec2.lerp(p0, p1, u);
  final q1 = Vec2.lerp(p1, p2, u);
  final q2 = Vec2.lerp(p2, p3, u);
  final r0 = Vec2.lerp(q0, q1, u);
  final r1 = Vec2.lerp(q1, q2, u);
  final s = Vec2.lerp(r0, r1, u);
  return (
    pos: s,
    inT: r0 - s,
    outT: r1 - s,
    leftOut: q0 - p0,
    rightIn: q2 - p3,
  );
}

/// The control points of the sub-arc of the cubic [p0]..[p3] between parameters
/// [t0] and [t1] (`0 <= t0 <= t1 <= 1`).
///
/// Exact, not sampled: two de Casteljau operations, so the returned cubic is the
/// authored curve restricted to `[t0, t1]` — which is what lets the trim stage's
/// output lie **on** the authored path rather than fanning out of the origin
/// (docs/v3/01 §13.4).
(Vec2, Vec2, Vec2, Vec2) subCubic(
    Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double t0, double t1) {
  // Left-split at t1: the cubic covering [0, t1] is (p0, q0, r0, s1).
  final q0 = Vec2.lerp(p0, p1, t1);
  final q1 = Vec2.lerp(p1, p2, t1);
  final q2 = Vec2.lerp(p2, p3, t1);
  final r0 = Vec2.lerp(q0, q1, t1);
  final r1 = Vec2.lerp(q1, q2, t1);
  final s1 = Vec2.lerp(r0, r1, t1);
  // On that left cubic, parameter t0 sits at u = t0 / t1; keep its right part.
  final u = t1 <= 0.0 ? 0.0 : t0 / t1;
  final w0 = Vec2.lerp(p0, q0, u);
  final w1 = Vec2.lerp(q0, r0, u);
  final w2 = Vec2.lerp(r0, s1, u);
  final x0 = Vec2.lerp(w0, w1, u);
  final x1 = Vec2.lerp(w1, w2, u);
  final y = Vec2.lerp(x0, x1, u);
  return (y, x1, w2, s1);
}

/// Adaptive subdivision of one cubic, emitting the points **after** [p0] up to
/// and including [p3], each tagged with its cubic parameter in `[t0, t1]`.
///
/// The classic control-point-deviation flatness test. The positions are exactly
/// those the M5 code produced; the parameter tag is the addition M6 needs to
/// turn an arc-length position back into a curve parameter to split at.
void flattenCubic(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, double t0, double t1,
    int depth, List<({double t, Vec2 point})> out) {
  if (depth >= _maxDepth || _flatEnough(p0, p1, p2, p3)) {
    out.add((t: t1, point: p3));
    return;
  }
  final p01 = Vec2.lerp(p0, p1, 0.5);
  final p12 = Vec2.lerp(p1, p2, 0.5);
  final p23 = Vec2.lerp(p2, p3, 0.5);
  final p012 = Vec2.lerp(p01, p12, 0.5);
  final p123 = Vec2.lerp(p12, p23, 0.5);
  final mid = Vec2.lerp(p012, p123, 0.5);
  final tm = (t0 + t1) * 0.5;
  flattenCubic(p0, p01, p012, mid, t0, tm, depth + 1, out);
  flattenCubic(mid, p123, p23, p3, tm, t1, depth + 1, out);
}

bool _flatEnough(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3) {
  var ux = 3.0 * p1.x - 2.0 * p0.x - p3.x;
  ux *= ux;
  var uy = 3.0 * p1.y - 2.0 * p0.y - p3.y;
  uy *= uy;
  var vx = 3.0 * p2.x - p0.x - 2.0 * p3.x;
  vx *= vx;
  var vy = 3.0 * p2.y - p0.y - 2.0 * p3.y;
  vy *= vy;
  if (ux < vx) ux = vx;
  if (uy < vy) uy = vy;
  return ux + uy <= 16.0 * _tolerance * _tolerance;
}

/// One flattened sample: cubic parameter [t] within its segment and the global
/// cumulative arc length [arc] at that point.
typedef _Sample = ({double t, double arc});

/// A cumulative arc-length table over an immutable [PathData], built by adaptive
/// flattening (docs/v3/01 §5).
///
/// Correct, not fast, and built **once per document mutation** — never inside the
/// tick (docs/v3/03 AC-13.5). The evaluator's trim stage memoizes it per
/// immutable `PathData`; [PathOps.retopologize] builds it directly and per
/// keyframe, because each keyframe draws different geometry (AC-8.1.7 explicitly
/// calls that an inherent per-t rebuild, not a memo miss to fix).
class ArcTable {
  ArcTable._(this._points, this._cumulative, this.total, this._anchorArc,
      this._segments, this._segmentCount);

  /// **Diagnostic only.** Incremented on every real build so a test can prove the
  /// evaluator's memo works (AC-8.1.7). Not read by any production code path.
  static int buildCount = 0;

  /// Flattened polyline of the whole path, in draw order.
  final List<Vec2> _points;

  /// Cumulative arc length at each entry of [_points]. `_cumulative[0] == 0`.
  final List<double> _cumulative;

  /// Total arc length of the path.
  final double total;

  /// Arc length at each anchor (the start of its outgoing segment; the final
  /// anchor of an open path sits at [total]).
  final List<double> _anchorArc;

  /// Per segment, the flattened `(t, arc)` samples, each list opening with
  /// `(0.0, segment-start-arc)` and closing with `(1.0, segment-end-arc)`.
  final List<List<_Sample>> _segments;

  final int _segmentCount;

  static ArcTable build(PathData path) {
    buildCount++;
    final points = <Vec2>[];
    final cumulative = <double>[];
    final anchorArc = <double>[];
    final segments = <List<_Sample>>[];

    if (path.segmentCount == 0) {
      // 0 or 1 anchor renders nothing (invariant P2); every fraction collapses
      // to the single point (or the origin for the empty path).
      for (final a in path.anchors) {
        anchorArc.add(0.0);
        if (points.isEmpty) {
          points.add(a.position);
          cumulative.add(0.0);
        }
      }
      return ArcTable._(points, cumulative, 0.0, anchorArc, segments, 0);
    }

    var length = 0.0;
    points.add(path.segment(0).$1);
    cumulative.add(0.0);
    for (var k = 0; k < path.segmentCount; k++) {
      anchorArc.add(length); // arc at anchor k (start of segment k)
      final (p0, p1, p2, p3) = path.segment(k);
      final seg = <_Sample>[(t: 0.0, arc: length)];
      final flat = <({double t, Vec2 point})>[];
      flattenCubic(p0, p1, p2, p3, 0.0, 1.0, 0, flat);
      for (final sample in flat) {
        length += (sample.point - points.last).length;
        points.add(sample.point);
        cumulative.add(length);
        seg.add((t: sample.t, arc: length));
      }
      segments.add(seg);
    }
    // An open path has one more anchor than segments; it sits at the far end.
    if (!path.closed) anchorArc.add(length);
    return ArcTable._(
        points, cumulative, length, anchorArc, segments, path.segmentCount);
  }

  /// The arc-length fraction `[0,1]` of each anchor, in topology order. Used by
  /// [PathOps.retopologize] for arc-length correspondence.
  List<double> anchorFractions() => <double>[
        for (final a in _anchorArc) total <= 0.0 ? 0.0 : a / total,
      ];

  /// The point at arc-length fraction [f] along the flattened path. Used by
  /// [PathOps.retopologize].
  Vec2 pointAtFraction(double f) {
    if (_points.isEmpty) return Vec2.zero;
    if (_points.length == 1 || total <= 0.0) return _points.first;
    final target = f.clamp(0.0, 1.0) * total;
    for (var i = 1; i < _cumulative.length; i++) {
      if (_cumulative[i] >= target) {
        final span = _cumulative[i] - _cumulative[i - 1];
        final t = span <= 0.0 ? 0.0 : (target - _cumulative[i - 1]) / span;
        return Vec2.lerp(_points[i - 1], _points[i], t);
      }
    }
    return _points.last;
  }

  /// The segment index and cubic parameter at absolute arc length [arc], the
  /// inverse of the arc-length integral the trim stage cuts at.
  ///
  /// Clamped to `[0, total]`: a position before the path starts at segment 0
  /// parameter 0, one past the end at the last segment parameter 1. Total —
  /// never NaN, never out of range.
  (int segment, double t) locate(double arc) {
    if (_segmentCount == 0) return (0, 0.0);
    if (arc <= 0.0) return (0, 0.0);
    if (arc >= total) return (_segmentCount - 1, 1.0);
    for (var k = 0; k < _segmentCount; k++) {
      final seg = _segments[k];
      if (arc <= seg.last.arc) {
        for (var i = 1; i < seg.length; i++) {
          if (seg[i].arc >= arc) {
            final span = seg[i].arc - seg[i - 1].arc;
            final f = span <= 0.0 ? 0.0 : (arc - seg[i - 1].arc) / span;
            return (k, seg[i - 1].t + (seg[i].t - seg[i - 1].t) * f);
          }
        }
        return (k, 1.0);
      }
    }
    return (_segmentCount - 1, 1.0);
  }
}
