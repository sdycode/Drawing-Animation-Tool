// Locks the pure geometry helpers used by the shape/animation engine.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/radian_to_degree.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/add_two_points.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/geometric%20functions/get_startpoint_for_polygon_withcenter_side_and_no.dart'
    as poly;

void main() {
  group('radianToDegree', () {
    test('pi -> 180', () => expect(radianToDegree(math.pi), closeTo(180, 1e-9)));
    test('pi/2 -> 90',
        () => expect(radianToDegree(math.pi / 2), closeTo(90, 1e-9)));
    test('0 -> 0', () => expect(radianToDegree(0), 0));
  });

  group('addTwoPoints', () {
    test('adds component-wise', () {
      final p = addTwoPoints(const Point(x: 1.0, y: 2.0), const Point(x: 3.0, y: 4.0));
      expect(p.x, 4.0);
      expect(p.y, 6.0);
    });
  });

  group('getNthPointFromInitialAngleWithStepAngle (polygon vertices)', () {
    const center = Point(x: 0.0, y: 0.0);

    test('n < 3 returns a single zero point (guard)', () {
      final pts =
          poly.getNthPointFromInitialAngleWithStepAngle(50, center, 100, 100, 2);
      expect(pts.length, 1);
      expect(pts.first.x, 0.0);
      expect(pts.first.y, 0.0);
    });

    test('generates n finite vertices for a square (n=4)', () {
      final pts = poly.getNthPointFromInitialAngleWithStepAngle(50, center, 100, 100, 4,
          initAngle: 0);
      expect(pts.length, 4);
      for (final p in pts) {
        expect(p.x.isFinite, isTrue);
        expect(p.y.isFinite, isTrue);
      }
    });

    test('generates n vertices for an odd n when initAngle is supplied', () {
      final pts = poly.getNthPointFromInitialAngleWithStepAngle(50, center, 100, 100, 3,
          initAngle: 0);
      expect(pts.length, 3);
    });

    test('KNOWN BUG: odd n without initAngle throws (double assigned to int)',
        () {
      // The auto initial-angle branch does `int angleinDeg = radianToDegree(...)`
      // where radianToDegree returns a double -> TypeError for odd n.
      expect(
        () => poly.getNthPointFromInitialAngleWithStepAngle(50, center, 100, 100, 3),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
