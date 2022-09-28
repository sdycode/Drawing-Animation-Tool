import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:flutter/material.dart';

class HoverPaint extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
 Paint   hoverPointpaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.green
      ..strokeWidth = 1;
    canvas.drawCircle(hoverPoint, 8, hoverPointpaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // TODO: implement shouldRepaint
    return true;
  }
}
