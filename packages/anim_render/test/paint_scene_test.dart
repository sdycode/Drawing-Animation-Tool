/// Containment tests for the render layer (docs/v3/08 §1, §2).
///
/// These are not pixel tests. They assert the one property that decides whether
/// a rendering bug costs an afternoon or a week: **a failure is attributed to
/// one item and stays there.** Legacy's renderer failed per frame and reported
/// per frame, so every bug looked like "the canvas is broken" and every bisect
/// started in the wrong package.
library;

import 'dart:ui' as ui;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Draws onto a real `PictureRecorder`, so `Canvas` is the production one and
/// its save/restore balance is actually enforced rather than mocked away.
void _record(void Function(ui.Canvas canvas) body) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  body(canvas);
  recorder.endRecording().dispose();
}

ResolvedNode _node(
  String id, {
  required PathData geometry,
  Affine world = Affine.identity,
  double opacity = 1.0,
  bool visible = true,
  List<Fill> fills = const [],
  List<Stroke> strokes = const [],
}) =>
    ResolvedNode(
      path: ScenePath(NodeId(id)),
      world: world,
      worldOpacity: opacity,
      worldVisible: visible,
      geometry: geometry,
      fills: fills,
      strokes: strokes,
    );

Scene _scene(List<ResolvedNode> nodes) =>
    Scene(nodes, {for (final n in nodes) n.path: n});

PathData _square() => PathData(anchors: [
      const Anchor(id: AnchorId('a'), position: Vec2(0, 0)),
      const Anchor(id: AnchorId('b'), position: Vec2(10, 0)),
      const Anchor(id: AnchorId('c'), position: Vec2(10, 10)),
    ], closed: true);

const _solid = Fill(id: PaintId('f'), paint: SolidPaint(Rgba(1, 0, 0, 1)));

void main() {
  final captured = <RenderFault>[];

  setUp(() {
    captured.clear();
    RenderFaults.sink = captured.add;
  });
  tearDown(() => RenderFaults.sink = null);

  group('paintScene totality', () {
    test('a degenerate path draws nothing and throws nothing', () {
      // The pen tool produces exactly this on its first click. A half-drawn
      // shape must not take the canvas down.
      final zero = PathData(anchors: const []);
      final one = PathData(anchors: [
        const Anchor(id: AnchorId('only'), position: Vec2(4, 4)),
      ]);

      _record((canvas) {
        paintScene(
          canvas,
          _scene([
            _node('zero', geometry: zero, fills: const [_solid]),
            _node('one', geometry: one, fills: const [_solid]),
          ]),
        );
      });

      expect(captured, isEmpty, reason: 'degenerate is legal, not a fault');
    });

    test('an unknown paint source is skipped, not drawn and not reported', () {
      // Asymmetry is the point of UnknownPaint: the encoder writes it back
      // verbatim while the painter declines to guess. A magenta error swatch
      // would make a newer file look corrupt rather than look unsupported.
      _record((canvas) {
        paintScene(
          canvas,
          _scene([
            _node('u', geometry: _square(), fills: [
              const Fill(
                  id: PaintId('f'), paint: UnknownPaint({'type': 'mesh'})),
            ], strokes: [
              const Stroke(
                  id: PaintId('s'), paint: UnknownPaint({'type': 'mesh'})),
            ]),
          ]),
        );
      });

      expect(captured, isEmpty);
    });

    test('a singular world matrix draws nothing and never throws', () {
      // An animator WILL key scale to 0. Affine.invert() returns null and the
      // painter early-returns; `invert()!` here would end the frame.
      _record((canvas) {
        paintScene(
          canvas,
          _scene([
            _node('collapsed',
                geometry: _square(),
                world: const Affine.scale(0, 0),
                fills: const [_solid]),
          ]),
        );
      });

      expect(captured, isEmpty);
    });

    test('a NaN world matrix draws nothing — invert() alone would not stop it',
        () {
      // determinant.abs() < 1e-12 is FALSE for NaN, so invert() "succeeds" and
      // hands back more NaN. Canvas.transform with a NaN poisons the layer,
      // not just the node, which is why _isDrawable checks finiteness too.
      _record((canvas) {
        paintScene(
          canvas,
          _scene([
            _node('nan',
                geometry: _square(),
                world: const Affine(double.nan, 0, 0, 1, 0, 0),
                fills: const [_solid]),
          ]),
        );
      });

      expect(captured, isEmpty);
    });

    test('a NaN opacity is treated as invisible, not as opaque', () {
      _record((canvas) {
        paintScene(
          canvas,
          _scene([
            _node('nan-op',
                geometry: _square(),
                opacity: double.nan,
                fills: const [_solid]),
          ]),
        );
      });

      expect(captured, isEmpty);
    });

    test('a group (null geometry) occupies a slot and is skipped', () {
      const group = ResolvedNode(
        path: ScenePath(NodeId('g')),
        world: Affine.identity,
        worldOpacity: 1.0,
        worldVisible: true,
      );

      _record((canvas) => paintScene(canvas, _scene([group])));

      expect(captured, isEmpty);
    });
  });

  group('per-item containment', () {
    // A gradient with a NaN stop offset is the smallest real thing that throws
    // from inside ui: Gradient.linear rejects it. It stands in for every future
    // "one node is malformed" case.
    Fill badGradient() => const Fill(
          id: PaintId('bad'),
          paint: LinearGradientPaint(
            // A NaN gradient endpoint is the smallest *real* thing that throws from
            // inside `dart:ui`: `Gradient.linear` rejects a non-finite Offset. It
            // stands in for every future "one node is individually malformed" case
            // — a bad shader, a degenerate trim, a paint a plugin authored wrong.
            start: Vec2(double.nan, 0),
            end: Vec2(10, 10),
            stops: [
              GradientStop(
                  id: StopId('s0'), offset: 0.0, color: Rgba(1, 0, 0, 1)),
              GradientStop(
                  id: StopId('s1'), offset: 1.0, color: Rgba(0, 0, 1, 1)),
            ],
          ),
        );

    test('one bad node is reported once, by path, and the frame survives', () {
      var painted = 0;
      _record((canvas) {
        paintScene(
          canvas,
          _scene([
            _node('good-before', geometry: _square(), fills: const [_solid]),
            _node('bad', geometry: _square(), fills: [badGradient()]),
            _node('good-after', geometry: _square(), fills: const [_solid]),
          ]),
        );
        painted++;
      });

      expect(painted, 1, reason: 'no exception escaped paintScene');
      expect(captured, hasLength(1), reason: 'per item, never per frame');
      expect(captured.single.path, const ScenePath(NodeId('bad')));
      expect(captured.single.stage, 'drawNode');
    });

    test('every bad node is reported — the guard is inside the loop', () {
      // A try AROUND the loop would report once and silently drop the second
      // failure along with every node after the first. That is the exact defect
      // docs/v3/08 §2 names.
      _record((canvas) {
        paintScene(
          canvas,
          _scene([
            _node('bad1', geometry: _square(), fills: [badGradient()]),
            _node('bad2', geometry: _square(), fills: [badGradient()]),
          ]),
        );
      });

      expect(captured.map((f) => f.path.toString()), hasLength(2));
    });

    test('a failure does not leak canvas state onto the next node', () {
      // The canvas is unwound to the save depth recorded before the item, so a
      // throw between save and restore cannot smear a transform across nodes
      // that are individually fine. If it did, this recording would throw on
      // the trailing restore.
      _record((canvas) {
        final before = canvas.getSaveCount();
        paintScene(
          canvas,
          _scene([
            _node('bad', geometry: _square(), fills: [badGradient()]),
            _node('good', geometry: _square(), fills: const [_solid]),
          ]),
        );
        expect(canvas.getSaveCount(), before);
      });

      expect(captured, hasLength(1));
    });
  });

  group('ArtboardPainter', () {
    Document docWith(PathNode node) => Document(
          id: 'd',
          name: 'd',
          artboard: const Vec2(100, 100),
          root: GroupNode(
              id: const NodeId('root'), name: 'root', children: [node]),
        );

    PathNode pathNode() => PathNode(
          id: const NodeId('p'),
          name: 'p',
          path: _square(),
          fills: const [_solid],
        );

    test('evaluates inside paint and survives a NaN playhead', () {
      // The playhead is clamped HERE, at the painter boundary, because a clamp
      // inside the evaluator would be the NaN rescue docs/v3/08 §1 forbids.
      final doc = docWith(pathNode());
      final playhead = ValueNotifier<double>(double.nan);
      addTearDown(playhead.dispose);

      final painter = ArtboardPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        fit: artboardFit(doc.artboard, const ui.Size(200, 200)),
        mode: RenderMode.editor,
      );

      _record((canvas) => painter.paint(canvas, const ui.Size(200, 200)));
      expect(captured, isEmpty);
    });

    test('shouldRepaint is identity on the document, never deep equality', () {
      final playhead = ValueNotifier<double>(0.0);
      addTearDown(playhead.dispose);

      final a = docWith(pathNode());
      // Structurally identical, different object: a mutation always produces a
      // new Document, so identity is a complete change signal and comparing
      // 114 anchors to avoid a cheap paint is backwards.
      final b = docWith(pathNode());

      const fit = Affine.identity;
      final p1 = ArtboardPainter(
          document: a,
          playhead: playhead,
          animation: null,
          fit: fit,
          mode: RenderMode.editor);
      final p2 = ArtboardPainter(
          document: a,
          playhead: playhead,
          animation: null,
          fit: fit,
          mode: RenderMode.editor);
      final p3 = ArtboardPainter(
          document: b,
          playhead: playhead,
          animation: null,
          fit: fit,
          mode: RenderMode.editor);

      expect(p2.shouldRepaint(p1), isFalse);
      expect(p3.shouldRepaint(p1), isTrue);
    });

    test('the playhead repaints without a rebuild', () {
      // `repaint:` is the whole reason the tick never reaches build(). If this
      // ever regresses to a plain CustomPainter, scrubbing becomes a rebuild
      // storm and no test below would notice.
      final playhead = ValueNotifier<double>(0.0);
      addTearDown(playhead.dispose);

      final painter = ArtboardPainter(
        document: docWith(pathNode()),
        playhead: playhead,
        animation: null,
        fit: Affine.identity,
        mode: RenderMode.editor,
      );

      var repaints = 0;
      painter.addListener(() => repaints++);
      playhead.value = 0.5;
      expect(repaints, 1);
    });
  });

  group('OverlayPainter', () {
    test('draws authored anchors and pending markers without faulting', () {
      final doc = Document(
        id: 'd',
        name: 'd',
        artboard: const Vec2(100, 100),
        root: GroupNode(id: const NodeId('root'), name: 'root', children: [
          PathNode(id: const NodeId('p'), name: 'p', path: _square()),
          // A collapsed node: handles are skipped, nothing throws.
          PathNode(
            id: const NodeId('q'),
            name: 'q',
            path: _square(),
            transform: const Transform2(scale: Vec2(0, 0)),
          ),
        ]),
      );
      final playhead = ValueNotifier<double>(0.0);
      addTearDown(playhead.dispose);

      final painter = OverlayPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        anchor: const Color(0xFFFFFFFF),
        anchorBorder: const Color(0xFF000000),
        pendingColor: const Color(0xFFFFAB40),
        pending: const [Vec2(5, 5)],
        fit: artboardFit(doc.artboard, const ui.Size(200, 200)),
        mode: RenderMode.editor,
      );

      _record((canvas) => painter.paint(canvas, const ui.Size(200, 200)));
      expect(captured, isEmpty);
    });

    test('a dangling selected id is filtered, never repaired', () {
      final doc = Document(
        id: 'd',
        name: 'd',
        artboard: const Vec2(100, 100),
        root: GroupNode(id: const NodeId('root'), name: 'root', children: [
          PathNode(id: const NodeId('p'), name: 'p', path: _square()),
        ]),
      );
      final playhead = ValueNotifier<double>(0.0);
      addTearDown(playhead.dispose);

      final painter = OverlayPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        anchor: const Color(0xFFFFFFFF),
        anchorBorder: const Color(0xFF000000),
        pendingColor: const Color(0xFFFFAB40),
        selected: {const NodeId('deleted-by-undo')},
        fit: artboardFit(doc.artboard, const ui.Size(200, 200)),
        mode: RenderMode.editor,
      );

      _record((canvas) => painter.paint(canvas, const ui.Size(200, 200)));
      expect(captured, isEmpty);
    });
  });

  group('the fault sink itself', () {
    test('report returns false when nobody is watching', () {
      // That false is what makes the assert fire in a debug build with no sink
      // installed. A catch that only returns is the quiet cousin of legacy's
      // modal-per-frame (docs/v3/08 §1).
      RenderFaults.sink = null;
      expect(
        RenderFaults.report(const RenderFault(
          stage: 'test',
          error: 'x',
          stack: StackTrace.empty,
        )),
        isFalse,
      );
    });
  });
}
