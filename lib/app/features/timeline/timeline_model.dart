/// The timeline's read-only projection of the document (docs/v3/08 §2).
///
/// **A value type, deeply equatable, and that is the whole point.** The timeline
/// reads the document through `timelineModelProvider`, whose `.select` compares
/// this projection to the previous one with `==`. A node move that changes a
/// `Transform2` but no key list produces a `TimelineModel` that compares
/// **equal**, so the timeline does not rebuild for it — the "named slice" that
/// stops an anchor commit from rebuilding layers + inspector + timeline
/// (docs/v3/08 §2). Identity equality would defeat that on every rebuild, so
/// every class here overrides `==`/`hashCode` and compares its lists by value.
///
/// It is also **derived, never stored**: nothing here is serialized, and no
/// widget mutates it — `build`/`itemBuilder` reading this model performs pure
/// reads (AC-6.2.5). The unit is the model's normalized `t`; pixels appear only
/// in the widgets that paint it (AC-9.1.4).
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart';

/// One key on a property row: its normalized time and the easing that governs
/// the segment **leaving** it (docs/v3/01 §8). The easing is carried so the row
/// can show each segment's curve without re-reading the document.
@immutable
class TimelineKeyModel {
  const TimelineKeyModel(this.t, this.easing);

  final double t;
  final Easing easing;

  @override
  bool operator ==(Object other) =>
      other is TimelineKeyModel && other.t == t && other.easing == easing;

  @override
  int get hashCode => Object.hash(t, easing);
}

/// One expanded property row: every key of `(node, property)`, in order.
@immutable
class TimelinePropertyRow {
  const TimelinePropertyRow(this.node, this.property, this.keys);

  final NodeId node;
  final PropertyKey property;
  final List<TimelineKeyModel> keys;

  /// The dot positions, as a pure read off [keys].
  List<double> get times => <double>[for (final k in keys) k.t];

  @override
  bool operator ==(Object other) =>
      other is TimelinePropertyRow &&
      other.node == node &&
      other.property == property &&
      listEquals(other.keys, keys);

  @override
  int get hashCode => Object.hash(node, property, Object.hashAll(keys));
}

/// One node with at least one track: a collapsed summary (the **union** of its
/// keys, read-only, docs/v3/05 §2) plus one expandable row per `PropertyKey`.
@immutable
class TimelineNodeModel {
  const TimelineNodeModel(this.node, this.name, this.summary, this.rows);

  final NodeId node;
  final String name;

  /// The union of every property row's key times, sorted — the collapsed row.
  /// There is **no shared grid**: this union is per node and never aligns
  /// columns across nodes (AC-6.1.1, AC-6.1.5).
  final List<double> summary;

  final List<TimelinePropertyRow> rows;

  @override
  bool operator ==(Object other) =>
      other is TimelineNodeModel &&
      other.node == node &&
      other.name == name &&
      listEquals(other.summary, summary) &&
      listEquals(other.rows, rows);

  @override
  int get hashCode =>
      Object.hash(node, name, Object.hashAll(summary), Object.hashAll(rows));
}

/// The timeline's whole row model: every node that has a track, in document
/// order. Nodes with no track are omitted — a fully static node has nothing to
/// key against and no row to draw (AC-6.1.4); the choice is documented here so
/// "why is my untracked shape not in the timeline" has an answer.
@immutable
class TimelineModel {
  const TimelineModel(this.nodes);

  final List<TimelineNodeModel> nodes;

  static const TimelineModel empty = TimelineModel(<TimelineNodeModel>[]);

  @override
  bool operator ==(Object other) =>
      other is TimelineModel && listEquals(other.nodes, nodes);

  @override
  int get hashCode => Object.hashAll(nodes);
}
