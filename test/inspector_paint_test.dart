import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_core/anim_core.dart' as core show Animation;
import 'package:anim_render/anim_render.dart' show paintScene;
import 'package:drawing_animation_tool/app/common/color_field.dart';
import 'package:drawing_animation_tool/app/common/number_field.dart';
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/inspector/providers.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:drawing_animation_tool/app/state/recipe_guard.dart';
// The domain's `StrokeCap`/`StrokeJoin` are the ones under test; Flutter's
// same-named `dart:ui` enums would shadow them.
import 'package:flutter/material.dart' hide StrokeCap, StrokeJoin;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// M3 — solid fill & solid stroke authoring, and shape-parameter re-editing
/// (F5.1, AC-4.1.5).
///
/// These pin the properties that decide whether paint authoring is trustworthy:
/// **one control commit is one undo entry** and undo really reverts it; every
/// edit **survives a save and reload from the store**, because a paint the user
/// cannot get back after a refresh is worse than one they never applied; **fills
/// paint before strokes** in the evaluated frame, not merely in the order the
/// widgets happen to be listed; and a **gradient-painted node is read-only**,
/// because the ops that would overwrite it throw on purpose and a UI that can
/// reach a throw is a UI that will.
void main() {
  const Vec2 artboard = Vec2(400, 400);
  const NodeId sq = NodeId('sq');

  PathData squarePath() => PathData(
        anchors: const [
          Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
          Anchor(id: AnchorId('a1'), position: Vec2(40, 0)),
          Anchor(id: AnchorId('a2'), position: Vec2(40, 40)),
          Anchor(id: AnchorId('a3'), position: Vec2(0, 40)),
        ],
        closed: true,
      );

  PathNode square(
    String id, {
    List<Fill> fills = const [],
    List<Stroke> strokes = const [],
    ShapeRecipe? recipe,
  }) =>
      PathNode(
        id: NodeId(id),
        name: id,
        path: recipe == null ? squarePath() : recipe.toPath(),
        fills: fills,
        strokes: strokes,
        recipe: recipe,
      );

  ({MemoryProjectStore store, String id}) seed(
    List<Node> children, {
    List<core.Animation> animations = const [],
  }) {
    final base = Document.create(name: 'Sketch', artboard: artboard);
    final doc = base
        .copyWith(
          root: GroupNode(
              id: base.root.id, name: base.root.name, children: children),
          animations: animations,
        )
        .bumpRev();
    return (
      store: MemoryProjectStore({doc.id: jsonEncode(doc.toJson())}),
      id: doc.id,
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

  DocumentController ctrl(ProviderContainer c, String id) =>
      c.read(documentControllerProvider(id).notifier);

  /// The document as it is **on disk**, decoded fresh — the only honest test of
  /// "the edit survived", since the in-memory `Document` would look identical
  /// even if nothing had ever been written.
  Future<Document> reloaded(MemoryProjectStore store, String id) async =>
      Document.fromJson(
          jsonDecode((await store.load(id))!) as Map<String, Object?>);

  Future<({ProviderContainer c, String id, MemoryProjectStore store})> open(
    WidgetTester tester,
    List<Node> children, {
    List<core.Animation> animations = const [],
    NodeId select = sq,
  }) async {
    final s = seed(children, animations: animations);
    final c = containerFor(s.store);
    addTearDown(c.dispose);
    await tester.pumpWidget(harness(c, s.id));
    await tester.pumpAndSettle();
    c.read(editorControllerProvider.notifier).selectNode(ScenePath(select));
    await tester.pumpAndSettle();
    return (c: c, id: s.id, store: s.store);
  }

  /// The inspector is a `ListView`, so a row below the fold is not merely
  /// off-screen — it is not built at all, and `find.byKey` cannot see it.
  Future<Finder> reveal(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));

    // `.first` is the ListView's own viewport: every `TextField` already on
    // screen contributes its own inner `Scrollable`, so an unqualified
    // descendant finder matches a dozen of them.
    final list = find
        .descendant(
          of: find.byKey(const Key('inspector-transform')),
          matching: find.byType(Scrollable),
        )
        .first;

    if (target.evaluate().isEmpty) {
      // Back to the top first. `scrollUntilVisible` only walks one way, and an
      // earlier reveal may have left the panel scrolled *past* the wanted row.
      await tester.drag(list, const Offset(0, 3000));
      await tester.pumpAndSettle();
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(target, 90, scrollable: list);
        await tester.pumpAndSettle();
      }
    }
    // BUILT is not the same as HITTABLE: a taller panel can leave a row inside
    // the ListView's cache extent (so `find` sees it) but scrolled under the
    // shell header, where a tap misses. Scroll it fully into the viewport before
    // returning so the caller always taps a real target.
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    return target;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(await reveal(tester, key));
    await tester.pumpAndSettle();
  }

  /// Type into a field and commit it the way a user does — Enter.
  Future<void> commitField(WidgetTester tester, String key, String text) async {
    await tester.enterText(await reveal(tester, key), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  EditableText editableOf(WidgetTester tester, String key) =>
      tester.widget<EditableText>(find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ));

  /// Undo through the **real keyboard path** (docs/v3/05 §5) — no direct call to
  /// the controller, and no click first: a committed field has already released
  /// focus into the shell's scope, which is the whole reason it does so.
  Future<void> ctrlZ(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Fill solidFill(String id, Rgba color) =>
      Fill(id: PaintId(id), paint: SolidPaint(color));

  // --- AC-5.1.1 — fill authoring ------------------------------------------

  testWidgets(
      'adding a fill is ONE undo entry, Ctrl+Z reverts it, and it survives a '
      'reload (AC-5.1.1)', (tester) async {
    final t = await open(tester, [square('sq')]);
    expect(pathOf(t.c, t.id).fills, isEmpty);
    expect(ctrl(t.c, t.id).canUndo, isFalse);

    await tapKey(tester, 'inspector-add-fill');

    final fills = pathOf(t.c, t.id).fills;
    expect(fills, hasLength(1));
    expect(fills.single.paint, isA<SolidPaint>());
    expect(ctrl(t.c, t.id).undoLabel, 'Add fill');

    // Length-0-or-1 list, serialized as a list from day one.
    final onDisk = await reloaded(t.store, t.id);
    expect((onDisk.nodeIndex[sq]! as PathNode).fills, hasLength(1));

    await ctrlZ(tester);
    expect(pathOf(t.c, t.id).fills, isEmpty);
    expect(ctrl(t.c, t.id).canUndo, isFalse,
        reason: 'the add was a single entry, not two');
  });

  testWidgets(
      'the colour field writes straight sRGB 0..1 through ONE command, and it '
      'round-trips to disk (AC-5.1.1)', (tester) async {
    final t = await open(tester, [
      square('sq', fills: [solidFill('f', Rgba.black)])
    ]);

    await commitField(tester, 'inspector-fill-color', '#FF8800');
    await tester.pumpAndSettle();

    final paint = pathOf(t.c, t.id).fills.single.paint as SolidPaint;
    expect(paint.color.r, closeTo(1.0, 1e-9));
    expect(paint.color.g, closeTo(0x88 / 255, 1e-9));
    expect(paint.color.b, closeTo(0.0, 1e-9));
    expect(paint.color.a, closeTo(1.0, 1e-9),
        reason: 'six digits leave the alpha in force');
    expect(ctrl(t.c, t.id).undoLabel, 'Fill colour');

    final onDisk = await reloaded(t.store, t.id);
    final saved =
        ((onDisk.nodeIndex[sq]! as PathNode).fills.single.paint as SolidPaint)
            .color;
    expect(saved.r, closeTo(1.0, 1e-9));
    expect(saved.g, closeTo(0x88 / 255, 1e-9));

    await ctrlZ(tester);
    expect(
        (pathOf(t.c, t.id).fills.single.paint as SolidPaint).color, Rgba.black);
    expect(ctrl(t.c, t.id).canUndo, isFalse,
        reason: 'Enter committed once — the double-commit bug, not reopened');
  });

  testWidgets(
      'fill opacity, winding rule and visibility each write ONE undo entry and '
      'each survives a reload (AC-5.1.4)', (tester) async {
    final t = await open(tester, [
      square('sq', fills: [solidFill('f', Rgba.black)])
    ]);
    const id = PaintId('f');

    await commitField(tester, 'inspector-fill-opacity', '40');
    expect(pathOf(t.c, t.id).fills.single.opacity, closeTo(0.4, 1e-12),
        reason: '40% is stored as 0.4, not as 40');
    expect(ctrl(t.c, t.id).undoLabel, 'Fill opacity');
    await ctrlZ(tester);
    expect(pathOf(t.c, t.id).fills.single.opacity, 1.0);

    await tapKey(tester, 'inspector-fill-rule-evenOdd');
    expect(pathOf(t.c, t.id).fills.single.rule, FillRule.evenOdd);
    expect(ctrl(t.c, t.id).undoLabel, 'Fill rule');
    expect(
        (await reloaded(t.store, t.id)).nodeIndex[sq],
        isA<PathNode>().having(
            (n) => n.fills.single.rule, 'saved rule', FillRule.evenOdd));
    await ctrlZ(tester);
    expect(pathOf(t.c, t.id).fills.single.rule, FillRule.nonZero);

    await tapKey(tester, 'inspector-fill-visible');
    expect(pathOf(t.c, t.id).fills.single.visible, isFalse);
    expect(ctrl(t.c, t.id).undoLabel, 'Hide fill');
    // A hidden fill is not a removed fill — it keeps its PaintId, so its future
    // tracks survive the toggle and come back with it.
    expect(pathOf(t.c, t.id).fills.single.id, id);
    await ctrlZ(tester);
    expect(pathOf(t.c, t.id).fills.single.visible, isTrue);

    expect(ctrl(t.c, t.id).canUndo, isFalse,
        reason: 'three edits, three undos, nothing left over');
  });

  testWidgets('removing a fill is one undo entry and Ctrl+Z brings it back',
      (tester) async {
    final t = await open(tester, [
      square('sq', fills: [solidFill('f', const Rgba(1, 0, 0))])
    ]);

    await tapKey(tester, 'inspector-fill-remove');
    expect(pathOf(t.c, t.id).fills, isEmpty);
    expect((await reloaded(t.store, t.id)).nodeIndex[sq],
        isA<PathNode>().having((n) => n.fills, 'saved fills', isEmpty));
    expect(find.byKey(const Key('inspector-add-fill')), findsOneWidget,
        reason: 'the section offers to add one again');

    await ctrlZ(tester);
    final back = pathOf(t.c, t.id).fills.single;
    expect(back.id, const PaintId('f'), reason: 'the same PaintId comes back');
    expect((back.paint as SolidPaint).color, const Rgba(1, 0, 0));
  });

  // --- AC-5.1.2 — stroke authoring ----------------------------------------

  testWidgets(
      'adding a stroke is ONE undo entry and it survives a reload (AC-5.1.2)',
      (tester) async {
    final t = await open(tester, [square('sq')]);

    await tapKey(tester, 'inspector-add-stroke');
    expect(pathOf(t.c, t.id).strokes, hasLength(1));
    expect(ctrl(t.c, t.id).undoLabel, 'Add stroke');
    expect(
        (await reloaded(t.store, t.id)).nodeIndex[sq],
        isA<PathNode>()
            .having((n) => n.strokes, 'saved strokes', hasLength(1)));

    await ctrlZ(tester);
    expect(pathOf(t.c, t.id).strokes, isEmpty);
    expect(ctrl(t.c, t.id).canUndo, isFalse);
  });

  testWidgets(
      'stroke colour, width, cap, join, miter limit, opacity and visibility '
      'each write ONE undo entry and each survives a reload (AC-5.1.2)',
      (tester) async {
    final t = await open(tester, [
      square('sq', strokes: [
        const Stroke(id: PaintId('s'), paint: SolidPaint(Rgba.black)),
      ])
    ]);
    Stroke stroke() => pathOf(t.c, t.id).strokes.single;

    await commitField(tester, 'inspector-stroke-color', '#00FF00');
    expect((stroke().paint as SolidPaint).color.g, closeTo(1.0, 1e-9));
    expect(ctrl(t.c, t.id).undoLabel, 'Stroke colour');
    await ctrlZ(tester);
    expect((stroke().paint as SolidPaint).color, Rgba.black);

    await commitField(tester, 'inspector-stroke-width', '6.5');
    expect(stroke().width, 6.5);
    expect(ctrl(t.c, t.id).undoLabel, 'Stroke width');
    await ctrlZ(tester);
    expect(stroke().width, 1.0);

    await tapKey(tester, 'inspector-stroke-cap-round');
    expect(stroke().cap, StrokeCap.round);
    expect(ctrl(t.c, t.id).undoLabel, 'Stroke cap');
    await ctrlZ(tester);
    expect(stroke().cap, StrokeCap.butt);

    await tapKey(tester, 'inspector-stroke-join-bevel');
    expect(stroke().join, StrokeJoin.bevel);
    expect(ctrl(t.c, t.id).undoLabel, 'Stroke join');
    await ctrlZ(tester);
    expect(stroke().join, StrokeJoin.miter);

    await commitField(tester, 'inspector-stroke-miter', '8');
    expect(stroke().miterLimit, 8.0);
    expect(ctrl(t.c, t.id).undoLabel, 'Miter limit');
    await ctrlZ(tester);
    expect(stroke().miterLimit, 4.0);

    await commitField(tester, 'inspector-stroke-opacity', '25');
    expect(stroke().opacity, closeTo(0.25, 1e-12));
    await ctrlZ(tester);
    expect(stroke().opacity, 1.0);

    await tapKey(tester, 'inspector-stroke-visible');
    expect(stroke().visible, isFalse);
    await ctrlZ(tester);
    expect(stroke().visible, isTrue);

    expect(ctrl(t.c, t.id).canUndo, isFalse,
        reason: 'seven edits, seven undos — no commit fired twice');

    // ...and the whole set round-trips once re-applied.
    await commitField(tester, 'inspector-stroke-width', '3');
    await tapKey(tester, 'inspector-stroke-cap-square');
    await tapKey(tester, 'inspector-stroke-join-round');
    await commitField(tester, 'inspector-stroke-miter', '2');
    final saved = (await reloaded(t.store, t.id)).nodeIndex[sq]! as PathNode;
    expect(saved.strokes.single.width, 3.0);
    expect(saved.strokes.single.cap, StrokeCap.square);
    expect(saved.strokes.single.join, StrokeJoin.round);
    expect(saved.strokes.single.miterLimit, 2.0);
  });

  testWidgets('removing a stroke is one undo entry and Ctrl+Z brings it back',
      (tester) async {
    final t = await open(tester, [
      square('sq', strokes: [
        const Stroke(id: PaintId('s'), paint: SolidPaint(Rgba.black), width: 3),
      ])
    ]);

    await tapKey(tester, 'inspector-stroke-remove');
    expect(pathOf(t.c, t.id).strokes, isEmpty);
    await ctrlZ(tester);
    expect(pathOf(t.c, t.id).strokes.single.width, 3.0);
    expect(pathOf(t.c, t.id).strokes.single.id, const PaintId('s'));
  });

  // --- AC-5.1.5 — fills paint first, in the EVALUATED frame ---------------

  testWidgets(
      'FILLS PAINT BEFORE STROKES in the evaluated frame, whichever was added '
      'first (AC-5.1.5)', (tester) async {
    final t = await open(tester, [square('sq')]);

    // Stroke first, deliberately: if the order came from authoring order rather
    // than from the two fields being two fields, this is where it would show.
    await tapKey(tester, 'inspector-add-stroke');
    await tapKey(tester, 'inspector-add-fill');
    await commitField(tester, 'inspector-stroke-width', '4');

    final doc = docOf(t.c, t.id);
    final scene = evaluate(doc, const <AnimationMix>[]);
    final node = scene.byPath[const ScenePath(sq)]!;
    expect(node.fills, hasLength(1));
    expect(node.strokes, hasLength(1));

    // The assertion that matters is on the display list, not on the widget
    // tree: the panel could list Fill above Stroke and still paint them the
    // wrong way round, and only the recorded canvas can tell the difference.
    void painter(Canvas canvas) => paintScene(canvas, scene, doc);
    expect(
      painter,
      paints
        ..path(style: PaintingStyle.fill)
        ..path(style: PaintingStyle.stroke, strokeWidth: 4.0),
    );
  });

  // --- AC-5.1.3 — gradients render, and are never authored ----------------

  testWidgets(
      'a GRADIENT-painted node renders READ-ONLY and offers no control that '
      'could throw (AC-5.1.3)', (tester) async {
    const stops = [
      GradientStop(id: StopId('s0'), offset: 0, color: Rgba(1, 0, 0)),
      GradientStop(id: StopId('s1'), offset: 1, color: Rgba(0, 0, 1)),
    ];
    final t = await open(tester, [
      square('sq', fills: [
        const Fill(
          id: PaintId('grad'),
          paint: LinearGradientPaint(
              start: Vec2(0, 0), end: Vec2(40, 40), stops: stops),
        )
      ], strokes: [
        const Stroke(
          id: PaintId('gstroke'),
          paint: RadialGradientPaint(
              center: Vec2(20, 20), radius: 20, stops: stops),
        )
      ]),
    ]);

    await reveal(tester, 'inspector-fill-readonly');
    expect(find.byKey(const Key('inspector-fill-readonly')), findsOneWidget);
    expect(find.byKey(const Key('inspector-stroke-readonly')), findsOneWidget);
    expect(find.text(kGradientPaintMessage), findsNWidgets(2));

    // Not one control anywhere in the paint section: no colour field to throw
    // through, and nothing offering to replace a gradient with a flat colour.
    expect(
        find.descendant(
            of: find.byKey(const Key('inspector-paint')),
            matching: find.byType(CommittedColorField)),
        findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('inspector-paint')),
            matching: find.byType(CommittedNumberField)),
        findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('inspector-paint')),
            matching: find.byType(Switch)),
        findsNothing);
    expect(find.byKey(const Key('inspector-fill-remove')), findsNothing);
    expect(find.byKey(const Key('inspector-add-fill')), findsNothing,
        reason: 'the node HAS a fill; offering to add another would be a lie');
    expect(tester.takeException(), isNull);

    // Why the panel must not offer one: the op refuses, on purpose. If this ever
    // stops throwing, the read-only branch above is no longer load-bearing and
    // somebody should be told.
    expect(
        () => PaintOps.setFillColor(
            docOf(t.c, t.id), sq, const PaintId('grad'), Rgba.black),
        throwsArgumentError);

    // The gradient survives an unrelated edit and a reload, byte for byte —
    // nothing here flattens what it cannot recreate.
    await commitField(tester, 'inspector-position-x', '12');
    final saved = (await reloaded(t.store, t.id)).nodeIndex[sq]! as PathNode;
    final gradient = saved.fills.single.paint as LinearGradientPaint;
    expect(gradient.stops, hasLength(2));
    expect(gradient.stops.first.color, const Rgba(1, 0, 0));
    expect(gradient.end, const Vec2(40, 40));
    expect(saved.strokes.single.paint, isA<RadialGradientPaint>());
  });

  // --- AC-5.1.6 — a newer client's two fills ------------------------------

  testWidgets(
      'a document with TWO fills round-trips; the UI edits the first, by its '
      'PaintId, and says the other is kept (AC-5.1.6)', (tester) async {
    final t = await open(tester, [
      square('sq', fills: [
        solidFill('f1', const Rgba(1, 0, 0)),
        solidFill('f2', const Rgba(0, 0, 1)),
      ])
    ]);

    await reveal(tester, 'inspector-fill-color');
    expect(
        editableOf(tester, 'inspector-fill-color').controller.text, '#FF0000');
    expect(find.byKey(const Key('inspector-extra-fills')), findsOneWidget,
        reason: 'silent truncation is the half that makes users delete work');

    await commitField(tester, 'inspector-fill-color', '#00FF00');

    final saved = (await reloaded(t.store, t.id)).nodeIndex[sq]! as PathNode;
    expect(saved.fills, hasLength(2), reason: 'no silent truncation');
    expect(saved.fills[0].id, const PaintId('f1'));
    expect((saved.fills[0].paint as SolidPaint).color.g, closeTo(1.0, 1e-9));
    expect((saved.fills[1].paint as SolidPaint).color, const Rgba(0, 0, 1),
        reason: 'the edit was addressed by PaintId, not by list index');
  });

  // --- AC-4.1.5 — shape parameters ----------------------------------------

  testWidgets(
      'a shape-parameter edit REGENERATES the geometry on an untracked node '
      '(AC-4.1.5)', (tester) async {
    final t = await open(tester, [
      square('sq', recipe: const RectRecipe(w: 40, h: 20)),
    ]);

    double width(PathNode n) {
      final xs = n.path.anchors.map((a) => a.position.x);
      return xs.reduce((a, b) => a > b ? a : b) -
          xs.reduce((a, b) => a < b ? a : b);
    }

    expect(width(pathOf(t.c, t.id)), closeTo(40, 1e-9));

    await commitField(tester, 'inspector-shape-w', '80');

    final after = pathOf(t.c, t.id);
    expect((after.recipe! as RectRecipe).w, 80.0);
    expect(width(after), closeTo(80, 1e-9),
        reason:
            'the recipe regenerated the anchors, it did not just record 80');
    expect(ctrl(t.c, t.id).undoLabel, 'Shape');

    expect(
        (await reloaded(t.store, t.id)).nodeIndex[sq],
        isA<PathNode>()
            .having((n) => (n.recipe! as RectRecipe).w, 'saved w', 80.0));

    await ctrlZ(tester);
    expect(width(pathOf(t.c, t.id)), closeTo(40, 1e-9));
    expect(ctrl(t.c, t.id).canUndo, isFalse);
  });

  // M5 — the M4-era "disabled on a tracked node" assertion, rewritten. Tracked
  // recipe regeneration now WORKS: it routes through `PathOps.retopologize`
  // (arc-length correspondence), so the fields are ENABLED and an edit rewrites
  // every keyframe onto the new topology rather than being refused.
  testWidgets(
      'on a PATH-TRACKED node the shape fields are ENABLED, and editing one '
      'RETOPOLOGIZES — the topology becomes the new recipe id set and every '
      'keyframe still poses exactly it (AC-4.1.5, AC-4.3.6)', (tester) async {
    final node = square('sq', recipe: const RectRecipe(w: 40, h: 20));
    final animation = core.Animation(
      id: const AnimationId('anim'),
      name: 'Main',
      tracks: {
        sq: TrackSet({
          const PropertyKey(PropKey.path): PathTrack([
            Keyframe(
                t: 0.0,
                value: PathPose({
                  for (final a in node.path.anchors)
                    a.id: AnchorPose(a.position, a.inTangent, a.outTangent),
                })),
            Keyframe(
                t: 1.0,
                value: PathPose({
                  for (final a in node.path.anchors)
                    a.id: AnchorPose(a.position + const Vec2(5, 5), a.inTangent,
                        a.outTangent),
                })),
          ]),
        }),
      },
    );
    final t = await open(tester, [node], animations: [animation]);

    PathTrack trackOf(Document doc) {
      for (final clip in doc.animations) {
        final track = clip.tracksFor(sq).pathTrack();
        if (track != null) return track;
      }
      fail('expected a path track on sq');
    }

    // The node IS tracked, so the routing predicate the command reads sends this
    // edit through retopologize — never the in-place regeneration that refuses.
    expect(hasPathTrack(docOf(t.c, t.id), sq), isTrue);
    final beforeIds = pathOf(t.c, t.id).path.anchors.map((a) => a.id.v).toSet();
    expect(trackOf(docOf(t.c, t.id)).keyCount, 2);

    // No disabled banner, and the fields are live — the M4-era "come back after
    // M5" state is gone (the shape section is a ListView row, so reveal it first).
    await reveal(tester, 'inspector-shape-w');
    expect(find.byKey(const Key('inspector-shape-disabled')), findsNothing,
        reason: 'M5 makes tracked recipe regeneration work; no refusal');
    for (final field in ['inspector-shape-w', 'inspector-shape-h']) {
      expect(
          tester
              .widget<CommittedNumberField>(await reveal(tester, field))
              .enabled,
          isTrue,
          reason:
              'a tracked node retopologizes; its shape fields are editable');
    }

    // Editing width regenerates the geometry through PathOps.retopologize.
    await commitField(tester, 'inspector-shape-w', '80');

    final after = pathOf(t.c, t.id);
    // The topology is the NEW recipe's anchor set — a rect is four anchors, minted
    // fresh by the op (PathOps is the only route to a topology change, AC-4.3.8).
    expect(after.path.anchors, hasLength(4));
    final newIds = after.path.anchors.map((a) => a.id.v).toList();
    expect(newIds.toSet().intersection(beforeIds), isEmpty,
        reason: 'retopologize mints a fresh id set; the old ids are gone');

    // AC-4.3.6 on the new id set: BOTH keyframes survive and each poses exactly
    // the topology's AnchorId sequence, in order — the disjoint-id-set state the
    // whole of v3 exists to make unrepresentable never reached the evaluator.
    final track = trackOf(docOf(t.c, t.id));
    expect(track.keyCount, 2, reason: 'both keyframes survive the rewrite');
    for (final key in track.keys) {
      expect(key.value.anchors.keys.map((a) => a.v).toList(), newIds,
          reason: 'AC-4.3.6: identical AnchorId sequence at every keyframe');
    }

    // ONE undo entry, labelled for what it did — a retopologise, not an in-place
    // "Shape" regeneration.
    expect(ctrl(t.c, t.id).undoLabel, 'Retopologize');

    // The recipe is cleared — a retopologise is a manual topology edit no recipe
    // regenerates (docs/v3/01 §5) — so the Shape section drops away entirely.
    expect(after.recipe, isNull);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inspector-shape')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recipe this build cannot read is shown, not regenerated',
      (tester) async {
    final t = await open(tester, [
      PathNode(
        id: sq,
        name: 'sq',
        path: squarePath(),
        recipe: const UnknownRecipe({'type': 'spiral', 'turns': 3}),
      )
    ]);

    await reveal(tester, 'inspector-shape-disabled');
    expect(find.text(kUnreadableRecipeMessage), findsOneWidget);
    expect(find.byKey(const Key('inspector-shape-w')), findsNothing,
        reason: 'there are no readable parameters to draw a field for');

    // ...and it is re-emitted verbatim on the next save.
    await commitField(tester, 'inspector-position-x', '5');
    final saved = (await reloaded(t.store, t.id)).nodeIndex[sq]! as PathNode;
    expect(saved.recipe, isA<UnknownRecipe>());
    expect((saved.recipe! as UnknownRecipe).raw['turns'], 3);
  });

  testWidgets('polygon and ellipse parameters author their own recipes',
      (tester) async {
    final t = await open(tester, [
      square('sq', recipe: const EllipseRecipe(rx: 30, ry: 20)),
      square('poly', recipe: const PolygonRecipe(sides: 5, radius: 40)),
    ]);

    await commitField(tester, 'inspector-shape-rx', '50');
    expect((pathOf(t.c, t.id).recipe! as EllipseRecipe).rx, 50.0);

    t.c
        .read(editorControllerProvider.notifier)
        .selectNode(const ScenePath(NodeId('poly')));
    await tester.pumpAndSettle();

    await commitField(tester, 'inspector-shape-sides', '7');
    final poly =
        pathOf(t.c, t.id, const NodeId('poly')).recipe! as PolygonRecipe;
    expect(poly.sides, 7, reason: 'a polygon with 7.0 sides is still an int');

    await tapKey(tester, 'inspector-shape-star');
    expect(
        (pathOf(t.c, t.id, const NodeId('poly')).recipe! as PolygonRecipe).star,
        isTrue);
  });

  // --- AC-4.1.5 — a degenerate shape value can never erase the geometry -----
  //
  // A shape field is a plain number field with no minimum, so `0`, a negative,
  // and `sides: 2` are all committable keystrokes. Each makes `toPath()` empty,
  // and on an UNTRACKED node the old route recorded the empty recipe (recoverable)
  // while on a TRACKED node it retopologized every keyframe onto nothing —
  // silently erasing the animation. The field clamps the recipe at the mutation
  // so the degenerate value can never be authored.

  double shapeWidth(PathNode n) {
    final xs = n.path.anchors.map((a) => a.position.x);
    return xs.reduce((a, b) => a > b ? a : b) -
        xs.reduce((a, b) => a < b ? a : b);
  }

  testWidgets(
      'a degenerate shape value CLAMPS at the field (untracked): the recipe '
      'survives, geometry is regenerated not erased, recoverable in place',
      (tester) async {
    final t = await open(tester, [
      square('sq', recipe: const RectRecipe(w: 40, h: 20)),
      square('poly', recipe: const PolygonRecipe(sides: 5, radius: 40)),
    ]);

    // Width 0 — `toPath()` is empty for a non-positive extent. It clamps to the
    // positive floor instead of authoring nothing.
    await commitField(tester, 'inspector-shape-w', '0');
    final after = pathOf(t.c, t.id);
    expect(after.recipe, isNotNull,
        reason: 'the recipe survives a degenerate entry, unlike an erase');
    expect((after.recipe! as RectRecipe).w, greaterThanOrEqualTo(1.0),
        reason: 'clamped to the positive floor, never 0');
    expect(after.path.anchors, isNotEmpty,
        reason: 'geometry was regenerated at the floor, not wiped to empty');
    expect(ctrl(t.c, t.id).undoLabel, 'Shape',
        reason: 'one ordinary regenerate entry, no assert, no crash');
    expect(tester.takeException(), isNull);

    // A negative extent is degenerate the same way, and clamps the same way.
    await commitField(tester, 'inspector-shape-h', '-5');
    expect(
        (pathOf(t.c, t.id).recipe! as RectRecipe).h, greaterThanOrEqualTo(1.0),
        reason: 'a negative height clamps to the floor');

    // Recoverable IN PLACE: the field is still there (recipe kept), so typing a
    // valid value back just takes — no undo needed.
    await commitField(tester, 'inspector-shape-w', '120');
    expect((pathOf(t.c, t.id).recipe! as RectRecipe).w, 120.0);
    expect(shapeWidth(pathOf(t.c, t.id)), closeTo(120, 1e-9));

    // A polygon needs three sides to enclose an area; `sides: 2` is a line.
    t.c
        .read(editorControllerProvider.notifier)
        .selectNode(const ScenePath(NodeId('poly')));
    await tester.pumpAndSettle();
    await commitField(tester, 'inspector-shape-sides', '2');
    final poly =
        pathOf(t.c, t.id, const NodeId('poly')).recipe! as PolygonRecipe;
    expect(poly.sides, greaterThanOrEqualTo(3),
        reason: 'sides clamps to the 3-side floor, never 2');
    expect(pathOf(t.c, t.id, const NodeId('poly')).path.anchors, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a degenerate shape value on a PATH-TRACKED node does NOT erase the '
      'animation — the keyframes survive, one undo entry, no assert',
      (tester) async {
    final node = square('sq', recipe: const RectRecipe(w: 40, h: 20));
    PathPose poseAt(Vec2 offset) => PathPose({
          for (final a in node.path.anchors)
            a.id: AnchorPose(a.position + offset, a.inTangent, a.outTangent),
        });
    final animation = core.Animation(
      id: const AnimationId('anim'),
      name: 'Main',
      tracks: {
        sq: TrackSet({
          const PropertyKey(PropKey.path): PathTrack([
            Keyframe(t: 0.0, value: poseAt(Vec2.zero)),
            Keyframe(t: 1.0, value: poseAt(const Vec2(5, 5))),
          ]),
        }),
      },
    );
    final t = await open(tester, [node], animations: [animation]);

    PathTrack trackOf(Document doc) {
      for (final clip in doc.animations) {
        final track = clip.tracksFor(sq).pathTrack();
        if (track != null) return track;
      }
      fail('expected a path track on sq');
    }

    expect(hasPathTrack(docOf(t.c, t.id), sq), isTrue);
    expect(trackOf(docOf(t.c, t.id)).keyCount, 2);

    // Committing width 0 clamps to the floor, so a VALID (tiny) rectangle
    // retopologizes — the keyframes are rewritten onto real anchors, never the
    // empty poses the unclamped route produced. No assert(false) trips, because
    // the recipe reaching the command is never degenerate.
    await commitField(tester, 'inspector-shape-w', '0');
    expect(tester.takeException(), isNull);

    final after = pathOf(t.c, t.id);
    expect(after.path.anchors, isNotEmpty,
        reason:
            'the topology is a real (tiny) rect, not the erased empty path');
    final track = trackOf(docOf(t.c, t.id));
    expect(track.keyCount, 2, reason: 'both keyframes survive');
    for (final key in track.keys) {
      expect(key.value.anchors, isNotEmpty,
          reason: 'every keyframe still poses real anchors — NOT erased');
      expect(key.value.anchors.length, after.path.anchors.length,
          reason: 'AC-4.3.6: each keyframe poses exactly the topology');
    }

    // ONE undo entry, and it restores the original 40×20 rect and its keyframes.
    expect(ctrl(t.c, t.id).canUndo, isTrue);
    await ctrlZ(tester);
    final restored = pathOf(t.c, t.id);
    expect(shapeWidth(restored), closeTo(40, 1e-9),
        reason: 'one undo brings back the original width');
    expect(trackOf(docOf(t.c, t.id)).keyCount, 2);
    expect(tester.takeException(), isNull);
  });

  // --- docs/v3/05 §5 — the colour field's focus contract -------------------

  testWidgets(
      'the colour field RELEASES FOCUS on commit and commits EXACTLY ONCE on '
      'Enter (docs/v3/05 §5)', (tester) async {
    final t = await open(tester, [
      square('sq', fills: [solidFill('f', Rgba.black)])
    ]);

    await tester.enterText(
        await reveal(tester, 'inspector-fill-color'), '#123456');
    await tester.pump();
    expect(
        editableOf(tester, 'inspector-fill-color').focusNode.hasFocus, isTrue,
        reason: 'typing focuses the field');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
        editableOf(tester, 'inspector-fill-color').focusNode.hasFocus, isFalse,
        reason: 'a focused DOM input would swallow the next Cmd/Ctrl+Z');

    // Exactly one entry: `onSubmitted` commits and then unfocuses, and the blur
    // listener must not commit the same edit a second time while the first is
    // still in flight. Two entries here would make the first Ctrl+Z look dead.
    expect(ctrl(t.c, t.id).undoLabel, 'Fill colour');
    await ctrlZ(tester);
    expect(
        (pathOf(t.c, t.id).fills.single.paint as SolidPaint).color, Rgba.black);
    expect(ctrl(t.c, t.id).canUndo, isFalse);
  });

  testWidgets('blurring the colour field commits it too', (tester) async {
    final t = await open(tester, [
      square('sq', fills: [solidFill('f', Rgba.black)])
    ]);

    await tester.enterText(
        await reveal(tester, 'inspector-fill-color'), '#ABCDEF');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect((pathOf(t.c, t.id).fills.single.paint as SolidPaint).color.r,
        closeTo(0xAB / 255, 1e-9),
        reason: 'committing only on Enter silently discards the edit');
  });

  testWidgets(
      'an unusable hex reverts and writes nothing; retyping the shown colour '
      'writes nothing either', (tester) async {
    final t = await open(tester, [
      square('sq', fills: [solidFill('f', const Rgba(1, 0.5, 0))])
    ]);

    await commitField(tester, 'inspector-fill-color', '#ZZ');
    expect(ctrl(t.c, t.id).canUndo, isFalse,
        reason: 'a rejected entry is not an edit');
    expect(
        editableOf(tester, 'inspector-fill-color').controller.text, '#FF8000',
        reason: 'the field snaps back to what is actually in force');
    expect(tester.takeException(), isNull);

    // The field is 8 bits per channel; retyping what it shows must not rewrite
    // the document just because the display is quantized.
    await commitField(tester, 'inspector-fill-color', '#FF8000');
    expect(ctrl(t.c, t.id).canUndo, isFalse);
  });

  // --- The panel stays calm for the things it does not author --------------

  testWidgets('a group has no paint section at all, and does not crash',
      (tester) async {
    await open(
      tester,
      [
        GroupNode(
            id: const NodeId('grp'), name: 'grp', children: [square('sq')]),
      ],
      select: const NodeId('grp'),
    );

    expect(find.byKey(const Key('inspector-transform')), findsOneWidget);
    expect(find.byKey(const Key('inspector-paint')), findsNothing,
        reason: 'paint hangs off path nodes only; PaintOps refuses a group');
    expect(find.byKey(const Key('inspector-shape')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
