/// The inspector feature's named slices (docs/v3/08 §2).
///
/// The inspector owns numeric/typed editing of the selected node's values
/// (docs/v3/05 §2). It reads the document through **one value-projected slice**
/// keyed by the selected node, so editing an anchor on some *other* node — or
/// scrubbing the playhead — rebuilds nothing here (AC-13.3). Selection is the
/// same `EditorState.selectedNodes` set the canvas and the layers panel read.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';

/// The selected nodes as `NodeId`s — the same shared editor slice the canvas and
/// layers panel read, projected off `ScenePath` (`instancePath` is `const []` in
/// v1). Watching `s.selectedNodes` alone keeps a viewport pan or a scrub from
/// rebuilding the inspector.
final inspectorSelectionProvider = Provider.autoDispose<Set<NodeId>>((ref) {
  final paths =
      ref.watch(editorControllerProvider.select((s) => s.selectedNodes));
  return <NodeId>{for (final p in paths) p.nodeId};
});

/// Just the one selected node's `Transform2` (plus its name and kind), by value.
///
/// A value type so the `.select` below dedups: `Transform2` compares by value,
/// so an edit elsewhere that leaves this node's transform alone yields an equal
/// view and no rebuild.
@immutable
final class NodeTransformView {
  const NodeTransformView({
    required this.id,
    required this.name,
    required this.transform,
    required this.opacity,
    required this.isUnknown,
  });

  final NodeId id;
  final String name;
  final Transform2 transform;

  /// The node's **own authored** `opacity`, never a product with its ancestors'.
  ///
  /// `worldOpacity` is a PRODUCT down the chain (AC-2.2.5) and it is the
  /// evaluator's, recomputed per frame. Projecting an "effective" opacity here
  /// would store a derived value beside the authored one — the exact desync
  /// docs/v3/08 §4 forbids — and it would also be uneditable: there is no
  /// inverse for "0.25 effective" that does not silently rewrite an ancestor.
  final double opacity;

  /// An `UnknownNode` re-emits raw JSON verbatim, so a typed transform written to
  /// it would be dropped on save (`NodeOps.setTransform` refuses one). The panel
  /// shows it read-only rather than offering fields that silently do nothing.
  final bool isUnknown;

  @override
  bool operator ==(Object other) =>
      other is NodeTransformView &&
      other.id == id &&
      other.name == name &&
      other.transform == transform &&
      other.opacity == opacity &&
      other.isUnknown == isUnknown;

  @override
  int get hashCode => Object.hash(id, name, transform, opacity, isUnknown);
}

/// What the inspector should show: exactly one node's transform, or a calm
/// summary of a 0-or-many selection.
@immutable
final class InspectorTarget {
  const InspectorTarget._(this.node, this.selectionCount);

  /// Show one node's editable transform.
  const InspectorTarget.node(NodeTransformView view) : this._(view, 1);

  /// Show the empty/summary state for [count] selected nodes (0 or >1).
  const InspectorTarget.summary(int count) : this._(null, count);

  /// Non-null exactly when [selectionCount] is 1 and the node resolves.
  final NodeTransformView? node;
  final int selectionCount;

  @override
  bool operator ==(Object other) =>
      other is InspectorTarget &&
      other.node == node &&
      other.selectionCount == selectionCount;

  @override
  int get hashCode => Object.hash(node, selectionCount);
}

/// The inspector's single read. Exactly one selected node → its transform view;
/// otherwise a summary. A dangling selection path (its node was deleted) is
/// resolved, never repaired: it simply resolves to null here and shows the
/// summary state, never a crash (docs/v3/08 §2).
final inspectorTargetProvider =
    Provider.autoDispose.family<InspectorTarget, String>((ref, projectId) {
  final ids = ref.watch(inspectorSelectionProvider);
  if (ids.length != 1) return InspectorTarget.summary(ids.length);

  final id = ids.single;
  final view = ref.watch(documentControllerProvider(projectId).select((async) {
    final node = async.valueOrNull?.nodeIndex[id];
    if (node == null) return null;
    return NodeTransformView(
      id: id,
      name: node.name,
      transform: node.transform,
      opacity: node.opacity,
      isUnknown: node is UnknownNode,
    );
  }));

  return view == null
      ? const InspectorTarget.summary(1)
      : InspectorTarget.node(view);
});
