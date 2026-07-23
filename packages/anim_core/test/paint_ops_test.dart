import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// Solid fill and stroke authoring (docs/v3/01 §6; F5.1).
///
/// The gradient half of these tests is the M3 scope-leak line, asserted rather
/// than promised: docs/v3/06 M3 names gradient authoring as one of the two most
/// likely leaks, and AC-5.1.3 gives gradients a rendered type and **no**
/// authoring API.
void main() {
  group('PaintOps.addFill / addStroke', () {
    test('appends a solid fill and returns its freshly minted PaintId', () {
      final (out, id) = PaintOps.addFill(_doc(), const NodeId('p'),
          color: const Rgba(1, 0, 0));

      final node = out.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.fills, hasLength(1));
      expect(node.fills.single.id, id);
      expect(
          (node.fills.single.paint as SolidPaint).color, const Rgba(1, 0, 0));
      expect(node.fills.single.rule, FillRule.nonZero);
      expect(node.fills.single.visible, isTrue);
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
                  r'[0-9a-f]{12}$')
              .hasMatch(id.v),
          isTrue,
          reason: 'a PaintId is a track subjectId — never a list position');
    });

    test('a second fill APPENDS: nothing is silently truncated (AC-5.1.6)', () {
      var (d, first) = PaintOps.addFill(_doc(), const NodeId('p'),
          color: const Rgba(1, 0, 0));
      final (d2, second) =
          PaintOps.addFill(d, const NodeId('p'), color: const Rgba(0, 1, 0));
      d = d2;

      final node = d.nodeIndex[const NodeId('p')]! as PathNode;
      expect(node.fills.map((f) => f.id).toList(), [first, second]);
      expect(first, isNot(second));
    });

    test(
        'fills and strokes are separate lists, each in insertion order — '
        'fills paint first, always', () {
      var (d, strokeId) = PaintOps.addStroke(_doc(), const NodeId('p'),
          color: const Rgba(0, 0, 0), width: 3);
      final (d2, fillId) = PaintOps.addFill(d, const NodeId('p'));
      d = d2;

      final node = d.nodeIndex[const NodeId('p')]! as PathNode;
      // The stroke was added FIRST and still paints last: the order is
      // structural — two fields — not an authored z-index anyone can invert.
      expect(node.fills.map((f) => f.id).toList(), [fillId]);
      expect(node.strokes.map((s) => s.id).toList(), [strokeId]);
      final json = node.toJson();
      expect((json['fills']! as List).length, 1);
      expect((json['strokes']! as List).length, 1);
      expect(json.containsKey('zIndex'), isFalse);
      expect(json.containsKey('paintOrder'), isFalse);
    });

    test('stroke defaults and validation', () {
      final (out, id) = PaintOps.addStroke(_doc(), const NodeId('p'),
          width: 2.5, cap: StrokeCap.round, join: StrokeJoin.bevel);
      final s = (out.nodeIndex[const NodeId('p')]! as PathNode).strokes.single;
      expect(s.id, id);
      expect(s.width, 2.5);
      expect(s.cap, StrokeCap.round);
      expect(s.join, StrokeJoin.bevel);
      expect(s.miterLimit, 4.0);

      expect(() => PaintOps.addStroke(_doc(), const NodeId('p'), width: -1),
          throwsArgumentError);
      expect(
          () => PaintOps.addStroke(_doc(), const NodeId('p'), miterLimit: 0.5),
          throwsArgumentError);
    });

    test('an unknown node and a group both throw', () {
      expect(() => PaintOps.addFill(_doc(), const NodeId('nope')),
          throwsArgumentError);
      expect(() => PaintOps.addFill(_doc(), const NodeId('root')),
          throwsArgumentError,
          reason: 'a group has no outline to fill');
      expect(() => PaintOps.addStroke(_doc(), const NodeId('root')),
          throwsArgumentError);
    });
  });

  group('per-concern setters', () {
    test('colour, rule, opacity and visibility each edit one field', () {
      var (d, id) = PaintOps.addFill(_doc(), const NodeId('p'));

      d = PaintOps.setFillColor(d, const NodeId('p'), id, const Rgba(0, 0, 1));
      d = PaintOps.setFillRule(d, const NodeId('p'), id, FillRule.evenOdd);
      d = PaintOps.setFillOpacity(d, const NodeId('p'), id, 0.25);
      d = PaintOps.setFillVisible(d, const NodeId('p'), id, false);

      final f = (d.nodeIndex[const NodeId('p')]! as PathNode).fills.single;
      expect(f.id, id, reason: 'the subject id survives every edit');
      expect((f.paint as SolidPaint).color, const Rgba(0, 0, 1));
      expect(f.rule, FillRule.evenOdd);
      expect(f.opacity, 0.25);
      expect(f.visible, isFalse);
    });

    test('opacity clamps at the mutation, and NaN throws', () {
      var (d, id) = PaintOps.addFill(_doc(), const NodeId('p'));
      d = PaintOps.setFillOpacity(d, const NodeId('p'), id, 1.7);
      expect((d.nodeIndex[const NodeId('p')]! as PathNode).fills.single.opacity,
          1.0);
      d = PaintOps.setFillOpacity(d, const NodeId('p'), id, -2);
      expect((d.nodeIndex[const NodeId('p')]! as PathNode).fills.single.opacity,
          0.0);
      expect(
          () => PaintOps.setFillOpacity(d, const NodeId('p'), id, double.nan),
          throwsArgumentError);
    });

    test('every stroke concern has its own op', () {
      var (d, id) = PaintOps.addStroke(_doc(), const NodeId('p'));
      d = PaintOps.setStrokeColor(
          d, const NodeId('p'), id, const Rgba(1, 1, 0));
      d = PaintOps.setStrokeWidth(d, const NodeId('p'), id, 8);
      d = PaintOps.setStrokeCap(d, const NodeId('p'), id, StrokeCap.square);
      d = PaintOps.setStrokeJoin(d, const NodeId('p'), id, StrokeJoin.round);
      d = PaintOps.setStrokeMiterLimit(d, const NodeId('p'), id, 12);
      d = PaintOps.setStrokeOpacity(d, const NodeId('p'), id, 0.5);
      d = PaintOps.setStrokeVisible(d, const NodeId('p'), id, false);

      final s = (d.nodeIndex[const NodeId('p')]! as PathNode).strokes.single;
      expect((s.paint as SolidPaint).color, const Rgba(1, 1, 0));
      expect(s.width, 8.0);
      expect(s.cap, StrokeCap.square);
      expect(s.join, StrokeJoin.round);
      expect(s.miterLimit, 12.0);
      expect(s.opacity, 0.5);
      expect(s.visible, isFalse);

      expect(() => PaintOps.setStrokeWidth(d, const NodeId('p'), id, -0.1),
          throwsArgumentError);
      expect(() => PaintOps.setStrokeMiterLimit(d, const NodeId('p'), id, 0.9),
          throwsArgumentError);
    });

    test('an unknown PaintId throws rather than silently doing nothing', () {
      final (d, _) = PaintOps.addFill(_doc(), const NodeId('p'));
      expect(
          () => PaintOps.setFillColor(
              d, const NodeId('p'), const PaintId('ghost'), Rgba.black),
          throwsArgumentError);
      expect(
          () => PaintOps.setStrokeWidth(
              d, const NodeId('p'), const PaintId('ghost'), 2),
          throwsArgumentError);
      expect(
          () =>
              PaintOps.removeFill(d, const NodeId('p'), const PaintId('ghost')),
          throwsArgumentError);
    });

    test('an op leaves the input document untouched', () {
      final (d, id) = PaintOps.addFill(_doc(), const NodeId('p'));
      PaintOps.setFillColor(d, const NodeId('p'), id, const Rgba(1, 0, 1));
      expect(
          ((d.nodeIndex[const NodeId('p')]! as PathNode).fills.single.paint
                  as SolidPaint)
              .color,
          Rgba.black,
          reason: 'no model object is mutable');
    });
  });

  group('gradients get no authoring API (AC-5.1.3)', () {
    test('a colour edit REFUSES a gradient rather than flattening it', () {
      final gradient = LinearGradientPaint(
        start: const Vec2(0, 0),
        end: const Vec2(20, 0),
        stops: const [
          GradientStop(id: StopId('s0'), offset: 0, color: Rgba.black),
          GradientStop(id: StopId('s1'), offset: 1, color: Rgba(1, 1, 1)),
        ],
      );
      final node = _node().copyWith(
        fills: [Fill(id: const PaintId('f0'), paint: gradient)],
        strokes: [Stroke(id: const PaintId('s0'), paint: gradient)],
      );
      final d = _docOf(node);

      expect(
        () => PaintOps.setFillColor(
            d, const NodeId('p'), const PaintId('f0'), const Rgba(1, 0, 0)),
        throwsA(isA<ArgumentError>()
            .having((e) => '${e.message}', 'message', contains('solid'))),
        reason: 'a colour picker flattening an authored gradient is a '
            'destructive edit v1 has no UI to undo',
      );
      expect(
          () => PaintOps.setStrokeColor(
              d, const NodeId('p'), const PaintId('s0'), Rgba.black),
          throwsArgumentError);
    });

    test('the non-colour concerns still work on a gradient paint', () {
      // Refusing the colour must not make the whole paint un-editable: opacity,
      // width and visibility are orthogonal to the paint source.
      final node = _node().copyWith(
        fills: [
          Fill(
            id: const PaintId('f0'),
            paint: RadialGradientPaint(
                center: Vec2.zero, radius: 10, stops: const []),
          )
        ],
      );
      var d = _docOf(node);
      d = PaintOps.setFillOpacity(
          d, const NodeId('p'), const PaintId('f0'), 0.5);
      d = PaintOps.setFillVisible(
          d, const NodeId('p'), const PaintId('f0'), false);

      final f = (d.nodeIndex[const NodeId('p')]! as PathNode).fills.single;
      expect(f.paint, isA<RadialGradientPaint>(),
          reason: 'the gradient rides through untouched');
      expect(f.opacity, 0.5);
      expect(f.visible, isFalse);
    });
  });

  group('removal takes the paint tracks with it', () {
    test('removeFill drops tracks addressed to that PaintId only', () {
      const gone = PaintId('f-gone');
      const kept = PaintId('f-kept');
      final node = _node().copyWith(fills: const [
        Fill(id: gone, paint: SolidPaint(Rgba.black)),
        Fill(id: kept, paint: SolidPaint(Rgba.black)),
      ]);
      final animation = Animation(
        id: const AnimationId('a1'),
        name: 'Main',
        tracks: {
          const NodeId('p'): TrackSet({
            const PropertyKey(PropKey.fillColor, 'f-gone'): ColorTrack([
              const Keyframe(t: 0.0, value: Rgba.black),
              const Keyframe(t: 1.0, value: Rgba(1, 1, 1)),
            ]),
            const PropertyKey(PropKey.fillColor, 'f-kept'): ColorTrack([
              const Keyframe(t: 0.0, value: Rgba.black),
            ]),
            const PropertyKey(PropKey.opacity): ScalarTrack([
              const Keyframe(t: 0.0, value: 1.0),
            ]),
          }),
        },
      );
      final d = Document(
        id: 'doc',
        name: 'test',
        artboard: const Vec2(450.2, 250.4),
        root:
            GroupNode(id: const NodeId('root'), name: 'Root', children: [node]),
        animations: [animation],
        defaultAnimationId: animation.id,
      );

      final out = PaintOps.removeFill(d, const NodeId('p'), gone);

      final fills = (out.nodeIndex[const NodeId('p')]! as PathNode).fills;
      expect(fills.map((f) => f.id).toList(), [kept]);

      final tracks = out.defaultAnimation!.tracksFor(const NodeId('p'));
      expect(tracks.byKey.keys.map((k) => k.wire).toSet(),
          {'fillColor:f-kept', 'opacity'});
    });

    test('removeStroke does the same for a stroke', () {
      var (d, id) = PaintOps.addStroke(_doc(), const NodeId('p'));
      d = PaintOps.removeStroke(d, const NodeId('p'), id);
      expect((d.nodeIndex[const NodeId('p')]! as PathNode).strokes, isEmpty);
    });
  });

  test('an authored fill and stroke survive a JSON round trip in order', () {
    var (d, fillId) = PaintOps.addFill(_doc(), const NodeId('p'),
        color: const Rgba(0.2, 0.4, 0.6, 0.8), rule: FillRule.evenOdd);
    final (d2, strokeId) = PaintOps.addStroke(d, const NodeId('p'),
        color: const Rgba(1, 0, 0),
        width: 3.5,
        cap: StrokeCap.round,
        join: StrokeJoin.bevel,
        miterLimit: 2.0);
    d = d2;

    final back = Document.fromJson(
        jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>);
    final node = back.nodeIndex[const NodeId('p')]! as PathNode;

    expect(node.fills.single.id, fillId);
    expect((node.fills.single.paint as SolidPaint).color,
        const Rgba(0.2, 0.4, 0.6, 0.8));
    expect(node.fills.single.rule, FillRule.evenOdd);
    expect(node.strokes.single.id, strokeId);
    expect(node.strokes.single.width, 3.5);
    expect(node.strokes.single.cap, StrokeCap.round);
    expect(node.strokes.single.join, StrokeJoin.bevel);
    expect(node.strokes.single.miterLimit, 2.0);
  });
}

PathNode _node() => PathNode(
      id: const NodeId('p'),
      name: 'p',
      path: PathData(anchors: const [
        Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
        Anchor(id: AnchorId('a1'), position: Vec2(20, 0)),
        Anchor(id: AnchorId('a2'), position: Vec2(20, 20)),
      ], closed: true),
    );

Document _docOf(PathNode node) {
  const animation = Animation(id: AnimationId('a1'), name: 'Main');
  return Document(
    id: 'doc',
    name: 'test',
    artboard: const Vec2(450.2, 250.4),
    root: GroupNode(id: const NodeId('root'), name: 'Root', children: [node]),
    animations: const [animation],
    defaultAnimationId: animation.id,
  );
}

Document _doc() => _docOf(_node());
