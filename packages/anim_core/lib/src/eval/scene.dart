/// The evaluator's input and output types (docs/v3/01 §11).
///
/// Everything here is **derived**: a [Scene] is rebuilt from a [Document] and a
/// playhead on demand and is never stored on the document, never serialized and
/// never edited. Legacy persisted its derived render list next to the
/// authoritative one and spent its life resyncing them.
library;

import '../affine.dart';
import '../paint.dart';
import '../path.dart';
import '../primitives.dart';

/// A weighted sample of one animation.
///
/// v1 always passes exactly one entry at weight 1.0. Deciding this signature
/// now is the difference between the state machine being additive and being a
/// signature break through every call site.
final class AnimationMix {
  const AnimationMix(this.animation, this.t, {this.weight = 1.0});

  final AnimationId animation;

  /// Normalized position **within that animation**, 0..1.
  final double t;

  /// Contribution weight. Deliberately **not** renormalized across the list —
  /// see the blend contract in `evaluate.dart`.
  final double weight;

  @override
  String toString() => 'AnimationMix(${animation.v} @ $t ×$weight)';
}

/// Identity of a node **in the evaluated scene**.
///
/// [instancePath] is `const []` in v1 and there is nothing to instance yet. It
/// exists because keying anything by [NodeId] instead of by a path makes two
/// instances of the same subtree collide *silently* — same selection, same
/// hit-test result, same gizmo — and the fix at that point is a refactor
/// through hit-testing, selection, the layers panel and the transform gizmo.
/// Introducing it now is a rename; introducing it later is that refactor.
///
/// Ephemeral. Never serialized.
final class ScenePath {
  const ScenePath(this.nodeId, {this.instancePath = const []});

  final NodeId nodeId;

  /// Outermost instance first. Empty for a node reached directly through the
  /// document tree, which is every node in v1.
  final List<NodeId> instancePath;

  /// Value equality is load-bearing: this type is a `Map` key in [Scene] and a
  /// `Set` member in the editor's selection, and identity equality would make
  /// both silently miss on every rebuild.
  @override
  bool operator ==(Object other) {
    if (other is! ScenePath) return false;
    if (other.nodeId != nodeId) return false;
    if (other.instancePath.length != instancePath.length) return false;
    for (var n = 0; n < instancePath.length; n++) {
      if (other.instancePath[n] != instancePath[n]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(nodeId, Object.hashAll(instancePath));

  @override
  String toString() => instancePath.isEmpty
      ? 'ScenePath(${nodeId.v})'
      : 'ScenePath(${instancePath.map((i) => i.v).join('/')}/${nodeId.v})';
}

/// One node, fully evaluated at one instant.
final class ResolvedNode {
  const ResolvedNode({
    required this.path,
    required this.world,
    required this.worldOpacity,
    required this.worldVisible,
    this.geometry,
    this.fills = const [],
    this.strokes = const [],
  });

  final ScenePath path;

  /// Document space ← node local space. Already composed with every ancestor.
  final Affine world;

  /// The node's own opacity multiplied by every ancestor's.
  final double worldOpacity;

  /// The node's own `visible` ANDed with every ancestor's. Also false when
  /// [world] is singular, because a collapsed matrix renders nothing.
  ///
  /// `locked` is **not** a factor at any depth: it is a hit-test gate, not a
  /// render gate.
  final bool worldVisible;

  /// Posed and trimmed geometry in the node's **local** space. Null for a group
  /// and for a node type this build does not understand.
  ///
  /// WARNING: after the trim stage the `AnchorId`s here are **synthetic and
  /// non-authoritative**. No downstream stage, exporter, or future skinning
  /// pass may join by them.
  final PathData? geometry;

  final List<Fill> fills;
  final List<Stroke> strokes;

  ResolvedNode copyWith({
    Affine? world,
    double? worldOpacity,
    bool? worldVisible,
    PathData? geometry,
    List<Fill>? fills,
    List<Stroke>? strokes,
  }) =>
      ResolvedNode(
        path: path,
        world: world ?? this.world,
        worldOpacity: worldOpacity ?? this.worldOpacity,
        worldVisible: worldVisible ?? this.worldVisible,
        geometry: geometry ?? this.geometry,
        fills: fills ?? this.fills,
        strokes: strokes ?? this.strokes,
      );

  @override
  String toString() => 'ResolvedNode($path, visible: $worldVisible)';
}

/// The evaluator's whole output. The [Document] it came from is unmodified —
/// evaluation is a pure read (AC-9.2.6).
final class Scene {
  const Scene(this.drawOrder, this.byPath);

  /// Flattened, **back-to-front**. Groups appear too, with null geometry, so
  /// the order is a faithful pre-order flattening and a painter needs no second
  /// structure to walk clips with later.
  final List<ResolvedNode> drawOrder;

  /// Keyed by [ScenePath], **not** by [NodeId] — see [ScenePath].
  final Map<ScenePath, ResolvedNode> byPath;

  static const empty = Scene(<ResolvedNode>[], <ScenePath, ResolvedNode>{});

  @override
  String toString() => 'Scene(${drawOrder.length} nodes)';
}
