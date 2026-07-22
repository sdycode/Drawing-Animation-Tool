/// Every document mutation the inspector can cause, and the only place it
/// catches (docs/v3/08 §1).
///
/// At M2 that is two: authoring a node's `Transform2`, and authoring its own
/// `opacity`. Fill / stroke /
/// trim / easing / anchor-kind editing are M3+ and are left as labelled seams in
/// the panel, not stubbed here — a command that pretended to write paint would
/// be worse than its absence. Nothing here builds a `Document` by hand and
/// nothing here touches `EditorState`.
library;

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../state/command.dart';
import '../../state/document_controller.dart';

const String kRejectedInspectorEditMessage = 'That value could not be applied.';

final class InspectorCommands {
  const InspectorCommands(this._ref, this._projectId);

  final WidgetRef _ref;
  final String _projectId;

  DocumentController get _controller =>
      _ref.read(documentControllerProvider(_projectId).notifier);

  /// Overwrite the selected node's `Transform2` (F3.1, AC-3.1.1).
  ///
  /// **One field edit is one command and one undo entry.** The panel builds the
  /// whole next `Transform2` (via `copyWith` on the current one) and hands it
  /// here, so composition order stays anim_core's golden-tested `toAffine` and
  /// this layer never re-derives a matrix. Rotation arrives already converted to
  /// **unbounded radians** — the panel shows degrees but stores radians with no
  /// wrap and no shortest-arc (AC-3.1.2).
  Future<String?> setTransform(NodeId node, Transform2 transform) =>
      _guard(() => _controller.run(SetTransformCommand(node, transform)));

  /// Author one node's own `opacity` (F2.2's `opacity` PRODUCT row, AC-2.2.5).
  ///
  /// [opacity] is the stored **0..1** value; the panel shows percent and
  /// converts, the same display-vs-storage split rotation uses for degrees vs
  /// radians. The product down the ancestor chain belongs to the evaluator, so
  /// nothing here reads or writes an effective opacity — one field, one write,
  /// one undo entry. Range clamping lives in `NodeOps.setOpacity`, at the
  /// mutation.
  Future<String?> setOpacity(NodeId node, double opacity) =>
      _guard(() => _controller.run(SetOpacityCommand(node, opacity)));

  static Future<String?> _guard(Future<void> Function() run) async {
    try {
      await run();
      return null;
    } on StoreException catch (e) {
      return e.failure.message;
    } on ArgumentError catch (e) {
      assert(false, 'inspector command rejected by an op: $e');
      return kRejectedInspectorEditMessage;
    }
  }
}
