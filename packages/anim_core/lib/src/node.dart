/// The scene graph (docs/v3/01 §3).
library;

import 'affine.dart';
import 'json.dart';
import 'paint.dart';
import 'path.dart';
import 'primitives.dart';

sealed class Node {
  const Node({
    required this.id,
    required this.name,
    this.transform = Transform2.identity,
    this.opacity = 1.0,
    this.visible = true,
    this.locked = false,
    this.unknownKeys = const {},
  });

  final NodeId id;
  final String name;

  /// The **pose**. Tracks override it per-property at sample time.
  final Transform2 transform;

  /// 0..1. Multiplies down the tree.
  final double opacity;

  /// Authored. ANDs down the tree — a hidden group hides every descendant
  /// regardless of that descendant's own tracks.
  final bool visible;

  /// **Editor only.** Persisted, because it must survive reload (unlike
  /// selection and hover, which are ephemeral), but the evaluator never reads
  /// it at any depth. It is a hit-test gate and nothing else.
  final bool locked;

  /// Forward-compat passthrough (docs/v3/02 §7).
  final Map<String, Object?> unknownKeys;

  /// Keys every node claims. A subtype adds its own before computing
  /// [unknownKeys], so `children` never lands in a group's passthrough map.
  static const commonKeys = <String>{
    'type',
    'id',
    'name',
    'transform',
    'opacity',
    'visible',
    'locked',
  };

  Map<String, Object?> toJson();

  /// Discriminated by an **open** `type` string. An unrecognised value is not
  /// an error — it becomes an [UnknownNode] and survives the round trip.
  factory Node.fromJson(Object? j) {
    final m = j! as Map<String, Object?>;
    final type = m['type'] as String;
    return switch (type) {
      'group' => GroupNode.fromJson(m),
      'path' => PathNode.fromJson(m),
      _ => UnknownNode.fromJson(m),
    };
  }

  static Map<String, Object?> _common(Map<String, Object?> m) =>
      <String, Object?>{
        'id': m['id'] as String,
        'name': opt(m, 'name', (v) => v as String, ''),
        'transform':
            opt(m, 'transform', Transform2.fromJson, Transform2.identity),
        'opacity': opt(m, 'opacity', d, 1.0),
        'visible': opt(m, 'visible', (v) => v as bool, true),
        'locked': opt(m, 'locked', (v) => v as bool, false),
      };

  Map<String, Object?> _commonJson(String type) => <String, Object?>{
        'type': type,
        'id': id.v,
        'name': name,
        'transform': transform.toJson(),
        'opacity': opacity,
        'visible': visible,
        'locked': locked,
      };
}

/// Container — and the artboard root.
final class GroupNode extends Node {
  const GroupNode({
    required super.id,
    required super.name,
    this.children = const [],
    this.clipChildren = false,
    super.transform,
    super.opacity,
    super.visible,
    super.locked,
    super.unknownKeys,
  });

  /// **Z-order IS this list.** Index 0 paints first, so it is back-most; the
  /// layers panel displays it reversed.
  ///
  /// There is deliberately no `zIndex` field, so there is nothing to desync —
  /// a derived sorted array sitting beside an unsorted authoritative one was
  /// legacy's worst latent defect. Reordering is a list splice.
  final List<Node> children;

  final bool clipChildren;

  static const _own = {'children', 'clipChildren'};

  factory GroupNode.fromJson(Map<String, Object?> m) {
    final c = Node._common(m);
    return GroupNode(
      id: NodeId(c['id']! as String),
      name: c['name']! as String,
      transform: c['transform']! as Transform2,
      opacity: c['opacity']! as double,
      visible: c['visible']! as bool,
      locked: c['locked']! as bool,
      children: opt(
        m,
        'children',
        (v) => (v! as List<Object?>).map(Node.fromJson).toList(growable: false),
        const <Node>[],
      ),
      clipChildren: opt(m, 'clipChildren', (v) => v as bool, false),
      unknownKeys: unknownKeysOf(m, {...Node.commonKeys, ..._own}),
    );
  }

  @override
  Map<String, Object?> toJson() => withUnknown(unknownKeys, {
        ..._commonJson('group'),
        'children': children.map((c) => c.toJson()).toList(growable: false),
        'clipChildren': clipChildren,
      });

  GroupNode copyWith({
    String? name,
    List<Node>? children,
    bool? clipChildren,
    Transform2? transform,
    double? opacity,
    bool? visible,
    bool? locked,
  }) =>
      GroupNode(
        id: id,
        name: name ?? this.name,
        children: children ?? this.children,
        clipChildren: clipChildren ?? this.clipChildren,
        transform: transform ?? this.transform,
        opacity: opacity ?? this.opacity,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        unknownKeys: unknownKeys,
      );
}

/// The only leaf in v1.
final class PathNode extends Node {
  const PathNode({
    required super.id,
    required super.name,
    required this.path,
    this.fills = const [],
    this.strokes = const [],
    this.trim = PathTrim.full,
    super.transform,
    super.opacity,
    super.visible,
    super.locked,
    super.unknownKeys,
  });

  /// **Authoritative** topology and rest pose. Keyframes pose these anchors by
  /// id; they never restate which anchors exist.
  final PathData path;

  /// Painted in list order, first is bottom. The v1 UI exposes 0 or 1 of each,
  /// but they are lists from day one so multi-paint is additive.
  final List<Fill> fills;

  /// Painted after all fills.
  final List<Stroke> strokes;

  final PathTrim trim;

  /// `recipe` is deliberately **not** claimed here.
  ///
  /// `ShapeRecipe` is inert re-edit metadata that arrives with the shape tools
  /// (M3). Leaving the key unclaimed routes it through [unknownKeys], so a
  /// rectangle authored by a later build stays re-editable instead of being
  /// flattened into anonymous anchors by this one.
  static const _own = {'path', 'fills', 'strokes', 'trim'};

  factory PathNode.fromJson(Map<String, Object?> m) {
    final c = Node._common(m);
    return PathNode(
      id: NodeId(c['id']! as String),
      name: c['name']! as String,
      transform: c['transform']! as Transform2,
      opacity: c['opacity']! as double,
      visible: c['visible']! as bool,
      locked: c['locked']! as bool,
      path: PathData.fromJson(m['path']),
      fills: opt(
        m,
        'fills',
        (v) => (v! as List<Object?>).map(Fill.fromJson).toList(growable: false),
        const <Fill>[],
      ),
      strokes: opt(
        m,
        'strokes',
        (v) =>
            (v! as List<Object?>).map(Stroke.fromJson).toList(growable: false),
        const <Stroke>[],
      ),
      trim: opt(m, 'trim', PathTrim.fromJson, PathTrim.full),
      unknownKeys: unknownKeysOf(m, {...Node.commonKeys, ..._own}),
    );
  }

  @override
  Map<String, Object?> toJson() => withUnknown(unknownKeys, {
        ..._commonJson('path'),
        'path': path.toJson(),
        'fills': fills.map((f) => f.toJson()).toList(growable: false),
        'strokes': strokes.map((s) => s.toJson()).toList(growable: false),
        // Omitted when full, per docs/v3/02 §3.6 — the common case writes no
        // trim key at all.
        if (!trim.isFull) 'trim': trim.toJson(),
      });

  PathNode copyWith({
    String? name,
    PathData? path,
    List<Fill>? fills,
    List<Stroke>? strokes,
    PathTrim? trim,
    Transform2? transform,
    double? opacity,
    bool? visible,
    bool? locked,
  }) =>
      PathNode(
        id: id,
        name: name ?? this.name,
        path: path ?? this.path,
        fills: fills ?? this.fills,
        strokes: strokes ?? this.strokes,
        trim: trim ?? this.trim,
        transform: transform ?? this.transform,
        opacity: opacity ?? this.opacity,
        visible: visible ?? this.visible,
        locked: locked ?? this.locked,
        unknownKeys: unknownKeys,
      );
}

/// Forward compatibility, **not a feature**.
///
/// A decoder meeting an unrecognised node `type` keeps the raw JSON and
/// re-emits it verbatim on save. Renders nothing, unselectable, not
/// hit-testable. Without it, a v1 client opening a v2 document (bones,
/// instancing) from Firestore silently destroys it on the next autosave — and
/// autosave means the user never even sees it happen.
final class UnknownNode extends Node {
  const UnknownNode({
    required super.id,
    required super.name,
    required this.rawType,
    required this.raw,
  });

  final String rawType;
  final Map<String, Object?> raw;

  factory UnknownNode.fromJson(Map<String, Object?> m) => UnknownNode(
        id: NodeId(m['id']! as String),
        name: opt(m, 'name', (v) => v as String, ''),
        rawType: m['type']! as String,
        raw: Map.unmodifiable(m),
      );

  /// Verbatim. Not `_commonJson` — re-encoding through the typed fields would
  /// normalise an absent `opacity` into an explicit `1.0`, which is exactly the
  /// silent rewrite this class exists to prevent.
  @override
  Map<String, Object?> toJson() => Map<String, Object?>.from(raw);
}
