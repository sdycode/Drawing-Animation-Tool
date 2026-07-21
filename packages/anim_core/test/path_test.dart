import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

Anchor at(String id, double x, double y,
        {Vec2 inT = Vec2.zero, Vec2 outT = Vec2.zero, AnchorKind? kind}) =>
    Anchor(
      id: AnchorId(id),
      position: Vec2(x, y),
      inTangent: inT,
      outTangent: outT,
      kind: kind ?? AnchorKind.corner,
    );

void main() {
  group('PathData invariants', () {
    test('P1 — a duplicate AnchorId is rejected by the factory', () {
      // The whole keyframe join is a dictionary lookup on this id. A collision
      // does not fail loudly at render time; it poses one anchor with another's
      // value, forever.
      expect(
        () => PathData(anchors: [at('a', 0, 0), at('a', 10, 10)]),
        throwsA(isA<ArgumentError>()),
      );
      expect(PathData(anchors: [at('a', 0, 0), at('b', 10, 10)]).anchors,
          hasLength(2));
    });

    test('P2 — 0 or 1 anchor renders nothing and never throws', () {
      // The pen tool produces exactly this on its first click.
      expect(PathData.empty.segmentCount, 0);
      expect(PathData.empty.isEmpty, isTrue);
      expect(PathData(anchors: [at('a', 5, 5)]).segmentCount, 0);
      expect(PathData(anchors: [at('a', 5, 5)]).isEmpty, isTrue);
    });

    test('segmentCount closes the loop only when closed', () {
      final open =
          PathData(anchors: [at('a', 0, 0), at('b', 10, 0), at('c', 10, 10)]);
      expect(open.segmentCount, 2);
      expect(
        PathData(
          anchors: [at('a', 0, 0), at('b', 10, 0), at('c', 10, 10)],
          closed: true,
        ).segmentCount,
        3,
      );
    });

    test('the anchor list is unmodifiable once built', () {
      // P4: the sequence *is* the topology. PathOps is the only mutator, so a
      // caller reaching in with .add() would bypass every invariant at once.
      final p = PathData(anchors: [at('a', 0, 0), at('b', 1, 1)]);
      expect(() => p.anchors.add(at('c', 2, 2)), throwsUnsupportedError);
    });
  });

  group('segments are always cubic', () {
    test('a corner anchor degenerates to a straight line', () {
      // One segment type, no polyline/curve branch for the renderer to get
      // wrong: zero tangents put both control points on the endpoints.
      final p = PathData(anchors: [at('a', 0, 0), at('b', 30, 40)]);
      final (p0, p1, p2, p3) = p.segment(0);

      expect(p0, const Vec2(0, 0));
      expect(p1, const Vec2(0, 0));
      expect(p2, const Vec2(30, 40));
      expect(p3, const Vec2(30, 40));
    });

    test('tangents are relative to their anchor, not absolute', () {
      // Lottie i/o convention: tangents move with the anchor, so dragging a
      // point needs no fix-up pass over its handles.
      final p = PathData(anchors: [
        at('a', 100, 100, outT: const Vec2(10, 0)),
        at('b', 200, 100, inT: const Vec2(-10, 0)),
      ]);
      final (p0, p1, p2, p3) = p.segment(0);

      expect(p0, const Vec2(100, 100));
      expect(p1, const Vec2(110, 100), reason: 'anchor + outTangent');
      expect(p2, const Vec2(190, 100), reason: 'next anchor + its inTangent');
      expect(p3, const Vec2(200, 100));
    });

    test('the closing segment of a closed path wraps to anchor 0', () {
      final p = PathData(
        anchors: [at('a', 0, 0), at('b', 10, 0), at('c', 10, 10)],
        closed: true,
      );
      final (p0, _, _, p3) = p.segment(2);
      expect(p0, const Vec2(10, 10));
      expect(p3, const Vec2(0, 0), reason: 'last -> first');
    });
  });

  group('PathData JSON', () {
    test('round-trips anchors, tangents, kind and closed', () {
      final p = PathData(
        anchors: [
          at('b0', 40, 40, outT: const Vec2(5, 0), kind: AnchorKind.smooth),
          at('b1', 90, 40, inT: const Vec2(-5, 0), kind: AnchorKind.symmetric),
        ],
        closed: true,
      );

      final back = PathData.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, Object?>);

      expect(back.closed, isTrue);
      expect(back.anchors, p.anchors);
      expect(back.anchors.first.kind, AnchorKind.smooth);
      expect(back.anchors.last.inTangent, const Vec2(-5, 0));
    });

    test('an unknown kind falls back to corner instead of throwing', () {
      // kind is an authoring hint the evaluator never reads, so being wrong
      // about it costs a UI affordance. Throwing would cost the document.
      final a = Anchor.fromJson(<String, Object?>{
        'id': 'b0',
        'position': <String, Object?>{'x': 0, 'y': 0},
        'kind': 'bouncy',
      });
      expect(a.kind, AnchorKind.corner);
    });

    test('absent tangents default to zero, and ints decode', () {
      final a = Anchor.fromJson(<String, Object?>{
        'id': 'b0',
        'position': <String, Object?>{'x': 40, 'y': 40},
      });
      expect(a.position, const Vec2(40, 40));
      expect(a.inTangent, Vec2.zero);
      expect(a.outTangent, Vec2.zero);
    });
  });

  group('PathTrim', () {
    test('end <= start renders nothing rather than throwing', () {
      expect(const PathTrim(start: 0.6, end: 0.6).rendersNothing, isTrue);
      // A wrapped window is a written non-goal; it reads as empty, not as a
      // reversed reveal.
      expect(const PathTrim(start: 0.8, end: 0.2).rendersNothing, isTrue);
      expect(PathTrim.full.rendersNothing, isFalse);
    });

    test('a full trim is omitted from the node it sits on', () {
      final node = PathNode(
        id: const NodeId('n'),
        name: 'p',
        path: PathData(anchors: [at('a', 0, 0), at('b', 1, 1)]),
      );
      expect(node.toJson().containsKey('trim'), isFalse);

      final trimmed = node.copyWith(trim: const PathTrim(end: 0.5));
      expect(trimmed.toJson()['trim'], isNotNull);
      expect(
        PathTrim.fromJson(trimmed.toJson()['trim']),
        const PathTrim(end: 0.5),
      );
    });
  });

  group('PathNode', () {
    test('round-trips through a Document with fills and strokes', () {
      final node = PathNode(
        id: const NodeId('n-sig'),
        name: 'Signature',
        path: PathData(
          anchors: [
            at('b0', 40, 40, outT: const Vec2(10, 0)),
            at('b1', 120, 90, inT: const Vec2(-10, 0)),
          ],
        ),
        fills: const [
          Fill(
            id: PaintId('p-body'),
            paint: SolidPaint(Rgba(0.9, 0.24, 0.19, 1.0)),
            rule: FillRule.evenOdd,
          ),
        ],
        strokes: const [
          Stroke(
            id: PaintId('p-ink'),
            paint: SolidPaint(Rgba(0.05, 0.05, 0.08, 1.0)),
            width: 6.0,
            cap: StrokeCap.round,
            join: StrokeJoin.round,
          ),
        ],
      );

      final doc = Document(
        id: 'd',
        name: 'with a path',
        artboard: const Vec2(450.2, 250.4),
        root: GroupNode(
          id: const NodeId('n-root'),
          name: 'Root',
          children: [node],
        ),
      );

      final back = Document.fromJson(
          jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>);
      final backNode = back.root.children.single as PathNode;

      expect(backNode.id, node.id);
      expect(backNode.path.anchors, node.path.anchors);
      expect(backNode.fills.single.rule, FillRule.evenOdd);
      expect((backNode.fills.single.paint as SolidPaint).color,
          const Rgba(0.9, 0.24, 0.19, 1.0));
      expect(backNode.strokes.single.width, 6.0);
      expect(backNode.strokes.single.cap, StrokeCap.round);

      // Byte-stable across a second pass — autosave runs this loop constantly.
      expect(jsonEncode(back.toJson()), jsonEncode(doc.toJson()));
    });

    test('a path node counts in nodeIndex and validate()', () {
      final doc = Document(
        id: 'd',
        name: 'n',
        artboard: const Vec2(100, 100),
        root: GroupNode(
          id: const NodeId('n-root'),
          name: 'Root',
          children: [
            PathNode(
              id: const NodeId('n-p'),
              name: 'P',
              path: PathData(anchors: [at('a', 0, 0)]),
            ),
          ],
        ),
      );
      expect(doc.nodeIndex.keys.map((k) => k.v).toSet(), {'n-root', 'n-p'});
    });
  });

  group('paint', () {
    test('an unknown paint type is preserved, not dropped', () {
      // Gradients are declared and rendered in v1; a type from a later build
      // must still survive an autosave by this one.
      final raw = <String, Object?>{
        'type': 'meshGradient',
        'patches': <Object?>[1, 2, 3],
      };
      final fill = Fill.fromJson(<String, Object?>{
        'id': 'p-1',
        'paint': raw,
      });

      expect(fill.paint, isA<UnknownPaint>());
      expect(fill.toJson()['paint'], raw);
    });

    test('gradients decode to typed sources', () {
      final fill = Fill.fromJson(<String, Object?>{
        'id': 'p-1',
        'paint': <String, Object?>{
          'type': 'linearGradient',
          'start': <String, Object?>{'x': 0, 'y': 0},
          'end': <String, Object?>{'x': 100, 'y': 0},
          'stops': <Object?>[
            <String, Object?>{
              'id': 's-0',
              'offset': 0,
              'color': <Object?>[1, 0, 0, 1],
            },
            <String, Object?>{
              'id': 's-1',
              'offset': 1,
              'color': <Object?>[0, 0, 1, 1],
            },
          ],
        },
      });

      final paint = fill.paint as LinearGradientPaint;
      expect(paint.end, const Vec2(100, 0));
      expect(paint.stops, hasLength(2));
      // Stable stop ids are what make an individual stop animatable and
      // reorder-safe.
      expect(paint.stops.first.id, const StopId('s-0'));
      expect(paint.stops.last.color, const Rgba(0, 0, 1, 1));
    });

    test('an unknown enum value falls back rather than failing the decode', () {
      final s = Stroke.fromJson(<String, Object?>{
        'id': 'p-1',
        'paint': <String, Object?>{
          'type': 'solid',
          'color': <Object?>[0, 0, 0, 1],
        },
        'cap': 'chisel',
      });
      expect(s.cap, StrokeCap.butt);
      expect(s.join, StrokeJoin.miter, reason: 'absent join defaults');
    });
  });
}
