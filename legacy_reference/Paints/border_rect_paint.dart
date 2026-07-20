import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/paint%20methods/get_continuous_path_for_points.dart';
import 'package:flutter/material.dart';

class BorderRectPaint extends CustomPainter {
  final List<Point> points;
  const BorderRectPaint(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    Path path = Path();
    Paint paint = Paint();

    paint
      ..style = PaintingStyle.stroke
      ..color =
          // myColors[cu]
          Colors.black
      ..strokeWidth = 1;
    canvas.drawPath(getContinuousPathForPoints(points), paint);
    // TODO: implement paint
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
