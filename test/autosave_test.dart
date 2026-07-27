import 'dart:async';
import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/save_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M7 F10.3 — debounced autosave and the save indicator.
///
/// The default `autosaveDebounceProvider` is zero (eager save), so every other
/// test persists synchronously. These override it to a real settle window and
/// assert the *debounce itself*: a burst coalesces into one write (AC-10.3.1),
/// the indicator walks saved → dirty → saved (AC-10.3.3), and a pending edit is
/// not lost when the controller is torn down.
class _CountingStore implements ProjectStore {
  _CountingStore(this._inner);

  final ProjectStore _inner;

  /// Incremented synchronously at the start of every write, so a test sees the
  /// count the instant a write is *issued* (even a fire-and-forget dispose one).
  int saves = 0;

  @override
  Future<List<ProjectSummary>> list() => _inner.list();

  @override
  Future<String?> load(String id) => _inner.load(id);

  @override
  Future<void> save(String id, String json) {
    saves++;
    return _inner.save(id, json);
  }

  @override
  Future<void> delete(String id) => _inner.delete(id);
}

void main() {
  const node = NodeId('p1');
  late MemoryProjectStore memory;
  late _CountingStore store;

  String seed() {
    final base = Document.create(name: 'Sketch').copyWith(
          root: GroupNode(
            id: const NodeId('n-root'),
            name: 'Root',
            children: [
              PathNode(
                id: node,
                name: 'Tri',
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

  /// Opens [id] with a real settle [debounce]. Returns the container too so a
  /// test can dispose it on its own terms (the teardown-flush test disposes mid
  /// body; the rest register [addTearDown]).
  Future<(ProviderContainer, DocumentController, ValueNotifier<SaveState>)> open(
      String id, Duration debounce) async {
    final c = ProviderContainer(overrides: [
      projectStoreProvider.overrideWithValue(store),
      autosaveDebounceProvider.overrideWithValue(debounce),
    ]);
    c.listen(documentControllerProvider(id), (_, __) {});
    await c.read(documentControllerProvider(id).future);
    return (
      c,
      c.read(documentControllerProvider(id).notifier),
      c.read(saveStateProvider(id)),
    );
  }

  test('AC-10.3.1: a burst of edits debounces into ONE write, deferred to settle',
      () async {
    final id = seed();
    final (c, controller, save) = await open(id, const Duration(milliseconds: 40));
    addTearDown(c.dispose);

    // Five discrete edits in quick succession. With a real settle window every
    // write is deferred — none has reached the store yet — and the indicator
    // reads dirty throughout.
    for (var i = 1; i <= 5; i++) {
      await controller.rename('name-$i');
      expect(store.saves, 0, reason: 'debounced: nothing written mid-burst');
      expect(save.value.phase, SavePhase.dirty);
    }

    // Forcing the flush coalesces the whole burst into ONE write of the latest
    // document, one rev bump.
    await controller.flushNow();
    expect(store.saves, 1, reason: 'five edits, one write');
    expect(save.value.phase, SavePhase.saved);
    expect((await onDisk(id)).name, 'name-5', reason: 'the latest edit persisted');
    expect((await onDisk(id)).rev, 2, reason: 'one bump for the coalesced write');
  });

  test('AC-10.3.1: the debounce timer flushes on its own once edits settle',
      () async {
    final id = seed();
    final (c, controller, save) = await open(id, const Duration(milliseconds: 20));
    addTearDown(c.dispose);
    await controller.rename('typed');
    expect(store.saves, 0);

    // Let the settle window elapse: the timer fires and writes once, unassisted.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(store.saves, 1, reason: 'the timer flushed without an explicit flush');
    expect(save.value.phase, SavePhase.saved);
    expect((await onDisk(id)).name, 'typed');
  });

  test('AC-10.3.3: the indicator walks saved → dirty → saved across one edit',
      () async {
    final id = seed();
    final (c, controller, save) = await open(id, const Duration(milliseconds: 20));
    addTearDown(c.dispose);
    expect(save.value.phase, SavePhase.saved,
        reason: 'a freshly opened document is clean');

    await controller.rename('x');
    expect(save.value.phase, SavePhase.dirty,
        reason: 'an edit is dirty until it settles');

    await controller.flushNow();
    expect(save.value.phase, SavePhase.saved,
        reason: 'and saved once the write lands');
    expect(save.value.lastSaved, isNotNull, reason: 'a save stamps the time');
  });

  test('a pending edit is flushed when the controller is disposed', () async {
    final id = seed();
    // A long window so nothing settles on its own before teardown.
    final (c, controller, _) = await open(id, const Duration(seconds: 30));
    await controller.rename('unsaved-at-teardown');
    expect(store.saves, 0, reason: 'still inside the settle window');

    // Disposing the container tears the controller down; the teardown flush must
    // write the pending edit best-effort so it is not lost (AC-10.3.1 safety).
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(store.saves, 1, reason: 'the pending edit was flushed on dispose');
    expect((await onDisk(id)).name, 'unsaved-at-teardown');
  });

  test('teardown mid-drag drops the uncommitted gesture but keeps the pending '
      'edit (docs/v3/08 §1)', () async {
    final id = seed();
    final (c, controller, _) = await open(id, const Duration(seconds: 30));
    // A committed discrete edit, pending in the settle window.
    await controller.rename('kept');
    // A gesture still OPEN: an anchor moved but never committed.
    await controller.beginGesture(label: 'Move');
    await controller.moveAnchorAt(
        node, const AnchorId('b0'), const Vec2(99, 99),
        atT: null);
    expect(store.saves, 0, reason: 'nothing written mid-span');

    // Teardown mid-span. The teardown flush must write only the committed base —
    // an unfinished drag must not leak to storage.
    c.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final disk = await onDisk(id);
    expect(disk.name, 'kept', reason: 'the committed pending edit is preserved');
    final b0 = (disk.nodeIndex[node]! as PathNode)
        .path
        .anchors
        .firstWhere((a) => a.id == const AnchorId('b0'));
    expect(b0.position, const Vec2(0, 0),
        reason: 'the uncommitted drag (b0 → 99,99) is NOT persisted');
  });

  test('a failed teardown write is swallowed, not an unhandled async error '
      '(docs/v3/08 §1)', () async {
    final id = seed();
    final (c, controller, _) = await open(id, const Duration(seconds: 30));
    await controller.rename('doomed');
    expect(store.saves, 0);

    // The teardown write will fail. It must be swallowed best-effort, never
    // escape to the zone as an unhandled async error.
    memory.failNext = StoreFailure.network;
    Object? uncaught;
    await runZonedGuarded(() async {
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }, (e, _) => uncaught = e);

    expect(store.saves, 1, reason: 'the teardown write was attempted');
    expect(uncaught, isNull,
        reason: 'the failed teardown write did not escape as an unhandled '
            'async error');
  });
}
