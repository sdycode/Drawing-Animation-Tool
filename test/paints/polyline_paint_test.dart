// Regression test for the PointsLinePaint crash that flooded the editor with
// `RangeError (index): Index out of range: no indices are valid: 0` on every
// repaint of a frame with no points drawn yet (the default closedCustomPath
// mode did `_p[0]` unconditionally).
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:animated_icon_demo/Paints/polyline_paint.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart'
    as g;

void paintWith(List<Offset> points) {
  final painter = PointsLinePaint(points);
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, const Size(200, 200));
}

void main() {
  setUp(() {
    drawingType = DrawingType.closedCustomPath; // the default editor mode
    g.projectList = []; // no project -> fill color must fall back, not crash
  });

  test('does not throw on an EMPTY points list (the reported crash)', () {
    expect(() => paintWith(const <Offset>[]), returnsNormally);
  });

  test('does not throw on a single point', () {
    expect(() => paintWith(const [Offset(5, 5)]), returnsNormally);
  });

  test('renders a multi-point closed path without throwing', () {
    expect(
      () => paintWith(const [Offset(0, 0), Offset(10, 10), Offset(20, 0)]),
      returnsNormally,
    );
  });
}
