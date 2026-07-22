/// The timeline feature's named slices (docs/v3/08 §2).
///
/// The timeline owns rows, keyframe dots and the playhead drag. It does **not**
/// own the document, and the two providers here are the entire surface it reads
/// it through — no widget under `timeline/widgets/` watches
/// `documentControllerProvider` directly. That matters more here than anywhere:
/// legacy's timeline rebuilt on every notify and mutated the document from
/// inside `itemBuilder`, so merely rendering it edited the user's file
/// (AC-6.2.5).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';

/// Seconds for the whole animation, defaulting to 1.0 when there is none.
///
/// The document stores **fractions**; seconds exist only for display, and the
/// UI writes `t = seconds / durationSeconds` back (docs/v3/01 §10, AC-9.1.5).
/// That is why changing `durationSeconds` from 1.0 to 2.6 retimes everything
/// and re-authors no keyframe — and why the legacy file full of `0.769` magic
/// numbers could never be retimed at all.
final timelineDurationProvider =
    Provider.autoDispose.family<double, String>((ref, projectId) {
  final animation = ref.watch(activeAnimationProvider(projectId));
  return ref.watch(documentControllerProvider(projectId).select((d) {
    final doc = d.valueOrNull;
    if (doc == null || animation == null) return 1.0;
    for (final a in doc.animations) {
      if (a.id == animation) return a.durationSeconds;
    }
    return 1.0;
  }));
});

/// Every `t` at which the document holds a path keyframe, ascending.
///
/// M0 draws one lane for the whole document because there is no selection model
/// and no row expansion yet; M4 turns this into one row per node × `PropertyKey`
/// (AC-6.1.1 — there is no global keyframe grid, so the rows never share a key
/// list). The union is the *summary* row docs/v3/05 §2 describes, which is
/// read-only, which is exactly what M0 needs.
///
/// The selector returns a `List`, and lists compare by identity, so this
/// notifies on every document mutation rather than only on a keyframe change.
/// That is correct-but-coarse and deliberately left so: any mutation may add a
/// key, and a hand-rolled equality here would be a cache to keep in sync with
/// the ops.
final timelineKeyTimesProvider =
    Provider.autoDispose.family<List<double>, String>((ref, projectId) {
  final animation = ref.watch(activeAnimationProvider(projectId));
  return ref.watch(documentControllerProvider(projectId).select((d) {
    final doc = d.valueOrNull;
    if (doc == null || animation == null) return const <double>[];

    final times = <double>{};
    for (final a in doc.animations) {
      if (a.id != animation) continue;
      for (final trackSet in a.tracks.values) {
        // The typed accessor, never a cast: it returns null on a type mismatch
        // instead of throwing, so a stored document whose `path` key holds a
        // vec2 track draws no dots rather than blanking the timeline.
        final track = trackSet.pathTrack();
        if (track == null) continue;
        for (final key in track.keys) {
          times.add(key.t);
        }
      }
    }
    return times.toList(growable: false)..sort();
  }));
});
