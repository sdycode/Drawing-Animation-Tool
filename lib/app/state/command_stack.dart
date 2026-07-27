/// Undo/redo as a bounded snapshot stack of immutable documents (docs/v3/04 §6).
///
/// **Snapshots, not inverse commands.** `Document` is immutable, so a snapshot is
/// a pointer and unchanged subtrees are shared — depth 100 is cheap. Hand-written
/// inverses are where undo bugs live, and `PathOps.retopologize` has no clean
/// inverse at all. So the stack never inverts anything: it remembers the whole
/// document as it was, and undo restores that pointer.
///
/// **One command = one entry, even across many ids.** `DuplicateSubtreeCommand`
/// re-mints a hundred `NodeId`s / `AnchorId`s and undoes as a single entry,
/// because the command produced one whole new `Document` and the stack recorded
/// exactly one snapshot before it. This is the M2 exit criterion.
///
/// **Gestures coalesce.** [begin] on drag start, [commit] on drag end — a
/// 200-event drag is one entry, not 200. Between the two, [run] advances the
/// document without recording a new entry. A span is a *value* here — it is
/// `_coalesceBase != null`, never a separate `bool` latch, because two fields
/// that can disagree is exactly how a `begin` without a `commit` left the stack
/// coalescing for the rest of the session with undo silently dead.
///
/// **Ephemeral state is not undoable.** The stack knows nothing of selection,
/// hover, zoom or tool mode. It captures one exception, the
/// `EditorState.selectedKeyframe` (so undo returns you to where you were
/// editing), and restores it with the snapshot. It has **no reference to
/// `viewportTransform`** — undo cannot move the camera because the camera is not
/// in here (docs/v3/04 §6: "nothing is more disorienting than undo moving the
/// camera").
///
/// **The stack is `rev`-agnostic, and that is the whole of its relationship with
/// `rev`.** A snapshot is structure and geometry — history — not save metadata.
/// The `rev` field that happens to ride along inside a snapshotted `Document` is
/// meaningless: the stack never reads it, never compares it and never bumps it,
/// and `DocumentController` re-stamps every restored document with the **live
/// persisted `rev`** before that document goes anywhere near storage. That is
/// what docs/v3/04 §6's "`rev` is not touched by undo" means — undo must not
/// restore an *old `rev` value*. It does not mean undo must not persist. Undoing
/// a snapshot straight back onto disk with its historical `rev` is what made the
/// counter go **backwards** (three renames → `rev` 4; three undos plus one
/// rename → `rev` 2, two different documents written under the same `rev`), and
/// v1.1's optimistic concurrency (docs/v3/06 M13) is built on that counter never
/// decreasing (docs/v3/01 §11).
library;

import 'package:anim_core/anim_core.dart';

import 'command.dart';

/// Addresses one keyframe for edit-at-keyframe (docs/v3/01 §12). Structural, so
/// it is the same type as `EditorState.selectedKeyframe` without either file
/// importing the other.
typedef KeyframeRef = (NodeId, PropertyKey, int);

/// What an undo or redo restores: the document to show, plus the editing
/// keyframe to return to. There is deliberately no viewport field.
final class Restore {
  const Restore(this.document, this.selectedKeyframe);

  final Document document;
  final KeyframeRef? selectedKeyframe;
}

/// One remembered point in history: the document, the keyframe you were editing
/// at, and the label of the action this point lets you undo.
final class _Snapshot {
  const _Snapshot(this.document, this.keyframe, this.label);

  final Document document;
  final KeyframeRef? keyframe;
  final String? label;
}

class CommandStack {
  CommandStack(
    Document initial, {
    this.depth = 100,
    KeyframeRef? keyframe,
    this.spanTimeout = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _current = initial,
        _keyframe = keyframe,
        _clock = clock ?? DateTime.now;

  /// Worst realistic document is ~150 KB (docs/v3/02 §9) and structure is
  /// shared, so 100 whole-document snapshots cost far less than 100 copies.
  final int depth;

  /// How long an open span may sit *idle* before [isSpanStale] declares it
  /// abandoned. A drag touches the span on every event, so a real gesture never
  /// trips this; only a [begin] whose [commit] never arrived does — see
  /// [isSpanStale] for why the stack must be able to notice that itself.
  final Duration spanTimeout;

  /// Injectable so the staleness rule is testable without a real clock.
  final DateTime Function() _clock;

  Document _current;
  KeyframeRef? _keyframe;

  final List<_Snapshot> _undo = <_Snapshot>[];
  final List<_Snapshot> _redo = <_Snapshot>[];

  /// The open span, or null when there is none. **This single nullable field is
  /// the span** — there is no companion `bool`, so there is no state in which
  /// "coalescing" is true and the base is gone.
  _Snapshot? _coalesceBase;

  /// The label the span will be committed under if something has to close it
  /// without the gesture's own `commit` (a second [begin], or an abandoned
  /// span).
  String? _pendingLabel;

  /// Whether the open span has actually applied a command. The commit guard is
  /// this flag and not only pointer identity, because `syncCurrent` replaces
  /// `_current` with a new, equal object on every save: an unrelated in-flight
  /// save landing between [begin] and [commit] made a no-op click push a
  /// spurious "empty gesture" entry.
  bool _spanDirty = false;

  /// When the span last saw activity, for [isSpanStale].
  DateTime? _spanTouched;

  /// The redo branch as it was before the most recent [_dropRedoBranch], so
  /// [abortLast] and [cancel] can put the future back. A failed save used to
  /// destroy the redo branch permanently: `_push` cleared it, and the rollback
  /// restored the document and the undo entry but never the redo entries.
  List<_Snapshot>? _clearedRedo;

  /// The authoritative in-memory document. Every mutation replaces it **here**
  /// and nowhere else — that is the rule `DocumentController` leans on to expose
  /// no public setter (docs/v3/04 §6).
  Document get current => _current;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// The label of the edit a call to [undo] would reverse, for the menu item.
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  /// The label of the edit a call to [redo] would replay.
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  /// True between [begin] and [commit]/[cancel]. `DocumentController` reads it
  /// to know that a [run] must not persist yet — a span persists exactly once,
  /// at commit, which is what makes a 200-event drag one save as well as one
  /// entry.
  bool get isCoalescing => _coalesceBase != null;

  /// The label an abandoned span would be committed under.
  String? get pendingSpanLabel => _pendingLabel;

  /// An open span that has gone quiet for longer than [spanTimeout].
  ///
  /// A span is opened by a gesture and closed by that same gesture, so every
  /// path that does not reach `commit` — `onPanCancel`, widget disposal, a
  /// thrown handler, an early return — used to leave the stack coalescing
  /// **forever**: `begin`, one run, no commit, then ten ordinary edits, and
  /// `canUndo` is false for the rest of the session. An explicit [cancel] fixes
  /// the paths that remember to call it; this makes the latch defend itself
  /// against the paths that do not. `DocumentController` closes a stale span
  /// (committing it, so the work inside it survives as its own entry) before it
  /// runs anything else.
  bool get isSpanStale {
    final touched = _spanTouched;
    if (touched == null) return false;
    return _clock().difference(touched) > spanTimeout;
  }

  /// Apply [cmd] and record an undo entry — unless inside a [begin]/[commit]
  /// span, where the entry was already captured on `begin`.
  ///
  /// [cmd.apply] runs first and may throw (`ArgumentError` from an op on an
  /// invariant violation, docs/v3/08 §1); if it throws, nothing is recorded and
  /// [current] is unchanged, so a rejected edit leaves the history and the
  /// document exactly as they were. [keyframe] is the editing keyframe live at
  /// call time; passing null keeps whatever was already current.
  Document run(Command cmd, {KeyframeRef? keyframe}) {
    final leaving = _Snapshot(_current, _keyframe, cmd.label);
    final after = cmd.apply(_current); // throws → the lines below never run
    if (_coalesceBase == null) {
      // A command that changes nothing — an idempotent op clamping to the value
      // the node already holds returns the *same* Document instance — must not
      // push a phantom entry: undo would restore an identical document, `_push`
      // would clear a live redo branch, and `DocumentController` would bump `rev`
      // and write unchanged content (waking M7 autosave on a no-op edit). Mirror
      // the identity guard the coalescing branch already applies below.
      if (!identical(after, _current)) {
        _push(leaving);
      }
    } else {
      if (!identical(after, _current)) {
        // A coalesced run mutates the document, so the redo branch is just as
        // dead as it is for an ordinary run. The clear used to live only in
        // `_push`, so redo stayed *enabled during a drag* and, when pressed,
        // replaced the live in-progress document and pushed the half-finished
        // drag onto the undo stack.
        _dropRedoBranch();
        _spanDirty = true;
      }
      _spanTouched = _clock();
    }
    _current = after;
    _keyframe = keyframe ?? _keyframe;
    return after;
  }

  /// Open a coalescing span (drag start). Everything until [commit] collapses
  /// into the single entry captured here.
  ///
  /// A second `begin` while a span is open **keeps the outer base**. Overwriting
  /// it lost the outer gesture's starting point — `begin; run A; begin; run B;
  /// commit` left undo landing *after* A instead of before it, so the first half
  /// of the work was unreachable. Callers that want two entries close the first
  /// span first; `DocumentController.beginGesture` does exactly that, because it
  /// is the layer that can persist the closed one.
  void begin({KeyframeRef? keyframe, String label = 'Edit'}) {
    _spanTouched = _clock();
    if (_coalesceBase != null) return;
    _coalesceBase = _Snapshot(_current, keyframe ?? _keyframe, null);
    _pendingLabel = label;
    _spanDirty = false;
  }

  /// Close the span (drag end) and return the settled document that must be
  /// persisted, or null when there is nothing to record — a click that begins
  /// and commits without moving anything leaves no empty undo step and no save.
  Document? commit(String label) {
    final base = _coalesceBase;
    final dirty = _spanDirty;
    _coalesceBase = null;
    _pendingLabel = null;
    _spanDirty = false;
    _spanTouched = null;
    if (base == null) return null;
    if (!dirty || identical(base.document, _current)) return null;
    _push(_Snapshot(base.document, base.keyframe, label));
    return _current;
  }

  /// Abandon the open span: rewind to the document it started from, record
  /// nothing, and hand back what to show. Null when no span was open.
  ///
  /// This is the cancel path a latch has to have — `onPanCancel`, Escape, the
  /// widget going away mid-drag. Nothing inside a span is ever persisted, so a
  /// cancel is a pure in-memory rewind: no save, no `rev` churn, and the
  /// document on disk is already the one this returns.
  Restore? cancel() {
    final base = _coalesceBase;
    _coalesceBase = null;
    _pendingLabel = null;
    _spanTouched = null;
    if (base == null) return null;
    if (_spanDirty) _restoreRedoBranch();
    _spanDirty = false;
    _current = base.document;
    _keyframe = base.keyframe;
    return Restore(_current, _keyframe);
  }

  /// Restore the previous snapshot, or null if there is nothing to undo.
  ///
  /// **Refused while a span is open.** Undo is live during a drag (the shell
  /// binds Cmd/Ctrl+Z globally), and undoing *through* an open span made
  /// `commit` push a base newer than `_current` — pressing undo afterwards
  /// re-applied the edit the user had just reverted, i.e. undo moved history
  /// forward. The controller turns this refusal into a [cancel] of the
  /// in-progress gesture, which is what a user pressing undo mid-drag means.
  Restore? undo() {
    if (_coalesceBase != null) return null;
    if (_undo.isEmpty) return null;
    _clearedRedo = null;
    final target = _undo.removeLast();
    _redo.add(_Snapshot(_current, _keyframe, target.label));
    _current = target.document;
    _keyframe = target.keyframe;
    return Restore(_current, _keyframe);
  }

  /// Replay the most recently undone snapshot, or null if there is nothing to
  /// redo. Refused while a span is open, for the same reason as [undo].
  Restore? redo() {
    if (_coalesceBase != null) return null;
    if (_redo.isEmpty) return null;
    _clearedRedo = null;
    final target = _redo.removeLast();
    _undo.add(_Snapshot(_current, _keyframe, target.label));
    _current = target.document;
    _keyframe = target.keyframe;
    return Restore(_current, _keyframe);
  }

  /// Record one entry and clear the redo branch. When the stack is full the
  /// **oldest** entry drops — the 101st push loses the 1st, so the depth is a
  /// bound, not a leak.
  void _push(_Snapshot s) {
    _undo.add(s);
    if (_undo.length > depth) _undo.removeAt(0);
    _dropRedoBranch();
  }

  /// Drop the future, remembering it so a rollback can put it back.
  void _dropRedoBranch() {
    _clearedRedo = _redo.isEmpty ? const <_Snapshot>[] : List.of(_redo);
    _redo.clear();
  }

  void _restoreRedoBranch() {
    final saved = _clearedRedo;
    _clearedRedo = null;
    if (saved == null) return;
    _redo
      ..clear()
      ..addAll(saved);
  }

  /// Undo the most recent [run] without leaving a redo entry — the rollback the
  /// controller uses when the persist *after* an optimistic [run] fails, so a
  /// save error does not leave a phantom entry pointing at a document that never
  /// reached storage.
  ///
  /// Two things it must not do, both of which it used to:
  ///
  /// * **Inside an open span it must not pop `_undo`.** A coalesced `run` pushes
  ///   nothing, so popping reverted to the base of the *previous, already
  ///   persisted* command and deleted that command's undo entry — a network
  ///   hiccup on an unrelated later drag silently destroyed a committed rename.
  ///   Inside a span the rollback is the span's own base.
  /// * **It must restore the redo branch the failed `_push` cleared.** Otherwise
  ///   `run one; undo; run two whose save fails; abortLast` left `canRedo`
  ///   false: the failed command took the user's future with it.
  void abortLast() {
    final span = _coalesceBase;
    if (span != null) {
      if (_spanDirty) _restoreRedoBranch();
      _spanDirty = false;
      _current = span.document;
      _keyframe = span.keyframe;
      return;
    }
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    _current = s.document;
    _keyframe = s.keyframe;
    _restoreRedoBranch();
  }

  /// Re-stamp [current] with a persisted document (same structure, live `rev`)
  /// without recording history.
  ///
  /// `rev` is save metadata and lives with the controller that saves; the
  /// history in here is structure and geometry only. This is the one line that
  /// keeps the two in step: after a write, `current` is the document that
  /// actually reached storage, so the next command branches from the
  /// `rev`-correct object and the counter advances by exactly 1 per persisted
  /// save (docs/v3/01 §11).
  void syncCurrent(Document persisted) => _current = persisted;
}
