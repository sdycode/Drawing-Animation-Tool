import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart' show ArtboardPainter, artboardFit;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/canvas/widgets/canvas_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M0 step 5: one `PathTrack`, two keyframes, and a playhead that scrubs.
///
/// The exit criterion these tests pin is reachable **by hand**: draw a triangle,
/// move the playhead to the end, drag an anchor, and the document now holds two
/// keys that differ. Everything else here exists to stop that slice being
/// achieved by a shortcut that does not generalise — a rebuild storm, a
/// playhead written into the file, or a keyframe posing an anchor set the node
/// does not have.
void main() {
  late MemoryProjectStore store;

  String seed({Vec2 artboard = const Vec2(400, 400)}) {
    final doc = Document.create(name: 'Sketch', artboard: artboard).bumpRev();
    store = MemoryProjectStore({doc.id: jsonEncode(doc.toJson())});
    return doc.id;
  }

  Widget harness(String id) => ProviderScope(
        overrides: [projectStoreProvider.overrideWithValue(store)],
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  Future<String> raw(String id) async {
    final s = await store.load(id);
    expect(s, isNotNull, reason: 'the project must still be on disk');
    return s ?? '';
  }

  Future<Document> reload(String id) async =>
      Document.fromJson(jsonDecode(await raw(id)) as Map<String, Object?>);

  Future<void> drawTriangle(WidgetTester tester) async {
    final box = tester.getRect(find.byKey(const Key('canvas')));
    for (final o in [
      Offset(box.left + box.width * 0.3, box.top + box.height * 0.3),
      Offset(box.left + box.width * 0.7, box.top + box.height * 0.3),
      Offset(box.left + box.width * 0.5, box.top + box.height * 0.7),
    ]) {
      await tester.tapAt(o);
      await tester.pumpAndSettle();
    }
  }

  /// Where the overlay draws [anchor], in global coordinates.
  ///
  /// Derived from the *same* [artboardFit] the painters and the hit-test use.
  /// A second hand-rolled mapping here would let a broken app pass — which is
  /// exactly how legacy's y-scaled-by-width bug survived its own test suite.
  Offset anchorOnScreen(WidgetTester tester, Document doc, Anchor anchor) {
    final box = tester.getRect(find.byKey(const Key('canvas')));
    final at = artboardFit(doc.artboard, box.size).apply(anchor.position);
    return box.topLeft + Offset(at.x, at.y);
  }

  /// Drags the scrub bar past its right edge, so `t` clamps to exactly 1.0.
  Future<void> scrubToEnd(WidgetTester tester) async {
    await tester.drag(find.byKey(const Key('timeline')), const Offset(2000, 0));
    await tester.pumpAndSettle();
  }

  PathTrack onlyPathTrack(Document doc) {
    final animation = doc.defaultAnimation;
    expect(animation, isNotNull, reason: 'Document.create mints exactly one');

    final tracks = <PathTrack>[];
    for (final a in doc.animations) {
      for (final set in a.tracks.values) {
        final t = set.pathTrack();
        if (t != null) tracks.add(t);
      }
    }
    expect(tracks, hasLength(1),
        reason: 'one drag on one node authors exactly one path track');
    return tracks.single;
  }

  testWidgets(
      'a drag at the playhead authors two keys at t = 0.0 and t = 1.0, '
      'each posing the node topology exactly', (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);

    await scrubToEnd(tester);

    final before = await reload(id);
    final node = before.root.children.single as PathNode;
    final target = node.path.anchors.first;
    final from = anchorOnScreen(tester, before, target);

    await tester.dragFrom(from, const Offset(40, -30));
    await tester.pumpAndSettle();

    final after = await reload(id);
    final posed = after.root.children.single as PathNode;

    // The rest pose is untouched: a pose edit at a playhead is KEYFRAME-LOCAL
    // (docs/v3/01 §1, governing rule 1). If this drifted, the shape would move
    // at every t at once and the two keys would be indistinguishable.
    expect(posed.path.anchors.first.position, target.position);

    final track = onlyPathTrack(after);
    expect(track.keys.map((k) => k.t).toList(), [0.0, 1.0],
        reason: 'the first drag at t > 0 seeds a t = 0.0 key from the rest '
            'pose, so there are two keys that DIFFER');

    // docs/v3/01 §12's invariant, stated on the wire format rather than in
    // memory: every keyframe poses exactly the node's AnchorId sequence. A pose
    // keyed by index, or a backfill that skipped an anchor, fails here.
    final topology = posed.path.anchors.map((a) => a.id).toList();
    for (final key in track.keys) {
      expect(key.value.anchors.keys.toList(), topology);
    }

    // Two keys that differ, at the dragged anchor and nowhere else.
    final k0 = track.keys.first.value.anchors[target.id];
    final k1 = track.keys.last.value.anchors[target.id];
    expect(k0, isNotNull);
    expect(k1, isNotNull);
    expect(k0?.position.x, closeTo(target.position.x, 1e-9));
    expect(k1?.position.x, greaterThan(target.position.x));
    expect(k1?.position.y, lessThan(target.position.y));
  });

  testWidgets('t = 0.5 evaluates strictly between the two keys',
      (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);
    await scrubToEnd(tester);

    final before = await reload(id);
    final target = (before.root.children.single as PathNode).path.anchors.first;
    await tester.dragFrom(
        anchorOnScreen(tester, before, target), const Offset(60, 40));
    await tester.pumpAndSettle();

    // Asserted on the evaluated Scene, not on pixels: a golden image would go
    // green the moment the shape merely *looks* animated, and a frozen shape
    // drawn at the wrong colour looks animated too.
    final doc = await reload(id);
    final animation = doc.defaultAnimation;
    expect(animation, isNotNull);
    final id0 = animation?.id;
    if (id0 == null) return;

    Vec2 at(double t) {
      final scene = evaluate(doc, [AnimationMix(id0, t)]);
      final resolved = scene.byPath[ScenePath(doc.root.children.single.id)];
      expect(resolved, isNotNull);
      final geometry = resolved?.geometry;
      expect(geometry, isNotNull);
      return geometry!.anchors.firstWhere((a) => a.id == target.id).position;
    }

    final start = at(0.0);
    final end = at(1.0);
    final mid = at(0.5);

    expect(end.x, greaterThan(start.x));
    expect(mid.x, greaterThan(start.x));
    expect(mid.x, lessThan(end.x));
    expect(mid.x, closeTo((start.x + end.x) / 2, 1e-6),
        reason: 'linear easing at u = 0.5 is the midpoint');
    expect(mid.y, closeTo((start.y + end.y) / 2, 1e-6));
  });

  testWidgets('the playhead never reaches the saved JSON', (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);
    await scrubToEnd(tester);

    final before = await reload(id);
    final target = (before.root.children.single as PathNode).path.anchors.first;
    await tester.dragFrom(
        anchorOnScreen(tester, before, target), const Offset(30, 30));
    await tester.pumpAndSettle();

    // AC-2.2.7 as a string search, because that is the only check that cannot
    // be satisfied by a field that merely happens to be zero today. Legacy
    // persisted the playhead and the selection; a file saved mid-selection then
    // referenced ids a later edit deleted, and the document refused to open.
    final json = await raw(id);
    for (final banned in [
      'playhead',
      'playing',
      'selectedAnchors',
      'selection',
      'hover',
      'viewport',
    ]) {
      expect(json.contains(banned), isFalse, reason: '"$banned" is ephemeral');
    }
    // The keyframe it DID author is there, so this is not passing by writing
    // nothing at all.
    expect(json.contains('"path"'), isTrue);
  });

  testWidgets('scrubbing the playhead rebuilds no canvas widget',
      (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);
    await tester.pumpAndSettle();

    // The whole point of `playheadProvider` being a ValueNotifier (docs/v3/04
    // §4): the drag writes `.value`, the two painters repaint through
    // `super(repaint:)`, and `build()` is never entered. Routing it through a
    // provider instead is a named antipattern — it couples every panel to the
    // frame budget, and a rebuild that produces identical pixels is invisible
    // to every other kind of assertion.
    final baseline = CanvasView.debugBuildCount;

    final rail = tester.getRect(find.byKey(const Key('timeline')));
    final gesture =
        await tester.startGesture(rail.centerLeft + const Offset(4, 0));
    for (var i = 1; i <= 20; i++) {
      await gesture.moveBy(Offset(rail.width / 24, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(CanvasView.debugBuildCount, baseline,
        reason: 'a live scrub must rebuild nothing');

    // The readout is the one thing that did change, and it changed by
    // ValueListenableBuilder — a leaf rebuild, not a tree one.
    expect(find.byKey(const Key('timeline-readout')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('keyframe dots appear only after a key exists', (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();

    expect(find.text('0 keys'), findsOneWidget);

    await drawTriangle(tester);
    await tester.pumpAndSettle();
    // Drawing authors no track: the node is fully static and legal
    // (docs/v3/05 §4.1, AC-6.1.4).
    expect(find.text('0 keys'), findsOneWidget);

    await scrubToEnd(tester);
    final before = await reload(id);
    final target = (before.root.children.single as PathNode).path.anchors.first;
    await tester.dragFrom(
        anchorOnScreen(tester, before, target), const Offset(35, 25));
    await tester.pumpAndSettle();

    expect(find.text('2 keys'), findsOneWidget);
  });

  testWidgets('the timeline displays seconds derived from durationSeconds',
      (tester) async {
    // AC-9.1.5: the document stores fractions and the UI derives seconds, so a
    // retime is one field and re-authors no keyframe. Legacy stored 0.769 and
    // could never be retimed at all.
    final doc = Document.create(name: 'Sketch', artboard: const Vec2(400, 400))
        .bumpRev();
    final retimed = doc.copyWith(
      animations: [doc.animations.single.copyWith(durationSeconds: 2.6)],
    );
    store = MemoryProjectStore({retimed.id: jsonEncode(retimed.toJson())});

    await tester.pumpWidget(harness(retimed.id));
    await tester.pumpAndSettle();

    expect(find.textContaining('/ 2.60 s'), findsOneWidget);
    await scrubToEnd(tester);
    expect(find.textContaining('2.60 s / 2.60 s'), findsOneWidget);
    expect(find.textContaining('t = 1.000'), findsOneWidget);
  });

  testWidgets('a drag on empty canvas mutates nothing', (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);

    final box = tester.getRect(find.byKey(const Key('canvas')));
    await tester.dragFrom(
        box.topLeft + const Offset(6, 6), const Offset(40, 8));
    await tester.pumpAndSettle();

    final doc = await reload(id);
    expect(doc.rev, 2, reason: 'the pen commit is the only save so far');
    expect(doc.animations.single.tracks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the whole shape follows the anchor while the drag is in flight',
      (tester) async {
    // Before this, a drag moved a lone overlay dot across a stale outline: the
    // artboard layer kept painting the committed document until release, so the
    // user posed a shape they could not see until they let go. Direct
    // manipulation that only shows its result afterwards is not direct.
    //
    // The preview is the *same* `PathOps.moveAnchor` the release commits, so
    // what is on screen mid-drag cannot disagree with what lands. A separate
    // preview-only geometry path would be a second evaluator (docs/v3/08 §4).
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);
    await scrubToEnd(tester);

    final before = await reload(id);
    final target = (before.root.children.single as PathNode).path.anchors.first;
    final revBefore = before.rev;

    final gesture =
        await tester.startGesture(anchorOnScreen(tester, before, target));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(60, -40));
    await tester.pump();

    // What the artboard layer is drawing, right now, mid-gesture.
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<ArtboardPainter>()
        .single;
    final anim = painter.animation;
    final scene = evaluate(
      painter.document,
      anim == null
          ? const <AnimationMix>[]
          : <AnimationMix>[AnimationMix(anim, 1.0)],
    );
    final geometry =
        scene.drawOrder.map((n) => n.geometry).whereType<PathData>().single;
    final posed = geometry.anchors.firstWhere((a) => a.id == target.id);

    // Screen +x/-y is artboard +x/-y: the fit is a uniform scale plus a
    // translation, never a flip, so the drag's direction survives the mapping.
    expect(posed.position.x, greaterThan(target.position.x),
        reason: 'the painted shape must already hold the dragged position');
    expect(posed.position.y, lessThan(target.position.y));

    // The other two anchors are untouched — a preview that moved the whole
    // shape would also look "live" and would be wrong.
    for (final other
        in (before.root.children.single as PathNode).path.anchors.skip(1)) {
      final still = geometry.anchors.firstWhere((a) => a.id == other.id);
      expect(still.position.x, closeTo(other.position.x, 1e-9));
      expect(still.position.y, closeTo(other.position.y, 1e-9));
    }

    // And none of it has been written: the preview is painted, never saved.
    final onDisk = await reload(id);
    expect(onDisk.rev, revBefore, reason: 'no command runs until release');
    expect(onDisk.animations.single.tracks, isEmpty,
        reason: 'a mid-drag preview must not author a keyframe');

    await gesture.up();
    await tester.pumpAndSettle();

    // On release the commit matches what was previewed.
    final after = await reload(id);
    final committed = onlyPathTrack(after).keys.last.value.anchors[target.id];
    expect(committed, isNotNull);
    expect(committed?.position.x, closeTo(posed.position.x, 1e-9));
    expect(committed?.position.y, closeTo(posed.position.y, 1e-9));
  });

  testWidgets('an unhurried anchor drag deposits no pen click', (tester) async {
    // `BaseTapGestureRecognizer` fires `onTapDown` from `didExceedDeadline()`
    // after `kPressTimeout` (100 ms) whether or not the tap goes on to lose the
    // arena to the pan. Wiring the pen to tap-down therefore meant that any
    // drag where the user pressed and hesitated left a stray point in the pen's
    // pending list — and three unhurried drags committed a phantom triangle
    // whose vertices were the three grab points. On the deployed URL that is
    // M0's exit-criterion gesture: a stranger drags an anchor at a human pace
    // and gets an unexplained blue triangle in their document.
    //
    // `tester.dragFrom` cannot see this — it synthesizes down/move/up with no
    // elapsed time, so the deadline never fires. Hence the explicit pump.
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);
    await scrubToEnd(tester);

    final before = await reload(id);
    final anchors = (before.root.children.single as PathNode).path.anchors;

    for (final target in anchors) {
      final gesture =
          await tester.startGesture(anchorOnScreen(tester, before, target));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    final after = await reload(id);
    expect(after.root.children, hasLength(1),
        reason: 'three slow drags must not commit a fourth-wall triangle');
    expect(find.textContaining('Click 3 more times'), findsOneWidget,
        reason: 'and the pen must not be counting down mid-shape');

    // The drags themselves still did their job.
    expect(onlyPathTrack(after).keyCount, 2);
  });

  testWidgets('a save failure during an anchor drag leaves the editor usable',
      (tester) async {
    final id = seed();
    await tester.pumpWidget(harness(id));
    await tester.pumpAndSettle();
    await drawTriangle(tester);
    await scrubToEnd(tester);

    final before = await reload(id);
    final target = (before.root.children.single as PathNode).path.anchors.first;

    store.failNext = StoreFailure.network;
    await tester.dragFrom(
        anchorOnScreen(tester, before, target), const Offset(40, 40));
    await tester.pumpAndSettle();

    expect(find.text(StoreFailure.network.message), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The document on disk is untouched and `rev` did not advance — a failed
    // save must never bump it (docs/v3/08 §2, last row).
    final doc = await reload(id);
    expect(doc.rev, 2);
    expect(doc.animations.single.tracks, isEmpty);
    expect(find.byKey(const Key('canvas')), findsOneWidget);
    expect(find.byKey(const Key('timeline')), findsOneWidget);
  });
}
