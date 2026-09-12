import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common/editor_toast.dart';
import 'common/theme.dart';
import 'common/ui_prefs.dart';
import 'data/project_store.dart';
import 'features/canvas/commands.dart';
import 'features/canvas/widgets/canvas_view.dart';
import 'features/export/providers.dart';
import 'features/guide/widgets/guide_dialog.dart';
import 'features/inspector/widgets/inspector_panel.dart';
import 'features/layers/commands.dart';
import 'features/layers/providers.dart';
import 'features/layers/widgets/layers_panel.dart';
import 'features/timeline/widgets/timeline_bar.dart';
import 'features/tools/widgets/tool_rail.dart';
import 'features/transport/widgets/transport_bar.dart';
import 'state/command.dart';
import 'state/document_controller.dart';
import 'state/editor_controller.dart';
import 'state/save_state.dart';
import 'state/tool_controller.dart';

/// Screen 2 — the editor (docs/v3/05 §2).
///
/// **This file is not a feature, and that is the point.** The panels — canvas,
/// layers, inspector, timeline — may not import one another
/// (`tool/check_boundaries.dart` rejects it), so the one file that *composes*
/// them sits a level up. Deleting a panel is one import and one folder here, and
/// the compiler finds every loose end — the kill switch docs/v3/08 §5 prefers
/// over a feature-flag registry. The same reasoning puts the **global keyboard
/// shortcuts** here (docs/v3/05 §5): `Cmd/Ctrl+Z`, `Cmd/Ctrl+G` and
/// `Cmd/Ctrl+D` must fire while the pointer is on the canvas, so they cannot
/// live inside the panel that owns the command — the shell is the only scope
/// that contains every panel.
///
/// **The docs/v3/05 §2 layout:** a left LAYERS rail, the centre CANVAS, a right
/// INSPECTOR rail, and the TIMELINE below. **Every panel gets explicit
/// constraints from its parent** — fixed-width side rails, an `Expanded` canvas,
/// a fixed-height timeline (docs/v3/08 §2, last row). An unconstrained slot is
/// what makes the fallback `ErrorWidget` throw a *second* time during layout, and
/// that second throw is the white screen; a dead panel here leaves the rest of
/// the editor usable.
///
/// **The shell no longer hands the document down.** It is still the only place
/// that touches the whole `AsyncValue<Document>` — but only in the *chrome*
/// (title, rev, undo/redo), which is allowed to rebuild once per commit because
/// that is what it is displaying. The body is reached through a slice that
/// projects the async wrapper to a **phase**, so an ordinary document emission
/// compares equal and stops there. Handing `document` to an inline
/// `_EditorBody` (as this file used to) re-created `LayersPanel`,
/// `InspectorPanel`, `TimelineBar` and `CanvasView` on **every** commit —
/// none can be `const`, `projectId` being a runtime value — and a widget whose
/// parent rebuilt rebuilds regardless of how carefully its own `.select` slices
/// refuse to notify. That is docs/v3/08 §2's "an anchor commit rebuilding
/// layers + inspector + timeline", verbatim, and it fired once per keystroke
/// committed in the inspector.
///
/// The async wrapper is consumed with `.when`, never `.requireValue`, because a
/// `.requireValue` on the first frame throws at every `ref.watch` and takes the
/// tree with it (docs/v3/08 §2).
class EditorShell extends ConsumerStatefulWidget {
  const EditorShell({required this.projectId, super.key});

  final String projectId;

  /// Fixed rather than a flex share (docs/v3/08 §2, last row). The rails do not
  /// steal width from the canvas as names grow, and the timeline does not grow
  /// into the canvas as keys are added.
  static const double layersWidth = 248.0;
  static const double inspectorWidth = 260.0;

  /// The timeline's **default** height — the ruler plus three rows, enough to
  /// see that keys exist and where in time they sit.
  ///
  /// It is the one panel whose right size depends on the document rather than on
  /// the layout: four animated layers is twenty rows, and scrolling a 84-px
  /// window to find a key is how a timeline stops being a timeline. So it is
  /// draggable between [timelineMinHeight] and [timelineMaxHeight] — still a
  /// fixed constraint handed down by this parent at any instant (docs/v3/08 §2,
  /// last row), just one the user picks. The value is remembered per browser
  /// through [UiPrefs].
  static const double timelineHeight = 120.0;

  /// The floor: the readout, the ruler with its scale and handle, and one row.
  /// Below this the panel can no longer show what it is for, and the drag would
  /// silently become a hide.
  static const double timelineMinHeight = 96.0;

  /// The ceiling, further clamped by [workspaceFloor] on a short window — an
  /// editor whose canvas has been squeezed to nothing is not recoverable by the
  /// same drag that caused it, because the handle would be off screen.
  static const double timelineMaxHeight = 420.0;

  /// What the editor above the timeline needs before something in it starts to
  /// overflow, and therefore the real limit on this drag.
  ///
  /// It is a *measured* number, not a guess: the app bar (56) plus the tool
  /// rail's six fixed 52-px buttons and their padding (318) plus the transport
  /// row (48), leaving a canvas still worth looking at. The rail is the binding
  /// constraint — it is a `Column` of fixed buttons with nowhere to scroll, so
  /// the first thing a too-tall timeline breaks is the toolbar, and it breaks
  /// with a layout assertion rather than a scrollbar.
  static const double workspaceFloor = 396.0;

  /// The TRANSPORT row (docs/v3/05 §2), between the canvas and the timeline.
  /// Fixed like the timeline, and for the same reason (docs/v3/08 §2, last row):
  /// an unconstrained slot is what makes the fallback `ErrorWidget` throw again
  /// during layout — the literal white screen.
  static const double transportHeight = 48.0;

  @override
  ConsumerState<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends ConsumerState<EditorShell> {
  /// Flushes a pending autosave when the tab is hidden or the app is torn down,
  /// so an edit still inside the debounce window survives a close (AC-10.3.1's
  /// data-safety half). `AppLifecycleListener` is the portable, test-reachable
  /// hook — `onHide`/`onDetach` fire on a web tab-visibility change and close —
  /// so no web-only `beforeunload` interop is needed.
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: _flushPending,
      onPause: _flushPending,
      onDetach: _flushPending,
    );
    // After the first frame, so the guide opens over a drawn editor rather than
    // over a blank route — and so `showDialog` has a `Navigator` above it.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_maybeShowGuide()));
  }

  /// Open the guide once, for someone who has never opened the editor
  /// (docs/v3/00 §5's stranger). Every visit after that is button-only — a
  /// modal that returns is a modal people learn to dismiss without reading.
  ///
  /// **Marked seen before it is shown, not after.** The alternative re-nags
  /// anyone who closes the tab while it is open, and there is nothing in the
  /// dialog to lose by being early. A storage failure reads as "seen" for the
  /// same reason: a broken preference must not produce a modal on every load.
  Future<void> _maybeShowGuide() async {
    final prefs = ref.read(uiPrefsProvider);
    final seen = await readPref(prefs.guideSeen, 'guideSeen') ?? true;
    if (seen || !mounted) return;
    await writePref(() => prefs.setGuideSeen(true), 'guideSeen');
    if (!mounted) return;
    await showEditorGuide(context);
  }

  void _flushPending() {
    // Fire-and-forget: the app may be going away, and a no-op when nothing is
    // pending.
    ref.read(documentControllerProvider(widget.projectId).notifier).flushNow();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    // Nothing is watched at this level, so this widget builds once per open and
    // the body it hands down keeps its identity across every commit.
    return Scaffold(
      appBar: AppBar(
        title: _ChromeTitle(projectId: projectId),
        actions: [
          _SaveIndicator(projectId: projectId),
          _ChromeActions(projectId: projectId),
          // Always enabled, and deliberately outside `_ChromeActions`: the
          // guide needs no document, and the moment it is most wanted is the
          // moment nothing has loaded yet.
          const GuideButton(),
          const ThemeToggleButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: _EditorBodyGate(projectId: projectId),
    );
  }
}

/// Reverse the last edit, then put the captured editing keyframe back on
/// `EditorState` (docs/v3/04 §6). The controller hands the [Restore] back rather
/// than reaching into `EditorController` itself, keeping the two peers
/// uncoupled; the viewport is never restored — undo does not move the camera.
///
/// **A save failure surfaces on the indicator, not here.** Since M7 the autosave
/// is debounced and a failed write is *retained in memory* with the chrome's
/// error indicator (AC-10.3.4); `DocumentController.undo` no longer re-saves the
/// snapshot synchronously and no longer rethrows a store failure. The `catch`
/// below is therefore a defensive net — it does not fire on an ordinary save
/// failure, only on an *unexpected* rejection, so that even then nothing escapes
/// as an unhandled async error (docs/v3/08 §1). The messenger is captured
/// **before** the await because a `BuildContext` may not be used across an async
/// gap, exactly as [_reportShortcut] captures it.
Future<void> _undo(
    BuildContext context, WidgetRef ref, String projectId) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final restore =
        await ref.read(documentControllerProvider(projectId).notifier).undo();
    if (restore != null) {
      ref
          .read(editorControllerProvider.notifier)
          .restoreKeyframe(restore.selectedKeyframe);
    }
  } on StoreException catch (e) {
    showEditorToast(messenger, e.failure.message);
  }
}

/// The mirror of [_undo]; its `catch` is the same defensive net, not the
/// ordinary save-failure path (which is the indicator).
Future<void> _redo(
    BuildContext context, WidgetRef ref, String projectId) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final restore =
        await ref.read(documentControllerProvider(projectId).notifier).redo();
    if (restore != null) {
      ref
          .read(editorControllerProvider.notifier)
          .restoreKeyframe(restore.selectedKeyframe);
    }
  } on StoreException catch (e) {
    showEditorToast(messenger, e.failure.message);
  }
}

/// `Export .json` — download the current document as native v3 JSON (F11.1,
/// docs/v3/05 §4.10).
///
/// **One serializer, no parallel path (AC-11.1.3).** The bytes are exactly
/// `jsonEncode(doc.toJson())` — the same `Document.toJson` persistence writes —
/// so an exported file re-opens identically (AC-11.1.2) and `schemaVersion`
/// rides along for free (AC-11.1.1). Native JSON only; SVG/Lottie are v2 and are
/// not even stubbed (AC-11.1.4).
///
/// A pending autosave is flushed first (docs/v3/05 §4.10 step 1) so the file the
/// user gets is the file that will be on disk, not one debounce behind. The
/// actual save-as is reached through [downloadJsonProvider] rather than called
/// directly: that seam keeps this logic testable on the VM (a test overrides it
/// to capture the bytes) and confines `package:web` to the web build. The
/// messenger is captured before the await because a `BuildContext` may not cross
/// an async gap, exactly as [_undo] captures it.
Future<void> _export(
    BuildContext context, WidgetRef ref, String projectId) async {
  final messenger = ScaffoldMessenger.of(context);
  final download = ref.read(downloadJsonProvider);
  try {
    // Flush any debounced edit so the export matches what persistence will hold.
    await ref
        .read(documentControllerProvider(projectId).notifier)
        .flushNow();
    final doc = ref.read(documentControllerProvider(projectId)).valueOrNull;
    if (doc == null) return;
    final name = doc.name.trim();
    final base = name.isEmpty ? doc.id : name;
    download('${_safeFileStem(base)}.json', jsonEncode(doc.toJson()));
  } on StoreException catch (e) {
    showEditorToast(messenger, e.failure.message);
  }
}

/// Reduce a display name to something a browser will accept as a file stem:
/// path separators and control characters become `-`. Not identity — two
/// projects may share a name (see [Document.name]) — just a safe download label.
String _safeFileStem(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-').trim();
  return cleaned.isEmpty ? 'document' : cleaned;
}

/// The project name in the app bar. Its own `.select`, so a rev bump alone does
/// not rebuild it.
class _ChromeTitle extends ConsumerWidget {
  const _ChromeTitle({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(documentControllerProvider(projectId)
        .select((async) => async.valueOrNull?.name ?? 'Editor'));
    return Text(name);
  }
}

/// Undo, redo and the `rev` readout.
///
/// **This is the one widget that watches the whole `AsyncValue<Document>`** —
/// and it may, because it is chrome that *displays* the commit: `rev` changes on
/// every save and the undo labels change on every command. It is three small
/// widgets, and it is deliberately a sibling of the body rather than its
/// ancestor, so its rebuild reaches nothing else.
class _ChromeActions extends ConsumerWidget {
  const _ChromeActions({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(documentControllerProvider(projectId)).valueOrNull;
    if (doc == null) return const SizedBox.shrink();
    final controller = ref.read(documentControllerProvider(projectId).notifier);
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('editor-undo'),
          tooltip: controller.undoLabel == null
              ? 'Undo'
              : 'Undo ${controller.undoLabel}',
          icon: const Icon(Icons.undo, size: 18),
          onPressed:
              controller.canUndo ? () => _undo(context, ref, projectId) : null,
        ),
        IconButton(
          key: const Key('editor-redo'),
          tooltip: controller.redoLabel == null
              ? 'Redo'
              : 'Redo ${controller.redoLabel}',
          icon: const Icon(Icons.redo, size: 18),
          onPressed:
              controller.canRedo ? () => _redo(context, ref, projectId) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Center(
            child: Text(
              'rev ${doc.rev}',
              key: const Key('editor-rev'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        // docs/v3/05 §2's `[Export .json]` chrome (AC-11.1.1). Enabled whenever a
        // document is loaded — which, inside this widget, it always is (the
        // `doc == null` guard above returned early).
        TextButton.icon(
          key: const Key('editor-export'),
          onPressed: () => _export(context, ref, projectId),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Export .json'),
        ),
      ],
    );
  }
}

/// The autosave status (docs/v3/03 AC-10.3.3): always exactly one of
/// **saved / dirty / saving / error**, and on failure it shows error while the
/// edit stays in memory — no modal (AC-10.3.4).
///
/// A leaf that watches only the `SaveState` notifier, so a status change repaints
/// this chip and nothing else — the same discipline as the playhead. It never
/// watches the document, so a scrub or an ordinary commit does not rebuild it.
class _SaveIndicator extends ConsumerWidget {
  const _SaveIndicator({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(saveStateProvider(projectId));
    return ValueListenableBuilder<SaveState>(
      valueListenable: notifier,
      builder: (context, save, _) {
        final scheme = Theme.of(context).colorScheme;
        final (IconData icon, String label, Color color) = switch (save.phase) {
          SavePhase.saved => (
              Icons.cloud_done_outlined,
              'Saved',
              scheme.onSurfaceVariant
            ),
          SavePhase.dirty => (
              Icons.cloud_queue,
              'Unsaved',
              scheme.onSurfaceVariant
            ),
          SavePhase.saving => (
              Icons.cloud_sync_outlined,
              'Saving…',
              scheme.onSurfaceVariant
            ),
          SavePhase.error => (
              Icons.cloud_off_outlined,
              'Save failed',
              scheme.error
            ),
        };
        final tooltip = switch (save.phase) {
          SavePhase.error =>
            save.failure?.message ?? 'The last change could not be saved.',
          SavePhase.saved when save.lastSaved != null => 'All changes saved',
          _ => label,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Tooltip(
            message: tooltip,
            child: Row(
              key: Key('save-indicator-${save.phase.name}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12, color: color)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Which of the three body states is on screen — loading, error, or the panels.
///
/// A value type so the `.select` below dedups: every ordinary commit projects to
/// the same `ready` phase and rebuilds nothing.
@immutable
class _BodyPhase {
  const _BodyPhase._(this.ready, this.error);

  static const _BodyPhase loading = _BodyPhase._(false, null);
  static const _BodyPhase data = _BodyPhase._(true, null);
  const _BodyPhase.failed(String message) : this._(false, message);

  final bool ready;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is _BodyPhase && other.ready == ready && other.error == error;

  @override
  int get hashCode => Object.hash(ready, error);
}

/// Loading / error / panels, chosen from a **phase slice** rather than from the
/// document itself (see [EditorShell]'s note on the rebuild storm).
class _EditorBodyGate extends ConsumerWidget {
  const _EditorBodyGate({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final phase =
        ref.watch(documentControllerProvider(projectId).select((async) {
      return async.when(
        loading: () => _BodyPhase.loading,
        error: (e, _) => _BodyPhase.failed(e is StoreException
            ? e.failure.message
            : 'Could not open this project.'),
        data: (_) => _BodyPhase.data,
      );
    }));

    if (phase.ready) return _EditorBody(projectId: projectId);

    final error = phase.error;
    if (error == null) {
      return const Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          error,
          key: const Key('editor-error'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// The composed panels, holding **only `projectId`**.
///
/// It closes over no `Document`. The read-only banner reads its own two-field
/// slice, so the one thing here that depends on the document rebuilds when
/// *that* changes and at no other time.
class _EditorBody extends ConsumerWidget {
  const _EditorBody({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // A record compares by value, so this is a dedupping slice like any other.
    final banner = ref.watch(documentControllerProvider(projectId).select((a) {
      final doc = a.valueOrNull;
      return (
        readOnly: doc?.isReadOnly ?? false,
        version: doc?.schemaVersion ?? Document.currentSchemaVersion,
      );
    }));

    // docs/v3/05 §5's Edit section, in the one scope that contains every panel.
    // The canvas's own `Focus` returns `ignored` for these keys, so the event
    // bubbles here; both meta (macOS) and control (elsewhere) are bound because
    // the app ships to whichever the visitor is on.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            _undo(context, ref, projectId),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            _undo(context, ref, projectId),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            () => _redo(context, ref, projectId),
        const SingleActivator(LogicalKeyboardKey.keyZ,
            control: true, shift: true): () => _redo(context, ref, projectId),
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
            _group(context, ref, projectId),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
            _group(context, ref, projectId),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () =>
            _duplicate(context, ref, projectId),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
            _duplicate(context, ref, projectId),
        // docs/v3/05 §5's tool bindings. They live here, beside the panel row
        // that contains the rail and the canvas, because a tool switch must fire
        // while the pointer is anywhere in the editor — and because the rail
        // and these keys must call the **same** `activate`, or the highlighted
        // button and the live tool drift apart.
        for (final entry in kToolButtons.entries)
          SingleActivator(_toolKeys[entry.key] ?? LogicalKeyboardKey.keyV):
              () => _activate(ref, entry.key),
        // docs/v3/05 §5 — `Del` / `Backspace` removes the selected anchor(s) with
        // Direct select (AC-4.3.5). Bound here beside the other canvas keys and in
        // the same scope; the handler refuses while a text field has focus and
        // does nothing unless Direct select has an anchor selected — node-level
        // Del is a separate, still-unscheduled gap (docs/v3/06 M5).
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _deleteAnchors(context, ref, projectId),
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _deleteAnchors(context, ref, projectId),
        // docs/v3/05 §5 & §"Enter is resolved by focus": `Enter` is play/pause —
        // NOT `Space`, which is pan. It reaches here only when the canvas has NOT
        // consumed it: with the canvas focused the pen owns `Enter` (its `_onKey`
        // returns `handled`), so the event bubbles to this scope only when the
        // canvas is unfocused. The transport `Ticker` lives in the panel, but the
        // toggle is shared state, so the shortcut flips `playing` and the panel's
        // `ref.listen` starts/stops the Ticker.
        const SingleActivator(LogicalKeyboardKey.enter): () => _togglePlay(ref),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            _togglePlay(ref),
        // The conventional help key, and the only binding here that is safe
        // while a text field has focus — `F1` types no character, so it needs
        // no `_typingInAField` guard.
        const SingleActivator(LogicalKeyboardKey.f1): () =>
            unawaited(showEditorGuide(context)),
      },
      // **The scope that catches released focus** (docs/v3/05 §5).
      //
      // `CallbackShortcuts` only sees a key event that travels up from the
      // primary focus, so a shortcut with nothing focused inside the editor
      // silently dies — the failure mode the Flutter Web conflicts table names.
      // Every numeric field here `unfocus()`es on commit (so `Cmd/Ctrl+Z`
      // reaches the editor and not the browser's text-field undo), and
      // `unfocus()` hands focus to the nearest enclosing **scope**: without one
      // inside the editor, that is the app's root scope and the very next
      // Cmd/Ctrl+Z, +G or +D reaches nothing at all. With it, focus lands back
      // here. `autofocus` is what makes the shortcuts live on the first frame,
      // before the user has clicked anything.
      child: FocusScope(
        autofocus: true,
        debugLabel: 'editor-shortcuts',
        child: Column(
          children: [
            // docs/v3/02 §1 rule 7's user-facing half. `DocumentController._save`
            // is what actually refuses the write — the gate belongs at the one
            // place a write happens — but a refusal the user only discovers by
            // dragging something and reading a snackbar is a trap, so the state is
            // on screen before they touch anything.
            if (banner.readOnly) _ReadOnlyBanner(version: banner.version),
            Expanded(
              child: Row(
                children: [
                  // The tool rail, left of everything, exactly as docs/v3/05 §2
                  // draws it. It is modal state and nothing else — it never
                  // reads the selection or the document.
                  const ToolRail(),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  SizedBox(
                    width: EditorShell.layersWidth,
                    child: LayersPanel(projectId: projectId),
                  ),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  // The canvas and, directly beneath it, the TRANSPORT row
                  // (docs/v3/05 §2: below the canvas, above the timeline). It is
                  // stacked in the **centre column** rather than spanning the
                  // whole width, on purpose: a full-width strip would shorten the
                  // side rails, and the inspector's field list is a lazy
                  // `ListView` whose bottom fields stop building the moment its
                  // viewport loses ~50 px (docs/v3/08 §2's "constraints from the
                  // parent" cuts both ways — a panel silently dropping controls is
                  // as bad as one overflowing). Keeping the rails full height
                  // leaves the timeline the one full-width strip below.
                  //
                  // Both slots take an explicit constraint from this parent
                  // (docs/v3/08 §2): an unconstrained one makes the fallback
                  // ErrorWidget throw again during layout — the white screen.
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: CanvasView(projectId: projectId)),
                        Divider(height: 1, color: scheme.outlineVariant),
                        SizedBox(
                          height: EditorShell.transportHeight,
                          child: TransportBar(projectId: projectId),
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: scheme.outlineVariant),
                  SizedBox(
                    width: EditorShell.inspectorWidth,
                    child: InspectorPanel(projectId: projectId),
                  ),
                ],
              ),
            ),
            _TimelinePane(projectId: projectId),
          ],
        ),
      ),
    );
  }
}

/// The bare-letter tool bindings of docs/v3/05 §5, keyed by the tool they
/// select. `V` `A` `P` `R` `O` `G` — Figma/Illustrator convention, so the tool
/// is learnable without documentation.
const Map<ToolId, LogicalKeyboardKey> _toolKeys = <ToolId, LogicalKeyboardKey>{
  ToolId.select: LogicalKeyboardKey.keyV,
  ToolId.directSelect: LogicalKeyboardKey.keyA,
  ToolId.pen: LogicalKeyboardKey.keyP,
  ToolId.rect: LogicalKeyboardKey.keyR,
  ToolId.ellipse: LogicalKeyboardKey.keyO,
  ToolId.polygon: LogicalKeyboardKey.keyG,
};

/// Switch tools — the same call the rail's buttons make.
///
/// **Refused while a text field has focus.** These are unmodified letters, and
/// `CallbackShortcuts` sees a key event that travels up from the primary focus
/// whether or not an `EditableText` is going to turn it into a character. Without
/// this gate, renaming a layer to "Gear" silently selected the polygon tool on
/// the `G` — the shortcut firing *and* the letter being typed, which reads as
/// the editor having a mind of its own.
void _activate(WidgetRef ref, ToolId id) {
  if (_typingInAField()) return;
  ref.read(toolControllerProvider.notifier).activate(id);
}

/// `Enter` — play/pause (docs/v3/05 §5). `playing` is ephemeral, so this is a
/// pure `EditorController` write: no `Command`, no save, nothing serialized.
///
/// **Refused while a text field has focus** (the same `_typingInAField` guard
/// the tool letters use). Committing the duration field or a layer rename with
/// `Enter` must not also toggle playback; and `Enter` in a single-line field is
/// consumed by the field before it could bubble here anyway, so this is the belt
/// to that braces.
void _togglePlay(WidgetRef ref) {
  if (_typingInAField()) return;
  ref.read(editorControllerProvider.notifier).togglePlaying();
}

/// True when the primary focus is inside an [EditableText].
///
/// The ancestor walk is the load-bearing part. A `TextField`'s focus node is
/// attached by a `Focus` widget **inside** `EditableText`'s own subtree, so the
/// node's context is that `Focus` — testing `context.widget is EditableText`
/// alone is always false and the guard silently does nothing, which is worse
/// than no guard because it reads as one.
bool _typingInAField() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// `Del` / `Backspace` — remove the selected anchor(s) with the Direct-select
/// tool (docs/v3/05 §5, AC-4.3.5).
///
/// Each anchor is one [DeleteAnchorCommand], and therefore **one undo entry**:
/// `PathOps.deleteAnchor` writes the removal into the node's `PathData` and into
/// every keyframe of every path track for the node in a single `Document →
/// Document` (the floor is the legal empty path). It routes through the canvas's
/// command gate, exactly like an anchor drag, so a rejected edit surfaces the
/// same way.
///
/// **Refused while a text field has focus** (the same `_typingInAField` guard the
/// tool letters use — `CallbackShortcuts` sees the key travel up from an
/// `EditableText` before the field turns it into a delete), and **only** with
/// Direct select active over a non-empty anchor selection. **Node-level Del —
/// deleting a whole node — is a separate, still-unscheduled gap** and is
/// deliberately not handled here: with no anchor selected this does nothing, so
/// the two cannot collide.
///
/// The anchor selection is cleared afterwards. It is resolved-not-repaired
/// (docs/v3/08 §2) — a dangling id would be filtered at every read site anyway —
/// but the delete is the one moment we know the id is gone, and clearing it is the
/// same shape as the timeline's clear-on-remove (AC-4.2.3).
void _deleteAnchors(BuildContext context, WidgetRef ref, String projectId) {
  if (_typingInAField()) return;
  if (ref.read(toolControllerProvider).id != ToolId.directSelect) return;

  final editor = ref.read(editorControllerProvider);
  final anchors = editor.selectedAnchors;
  if (anchors.isEmpty) return;
  final doc = ref.read(documentControllerProvider(projectId)).valueOrNull;
  if (doc == null) return;

  final commands = CanvasCommands(ref, projectId);
  final keyframe = editor.selectedKeyframe;
  var acted = false;
  for (final anchor in anchors) {
    final owner = _ownerOf(doc, anchor);
    if (owner == null) continue; // resolved, never repaired: a dangling id
    acted = true;
    _reportShortcut(context,
        commands.run(DeleteAnchorCommand(owner, anchor), keyframe: keyframe));
  }
  if (acted) {
    ref.read(editorControllerProvider.notifier).selectAnchor(null);
  }
}

/// The [PathNode] whose topology holds [anchor], or null. `AnchorId`s are unique
/// within a `PathData` and minted as UUIDs, so the first match owns it.
NodeId? _ownerOf(Document doc, AnchorId anchor) {
  for (final node in doc.nodeIndex.values) {
    if (node is PathNode && node.path.anchors.any((a) => a.id == anchor)) {
      return node.id;
    }
  }
  return null;
}

/// `Cmd/Ctrl+G` — group the current multi-selection (docs/v3/05 §4.5 step 4,
/// §5).
///
/// Reads the gate with `ref.read`, never `ref.watch`: watching the selection
/// here would rebuild the whole panel row on every click, which is the defect
/// this file was just restructured to remove. A blocked group **says why** —
/// `CreateGroupCommand` has real preconditions, and a shortcut that silently
/// does nothing is indistinguishable from an unbound key.
void _group(BuildContext context, WidgetRef ref, String projectId) {
  final actions = ref.read(layersActionsProvider(projectId));
  final blocked = actions.groupBlockedReason;
  if (blocked != null) {
    _toast(context, blocked);
    return;
  }
  _reportShortcut(
      context, LayersCommands(ref, projectId).group(actions.groupMembers));
}

/// `Cmd/Ctrl+D` — duplicate the selected subtree as ONE undo entry
/// (docs/v3/05 §5, AC-2.1.5).
void _duplicate(BuildContext context, WidgetRef ref, String projectId) {
  final actions = ref.read(layersActionsProvider(projectId));
  final target = actions.duplicateTarget;
  if (target == null) {
    _toast(context, actions.duplicateBlockedReason ?? 'Nothing to duplicate.');
    return;
  }
  _reportShortcut(context, LayersCommands(ref, projectId).duplicate(target));
}

void _toast(BuildContext context, String message) =>
    showEditorToast(ScaffoldMessenger.of(context), message);

/// Same contract as the panel's reporter: capture the messenger before the
/// await, and handle `onError` so a rejected edit can never escape as an
/// unhandled async error (docs/v3/08 §1).
void _reportShortcut(BuildContext context, Future<String?> pending) {
  final messenger = ScaffoldMessenger.of(context);
  void show(String message) => showEditorToast(messenger, message);
  pending.then(
    (message) {
      if (message != null) show(message);
    },
    onError: (Object _, StackTrace __) => show(kRejectedLayerEditMessage),
  );
}

/// Says which build wrote the file, because "read-only" without a reason reads
/// as a bug in this build rather than as a newer document.
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.version});

  final int version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: scheme.tertiaryContainer,
      child: Text(
        'Read-only — this project was written by a newer editor '
        '(schema $version, this build reads ${Document.currentSchemaVersion}). '
        'Edits will not be saved.',
        key: const Key('editor-readonly'),
        style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer),
      ),
    );
  }
}

/// The timeline, with the **drag handle that sets its height**.
///
/// Its own widget for the reason everything else in this file is: the height is
/// live state, and a `setState` at the shell level would rebuild the canvas, the
/// rails and the timeline on every pointer move of the drag — the rebuild storm
/// [EditorShell] was restructured to remove. So the height is a
/// `ValueNotifier` and only the `SizedBox` listens; `TimelineBar` is passed as
/// the builder's `child`, so it keeps its identity (and its expansion state,
/// its focus and its scroll offset) across the whole drag and is re-*laid out*
/// rather than rebuilt.
///
/// The pane still hands the timeline an explicit constraint at every instant,
/// which is what docs/v3/08 §2's last row actually asks for — an unconstrained
/// slot is what makes the fallback `ErrorWidget` throw again during layout.
class _TimelinePane extends ConsumerStatefulWidget {
  const _TimelinePane({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_TimelinePane> createState() => _TimelinePaneState();
}

class _TimelinePaneState extends ConsumerState<_TimelinePane> {
  final ValueNotifier<double> _height =
      ValueNotifier<double>(EditorShell.timelineHeight);

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void dispose() {
    // Back to the bottom edge: the next screen (the project list) has no
    // timeline for a toast to clear.
    setEditorBottomChrome(0);
    _height.dispose();
    super.dispose();
  }

  /// Adopt the remembered height on arrival. Starting at the default and
  /// adopting the stored value is the same shape [ThemeModeController] uses,
  /// and for the same reason: the editor must render before storage answers.
  Future<void> _restore() async {
    final prefs = ref.read(uiPrefsProvider);
    final stored = await readPref(prefs.timelineHeight, 'timelineHeight');
    if (!mounted || stored == null) return;
    _height.value = _clamp(stored, _ceiling(context));
  }

  void _persist() => unawaited(writePref(
      () => ref.read(uiPrefsProvider).setTimelineHeight(_height.value),
      'timelineHeight'));

  /// The most this window can give the timeline.
  ///
  /// [EditorShell.workspaceFloor] is what keeps the canvas, the transport row,
  /// the tool rail **and the handle itself** on screen: a drag that could hide
  /// its own handle is a one-way door, and one that overflows the rail turns a
  /// resize into a layout assertion. On a tall window the absolute
  /// [EditorShell.timelineMaxHeight] binds first instead — past roughly twenty
  /// rows a taller timeline is a scroll, not a view.
  static double _ceiling(BuildContext context) => math.max(
        EditorShell.timelineMinHeight,
        math.min(EditorShell.timelineMaxHeight,
            MediaQuery.sizeOf(context).height - EditorShell.workspaceFloor),
      );

  /// Total, like every other value that reaches a constraint: a NaN out of
  /// storage or out of a degenerate drag would propagate into `SizedBox` and
  /// take the layout with it, and `clamp` cannot rescue a NaN because every
  /// comparison against one is false.
  static double _clamp(double h, double ceiling) => h.isFinite
      ? h.clamp(EditorShell.timelineMinHeight, ceiling)
      : EditorShell.timelineHeight;

  @override
  Widget build(BuildContext context) {
    // Read in `build`, so this pane depends on the window size and a browser
    // resize re-clamps a height that no longer fits.
    final ceiling = _ceiling(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TimelineResizeHandle(
          // Dragging UP grows the timeline, which is the direction the edge
          // itself moves — the opposite mapping reads as a broken handle.
          onDrag: (dy) => _height.value = _clamp(_height.value - dy, ceiling),
          onDragEnd: _persist,
          onReset: () {
            _height.value = EditorShell.timelineHeight;
            _persist();
          },
        ),
        ValueListenableBuilder<double>(
          valueListenable: _height,
          // AC-13.1: the timeline gets its own raster layer, like the canvas, so
          // a scrub — which drives both the canvas and the timeline's playhead
          // marker via the shared notifier — repaints each in isolation and
          // neither forces the other's whole subtree to redraw. Passed as
          // `child` so a resize does not rebuild it at all.
          child:
              RepaintBoundary(child: TimelineBar(projectId: widget.projectId)),
          builder: (context, height, child) {
            final settled = _clamp(height, ceiling);
            // Publish the timeline's footprint so a toast floats above it
            // rather than over the rows the message is usually about. A
            // write-only assignment — nothing reads it until a toast is shown,
            // so it cannot feed back into this build.
            setEditorBottomChrome(settled + _handleHeight);
            return SizedBox(height: settled, child: child);
          },
        ),
      ],
    );
  }
}

/// The grip between the transport row and the timeline.
///
/// It is also the divider that used to be there: 8 px of hit area around a
/// 1-px line, which is the smallest target that can be hit without aiming and
/// the largest that does not read as a gap. Double-click restores the default,
/// so a drag is never a decision the user has to undo by eye.
/// The grip's own height, and therefore part of what a toast has to clear.
const double _handleHeight = 8.0;

class _TimelineResizeHandle extends StatefulWidget {
  const _TimelineResizeHandle({
    required this.onDrag,
    required this.onDragEnd,
    required this.onReset,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  @override
  State<_TimelineResizeHandle> createState() => _TimelineResizeHandleState();
}

class _TimelineResizeHandleState extends State<_TimelineResizeHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        key: const Key('timeline-resize'),
        behavior: HitTestBehavior.opaque,
        // `down` so the edge tracks the pointer exactly: with the default the
        // first 18 px of every drag are eaten by the touch slop and the handle
        // appears to lag behind the cursor it is supposed to be under.
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: (_) => widget.onDragEnd(),
        onDoubleTap: widget.onReset,
        child: Tooltip(
          message: 'Drag to resize the timeline · double-click to reset',
          waitDuration: const Duration(milliseconds: 600),
          child: Container(
            height: _handleHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Container(
              width: 44,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: _active ? scheme.primary : scheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
