/// The autosave indicator's state — ephemeral, never serialized (docs/v3/03
/// F10.3, AC-10.3.3).
///
/// The chrome must always show exactly one of **dirty / saving / saved / error**
/// (AC-10.3.3), and a failed write must show **error** while the edit stays in
/// memory — no modal, no silent success (AC-10.3.4). This is the one piece of
/// state that lets a user trust the editor with their work, so it is modelled
/// explicitly rather than inferred from `rev` (which only signals that a save
/// *completed*, never that one is pending, in flight, or failed).
///
/// It lives beside the playhead as an ephemeral `ValueNotifier` the chrome
/// watches with a leaf `ValueListenableBuilder`: a status change repaints the
/// indicator, not the editor. It is **never** part of `Document`, so it can
/// never reach storage (AC-2.2.7).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_store.dart';

/// The four states the indicator is always in exactly one of (AC-10.3.3).
enum SavePhase {
  /// On disk matches the screen — nothing pending.
  saved,

  /// An edit has applied and is shown, but the debounced write has not fired.
  dirty,

  /// The write is in flight to the store.
  saving,

  /// The last write failed. The edit is retained in memory (AC-10.3.4); the
  /// next edit — or a scheduled retry — will try again.
  error,
}

@immutable
final class SaveState {
  const SaveState({required this.phase, this.lastSaved, this.failure});

  /// A freshly opened document is clean.
  static const initial = SaveState(phase: SavePhase.saved);

  final SavePhase phase;

  /// When the last successful write acknowledged, for the "saved 2s ago" chrome
  /// (docs/v3/05 §2). Null until the first save of the session lands; carried
  /// forward across dirty/saving/error so the chrome can still say when the last
  /// good save was even while a newer edit is pending or failing.
  final DateTime? lastSaved;

  /// The reason the last write failed, for the error tooltip. Null unless
  /// [phase] is [SavePhase.error].
  final StoreFailure? failure;

  SaveState dirty() =>
      SaveState(phase: SavePhase.dirty, lastSaved: lastSaved, failure: null);

  SaveState saving() =>
      SaveState(phase: SavePhase.saving, lastSaved: lastSaved, failure: null);

  SaveState saved(DateTime at) =>
      SaveState(phase: SavePhase.saved, lastSaved: at, failure: null);

  SaveState errored(StoreFailure why) =>
      SaveState(phase: SavePhase.error, lastSaved: lastSaved, failure: why);

  @override
  bool operator ==(Object other) =>
      other is SaveState &&
      other.phase == phase &&
      other.lastSaved == lastSaved &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(phase, lastSaved, failure);

  @override
  String toString() =>
      'SaveState($phase, lastSaved: $lastSaved, failure: $failure)';
}

/// The live save status for one open project. Ephemeral and per-project. The
/// controller drives it (dirty on edit → saving on flush → saved / error); the
/// chrome reads it. A `ValueNotifier` — not provider state — so the indicator
/// repaints without rebuilding the editor, exactly as the playhead does.
///
/// **Deliberately not `autoDispose`.** The controller holds this notifier and
/// keeps writing to it from a queued flush that can outlive the last widget
/// watching it; an `autoDispose` provider would tear the notifier down the
/// instant no widget listened (a controller-only test never mounts the chrome)
/// and the next flush would write a disposed notifier. It instead lives with its
/// container and disposes when the container does — one cheap notifier per
/// project opened in a session.
final saveStateProvider =
    Provider.family<ValueNotifier<SaveState>, String>((ref, id) {
  final notifier = ValueNotifier<SaveState>(SaveState.initial);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// How long the autosave waits for edits to settle before it writes (AC-10.3.1).
///
/// **Defaults to zero — eager save.** At a zero window the controller flushes
/// inline, so an awaited edit is a persisted edit: the pre-debounce contract
/// every existing test relies on holds without an override, and a zero window is
/// itself a safe behaviour (one write per edit, just uncoalesced). The real
/// editor overrides this to ~600 ms in `main.dart` to coalesce a burst of
/// discrete edits — a run of keystrokes, a flurry of keyframe ops — into one
/// write, while staying short enough that "saved" appears promptly. A test that
/// exercises the *debounce itself* overrides it to a real window and pumps
/// across it.
final autosaveDebounceProvider = Provider<Duration>((ref) => Duration.zero);
