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
/// Addresses one keyframe for edit-at-keyframe (docs/v3/01 §12). A bare record,
/// so it is structurally the same type as `command_stack.dart`'s `KeyframeRef`
/// without either file importing the other — undo can hand this back and it
/// drops straight into [EditorState.selectedKeyframe].
typedef KeyframeRef = (NodeId, PropertyKey, int);

@immutable
final class EditorState {
  const EditorState({
    this.playhead = 0.0,
    this.playing = false,
    this.selectedNodes = const <ScenePath>{},
    this.selectedAnchors = const <AnchorId>{},
    this.selectedKeyframe,
    this.viewportTransform = Affine.identity,
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

  /// The selected nodes, keyed by **`ScenePath`, not `NodeId`** (docs/v3/01 §11).
  ///
  /// Keying ephemeral state by `ScenePath` is what stops instancing colliding
  /// later — six expansions of one master must select independently, and
  /// `instancePath` (const `[]` in v1) is what tells them apart. Like every set
  /// here it is **resolved, never repaired** (docs/v3/08 §2): a dangling path
  /// (the node it named was deleted) is legal and filtered at each read site,
  /// never scrubbed out on delete — scrubbing is what makes undo unable to
  /// restore the selection it took away.
  final Set<ScenePath> selectedNodes;

  /// **Resolved, never repaired** (docs/v3/08 §2): a dangling id is legal here
  /// and is filtered at every read site. Scrubbing it out on delete is what
  /// would make undo unable to restore the selection it took away.
  final Set<AnchorId> selectedAnchors;

  /// The keyframe being edited, or null. Edit-at-keyframe is used in earnest at
  /// M4, but the field lives here now because undo is tied to it (docs/v3/04 §6):
  /// a snapshot captures it and undo restores it, so it belongs to the ephemeral
  /// state the snapshot pairs with — never to the document.
  final KeyframeRef? selectedKeyframe;

  /// Pan/zoom applied **on top of** the artboard fit (the canvas composes
  /// `viewportTransform ∘ artboardFit` — owner decision, docs/v3/05 §3), so the
  /// identity default means "just fit the artboard". It is **one** `Affine` —
  /// there is no second matrix and no per-axis scale helper anywhere (AC-3.1.4);
  /// hit-testing inverts this same composed matrix. It is **never serialized,
  /// never undoable, and undo never restores it** (docs/v3/04 §6): nothing is
  /// more disorienting than undo moving the camera.
  final Affine viewportTransform;

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
    Set<ScenePath>? selectedNodes,
    Set<AnchorId>? selectedAnchors,
    KeyframeRef? selectedKeyframe,
    bool clearSelectedKeyframe = false,
    Affine? viewportTransform,
    AnimationId? activeAnimation,
    bool clearActiveAnimation = false,
  }) =>
      EditorState(
        playhead: playhead ?? this.playhead,
        playing: playing ?? this.playing,
        selectedNodes: selectedNodes ?? this.selectedNodes,
        selectedAnchors: selectedAnchors ?? this.selectedAnchors,
        selectedKeyframe: clearSelectedKeyframe
            ? null
            : (selectedKeyframe ?? this.selectedKeyframe),
        viewportTransform: viewportTransform ?? this.viewportTransform,
        activeAnimation: clearActiveAnimation
            ? null
            : (activeAnimation ?? this.activeAnimation),
      );
}

class EditorController extends AutoDisposeNotifier<EditorState> {
  /// The project this ephemeral state belongs to, or null before anything has
  /// claimed it. Ephemeral state is per-*document* state that simply is not
  /// stored in the document, so carrying it from one project to the next is a
  /// leak: opening project two used to inherit project one's camera offset, its
  /// playhead, and a phantom selection of a node that is not in project two's
  /// tree at all.
  String? _projectId;

  @override
  EditorState build() => const EditorState();

  /// Bind this state to [projectId], resetting it when the open project
  /// changes.
  ///
  /// The provider is `autoDispose`, so the ordinary path already resets: the
  /// panels are its only watchers, and closing a project unmounts every one of
  /// them. This is the belt to that braces — it makes the reset explicit and
  /// survives a future where two projects are open without the editor ever
  /// unmounting. Nothing here is persisted, so AC-2.2.7 is untouched either way.
  void bindProject(String projectId) {
    if (_projectId == projectId) return;
    _projectId = projectId;
    state = const EditorState();
  }

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

  // --- Transport (M6) -------------------------------------------------------
  //
  // `playing` is EPHEMERAL: it is not a field of `Document` and never
  // serializes (the AC-2.2.7 split this whole controller exists to keep — a file
  // saved mid-playback must not carry a "playing" bit a reopen would honour).
  // The `Ticker` in the transport bar keys its lifecycle off this bit and is the
  // ONLY thing that moves the playhead; neither method below moves it. On PAUSE
  // the transport commits the settled playhead once via [commitPlayhead],
  // exactly as scrub-end does — the live value lived in `playheadProvider` (the
  // hot path) for the duration of play and never round-tripped through pixels or
  // a `BuildContext` (the legacy defect, docs/v3/04 §4).

  /// Flip play/pause — the play button and the shell's `Enter` both route here
  /// (AC-9.1.1, docs/v3/05 §5). `Enter`, not `Space`: `Space` is pan.
  void togglePlaying() => setPlaying(!state.playing);

  /// Set the transport play state. A no-op when unchanged, so a redundant flip
  /// notifies nothing.
  void setPlaying(bool playing) {
    if (state.playing == playing) return;
    state = state.copyWith(playing: playing);
  }

  void selectAnchor(AnchorId? anchor) {
    state = state.copyWith(
      selectedAnchors: anchor == null ? const <AnchorId>{} : <AnchorId>{anchor},
    );
  }

  // --- Node selection ------------------------------------------------------
  //
  // Selection is **stored, never checked** (docs/v3/08 §2). These methods do not
  // verify the path still resolves against the document; read sites filter a
  // dangling path. That is what keeps `NodeOps` free of `EditorState` — an op
  // that cleared selection "to be safe" would grow `anim_core` a dependency on
  // editor types and invert docs/v3/04 §1 for every future op.

  /// Replace the selection with [node], or clear it when [node] is null.
  void selectNode(ScenePath? node) {
    state = state.copyWith(
      selectedNodes: node == null ? const <ScenePath>{} : <ScenePath>{node},
    );
  }

  /// Add [node] to the selection (`Shift`+click, docs/v3/05 §3).
  void addToSelection(ScenePath node) {
    state = state.copyWith(
      selectedNodes: <ScenePath>{...state.selectedNodes, node},
    );
  }

  void clearSelection() {
    state = state.copyWith(selectedNodes: const <ScenePath>{});
  }

  /// Restore the keyframe captured with an undo/redo snapshot (docs/v3/04 §6).
  /// The document controller hands this back from `undo()`/`redo()`; wiring it
  /// here — rather than the document controller reaching across — keeps the two
  /// peers uncoupled.
  ///
  /// **A null [keyframe] means the snapshot carried none, and that is not the
  /// same as "clear it".** No call site passes `keyframe:` to `run()` yet
  /// (capturing it in earnest is M4), so every `Restore` carries null today —
  /// and this method used to read that null as an instruction and wipe the field
  /// the user was editing at. docs/v3/04 §6 says undo should return the user to
  /// where they were editing; when the snapshot cannot say where that was, the
  /// answer is to leave them where they are. Clearing is [clearKeyframe], which
  /// says so.
  void restoreKeyframe(KeyframeRef? keyframe) {
    if (keyframe == null) return;
    state = state.copyWith(selectedKeyframe: keyframe);
  }

  /// Enter edit-at-keyframe on key [index] of `(node, property)`, and **snap the
  /// playhead to that key** (AC-6.2.6, docs/v3/05 §2 "edit-at-keyframe, not
  /// record mode"). The next agent's canvas and inspector consume the resulting
  /// `selectedKeyframe`; this method is the one place it is set for editing.
  ///
  /// [snapT] is the key's own `t`, sampled from the document **by the caller** —
  /// this controller never reads a `Document` (docs/v3/04 §1), so it is told
  /// where the key is rather than looking it up. Omit it to select without
  /// moving the playhead (undo restores selection through [restoreKeyframe], not
  /// through here).
  ///
  /// **It settles the playhead in `EditorState` AND writes the live
  /// [playheadProvider] notifier.** The canvas paints at the notifier's value
  /// (`CustomPainter(repaint:)`, docs/v3/04 §4), so committing only the settled
  /// field would set edit-at-keyframe up correctly for the selection logic yet
  /// leave the shown frame behind the key — the canvas would not actually snap
  /// to it. Writing both is the same live/settled pair the scrub keeps in step
  /// (`.value` during the drag, `commitPlayhead` on release); a keyframe click
  /// settles both at once because it is not a drag.
  ///
  /// `selectedKeyframe` stays **ephemeral** — it is never in the document and
  /// never serialized (AC-6.2.6, and the AC-2.2.7 defect this whole controller
  /// exists to prevent).
  void selectKeyframe(NodeId node, PropertyKey property, int index,
      {double? snapT}) {
    final target = snapT ?? state.playhead;
    final clamped = target.isNaN ? 0.0 : target.clamp(0.0, 1.0);
    // Live first, so the canvas repaint and the settled state land on the same
    // frame; the notifier write invalidates no provider (the hot path).
    ref.read(playheadProvider).value = clamped;
    state = state.copyWith(
      selectedKeyframe: (node, property, index),
      playhead: clamped,
    );
  }

  /// Leave edit-at-keyframe — the explicit clear [restoreKeyframe] deliberately
  /// is not. This is `clearSelectedKeyframe` under the name it has carried since
  /// M2; the canvas/inspector call it when a pose edit finishes or the selection
  /// moves off a key.
  void clearKeyframe() {
    state = state.copyWith(clearSelectedKeyframe: true);
  }

  // --- Viewport (pan / zoom) ----------------------------------------------
  //
  // Ephemeral, never serialized, never undoable (AC-3.1.4, docs/v3/04 §6). One
  // `Affine`; the helpers compose it and never reach for a second matrix or a
  // per-axis scale. `viewportTransform` operates in the fitted-screen space the
  // canvas has already mapped the artboard into, so the maths below is plain
  // screen-space translate/scale.

  void setViewport(Affine viewport) {
    state = state.copyWith(viewportTransform: viewport);
  }

  /// Translate the viewport by a **screen-space** delta — the Pan tool (hold
  /// Space / middle-drag, docs/v3/05 §3). Mutates nothing but this field.
  void panBy(Vec2 deltaScreen) {
    state = state.copyWith(
      viewportTransform: Affine.translate(deltaScreen.x, deltaScreen.y)
          .mul(state.viewportTransform),
    );
  }

  /// Zoom about the cursor by [factor] — the Zoom tool (Cmd/Ctrl+scroll,
  /// docs/v3/05 §3). Scaling about [focusScreen] keeps the document point under
  /// the cursor fixed: pre- and post-compose the uniform scale with a translate
  /// to and from the focus, all in one `Affine`.
  void zoomAround(Vec2 focusScreen, double factor) {
    final about = Affine.translate(focusScreen.x, focusScreen.y)
        .mul(Affine.scale(factor, factor))
        .mul(Affine.translate(-focusScreen.x, -focusScreen.y));
    state = state.copyWith(
      viewportTransform: about.mul(state.viewportTransform),
    );
  }

  /// Fit the artboard (Cmd/Ctrl+0). Identity `viewportTransform` **is** the fit,
  /// because the canvas composes it over `artboardFit` which already letterboxes
  /// the artboard into the canvas — so fitting is resetting the pan/zoom on top.
  void fitArtboard() {
    state = state.copyWith(viewportTransform: Affine.identity);
  }

  /// 100% zoom about [focusScreen] (Cmd/Ctrl+1). The canvas passes [fitScale] —
  /// the uniform scale its `artboardFit` applied — and this cancels it, so one
  /// document unit maps to one screen pixel: net scale = `(1 / fitScale) ·
  /// fitScale = 1`.
  ///
  /// **It composes onto the live camera; it does not replace it.** Assigning a
  /// fresh matrix got the net scale right and the *focus wrong* — the whole
  /// point of "zoom about the cursor" is that the document point under the
  /// cursor does not move, and replacing the transform silently discards the pan
  /// that decided which point that was. On a 450.2 × 250.4 artboard in an
  /// 800 × 620 canvas, `panBy(100, 50)` then Cmd/Ctrl+1 at the canvas centre
  /// moved the point under the cursor by (-56.3, -28.1) px. So this is
  /// [zoomAround] with the factor that lands the *composed* scale on 1:
  /// `1 / (fitScale · currentScale)`. Cmd/Ctrl+0 remains the reset —
  /// [fitArtboard] is the only method that throws the camera away.
  void zoom100(double fitScale, Vec2 focusScreen) {
    // The viewport is a uniform scale by construction (AC-3.1.4: one `Affine`,
    // never a per-axis one), so `a` is the whole of the current zoom.
    final current = state.viewportTransform.a;
    final composed = fitScale * current;
    if (composed == 0 || !composed.isFinite) return;
    zoomAround(focusScreen, 1.0 / composed);
  }
}

/// **`autoDispose`, and that is the fix for the cross-project leak.**
///
/// A plain global provider kept selection, the playhead and the camera alive for
/// the whole session, so project two opened with project one's viewport offset,
/// its playhead, and a selection pointing at a node that does not exist in it —
/// harmless on disk (nothing here is ever serialized, AC-2.2.7 still holds) and
/// very confusing on screen. Every watcher is an editor panel, so the state now
/// lives exactly as long as an editor is on screen and a fresh open starts
/// fresh.
///
/// It stays a plain (non-family) provider on purpose: `activeAnimationProvider`
/// below and four feature providers read it with no project key, and keying it
/// would change the call signature in files this change may not touch — for the
/// same reason, [EditorController.bindProject] exists for callers that do know
/// the project id.
final editorControllerProvider =
    NotifierProvider.autoDispose<EditorController, EditorState>(
        EditorController.new);

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
