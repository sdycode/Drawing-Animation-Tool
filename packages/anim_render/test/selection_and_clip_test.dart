/// Selection geometry and the artboard clip (AC-1.1.3, AC-3.1.4, docs/v3/08 §4).
///
/// Two properties are pinned here, and both are about **agreement** rather than
/// about pixels:
///
///  1. **What the user can click is what the user can see.** The editor clips
///     nothing, so off-artboard geometry draws, hit-tests and drags; only the
///     export preview clips, and when it does, all clipping layers use the one
///     rect. A geometry layer that clipped while `hitTestScene` and the overlay
///     did not is how a user gets a selection box and anchor handles floating
///     over blank canvas around a shape they cannot see.
///  2. **A group is a first-class node on the canvas.** Its hit area and its
///     selection outline are the *same* [selectionBounds] union of its
///     descendants, so the box that answers a click is the box that was drawn.
///
/// Asserted on the clip arithmetic, the painters' recorded canvas calls and the
/// hit-test — never on rastered pixels: `Picture.toImage` returns a blank buffer
/// headlessly under `flutter_test`, so a raster diff here would be green for the
/// wrong reason.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const Vec2 _artboard = Vec2(450.2, 250.4);
const ui.Size _size = ui.Size(600, 400);

PathNode _square(String id, Vec2 origin, double s, {bool visible = true}) =>
    PathNode(
      id: NodeId(id),
      name: id,
      visible: visible,
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

Document _doc(List<Node> children) => Document(
      id: 'd',
      name: 'd',
      artboard: _artboard,
      root:
          GroupNode(id: const NodeId('root'), name: 'root', children: children),
    );

Scene _sceneOf(Document doc) => evaluate(doc, const <AnimationMix>[]);

ScenePath? _hit(Document doc, Vec2 at) =>
    hitTestScene(_sceneOf(doc), doc, at, (_) => true);

void main() {
  group('the artboard clip is a MODE, not a constant (AC-1.1.3)', () {
    test('the editor clips nothing; the export preview clips the board', () {
      final fit = artboardFit(_artboard, _size);

      expect(artboardClipRect(RenderMode.editor, _artboard, fit), isNull,
          reason: 'off-artboard geometry is legal, draws, and is selectable');

      final clip = artboardClipRect(RenderMode.exportPreview, _artboard, fit);
      final origin = fit.apply(Vec2.zero);
      final corner = fit.apply(_artboard);
      expect(clip, isNotNull);
      expect(clip?.left, closeTo(origin.x, 1e-9));
      expect(clip?.top, closeTo(origin.y, 1e-9));
      expect(clip?.right, closeTo(corner.x, 1e-9));
      expect(clip?.bottom, closeTo(corner.y, 1e-9));
    });

    test('the clip follows the composed fit — a pan moves it with the board',
        () {
      // The clip is screen-space, so it must be derived from the SAME composed
      // matrix the painters draw through. A clip computed from the bare
      // letterbox would stay put while the board panned out from under it.
      final panned = composedFit(
          const Affine.translate(37, -21).mul(const Affine.scale(1.4, 1.4)),
          _artboard,
          _size);
      final clip =
          artboardClipRect(RenderMode.exportPreview, _artboard, panned);
      final corner = panned.apply(_artboard);
      expect(clip?.right, closeTo(corner.x, 1e-9));
      expect(clip?.bottom, closeTo(corner.y, 1e-9));
    });
  });

  group('the painters agree about the clip', () {
    final doc = _doc([_square('off', const Vec2(600, 300), 40)]);
    final fit = artboardFit(_artboard, _size);
    final playhead = ValueNotifier<double>(0.0);

    tearDownAll(playhead.dispose);

    ArtboardPainter artboard(RenderMode mode) => ArtboardPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        fit: fit,
        mode: mode);

    OverlayPainter overlay(RenderMode mode) => OverlayPainter(
          document: doc,
          playhead: playhead,
          animation: null,
          anchor: const Color(0xFFFFFFFF),
          anchorBorder: const Color(0xFF000000),
          pendingColor: const Color(0xFFFFAB40),
          showAnchors: true,
          fit: fit,
          mode: mode,
          selectedPaths: {const ScenePath(NodeId('off'))},
          selectionColor: const Color(0xFF2196F3),
        );

    test('editor mode: NEITHER layer clips, so both show off-board geometry',
        () {
      expect(
          (Canvas canvas) => artboard(RenderMode.editor).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 0));
      expect((Canvas canvas) => overlay(RenderMode.editor).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 0));
    });

    test('export preview: BOTH layers clip, to the one shared rect', () {
      final expected =
          artboardClipRect(RenderMode.exportPreview, _artboard, fit);
      expect(expected, isNotNull);
      expect(
        (Canvas canvas) =>
            artboard(RenderMode.exportPreview).paint(canvas, _size),
        paints..clipRect(rect: expected),
      );
      expect(
        (Canvas canvas) =>
            overlay(RenderMode.exportPreview).paint(canvas, _size),
        paints..clipRect(rect: expected),
      );
    });

    test('an off-artboard node is hittable, and in the editor it is drawn', () {
      // The two halves of AC-1.1.3, asserted together on purpose: a hit-test
      // that answers for geometry the painter clipped away is the whole defect.
      expect(_hit(doc, const Vec2(620, 320)), const ScenePath(NodeId('off')),
          reason: 'off-artboard geometry is selectable');
      expect(
          (Canvas canvas) => artboard(RenderMode.editor).paint(canvas, _size),
          paintsExactlyCountTimes(#clipRect, 0),
          reason: 'the editor draws it too — clipping it here while the '
              'hit-test answers for it is the defect');
      // And it really is outside the board, so this is not passing by accident.
      expect(620.0, greaterThan(_artboard.x));
    });

    test('the mode is part of shouldRepaint — flipping it redraws', () {
      expect(
          artboard(RenderMode.exportPreview)
              .shouldRepaint(artboard(RenderMode.editor)),
          isTrue);
      expect(
          overlay(RenderMode.exportPreview)
              .shouldRepaint(overlay(RenderMode.editor)),
          isTrue);
    });
  });

  group('a group is a first-class node on the canvas', () {
    // g = { a: (40,40)-(70,70), b: (120,90)-(150,120) }.
    Document grouped({bool bVisible = true, bool groupVisible = true}) => _doc([
          GroupNode(
            id: const NodeId('g'),
            name: 'g',
            visible: groupVisible,
            children: [
              _square('a', const Vec2(40, 40), 30),
              _square('b', const Vec2(120, 90), 30, visible: bVisible),
            ],
          ),
        ]);

    test('its bounds are the union of its descendants, in world space', () {
      final doc = grouped();
      final bounds =
          selectionBounds(_sceneOf(doc), doc, const ScenePath(NodeId('g')));
      expect(bounds, isNotNull);
      expect(bounds?.left, closeTo(40, 1e-9));
      expect(bounds?.top, closeTo(40, 1e-9));
      expect(bounds?.right, closeTo(150, 1e-9));
      expect(bounds?.bottom, closeTo(120, 1e-9));
    });

    test('a group carries its children: its box moves with its transform', () {
      // The union is read off the EVALUATED scene, so an ancestor transform is
      // already in it. Deriving it from authored positions would be a second
      // evaluator that disagrees the moment anything is nested.
      final doc = _doc([
        GroupNode(
          id: const NodeId('g'),
          name: 'g',
          transform: const Transform2(position: Vec2(10, 5)),
          children: [_square('a', const Vec2(40, 40), 30)],
        ),
      ]);
      final bounds =
          selectionBounds(_sceneOf(doc), doc, const ScenePath(NodeId('g')));
      expect(bounds?.left, closeTo(50, 1e-9));
      expect(bounds?.top, closeTo(45, 1e-9));
    });

    test('the gap between children hits the GROUP; a child hits the CHILD', () {
      final doc = grouped();
      // (100, 80) is inside the union but on neither square.
      expect(_hit(doc, const Vec2(100, 80)), const ScenePath(NodeId('g')),
          reason: 'a group without a hit area cannot be operated on at all');
      // Front-most still wins over the container: children are tested first
      // because `composeWorldA` emits a group before its children.
      expect(_hit(doc, const Vec2(50, 50)), const ScenePath(NodeId('a')));
      expect(_hit(doc, const Vec2(130, 100)), const ScenePath(NodeId('b')));
    });

    test('the ROOT is never hit — it is the canvas, not a node', () {
      final doc = grouped();
      // Empty space stays empty: the root's union covers every shape in the
      // document, so a root that answered like a group would swallow every
      // click meant for the canvas.
      expect(_hit(doc, const Vec2(-5, -5)), isNull);
      for (final at in [const Vec2(100, 80), const Vec2(50, 50)]) {
        expect(_hit(doc, at)?.nodeId, isNot(const NodeId('root')));
      }
    });

    test('a hidden child contributes no area to click', () {
      final doc = grouped(bVisible: false);
      final bounds =
          selectionBounds(_sceneOf(doc), doc, const ScenePath(NodeId('g')));
      expect(bounds?.right, closeTo(70, 1e-9),
          reason: 'a hidden shape draws nothing, so it hits nothing');
      expect(_hit(doc, const Vec2(130, 100)), isNull);
    });

    test('a hidden group is not hittable, and an empty one encloses nothing',
        () {
      expect(_hit(grouped(groupVisible: false), const Vec2(100, 80)), isNull);

      final empty = _doc([
        const GroupNode(id: NodeId('g'), name: 'g', children: []),
      ]);
      expect(
          selectionBounds(_sceneOf(empty), empty, const ScenePath(NodeId('g'))),
          isNull);
      expect(_hit(empty, const Vec2(10, 10)), isNull);
    });

    test('the outline the overlay strokes IS the box the hit-test answers for',
        () {
      final doc = grouped();
      final playhead = ValueNotifier<double>(0.0);
      addTearDown(playhead.dispose);
      const fit = Affine.identity; // document space == screen space

      final bounds =
          selectionBounds(_sceneOf(doc), doc, const ScenePath(NodeId('g')));
      expect(bounds, isNotNull);

      final painter = OverlayPainter(
        document: doc,
        playhead: playhead,
        animation: null,
        anchor: const Color(0xFFFFFFFF),
        anchorBorder: const Color(0xFF000000),
        pendingColor: const Color(0xFFFFAB40),
        showAnchors: true,
        fit: fit,
        mode: RenderMode.editor,
        selectedPaths: {const ScenePath(NodeId('g'))},
        selectionColor: const Color(0xFF2196F3),
      );

      // A group used to early-return here for want of geometry, so a group
      // selected in the layers panel showed nothing at all on the canvas.
      expect(
        (Canvas canvas) => painter.paint(canvas, _size),
        paints..rect(rect: bounds),
      );
    });
  });

  group('selection bounds for a leaf', () {
    test('are the posed anchors AFTER the world matrix', () {
      final doc = _doc([
        PathNode(
          id: const NodeId('p'),
          name: 'p',
          transform:
              const Transform2(position: Vec2(100, 20), scale: Vec2(2, 3)),
          path: PathData(anchors: const [
            Anchor(id: AnchorId('0'), position: Vec2(0, 0)),
            Anchor(id: AnchorId('1'), position: Vec2(10, 0)),
            Anchor(id: AnchorId('2'), position: Vec2(10, 10)),
          ], closed: true),
        ),
      ]);
      final bounds =
          selectionBounds(_sceneOf(doc), doc, const ScenePath(NodeId('p')));
      expect(bounds?.left, closeTo(100, 1e-9));
      expect(bounds?.top, closeTo(20, 1e-9));
      expect(bounds?.right, closeTo(120, 1e-9));
      expect(bounds?.bottom, closeTo(50, 1e-9));
    });

    test('a collapsed node encloses nothing and never throws (AC-3.1.5)', () {
      final doc = _doc([
        PathNode(
          id: const NodeId('p'),
          name: 'p',
          transform: const Transform2(scale: Vec2(0, 0)),
          path: PathData(anchors: const [
            Anchor(id: AnchorId('0'), position: Vec2(0, 0)),
            Anchor(id: AnchorId('1'), position: Vec2(10, 10)),
          ]),
        ),
      ]);
      expect(selectionBounds(_sceneOf(doc), doc, const ScenePath(NodeId('p'))),
          isNull);
    });

    test('a dangling path resolves to nothing rather than throwing', () {
      final doc = _doc([_square('a', const Vec2(10, 10), 10)]);
      expect(
          selectionBounds(
              _sceneOf(doc), doc, const ScenePath(NodeId('deleted-by-undo'))),
          isNull);
    });
  });

  group('one mapping, one source (AC-3.1.4, docs/v3/08 §4)', () {
    test('no painter falls back to a fit of its own', () {
      // `fit` was nullable on all three painters and each fell back to its own
      // `artboardFit(...)` — three places that could build a document→screen
      // mapping, so passing `fit:` to two of them and forgetting the third gave
      // one silently un-panned layer with no compile error and no test failure.
      // Required parameters make that unrepresentable; this is the guard that
      // stops the fallback growing back.
      final offenders = <String>[];
      for (final entity in Directory('lib/src')
          .listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (RegExp(r'\?\?\s*artboardFit\(').hasMatch(src) ||
            RegExp(r'Affine\?\s+fit').hasMatch(src)) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'the composed fit is required, never nullable-with-fallback');
    });
  });
}
