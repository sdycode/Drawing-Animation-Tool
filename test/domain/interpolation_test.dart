// Locks the linear-interpolation contract — the heart of the animation engine.
// `getInterPolatedPoint(t, a, b)` is a straight lerp: a*(1-t) + b*t.
// Phase 5 will add easing on top of this chokepoint; these tests pin the
// current linear behavior so that change is deliberate and visible.
import 'package:flutter_test/flutter_test.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_interpolated_point.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

void main() {
  const a = Point(x: 0.0, y: 0.0);
  const b = Point(x: 10.0, y: 20.0);

  group('getInterPolatedPoint', () {
    test('t=0 returns the initial point', () {
      final p = getInterPolatedPoint(0.0, a, b);
      expect(p.x, 0.0);
      expect(p.y, 0.0);
    });

    test('t=1 returns the last point', () {
      final p = getInterPolatedPoint(1.0, a, b);
      expect(p.x, 10.0);
      expect(p.y, 20.0);
    });

    test('t=0.5 returns the midpoint', () {
      final p = getInterPolatedPoint(0.5, a, b);
      expect(p.x, 5.0);
      expect(p.y, 10.0);
    });

    test('is linear at arbitrary t', () {
      final p = getInterPolatedPoint(0.25, const Point(x: 0.0, y: 0.0),
          const Point(x: 100.0, y: -40.0));
      expect(p.x, 25.0);
      expect(p.y, -10.0);
    });

    test('extrapolates beyond [0,1] (no clamping)', () {
      final p = getInterPolatedPoint(2.0, a, b);
      expect(p.x, 20.0);
      expect(p.y, 40.0);
    });
  });
}
