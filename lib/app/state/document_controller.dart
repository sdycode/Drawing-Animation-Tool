import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_store.dart';
import '../data/providers.dart';

/// Owns the open document and nothing else (docs/v3/04 §4).
///
/// Selection, hover, the playhead and the viewport are **not** here — they are
/// ephemeral editor state, and persisting them is the legacy defect that made
/// documents unloadable (AC-2.2.7). This controller holds only what round-trips
/// to storage.
///
/// `Async` because the first thing it does is await IO (docs/v3/08 §2): the UI
/// consumes it with `.when`, so a failed load renders an error state instead of
/// throwing at every `ref.watch`.
class DocumentController
    extends AutoDisposeFamilyAsyncNotifier<Document, String> {
  @override
  Future<Document> build(String projectId) async {
    final raw = await ref.read(projectStoreProvider).load(projectId);
    if (raw == null) {
      throw const StoreException(StoreFailure.notFound);
    }
    try {
      return Document.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on StoreException {
      rethrow;
    } on Object catch (e) {
      // Anything undecodable is corrupt, not "unknown" — the user gets a real
      // sentence and the developer gets the raw reason.
      throw StoreException(StoreFailure.corrupt, details: '$e');
    }
  }

  /// The tail of the apply→save chain. **Every** mutation goes through it.
  ///
  /// Without it two commands issued while a save is in flight both branch from
  /// the same base `Document` — `state` is only assigned after the store
  /// returns — and the second write silently overwrites the first. Nothing
  /// throws, so `_guard` never fires and no snackbar appears; the user simply
  /// drags one anchor, drags another within ~200 ms, and the first drag is
  /// gone. It also undercounts `rev`, which must advance by exactly 1 per
  /// persisted save (docs/v3/01 §11) because v1.1's optimistic concurrency is
  /// built on that counter.
  ///
  /// This is the M0 shape of what docs/v3/04 §6 puts in `CommandStack.run`:
  /// serialising apply→save so an edit always branches from the document the
  /// previous edit actually persisted. When the stack lands at M2 it takes this
  /// chain over; the mutations below do not change.
  Future<void> _queue = Future<void>.value();

  /// Runs [edit] against the **latest persisted** document, then saves.
  ///
  /// [edit] is a pure `Document → Document` call and is invoked inside the
  /// chain, never at call time, so `state.requireValue` below is read after
  /// every earlier save has landed.
  Future<void> _mutate(Document Function(Document doc) edit) {
    final next = _queue.then((_) => _save(edit(state.requireValue)));
    // The chain must survive a failed link: a network error on one drag cannot
    // wedge every later edit. The error still reaches the caller through
    // [next], which is what the command layer catches.
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Appends a node to the root and persists.
  ///
  /// M0 has no `NodeOps` and no undo stack; both arrive at M2. The shape of the
  /// call is already right, though: a mutation produces a **new** `Document`
  /// rather than editing one in place, which is what makes snapshot undo a
  /// later addition instead of a rewrite.
  Future<void> addNode(Node node) => _mutate((doc) => doc.copyWith(
        root: doc.root.copyWith(children: [...doc.root.children, node]),
      ));

  /// Moves one anchor and persists — the pose edit of docs/v3/01 §12.
  ///
  /// [atT] `null` edits the node's rest pose; non-null writes the pose into the
  /// `PathTrack` keyframe at that `t`, seeding a `t = 0.0` key from the rest
  /// pose the first time, so a first drag at `t > 0` yields **two keys that
  /// differ**. All of that lives in [PathOps.moveAnchor] rather than here: this
  /// controller owns the document and the save, not path semantics. Duplicating
  /// even the seeding rule at a call site is how the pen tool and the timeline
  /// end up disagreeing about what a keyframe contains.
  ///
  /// [PathOps] throws [ArgumentError] on an invariant violation and this method
  /// does not catch it — loud failure is the product (docs/v3/08 §1). The catch
  /// belongs one layer out, at the feature's `commands.dart`, which is the
  /// command boundary M2 replaces with `CommandStack.run`.
  Future<void> moveAnchorAt(
    NodeId node,
    AnchorId anchor,
    Vec2 to, {
    double? atT,
  }) =>
      _mutate((doc) => PathOps.moveAnchor(doc, node, anchor, to, atT: atT));

  Future<void> rename(String name) =>
      _mutate((doc) => doc.copyWith(name: name));

  /// `rev` advances here and nowhere else, because this is the only place a
  /// write actually reaches storage (docs/v3/01 §11).
  ///
  /// It is also where docs/v3/02 §1 rule 7 is **enforced**: a document whose
  /// `schemaVersion` is newer than this build reads opens read-only and every
  /// save path is disabled. One gate, at the one place a write happens, rather
  /// than a check per command — a command added later cannot forget it.
  Future<void> _save(Document next) async {
    if (next.isReadOnly) {
      throw const StoreException(StoreFailure.readOnly);
    }
    final saved = next.bumpRev();
    await ref
        .read(projectStoreProvider)
        .save(saved.id, jsonEncode(saved.toJson()));
    state = AsyncData(saved);
  }
}

final documentControllerProvider = AsyncNotifierProvider.autoDispose
    .family<DocumentController, Document, String>(DocumentController.new);
