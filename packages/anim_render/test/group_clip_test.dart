/// `GroupNode.clipChildren` — AC-2.1.6, on the recorded canvas calls.
///
/// The field was authored, decoded, round-tripped and shipped in M2 while no
/// painter honoured it, so a document could say "clip this" and render as if it
/// had not. These tests pin the four things that make the feature real and keep
/// it from taking the frame with it:
///
///  1. `true` clips and `false` does not — and the clip is the group's **own
///     window** ([groupClipWindow]), not the artboard clip, which stays a
///     [RenderMode] decision (AC-1.1.3) and is not conflated with this one.
///  2. Nested clipping groups **compose**, because clipping is hierarchical
///     while `Scene.drawOrder` is flat.
///  3. A clip is **closed on the way out**. A clip leaked onto the following
///     sibling is the worst kind of render bug: it is invisible on the node
///     that caused it.
///  4. A group whose matrix collapsed draws nothing and **throws nothing** —
///     `Affine.invert()` returning null is an early return, never `invert()!`.
///
/// Asserted on canvas ops, never on pixels: `Picture.toImage` returns a blank
/// buffer headlessly under `flutter_test`, so a raster assertion here would
/// pass on nothing.
library;

import 'dart:ui' as ui;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const Vec2 _artboard = Vec2(450.2, 250.4);
const ui.Size _size = ui.Size(600, 400);

/// The window every clipping group in this file gets: the artboard rect in the
/// group's own local space (see [groupClipWindow] for why that is the ruling).
final ui.Rect _window = groupClipWindow(_artboard);

/// Well outside [_window], so "it was clipped" cannot pass by accident.
const Vec2 _outside = Vec2(600, 300);

/// Comfortably inside it.
const Vec2 _inside = Vec2(40, 40);

PathNode _square(String id, Vec2 origin, [double s = 30]) => PathNode(
      id: NodeId(id),
      name: id,
      path: PathData(anchors: [
        Anchor(id: AnchorId('$id-0'), position: origin),
        Anchor(id: AnchorId('$id-1'), position: origin + Vec2(s, 0)),
        Anchor(id: AnchorId('$id-2'), position: origin + Vec2(s, s)),
        Anchor(id: AnchorId('$id-3'), position: origin + Vec2(0, s)),
      ], closed: true),
      fills: const [
        Fill(id: PaintId('f'), paint: SolidPaint(Rgba(0.3, 0.5, 0.9, 1))),
      ],
    );

Document _doc(List<Node> children, {bool rootClips = false}) => Document(
      id: 'd',
      name: 'd',
      artboard: _artboard,
      root: GroupNode(
        id: const NodeId('root'),
        name: 'root',
        clipChildren: rootClips,
        children: children,
      ),
    );

/// One clipping (or not) group holding one child that overflows the window.
Document _clipping({required bool clip, Transform2? transform}) => _doc([
      GroupNode(
        id: const NodeId('g'),
        name: 'g',
        clipChildren: clip,
        transform: transform ?? Transform2.identity,
        children: [_square('child', _outside)],
      ),
    ]);

/// Draws onto a real `PictureRecorder`, so `Canvas` is the production one and
/// the save/restore balance is actually enforced rather than mocked away.
void _record(void Function(ui.Canvas canvas) body) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  body(canvas);
  recorder.endRecording().dispose();
}

void main() {
  final captured = <RenderFault>[];
  final playhead = ValueNotifier<double>(0.0);

  setUp(() {
    captured.clear();
    RenderFaults.sink = captured.add;
  });
  tearDown(() => RenderFaults.sink = null);
  tearDownAll(playhead.dispose);

  ArtboardPainter artboard(Document doc,
          {RenderMode mode = RenderMode.editor,
          Affine fit = Affine.identity}) =>
      ArtboardPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        fit: fit,
        mode: mode,
      );

  OverlayPainter overlay(Document doc,
          {RenderMode mode = RenderMode.editor,
          Affine fit = Affine.identity}) =>
      OverlayPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        anchor: const Color(0xFFFFFFFF),
        anchorBorder: const Color(0xFF000000),
        pendingColor: const Color(0xFFFFAB40),
        showAnchors: true,
        fit: fit,
        mode: mode,
      );

  group('AC-2.1.6 — clipChildren is honoured', () {
    test('true clips the overflowing child; false does not', () {
      // The child really is outside the group's window, so neither half of
      // this passes by accident.
      expect(_window.contains(ui.Offset(_outside.x, _outside.y)), isFalse);

      expect(
        (Canvas canvas) => artboard(_clipping(clip: true)).paint(canvas, _size),
        paints
          ..clipRect(rect: _window)
          ..path(),
        reason: 'the clip is applied BEFORE the child it confines',
      );

      expect(
        (Canvas canvas) =>
            artboard(_clipping(clip: false)).paint(canvas, _size),
        paintsExactlyCountTimes(#clipRect, 0),
        reason: 'with false the child draws unclipped — and the editor does '
            'not clip at the artboard boundary either (AC-1.1.3)',
      );
    });

    test('the window is the artboard rect in the GROUP\'s local space', () {
      // The ruling, asserted rather than merely documented: the window travels
      // with the group's transform, so it is the group's own frame and not the
      // board. A clip that ignored the transform would record the same rect
      // through a different matrix and this test would not notice — so the
      // transformed corner is checked directly.
      final moved = _clipping(
          clip: true, transform: const Transform2(position: Vec2(60, 20)));
      final scene = evaluate(moved, const <AnimationMix>[]);
      final world = scene.byPath[const ScenePath(NodeId('g'))]?.world;
      expect(world, isNotNull);
      expect(world?.apply(Vec2.zero).x, closeTo(60, 1e-9));

      expect(
        (Canvas canvas) => artboard(moved).paint(canvas, _size),
        paints..clipRect(rect: _window),
        reason: 'the rect is local; the matrix pushed before it places it',
      );
    });

    test('a degenerate artboard yields an empty window, not a NaN clip', () {
      expect(groupClipWindow(const Vec2(0, 100)), ui.Rect.zero);
      expect(groupClipWindow(const Vec2(double.nan, 100)), ui.Rect.zero);
      expect(groupClipWindow(const Vec2(450.2, 250.4)),
          const ui.Rect.fromLTWH(0, 0, 450.2, 250.4));
    });

    test('the export preview applies BOTH clips — board and group', () {
      // The two are different questions and neither replaces the other: the
      // board clips because of the MODE, the group because of the DOCUMENT.
      expect(
        (Canvas canvas) => artboard(_clipping(clip: true),
                mode: RenderMode.exportPreview,
                fit: artboardFit(_artboard, _size))
            .paint(canvas, _size),
        paintsExactlyCountTimes(#clipRect, 2),
      );
    });
  });

  group('the chain, not a second tree walk', () {
    test('nested clipping groups compose, outermost first', () {
      final doc = _doc([
        GroupNode(
          id: const NodeId('outer'),
          name: 'outer',
          clipChildren: true,
          children: [
            GroupNode(
              id: const NodeId('inner'),
              name: 'inner',
              clipChildren: true,
              transform: const Transform2(position: Vec2(100, 0)),
              children: [_square('child', _outside)],
            ),
          ],
        ),
      ]);

      final chains = clipChains(doc);
      expect(chains[const NodeId('child')],
          [const NodeId('outer'), const NodeId('inner')]);
      // A clipping group is NOT in its own chain. This used to read
      // `[outer, inner]` with the reason "a clipping group is inside its own
      // window too" — which was wrong for the OVERLAY: a selected clipping
      // group draws its outline (the full descendant union) from its own slot,
      // and clipping that outline to the group's own window truncated or erased
      // it while the hit-test still answered for the whole union. `inner` is
      // inside its ANCESTOR `outer`, never inside itself; the clip it opens for
      // its children opens one node later. The geometry layer is unaffected — a
      // group draws nothing from its own slot — as the clipRect count below
      // still shows.
      expect(chains[const NodeId('inner')], [const NodeId('outer')],
          reason: 'inside its ancestor, never inside itself');
      expect(chains[const NodeId('outer')], isNull,
          reason: 'the outermost clipping group is confined by nothing');

      expect(
        (Canvas canvas) => artboard(doc).paint(canvas, _size),
        paints
          ..clipRect(rect: _window)
          ..clipRect(rect: _window)
          ..path(),
        reason: 'both windows are still open when the child draws',
      );
      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 2));
    });

    test('a non-clipping group in between passes the chain through', () {
      final doc = _doc([
        GroupNode(
          id: const NodeId('g'),
          name: 'g',
          clipChildren: true,
          children: [
            GroupNode(
              id: const NodeId('plain'),
              name: 'plain',
              children: [_square('child', _inside)],
            ),
          ],
        ),
      ]);
      expect(clipChains(doc)[const NodeId('child')], [const NodeId('g')]);
      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 1));
    });

    test('a document with no clipping group produces no chains at all', () {
      final doc = _doc([
        GroupNode(id: const NodeId('g'), name: 'g', children: [
          _square('child', _inside),
        ]),
      ]);
      expect(clipChains(doc), isEmpty);
      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 0));
    });

    test('the ROOT never clips, whatever it is authored as (AC-1.1.3)', () {
      // Honouring root.clipChildren would clip at the board in the EDITOR,
      // which is the one thing AC-1.1.3 forbids, and it would do it by
      // conflating an authored group clip with the mode-owned artboard clip.
      final doc = _doc([_square('off', _outside)], rootClips: true);
      expect(clipChains(doc), isEmpty);
      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 0));
    });
  });

  group('a clip never outlives its group', () {
    final doc = _doc([
      GroupNode(
        id: const NodeId('g'),
        name: 'g',
        clipChildren: true,
        children: [_square('inside', _inside)],
      ),
      _square('sibling', _outside),
    ]);

    test('the following sibling is drawn after the clip is closed', () {
      expect(
        (Canvas canvas) => artboard(doc).paint(canvas, _size),
        paints
          ..clipRect(rect: _window)
          ..path() // the group's child, clipped
          ..something((symbol, _) => symbol == #restoreToCount)
          ..path(), // the sibling, no longer clipped
      );
      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 1),
          reason: 'one group, one clip — not one per node inside it');
    });

    test('paintScene leaves the canvas exactly as it found it', () {
      _record((canvas) {
        final before = canvas.getSaveCount();
        paintScene(canvas, evaluate(doc, const <AnimationMix>[]), doc);
        expect(canvas.getSaveCount(), before,
            reason: 'an unopened restore throws; an unclosed save leaks the '
                'clip into whatever draws next');
      });
      expect(captured, isEmpty);
    });

    test('a node that throws inside a clip loses itself, not the clip', () {
      // The bad node sits INSIDE the clipping group, so the catch has to unwind
      // to the stack floor — the depth below what this item leaked and above
      // the clip its group legitimately opened. Restoring further would drop
      // the group's clip onto every node after it.
      final withBad = _doc([
        GroupNode(
          id: const NodeId('g'),
          name: 'g',
          clipChildren: true,
          children: [
            PathNode(
              id: const NodeId('bad'),
              name: 'bad',
              path: _square('bad', _inside).path,
              fills: const [
                Fill(
                  id: PaintId('bad'),
                  paint: LinearGradientPaint(
                    start: Vec2(double.nan, 0),
                    end: Vec2(10, 10),
                    stops: [
                      GradientStop(
                          id: StopId('s0'), offset: 0, color: Rgba(1, 0, 0, 1)),
                      GradientStop(
                          id: StopId('s1'), offset: 1, color: Rgba(0, 0, 1, 1)),
                    ],
                  ),
                ),
              ],
            ),
            _square('good', _inside),
          ],
        ),
      ]);

      _record((canvas) {
        final before = canvas.getSaveCount();
        paintScene(canvas, evaluate(withBad, const <AnimationMix>[]), withBad);
        expect(canvas.getSaveCount(), before);
      });

      expect(captured, hasLength(1), reason: 'per item, never per frame');
      expect(captured.single.path, const ScenePath(NodeId('bad')));

      expect(
        (Canvas canvas) => artboard(withBad).paint(canvas, _size),
        paints
          ..clipRect(rect: _window)
          ..path(),
        reason: 'the sibling after the failure still draws, still clipped',
      );
    });
  });

  group('a collapsed clipping group', () {
    Document collapsed(Transform2 transform) => _doc([
          GroupNode(
            id: const NodeId('g'),
            name: 'g',
            clipChildren: true,
            transform: transform,
            children: [_square('child', _inside)],
          ),
        ]);

    test('a singular world clips everything away and throws nothing', () {
      // An animator WILL key a group's scale to 0. Its window has no area, so
      // the subtree shows nothing — fail closed, and never `invert()!`.
      final doc = collapsed(const Transform2(scale: Vec2(0, 0)));

      _record((canvas) {
        final before = canvas.getSaveCount();
        paintScene(canvas, evaluate(doc, const <AnimationMix>[]), doc);
        expect(canvas.getSaveCount(), before);
      });
      expect(captured, isEmpty, reason: 'collapsed is legal, not a fault');

      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paints..clipRect(rect: ui.Rect.zero));
      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paintsExactlyCountTimes(#drawPath, 0));
    });

    test('a NaN world clips everything away — invert() alone would not', () {
      // determinant.abs() < 1e-12 is FALSE for NaN, so invert() "succeeds" and
      // hands back more NaN; a NaN reaching Canvas.transform poisons the whole
      // layer rather than one node, which is why isPlaceable is asked too.
      final doc = collapsed(const Transform2(rotation: double.nan));

      _record((canvas) =>
          paintScene(canvas, evaluate(doc, const <AnimationMix>[]), doc));
      expect(captured, isEmpty);

      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paints..clipRect(rect: ui.Rect.zero));
    });
  });

  group('the overlay agrees with the geometry layer', () {
    test('it clips handles to the same window, and only when the group does',
        () {
      // Same rule as the artboard clip one layer up: a handle must never
      // outlive the shape it belongs to. An overlay that skipped this would
      // leave anchor markers floating over blank canvas outside the window.
      expect(
        (Canvas canvas) => overlay(_clipping(clip: true)).paint(canvas, _size),
        paints
          ..clipRect(rect: _window)
          ..circle(),
      );
      expect(
        (Canvas canvas) => overlay(_clipping(clip: false)).paint(canvas, _size),
        paintsExactlyCountTimes(#clipRect, 0),
      );
    });

    test('the two layers record the same window under the same fit', () {
      final fit = artboardFit(_artboard, _size);
      final doc = _clipping(clip: true);
      for (final painter in <CustomPainter>[
        artboard(doc, fit: fit),
        overlay(doc, fit: fit),
      ]) {
        expect((Canvas canvas) => painter.paint(canvas, _size),
            paints..clipRect(rect: _window),
            reason: '${painter.runtimeType} must clip to the one window — the '
                'overlay maps it through `fit`, the geometry layer through the '
                'canvas, and they must land in the same place');
      }
    });

    test('pending markers are tool state and are never left inside a clip', () {
      // The clip stack is closed before them: an in-progress gesture is not a
      // child of any group, and a marker drawn into a clip nobody closes would
      // vanish for a reason the user cannot see.
      final painter = OverlayPainter(
        document: _clipping(clip: true),
        playhead: playhead,
        animation: null,
        anchor: const Color(0xFFFFFFFF),
        anchorBorder: const Color(0xFF000000),
        pendingColor: const Color(0xFFFFAB40),
        showAnchors: true,
        pending: const [Vec2(700, 350)],
        fit: Affine.identity,
        mode: RenderMode.editor,
      );

      expect(
        (Canvas canvas) => painter.paint(canvas, _size),
        paints
          ..clipRect(rect: _window)
          ..something((symbol, _) => symbol == #restoreToCount)
          ..circle(x: 700, y: 350),
      );

      _record((canvas) {
        final before = canvas.getSaveCount();
        painter.paint(canvas, _size);
        expect(canvas.getSaveCount(), before);
      });
      expect(captured, isEmpty);
    });

    test(
        'a SELECTED clipping group strokes its outline UNCLIPPED by its own '
        'window, while its child still enters the clip', () {
      // The group's window is the artboard; its one child overflows it, so the
      // selection outline (the full descendant union) lies WHOLLY OUTSIDE the
      // window. Opening the group's own clip before that stroke — the bug —
      // truncated the outline to the window, and here would erase it entirely,
      // while `hitTestScene` still answered a click for the whole union. The
      // fix removes the group from its own chain: its own slot opens no clip.
      final doc = _clipping(clip: true);
      final bounds = selectionBounds(evaluate(doc, const <AnimationMix>[]), doc,
          const ScenePath(NodeId('g')));
      expect(bounds, isNotNull);
      expect(_window.overlaps(bounds!), isFalse,
          reason: 'the union is outside the window — a clipped outline would '
              'stroke nothing at all');

      final painter = OverlayPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        anchor: const Color(0xFFFFFFFF),
        anchorBorder: const Color(0xFF000000),
        pendingColor: const Color(0xFFFFAB40),
        showAnchors: false,
        fit: Affine.identity, // document space == screen space
        mode: RenderMode.editor,
        selectedPaths: {const ScenePath(NodeId('g'))},
        selectionColor: const Color(0xFF2196F3),
      );

      // The outline `drawRect` is recorded BEFORE the child's clip opens — so it
      // is drawn with no surrounding clipRect — and there is exactly ONE
      // clipRect, the child's. Together: the group's own draw is outside every
      // clip, and its descendant is still inside one.
      expect(
        (Canvas canvas) => painter.paint(canvas, _size),
        paints
          ..rect(rect: bounds)
          ..clipRect(rect: _window),
        reason:
            'the outline strokes first, unclipped; then the child opens the '
            'clip it draws inside',
      );
      expect((Canvas canvas) => painter.paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 1),
          reason:
              'the one clip is the child\'s — the group\'s slot opens none');

      // The GEOMETRY layer is UNCHANGED: the child is still clipped and the clip
      // still opens before it draws. Removing the group from its own chain moved
      // no clipRect that wraps a child — the group drew nothing from its slot.
      expect(
        (Canvas canvas) => artboard(doc).paint(canvas, _size),
        paints
          ..clipRect(rect: _window)
          ..path(),
      );
      expect((Canvas canvas) => artboard(doc).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 1));
    });
  });
}
