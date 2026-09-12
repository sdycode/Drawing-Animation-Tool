/// Every document mutation the layers panel can cause, and the only place it
/// catches (docs/v3/08 §1).
///
/// One catch, one site: the `NodeOps` behind each call throw `ArgumentError` on
/// an invariant violation (a dangling id, a cross-parent group), and this file
/// turns that into a message the shell shows — never a red screen, never a lost
/// document. Nothing here builds a `Document` by hand and nothing here touches
/// `EditorState`; selection is applied straight through `EditorController` by the
/// panel, because selection is ephemeral and is not a `Command` (docs/v3/08 §2).
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../state/command.dart';
import '../../state/document_controller.dart';

/// Shown when an op rejected the edit. The op's own reason is appended when it
/// has one, because "could not be applied" alone tells the user nothing about
/// what to try instead.
const String kRejectedLayerEditMessage =
    'That layer change could not be applied.';

final class LayersCommands {
  const LayersCommands(this._ref, this._projectId);

  final WidgetRef _ref;
  final String _projectId;

  DocumentController get _controller =>
      _ref.read(documentControllerProvider(_projectId).notifier);

  /// Wrap the current multi-selection in a fresh group (F2.1, AC-2.1.3,
  /// docs/v3/05 §4.5 step 4 — `Cmd/Ctrl+G`).
  ///
  /// The panel's header button and the shell's shortcut are the *only* two call
  /// sites, and both gate on [LayersActions] first: `NodeOps.createGroup` has
  /// real preconditions (siblings, contiguous) and a gesture that fires a
  /// guaranteed-throwing op is not an affordance.
  Future<String?> group(List<NodeId> members) =>
      _guard(() => _controller.run(CreateGroupCommand(members)));

  /// Deep-copy a subtree under fresh ids as **one** undo entry, however many
  /// `NodeId`s and `AnchorId`s it re-mints (F2.1, AC-2.1.5 — `Cmd/Ctrl+D`).
  Future<String?> duplicate(NodeId node) =>
      _guard(() => _controller.run(DuplicateSubtreeCommand(node)));

  /// Delete whole layers — the row's trash button, the header button and `Del`
  /// (F2.2). Every selected subtree goes in **one** [DeleteNodesCommand], so one
  /// `Cmd/Ctrl+Z` brings the whole selection back with its keyframes.
  ///
  /// Like [group], the three call sites gate on [LayersActions] first: a locked
  /// row, a stale id and an empty selection are all refusals `NodeOps` would
  /// throw on, and a trash button that can only ever produce an error message is
  /// not an affordance.
  Future<String?> delete(List<NodeId> nodes) =>
      _guard(() => _controller.run(DeleteNodesCommand(nodes)));

  /// Rename a layer — `NodeId` is unchanged (AC-2.2.3).
  Future<String?> rename(NodeId node, String name) =>
      _guard(() => _controller.run(RenameNodeCommand(node, name)));

  /// Reorder within one parent — a `children` splice, z-order is child order
  /// (AC-2.2.2). [oldIndex]/[newIndex] are authoritative child indices, not
  /// display-reversed ones — the panel converts before calling.
  Future<String?> reorder(NodeId parent, int oldIndex, int newIndex) => _guard(
      () => _controller.run(ReorderChildCommand(parent, oldIndex, newIndex)));

  /// Move a layer into a *different* group — world-preserving, the node does not
  /// visually move (AC-2.1.4, docs/v3/05 §4.5).
  Future<String?> reparent(NodeId node, NodeId newParent, int index) =>
      _guard(() => _controller.run(ReparentCommand(node, newParent, index)));

  /// Toggle visibility (AC-2.2.4). The AND-down-the-tree is the evaluator's.
  Future<String?> setVisible(NodeId node, bool visible) =>
      _guard(() => _controller.run(SetVisibleCommand(node, visible)));

  /// Toggle lock (AC-2.2.6). A hit-test gate, never read by the evaluator.
  Future<String?> setLocked(NodeId node, bool locked) =>
      _guard(() => _controller.run(SetLockedCommand(node, locked)));

  /// **No `assert(false)` here, deliberately.**
  ///
  /// An op's `ArgumentError` in *this* file is not a programming error — it is
  /// this panel's ops refusing a gesture by design: dropping a group onto its
  /// own descendant, grouping a non-contiguous selection, toggling a flag on an
  /// `UnknownNode` whose raw JSON would swallow it. `assert(false)` is for
  /// programming errors (docs/v3/08 §1); on user input it turns a legal gesture
  /// into an `AssertionError` thrown from inside the `catch`, which escapes this
  /// future and lands as an **unhandled async error** in debug — so the snackbar
  /// this method exists to produce never appears, and only release builds behave
  /// correctly. The refusal is reported to the user in the sentence the op
  /// itself wrote, which is more useful than a stack trace.
  static Future<String?> _guard(Future<void> Function() run) async {
    try {
      await run();
      return null;
    } on StoreException catch (e) {
      return e.failure.message;
    } on ArgumentError catch (e) {
      final reason = e.message;
      return reason == null || '$reason'.isEmpty
          ? kRejectedLayerEditMessage
          : '$kRejectedLayerEditMessage $reason';
    }
  }
}
