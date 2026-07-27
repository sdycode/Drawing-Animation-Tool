import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/state/command.dart';
import 'package:drawing_animation_tool/app/state/command_stack.dart';
import 'package:flutter_test/flutter_test.dart';

/// A command that changes nothing — it hands back the *same* Document instance,
/// exactly as an idempotent op does when it clamps to the value already held
/// (`NodeOps.setTrim` returns `d` when `node.trim == next`).
final class _NoopCommand implements Command {
  const _NoopCommand();
  @override
  String get label => 'Noop';
  @override
  Document apply(Document before) => before;
}

/// The undo stack in isolation — no widgets, no store, no controller. It is a
/// pure in-memory history of immutable [Document] pointers (docs/v3/04 §6), so
/// every property below is a `dart test`-shaped assertion about pointers and
/// counts.
void main() {
  const root = NodeId('n-root');
  const leaf = NodeId('p1');

  /// A group with one path child, so a duplicate has a real subtree to copy and
  /// `rev` starts non-zero (proving the stack never touches it).
  Document seed() => Document.create(name: 'Sketch').copyWith(
        rev: 5,
        root: GroupNode(
          id: root,
          name: 'Root',
          children: [
            PathNode(
              id: leaf,
              name: 'Triangle',
              path: PathData(anchors: const [
                Anchor(id: AnchorId('b0'), position: Vec2(0, 0)),
                Anchor(id: AnchorId('b1'), position: Vec2(10, 0)),
                Anchor(id: AnchorId('b2'), position: Vec2(10, 10)),
              ]),
            ),
          ],
        ),
      );

  test('run then undo/redo restores prior documents by identity', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    final doc1 = stack.run(const RenameDocumentCommand('one'));
    final doc2 = stack.run(const RenameDocumentCommand('two'));
    expect(stack.current, same(doc2));

    // Undo hands back the *exact* previous pointer, not an equal rebuild — that
    // is the whole point of snapshotting immutable documents (docs/v3/04 §6).
    expect(stack.undo()!.document, same(doc1));
    expect(stack.current, same(doc1));
    expect(stack.undo()!.document, same(doc0));
    expect(stack.current, same(doc0));
    expect(stack.undo(), isNull, reason: 'nothing left to undo');

    expect(stack.redo()!.document, same(doc1));
    expect(stack.redo()!.document, same(doc2));
    expect(stack.current, same(doc2));
  });

  test('a no-op command records no entry and preserves the redo branch', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    final doc1 = stack.run(const RenameDocumentCommand('one'));
    stack.undo(); // back at doc0, with doc1 waiting on the redo branch
    expect(stack.current, same(doc0));
    expect(stack.canRedo, isTrue);
    expect(stack.canUndo, isFalse);

    // An idempotent op that changes nothing returns the *same* instance. This
    // must not push a phantom undo entry, and — the sharper bug — must not let
    // `_push` clear the live redo branch (`_push` both records and drops redo).
    final after = stack.run(const _NoopCommand());
    expect(after, same(doc0), reason: 'a no-op leaves the document untouched');
    expect(stack.canUndo, isFalse,
        reason: 'no phantom entry for an unchanged document');
    expect(stack.canRedo, isTrue,
        reason: 'a no-op must not destroy a reachable future');
    expect(stack.redo()!.document, same(doc1),
        reason: 'the redo the no-op almost ate is still there');

    // A command that DOES change the document still behaves normally: one entry,
    // redo branch dropped.
    final doc2 = stack.run(const RenameDocumentCommand('two'));
    expect(stack.current, same(doc2));
    expect(stack.canUndo, isTrue);
    expect(stack.canRedo, isFalse, reason: 'a real edit drops the future');
  });

  test('depth caps at 100 — the 101st push drops the oldest', () {
    final doc0 = seed();
    final stack = CommandStack(doc0); // default depth 100

    // 101 edits. The snapshot taken before edit #1 (which points at doc0) is the
    // one that must fall off the bottom when the 101st entry lands.
    for (var n = 0; n < 101; n++) {
      stack.run(RenameDocumentCommand('edit-$n'));
    }

    var undos = 0;
    while (stack.canUndo) {
      stack.undo();
      undos++;
    }
    expect(undos, 100, reason: 'the bound is a bound, not a leak');
    // doc0 is gone — the oldest reachable state is the one after the first edit,
    // never the original.
    expect(stack.current, isNot(same(doc0)),
        reason: 'the 101st push evicted the doc0 snapshot');
  });

  test('a coalesced drag is one undo entry', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    // A 3-event "drag": begin, three intermediate applies, commit. Between begin
    // and commit, run advances the document without recording an entry.
    stack.begin();
    stack.run(const RenameDocumentCommand('drag-a'));
    stack.run(const RenameDocumentCommand('drag-b'));
    final atDragEnd = stack.run(const RenameDocumentCommand('drag-c'));
    stack.commit('Drag');

    expect(stack.current, same(atDragEnd));
    expect(stack.undoLabel, 'Drag');

    // One undo returns the whole drag to the pre-begin document.
    expect(stack.undo()!.document, same(doc0));
    expect(stack.canUndo, isFalse, reason: '200 events, one entry');
  });

  test('a begin/commit span that changed nothing records no entry', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);
    stack.begin();
    stack.commit('Empty drag'); // a click that moved nothing
    expect(stack.canUndo, isFalse, reason: 'no empty undo step');
  });

  test('duplicateSubtree undoes as ONE entry however many ids it re-mints', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    final after = stack.run(const DuplicateSubtreeCommand(leaf));
    // The copy re-mints the node id and every anchor id, but it is one command
    // and therefore one snapshot — the M2 exit criterion.
    expect(after.root.children, hasLength(2));
    expect(stack.undoLabel, 'Duplicate');

    expect(stack.undo()!.document, same(doc0));
    expect(stack.current.root.children, hasLength(1));
    expect(stack.canUndo, isFalse, reason: 'a many-id duplicate is one entry');
  });

  test('the stack never touches rev', () {
    final doc0 = seed(); // rev 5
    final stack = CommandStack(doc0);

    final doc1 = stack.run(const RenameDocumentCommand('renamed'));
    expect(doc1.rev, 5,
        reason: 'a command is pure Document->Document; rev '
            'advances only on a persisted save (docs/v3/01 §11)');
    expect(stack.undo()!.document.rev, 5);
    expect(stack.redo()!.document.rev, 5);
  });

  test('a new command after an undo clears the redo branch', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    stack.run(const RenameDocumentCommand('one'));
    stack.run(const RenameDocumentCommand('two'));
    stack.undo();
    expect(stack.canRedo, isTrue);

    stack.run(const RenameDocumentCommand('three'));
    expect(stack.canRedo, isFalse,
        reason: 'branching forward drops the future');
  });

  test(
      'undo restores the captured selectedKeyframe (and Restore has no '
      'viewport)', () {
    const kfBefore = (NodeId('p1'), PropertyKey(PropKey.position), 0);
    const kfAfter = (NodeId('p1'), PropertyKey(PropKey.rotation), 1);

    final doc0 = seed();
    // Seed the stack at kfBefore, then issue a command while editing at kfAfter.
    final stack = CommandStack(doc0, keyframe: kfBefore);
    stack.run(const RenameDocumentCommand('edit'), keyframe: kfAfter);

    // Undo returns the document *and* the keyframe you were at when you made the
    // edit — so undo drops you back where you were editing (docs/v3/04 §6). The
    // [Restore] deliberately carries no viewport field: undo cannot move the
    // camera, because the camera is not in the stack at all.
    final restore = stack.undo()!;
    expect(restore.document, same(doc0));
    expect(restore.selectedKeyframe, kfBefore);

    // Redo returns the keyframe live when the edit was made.
    expect(stack.redo()!.selectedKeyframe, kfAfter);
  });

  test('abortLast rolls back the most recent run without leaving a redo entry',
      () {
    final doc0 = seed();
    final stack = CommandStack(doc0);
    stack.run(const RenameDocumentCommand('optimistic'));

    // The controller calls this when the persist *after* an optimistic run
    // fails: the document returns to before the run and no phantom redo entry is
    // left pointing at a document that never reached storage.
    stack.abortLast();
    expect(stack.current, same(doc0));
    expect(stack.canUndo, isFalse);
    expect(stack.canRedo, isFalse);
  });

  // --- The coalescing span -------------------------------------------------
  //
  // A span is `_coalesceBase != null` and nothing else. Every test below pins a
  // way the old `bool _coalescing` latch could disagree with it, or a way the
  // span could be entered/left without the history staying sane.

  test('a SECOND begin keeps the OUTER base — the first half is not lost', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    stack.begin(label: 'Drag');
    final afterA = stack.run(const RenameDocumentCommand('A'));
    // A second begin used to overwrite `_coalesceBase`, so the span's starting
    // point became the document *after* A and one undo landed between A and B —
    // the first half of the work was unreachable.
    stack.begin(label: 'Inner');
    stack.run(const RenameDocumentCommand('B'));
    stack.commit('Drag');

    expect(stack.undo()!.document, same(doc0),
        reason: 'the span still starts where the OUTER begin opened it');
    expect(stack.current, isNot(same(afterA)));
  });

  test('a coalesced run clears the redo branch', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    stack.run(const RenameDocumentCommand('one'));
    stack.undo();
    expect(stack.canRedo, isTrue);

    // The clear used to live only in `_push`, which a coalesced run skips — so
    // redo stayed enabled *during a drag* and, when pressed, replaced the live
    // in-progress document and pushed the half-finished drag onto the stack.
    stack.begin(label: 'Drag');
    stack.run(const RenameDocumentCommand('drag'));
    expect(stack.canRedo, isFalse,
        reason: 'mutating the document forward drops the future, span or not');
  });

  test('undo and redo REFUSE while a span is open, and cancel closes it', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    final one = stack.run(const RenameDocumentCommand('one'));
    stack.begin(label: 'Drag');
    stack.run(const RenameDocumentCommand('drag'));

    // Undoing *through* an open span made `commit` push a base newer than
    // `current`, so the next undo re-applied the edit the user had just
    // reverted — undo moving history forward.
    expect(stack.undo(), isNull, reason: 'an open span is not undone through');
    expect(stack.redo(), isNull);

    // The cancel path a latch has to have. It rewinds to the drag's base,
    // records nothing, and leaves the earlier entry alone.
    final cancelled = stack.cancel()!;
    expect(cancelled.document, same(one));
    expect(stack.isCoalescing, isFalse);
    expect(stack.undo()!.document, same(doc0),
        reason: 'the pre-drag history is intact and reachable again');
  });

  test('an abandoned span goes stale instead of latching forever', () {
    var now = DateTime(2026, 7, 21, 12);
    final stack = CommandStack(
      seed(),
      spanTimeout: const Duration(seconds: 5),
      clock: () => now,
    );

    // begin with no commit — onPanCancel, a disposed widget, a thrown handler,
    // an early return. This used to leave the stack coalescing for the rest of
    // the session: ten ordinary edits later, `canUndo` was still false.
    stack.begin(label: 'Drag');
    stack.run(const RenameDocumentCommand('drag'));
    expect(stack.isSpanStale, isFalse);

    // A live drag touches the span on every event, so it never goes stale.
    now = now.add(const Duration(seconds: 4));
    stack.run(const RenameDocumentCommand('drag-2'));
    now = now.add(const Duration(seconds: 4));
    expect(stack.isSpanStale, isFalse, reason: 'activity keeps it alive');

    // Silence does.
    now = now.add(const Duration(seconds: 2));
    expect(stack.isSpanStale, isTrue);
    expect(stack.pendingSpanLabel, 'Drag',
        reason: 'the controller commits it under the label begin gave it');
  });

  test('a span that only saw a syncCurrent records no entry', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    stack.begin(label: 'Drag');
    // An unrelated in-flight save landing mid-span replaces `current` with a
    // new, equal object. The old identity-only guard read that as "the gesture
    // changed something" and pushed a spurious entry for a click that moved
    // nothing.
    stack.syncCurrent(doc0.bumpRev());
    expect(stack.commit('Drag'), isNull, reason: 'nothing to persist');
    expect(stack.canUndo, isFalse, reason: 'and nothing to undo');
  });

  test('commit hands back the settled document to persist', () {
    final stack = CommandStack(seed());
    stack.begin(label: 'Drag');
    final settled = stack.run(const RenameDocumentCommand('drag'));
    // One save per span, and this is the document it saves — the controller
    // cannot know it any other way, because a coalesced run never persists.
    expect(stack.commit('Drag'), same(settled));
  });

  // --- Rollback ------------------------------------------------------------

  test('abortLast inside a span does NOT eat the previous entry', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    final renamed = stack.run(const RenameDocumentCommand('committed'));
    stack.begin(label: 'Drag');
    stack.run(const RenameDocumentCommand('drag'));

    // A coalesced run pushes nothing, so popping `_undo` here reverted to the
    // base of the PREVIOUS, already-persisted command and deleted that
    // command's undo entry: an unrelated hiccup on a later drag silently
    // destroyed a committed rename.
    stack.abortLast();
    expect(stack.current, same(renamed),
        reason: 'the rollback is the span base, not the previous command');
    expect(stack.canUndo, isTrue);
    // The gesture is still live — the pointer is still down — so the span stays
    // open and undo stays refused. Close it, and the committed rename is right
    // where it was.
    expect(stack.commit('Drag'), isNull, reason: 'the span was rolled back');
    expect(stack.undo()!.document, same(doc0),
        reason: 'the committed rename is still undoable');
  });

  test('abortLast restores the redo branch the failed push cleared', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    final one = stack.run(const RenameDocumentCommand('one'));
    stack.undo();
    expect(stack.canRedo, isTrue);

    // `run` pushes and clears the redo branch; the save then fails. The
    // rollback used to restore `current` and the undo entry but not the future,
    // so a network hiccup silently took the user's redo with it.
    stack.run(const RenameDocumentCommand('two'));
    stack.abortLast();
    expect(stack.current, same(doc0));
    expect(stack.canUndo, isFalse);
    expect(stack.canRedo, isTrue, reason: 'the failed command kept no branch');
    expect(stack.redo()!.document, same(one));
  });

  test('a command that throws leaves history and current untouched', () {
    final doc0 = seed();
    final stack = CommandStack(doc0);

    // Duplicating the root is an invariant violation the op throws on. The throw
    // must reach the caller with nothing recorded and current unchanged (the one
    // catch site is a feature's commands.dart, docs/v3/08 §1).
    expect(() => stack.run(const DuplicateSubtreeCommand(NodeId('n-root'))),
        throwsA(isA<ArgumentError>()));
    expect(stack.current, same(doc0));
    expect(stack.canUndo, isFalse);
  });
}
