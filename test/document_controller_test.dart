import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/state/command.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/save_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The save path: one document, one queue, `rev` advancing by exactly one.
///
/// These are controller tests rather than widget tests on purpose. The defect
/// they pin is a *timing* one — two commands issued while a save is in flight —
/// and a widget test cannot make the store slow enough to expose it without
/// also making the gesture unrealistic.
class _SlowStore implements ProjectStore {
  _SlowStore(this._inner, this.delay);

  final ProjectStore _inner;

  /// A Firestore round trip is tens of milliseconds. `MemoryProjectStore`
  /// completes in one microtask, which is exactly why the in-flight window this
  /// test needs does not exist against it.
  final Duration delay;

  int saves = 0;

  @override
  Future<List<ProjectSummary>> list() => _inner.list();

  @override
  Future<String?> load(String id) => _inner.load(id);

  @override
  Future<void> save(String id, String json) async {
    saves++;
    await Future<void>.delayed(delay);
    await _inner.save(id, json);
  }

  @override
  Future<void> delete(String id) => _inner.delete(id);
}

void main() {
  late MemoryProjectStore memory;
  late _SlowStore store;

  const node = NodeId('p1');
  const a1 = AnchorId('b1');
  const a2 = AnchorId('b2');

  /// A stored triangle, so there is something with anchors to pose.
  String seed({int schemaVersion = 3}) {
    final base = Document.create(name: 'Sketch')
        .copyWith(
          root: GroupNode(
            id: const NodeId('n-root'),
            name: 'Root',
            children: [
              PathNode(
                id: node,
                name: 'Triangle',
                path: PathData(anchors: const [
                  Anchor(id: AnchorId('b0'), position: Vec2(0, 0)),
                  Anchor(id: a1, position: Vec2(10, 0)),
                  Anchor(id: a2, position: Vec2(10, 10)),
                ]),
              ),
            ],
          ),
        )
        .bumpRev();

    final json = jsonDecode(jsonEncode(base.toJson())) as Map<String, Object?>;
    json['schemaVersion'] = schemaVersion;

    memory = MemoryProjectStore({base.id: jsonEncode(json)});
    store = _SlowStore(memory, const Duration(milliseconds: 50));
    return base.id;
  }

  Future<Document> reload(String id) async => Document.fromJson(
      jsonDecode((await memory.load(id))!) as Map<String, Object?>);

  Future<(ProviderContainer, DocumentController)> open(String id) async {
    final container = ProviderContainer(
      overrides: [projectStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    // A listener, so the autoDispose family stays alive across the awaits.
    container.listen(documentControllerProvider(id), (_, __) {});
    await container.read(documentControllerProvider(id).future);
    return (container, container.read(documentControllerProvider(id).notifier));
  }

  AnchorPose? poseOf(Document doc, AnchorId anchor) {
    final track = doc.defaultAnimation?.tracksFor(node).pathTrack();
    return track?.keys.last.value.anchors[anchor];
  }

  test('two commands issued while a save is in flight BOTH land', () async {
    // The silent loss: `_document` used to be read at call time, before the
    // in-flight save had assigned `state`, so both commands branched from the
    // same base and the second overwrote the first. Nothing threw, so the
    // command layer's catch never fired and no snackbar appeared — the user
    // dragged one anchor, dragged another within ~200 ms, and the first drag
    // was simply gone.
    final id = seed();
    final (_, controller) = await open(id);

    final first = controller.moveAnchorAt(node, a1, const Vec2(5, 5), atT: 0.5);
    final second =
        controller.moveAnchorAt(node, a2, const Vec2(7, 7), atT: 0.5);
    await Future.wait(<Future<void>>[first, second]);

    final doc = await reload(id);
    expect(poseOf(doc, a1)?.position, const Vec2(5, 5),
        reason: 'the first drag must survive the second');
    expect(poseOf(doc, a2)?.position, const Vec2(7, 7));

    // docs/v3/01 §11: `rev` advances by exactly 1 per persisted save. Two
    // writes reaching storage while it advanced once is the counter v1.1's
    // optimistic concurrency would be built on already undercounting.
    expect(store.saves, 2);
    expect(doc.rev, 3, reason: 'seeded at 1, plus one per persisted save');
  });

  test('a failed save is retained in memory and lands on the next edit',
      () async {
    final id = seed();
    final (container, controller) = await open(id);
    final save = container.read(saveStateProvider(id));

    // AC-10.3.4: a write that fails does not throw and does not lose the edit —
    // it stays in memory and the indicator shows error, with no rev bump.
    memory.failNext = StoreFailure.network;
    await controller.moveAnchorAt(node, a1, const Vec2(5, 5), atT: 0.5);
    expect(save.value.phase, SavePhase.error);
    expect(save.value.failure, StoreFailure.network);

    // The next edit carries the retained one with it: both land in one write,
    // one rev bump, and the indicator recovers to saved.
    await controller.moveAnchorAt(node, a2, const Vec2(7, 7), atT: 0.5);
    expect(save.value.phase, SavePhase.saved);

    final doc = await reload(id);
    expect(poseOf(doc, a1)?.position, const Vec2(5, 5),
        reason: 'the failed edit was retained and saved with the next one');
    expect(poseOf(doc, a2)?.position, const Vec2(7, 7));
    expect(doc.rev, 2,
        reason: 'the failed save bumped nothing; the recovery bumped once');
  });

  test('a no-op edit neither bumps rev nor reaches the store', () async {
    final id = seed();
    final (container, controller) = await open(id);

    // One real edit for a baseline: rev 1 -> 2, one save.
    await controller.moveAnchorAt(node, a1, const Vec2(5, 5), atT: 0.5);
    expect(store.saves, 1);
    expect(container.read(documentControllerProvider(id)).value!.rev, 2);
    final label = controller.undoLabel;

    // The node holds the default `PathTrim.full`; writing it again is an
    // idempotent op that returns the SAME Document. It must not persist — a
    // phantom `rev` bump here is exactly what M7's autosave would wake on.
    await controller.run(const SetTrimCommand(node, PathTrim()));

    expect(store.saves, 1, reason: 'a no-op writes nothing to the store');
    expect(container.read(documentControllerProvider(id)).value!.rev, 2,
        reason: 'no phantom rev bump on an unchanged document');
    expect(controller.undoLabel, label,
        reason: 'no phantom undo entry stacked on the real edit');
  });

  test('a newer-schema document refuses every save path — error, no write',
      () async {
    // docs/v3/02 §1 rule 7. `Document.isReadOnly` existed and was unit-tested,
    // but nothing consulted it: the editor happily wrote a schemaVersion-4
    // document back with `rev` bumped and every v4-only field stripped, because
    // key preservation does not reach `Anchor`, `PathData`, `Fill`, `Stroke` or
    // `Transform2` — a v4 addition there is a version bump, not an unknown key.
    final id = seed(schemaVersion: 4);
    final (container, controller) = await open(id);
    final save = container.read(saveStateProvider(id));

    final before = await memory.load(id);
    expect(container.read(documentControllerProvider(id)).value!.isReadOnly,
        isTrue);

    // The read-only gate lives in `_save`. An edit no longer throws — the flush
    // surfaces the refusal as the error indicator (AC-10.3.4, no modal) and the
    // store is never touched.
    await controller.moveAnchorAt(node, a1, const Vec2(5, 5), atT: 0.5);
    expect(save.value.phase, SavePhase.error);
    expect(save.value.failure, StoreFailure.readOnly);
    await controller.rename('renamed');
    expect(save.value.failure, StoreFailure.readOnly);

    expect(store.saves, 0, reason: 'the gate is before the store, not after');
    expect(await memory.load(id), before, reason: 'byte-identical on disk');
  });
}
