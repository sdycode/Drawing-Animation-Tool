/// The timeline feature's named slices (docs/v3/08 §2).
///
/// The timeline owns rows, keyframe dots and the playhead drag. It does **not**
/// own the document, and the providers here are the entire surface it reads it
/// through — no widget under `timeline/widgets/` watches
/// `documentControllerProvider` directly. That matters more here than anywhere:
/// legacy's timeline rebuilt on every notify and mutated the document from
/// inside `itemBuilder`, so merely rendering it edited the user's file
/// (AC-6.2.5).
library;

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';
import 'timeline_model.dart';

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

/// The whole timeline row model — one node per tracked node, one row per
/// `PropertyKey`, and the union summary — as a **value-equal projection**
/// (docs/v3/08 §2).
///
/// `.select` compares each rebuild's [TimelineModel] to the last with `==`, and
/// [TimelineModel] equates deeply, so a document mutation that leaves every key
/// list untouched (a node dragged on the canvas, a colour changed) yields an
/// equal model and rebuilds the timeline **not at all**. That is the difference
/// between "correct but coarse" (the M0 union that notified on every mutation)
/// and the real slice: the coarseness is gone without a hand-rolled cache to
/// keep in sync with the ops.
///
/// It reads the **default/active animation only** (v1 has one, and the UI hides
/// the concept), walks the tree in document order for a stable row order, and
/// keeps only nodes whose `TrackSet` has a typed track. Every read is total: a
/// malformed stored track lands in `unknownKeys` and never reaches `byKey`, so
/// it simply draws no row rather than throwing inside a projection the paint
/// loop depends on (AC-9.2.4).
final timelineModelProvider =
    Provider.autoDispose.family<TimelineModel, String>((ref, projectId) {
  final animationId = ref.watch(activeAnimationProvider(projectId));
  return ref.watch(documentControllerProvider(projectId).select((async) {
    final doc = async.valueOrNull;
    if (doc == null || animationId == null) return TimelineModel.empty;

    // The default/active animation's per-node tracks. Named without the
    // `Animation` identifier so the barrel need not be aliased here.
    Map<NodeId, TrackSet> tracks = const <NodeId, TrackSet>{};
    for (final a in doc.animations) {
      if (a.id == animationId) {
        tracks = a.tracks;
        break;
      }
    }
    if (tracks.isEmpty) return TimelineModel.empty;

    final nodes = <TimelineNodeModel>[];
    for (final node in doc.walk()) {
      final set = tracks[node.id];
      if (set == null || set.byKey.isEmpty) continue;

      // One row per property, ordered by the `PropKey` enum so the row order is
      // deterministic and stable across rebuilds (a `Map` iteration order is
      // not a contract to hang a UI on).
      final entries = set.byKey.entries.toList()
        ..sort((a, b) => a.key.prop.index.compareTo(b.key.prop.index));

      final rows = <TimelinePropertyRow>[];
      final summary = <double>{};
      for (final entry in entries) {
        // Every track in `byKey` is a `TypedTrack`; the switch reads its keys
        // without a blind cast (docs/v3/08 §4). We need only `t` and easing.
        final keys = <TimelineKeyModel>[
          for (final k in switch (entry.value) {
            final TypedTrack<Object?> t => t.keys
          })
            TimelineKeyModel(k.t, k.easing),
        ];
        for (final k in keys) {
          summary.add(k.t);
        }
        rows.add(TimelinePropertyRow(
            node.id, entry.key, List<TimelineKeyModel>.unmodifiable(keys)));
      }

      final summaryList = summary.toList()..sort();
      nodes.add(TimelineNodeModel(
        node.id,
        node.name,
        List<double>.unmodifiable(summaryList),
        List<TimelinePropertyRow>.unmodifiable(rows),
      ));
    }
    return TimelineModel(List<TimelineNodeModel>.unmodifiable(nodes));
  }));
});
