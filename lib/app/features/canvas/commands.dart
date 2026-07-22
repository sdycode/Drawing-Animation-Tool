/// Every document mutation the canvas can cause, and the only place it catches.
///
/// docs/v3/08 §1: ops throw loudly and the **command layer** catches — one
/// catch, one site. At M2 this file becomes calls into `CommandStack.run` and
/// gains undo for free, because every mutation below is already a pure
/// `Document → Document` call made by [DocumentController]. Nothing here builds
/// a new document by hand, and nothing here touches `EditorState`: an op that
/// grows a dependency on editor state inverts docs/v3/04 §1 for every future op
/// (docs/v3/08 §4).
///
/// Commands return a **message or null**, never a `BuildContext` and never a
/// widget. The caller decides that a message means a `SnackBar`; this file
/// decides only what went wrong. That is what keeps the gesture handlers
/// testable without pumping a tree.
library;

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../state/document_controller.dart';

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

  /// Commits a finished pen gesture as one closed [PathNode].
  ///
  /// The whole node is built and appended in one call, so a document never
  /// contains half a gesture — an unfinished shape is ephemeral editor state
  /// and a document holding one cannot be meaningfully reloaded.
  Future<String?> addPath(List<Vec2> points) {
    final node = PathNode(
      id: NodeId(uuidV4()),
      name: 'Path',
      // One fresh AnchorId per point. Minted here, once, and never derived from
      // the loop index — an index-derived id is the legacy defect wearing a
      // different hat, and it is what makes a keyframe pose join to the wrong
      // anchor after an insert.
      path: PathData(
        anchors: [
          for (final p in points) Anchor(id: AnchorId(uuidV4()), position: p),
        ],
        closed: true,
      ),
      fills: const [
        // One hard-coded colour at M0. A paint UI is M3.
        Fill(
          id: PaintId('p-body'),
          paint: SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0)),
        ),
      ],
      strokes: const [
        Stroke(
          id: PaintId('p-ink'),
          paint: SolidPaint(Rgba(0.05, 0.05, 0.08, 1.0)),
          width: 2.0,
          join: StrokeJoin.round,
        ),
      ],
    );
    return _guard(() => _controller.addNode(node));
  }

  /// **One** command per drag, issued on drag *end* (docs/v3/04 §6).
  ///
  /// A 200-event anchor drag is one entry, not 200. That is why the live
  /// position stays a private field of the tool and only the released position
  /// reaches here: a command per pointer move would make undo useless and would
  /// write 200 documents to storage.
  ///
  /// [atT] is the playhead. Non-null is the M0 exit criterion — the drag writes
  /// a `PathTrack` keyframe rather than the rest pose, and the first one seeds
  /// a `t = 0.0` key so there are two keys that differ.
  Future<String?> moveAnchorAt(
    NodeId node,
    AnchorId anchor,
    Vec2 to, {
    required double? atT,
  }) {
    return _guard(() => _controller.moveAnchorAt(node, anchor, to, atT: atT));
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
