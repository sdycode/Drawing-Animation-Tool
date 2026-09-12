import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/common/ui_prefs.dart';
import 'package:drawing_animation_tool/app/data/memory_project_store.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/editor_shell.dart';
import 'package:drawing_animation_tool/app/features/inspector/widgets/inspector_panel.dart'
    show kNextKeyframeHint, kNextPathKeyHint;
import 'package:drawing_animation_tool/app/features/timeline/widgets/timeline_bar.dart';
import 'package:drawing_animation_tool/app/state/document_controller.dart';
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three editor affordances added for discoverability and comfort: the
/// how-to **guide**, the **resizable timeline**, and the inspector's **field
/// steppers** end-to-end (the widget itself is pinned in
/// `number_field_test.dart`).
///
/// All of it is driven by hand through the real shell, because each one is a
/// claim about the composed editor — a dialog that opens over it, a panel that
/// takes height from its neighbour, a button that has to reach the command
/// stack — and none of those can be true in a unit test of one widget.
void main() {
  const Vec2 artboard = Vec2(400, 400);

  PathNode square(String id) => PathNode(
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
      );

  ({MemoryProjectStore store, String id}) seed() {
    final base = Document.create(name: 'Sketch', artboard: artboard);
    final doc = base
        .copyWith(
          root: GroupNode(
            id: base.root.id,
            name: base.root.name,
            children: [square('sq')],
          ),
        )
        .bumpRev();
    return (
      store: MemoryProjectStore({doc.id: jsonEncode(doc.toJson())}),
      id: doc.id,
    );
  }

  /// Open the editor. [prefs] is the chrome store under test; the default is
  /// the in-memory one, which reports the guide as already seen — so a test
  /// that says nothing about the guide is never handed one.
  Future<({ProviderContainer c, String id, UiPrefs prefs})> open(
    WidgetTester tester, {
    UiPrefs? prefs,
    bool selectNode = false,
  }) async {
    // A realistic editor window. The 800×600 test default is shorter than any
    // browser this ships to, and the timeline's ceiling is a function of window
    // height — measuring the clamp against a window nobody uses would pin the
    // wrong number.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final s = seed();
    final store = prefs ?? MemoryUiPrefs();
    final c = ProviderContainer(overrides: [
      projectStoreProvider.overrideWithValue(s.store),
      uiPrefsProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: EditorShell(projectId: s.id)),
    ));
    await tester.pumpAndSettle();
    if (selectNode) {
      c
          .read(editorControllerProvider.notifier)
          .selectNode(const ScenePath(NodeId('sq')));
      await tester.pumpAndSettle();
    }
    return (c: c, id: s.id, prefs: store);
  }

  // =========================================================================
  // The guide
  // =========================================================================

  group('the how-to guide', () {
    testWidgets('the app-bar button opens it, and the chapters navigate',
        (tester) async {
      await open(tester);
      expect(find.byKey(const Key('editor-guide-dialog')), findsNothing);

      await tester.tap(find.byKey(const Key('editor-guide')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editor-guide-dialog')), findsOneWidget);
      expect(find.text('The layout'), findsWidgets);

      // The keyframe chapter is the reason this screen exists — reachable both
      // from the chapter list and by walking forward.
      await tester.tap(find.byKey(const Key('guide-chapter-3')));
      await tester.pumpAndSettle();
      expect(find.text('Your first keyframe'), findsWidgets);
      expect(find.text('4 of 8'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide-next')));
      await tester.pumpAndSettle();
      expect(find.text('5 of 8'), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-guide-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-guide-dialog')), findsNothing);
    });

    testWidgets('F1 opens it from anywhere in the editor', (tester) async {
      await open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('editor-guide-dialog')), findsOneWidget);
    });

    testWidgets('it opens once for a first-time visitor, and marks itself seen',
        (tester) async {
      final prefs = MemoryUiPrefs(seenGuide: false);
      await open(tester, prefs: prefs);

      expect(find.byKey(const Key('editor-guide-dialog')), findsOneWidget,
          reason: 'the stranger docs/v3/00 §5 ships for gets one prompt');
      expect(await prefs.guideSeen(), isTrue,
          reason: 'marked before it is shown, so a closed tab does not re-nag');
    });

    testWidgets('a returning visitor is never interrupted', (tester) async {
      await open(tester, prefs: MemoryUiPrefs());

      expect(find.byKey(const Key('editor-guide-dialog')), findsNothing);
    });

    testWidgets('every chapter renders — including the ones nobody clicks',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('editor-guide')));
      await tester.pumpAndSettle();

      // Walk the whole guide. A content block that overflows or throws in an
      // unvisited chapter is invisible to a test that only opens the first one.
      for (var i = 1; i <= 7; i++) {
        await tester.tap(find.byKey(const Key('guide-next')));
        await tester.pumpAndSettle();
        expect(find.text('${i + 1} of 8'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'chapter ${i + 1}');
      }

      // The last page closes the guide rather than dead-ending on a Next.
      await tester.tap(find.byKey(const Key('guide-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-guide-dialog')), findsNothing);
    });

    testWidgets('on a narrow window the chapters become a strip, not a squeeze',
        (tester) async {
      await open(tester);
      tester.view.physicalSize = const Size(700, 620);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('editor-guide')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guide-chip-0')), findsOneWidget);
      expect(find.byKey(const Key('guide-chapter-0')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('guide-chip-3')));
      await tester.pumpAndSettle();
      expect(find.text('Your first keyframe'), findsWidgets);
    });

    testWidgets('a broken preference store does not produce a modal',
        (tester) async {
      await open(tester, prefs: _BrokenUiPrefs());

      expect(find.byKey(const Key('editor-guide-dialog')), findsNothing,
          reason: 'unreadable reads as seen — never a dialog on every load');
    });
  });

  // =========================================================================
  // The resizable timeline
  // =========================================================================

  group('the timeline height', () {
    double heightOf(WidgetTester tester) =>
        tester.getSize(find.byType(TimelineBar)).height;

    testWidgets('starts at the default and grows when the grip is dragged up',
        (tester) async {
      final opened = await open(tester);
      expect(heightOf(tester), EditorShell.timelineHeight);

      await tester.drag(
          find.byKey(const Key('timeline-resize')), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(heightOf(tester),
          closeTo(EditorShell.timelineHeight + 120, 1.0),
          reason: 'dragging up grows the panel by exactly what the edge moved');
      expect(await opened.prefs.timelineHeight(),
          closeTo(EditorShell.timelineHeight + 120, 1.0),
          reason: 'the height is remembered for the next visit');
    });

    testWidgets('it stops at the minimum, however far down it is dragged',
        (tester) async {
      await open(tester);

      await tester.drag(
          find.byKey(const Key('timeline-resize')), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(heightOf(tester), EditorShell.timelineMinHeight,
          reason: 'a drag must not be able to hide the panel');
    });

    testWidgets('it stops before the canvas is squeezed out', (tester) async {
      await open(tester);

      await tester.drag(
          find.byKey(const Key('timeline-resize')), const Offset(0, -5000));
      await tester.pumpAndSettle();

      final height = heightOf(tester);
      expect(height, EditorShell.timelineMaxHeight,
          reason: 'a 900-px window clamps at the absolute ceiling');
      // The workspace above it survives — the tool rail is the panel that
      // overflows first, and it is still whole.
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('timeline-resize')), findsOneWidget,
          reason: 'the handle that caused it must stay reachable');
    });

    testWidgets('double-clicking the grip restores the default',
        (tester) async {
      await open(tester);
      final grip = find.byKey(const Key('timeline-resize'));

      await tester.drag(grip, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(heightOf(tester), greaterThan(EditorShell.timelineHeight));

      await tester.tap(grip);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(grip);
      await tester.pumpAndSettle();

      expect(heightOf(tester), EditorShell.timelineHeight);
    });

    testWidgets('a remembered height is adopted on open', (tester) async {
      await open(tester, prefs: MemoryUiPrefs(timeline: 260));

      expect(heightOf(tester), 260);
    });

    testWidgets('a stored height too tall for this window is clamped',
        (tester) async {
      await open(tester, prefs: MemoryUiPrefs(timeline: 100000));

      expect(heightOf(tester), EditorShell.timelineMaxHeight);
      expect(find.byType(TimelineBar), findsOneWidget);
    });

    testWidgets('a short window lowers the ceiling rather than overflowing',
        (tester) async {
      await open(tester);
      // Shorter than the workspace wants: the timeline gets what is left over
      // and not a pixel more, and no panel overflows.
      tester.view.physicalSize = const Size(1400, 620);
      await tester.pumpAndSettle();

      await tester.drag(
          find.byKey(const Key('timeline-resize')), const Offset(0, -5000));
      await tester.pumpAndSettle();

      expect(heightOf(tester), 620 - EditorShell.workspaceFloor);
      expect(tester.takeException(), isNull);
    });
  });

  // =========================================================================
  // Making the keyframe flow legible — the second half of "how do I animate?"
  // =========================================================================

  group('keyframe coaching', () {
    testWidgets('an unkeyed layer is told what the diamond is for',
        (tester) async {
      await open(tester, selectNode: true);

      expect(find.byKey(const Key('inspector-animate-hint')), findsOneWidget);
      expect(find.byKey(const Key('inspector-animating')), findsNothing);
    });

    testWidgets('keying swaps that for a LIVE playhead readout',
        (tester) async {
      final opened = await open(tester, selectNode: true);

      await tester.tap(find.byKey(const Key('kf-position')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inspector-animating')), findsOneWidget);
      expect(find.text('Editing at 0.00 s'), findsOneWidget);

      // Scrubbing is what the user does between keys — the readout has to
      // follow it, or "change it at another time" has no visible anchor.
      opened.c.read(playheadProvider).value = 0.5;
      await tester.pumpAndSettle();
      expect(find.text('Editing at 0.50 s'), findsOneWidget);
    });

    testWidgets('the FIRST key on a property spells out the next step',
        (tester) async {
      await open(tester, selectNode: true);

      await tester.tap(find.byKey(const Key('kf-rotation')));
      await tester.pumpAndSettle();

      expect(find.text(kNextKeyframeHint), findsOneWidget,
          reason: 'the one moment the next step is actionable');
    });

    testWidgets('a later key on the same property does not repeat the lesson',
        (tester) async {
      final opened = await open(tester, selectNode: true);

      await tester.tap(find.byKey(const Key('kf-rotation')));
      await tester.pumpAndSettle();
      expect(find.text(kNextKeyframeHint), findsOneWidget);

      // Move off the key and add a second one: already tracked, so no coaching.
      opened.c.read(playheadProvider).value = 0.5;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kf-rotation')));
      await tester.pumpAndSettle(const Duration(seconds: 8));

      expect(find.text(kNextKeyframeHint), findsNothing);
    });

    testWidgets('the tip can be closed with its ✕ instead of waited out',
        (tester) async {
      await open(tester, selectNode: true);

      await tester.tap(find.byKey(const Key('kf-rotation')));
      await tester.pumpAndSettle();
      expect(find.text(kNextKeyframeHint), findsOneWidget);

      await tester.tap(find.byKey(const Key('toast-dismiss')));
      await tester.pumpAndSettle();

      expect(find.text(kNextKeyframeHint), findsNothing);
    });

    testWidgets('the shape diamond points at the canvas, not at the field',
        (tester) async {
      await open(tester, selectNode: true);

      await tester.tap(find.byKey(const Key('kf-path')));
      await tester.pumpAndSettle();

      expect(find.text(kNextPathKeyHint), findsOneWidget,
          reason: 'a PathPose has no field — the next step is Direct select');
    });

    testWidgets('the playhead is a wide grab target, not a hairline',
        (tester) async {
      final opened = await open(tester, selectNode: true);
      await tester.tap(find.byKey(const Key('kf-position')));
      await tester.pumpAndSettle();

      final ruler = find.byKey(const Key('timeline'));
      expect(tester.getSize(ruler).height, greaterThanOrEqualTo(28.0),
          reason: 'the handle and its rail have to be grabbable without aiming');

      // The coaching toast from that first key is still on screen — and it
      // must not be in the way of the very thing it tells the user to do.
      expect(find.text(kNextKeyframeHint), findsOneWidget);

      // Grab it anywhere along the rail and slide: the playhead follows, and so
      // does the inspector's readout.
      final rail = tester.getRect(ruler);
      await tester.dragFrom(
        Offset(rail.left + rail.width * 0.25, rail.center.dy),
        Offset(rail.width * 0.5, 0),
      );
      await tester.pumpAndSettle();

      expect(opened.c.read(playheadProvider).value, closeTo(0.75, 0.02));
      expect(find.text('Editing at 0.75 s'), findsOneWidget);
    });
  });

  // =========================================================================
  // The inspector's steppers, through the real command stack
  // =========================================================================

  group('inspector steppers', () {
    Finder upArrow(String fieldKey) => find.descendant(
          of: find.byKey(Key(fieldKey)),
          matching: find.byIcon(Icons.keyboard_arrow_up),
        );

    Transform2 transformOf(ProviderContainer c, String id) =>
        c.read(documentControllerProvider(id)).requireValue
            .nodeIndex[const NodeId('sq')]!
            .transform;

    testWidgets('every numeric inspector row offers them', (tester) async {
      await open(tester, selectNode: true);

      for (final field in [
        'inspector-position-x',
        'inspector-position-y',
        'inspector-scale-x',
        'inspector-scale-y',
        'inspector-pivot-x',
        'inspector-rotation',
        'inspector-skewx',
        'inspector-opacity',
      ]) {
        expect(upArrow(field), findsOneWidget, reason: '$field has a stepper');
      }
    });

    testWidgets('a click nudges the document by one step', (tester) async {
      final opened = await open(tester, selectNode: true);
      final before = transformOf(opened.c, opened.id).position;

      await tester.tap(upArrow('inspector-position-x'));
      await tester.pumpAndSettle();

      final after = transformOf(opened.c, opened.id).position;
      expect(after.x, before.x + 1, reason: 'one artboard unit per click');
      expect(after.y, before.y, reason: 'the other channel is untouched');
    });

    testWidgets(
        'a press-and-hold moves the value repeatedly and undoes as ONE entry',
        (tester) async {
      final opened = await open(tester, selectNode: true);
      final before = transformOf(opened.c, opened.id).position;

      final arrow = tester.getCenter(upArrow('inspector-position-x'));
      final gesture = await tester.startGesture(arrow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();

      final held = transformOf(opened.c, opened.id).position;
      expect(held.x, greaterThan(before.x + 2),
          reason: 'the hold kept nudging while the button was down');

      // The whole hold is one coalesced span (docs/v3/04 §6), so one undo.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(transformOf(opened.c, opened.id).position.x, before.x,
          reason: 'a held stepper is ONE undo entry, not thirty');
    });

    testWidgets(
        'on an ANIMATED property it writes the keyframe, not the rest pose',
        (tester) async {
      final opened = await open(tester, selectNode: true);

      // Key Position at the playhead with the diamond — the flow the guide's
      // fourth chapter teaches.
      await tester.tap(find.byKey(const Key('kf-position')));
      await tester.pumpAndSettle();

      final rest = transformOf(opened.c, opened.id).position;
      Vec2 keyedValue() {
        final doc = opened.c.read(documentControllerProvider(opened.id))
            .requireValue;
        final track = doc.animations.first
            .tracksFor(const NodeId('sq'))
            .byKey[const PropertyKey(PropKey.position)]! as Vec2Track;
        return track.keys.single.value;
      }

      expect(keyedValue(), rest, reason: 'the key holds the current value');

      await tester.tap(upArrow('inspector-position-x'));
      await tester.pumpAndSettle();

      expect(keyedValue().x, rest.x + 1,
          reason: 'the nudge lands on the key under the playhead');
      expect(keyedValue().y, rest.y,
          reason: 'the other channel of the Vec2 key is left alone');
      expect(transformOf(opened.c, opened.id).position, rest,
          reason: 'edit-at-keyframe: the static pose is NOT what moved');
    });

    testWidgets('the opacity stepper stops at 100 %', (tester) async {
      final opened = await open(tester, selectNode: true);
      Node node() => opened.c
          .read(documentControllerProvider(opened.id))
          .requireValue
          .nodeIndex[const NodeId('sq')]!;
      expect(node().opacity, 1.0);

      await tester.tap(upArrow('inspector-opacity'));
      await tester.pumpAndSettle();

      expect(node().opacity, 1.0, reason: 'already at the ceiling');
      expect(
          opened.c
              .read(documentControllerProvider(opened.id).notifier)
              .canUndo,
          isFalse,
          reason: 'a refused nudge leaves no empty undo entry');
    });
  });
}

/// A store whose every call fails — `localStorage` disabled, a quota, a browser
/// in private mode. The editor must not care.
class _BrokenUiPrefs implements UiPrefs {
  @override
  Future<bool> guideSeen() async => throw StateError('no storage');

  @override
  Future<void> setGuideSeen(bool seen) async => throw StateError('no storage');

  @override
  Future<double?> timelineHeight() async => throw StateError('no storage');

  @override
  Future<void> setTimelineHeight(double height) async =>
      throw StateError('no storage');
}
