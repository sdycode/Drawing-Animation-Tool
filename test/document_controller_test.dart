import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
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

  test('a failed save does not wedge the commands behind it', () async {
    final id = seed();
    final (_, controller) = await open(id);

    memory.failNext = StoreFailure.network;
    await expectLater(
      controller.moveAnchorAt(node, a1, const Vec2(5, 5), atT: 0.5),
      throwsA(isA<StoreException>()),
    );
    await controller.moveAnchorAt(node, a2, const Vec2(7, 7), atT: 0.5);

    final doc = await reload(id);
    expect(poseOf(doc, a2)?.position, const Vec2(7, 7));
    expect(doc.rev, 2, reason: 'the failed save never bumped it');
  });

  test('a newer-schema document refuses every save path', () async {
    // docs/v3/02 §1 rule 7. `Document.isReadOnly` existed and was unit-tested,
    // but nothing consulted it: the editor happily wrote a schemaVersion-4
    // document back with `rev` bumped and every v4-only field stripped, because
    // key preservation does not reach `Anchor`, `PathData`, `Fill`, `Stroke` or
    // `Transform2` — a v4 addition there is a version bump, not an unknown key.
    final id = seed(schemaVersion: 4);
    final (container, controller) = await open(id);

    final before = await memory.load(id);
    expect(container.read(documentControllerProvider(id)).value!.isReadOnly,
        isTrue);

    await expectLater(
      controller.moveAnchorAt(node, a1, const Vec2(5, 5), atT: 0.5),
      throwsA(isA<StoreException>()
          .having((e) => e.failure, 'failure', StoreFailure.readOnly)),
    );
    await expectLater(
        controller.rename('renamed'), throwsA(isA<StoreException>()));

    expect(store.saves, 0, reason: 'the gate is before the store, not after');
    expect(await memory.load(id), before, reason: 'byte-identical on disk');
  });
}
