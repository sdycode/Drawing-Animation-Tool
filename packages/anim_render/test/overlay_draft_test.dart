/// The overlay's two explicit channels: the in-progress geometry a tool is
/// building, and whether anchor handles are drawn at all.
///
/// **Recorded canvas ops, never pixels.** `Picture.toImage` returns a blank
/// buffer headlessly under `flutter_test`, so a raster assertion here would
/// silently pass on nothing — which has already cost this project twice. Every
/// assertion below is on what was *asked of the canvas*: `paints..path(...)`,
/// `paintsExactlyCountTimes(#drawCircle, n)`, and the recorded `ui.Path`'s own
/// bounds.
library;

import 'dart:ui' as ui;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const ui.Size _size = ui.Size(200, 200);
const ui.Color _pending = ui.Color(0xFFFFAB40);
const ui.Color _outline = ui.Color(0xFF2196F3);

/// Draws onto a real `PictureRecorder`, so `Canvas` is the production one and
/// its save/restore balance is actually enforced rather than mocked away.
void _record(void Function(ui.Canvas canvas) body) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  body(canvas);
  recorder.endRecording().dispose();
}

PathData _square() => PathData(anchors: [
      const Anchor(id: AnchorId('a'), position: Vec2(20, 20)),
      const Anchor(id: AnchorId('b'), position: Vec2(80, 20)),
      const Anchor(id: AnchorId('c'), position: Vec2(80, 80)),
    ], closed: true);

Document _doc({List<Node> children = const []}) => Document(
      id: 'd',
      name: 'd',
      artboard: const Vec2(100, 100),
      root: GroupNode(
        id: const NodeId('root'),
        name: 'root',
        children: children,
      ),
    );

/// A two-anchor draft that really bends: both tangents pull 60 units *up* off
/// the chord at `y = 50`, so a renderer that emitted a polyline instead of a
/// cubic could not produce these bounds.
DraftPath _arc({Vec2? cursor, AnchorId? handle}) => DraftPath(
      path: PathData(anchors: [
        const Anchor(
          id: AnchorId('one'),
          position: Vec2(10, 50),
          outTangent: Vec2(0, -60),
          kind: AnchorKind.symmetric,
        ),
        const Anchor(
          id: AnchorId('two'),
          position: Vec2(90, 50),
          inTangent: Vec2(0, -60),
          kind: AnchorKind.symmetric,
        ),
      ]),
      cursor: cursor,
      handle: handle,
    );

/// The same two anchors with no tangents at all — the straight-segment control.
DraftPath _chord() => DraftPath(
      path: PathData(anchors: [
        const Anchor(id: AnchorId('one'), position: Vec2(10, 50)),
        const Anchor(id: AnchorId('two'), position: Vec2(90, 50)),
      ]),
    );

void main() {
  final captured = <RenderFault>[];
  final playhead = ValueNotifier<double>(0.0);

  setUp(() {
    captured.clear();
    RenderFaults.sink = captured.add;
  });
  tearDown(() => RenderFaults.sink = null);
  tearDownAll(playhead.dispose);

  OverlayPainter overlay({
    Document? document,
    DraftPath? draft,
    bool showAnchors = false,
    Affine fit = Affine.identity,
    RenderMode mode = RenderMode.editor,
    Set<ScenePath> selectedPaths = const <ScenePath>{},
  }) =>
      OverlayPainter(
        document: document ?? _doc(),
        playhead: playhead,
        animation: null,
        anchor: const ui.Color(0xFFFFFFFF),
        anchorBorder: const ui.Color(0xFF000000),
        pendingColor: _pending,
        fit: fit,
        mode: mode,
        showAnchors: showAnchors,
        draft: draft,
        selectedPaths: selectedPaths,
        selectionColor: _outline,
      );

  /// The bounds of the k-th recorded `drawPath`, or null if there is none.
  ///
  /// Reading the recorded argument is the whole technique: it is the geometry
  /// the canvas was actually handed, so "is this a curve" is answered by the
  /// shape rather than by a screenshot that renders blank in this harness.
  ui.Rect? drawnBounds(OverlayPainter painter, {int index = 0}) {
    ui.Rect? found;
    var seen = 0;
    expect(
      (Canvas canvas) => painter.paint(canvas, _size),
      paints
        ..something((symbol, arguments) {
          if (symbol != #drawPath || arguments.isEmpty) return false;
          final path = arguments.first;
          if (path is! ui.Path) return false;
          if (seen++ != index) return false;
          found = path.getBounds();
          return true;
        }),
    );
    return found;
  }

  // ==========================================================================
  // GAP 1 — the in-progress path is real geometry, not a scatter of dots
  // ==========================================================================

  group('the in-progress path', () {
    test('is STROKED as a curve — not dotted, and never filled', () {
      final painter = overlay(draft: _arc());

      // Exactly one path op: the draft. The overlay draws no document geometry
      // at all, so anything else here would be a second, competing preview.
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paintsExactlyCountTimes(#drawPath, 1));

      // Stroked. `ui.Path` closes an open contour implicitly when it fills, so
      // a filled preview would show the user a solid blob bounded by a segment
      // they have not drawn yet.
      expect(
        (Canvas canvas) => painter.paint(canvas, _size),
        paints
          ..path(
            style: PaintingStyle.stroke,
            strokeWidth: OverlayPainter.draftWidth,
            color: _pending,
          ),
      );

      // A CURVE. The chord sits at y = 50 and the cubic's controls pull to
      // y = -10; a polyline through the same anchors could only ever be flat,
      // which is exactly what the pen's old markers channel could express.
      final bounds = drawnBounds(painter);
      expect(bounds, isNotNull);
      expect(bounds?.top, lessThan(20.0));
      expect(captured, isEmpty);
    });

    test('and the curve assertion is not vacuous: a straight draft is flat',
        () {
      // The control. Without it, "bounds.top < 20" would pass on any geometry
      // that happened to start high on the board.
      final bounds = drawnBounds(overlay(draft: _chord()));
      expect(bounds?.top, 50.0);
      expect(bounds?.bottom, 50.0, reason: 'zero tangents is a flat segment');
    });

    test('the live segment follows the cursor', () {
      // ONE anchor: there is no committed segment yet, so the only path op is
      // the rubber band — which is the state the pen is in after its first
      // click, and the state that used to show a lone dot.
      final one = DraftPath(
        path: PathData(anchors: [
          const Anchor(id: AnchorId('one'), position: Vec2(10, 10)),
        ]),
        cursor: const Vec2(90, 70),
      );
      final painter = overlay(draft: one);
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paintsExactlyCountTimes(#drawPath, 1));
      expect(drawnBounds(painter), const ui.Rect.fromLTRB(10, 10, 90, 70));

      // Move the cursor: the segment moves with it. Same draft, same anchor.
      final moved = DraftPath(path: one.path, cursor: const Vec2(30, 95));
      expect(drawnBounds(overlay(draft: moved)),
          const ui.Rect.fromLTRB(10, 10, 30, 95));

      // No cursor — the pointer left the canvas — draws no segment rather than
      // a segment to the origin.
      expect(
        (Canvas canvas) =>
            overlay(draft: DraftPath(path: one.path)).paint(canvas, _size),
        paintsExactlyCountTimes(#drawPath, 0),
      );
      expect(captured, isEmpty);
    });

    test('the live segment is suppressed while a handle is being pulled', () {
      // The cursor IS the handle end during a handle drag, so a rubber band
      // chasing it would draw a segment to a point no anchor will occupy.
      final pulling =
          _arc(cursor: const Vec2(95, 95), handle: const AnchorId('two'));
      expect((Canvas canvas) => overlay(draft: pulling).paint(canvas, _size),
          paintsExactlyCountTimes(#drawPath, 1));
      expect(drawnBounds(overlay(draft: pulling))?.right, 90.0,
          reason: 'the one path op is the committed arc, not a segment to 95');
    });

    test('handle lines and their end dots appear while dragging a handle', () {
      // Both tangents of the named anchor: a line out to each end, and a dot on
      // it. This is the one thing the old markers channel got right, and it is
      // kept.
      expect(
        (Canvas canvas) => overlay(draft: _arc(handle: const AnchorId('two')))
            .paint(canvas, _size),
        paintsExactlyCountTimes(#drawLine, 1),
      );
      expect(
        (Canvas canvas) => overlay(draft: _arc(handle: const AnchorId('two')))
            .paint(canvas, _size),
        paints..line(p1: const Offset(90, 50), p2: const Offset(90, -10)),
      );

      // Not dragging: no handle lines at all, on the very same geometry.
      expect((Canvas canvas) => overlay(draft: _arc()).paint(canvas, _size),
          paintsExactlyCountTimes(#drawLine, 0));

      // Dragging an anchor whose tangents are still zero — the instant of a
      // plain click — draws no zero-length handle either.
      final flat =
          DraftPath(path: _chord().path, handle: const AnchorId('two'));
      expect((Canvas canvas) => overlay(draft: flat).paint(canvas, _size),
          paintsExactlyCountTimes(#drawLine, 0));
      expect(captured, isEmpty);
    });

    test(
        'every placed anchor keeps its dot — the first one is the close target',
        () {
      expect((Canvas canvas) => overlay(draft: _arc()).paint(canvas, _size),
          paintsExactlyCountTimes(#drawCircle, 2));

      // Two anchor dots plus the one live handle end.
      expect(
        (Canvas canvas) => overlay(draft: _arc(handle: const AnchorId('two')))
            .paint(canvas, _size),
        paintsExactlyCountTimes(#drawCircle, 3),
      );
    });

    test(
        'a CLOSED draft (a dragged shape) strokes its whole outline — no rubber '
        'band, no corner dots', () {
      // The shape tools feed the overlay a CLOSED `PathData`, exactly as the pen
      // feeds an open one — the outline the user is dragging out. A closed draft
      // is a finished shape: it has no open end to chase the cursor from, and
      // its corners are not click-targets, so neither the rubber-band segment
      // nor the anchor dots apply. Dotting them would put back the very scatter
      // of dots this channel replaced. The cursor is supplied (the drag point)
      // to prove it draws NO rubber band regardless.
      final shape = DraftPath(
        path: PathData(anchors: const [
          Anchor(id: AnchorId('tl'), position: Vec2(20, 20)),
          Anchor(id: AnchorId('tr'), position: Vec2(80, 20)),
          Anchor(id: AnchorId('br'), position: Vec2(80, 80)),
          Anchor(id: AnchorId('bl'), position: Vec2(20, 80)),
        ], closed: true),
        cursor: const Vec2(80, 80),
      );
      final painter = overlay(draft: shape);

      // Exactly one path op — the closed outline — stroked, never filled.
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paintsExactlyCountTimes(#drawPath, 1));
      expect(
        (Canvas canvas) => painter.paint(canvas, _size),
        paints
          ..path(
            style: PaintingStyle.stroke,
            strokeWidth: OverlayPainter.draftWidth,
            color: _pending,
          ),
      );
      // The recorded path IS the closed box: it spans all four corners, so the
      // closing edge (bl→tl) was drawn — the whole boundary, not an open run.
      expect(drawnBounds(painter), const ui.Rect.fromLTRB(20, 20, 80, 80));

      // Not one dot, and not one rubber-band segment.
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paintsExactlyCountTimes(#drawCircle, 0),
          reason: 'a shape preview is an outline, not a scatter of dots');
      expect(captured, isEmpty);
    });

    test(
        'rides THE composed fit — the same one the artboard layer is drawn '
        'with', () {
      // A pan+zoom. If the draft built a mapping of its own, this is where the
      // preview and the committed shape would part company.
      final fit = const Affine.translate(25, 40).mul(const Affine.scale(2, 2));
      final bounds = drawnBounds(overlay(draft: _arc(), fit: fit));
      expect(bounds?.left, 45.0, reason: '10 * 2 + 25');
      expect(bounds?.right, 205.0, reason: '90 * 2 + 25');
      expect(bounds?.top, 20.0, reason: '-10 * 2 + 40 — scale first, then pan');

      // The stroke width does NOT scale: an affordance is a constant physical
      // size at every zoom, exactly like the anchor radius above it.
      expect(
        (Canvas canvas) =>
            overlay(draft: _arc(), fit: fit).paint(canvas, _size),
        paints..path(strokeWidth: OverlayPainter.draftWidth),
      );
      expect(captured, isEmpty);
    });

    test('a collapsed camera draws no draft, and never inverts with `!`', () {
      final painter =
          overlay(draft: _arc(), fit: const Affine(0, 0, 0, 0, 0, 0));
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paintsExactlyCountTimes(#drawPath, 0));
      _record((canvas) => painter.paint(canvas, _size));
      expect(captured, isEmpty, reason: 'an early return is not a fault');
    });

    test('save/restore stays balanced, draft and export clip together', () {
      for (final mode in RenderMode.values) {
        final painter = overlay(
          document: _doc(children: [
            PathNode(id: const NodeId('p'), name: 'p', path: _square()),
          ]),
          draft: _arc(cursor: const Vec2(95, 95)),
          showAnchors: true,
          mode: mode,
        );
        _record((canvas) {
          final before = canvas.getSaveCount();
          painter.paint(canvas, _size);
          expect(canvas.getSaveCount(), before,
              reason: 'an unbalanced save leaks a clip into the next layer, '
                  'which is invisible on the layer that caused it');
        });
      }
      expect(captured, isEmpty);
    });

    test('repaints on a change to the draft, and not otherwise', () {
      // One document object throughout: `Document` is compared by identity on
      // purpose (it is immutable, so a new object IS the change signal), and a
      // fresh one per call would mask what this test is about.
      final doc = _doc();
      final same = overlay(document: doc, draft: _arc());
      expect(overlay(document: doc, draft: _arc()).shouldRepaint(same), isFalse,
          reason: 'value equality: the pen mints a fresh PathData per paint, '
              'so identity would say "changed" every single build');
      expect(
          overlay(document: doc, draft: _arc(cursor: const Vec2(1, 1)))
              .shouldRepaint(same),
          isTrue);
      expect(overlay(document: doc).shouldRepaint(same), isTrue,
          reason: 'the draft going away is a change too');
      expect(
          overlay(document: doc, draft: _arc(), showAnchors: true)
              .shouldRepaint(same),
          isTrue);
    });
  });

  // ==========================================================================
  // GAP 2 — "draw no anchors" is asked outright, not said with a sentinel
  // ==========================================================================

  group('showAnchors', () {
    final doc = _doc(children: [
      PathNode(id: const NodeId('p'), name: 'p', path: _square()),
    ]);
    final selected = <ScenePath>{const ScenePath(NodeId('p'))};

    test('off: no anchor dot anywhere, and the selection outline still draws',
        () {
      final painter =
          overlay(document: doc, showAnchors: false, selectedPaths: selected);

      // The Select tool's affordance. It is a DIFFERENT question from anchors,
      // and this is the pairing that proves the two are no longer entangled:
      // the same call that turns handles off leaves the outline alone.
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paintsExactlyCountTimes(#drawCircle, 0));
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paints..rect(color: _outline, style: PaintingStyle.stroke));
      expect(captured, isEmpty);
    });

    test('on: Direct select gets a filled dot and a border per authored anchor',
        () {
      final painter =
          overlay(document: doc, showAnchors: true, selectedPaths: selected);
      // Three anchors × (fill + border).
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paintsExactlyCountTimes(#drawCircle, 6));
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paints..rect(color: _outline, style: PaintingStyle.stroke));
      expect(captured, isEmpty);
    });

    test('on, narrowed by `selected`: empty still means every path node', () {
      // The convention that was safe all along — it only ever *narrows* an
      // affordance `showAnchors` has already switched on. What was not safe was
      // using it to say "none", which needed an id that could not exist.
      final all = OverlayPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        anchor: const ui.Color(0xFFFFFFFF),
        anchorBorder: const ui.Color(0xFF000000),
        pendingColor: _pending,
        fit: Affine.identity,
        mode: RenderMode.editor,
        showAnchors: true,
      );
      final narrowed = OverlayPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        anchor: const ui.Color(0xFFFFFFFF),
        anchorBorder: const ui.Color(0xFF000000),
        pendingColor: _pending,
        fit: Affine.identity,
        mode: RenderMode.editor,
        showAnchors: true,
        selected: const <NodeId>{NodeId('somebody-else')},
      );

      expect((Canvas canvas) => all.paint(canvas, _size),
          paintsExactlyCountTimes(#drawCircle, 6));
      expect((Canvas canvas) => narrowed.paint(canvas, _size),
          paintsExactlyCountTimes(#drawCircle, 0));
      expect(captured, isEmpty,
          reason: 'a dangling id is resolved, never repaired');
    });

    test('the root id is no longer a way to say anything', () {
      // The sentinel that used to live at the call site: the geometry-less root
      // passed through `selected`, leaning on "empty means every node" to make
      // one impossible id mean "no node at all". Passing it now says only what
      // it looks like it says — narrow to the root — and `showAnchors` is what
      // decides whether handles exist.
      final rootNarrowed = OverlayPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        anchor: const ui.Color(0xFFFFFFFF),
        anchorBorder: const ui.Color(0xFF000000),
        pendingColor: _pending,
        fit: Affine.identity,
        mode: RenderMode.editor,
        showAnchors: false,
        selected: const <NodeId>{NodeId('root')},
      );
      expect((Canvas canvas) => rootNarrowed.paint(canvas, _size),
          paintsExactlyCountTimes(#drawCircle, 0));
    });
  });
}
