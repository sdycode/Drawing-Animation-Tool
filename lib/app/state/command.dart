/// The command vocabulary — one pure `Document → Document` per edit the editor
/// can make (docs/v3/04 §6).
///
/// **A command is a value, not a closure over a controller.** It names *what*
/// changed (its [Command.label]) and computes the next document from the
/// previous one, and it does nothing else — no IO, no `EditorState`, no
/// `BuildContext`. That is what lets [CommandStack] treat a command's result as
/// a snapshot and undo a hundred-id `DuplicateSubtreeCommand` as **one** entry.
///
/// **One class per edit — no generic `Command` with a `Map` payload, and no
/// `BatchCommand`.** Both are named antipatterns (docs/v3/08 §4): a `Map`
/// payload makes an invariant failure unattributable, and a batch makes
/// `insertAnchor`'s keyframe backfill undo as two entries. Each command below is
/// a thin wrapper over the `anim_core` op that already enforces the invariant,
/// so the throw the op raises is the same throw the command gate catches
/// (docs/v3/08 §1).
library;

import 'package:anim_core/anim_core.dart' hide Animation;

/// The undoable unit. `apply` is pure and may throw [ArgumentError] on an
/// invariant violation — the command layer never swallows that; [CommandStack]
/// runs `apply` and the one catch site (a feature's `commands.dart`) reports it.
abstract interface class Command {
  /// Shown in the UI ("Group", "Duplicate") and in the undo history.
  String get label;

  /// The new document. Pure: same input, same output, no side effects.
  Document apply(Document before);
}

/// Append a freshly built node to the artboard root.
///
/// The whole node is constructed by the caller (the pen tool builds one closed
/// [PathNode]) and appended here, so a document never holds half a gesture. This
/// mirrors the M0 inline append it replaces; the shape was already
/// `Document → Document`, which is why undo is an addition rather than a
/// rewrite.
final class AddNodeCommand implements Command {
  const AddNodeCommand(this.node);

  final Node node;

  @override
  String get label => 'Add ${node.name}';

  @override
  Document apply(Document d) => d.copyWith(
        root: d.root.copyWith(children: <Node>[...d.root.children, node]),
      );
}

/// Wrap [members] in a fresh group without moving a pixel (F2.1).
final class CreateGroupCommand implements Command {
  const CreateGroupCommand(this.members);

  final List<NodeId> members;

  @override
  String get label => 'Group';

  @override
  Document apply(Document d) => NodeOps.createGroup(d, members);
}

/// World-preserving reparent — the drag-reorder of the layers panel (F2.2,
/// docs/v3/05 §4.5).
final class ReparentCommand implements Command {
  const ReparentCommand(this.node, this.newParent, this.index);

  final NodeId node;
  final NodeId newParent;
  final int index;

  @override
  String get label => 'Move layer';

  @override
  Document apply(Document d) => NodeOps.reparent(d, node, newParent, index);
}

/// Deep-copy a subtree under fresh ids — **one** undo entry however many ids it
/// re-mints (F2.1; the M2 exit criterion names this exactly).
final class DuplicateSubtreeCommand implements Command {
  const DuplicateSubtreeCommand(this.node);

  final NodeId node;

  @override
  String get label => 'Duplicate';

  @override
  Document apply(Document d) => NodeOps.duplicateSubtree(d, node);
}

/// Rename a node in the tree — the layers-panel rename (F2.2).
///
/// Distinct from [RenameDocumentCommand]: this touches one node's `name`, that
/// touches the document's. Two edits, two commands, so the undo history reads
/// honestly.
final class RenameNodeCommand implements Command {
  const RenameNodeCommand(this.node, this.name);

  final NodeId node;
  final String name;

  @override
  String get label => 'Rename layer';

  @override
  Document apply(Document d) => NodeOps.setName(d, node, name);
}

/// Toggle a node's authored `visible` flag — the layers-panel eye (F2.2,
/// AC-2.2.4). The AND-down-the-tree is the evaluator's; this command only writes
/// the one field, so there is no derived "effective visibility" to keep in sync
/// (docs/v3/08 §4).
final class SetVisibleCommand implements Command {
  const SetVisibleCommand(this.node, this.visible);

  final NodeId node;
  final bool visible;

  @override
  String get label => visible ? 'Show layer' : 'Hide layer';

  @override
  Document apply(Document d) => NodeOps.setVisible(d, node, visible);
}

/// Set a node's authored `opacity` — the inspector's opacity field (F2.2,
/// AC-2.2.5).
///
/// The PRODUCT down the ancestor chain is the evaluator's, recomputed per frame,
/// so this writes one node's own value and there is no derived effective opacity
/// to desync (docs/v3/08 §4). Clamping lives in [NodeOps.setOpacity] — at the
/// mutation, not at read — because an authored 1.7 is a bad write, while a
/// *sampled* overshoot through an easing curve is legitimate and is clamped
/// separately by the evaluator.
final class SetOpacityCommand implements Command {
  const SetOpacityCommand(this.node, this.opacity);

  final NodeId node;
  final double opacity;

  @override
  String get label => 'Opacity';

  @override
  Document apply(Document d) => NodeOps.setOpacity(d, node, opacity);
}

/// Toggle a node's authored `locked` flag — the layers-panel lock (F2.2,
/// AC-2.2.6). `locked` is a hit-test gate the evaluator never reads, so this is
/// undoable editor structure and not an animation edit.
final class SetLockedCommand implements Command {
  const SetLockedCommand(this.node, this.locked);

  final NodeId node;
  final bool locked;

  @override
  String get label => locked ? 'Lock layer' : 'Unlock layer';

  @override
  Document apply(Document d) => NodeOps.setLocked(d, node, locked);
}

/// Reorder a child within one parent — the layers-panel drag-reorder (F2.2,
/// docs/v3/05 §4.5, AC-2.2.2).
///
/// Z-order **is** child order, so this is a child-list splice, not a move: the
/// node's `Transform2` is untouched. A drop into a *different* group is a
/// [ReparentCommand] instead (world-preserving), never this — reorder is
/// same-parent only, which is why it takes a `parent` and two indices rather
/// than a new parent.
final class ReorderChildCommand implements Command {
  const ReorderChildCommand(this.parent, this.oldIndex, this.newIndex);

  final NodeId parent;
  final int oldIndex;
  final int newIndex;

  @override
  String get label => 'Reorder layer';

  @override
  Document apply(Document d) =>
      NodeOps.reorderChild(d, parent, oldIndex, newIndex);
}

/// Overwrite a node's [Transform2] — the inspector's transform authoring (F3.1).
final class SetTransformCommand implements Command {
  const SetTransformCommand(this.node, this.transform);

  final NodeId node;
  final Transform2 transform;

  @override
  String get label => 'Transform';

  @override
  Document apply(Document d) => NodeOps.setTransform(d, node, transform);
}

/// Move one anchor — the pose edit of docs/v3/01 §12.
///
/// [atT] `null` edits the node's rest pose; non-null writes the pose into the
/// path track keyframe at that `t` (seeding a `t = 0.0` key from the rest pose
/// the first time). All of that lives in [PathOps.moveAnchor]; the command only
/// names the edit.
final class MoveAnchorCommand implements Command {
  const MoveAnchorCommand(this.node, this.anchor, this.to, {this.atT});

  final NodeId node;
  final AnchorId anchor;
  final Vec2 to;
  final double? atT;

  @override
  String get label => 'Move anchor';

  @override
  Document apply(Document d) =>
      PathOps.moveAnchor(d, node, anchor, to, atT: atT);
}

/// Rename the document itself.
///
/// Not in the F2.1/F2.2 op list, but every mutation routes through a command so
/// the controller can keep having no public setter (docs/v3/04 §6) — the
/// document title field cannot be an exception, or it becomes the one call site
/// that assigns `state = newDoc` directly.
final class RenameDocumentCommand implements Command {
  const RenameDocumentCommand(this.name);

  final String name;

  @override
  String get label => 'Rename';

  @override
  Document apply(Document d) => d.copyWith(name: name);
}
