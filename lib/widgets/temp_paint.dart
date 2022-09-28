import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/pair_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/cast_control_points.dart';
import 'package:flutter/material.dart';

class TempPaint extends StatelessWidget {
  final width;
  final height;
  final Frame frame;
  const TempPaint(
      {Key? key,
      required this.width,
      required this.height,
      required this.frame})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    Size size = Size(width, height);
    int cnt = 0;
    // log("pointt @ $cnt : ${frame.singleFrameModel.points.length}");
    List<Offset> _p = frame.singleFrameModel.points.map((e) {
      Offset of = Offset(e.x * (size.width / biggerSize.width),
          e.y * (size.height / biggerSize.height));
      // log("pointt @ $cnt : $of");
      cnt++;
      return of;
    }).toList();
    return Container(
      height: height,
      width: width,
      child:
          CustomPaint(size: Size(width, height), painter: _TempPainter(frame)),
    );
  }
}

class _TempPainter extends CustomPainter {
  Frame frame;
  _TempPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    Map<int, Offset> controlMidPoints = {};

    List<Offset> _p = frame.singleFrameModel.points.map((e) {
      return Offset(e.x * (size.width / biggerSize.width),
          e.y * (size.height / biggerSize.height));
    }).toList();
    ControlPointAdjecntPair controlPointAdjecntPair =
        frame.singleFrameModel.controlPointAdjecntPair ??
            ControlPointAdjecntPair.fromPair(Pair(0, 1));
    controlMidPoints = reverseCastControlPointsToIntOffset(
        frame.singleFrameModel.controlMidPoints, size); // singleFrameModel
// points.map((e) =>{
//     return Offset(e.x, e.y);
//   }).toList();
    Path path = Path();
    Paint paint = Paint();

    paint
      ..style = PaintingStyle.fill
      ..color = Colors.red
      ..strokeWidth = 1;
    Paint pointpaint = Paint();
    Paint hoverPointpaint = Paint();
    // hoverPointpaint
    //   ..style = PaintingStyle.fill
    //   ..color = Colors.green
    //   ..strokeWidth = 1;
    pointpaint
      ..style = PaintingStyle.fill
      ..color = Colors.deepOrange
      ..strokeWidth = 1;
    // canvas.drawCircle(hoverPoint, 8, hoverPointpaint);
    switch (drawingType) {
      case DrawingType.points:
        int cnt = 0;

        for (Offset e in _p) {
          // log("message $cnt : $e");
          cnt++;
          canvas.drawCircle(e, 2, pointpaint);
        }
        break;
      case DrawingType.linepaths:
        for (var i = 1; i < _p.length; i++) {
          canvas.drawLine(_p[i - 1], _p[i], paint);
        }

        break;
      case DrawingType.pointsAndLines:
        for (Offset e in _p) {
          canvas.drawCircle(e, 2, pointpaint);
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
          ..color = Colors.deepPurple
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
        break;
      default:
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // TODO: implement shouldRepaint
    return true;
  }
}
