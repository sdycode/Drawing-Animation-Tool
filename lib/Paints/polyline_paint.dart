import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:flutter/material.dart';



class PointsLinePaint extends CustomPainter {
  List<Offset> _p;
  int iconsecIndex;
  PointsLinePaint(this._p,  {this.iconsecIndex = 0});
  @override
  void paint(Canvas canvas, Size size) {
    // log("paintsize in PointsLinePaint ${size}");
    Path path = Path();
    Paint paint = Paint();

    paint
      ..style = PaintingStyle.fill
      ..color =
      // myColors[cu]
       Colors.red
      ..strokeWidth = 1;
    Paint pointpaint = Paint();
    Paint hoverPointpaint = Paint();
    // hoverPointpaint
    //   ..style = PaintingStyle.fill
    //   ..color = Colors.green
    //   ..strokeWidth = 1;
    pointpaint
      ..style = PaintingStyle.fill
      ..color = Colors.deepPurple
      ..strokeWidth = 1;
    // canvas.drawCircle(hoverPoint, 8, hoverPointpaint);
    switch (drawingType) {
      case DrawingType.points:
        for (Offset e in _p) {
          canvas.drawCircle(e, 3, pointpaint);
        }
        break;
      case DrawingType.linepaths:
        for (var i = 1; i < _p.length; i++) {
          canvas.drawLine(_p[i - 1], _p[i], paint);
        }

        break;
      case DrawingType.pointsAndLines:
        for (Offset e in _p) {
          canvas.drawCircle(e, 3, pointpaint);
        }
        for (var i = 1; i < _p.length; i++) {
          canvas.drawLine(_p[i - 1], _p[i], paint);
        }
        break;
      case DrawingType.curvePaths:
        for (var i = 0; i < _p.length - 1; i++) {
          if (controlMidPoints.containsKey(i)) {
            Path curvePath = Path();
            Paint curvepaint = Paint();
            curvePath.moveTo(_p[i].dx, _p[i].dy);
            curvePath.quadraticBezierTo(controlMidPoints[i]!.dx,
                controlMidPoints[i]!.dy, _p[i + 1].dx, _p[i + 1].dy);
            curvePath.moveTo(_p[i].dx, _p[i].dy);
            curvePath.close();
            bool isThisCurveSelected = controlPointAdjecntPair.preIndex == i;
            curvepaint
              ..style = PaintingStyle.stroke
              ..color = Colors.deepPurple
              ..strokeWidth = isThisCurveSelected ? 3 : 1;
            // path.cubicTo(_p[i-2].dx, _p[i-2].dy,_p[i-1].dx, _p[i-1].dy,_p[i].dx, _p[i].dy);
            canvas.drawPath(curvePath, curvepaint);
          } else {
            canvas.drawLine(_p[i], _p[i + 1], paint);
          }
        }
        
        break;
      case DrawingType.closedCustomPath:
        Path curvePath = Path();
        Paint curvepaint = Paint();
        curvepaint
          ..style = PaintingStyle.fill
          ..color =
          
          myColors[iconsecIndex].withAlpha(120)
          //  Colors.deepPurple
          ..strokeWidth = 4;
        // Only Straight line
          curvePath.moveTo(_p[0].dx, _p[0].dy);
        // for (var i = 1; i < _p.length ; i++) {
        //    curvePath.lineTo(_p[i].dx, _p[i].dy);
        // }

        for (var i = 0; i < _p.length - 1; i++) {
          if (controlMidPoints.containsKey(i)) {
            // curvePath.moveTo(_p[i].dx, _p[i].dy);
            curvePath.quadraticBezierTo(controlMidPoints[i]!.dx,
                controlMidPoints[i]!.dy, _p[i + 1].dx, _p[i + 1].dy);
            // curvePath.moveTo(_p[i].dx, _p[i].dy);
          } else {
            curvePath.lineTo(_p[i].dx, _p[i].dy);
            if (i == _p.length - 2) {
              curvePath.lineTo(_p[i + 1].dx, _p[i + 1].dy);
            }
          }
        }
        // curvePath.moveTo(_p.first.dx, _p.first.dy);
        curvePath.close();
        canvas.drawPath(curvePath, curvepaint);
        // curvePath.
        for (Offset e in _p) {
          canvas.drawCircle(e, 3, pointpaint);
        }
        break;
      default:
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
