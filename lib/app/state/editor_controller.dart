import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'document_controller.dart';

/// Ephemeral editor state — the second of the three controllers (docs/v3/04 §4).
///
/// **Nothing here is ever serialized.** Selection, the playhead and (later)
/// hover and the viewport transform are derived from what the user is doing
/// right now, not from what the file contains. Legacy persisted them onto the
/// document, which is AC-2.2.7: a file saved mid-selection referenced ids that
/// a later edit deleted, and the document then refused to open. Keeping them in
/// a separate notifier is also what makes a marquee drag cheap — it invalidates
/// nothing that reads the `Document`.
@immutable
final class EditorState {
  const EditorState({
    this.playhead = 0.0,
    this.playing = false,
    this.selectedAnchors = const <AnchorId>{},
    this.activeAnimation,
  });

  /// The **settled** playhead, unitless and normalized (AC-9.1.1).
  ///
  /// Not the live one: during a scrub the value lives in the `ValueNotifier`
  /// below and is committed here exactly once, on drag end. Selection logic and
  /// edit-at-keyframe read this field precisely because it is settled — a
  /// property read mid-drag would sample a different `t` on every frame.
  final double playhead;

  /// Transport is M6. The field exists now because `EditorState` is the place
  /// the answer lives, and adding it later would mean touching every
  /// `copyWith` call site instead of none.
  final bool playing;

  /// **Resolved, never repaired** (docs/v3/08 §2): a dangling id is legal here
  /// and is filtered at every read site. Scrubbing it out on delete is what
  /// would make undo unable to restore the selection it took away.
  final Set<AnchorId> selectedAnchors;

  /// Which animation the playhead is a position *within*, or null to mean
  /// "whatever the document's `defaultAnimationId` says".
  ///
  /// Null is not "no animation" — it is "no override". Resolving it against the
  /// document happens in each feature's `providers.dart`, so this controller
  /// never has to read a `Document`.
  final AnimationId? activeAnimation;

  EditorState copyWith({
    double? playhead,
    bool? playing,
    Set<AnchorId>? selectedAnchors,
    AnimationId? activeAnimation,
    bool clearActiveAnimation = false,
  }) =>
      EditorState(
        playhead: playhead ?? this.playhead,
        playing: playing ?? this.playing,
        selectedAnchors: selectedAnchors ?? this.selectedAnchors,
        activeAnimation: clearActiveAnimation
            ? null
            : (activeAnimation ?? this.activeAnimation),
      );
}

class EditorController extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  /// Commits the scrub. Called once on drag end, never per frame.
  ///
  /// Clamped here, at the controller boundary, because `TypedTrack.bracket` is
  /// deliberately honest about a NaN `t` — clamping inside the evaluator would
  /// be the NaN rescue docs/v3/08 §1 forbids. The painters clamp on their own
  /// side for the live value; this is the same guard for the settled one.
  void commitPlayhead(double t) {
    final clamped = t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
    if (clamped == state.playhead) return;
    state = state.copyWith(playhead: clamped);
  }

  void selectAnchor(AnchorId? anchor) {
    state = state.copyWith(
      selectedAnchors: anchor == null ? const <AnchorId>{} : <AnchorId>{anchor},
    );
  }
}

final editorControllerProvider =
    NotifierProvider<EditorController, EditorState>(EditorController.new);

/// The one hot path, and it bypasses the widget tree entirely (docs/v3/04 §4).
///
/// **Identity is stable for the app's lifetime; only its value changes.** The
/// scrub drag — and at M6 the transport `Ticker` — writes `playhead.value`, and
/// because that is a plain notifier and not provider state, **no provider is
/// invalidated and no widget rebuilds.** The painters receive it as
/// `CustomPainter(repaint: playhead)`, so the tick reaches `paint()` without
/// ever entering `build()`.
///
/// Routing the playhead through a provider instead is a named antipattern
/// (docs/v3/08 §4): it couples every panel to the frame budget, so one slow
/// inspector makes scrubbing unusable app-wide. Legacy went further and
/// round-tripped the playhead through pixels and a `BuildContext`; this
/// provider is the structural reason that cannot happen again.
final playheadProvider = Provider<ValueNotifier<double>>((ref) {
  final notifier = ValueNotifier<double>(0.0);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// The animation the playhead addresses: the editor's override if there is one,
/// otherwise the document's `defaultAnimationId`.
///
/// It lives here, next to the two controllers it joins, rather than in each
/// feature's `providers.dart`, because the canvas and the timeline must agree
/// on the answer and a feature may not import a sibling feature. Two copies of
/// one `??` is exactly how the timeline ends up drawing keyframe dots for a
/// track the canvas is not evaluating.
///
/// Never `animations.first` (docs/v3/01 §11) — `defaultAnimation` resolves the
/// id, so a stale pointer is null and renders the rest pose rather than
/// throwing on an empty list.
final activeAnimationProvider =
    Provider.autoDispose.family<AnimationId?, String>((ref, projectId) {
  final override =
      ref.watch(editorControllerProvider.select((s) => s.activeAnimation));
  if (override != null) return override;
  return ref.watch(documentControllerProvider(projectId)
      .select((d) => d.valueOrNull?.defaultAnimation?.id));
});
