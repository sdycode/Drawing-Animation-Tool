import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/drawing_board_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TriangleDragPointer extends StatelessWidget {
  const TriangleDragPointer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    AnimSheetProvider animSheetProvider =
        Provider.of<AnimSheetProvider>(context);
    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(
      context,
    );
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        // log("onhordrag ${d.delta}");
        if ((timeLinePointerXPosition + d.delta.dx) >= 0 &&
            (timeLinePointerXPosition + d.delta.dx + timelineBarH.sw(context)) <
                animTimelineWidthFactor.sw(context)) {
          timeLinePointerXPosition += d.delta.dx;
          animSheetProvider.updateUI();
          drawingBoardProvider.updateUI();
        }
      },
      child: Container(
        width: timelineBarH.sw(context),
        height: timelineBarH.sw(context),
        color: Colors.transparent,
        child: CustomPaint(
          painter: TrainglePointerPaint(),
          size: Size(timelineBarH.sw(context), timelineBarH.sw(context)),
        ),
      ),
    );
  }
}

class TrainglePointerPaint extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Path path = Path();
    Paint paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red
      ..strokeWidth = 1;
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width * 0.5, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // TODO: implement shouldRepaint
    return true;
  }
}
