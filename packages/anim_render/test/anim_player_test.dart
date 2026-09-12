/// `AnimPlayer` — the drop-in playback widget a consuming app actually holds.
///
/// These assert **behaviour, not pixels**: `Picture.toImage` returns a blank
/// buffer headlessly under `flutter_test`, so a raster assertion here would
/// pass on nothing (same rule the rest of this package's tests follow). What is
/// pinned instead is the contract a consumer depends on:
///
///  1. The editor's exported bytes decode and play — the export is
///     `jsonEncode(doc.toJson())`, so anything else here would mean the player
///     needed a conversion step the README does not mention.
///  2. Malformed input leaves a hole in the layout, not a crash in the host
///     app. An icon that fails to parse must not take a screen down with it.
///  3. The clock actually advances the playhead, `playing: false` holds the
///     frame rather than resetting it, and `speed` scales it.
///  4. `LoopMode.once` fires `onCompleted` exactly once.
///  5. The playhead reaches the painter as a `ValueNotifier`, because a tick
///     that rebuilds the widget subtree is the antipattern the whole design
///     exists to avoid (docs/v3/08 §4).
library;

import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_core/anim_core.dart' as anim show Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A document whose single animation has a known duration and loop mode.
Document _doc({
  double duration = 1.0,
  LoopMode loop = LoopMode.loop,
}) {
  final base = Document.create(name: 'probe', artboard: const Vec2(100, 100));
  final a = base.animations.single
      .copyWith(durationSeconds: duration, loop: loop);
  return base.copyWith(animations: <anim.Animation>[a]);
}

/// The painter the player handed the playhead to.
ArtboardPainter _painter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(find.descendant(
    of: find.byType(AnimPlayer),
    matching: find.byType(CustomPaint),
  ));
  return paints
      .map((p) => p.foregroundPainter)
      .whereType<ArtboardPainter>()
      .single;
}

Future<void> _pumpPlayer(WidgetTester tester, Widget player) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 200, height: 200, child: player),
        ),
      ),
    ));

void main() {
  testWidgets('plays the editor\'s exported JSON with no conversion step',
      (tester) async {
    final exported = jsonEncode(_doc().toJson());

    await _pumpPlayer(tester, AnimPlayer.fromJson(exported));
    await tester.pump();

    final painter = _painter(tester);
    expect(painter.document.name, 'probe');
    expect(painter.animation, isNotNull,
        reason: 'should fall back to the document default animation');
  });

  testWidgets('malformed JSON renders the errorBuilder, never throws',
      (tester) async {
    Object? seen;
    await _pumpPlayer(
      tester,
      AnimPlayer.fromJson(
        '{not json at all',
        errorBuilder: (context, e) {
          seen = e;
          return const Text('bad');
        },
      ),
    );

    expect(find.text('bad'), findsOneWidget);
    expect(seen, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid JSON that is not a document object is an error, not a crash',
      (tester) async {
    await _pumpPlayer(tester, const AnimPlayer.fromJson('[1, 2, 3]'));
    await tester.pump();
    // Default errorBuilder: an empty box, and nothing thrown.
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets); // scaffold chrome only
  });

  testWidgets('the clock advances the playhead', (tester) async {
    await _pumpPlayer(tester, AnimPlayer(document: _doc(duration: 4.0)));
    await tester.pump();

    final playhead = _painter(tester).playhead;
    expect(playhead.value, 0.0);

    await tester.pump(const Duration(seconds: 1));
    expect(playhead.value, closeTo(0.25, 1e-6),
        reason: '1s into a 4s loop is a quarter through');
  });

  testWidgets('speed scales wall-clock time', (tester) async {
    await _pumpPlayer(
      tester,
      AnimPlayer(document: _doc(duration: 4.0), speed: 2.0),
    );
    await tester.pump();

    final playhead = _painter(tester).playhead;
    await tester.pump(const Duration(seconds: 1));
    expect(playhead.value, closeTo(0.5, 1e-6));
  });

  testWidgets('playing: false holds the frame rather than resetting it',
      (tester) async {
    // ONE document instance across both builds. A fresh one would be new
    // content, and restarting for new content is the widget's job — reusing it
    // is what makes this a test of pause rather than of identity.
    final doc = _doc(duration: 4.0);
    Widget build(bool playing) =>
        AnimPlayer(document: doc, playing: playing);

    await _pumpPlayer(tester, build(true));
    await tester.pump();
    final playhead = _painter(tester).playhead;
    await tester.pump(const Duration(seconds: 1));
    final held = playhead.value;
    expect(held, closeTo(0.25, 1e-6));

    await _pumpPlayer(tester, build(false));
    await tester.pump(const Duration(seconds: 2));
    expect(playhead.value, held,
        reason: 'pause must not reset, and must not keep advancing');
  });

  testWidgets('LoopMode.once fires onCompleted exactly once', (tester) async {
    var completions = 0;
    await _pumpPlayer(
      tester,
      AnimPlayer(
        document: _doc(duration: 1.0, loop: LoopMode.once),
        onCompleted: () => completions++,
      ),
    );
    await tester.pump();
    expect(completions, 0);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(completions, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(completions, 1, reason: 'once means once, however long it runs');
  });

  testWidgets('the playhead reaches the painter as a repaint Listenable',
      (tester) async {
    await _pumpPlayer(tester, AnimPlayer(document: _doc()));
    await tester.pump();
    expect(_painter(tester).playhead, isA<ValueNotifier<double>>());
  });

  testWidgets('clipToArtboard selects the export-preview render mode',
      (tester) async {
    await _pumpPlayer(tester, AnimPlayer(document: _doc()));
    await tester.pump();
    expect(_painter(tester).mode, RenderMode.exportPreview);

    await _pumpPlayer(
        tester, AnimPlayer(document: _doc(), clipToArtboard: false));
    await tester.pump();
    expect(_painter(tester).mode, RenderMode.editor);
  });
}
