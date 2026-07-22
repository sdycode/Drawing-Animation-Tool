/// The canvas feature's named slices (docs/v3/08 §2).
///
/// A panel watching a whole document or editor provider with no `.select` is
/// banned, and this file is where that rule is kept honest: every widget under
/// `canvas/widgets/` watches one of these, never `documentControllerProvider`
/// itself. That is the direct antidote to legacy's 93 blind `updateUI()` call
/// sites — an anchor commit must not rebuild the layers panel, the inspector
/// and the timeline as a side effect of rebuilding the canvas.
library;

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';

/// The open document, or null while it is loading or failed.
///
/// The canvas is the one panel that legitimately reads the *whole* document —
/// it paints all of it — so the slice here is not a field projection but the
/// **collapse of `AsyncValue` to its value**. That is what it buys: the
/// loading→data and error→data transitions the shell renders with `.when` do
/// not reach the painters, so the canvas repaints when the geometry changes and
/// at no other time.
///
/// Null rather than `.requireValue`: the shell decides what "no document yet"
/// looks like, and a `.requireValue` here would throw at every `ref.watch` on
/// the first frame (docs/v3/08 §2).
final canvasDocumentProvider =
    Provider.autoDispose.family<Document?, String>((ref, projectId) {
  return ref.watch(
      documentControllerProvider(projectId).select((d) => d.valueOrNull));
});

/// The artboard's two painted values, so layer 1 does not watch the document.
///
/// `BackgroundPainter` repaints on artboard size and colour only. Handing it
/// the document instead would repaint the board on every anchor drag, because
/// document identity changes on every mutation — and the board has not changed
/// since the file opened. A record is used rather than a pair of providers
/// because records compare by value, which is exactly the signal `.select`
/// needs.
final canvasBackgroundProvider =
    Provider.autoDispose.family<(Vec2, Rgba)?, String>((ref, projectId) {
  return ref.watch(documentControllerProvider(projectId).select((d) {
    final doc = d.valueOrNull;
    return doc == null ? null : (doc.artboard, doc.background);
  }));
});

/// How many shapes the document holds — the tool hint's only document read.
///
/// A count, not the child list: the hint must not rebuild when a node moves,
/// only when one appears.
final canvasNodeCountProvider =
    Provider.autoDispose.family<int, String>((ref, projectId) {
  return ref.watch(documentControllerProvider(projectId)
      .select((d) => d.valueOrNull?.root.children.length ?? 0));
});

/// The pan/zoom the canvas composes over the artboard fit — a named slice of
/// `EditorState` (docs/v3/08 §2), so a marquee or a document mutation never
/// rebuilds the canvas *because of the viewport*, and a pan never invalidates a
/// slice that reads the `Document`.
///
/// **Ephemeral, never serialized, never undoable** (AC-3.1.4, docs/v3/04 §6).
/// The canvas feeds this into `composedFit` — the one place viewport∘artboardFit
/// is combined — and inverts that same matrix for hit-testing.
final canvasViewportProvider = Provider.autoDispose<Affine>((ref) {
  return ref.watch(editorControllerProvider.select((s) => s.viewportTransform));
});

/// The selected nodes, keyed by [ScenePath] (docs/v3/01 §11) — the slice the
/// overlay outlines and the Select tool's drag reads.
///
/// A slice, not the whole `EditorState`: selecting a node must not rebuild
/// anything that watches the playhead or the viewport, and vice versa. The set
/// is **resolved, never repaired** downstream — a dangling path is filtered at
/// each read site, never scrubbed here (docs/v3/08 §2).
final canvasSelectionProvider = Provider.autoDispose<Set<ScenePath>>((ref) {
  return ref.watch(editorControllerProvider.select((s) => s.selectedNodes));
});
