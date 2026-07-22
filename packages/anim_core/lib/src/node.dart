/// The scene graph (docs/v3/01 §3).
library;

import 'affine.dart';
import 'decode.dart';
import 'json.dart';
import 'paint.dart';
import 'path.dart';
import 'primitives.dart';
import 'recipe.dart';

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

  /// Discriminated by an **open** `type` string. An unrecognised *value* is not
  /// an error — it becomes an [UnknownNode] and survives the round trip.
  ///
  /// An **absent** `type`, by contrast, throws with [path]: there is no
  /// discriminator to preserve, so [UnknownNode] has nothing to re-emit under
  /// and the node would be silently invented. That is the boundary on
  /// [DocumentException], one level down from the root.
  factory Node.fromJson(Object? j, [String path = '']) {
    final m = reqObject(j, path);
    return switch (reqString(m['type'], jsonChild(path, 'type'))) {
      'group' => GroupNode.fromJson(m, path),
      'path' => PathNode.fromJson(m, path),
      _ => UnknownNode.fromJson(m, path),
    };
  }

  static Map<String, Object?> _common(Map<String, Object?> m, String path) =>
      <String, Object?>{
        'id': reqString(m['id'], jsonChild(path, 'id')),
        'name':
            opt(m, 'name', (v) => reqString(v, jsonChild(path, 'name')), ''),
        'transform': opt(
            m,
            'transform',
            (v) => Transform2.fromJson(v, jsonChild(path, 'transform')),
            Transform2.identity),
        'opacity': opt(
            m, 'opacity', (v) => reqDouble(v, jsonChild(path, 'opacity')), 1.0),
        'visible': opt(
            m, 'visible', (v) => reqBool(v, jsonChild(path, 'visible')), true),
        'locked': opt(
            m, 'locked', (v) => reqBool(v, jsonChild(path, 'locked')), false),
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

  factory GroupNode.fromJson(Map<String, Object?> m, [String path = '']) {
    final c = Node._common(m, path);
    final children = opt(
      m,
      'children',
      (v) => reqArray(v, jsonChild(path, 'children')),
      const <Object?>[],
    );
    return GroupNode(
      id: NodeId(c['id']! as String),
      name: c['name']! as String,
      transform: c['transform']! as Transform2,
      opacity: d(c['opacity']),
      visible: c['visible']! as bool,
      locked: c['locked']! as bool,
      children: <Node>[
        for (var k = 0; k < children.length; k++)
          Node.fromJson(children[k], jsonIndex(jsonChild(path, 'children'), k)),
      ],
      clipChildren: opt(m, 'clipChildren',
          (v) => reqBool(v, jsonChild(path, 'clipChildren')), false),
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
    this.recipe,
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

  /// **Inert** re-edit metadata — how a shape tool generated [path]. Never
  /// animated, never read by the evaluator or the renderer; see `recipe.dart`
  /// for the three rules and for why the tools that mint one are M3.
  ///
  /// Null is the normal state: everything the pen tool draws has no recipe, and
  /// `PathOps.moveAnchor` nulls it the moment an anchor is edited by hand
  /// (docs/v3/01 §5's authority rule).
  final ShapeRecipe? recipe;

  final PathTrim trim;

  static const _own = {'path', 'fills', 'strokes', 'recipe', 'trim'};

  factory PathNode.fromJson(Map<String, Object?> m, [String path = '']) {
    final c = Node._common(m, path);
    final fills = opt(
      m,
      'fills',
      (v) => reqArray(v, jsonChild(path, 'fills')),
      const <Object?>[],
    );
    final strokes = opt(
      m,
      'strokes',
      (v) => reqArray(v, jsonChild(path, 'strokes')),
      const <Object?>[],
    );
    return PathNode(
      id: NodeId(c['id']! as String),
      name: c['name']! as String,
      transform: c['transform']! as Transform2,
      opacity: d(c['opacity']),
      visible: c['visible']! as bool,
      locked: c['locked']! as bool,
      // Required: a path node without geometry is not a degraded path node,
      // it is a node with nothing to draw and nothing to key against.
      path: PathData.fromJson(m['path'], jsonChild(path, 'path')),
      fills: <Fill>[
        for (var k = 0; k < fills.length; k++)
          Fill.fromJson(fills[k], jsonIndex(jsonChild(path, 'fills'), k)),
      ],
      strokes: <Stroke>[
        for (var k = 0; k < strokes.length; k++)
          Stroke.fromJson(strokes[k], jsonIndex(jsonChild(path, 'strokes'), k)),
      ],
      // `"recipe": null` is the encoder's own output for a node without one,
      // so an explicit null must mean absent rather than "present and
      // unreadable" (docs/v3/02 §1 rule 5).
      recipe: opt<ShapeRecipe?>(
          m, 'recipe', (v) => v == null ? null : ShapeRecipe.fromJson(v), null),
      trim: opt(m, 'trim', (v) => PathTrim.fromJson(v, jsonChild(path, 'trim')),
          PathTrim.full),
      unknownKeys: unknownKeysOf(m, {...Node.commonKeys, ..._own}),
    );
  }

  @override
  Map<String, Object?> toJson() => withUnknown(unknownKeys, {
        ..._commonJson('path'),
        'path': path.toJson(),
        'fills': fills.map((f) => f.toJson()).toList(growable: false),
        'strokes': strokes.map((s) => s.toJson()).toList(growable: false),
        // Omitted when absent rather than written as an explicit null: the
        // no-recipe case is every path the pen tool has ever drawn, and a null
        // in every node is noise in a format people hand-inspect.
        if (recipe != null) 'recipe': recipe!.toJson(),
        // Omitted when full, per docs/v3/02 §3.6 — the common case writes no
        // trim key at all.
        if (!trim.isFull) 'trim': trim.toJson(),
      });

  /// [clearRecipe] exists because `recipe: null` cannot mean "null it" in a
  /// `copyWith` — a null argument is indistinguishable from an omitted one, and
  /// the authority rule (docs/v3/01 §5) needs a way to say *nulled*, not
  /// *unchanged*. Silently keeping a stale recipe through an anchor edit is
  /// precisely the wrong-shape bug that rule prevents.
  PathNode copyWith({
    String? name,
    PathData? path,
    List<Fill>? fills,
    List<Stroke>? strokes,
    ShapeRecipe? recipe,
    bool clearRecipe = false,
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
        recipe: clearRecipe ? null : (recipe ?? this.recipe),
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

  factory UnknownNode.fromJson(Map<String, Object?> m, [String path = '']) =>
      UnknownNode(
        id: NodeId(reqString(m['id'], jsonChild(path, 'id'))),
        name: opt(m, 'name', (v) => reqString(v, jsonChild(path, 'name')), ''),
        rawType: reqString(m['type'], jsonChild(path, 'type')),
        raw: Map.unmodifiable(m),
      );

  /// Verbatim. Not `_commonJson` — re-encoding through the typed fields would
  /// normalise an absent `opacity` into an explicit `1.0`, which is exactly the
  /// silent rewrite this class exists to prevent.
  @override
  Map<String, Object?> toJson() => Map<String, Object?>.from(raw);
}
