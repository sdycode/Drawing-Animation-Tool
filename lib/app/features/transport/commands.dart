/// Every document mutation the transport can cause, and the only place it
/// catches (docs/v3/08 §1).
///
/// Two edits, both on the active `Animation`'s PERSISTED time model: the loop
/// mode (AC-9.1.2) and the duration (AC-9.1.5). Each is one `state/command.dart`
/// command → one undo entry. **`playing` and the playhead are NOT here** — they
/// are ephemeral and are written straight through `EditorController` and the
/// `playheadProvider` notifier by the widget, never as a `Command`
/// (docs/v3/08 §2). Nothing here builds a `Document` by hand and nothing here
/// reads one.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../state/command.dart';
import '../../state/document_controller.dart';

/// Shown when a save refused a transport edit — a read-only document (a newer
/// schema, docs/v3/02 §1 rule 7) or an offline store. The op's own reason is
/// appended when it carries one.
const String kRejectedTransportEditMessage =
    'That transport change could not be applied.';

final class TransportCommands {
  const TransportCommands(this._ref, this._projectId);

  final WidgetRef _ref;
  final String _projectId;

  DocumentController get _controller =>
      _ref.read(documentControllerProvider(_projectId).notifier);

  /// Change the active animation's loop mode — ONE undo entry, and it persists
  /// (the mode is on the `Animation`, AC-9.1.2).
  Future<String?> setLoop(AnimationId animation, LoopMode loop) =>
      _guard(() => _controller.run(SetLoopModeCommand(animation, loop)));

  /// Retime the animation by editing `durationSeconds` — ONE undo entry, and it
  /// re-authors no keyframe (AC-9.1.5). The command clamps to a positive floor.
  Future<String?> setDuration(AnimationId animation, double seconds) =>
      _guard(() => _controller.run(SetDurationCommand(animation, seconds)));

  /// **No `assert(false)` on legal input**, for the reason
  /// `timeline/commands.dart` spells out. These edits carry no op-level invariant
  /// to trip, but the gate still turns a `StoreException` (a read-only or offline
  /// save) into a message rather than letting it escape as an unhandled async
  /// error on this dropped future (docs/v3/08 §1).
  static Future<String?> _guard(Future<void> Function() run) async {
    try {
      await run();
      return null;
    } on StoreException catch (e) {
      return e.failure.message;
    } on ArgumentError catch (e) {
      final reason = e.message;
      return reason == null || '$reason'.isEmpty
          ? kRejectedTransportEditMessage
          : '$kRejectedTransportEditMessage $reason';
    }
  }
}
