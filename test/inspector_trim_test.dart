import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/inspector/widgets/inspector_panel.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M6 — the `PathTrim` authoring half of F8.1 (the evaluator's `applyTrim` is
/// already green). The inspector's Trim section is the seam "Draw-on trim — not
/// yet available" made real: three percentage fields (Trim start / end / offset),
/// each keyable as a `ScalarTrack`, routed static-vs-keyframe **exactly** like
/// the transform/paint fields.
///
/// These pin what makes trim authoring trustworthy: an untracked edit writes the
/// static `PathTrim` (clamped 0..1) as one 'Trim' undo entry that survives a
/// reload; the AC-8.1.2 draw-on-then-fade authored **through the UI** shows up on
/// the EVALUATED scene; a tracked field is WYSIWYG at the playhead and a scrub
/// rebuilds no panel; and `end <= start` renders nothing without crashing.
void main() {
  const Vec2 artboard = Vec2(400, 400);
  const NodeId sq = NodeId('sq');
  const PropertyKey trimEnd = PropertyKey(PropKey.trimEnd);

  // A closed square (perimeter 160) with a stroke, so a partial trim reveals a
  // measurable fraction of its arc.
  PathNode strokedSquare(String id) => PathNode(
        id: NodeId(id),
        name: id,
        path: PathData(
          anchors: const [
            Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
            Anchor(id: AnchorId('a1'), position: Vec2(40, 0)),
            Anchor(id: AnchorId('a2'), position: Vec2(40, 40)),
            Anchor(id: AnchorId('a3'), position: Vec2(0, 40)),
          ],
          closed: true,
        ),
        fills: const [
          Fill(id: PaintId('f'), paint: SolidPaint(Rgba(0.3, 0.5, 0.9, 1.0))),
        ],
        strokes: const [
          Stroke(id: PaintId('s'), paint: SolidPaint(Rgba.black), width: 3),
        ],
      );

  Document baseDoc(List<Node> children) {
    final base = Document.create(name: 'Sketch', artboard: artboard);
    return base.copyWith(
      root:
          GroupNode(id: base.root.id, name: base.root.name, children: children),
    );
  }

  ProviderContainer containerFor(MemoryProjectStore store) => ProviderContainer(
        overrides: [projectStoreProvider.overrideWithValue(store)],
      );

  Widget harness(ProviderContainer container, String id) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: EditorShell(projectId: id)),
      );

  Document docOf(ProviderContainer c, String id) =>
      c.read(documentControllerProvider(id)).requireValue;

  PathNode pathOf(ProviderContainer c, String id, [NodeId node = sq]) =>
      docOf(c, id).nodeIndex[node]! as PathNode;

  PathTrim trimOf(ProviderContainer c, String id, [NodeId node = sq]) =>
      pathOf(c, id, node).trim;

  DocumentController ctrl(ProviderContainer c, String id) =>
      c.read(documentControllerProvider(id).notifier);

  ScalarTrack? scalarOf(Document doc, PropKey prop, [NodeId node = sq]) =>
      doc.defaultAnimation?.tracksFor(node).scalar(prop);

  Future<Document> reloaded(MemoryProjectStore store, String id) async =>
      Document.fromJson(
          jsonDecode((await store.load(id))!) as Map<String, Object?>);

  Future<({ProviderContainer c, String id, MemoryProjectStore store})> open(
    WidgetTester tester,
    Document doc, {
    NodeId select = sq,
  }) async {
    final d = doc.bumpRev();
    final store = MemoryProjectStore({d.id: jsonEncode(d.toJson())});
    final c = containerFor(store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, d.id));
    await tester.pumpAndSettle();
    c.read(editorControllerProvider.notifier).selectNode(ScenePath(select));
    await tester.pumpAndSettle();
    return (c: c, id: d.id, store: store);
  }

  /// The inspector is a lazy `ListView`; the trim rows sit below the fold, so
  /// scroll them in before finding. (Mirrors `inspector_paint_test`.)
  Future<Finder> reveal(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    final list = find
        .descendant(
          of: find.byKey(const Key('inspector-transform')),
          matching: find.byType(Scrollable),
        )
        .first;
    if (target.evaluate().isEmpty) {
      await tester.drag(list, const Offset(0, 3000));
      await tester.pumpAndSettle();
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(target, 90, scrollable: list);
        await tester.pumpAndSettle();
      }
    }
    // Built (in the ListView cache) is not the same as hittable — scroll the row
    // fully into the viewport so a tap never lands under the shell header.
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    return target;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(await reveal(tester, key));
    await tester.pumpAndSettle();
  }

  Future<void> commitField(WidgetTester tester, String key, String text) async {
    await tester.enterText(await reveal(tester, key), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String key) => tester
      .widget<EditableText>(find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ))
      .controller
      .text;

  void seekTo(ProviderContainer c, double t) {
    c.read(editorControllerProvider.notifier).commitPlayhead(t);
    c.read(playheadProvider).value = t;
  }

  Future<void> ctrlZ(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  // --- AC-8.1.1 — the three fields, static write, clamp, reload, undo -------

  testWidgets(
      'the Trim section shows start/end/offset for a PathNode; an untracked '
      'Trim end edit writes the static PathTrim, ONE "Trim" undo entry, survives '
      'a reload (AC-8.1.1)', (tester) async {
    final t = await open(tester, baseDoc([strokedSquare('sq')]));

    // All three fields are present (per-PathNode, AC-8.1.10).
    for (final k in const [
      'inspector-trim-start',
      'inspector-trim-end',
      'inspector-trim-offset',
    ]) {
      expect(await reveal(tester, k), findsOneWidget);
    }
    expect(trimOf(t.c, t.id).isFull, isTrue, reason: 'starts at the full trim');

    // Untracked edit → SetTrimCommand writes the static PathTrim (50% → 0.5).
    await commitField(tester, 'inspector-trim-end', '50');
    expect(trimOf(t.c, t.id).end, closeTo(0.5, 1e-12),
        reason: '50% is stored as 0.5, not 50');
    expect(trimOf(t.c, t.id).start, 0.0);
    expect(trimOf(t.c, t.id).offset, 0.0);
    expect(scalarOf(docOf(t.c, t.id), PropKey.trimEnd), isNull,
        reason: 'an untracked field writes the static value, not a keyframe');
    expect(ctrl(t.c, t.id).undoLabel, 'Trim');

    // Survives a reload — trim is authored, not ephemeral.
    expect(
        (await reloaded(t.store, t.id)).nodeIndex[sq],
        isA<PathNode>()
            .having((n) => n.trim.end, 'saved end', closeTo(0.5, 1e-12)));

    // One entry: a single undo restores the full trim.
    await ctrlZ(tester);
    expect(trimOf(t.c, t.id).isFull, isTrue);
    expect(ctrl(t.c, t.id).canUndo, isFalse, reason: 'exactly one entry');

    // The offset channel authors too.
    await commitField(tester, 'inspector-trim-offset', '25');
    expect(trimOf(t.c, t.id).offset, closeTo(0.25, 1e-12));

    // Values clamp to 0..100% at the mutation (a fraction outside 0..1 is a bad
    // write, like opacity). From a real 0.5, 150% clamps to 1.0.
    await commitField(tester, 'inspector-trim-end', '50');
    await commitField(tester, 'inspector-trim-end', '150');
    expect(trimOf(t.c, t.id).end, 1.0, reason: '150% clamps to 100%');
    expect(fieldText(tester, 'inspector-trim-end'), '100');
    await commitField(tester, 'inspector-trim-start', '30');
    await commitField(tester, 'inspector-trim-start', '-10');
    expect(trimOf(t.c, t.id).start, 0.0, reason: 'a negative clamps to 0%');
    expect(tester.takeException(), isNull);
  });

  // --- AC-8.1.2 — draw-on then fade, authored BY HAND through the UI --------

  testWidgets(
      'AC-8.1.2: keying trimEnd 0→1 then opacity 1→0 draws the stroke ON, then '
      'fades it — asserted on the EVALUATED scene (§13.4 draw-on-then-fade)',
      (tester) async {
    final t = await open(tester, baseDoc([strokedSquare('sq')]));

    // Phase 1 authoring — trimEnd reveals across [0, 0.5].
    // t=0: static write end=0, then the empty diamond keys 0 → the track is born.
    seekTo(t.c, 0.0);
    await commitField(tester, 'inspector-trim-end', '0');
    await tapKey(tester, 'kf-trimEnd');
    final te0 = scalarOf(docOf(t.c, t.id), PropKey.trimEnd)!;
    expect(te0.keyCount, 1);
    expect(te0.keys.single.value, closeTo(0.0, 1e-9),
        reason: 'the empty diamond keyed the current value (0)');

    // t=0.5: the field is tracked now → editing upserts the keyframe (1.0).
    seekTo(t.c, 0.5);
    await commitField(tester, 'inspector-trim-end', '100');
    final teTrack = scalarOf(docOf(t.c, t.id), PropKey.trimEnd)!;
    expect(teTrack.keyCount, 2, reason: 'edit-at-keyframe upserts at 0.5');
    expect(
        teTrack.keys.map((k) => k.t), [closeTo(0.0, 1e-9), closeTo(0.5, 1e-9)]);
    expect(teTrack.keys[1].value, closeTo(1.0, 1e-9));

    // Phase 2 authoring — opacity fades across [0.5, 1.0].
    // t=0.5: opacity untracked at 100% → the diamond keys the current 1.0.
    await tapKey(tester, 'kf-opacity');
    // t=1.0: tracked → editing upserts the fade-to-0 keyframe.
    seekTo(t.c, 1.0);
    await commitField(tester, 'inspector-opacity', '0');
    final opTrack = scalarOf(docOf(t.c, t.id), PropKey.opacity)!;
    expect(opTrack.keyCount, 2, reason: 'opacity keyed 1 → 0 over [0.5, 1.0]');

    // Now the exit behaviour, read off the EVALUATED scene at several playheads.
    final doc = docOf(t.c, t.id);
    final animId = doc.defaultAnimation!.id;

    double revealedArc(double at) {
      final geo = evaluate(doc, [AnimationMix(animId, at)])
          .byPath[const ScenePath(sq)]!
          .geometry;
      return geo == null ? 0.0 : ArcTable.build(geo).total;
    }

    double opacityAt(double at) => evaluate(doc, [AnimationMix(animId, at)])
        .byPath[const ScenePath(sq)]!
        .worldOpacity;

    final full = revealedArc(0.5); // trimEnd == 1 → the whole perimeter
    expect(full, greaterThan(0));

    // Draws ON: the revealed arc length grows 0 → full across [0, 0.5].
    expect(revealedArc(0.0), closeTo(0.0, 1e-9),
        reason: 'trimEnd 0 with trimStart 0 reveals nothing');
    expect(revealedArc(0.25), greaterThan(revealedArc(0.0)));
    expect(revealedArc(0.25), lessThan(full),
        reason: 'mid-reveal shows a partial arc');
    expect(revealedArc(0.5), closeTo(full, 1e-6),
        reason: 'fully drawn on by 0.5');

    // THEN fades: opacity 1 → 0 across [0.5, 1.0], while it stays fully drawn.
    expect(opacityAt(0.5), closeTo(1.0, 1e-9));
    expect(opacityAt(0.75), closeTo(0.5, 1e-9));
    expect(opacityAt(1.0), closeTo(0.0, 1e-9), reason: 'faded out at the end');
    expect(revealedArc(1.0), closeTo(full, 1e-6),
        reason: 'still fully revealed while it fades');
    expect(tester.takeException(), isNull);
  });

  // --- AC-6.2.6 / AC-13.3 — a tracked trim field is WYSIWYG, scrub-safe -----

  testWidgets(
      'a tracked Trim end field shows the value sampled at the playhead, and a '
      'scrub rebuilds NO panel (AC-6.2.6, AC-13.3)', (tester) async {
    // Key trimEnd 0 → 1 over [0, 0.5] directly, then drive the UI.
    var doc = baseDoc([strokedSquare('sq')]);
    doc = KeyframeOps.keyAt(doc, sq, trimEnd, 0.0, 0.0);
    doc = KeyframeOps.keyAt(doc, sq, trimEnd, 0.5, 1.0);
    final t = await open(tester, doc);

    // Reveal the field first (scrolling rebuilds), then measure from a baseline.
    await reveal(tester, 'inspector-trim-end');
    expect(fieldText(tester, 'inspector-trim-end'), '0',
        reason: 'at the settled playhead (0) the field samples key 0 → 0%');

    final baseline = InspectorPanel.debugBuildCount;
    seekTo(t.c, 0.5);
    await tester.pump();

    expect(fieldText(tester, 'inspector-trim-end'), '100',
        reason: 'the field shows what the canvas shows at 0.5 (100%), not the '
            'static rest value');
    expect(InspectorPanel.debugBuildCount, baseline,
        reason: 'a scrub writes only playhead.value — only the leaf field text '
            'repaints, the panel does not rebuild (AC-13.3)');

    // Typing at the playhead writes THAT key (no jump from a stale display).
    await commitField(tester, 'inspector-trim-end', '80');
    final track = scalarOf(docOf(t.c, t.id), PropKey.trimEnd)!;
    expect(track.keyCount, 2, reason: 'the key at 0.5 was replaced, not added');
    expect(track.keys[1].value, closeTo(0.8, 1e-9));
    expect(track.keys[0].value, closeTo(0.0, 1e-9),
        reason: 'the key at 0 is untouched');
    expect(tester.takeException(), isNull);
  });

  // --- AC-8.1.3 — end<=start renders nothing, never crashes the panel -------

  testWidgets(
      'end <= start renders empty geometry without crashing the panel, and '
      'the values still clamp to 0..100% (AC-8.1.3)', (tester) async {
    final t = await open(tester, baseDoc([strokedSquare('sq')]));

    await commitField(tester, 'inspector-trim-start', '80');
    await commitField(tester, 'inspector-trim-end', '30');
    expect(trimOf(t.c, t.id).start, closeTo(0.8, 1e-12));
    expect(trimOf(t.c, t.id).end, closeTo(0.3, 1e-12));

    // The panel is calm — no throw, and the section is still there.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('inspector-trim')), findsOneWidget);

    // Evaluated: end <= start reveals nothing. Never a throw, never a null deref.
    final geo = evaluate(docOf(t.c, t.id), const <AnimationMix>[])
        .byPath[const ScenePath(sq)]!
        .geometry;
    expect(geo, isNotNull);
    expect(geo!.anchors, isEmpty,
        reason: 'end <= start renders empty geometry');
    expect(tester.takeException(), isNull);
  });

  // --- AC-6.2.6 / AC-2.2.7 — a diamond key is ONE entry, nothing ephemeral --

  testWidgets(
      'a trim diamond key is ONE undo entry, round-trips through the store, and '
      'writes nothing ephemeral (AC-6.2.6, AC-2.2.7)', (tester) async {
    final t = await open(tester, baseDoc([strokedSquare('sq')]));
    final revBefore = docOf(t.c, t.id).rev;

    // Empty diamond → keys the current trimStart (0.0), creating the ScalarTrack.
    await tapKey(tester, 'kf-trimStart');
    expect(ctrl(t.c, t.id).undoLabel, 'Key');
    final keyed = scalarOf(docOf(t.c, t.id), PropKey.trimStart)!;
    expect(keyed.keyCount, 1);
    expect(keyed.keys.single.value, closeTo(0.0, 1e-9));

    // Persisted, and nothing ephemeral crossed the wire.
    final raw = (await t.store.load(t.id))!;
    final onDisk = Document.fromJson(jsonDecode(raw) as Map<String, Object?>);
    expect(scalarOf(onDisk, PropKey.trimStart)!.keyCount, 1);
    expect(onDisk.rev, revBefore + 1, reason: 'exactly one save');
    for (final banned in [
      'playhead',
      'selectedKeyframe',
      'selectedAnchors',
      'viewport',
    ]) {
      expect(raw.contains(banned), isFalse, reason: '"$banned" is ephemeral');
    }

    // ONE undo entry: a single undo removes the whole one-key track.
    await ctrlZ(tester);
    expect(scalarOf(docOf(t.c, t.id), PropKey.trimStart), isNull,
        reason: 'one undo reverts the key exactly');
  });
}
