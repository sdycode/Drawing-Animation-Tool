/// The layers feature's named slices (docs/v3/08 §2).
///
/// The layers panel owns the tree, z-order, rename, visibility and lock — and it
/// reads the document through **exactly these projections**, never
/// `documentControllerProvider` whole. That is the direct antidote to legacy's
/// 93 blind `updateUI()` sites: moving an anchor changes geometry, not the tree
/// shape or any flag, so [layersViewProvider] returns a value-equal [LayersView]
/// and this panel does not rebuild (AC-13.3). Selection is the *same* editor
/// slice the canvas reads (both directions), projected to `NodeId` here.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';

/// One row of the tree, flattened for display but carrying the structural facts
/// a command needs: its parent and its authoritative child index.
///
/// **Value type on purpose.** [LayersView] compares by value, and that is what
/// makes an anchor drag — which mints a whole new `Document` but changes no
/// name, flag or order — project to an *equal* view and rebuild nothing. It
/// deliberately holds no geometry: geometry is what changes every frame of a
/// drag, and none of it belongs in the tree.
@immutable
final class LayerRow {
  const LayerRow({
    required this.id,
    required this.parent,
    required this.name,
    required this.depth,
    required this.childIndex,
    required this.siblingCount,
    required this.visible,
    required this.locked,
    required this.lockedSelf,
    required this.isGroup,
    required this.isUnknown,
  });

  final NodeId id;

  /// The group that holds this row as a direct child — `root` for a top-level
  /// row. This is the `parent` a [ReorderChildCommand] splices within and the
  /// `newParent` a [ReparentCommand] moves into.
  final NodeId parent;

  final String name;

  /// 0 for a direct child of the root; one deeper per group nesting. Drives the
  /// indent only — it is not stored anywhere and never persisted.
  final int depth;

  /// Index in the parent's authoritative `children` list (back-to-front). The
  /// display order is this reversed, but the *command* addresses this index.
  final int childIndex;
  final int siblingCount;

  final bool visible;

  /// **Effective** lock — this node's own flag OR any ancestor's.
  ///
  /// Lock inherits down the tree, exactly as the canvas hit-test gate does
  /// (`_CanvasViewState._lockedIds`). Reading only the row's own flag here was a
  /// bypass around AC-2.2.6: with a group locked, the canvas refused to select
  /// its children while the panel happily selected them and handed the inspector
  /// an editable transform form. One rule, two surfaces.
  final bool locked;

  /// The **authored** flag, which is what the lock toggle writes. Kept beside
  /// [locked] because a row locked only by an ancestor must not offer a toggle
  /// that would write a flag it already holds and change nothing on screen.
  final bool lockedSelf;

  final bool isGroup;
  final bool isUnknown;

  /// True when an ancestor group holds the lock. The row is protected, but
  /// unlocking it means unlocking that ancestor.
  bool get lockedByAncestor => locked && !lockedSelf;

  @override
  bool operator ==(Object other) =>
      other is LayerRow &&
      other.id == id &&
      other.parent == parent &&
      other.name == name &&
      other.depth == depth &&
      other.childIndex == childIndex &&
      other.siblingCount == siblingCount &&
      other.visible == visible &&
      other.locked == locked &&
      other.lockedSelf == lockedSelf &&
      other.isGroup == isGroup &&
      other.isUnknown == isUnknown;

  @override
  int get hashCode => Object.hash(id, parent, name, depth, childIndex,
      siblingCount, visible, locked, lockedSelf, isGroup, isUnknown);
}

/// The whole tree, flattened **front-most first** (AC-2.2.1) and comparable by
/// value.
@immutable
final class LayersView {
  const LayersView(this.rows);

  static const empty = LayersView(<LayerRow>[]);

  /// Display order: top of the list is the front-most node. Children paint
  /// back-to-front by index (docs/v3/01 §3), so each level is walked in reverse.
  final List<LayerRow> rows;

  /// Flatten [root]'s descendants (the root itself is the artboard container and
  /// is never shown as a layer).
  factory LayersView.of(GroupNode root) {
    final rows = <LayerRow>[];
    // `inherited` carries the lock down the tree the way the canvas does — a
    // locked group protects its children in both surfaces or in neither.
    void walk(GroupNode g, int depth, bool inherited) {
      final kids = g.children;
      for (var i = kids.length - 1; i >= 0; i--) {
        final c = kids[i];
        final locked = inherited || c.locked;
        rows.add(LayerRow(
          id: c.id,
          parent: g.id,
          name: c.name,
          depth: depth,
          childIndex: i,
          siblingCount: kids.length,
          visible: c.visible,
          locked: locked,
          lockedSelf: c.locked,
          isGroup: c is GroupNode,
          isUnknown: c is UnknownNode,
        ));
        if (c is GroupNode) walk(c, depth + 1, locked);
      }
    }

    walk(root, 0, false);
    return LayersView(List<LayerRow>.unmodifiable(rows));
  }

  /// The chain-walk the drop target needs: is [candidate] [ancestor] itself or
  /// one of its descendants?
  ///
  /// Dropping a group into its own subtree is refused **by design** in
  /// `NodeOps.reparent` (it would orphan the subtree), so the row must never
  /// highlight as a valid target — a refused-by-design op is not a programming
  /// error and must not reach an `assert` (docs/v3/08 §1).
  bool isSelfOrDescendantOf(NodeId candidate, NodeId ancestor) {
    if (candidate == ancestor) return true;
    final parentOf = <NodeId, NodeId>{for (final r in rows) r.id: r.parent};
    var at = parentOf[candidate];
    // Bounded by the row count: the tree cannot be deeper than it is wide.
    for (var guard = 0; at != null && guard <= rows.length; guard++) {
      if (at == ancestor) return true;
      at = parentOf[at];
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is LayersView && listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hashAll(rows);
}

/// The tree the panel draws — a value-equal projection, so a geometry-only edit
/// (an anchor drag) yields an equal view and rebuilds nothing (AC-13.3).
///
/// It is a `.select` over the whole document precisely so the *comparison*
/// happens here, cheaply, on every mutation, and the widget rebuild happens only
/// when a name, flag or order actually changed.
final layersViewProvider =
    Provider.autoDispose.family<LayersView, String>((ref, projectId) {
  return ref.watch(documentControllerProvider(projectId).select((async) {
    final doc = async.valueOrNull;
    return doc == null ? LayersView.empty : LayersView.of(doc.root);
  }));
});

/// Whether **group**, **duplicate** and **delete** can run on the current
/// selection, and if not, the sentence to show the user.
///
/// This exists because "the button does nothing and says nothing" is the worst
/// of the three possible behaviours: `CreateGroupCommand` and
/// `DuplicateSubtreeCommand` had no call site at all before M2 phase 5, so the
/// M2 exit criterion (a 3-level nested document, reordered, reparented and
/// duplicated) was reachable only from a test calling `controller.run` directly.
/// Binding them needs a gate, and a gate needs a reason — hence a *reason*
/// beside every refusal rather than a bare `bool`.
///
/// It deliberately re-checks only what it can check **cheaply and stably**
/// (the ids resolve; they share one parent). Every other precondition
/// `NodeOps.createGroup` enforces — contiguity today, whatever it grows
/// tomorrow — stays the op's, and its `ArgumentError` message is surfaced by
/// `LayersCommands` as a snackbar. Mirroring the op's full precondition here
/// would be a second copy of a rule that must never disagree with the first.
@immutable
final class LayersActions {
  const LayersActions({
    required this.groupMembers,
    required this.groupBlockedReason,
    required this.duplicateTarget,
    required this.duplicateBlockedReason,
    required this.deleteTargets,
    required this.deleteBlockedReason,
  });

  static const unavailable = LayersActions(
    groupMembers: <NodeId>[],
    groupBlockedReason: 'This project is still opening.',
    duplicateTarget: null,
    duplicateBlockedReason: 'This project is still opening.',
    deleteTargets: <NodeId>[],
    deleteBlockedReason: 'This project is still opening.',
  );

  /// The selection, ordered by child index so the value is stable across
  /// re-selections that differ only in click order.
  final List<NodeId> groupMembers;

  /// Null exactly when [groupMembers] can be grouped.
  final String? groupBlockedReason;

  /// The one selected node, or null when the selection is not exactly one.
  final NodeId? duplicateTarget;
  final String? duplicateBlockedReason;

  /// Every selected subtree to remove, in child order — **one**
  /// [DeleteNodesCommand] takes all of them, so this is a list and not a single
  /// target the way [duplicateTarget] is.
  ///
  /// Unlike group and duplicate, delete has no arity rule: any non-empty,
  /// resolvable, unlocked selection can go, across as many parents as it spans.
  /// Nothing is moved, so there is no common-parent frame to preserve.
  final List<NodeId> deleteTargets;
  final String? deleteBlockedReason;

  bool get canGroup => groupBlockedReason == null;
  bool get canDuplicate => duplicateBlockedReason == null;
  bool get canDelete => deleteBlockedReason == null;

  /// What the panel and the `Cmd/Ctrl+G` binding both read.
  factory LayersActions.of(Document? doc, Set<NodeId> selection) {
    if (doc == null) return unavailable;

    final parentOf = <NodeId, NodeId>{};
    final indexOf = <NodeId, int>{};
    // Effective lock, inherited down the tree exactly as [LayerRow.locked] and
    // the canvas hit-test gate compute it — one rule, three surfaces.
    final lockedIds = <NodeId>{};
    void walk(GroupNode g, bool inherited) {
      for (var i = 0; i < g.children.length; i++) {
        final c = g.children[i];
        parentOf[c.id] = g.id;
        indexOf[c.id] = i;
        final locked = inherited || c.locked;
        if (locked) lockedIds.add(c.id);
        if (c is GroupNode) walk(c, locked);
      }
    }

    walk(doc.root, false);

    final resolved = <NodeId>[
      for (final id in selection)
        if (parentOf.containsKey(id)) id,
    ]..sort((a, b) => indexOf[a]!.compareTo(indexOf[b]!));

    String? groupReason;
    if (selection.isEmpty) {
      groupReason = 'Select a layer first — grouping needs something to group.';
    } else if (resolved.length != selection.length) {
      groupReason =
          'Some of the selected layers are no longer in this project.';
    } else if (resolved.map((id) => parentOf[id]).toSet().length > 1) {
      groupReason = 'Those layers live in different groups. Grouping across '
          'groups would move them, so move them together first.';
    }

    final String? duplicateReason;
    if (selection.length != 1) {
      duplicateReason = selection.isEmpty
          ? 'Select a layer to duplicate.'
          : 'Select exactly one layer to duplicate.';
    } else if (resolved.length != 1) {
      duplicateReason = 'That layer is no longer in this project.';
    } else {
      duplicateReason = null;
    }

    // Delete refuses a locked row for the same reason reorder and rename do
    // (AC-2.2.6, docs/v3/05 §4.5): it is an authored, persisted edit, and it is
    // the most destructive one the panel offers — a lock that stopped a drag but
    // not a delete would protect nothing worth protecting.
    final String? deleteReason;
    if (selection.isEmpty) {
      deleteReason = 'Select a layer to delete.';
    } else if (resolved.length != selection.length) {
      deleteReason = 'Some of the selected layers are no longer in this '
          'project.';
    } else if (resolved.any(lockedIds.contains)) {
      deleteReason = resolved.length == 1
          ? 'That layer is locked — unlock it to delete it.'
          : 'Some of those layers are locked — unlock them to delete them.';
    } else {
      deleteReason = null;
    }

    return LayersActions(
      groupMembers: List<NodeId>.unmodifiable(resolved),
      groupBlockedReason: groupReason,
      duplicateTarget: duplicateReason == null ? resolved.single : null,
      duplicateBlockedReason: duplicateReason,
      deleteTargets:
          deleteReason == null ? List<NodeId>.unmodifiable(resolved) : const [],
      deleteBlockedReason: deleteReason,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LayersActions &&
      listEquals(other.groupMembers, groupMembers) &&
      other.groupBlockedReason == groupBlockedReason &&
      other.duplicateTarget == duplicateTarget &&
      other.duplicateBlockedReason == duplicateBlockedReason &&
      listEquals(other.deleteTargets, deleteTargets) &&
      other.deleteBlockedReason == deleteBlockedReason;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(groupMembers),
      groupBlockedReason,
      duplicateTarget,
      duplicateBlockedReason,
      Object.hashAll(deleteTargets),
      deleteBlockedReason);
}

/// The group/duplicate/delete gate as a **named slice** — value-projected, so a
/// document emission that changes neither the selection's parents nor its
/// membership rebuilds nothing.
final layersActionsProvider =
    Provider.autoDispose.family<LayersActions, String>((ref, projectId) {
  final ids = ref.watch(layersSelectionProvider);
  return ref.watch(documentControllerProvider(projectId)
      .select((async) => LayersActions.of(async.valueOrNull, ids)));
});

/// The selected nodes as `NodeId`s — the **same** `EditorState.selectedNodes`
/// slice the canvas reads (docs/v3/01 §11), projected off `ScenePath` because
/// the tree addresses nodes by id and `instancePath` is `const []` in v1.
///
/// Watching `s.selectedNodes` (not the whole `EditorState`) means a viewport pan
/// or a playhead scrub does not rebuild the panel — only a real selection change
/// does. Because layers and canvas read the one slice, selecting in either
/// surface lights up the other.
final layersSelectionProvider = Provider.autoDispose<Set<NodeId>>((ref) {
  final paths =
      ref.watch(editorControllerProvider.select((s) => s.selectedNodes));
  return <NodeId>{for (final p in paths) p.nodeId};
});

/// Narrow the node selection to what survived a delete of [removed].
///
/// **Not a correctness repair, and deliberately not part of the op.** Selection
/// is stored-never-checked (docs/v3/08 §2) and a dangling `ScenePath` is
/// filtered at every read site, so nothing breaks if this never runs — which is
/// precisely why it lives in the editor layer and not inside
/// `NodeOps.deleteNodes`, where it would grow `anim_core` the dependency on
/// editor types that docs/v3/04 §1 exists to forbid. It is the same courtesy the
/// shell's anchor delete does: the delete is the one moment we *know* the ids
/// are gone, and an inspector still pointed at a layer that left the screen
/// reads as a bug even when nothing is actually wrong.
///
/// [view] must be the tree as it was **before** the delete — after it, the
/// ancestor walk has nothing left to walk. A descendant of a deleted group is
/// deleted too, so the test is that full walk and not `removed.contains`.
///
/// One function, called by both the panel's trash and the shell's `Del`, because
/// a rule with two implementations is a rule with two behaviours.
void dropDeletedFromSelection(
    WidgetRef ref, LayersView view, List<NodeId> removed) {
  final selected = ref.read(editorControllerProvider).selectedNodes;
  final survivors = <ScenePath>[
    for (final path in selected)
      if (!removed.any((r) => view.isSelfOrDescendantOf(path.nodeId, r))) path,
  ];
  if (survivors.length == selected.length) return; // nothing selected died
  final editor = ref.read(editorControllerProvider.notifier);
  editor.clearSelection();
  for (final path in survivors) {
    editor.addToSelection(path);
  }
}
