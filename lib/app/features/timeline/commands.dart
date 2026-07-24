/// Every document mutation the timeline can cause, and the only place it catches
/// (docs/v3/08 §1).
///
/// **At M0 this held exactly one call** — `commitScrub`, which writes the
/// ephemeral playhead and touches no document. M4 adds the keyframe edits (F6.2,
/// F7.1): move a dot, re-ease a segment, key at the playhead, delete a key. Each
/// is a thin wrapper over one `state/command.dart` command over `KeyframeOps`,
/// and the `ArgumentError` those ops raise on a refused edit — an unknown node,
/// a bad index, a within-`minSeparation` collision — is turned here into a
/// message the panel shows, never a red screen and never a lost document.
///
/// Nothing here builds a `Document` by hand and nothing here touches
/// `EditorState` except through its controller: selection and the playhead are
/// ephemeral and are applied straight through `EditorController` by the widget,
/// because they are not `Command`s (docs/v3/08 §2). The **evaluated value** a
/// `K` keys with is sampled by the widget from the document it is displaying and
/// passed in — this file never reads a document either.
///
/// Transport play/pause is still **M6** and still absent rather than stubbed: a
/// play button that did nothing would make the timeline look finished.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../state/command.dart';
import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';

/// Shown when an op rejected a keyframe edit. The op's own reason is appended
/// when it has one — "a key already sits within minSeparation of that time" is
/// far more useful than "could not be applied", and it is the sentence the op
/// itself wrote (docs/v3/08 §1).
const String kRejectedKeyframeEditMessage =
    'That keyframe change could not be applied.';

final class TimelineCommands {
  const TimelineCommands(this._ref, this._projectId);

  final WidgetRef _ref;
  final String _projectId;

  DocumentController get _controller =>
      _ref.read(documentControllerProvider(_projectId).notifier);

  /// The keyframe the user is editing right now, captured with the undo snapshot
  /// so undo returns them to it (docs/v3/04 §6). Ephemeral — never serialized.
  KeyframeRef? get _selectedKeyframe =>
      _ref.read(editorControllerProvider).selectedKeyframe;

  /// Called **once**, on scrub end — never per pointer event.
  ///
  /// During the drag the value goes straight into the `ValueNotifier`, which
  /// invalidates no provider and rebuilds no widget; this settles it into
  /// `EditorState` so that selection logic and edit-at-keyframe read a typed
  /// value that is not changing underneath them.
  void commitScrub(double t) =>
      _ref.read(editorControllerProvider.notifier).commitPlayhead(t);

  /// Upsert a key at [t] holding the already-sampled [value] — the route the
  /// canvas/inspector agent will reuse for edit-at-keyframe writes.
  Future<String?> keyAt(
          NodeId node, PropertyKey property, double t, Object? value) =>
      _guard(() => _controller.run(KeyframeAtCommand(node, property, t, value),
          keyframe: _selectedKeyframe));

  /// Key `(node, property)` at [t] with the property's **evaluated value** —
  /// the **K** action (docs/v3/05 §4.3 step 4, AC-6.2.7).
  ///
  /// The evaluated value of a keyed property at [t] is exactly `track.sampleAt(t)`
  /// — the node-local number `evaluate`'s stage-1 `sampleTracks` produces for
  /// that channel. It is read here rather than off the `Scene`'s `ResolvedNode`
  /// on purpose: `ResolvedNode` carries the **world-composed** transform, which
  /// for a nested node is the wrong number to write into a node-local track. So
  /// K samples the one track the row was drawn from. K on the timeline always
  /// targets an already-tracked property (a property row exists only for a
  /// property with a track), so the sample is defined; keying a brand-new
  /// property is the inspector's diamond, left to the next agent.
  ///
  /// Returns null — no command, no snackbar — when the track is absent or is a
  /// **path** track: a path key is a `PathPose` that `PathOps` owns, and
  /// [KeyframeOps.keyAt] refuses `PropKey.path` by design.
  Future<String?> keyAtPlayhead(NodeId node, PropertyKey property, double t) {
    final value = _sampleValue(node, property, t);
    if (value == null) return Future<String?>.value();
    return keyAt(node, property, t, value);
  }

  Object? _sampleValue(NodeId node, PropertyKey property, double t) {
    if (property.prop == PropKey.path) return null;
    final doc = _ref.read(documentControllerProvider(_projectId)).valueOrNull;
    final animId = _ref.read(activeAnimationProvider(_projectId));
    if (doc == null || animId == null) return null;
    Track? track;
    for (final a in doc.animations) {
      if (a.id == animId) {
        track = a.tracksFor(node).byKey[property];
        break;
      }
    }
    final at = t.isNaN ? 0.0 : t.clamp(0.0, 1.0).toDouble();
    return switch (track) {
      final Vec2Track v => v.sampleAt(at),
      final ScalarTrack s => s.sampleAt(at),
      final ColorTrack c => c.sampleAt(at),
      final BoolTrack b => b.sampleAt(at),
      _ => null, // a PathTrack (unreachable value) or no track at all
    };
  }

  /// Move key [index] to [newT] — a dot dragged along its rail. [index] is the
  /// one resolved when the drag started (AC-6.2.1); a drop within
  /// `TrackOps.minSeparation` of a neighbour is rejected by the op and surfaces
  /// here as a message, so the dot springs back to where it was.
  Future<String?> move(
          NodeId node, PropertyKey property, int index, double newT) =>
      _guard(() => _controller.run(
          MoveKeyframeCommand(node, property, index, newT),
          keyframe: _selectedKeyframe));

  /// Set the easing leaving key [index] — the segment picker (AC-7.1.1). [easing]
  /// is already a concrete `Easing`; no preset symbol reaches this layer.
  Future<String?> setEasing(
          NodeId node, PropertyKey property, int index, Easing easing) =>
      _guard(() => _controller.run(
          SetKeyframeEasingCommand(node, property, index, easing),
          keyframe: _selectedKeyframe));

  /// Remove key [index] — **Shift+K** on the key under the playhead.
  ///
  /// **When the removed key is the selected one, the selection is cleared**
  /// (AC-4.2.3's 2nd route): a `selectedKeyframe` left pointing at a key that no
  /// longer exists is what re-seeds a path track on the next canvas drag. Undo
  /// still restores both the key and its selection via the captured ref.
  Future<String?> remove(NodeId node, PropertyKey property, int index) async {
    final selected = _selectedKeyframe;
    final message = await _guard(() => _controller
        .run(RemoveKeyframeCommand(node, property, index), keyframe: selected));
    if (message == null && selected == (node, property, index)) {
      _ref.read(editorControllerProvider.notifier).clearKeyframe();
    }
    return message;
  }

  /// **No `assert(false)` here**, for the reason `layers/commands.dart` spells
  /// out: an op's `ArgumentError` in this file is the timeline refusing a
  /// gesture by design — dragging a dot onto its neighbour, keying a value type
  /// the track will not take — not a programming error. `assert(false)` on user
  /// input escapes this future as an unhandled async error in debug, so the
  /// snackbar this method exists to produce would never appear. The refusal is
  /// reported in the op's own words instead.
  static Future<String?> _guard(Future<void> Function() run) async {
    try {
      await run();
      return null;
    } on StoreException catch (e) {
      return e.failure.message;
    } on ArgumentError catch (e) {
      final reason = e.message;
      return reason == null || '$reason'.isEmpty
          ? kRejectedKeyframeEditMessage
          : '$kRejectedKeyframeEditMessage $reason';
    }
  }
}
