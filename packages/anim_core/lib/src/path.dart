/// Path geometry (docs/v3/01 §5).
library;

import 'json.dart';
import 'primitives.dart';

/// Authoring hint **only**. The renderer and the evaluator never read it — they
/// read `inTangent`/`outTangent` verbatim.
///
/// That is what keeps the evaluator total and makes `kind` safe to change
/// without re-tweening: flipping an anchor from corner to smooth is a UI
/// affordance, not a geometry change.
enum AnchorKind { corner, smooth, symmetric }

final class Anchor {
  const Anchor({
    required this.id,
    required this.position,
    this.inTangent = Vec2.zero,
    this.outTangent = Vec2.zero,
    this.kind = AnchorKind.corner,
  });

  /// **Stable.** Survives moves, reorders, keyframes and undo.
  ///
  /// Every keyframe joins to this id rather than to a list position. Legacy
  /// tweened by array index, so adding one point mis-paired every vertex after
  /// it — the defect this whole rewrite exists to remove.
  final AnchorId id;

  final Vec2 position;

  /// **Relative to [position]** (Lottie `i`/`o` convention), so tangents move
  /// with the anchor instead of needing a fix-up pass after every drag.
  final Vec2 inTangent;
  final Vec2 outTangent;

  final AnchorKind kind;

  Anchor copyWith({
    Vec2? position,
    Vec2? inTangent,
    Vec2? outTangent,
    AnchorKind? kind,
  }) =>
      Anchor(
        id: id,
        position: position ?? this.position,
        inTangent: inTangent ?? this.inTangent,
        outTangent: outTangent ?? this.outTangent,
        kind: kind ?? this.kind,
      );

  factory Anchor.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return Anchor(
      id: AnchorId(m['id']! as String),
      position: Vec2.fromJson(m['position']),
      inTangent: opt(m, 'inTangent', Vec2.fromJson, Vec2.zero),
      outTangent: opt(m, 'outTangent', Vec2.fromJson, Vec2.zero),
      // An unrecognised kind falls back to `corner` rather than throwing: it is
      // an authoring hint, so being wrong about it costs a UI affordance, while
      // throwing would cost the whole document.
      kind: opt(
        m,
        'kind',
        (v) => AnchorKind.values.asNameMap()[v] ?? AnchorKind.corner,
        AnchorKind.corner,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.v,
        'position': position.toJson(),
        'inTangent': inTangent.toJson(),
        'outTangent': outTangent.toJson(),
        'kind': kind.name,
      };

  @override
  bool operator ==(Object other) =>
      other is Anchor &&
      other.id == id &&
      other.position == position &&
      other.inTangent == inTangent &&
      other.outTangent == outTangent &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, position, inTangent, outTangent, kind);

  @override
  String toString() => 'Anchor(${id.v} @ $position)';
}

/// Topology **and** rest pose. Lives on the node, constant over time.
///
/// Which anchors exist is a property of the *shape*; keyframes vary only where
/// those anchors sit. That split is why a mismatched anchor set is not a
/// representable state in v3 (docs/v3/01 §1).
final class PathData {
  const PathData._(this.anchors, this.closed);

  /// **Draw order**, and load-bearing: the anchor *sequence* is the topology,
  /// which is what an insert operation splices into.
  final List<Anchor> anchors;

  /// Lives **only** here. Not per-keyframe, and it cannot vary over time.
  final bool closed;

  static const empty = PathData._(<Anchor>[], false);

  /// The only public constructor.
  ///
  /// Const construction is private specifically so the uniqueness invariant
  /// cannot be bypassed — legacy's public const constructors enforced nothing,
  /// and an id collision here silently animates one anchor with another's pose.
  factory PathData({required List<Anchor> anchors, bool closed = false}) {
    final seen = <String>{};
    for (final a in anchors) {
      if (!seen.add(a.id.v)) {
        throw ArgumentError('duplicate AnchorId ${a.id.v}');
      }
    }
    return PathData._(List.unmodifiable(anchors), closed);
  }

  /// Zero for a degenerate path. 0 or 1 anchor renders nothing and never
  /// throws — the pen tool produces exactly that on its first click.
  int get segmentCount =>
      anchors.length < 2 ? 0 : (closed ? anchors.length : anchors.length - 1);

  bool get isEmpty => anchors.length < 2;

  /// The cubic control points of segment [k], as `(p0, p1, p2, p3)`.
  ///
  /// There is one segment type. A `corner` anchor simply has zero tangents,
  /// which makes a straight line the degenerate cubic — so the renderer has no
  /// polyline/curve branch to get wrong.
  (Vec2, Vec2, Vec2, Vec2) segment(int k) {
    final a = anchors[k];
    final b = anchors[(k + 1) % anchors.length];
    return (
      a.position,
      a.position + a.outTangent,
      b.position + b.inTangent,
      b.position
    );
  }

  factory PathData.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return PathData(
      anchors: opt(
        m,
        'anchors',
        (v) =>
            (v! as List<Object?>).map(Anchor.fromJson).toList(growable: false),
        const <Anchor>[],
      ),
      closed: opt(m, 'closed', (v) => v as bool, false),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'closed': closed,
        'anchors': anchors.map((a) => a.toJson()).toList(growable: false),
      };

  @override
  String toString() => 'PathData(${anchors.length} anchors, closed: $closed)';
}

/// Draw-on / reveal, as fractions of **total arc length**.
final class PathTrim {
  const PathTrim({this.start = 0.0, this.end = 1.0, this.offset = 0.0});

  final double start;
  final double end;

  /// Required rather than optional: without it a closed path cannot begin its
  /// reveal anywhere but anchor 0.
  final double offset;

  static const full = PathTrim();

  bool get isFull => start == 0.0 && end == 1.0 && offset == 0.0;

  /// `end <= start` renders nothing — empty geometry, never a throw. Wrapped
  /// windows (`start > end`) are a written non-goal and clamp to empty.
  bool get rendersNothing => end <= start;

  factory PathTrim.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    return PathTrim(
      start: opt(m, 'start', d, 0.0),
      end: opt(m, 'end', d, 1.0),
      offset: opt(m, 'offset', d, 0.0),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'start': start,
        'end': end,
        'offset': offset,
      };

  @override
  bool operator ==(Object other) =>
      other is PathTrim &&
      other.start == start &&
      other.end == end &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(start, end, offset);

  @override
  String toString() => 'PathTrim($start..$end, offset $offset)';
}
