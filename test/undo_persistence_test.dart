import 'dart:async';
import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/save_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Undo, redo and gesture coalescing **through `DocumentController`** — the
/// layer where the stack meets the store.
///
/// The stack's own tests (`command_stack_test.dart`) drive it synchronously and
/// therefore cannot see any of the defects below: every one of them is about
/// *ordering against the save queue* or about *what reaches disk*. Two roots
/// account for all of them —
///
/// 1. **Sync/async ordering.** `begin`/`commit` touched the stack synchronously
///    while `run` deferred onto the queue, so at drag end `commit` ran before
///    any queued run had applied — no entry at all — and the runs then landed
///    with the span already closed, one entry and one save each.
/// 2. **The `rev`/persistence model.** Undo restored a snapshot *with its
///    historical `rev`* and never saved, so the counter marched backwards and
///    the file disagreed with the screen.
class _CountingStore implements ProjectStore {
  _CountingStore(this._inner);

  final MemoryProjectStore _inner;

  /// Every payload that actually reached storage, in order.
  final List<String> writes = <String>[];

  StoreFailure? failNext;

  @override
  Future<List<ProjectSummary>> list() => _inner.list();

  @override
  Future<String?> load(String id) => _inner.load(id);

  @override
  Future<void> save(String id, String json) async {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw StoreException(f);
    }
    // A real round trip is tens of milliseconds; one microtask is enough to
    // open the in-flight window the queue exists to serialise.
    await Future<void>.delayed(Duration.zero);
    await _inner.save(id, json);
    writes.add(json);
  }

  @override
  Future<void> delete(String id) => _inner.delete(id);

  int get saves => writes.length;

  List<int> get revs => <int>[
        for (final w in writes)
          ((jsonDecode(w) as Map<String, Object?>)['rev'] as num).toInt(),
      ];
}

void main() {
  const node = NodeId('sq');

  late MemoryProjectStore memory;
  late _CountingStore store;

  /// A one-node document already at `rev` 1, so "never decreasing" is a claim
  /// about a counter that started somewhere.
  String seed() {
    final base = Document.create(name: 'Sketch')
        .copyWith(
          root: GroupNode(
            id: const NodeId('n-root'),
            name: 'Root',
            children: [
              PathNode(
                id: node,
                name: 'Square',
                path: PathData(anchors: const [
                  Anchor(id: AnchorId('b0'), position: Vec2(0, 0)),
                  Anchor(id: AnchorId('b1'), position: Vec2(10, 0)),
                  Anchor(id: AnchorId('b2'), position: Vec2(10, 10)),
                ]),
              ),
            ],
          ),
        )
        .bumpRev();

    memory = MemoryProjectStore({base.id: jsonEncode(base.toJson())});
    store = _CountingStore(memory);
    return base.id;
  }

  Future<Document> onDisk(String id) async => Document.fromJson(
      jsonDecode((await memory.load(id))!) as Map<String, Object?>);

  Future<(ProviderContainer, DocumentController)> open(
    String id, {
    ProjectStore? override,
  }) async {
    final container = ProviderContainer(
      overrides: [projectStoreProvider.overrideWithValue(override ?? store)],
    );
    addTearDown(container.dispose);
    // A listener, so the autoDispose family stays alive across the awaits.
    container.listen(documentControllerProvider(id), (_, __) {});
    await container.read(documentControllerProvider(id).future);
    return (container, container.read(documentControllerProvider(id).notifier));
  }

  // --- Undo reaches storage, and `rev` only ever goes up -------------------

  test('undo persists: what the user sees survives a reload', () async {
    // Draw a shape, Ctrl+Z, reopen the project — and the shape was back,
    // because undo only assigned `state` while every command autosaved. The M2
    // exit criterion was true exactly until the next refresh.
    final id = seed();
    final (_, controller) = await open(id);

    await controller.rename('after the edit');
    expect((await onDisk(id)).name, 'after the edit');

    await controller.undo();
    expect((await onDisk(id)).name, 'Sketch',
        reason: 'the file agrees with the screen, not with the last command');

    await controller.redo();
    expect((await onDisk(id)).name, 'after the edit');
  });

  test('rev never decreases across renames and undos, and never repeats',
      () async {
    // Three renames took the stored `rev` to 4; three undos plus one fresh
    // rename wrote `rev` **2** — two different documents persisted under the
    // same number. docs/v3/01 §11 requires non-negative and never decreasing,
    // and v1.1's optimistic concurrency (docs/v3/06 M13) is built on it.
    final id = seed();
    final (_, controller) = await open(id);

    await controller.rename('one');
    await controller.rename('two');
    await controller.rename('three');
    expect((await onDisk(id)).rev, 4, reason: 'seeded at 1, three saves');

    await controller.undo();
    await controller.undo();
    await controller.undo();
    await controller.rename('four');

    final revs = store.revs;
    expect(revs, [2, 3, 4, 5, 6, 7, 8],
        reason: 'exactly +1 per persisted save, undos included');
    for (var i = 1; i < revs.length; i++) {
      expect(revs[i], greaterThan(revs[i - 1]), reason: 'strictly monotonic');
    }
    // No two different documents under one `rev`.
    final byRev = <int, String>{};
    for (var i = 0; i < store.writes.length; i++) {
      final r = revs[i];
      expect(byRev.containsKey(r), isFalse, reason: 'rev $r written twice');
      byRev[r] = store.writes[i];
    }
    expect((await onDisk(id)).name, 'four');
    expect((await onDisk(id)).rev, 8);
  });

  // --- Gesture coalescing, end to end --------------------------------------

  test('a 20-event drag is ONE undo entry and ONE store save', () async {
    // Reproduced at 20 entries and 20 saves: `commit` ran before any queued run
    // had applied (so `identical(base, current)` was still true and nothing was
    // pushed), and the runs then landed with the span already closed.
    final id = seed();
    final (container, controller) = await open(id);

    final savesBefore = store.saves;
    // A gesture handler never awaits the store (docs/v3/08 §2) — it fires and
    // forgets, exactly as the canvas does. The ordering comes from the one
    // queue, not from the caller.
    unawaited(controller.beginGesture(label: 'Move'));
    for (var i = 1; i <= 20; i++) {
      unawaited(controller.setTransform(
          node, Transform2(position: Vec2(i.toDouble(), i.toDouble()))));
    }
    await controller.commitGesture('Move');

    expect(store.saves - savesBefore, 1, reason: '20 events, one write');
    expect(controller.undoLabel, 'Move');

    final moved = (await onDisk(id)).nodeIndex[node]!;
    expect(moved.transform.position, const Vec2(20, 20),
        reason: 'the settled document is the one that persisted');

    // ...and one undo reverts the whole drag, on screen and on disk.
    await controller.undo();
    expect(controller.canUndo, isFalse, reason: '20 events, one entry');
    expect((await onDisk(id)).nodeIndex[node]!.transform.position, Vec2.zero);
    expect(
        container
            .read(documentControllerProvider(id))
            .requireValue
            .nodeIndex[node]!
            .transform
            .position,
        Vec2.zero);
  });

  test('a drag that moved nothing writes nothing and records nothing',
      () async {
    final id = seed();
    final (_, controller) = await open(id);

    final savesBefore = store.saves;
    unawaited(controller.beginGesture(label: 'Move'));
    await controller.commitGesture('Move');

    expect(store.saves, savesBefore, reason: 'a click is not a write');
    expect(controller.canUndo, isFalse, reason: 'and not an undo step');
  });

  test('undo during a drag cancels the drag instead of undoing through it',
      () async {
    // `run one; begin; run drag; undo; commit` used to push a base NEWER than
    // the current document, so pressing undo afterwards re-applied the edit the
    // user had just reverted — undo moving history forward. Undo is live during
    // a drag: the shell binds Cmd/Ctrl+Z globally.
    final id = seed();
    final (_, controller) = await open(id);

    await controller.rename('one');
    final savesAfterEdit = store.saves;

    unawaited(controller.beginGesture(label: 'Move'));
    unawaited(
        controller.setTransform(node, const Transform2(position: Vec2(9, 9))));
    await controller.undo();

    expect(store.saves, savesAfterEdit,
        reason: 'nothing inside a span was ever written, so cancel is free');
    expect((await onDisk(id)).nodeIndex[node]!.transform.position, Vec2.zero);
    expect((await onDisk(id)).name, 'one', reason: 'the rename is untouched');

    // The commit that arrives on pointer-up finds no span, and the history is
    // exactly where it was before the drag started.
    await controller.commitGesture('Move');
    expect(controller.undoLabel, 'Rename');
    await controller.undo();
    expect((await onDisk(id)).name, 'Sketch',
        reason: 'undo still walks backwards, never forwards');
  });

  test('a gesture that never commits does not wedge undo for the session',
      () async {
    // `begin` with no `commit` — onPanCancel, a disposed widget, a thrown
    // handler — left the stack coalescing forever: ten ordinary edits later,
    // `canUndo` was still false and undo was dead for the rest of the session.
    final id = seed();
    final (_, controller) = await open(id);

    unawaited(controller.beginGesture(label: 'Move'));
    await controller.setTransform(node, const Transform2(position: Vec2(4, 4)));

    // The next gesture closes the abandoned one instead of overwriting its
    // base, so the abandoned work survives as its own entry...
    unawaited(controller.beginGesture(label: 'Second move'));
    unawaited(
        controller.setTransform(node, const Transform2(position: Vec2(8, 8))));
    await controller.commitGesture('Second move');

    expect(controller.canUndo, isTrue, reason: 'undo is alive');
    expect((await onDisk(id)).nodeIndex[node]!.transform.position,
        const Vec2(8, 8));

    await controller.undo();
    expect((await onDisk(id)).nodeIndex[node]!.transform.position,
        const Vec2(4, 4),
        reason: 'the abandoned span became its own entry, not a lost one');

    // ...and the explicit cancel path leaves nothing behind at all.
    unawaited(controller.beginGesture(label: 'Move'));
    unawaited(controller.setTransform(
        node, const Transform2(position: Vec2(99, 99))));
    await controller.cancelGesture();
    expect((await onDisk(id)).nodeIndex[node]!.transform.position,
        const Vec2(4, 4));
    await controller.rename('still working');
    expect((await onDisk(id)).name, 'still working',
        reason: 'ordinary edits persist again immediately after a cancel');
  });

  test('a failed save at drag end retains the gesture on screen and flags error',
      () async {
    final id = seed();
    final (container, controller) = await open(id);
    final save = container.read(saveStateProvider(id));

    unawaited(controller.beginGesture(label: 'Move'));
    unawaited(
        controller.setTransform(node, const Transform2(position: Vec2(5, 5))));
    store.failNext = StoreFailure.network;
    await controller.commitGesture('Move');

    // AC-10.3.4: a drag whose save fails is NOT rolled back under the user — it
    // stays on screen, retained in memory, with an error indicator and no rev
    // bump. The gesture is still one undo entry, and a retry lands it.
    expect(save.value.phase, SavePhase.error);
    expect(
        container
            .read(documentControllerProvider(id))
            .requireValue
            .nodeIndex[node]!
            .transform
            .position,
        const Vec2(5, 5),
        reason: 'the gesture is retained, not lost');
    expect(controller.canUndo, isTrue, reason: 'the commit is one entry');
    expect((await onDisk(id)).rev, 1, reason: 'a failed save never bumps rev');

    // It lands on the next successful write.
    store.failNext = null;
    await controller.flushNow();
    expect(save.value.phase, SavePhase.saved);
    expect((await onDisk(id)).nodeIndex[node]!.transform.position,
        const Vec2(5, 5));
    expect((await onDisk(id)).rev, 2, reason: 'the recovery bumps once');
  });

  // --- The public getters are total ----------------------------------------

  test('canUndo/canRedo/labels do not throw on a document that never loaded',
      () async {
    // `late CommandStack _stack` was assigned only inside `build`'s try, so on
    // notFound/corrupt these public, unguarded getters threw
    // LateInitializationError — straight out of the toolbar that renders the
    // error state.
    final container = ProviderContainer(
      overrides: [
        projectStoreProvider.overrideWithValue(MemoryProjectStore()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(documentControllerProvider('missing'), (_, __) {});
    await expectLater(
      container.read(documentControllerProvider('missing').future),
      throwsA(isA<StoreException>()
          .having((e) => e.failure, 'failure', StoreFailure.notFound)),
    );

    final controller =
        container.read(documentControllerProvider('missing').notifier);
    expect(controller.canUndo, isFalse);
    expect(controller.canRedo, isFalse);
    expect(controller.undoLabel, isNull);
    expect(controller.redoLabel, isNull);
    expect(await controller.undo(), isNull);
    expect(await controller.redo(), isNull);
  });
}
