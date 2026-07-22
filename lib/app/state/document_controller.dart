import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_store.dart';
import '../data/providers.dart';
import 'command.dart';
import 'command_stack.dart';

/// Owns the open document and nothing else (docs/v3/04 §4).
///
/// Selection, hover, the playhead and the viewport are **not** here — they are
/// ephemeral editor state, and persisting them is the legacy defect that made
/// documents unloadable (AC-2.2.7). This controller holds only what round-trips
/// to storage.
///
/// **No public setter.** Every mutation is a [Command] run through the
/// [CommandStack]; there is no `set document`. If a call site could assign
/// `state = newDoc` directly, some call site eventually would, and that edit
/// would be unrecoverable (docs/v3/04 §6). The stack is the one place the
/// document is replaced by an edit; [undo]/[redo] are the only other writers,
/// and both go through it.
///
/// **Everything that touches the stack is enqueued on the one chain.** [run],
/// [undo], [redo] and the three gesture calls all go through [_enqueue], in the
/// order they were issued. A `begin`/`commit` that touched the stack
/// *synchronously* while `run` deferred onto the chain is a mis-ordering, not a
/// race: at drag end `commit` ran before any queued `run` had applied, so
/// nothing had changed yet and no entry was pushed at all — and by the time the
/// runs landed the span was already closed, so each one pushed its own. A
/// 20-event drag produced 20 undo entries and 20 saves. One chain, one order.
///
/// `Async` because the first thing it does is await IO (docs/v3/08 §2): the UI
/// consumes it with `.when`, so a failed load renders an error state instead of
/// throwing at every `ref.watch`.
class DocumentController
    extends AutoDisposeFamilyAsyncNotifier<Document, String> {
  /// Null until a document has actually loaded, and **not `late`**. The public
  /// getters below are read by the shell's toolbar on every frame, including the
  /// frame that renders a `notFound`/`corrupt` error — a `late` field assigned
  /// only inside `build`'s try made `canUndo` throw `LateInitializationError`
  /// straight out of a getter the error state calls.
  CommandStack? _stack;

  CommandStack get _commands =>
      _stack ?? (throw StateError('No document is open.'));

  @override
  Future<Document> build(String projectId) async {
    // Drop any stack from a previous (or failed) load *first*: a retry must not
    // inherit the history of the document that would not open.
    _stack = null;
    final raw = await ref.read(projectStoreProvider).load(projectId);
    if (raw == null) {
      throw const StoreException(StoreFailure.notFound);
    }
    try {
      final doc = Document.fromJson(jsonDecode(raw) as Map<String, Object?>);
      // A fresh history per open: undo does not reach across reloads. The stack
      // is seeded with the loaded document so the first command branches from
      // exactly what is on disk.
      _stack = CommandStack(doc);
      return doc;
    } on StoreException {
      rethrow;
    } on Object catch (e) {
      // Anything undecodable is corrupt, not "unknown" — the user gets a real
      // sentence and the developer gets the raw reason.
      throw StoreException(StoreFailure.corrupt, details: '$e');
    }
  }

  bool get canUndo => _stack?.canUndo ?? false;
  bool get canRedo => _stack?.canRedo ?? false;
  String? get undoLabel => _stack?.undoLabel;
  String? get redoLabel => _stack?.redoLabel;

  /// Serialises the apply→save chain. **Every** mutation goes through it.
  ///
  /// Without it two commands issued while a save is in flight both branch from
  /// the same base `Document` — `state` is only assigned after the store
  /// returns — and the second write silently overwrites the first. Nothing
  /// throws, so the command gate never fires and no snackbar appears; the user
  /// simply drags one anchor, drags another within ~200 ms, and the first drag
  /// is gone. It also undercounts `rev`, which must advance by exactly 1 per
  /// persisted save (docs/v3/01 §11) because v1.1's optimistic concurrency is
  /// built on that counter.
  Future<void> _queue = Future<void>.value();

  /// Append [body] to the one chain and hand the caller its own future.
  ///
  /// The chain must survive a failed link: a network error on one drag cannot
  /// wedge every later edit, so the *chain's* copy swallows the error while the
  /// caller's copy still throws — that is what the feature's command gate
  /// catches (docs/v3/08 §1).
  Future<T> _enqueue<T>(Future<T> Function() body) {
    final next = _queue.then((_) => body());
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Run [cmd] against the **latest persisted** document, then save.
  ///
  /// The command applies through [CommandStack.run] (the one place an edit
  /// replaces the document) and persists inside the serialised chain, so it
  /// always branches from the document the previous edit actually persisted. On
  /// a save failure the optimistic advance is rolled back with
  /// [CommandStack.abortLast], so a Firestore hiccup neither corrupts the
  /// history nor loses the earlier edit — the error still reaches the caller.
  ///
  /// Inside a gesture span the command applies and is **shown but not saved**:
  /// a span persists exactly once, at [commitGesture]. That is the second half
  /// of "a 200-event drag is one entry" — it is one *write* too, instead of 200
  /// store round trips for intermediate documents the user never asked to keep.
  ///
  /// [keyframe] is the editing keyframe live at call time, captured with the
  /// undo snapshot so undo returns the user to where they were editing
  /// (docs/v3/04 §6). The M2 call sites pass null; the inspector wires it at M4.
  Future<void> run(Command cmd, {KeyframeRef? keyframe}) => _enqueue(() async {
        await _closeAbandonedSpan();
        // May throw ArgumentError from the op on an invariant violation —
        // before anything is recorded, so a rejected edit leaves history
        // untouched.
        final after = _commands.run(cmd, keyframe: keyframe);
        if (_commands.isCoalescing) {
          state = AsyncData(after);
          return;
        }
        await _persist(after);
      });

  /// Reverse the last edit — and **persist the result**.
  ///
  /// docs/v3/04 §6's "`rev` is not touched by undo" means undo must not restore
  /// an old `rev` *value*; it does not mean undo must not write. Every command
  /// already autosaves, so an undo that only assigned `state` left the file
  /// disagreeing with the screen: draw a shape, Ctrl+Z, reopen the project, and
  /// the shape is back. So a restored snapshot is re-stamped with the **live**
  /// persisted `rev` (never the historical one — see [_save]) and saved like any
  /// other write, advancing `rev` by exactly 1. `rev` is then strictly monotonic
  /// across any sequence of edits and undos, and disk always matches the screen.
  ///
  /// It returns the [Restore] so the caller can put the captured
  /// `selectedKeyframe` back on `EditorState` — the controller does not reach
  /// into `EditorController` itself, keeping the two peers uncoupled. The
  /// viewport is never in the [Restore]; undo cannot move the camera.
  ///
  /// **Undo during an open gesture cancels the gesture** rather than undoing
  /// through it. Undoing through an open span made `commit` push a base *newer*
  /// than the current document, so the next undo replayed the edit the user had
  /// just reverted. Nothing inside a span is persisted, so cancelling costs no
  /// write: the document on disk is already the one the cancel returns to.
  Future<Restore?> undo() => _enqueue(() async {
        if (_stack == null) return null;
        await _closeAbandonedSpan();
        final cancelled = _commands.cancel();
        if (cancelled != null) {
          state = AsyncData(cancelled.document);
          return cancelled;
        }
        final restore = _commands.undo();
        if (restore == null) return null;
        try {
          await _save(restore.document);
        } on Object {
          _commands.redo(); // put the entry back where undo took it from
          rethrow;
        }
        final persisted = state.requireValue;
        _commands.syncCurrent(persisted);
        return Restore(persisted, restore.selectedKeyframe);
      });

  /// Replay the last undone edit — the mirror of [undo], and it persists for the
  /// same reason.
  Future<Restore?> redo() => _enqueue(() async {
        if (_stack == null) return null;
        await _closeAbandonedSpan();
        final cancelled = _commands.cancel();
        if (cancelled != null) {
          state = AsyncData(cancelled.document);
          return cancelled;
        }
        final restore = _commands.redo();
        if (restore == null) return null;
        try {
          await _save(restore.document);
        } on Object {
          _commands.undo(); // put the entry back where redo took it from
          rethrow;
        }
        final persisted = state.requireValue;
        _commands.syncCurrent(persisted);
        return Restore(persisted, restore.selectedKeyframe);
      });

  /// Coalesce a gesture into one undo entry (docs/v3/04 §6). The canvas wraps a
  /// drag in [beginGesture]…[commitGesture] so a 200-event drag is one entry and
  /// one save, not 200 of each.
  ///
  /// Enqueued, like every other stack call: a `begin` that jumped the queue
  /// opened its span after the runs it was supposed to contain. [label] names
  /// the entry if something other than [commitGesture] has to close the span.
  Future<void> beginGesture({String label = 'Edit', KeyframeRef? keyframe}) =>
      _enqueue(() async {
        if (_stack == null) return;
        // A gesture starting while another is open means the first never
        // committed. Close it — committing, so its work survives as its own
        // entry — rather than letting the second overwrite the first's base.
        await _closeOpenSpan();
        _commands.begin(label: label, keyframe: keyframe);
      });

  /// Close the span and persist the settled document — the single save the whole
  /// drag produces. A span that changed nothing writes nothing.
  Future<void> commitGesture(String label) => _enqueue(() async {
        if (_stack == null) return;
        final settled = _commands.commit(label);
        if (settled == null) return;
        await _persist(settled);
      });

  /// Abandon the open gesture: rewind to the document the drag started from and
  /// record nothing. The cancel path a coalescing latch has to have —
  /// `onPanCancel`, Escape, the canvas going away mid-drag. No save, because
  /// nothing inside a span was ever written.
  Future<void> cancelGesture() => _enqueue(() async {
        if (_stack == null) return;
        final cancelled = _commands.cancel();
        if (cancelled != null) state = AsyncData(cancelled.document);
      });

  /// Close a span whose gesture never came back, before doing anything else.
  ///
  /// The self-defending half of the latch: a `begin` with no `commit` used to
  /// leave the stack coalescing for the rest of the session. A stale span is
  /// **committed**, not cancelled — the edits that landed inside it are real
  /// work and become their own entry — see [CommandStack.isSpanStale].
  Future<void> _closeAbandonedSpan() async {
    if (_stack == null || !_commands.isSpanStale) return;
    await _closeOpenSpan();
  }

  /// Commit whatever span is open, under its pending label, and persist it.
  Future<void> _closeOpenSpan() async {
    if (!_commands.isCoalescing) return;
    final settled = _commands.commit(_commands.pendingSpanLabel ?? 'Edit');
    if (settled == null) return;
    await _persist(settled);
  }

  /// Save [next], or roll the stack back to what is actually on disk.
  ///
  /// The rollback also re-publishes the document, because inside a span `state`
  /// has been running ahead of storage — leaving the screen on a document the
  /// store rejected is how a "saved" drag survives on screen until the next
  /// reload eats it.
  Future<void> _persist(Document next) async {
    try {
      await _save(next);
    } on Object {
      _commands.abortLast();
      state = AsyncData(_commands.current);
      rethrow;
    }
    // Keep the stack's current rev-consistent with what actually persisted;
    // the next command then branches from the rev-correct document.
    _commands.syncCurrent(state.requireValue);
  }

  /// Appends a node to the root and persists.
  ///
  /// Mirrors the M0 call shape; the mutation is now an [AddNodeCommand] so it is
  /// undoable, but the pen tool building a whole [PathNode] and appending it in
  /// one call is unchanged.
  Future<void> addNode(Node node) => run(AddNodeCommand(node));

  /// Moves one anchor and persists — the pose edit of docs/v3/01 §12.
  ///
  /// [atT] `null` edits the node's rest pose; non-null writes the pose into the
  /// `PathTrack` keyframe at that `t`. All of that lives in [PathOps.moveAnchor]
  /// via [MoveAnchorCommand]; this controller owns the document and the save,
  /// not path semantics.
  Future<void> moveAnchorAt(
    NodeId node,
    AnchorId anchor,
    Vec2 to, {
    double? atT,
  }) =>
      run(MoveAnchorCommand(node, anchor, to, atT: atT));

  /// Overwrites a node's [Transform2] and persists — the Select tool's move
  /// (docs/v3/05 §3, F3.1).
  ///
  /// One [SetTransformCommand] per completed drag, issued on release, so a
  /// 200-event move is one undo entry, not 200 — the live drag stays a private
  /// field of the canvas gesture layer and only the settled transform reaches
  /// here (docs/v3/04 §6). Semantics live in [NodeOps.setTransform]; this
  /// controller owns the document and the save, not transform maths.
  Future<void> setTransform(NodeId node, Transform2 transform) =>
      run(SetTransformCommand(node, transform));

  Future<void> rename(String name) => run(RenameDocumentCommand(name));

  /// The `rev` of the document that most recently reached storage. Zero only
  /// before the first load, where nothing can be saved anyway.
  int get _liveRev => state.valueOrNull?.rev ?? 0;

  /// `rev` advances here and nowhere else, because this is the only place a
  /// write actually reaches storage (docs/v3/01 §11).
  ///
  /// **The new `rev` is derived from the live one, never from [next].** [next]
  /// may be a snapshot lifted out of the undo stack, and that snapshot carries
  /// the `rev` the document had when it was *taken* — writing it back bumped
  /// from a stale value and marched the counter **backwards** (three renames →
  /// `rev` 4; three undos and one rename → `rev` 2, with two different documents
  /// persisted under the same `rev`). docs/v3/01 §11 requires `rev` to be
  /// non-negative and never decreasing, and v1.1's optimistic concurrency
  /// (docs/v3/06 M13) is built on exactly that. Re-stamping here — at the one
  /// place a write happens — makes the counter monotonic for *every* writer,
  /// including writers added later, instead of asking each of them to remember.
  ///
  /// It is also where docs/v3/02 §1 rule 7 is **enforced**: a document whose
  /// `schemaVersion` is newer than this build reads opens read-only and every
  /// save path is disabled. One gate, at the one place a write happens, rather
  /// than a check per command — a command added later cannot forget it.
  Future<void> _save(Document next) async {
    if (next.isReadOnly) {
      throw const StoreException(StoreFailure.readOnly);
    }
    final saved = next.copyWith(rev: _liveRev).bumpRev();
    await ref
        .read(projectStoreProvider)
        .save(saved.id, jsonEncode(saved.toJson()));
    state = AsyncData(saved);
  }
}

final documentControllerProvider = AsyncNotifierProvider.autoDispose
    .family<DocumentController, Document, String>(DocumentController.new);
