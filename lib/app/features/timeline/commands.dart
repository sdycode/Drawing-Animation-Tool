/// What the timeline is allowed to change, and what it deliberately cannot.
///
/// **At M0 the timeline issues no document mutation at all.** Scrubbing moves
/// the playhead, and the playhead is ephemeral (docs/v3/04 §4) — it is never in
/// the document and never in the saved JSON. So this file holds exactly one
/// call, and it writes to `EditorController`, not to `DocumentController`.
///
/// The keyframe operations that *will* live here are `TrackOps.moveKeyframe`,
/// `removeKeyframeAt`, `setEasing` and `pinEndpoints` (F6.2, **M4**). They are
/// absent rather than stubbed: `moveKeyframe` addresses a key **by index
/// resolved at command-construction time** and must reject or ε-nudge a move
/// that lands within `TrackOps.minSeparation` (AC-6.2.1, AC-6.2.2), and a stub
/// that re-derived the index from a float mid-drag would pass a happy-path
/// demo and silently retime the wrong key. `TrackOps` does not export those
/// functions yet, so this file cannot pretend they exist.
///
/// Transport play/pause is F9.1's `playing` flag and a `Ticker` — **M6**, and
/// likewise not stubbed. A play button that does nothing is worse than no play
/// button, because it makes the timeline look finished.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/editor_controller.dart';

final class TimelineCommands {
  const TimelineCommands(this._ref);

  final WidgetRef _ref;

  /// Called **once**, on scrub end — never per pointer event.
  ///
  /// During the drag the value goes straight into the `ValueNotifier`, which
  /// invalidates no provider and rebuilds no widget; this settles it into
  /// `EditorState` so that selection logic and (at M4) edit-at-keyframe read a
  /// typed value that is not changing underneath them.
  void commitScrub(double t) =>
      _ref.read(editorControllerProvider.notifier).commitPlayhead(t);
}
