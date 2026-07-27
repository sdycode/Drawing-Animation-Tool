/// Every document mutation the canvas can cause, and the only place it catches.
///
/// docs/v3/08 §1: ops throw loudly and the **command layer** catches — one
/// catch, one site. Nothing here builds a new document by hand, and nothing here
/// touches `EditorState`: an op that grows a dependency on editor state inverts
/// docs/v3/04 §1 for every future op (docs/v3/08 §4).
///
/// **M3 collapsed four typed methods into [CanvasCommands.run].** The canvas no
/// longer knows which edit a gesture produces — the active [ToolMode] returns a
/// [Command] and this file runs it — so a method per edit here would have been a
/// method per tool, in a file the tools may not import. The gate is unchanged:
/// one `try`, one site, and a `Document → Document` command underneath it.
///
/// Commands return a **message or null**, never a `BuildContext` and never a
/// widget. The caller decides that a message means a `SnackBar`; this file
/// decides only what went wrong. That is what keeps the gesture handlers
/// testable without pumping a tree.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../state/command.dart';
import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';
import '../../state/recipe_guard.dart';

/// The message shown when an op rejected the edit.
///
/// An `ArgumentError` out of `PathOps` means the canvas asked for something the
/// document does not contain — a dangling anchor id, a node that has been
/// deleted. It is a programming error, so it also trips an `assert`; in release
/// the user gets a sentence and keeps their document instead of a red screen.
const String kRejectedEditMessage = 'That edit could not be applied.';

final class CanvasCommands {
  const CanvasCommands(this._ref, this._projectId);

  final WidgetRef _ref;
  final String _projectId;

  DocumentController get _controller =>
      _ref.read(documentControllerProvider(_projectId).notifier);

  /// Run a [Command] a tool produced — the **one** route from a gesture to the
  /// document.
  ///
  /// One command per completed gesture, never one per pointer event: the pen
  /// builds a whole [PathNode] and commits it on exit, a drag commits on
  /// release. That is what makes a 200-event drag one undo entry and one save
  /// (docs/v3/04 §6), and it is enforced in the tools — a tool that returned a
  /// command from `onPointerMove` would get 200 of each, and this method would
  /// dutifully run them all.
  ///
  /// [keyframe] is the editing keyframe live at gesture time, captured with the
  /// undo snapshot so undo returns the user to the key they were editing
  /// (docs/v3/04 §6). Null when nothing is selected — a rest-pose edit — which
  /// the snapshot reads as "carried none" rather than "clear the selection".
  Future<String?> run(Command command, {KeyframeRef? keyframe}) =>
      _guard(() => _controller.run(command, keyframe: keyframe));

  /// Regenerate a node's geometry from an edited [ShapeRecipe] (AC-4.1.5).
  ///
  /// Forks on **one predicate — does the node carry a `path` track?**
  /// ([hasPathTrack]), so the answer stays in `state/` where the inspector reads
  /// the same one to route its shape fields:
  ///
  /// - **Untracked** → [RegenerateRecipeCommand] regenerates in place, keeping the
  ///   recipe as inert metadata.
  /// - **Tracked** → in-place regeneration is unrepresentable (fresh `AnchorId`s
  ///   against keyframes posing the old ones), so it routes through
  ///   [RetopologizeCommand] — arc-length correspondence rewrites every keyframe
  ///   onto the recipe's new id set (AC-4.3.7) and clears the stale recipe. Once
  ///   per edit, from a command, never in the tick.
  ///
  /// A recipe with no geometry never takes the tracked branch: an [UnknownRecipe]
  /// builds none, and neither does a degenerate one (a `RectRecipe` with `w <= 0`,
  /// a `PolygonRecipe` with `sides < 3`) — its `toPath()` is empty. Retopologising
  /// onto an empty path rewrites every keyframe to an empty pose and silently
  /// erases the animation, so the fork also requires `toPath()` to carry anchors;
  /// a degenerate recipe falls through to [RegenerateRecipeCommand], which keeps
  /// the recipe (recoverable in place, exactly like the untracked case) and never
  /// touches the keyframes. This predicate is kept **identical** to the
  /// inspector's so the two features cannot route the same document two ways.
  ///
  /// **Call site:** the inspector's shape-parameter fields, which clamp the
  /// recipe past its floor first (`_clampShapeRecipe`), so this guard is the
  /// routing backstop, not a path legal input reaches. It lives in the canvas's
  /// command file because `PathOps` edits the geometry the canvas paints, and
  /// because the shape *tools* — which construct whole nodes and need no op at
  /// all — are the other half of AC-4.1.4 and are one feature away.
  Future<String?> regenerateRecipe(NodeId node, ShapeRecipe recipe) {
    final doc = _ref.read(documentControllerProvider(_projectId)).valueOrNull;
    if (doc == null) return Future<String?>.value(kRejectedEditMessage);
    if (hasPathTrack(doc, node) &&
        recipe is! UnknownRecipe &&
        recipe.toPath().anchors.isNotEmpty) {
      return run(RetopologizeCommand(node, recipe.toPath()));
    }
    return run(RegenerateRecipeCommand(node, recipe));
  }

  /// The one catch site.
  ///
  /// A failed save leaves the previous document in place and does **not** bump
  /// `rev` — the controller only assigns state after the store returns — so the
  /// editor stays usable and the file on disk stays valid. A Firestore hiccup
  /// freezing drawing is the least important feature blocking the most
  /// important one (docs/v3/08 §2, last row).
  static Future<String?> _guard(Future<void> Function() run) async {
    try {
      await run();
      return null;
    } on StoreException catch (e) {
      return e.failure.message;
    } on ArgumentError catch (e) {
      assert(false, 'canvas command rejected by an op: $e');
      return kRejectedEditMessage;
    }
  }
}
