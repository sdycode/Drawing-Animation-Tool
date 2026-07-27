import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/canvas/widgets/canvas_view.dart';
import 'package:drawing_animation_tool/app/features/timeline/widgets/timeline_bar.dart';
import 'package:drawing_animation_tool/app/features/tools/registry.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:drawing_animation_tool/app/state/tool_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M4: the real timeline — per-node/per-property rows, draggable keyframe dots,
/// per-segment easing, and the timeline's own keyboard row.
///
/// Most tests seed the tracks **directly** (via `KeyframeOps`) and mount only
/// [TimelineBar]: the row/dot behaviour is about the timeline, not about the
/// canvas that happens to author path tracks by hand. The three carried-forward
/// tests at the bottom keep the M0 guarantees the scrub still owes — the hot
/// path, the seconds readout, and the playhead never reaching disk — and those
/// still drive the whole editor.
void main() {
  late MemoryProjectStore store;

  const rotation = PropertyKey(PropKey.rotation);

  // --- Direct-seeded fixtures -----------------------------------------------

  PathNode tri(String id, String name) => PathNode(
        id: NodeId(id),
        name: name,
        path: PathData(
          anchors: [
            Anchor(id: AnchorId('$id-a'), position: const Vec2(0, 0)),
            Anchor(id: AnchorId('$id-b'), position: const Vec2(20, 0)),
            Anchor(id: AnchorId('$id-c'), position: const Vec2(20, 20)),
          ],
          closed: true,
        ),
      );

  /// A document on the LOPSIDED 450.2×250.4 board (the default) with [children].
  Document docWith(List<Node> children) {
    final d = Document.create(name: 'Sketch');
    return d.copyWith(root: d.root.copyWith(children: children));
  }

  /// Key `rotation` on [node] at each `{t: value}`.
  Document rotate(Document d, NodeId node, Map<double, double> keys) {
    var doc = d;
    keys.forEach((t, v) {
      doc = KeyframeOps.keyAt(doc, node, rotation, t, v);
    });
    return doc;
  }

  String seed(Document doc) {
    final d = doc.bumpRev(); // rev 1, matching the M0 seed shape
    store = MemoryProjectStore({d.id: jsonEncode(d.toJson())});
    return d.id;
  }

  Future<String> raw(String id) async {
    final s = await store.load(id);
    expect(s, isNotNull, reason: 'the project must still be on disk');
    return s ?? '';
  }

  Future<Document> reload(String id) async =>
      Document.fromJson(jsonDecode(await raw(id)) as Map<String, Object?>);

  List<double> keyTimesOf(Document doc, NodeId node, PropertyKey p) =>
      doc.defaultAnimation?.tracksFor(node).byKey[p]?.keyTimes ??
      const <double>[];

  ScalarTrack scalarTrack(Document doc, NodeId node) =>
      doc.defaultAnimation!.tracksFor(node).scalar(PropKey.rotation)!;

  /// Mounts [TimelineBar] under a fixed height, with a sibling text field so the
  /// "not while typing" guard has something to focus.
  Widget lean(String id, {double height = 420}) => ProviderScope(
        overrides: [projectStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const SizedBox(
                  height: 48,
                  child: TextField(key: Key('sink-field')),
                ),
                SizedBox(height: height, child: TimelineBar(projectId: id)),
              ],
            ),
          ),
        ),
      );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(TimelineBar)),
          listen: false);

  Finder nodeHeader(String id) => find.byKey(Key('node-$id'));
  Finder dot(NodeId node, PropertyKey p, int i) =>
      find.byKey(Key('kf-${node.v}-${p.wire}-$i'));
  Finder seg(NodeId node, PropertyKey p, int i) =>
      find.byKey(Key('seg-${node.v}-${p.wire}-$i'));
  Rect railRect(WidgetTester tester, NodeId node, PropertyKey p) =>
      tester.getRect(find.byKey(Key('rail-${node.v}-${p.wire}')));

  Future<void> expand(WidgetTester tester, String id) async {
    await tester.tap(nodeHeader(id));
    await tester.pumpAndSettle();
  }

  // ==========================================================================
  // Rows & dots
  // ==========================================================================

  testWidgets(
      'a keyed property shows one dot per key at the right x, and dragging a dot '
      'commits one MoveKeyframeCommand', (tester) async {
    const node = NodeId('cog');
    final id =
        seed(rotate(docWith([tri('cog', 'cog')]), node, {0.2: 0.0, 0.7: 1.0}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');

    // A dot per key, positioned by `t` across the rail — pixels appear only here
    // (AC-9.1.4), and node A's key at 0.2 sits at 0.2 with no grid to snap to.
    final rail = railRect(tester, node, rotation);
    for (final pair in [(0, 0.2), (1, 0.7)]) {
      final center = tester.getRect(dot(node, rotation, pair.$1)).center;
      expect(center.dx, closeTo(rail.left + pair.$2 * rail.width, 1.0));
    }

    final before = await reload(id);

    // Drag key 0 from 0.2 to 0.45.
    await tester.drag(dot(node, rotation, 0), Offset(0.25 * rail.width, 0));
    await tester.pumpAndSettle();

    final after = await reload(id);
    expect(after.rev, before.rev + 1, reason: 'exactly one move, one save');
    expect(keyTimesOf(after, node, rotation),
        [closeTo(0.45, 0.01), closeTo(0.7, 1e-9)]);
    // The moved key kept its value — moveKey never touches it.
    expect(scalarTrack(after, node).keys.first.value, 0.0);
  });

  testWidgets(
      'a drag within minSeparation is rejected with a message and no change',
      (tester) async {
    const node = NodeId('cog');
    final id =
        seed(rotate(docWith([tri('cog', 'cog')]), node, {0.5: 0.0, 0.6: 1.0}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');

    final rail = railRect(tester, node, rotation);
    final before = await reload(id);

    // Drop key 0 (0.5) exactly onto key 1 (0.6): a within-minSeparation collision.
    await tester.drag(
        dot(node, rotation, 0), Offset((0.6 - 0.5) * rail.width, 0));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be applied'), findsOneWidget,
        reason: 'the op refuses the merge and the panel surfaces it');
    final after = await reload(id);
    expect(after.rev, before.rev, reason: 'a rejected move never persists');
    expect(keyTimesOf(after, node, rotation),
        [closeTo(0.5, 1e-9), closeTo(0.6, 1e-9)]);
  });

  testWidgets(
      'clicking a dot selects the keyframe and snaps the playhead to its t',
      (tester) async {
    const node = NodeId('cog');
    // An interior key (not the rail edge) so the dot's whole hit box is on-rail.
    final id =
        seed(rotate(docWith([tri('cog', 'cog')]), node, {0.2: 0.0, 0.6: 3.14}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');

    await tester.tap(dot(node, rotation, 1));
    await tester.pumpAndSettle();

    final c = containerOf(tester);
    expect(
        c.read(editorControllerProvider).selectedKeyframe, (node, rotation, 1),
        reason: 'edit-at-keyframe, selection in EditorState (AC-6.2.6)');
    expect(c.read(editorControllerProvider).playhead, closeTo(0.6, 1e-9));
    expect(c.read(playheadProvider).value, closeTo(0.6, 1e-9),
        reason: 'the live notifier snaps too, so the canvas shows that key');
  });

  // ==========================================================================
  // Segment easing (AC-7.1.1 / AC-7.1.2)
  // ==========================================================================

  testWidgets(
      'a different easing on each of three segments issues three commands and '
      'stores three CubicEasings — no preset symbol', (tester) async {
    const node = NodeId('cog');
    final id = seed(rotate(docWith([tri('cog', 'cog')]), node,
        {0.1: 0.0, 0.4: 1.0, 0.7: 2.0, 1.0: 3.0}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');
    final before = await reload(id);

    Future<void> setSeg(int i, String presetId) async {
      await tester.tap(seg(node, rotation, i));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('easing-$presetId')));
      await tester.pumpAndSettle();
    }

    await setSeg(0, 'easeIn');
    await setSeg(1, 'easeOut');
    await setSeg(2, 'backIn');

    final after = await reload(id);
    expect(after.rev, before.rev + 3, reason: 'three independent commands');

    final keys = scalarTrack(after, node).keys;
    // Easing governs the segment LEAVING each key, addressed by the left index.
    expect(keys[0].easing, CubicEasing.easeIn);
    expect(keys[1].easing, CubicEasing.easeOut);
    expect(keys[2].easing, CubicEasing.backIn);
    // The last key's outgoing easing was never touched — it stays the linear
    // model default (AC-7.1.3).
    expect(keys[3].easing, const LinearEasing());

    final set = {keys[0].easing, keys[1].easing, keys[2].easing};
    expect(set, hasLength(3), reason: 'three distinct curves');
    for (final e in set) {
      expect(e, isA<CubicEasing>(),
          reason: 'presets lower to CubicEasing numbers, no symbol (AC-7.1.2)');
    }
  });

  // ==========================================================================
  // Keyboard (docs/v3/05 §5)
  // ==========================================================================

  testWidgets(
      'K keys the selected property at the playhead with its evaluated value',
      (tester) async {
    const node = NodeId('cog');
    final id = seed(rotate(
        docWith([tri('cog', 'cog')]), node, {0.0: 0.0, 0.5: 10.0, 1.0: 20.0}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');

    // Select a key (focuses the timeline) then move the playhead off it.
    await tester.tap(dot(node, rotation, 1));
    await tester.pumpAndSettle();
    final c = containerOf(tester);
    c.read(playheadProvider).value = 0.25;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();

    final after = await reload(id);
    expect(
        keyTimesOf(after, node, rotation),
        [
          closeTo(0.0, 1e-9),
          closeTo(0.25, 1e-9),
          closeTo(0.5, 1e-9),
          closeTo(1.0, 1e-9),
        ],
        reason: 'a new key appears at the playhead');
    // Its value is the evaluated one — the linear midpoint of 0.0 and 10.0.
    expect(scalarTrack(after, node).sampleAt(0.25), closeTo(5.0, 1e-6));
  });

  testWidgets('Shift+K removes the keyframe under the playhead',
      (tester) async {
    const node = NodeId('cog');
    final id = seed(rotate(
        docWith([tri('cog', 'cog')]), node, {0.0: 0.0, 0.5: 1.0, 1.0: 2.0}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');

    // Selecting key 1 snaps the playhead to 0.5 — the key under it.
    await tester.tap(dot(node, rotation, 1));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    final after = await reload(id);
    expect(keyTimesOf(after, node, rotation),
        [closeTo(0.0, 1e-9), closeTo(1.0, 1e-9)]);
  });

  testWidgets(
      'comma and period step between keys, moving the playhead and selection',
      (tester) async {
    const node = NodeId('cog');
    final id = seed(rotate(
        docWith([tri('cog', 'cog')]), node, {0.0: 0.0, 0.5: 1.0, 1.0: 2.0}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');
    await tester.tap(dot(node, rotation, 1)); // playhead 0.5, selected index 1
    await tester.pumpAndSettle();

    final c = containerOf(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.pumpAndSettle();
    expect(c.read(playheadProvider).value, closeTo(1.0, 1e-9));
    expect(
        c.read(editorControllerProvider).selectedKeyframe, (node, rotation, 2));

    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();
    expect(c.read(playheadProvider).value, closeTo(0.5, 1e-9));
    expect(
        c.read(editorControllerProvider).selectedKeyframe, (node, rotation, 1));
  });

  testWidgets('Home and End jump the playhead to 0 and 1', (tester) async {
    const node = NodeId('cog');
    final id =
        seed(rotate(docWith([tri('cog', 'cog')]), node, {0.3: 0.0, 0.8: 1.0}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');
    await tester.tap(dot(node, rotation, 0)); // focus the timeline
    await tester.pumpAndSettle();

    final c = containerOf(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(c.read(playheadProvider).value, closeTo(0.0, 1e-9));
    expect(c.read(editorControllerProvider).playhead, closeTo(0.0, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(c.read(playheadProvider).value, closeTo(1.0, 1e-9));
    expect(c.read(editorControllerProvider).playhead, closeTo(1.0, 1e-9));
  });

  testWidgets('the timeline shortcuts do not fire while a text field has focus',
      (tester) async {
    const node = NodeId('cog');
    final id = seed(rotate(
        docWith([tri('cog', 'cog')]), node, {0.0: 0.0, 0.5: 10.0, 1.0: 20.0}));

    await tester.pumpWidget(lean(id));
    await tester.pumpAndSettle();
    await expand(tester, 'cog');
    await tester.tap(dot(node, rotation, 1)); // focus timeline, select a key
    await tester.pumpAndSettle();
    final c = containerOf(tester);
    c.read(playheadProvider).value = 0.25;

    // Move focus into the text field, then press K.
    await tester.tap(find.byKey(const Key('sink-field')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();

    expect(keyTimesOf(await reload(id), node, rotation), hasLength(3),
        reason: 'K must not fire while an EditableText holds focus');

    // Refocus the timeline and it fires again — proving the guard, not a dead key.
    await tester.tap(dot(node, rotation, 1));
    await tester.pumpAndSettle();
    c.read(playheadProvider).value = 0.25;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(keyTimesOf(await reload(id), node, rotation), hasLength(4));
  });

  // ==========================================================================
  // AC-6.2.5 & AC-6.1.5
  // ==========================================================================

  testWidgets('rendering and scrolling the timeline mutates nothing (AC-6.2.5)',
      (tester) async {
    final children = <Node>[for (var i = 0; i < 6; i++) tri('n$i', 'node $i')];
    var doc = docWith(children);
    for (var i = 0; i < 6; i++) {
      doc = rotate(doc, NodeId('n$i'), {0.1 * (i + 1): i.toDouble(), 0.9: 9.0});
    }
    final id = seed(doc);
    final original = await raw(id);

    // A short panel, so six summary rows overflow and the list actually scrolls.
    await tester.pumpWidget(lean(id, height: 120));
    await tester.pumpAndSettle();

    // Expanding is UI state, not a document edit (done first, while n0 is still
    // at the top and on-screen).
    await tester.tap(nodeHeader('n0'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('timeline-rows')), const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(await raw(id), original,
        reason: 'no build/scroll/expand path writes the document');
    expect((await reload(id)).rev, 1, reason: 'the seed is the only write');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'four nodes with independent keys each show their own rows and dots — '
      'no shared grid (AC-6.1.5)', (tester) async {
    final id = seed(() {
      var doc =
          docWith([tri('a', 'a'), tri('b', 'b'), tri('c', 'c'), tri('d', 'd')]);
      doc = rotate(doc, const NodeId('a'), {0.0: 0.0, 0.5: 1.0, 1.0: 2.0});
      doc = rotate(doc, const NodeId('b'), {0.13: 0.0, 0.77: 1.0});
      doc = rotate(doc, const NodeId('c'), {0.25: 0.0, 0.5: 1.0});
      doc = rotate(doc, const NodeId('d'), {0.9: 0.0});
      return doc;
    }());

    await tester.pumpWidget(lean(id, height: 520));
    await tester.pumpAndSettle();

    for (final n in ['a', 'b', 'c', 'd']) {
      expect(nodeHeader(n), findsOneWidget);
    }

    const expected = {
      'a': [0.0, 0.5, 1.0],
      'b': [0.13, 0.77],
      'c': [0.25, 0.5],
      'd': [0.9],
    };
    for (final entry in expected.entries) {
      await expand(tester, entry.key);
      final node = NodeId(entry.key);
      final rail = railRect(tester, node, rotation);
      for (var i = 0; i < entry.value.length; i++) {
        expect(dot(node, rotation, i), findsOneWidget);
        final center = tester.getRect(dot(node, rotation, i)).center;
        expect(center.dx, closeTo(rail.left + entry.value[i] * rail.width, 1.0),
            reason:
                'node ${entry.key} key $i sits at its OWN t, on its own row');
      }
    }
  });

  // ==========================================================================
  // Carried forward from M0 (the scrub's still-owed guarantees)
  // ==========================================================================

  Widget shell(String id) => ProviderScope(
        overrides: [
          projectStoreProvider.overrideWithValue(store),
          toolResolverProvider.overrideWithValue(toolRegistry()),
        ],
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  String seedEmpty() {
    final doc = Document.create(name: 'Sketch').bumpRev();
    store = MemoryProjectStore({doc.id: jsonEncode(doc.toJson())});
    return doc.id;
  }

  Future<void> drawTriangle(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byKey(const Key('canvas')));
    final first =
        Offset(box.left + box.width * 0.3, box.top + box.height * 0.3);
    for (final o in [
      first,
      Offset(box.left + box.width * 0.7, box.top + box.height * 0.3),
      Offset(box.left + box.width * 0.5, box.top + box.height * 0.7),
      first,
    ]) {
      await tester.tapAt(o);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
  }

  testWidgets('a live scrub rebuilds no canvas widget (AC-9.1.3, the hot path)',
      (tester) async {
    final id = seedEmpty();
    await tester.pumpWidget(shell(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);
    await tester.pumpAndSettle();

    final baseline = CanvasView.debugBuildCount;

    final rail = tester.getRect(find.byKey(const Key('timeline')));
    final gesture =
        await tester.startGesture(rail.centerLeft + const Offset(4, 0));
    for (var i = 1; i <= 20; i++) {
      await gesture.moveBy(Offset(rail.width / 24, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(CanvasView.debugBuildCount, baseline,
        reason: 'the drag writes playhead.value; no provider invalidates');
    expect(find.byKey(const Key('timeline-readout')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the timeline displays seconds derived from durationSeconds',
      (tester) async {
    final doc = Document.create(name: 'Sketch').bumpRev();
    final retimed = doc.copyWith(
      animations: [doc.animations.single.copyWith(durationSeconds: 2.6)],
    );
    store = MemoryProjectStore({retimed.id: jsonEncode(retimed.toJson())});

    await tester.pumpWidget(shell(retimed.id));
    await tester.pumpAndSettle();

    // Scoped to the TimelineBar: the transport bar (M6) now shows its own
    // seconds↔t readout in the same shell, so a bare `findsOneWidget` on the
    // text would find both. This test is about the timeline's readout.
    Finder inTimeline(String text) => find.descendant(
        of: find.byType(TimelineBar), matching: find.textContaining(text));

    expect(inTimeline('/ 2.60 s'), findsOneWidget);
    await tester.drag(find.byKey(const Key('timeline')), const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(inTimeline('2.60 s / 2.60 s'), findsOneWidget);
    expect(inTimeline('t = 1.000'), findsOneWidget);
  });

  testWidgets('the playhead never reaches the saved JSON (AC-2.2.7)',
      (tester) async {
    final id = seedEmpty();
    await tester.pumpWidget(shell(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);
    await tester.drag(find.byKey(const Key('timeline')), const Offset(2000, 0));
    await tester.pumpAndSettle();

    final before = await reload(id);
    final target = (before.root.children.single as PathNode).path.anchors.first;
    final box = tester.getRect(find.byKey(const Key('canvas')));
    final at = box.topLeft +
        Offset(
          (target.position.x / before.artboard.x) * box.width,
          (target.position.y / before.artboard.y) * box.height,
        );
    // A pose edit at t = 1 authors a path track; the drag itself is M3's, only
    // used here to make the file hold a keyframe.
    await tester.dragFrom(at, const Offset(30, 30));
    await tester.pumpAndSettle();

    final json = await raw(id);
    for (final banned in [
      'playhead',
      'playing',
      'selectedKeyframe',
      'selectedAnchors',
      'selection',
      'viewport',
    ]) {
      expect(json.contains(banned), isFalse, reason: '"$banned" is ephemeral');
    }
  });
}
