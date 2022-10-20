import 'dart:developer';
import 'dart:math' as m;

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/Paints/border_rect_paint.dart';
import 'package:animated_icon_demo/controllers/text_controllers/text_controllers.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/angle_between3_points.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/getCenterPointForBoxCornerPoints.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/get_box_corner_points_for_numerousPoints.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/get_current_box_origin.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/get_top_right_point.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/point_to_offset.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/providers/drawing_board_provider.dart';
import 'package:animated_icon_demo/providers/edit_pallet_provider.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/drawing_plane_widget.dart';
import 'package:animated_icon_demo/widgets/error/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DrawingBoardWidget extends StatefulWidget {
  DrawingBoardWidget({Key? key}) : super(key: key);

  @override
  State<DrawingBoardWidget> createState() => _DrawingBoardWidgetState();
}

class _DrawingBoardWidgetState extends State<DrawingBoardWidget> {
  @override
  Widget build(BuildContext context) {
    EditPalletProvider editPalletProvider =
        Provider.of<EditPalletProvider>(context);
    DrawingBoardProvider drawingBoardProvider =
        Provider.of<DrawingBoardProvider>(
      context,
    );
    Point topRightRotatingIconPoint = Point.zero;
    try {
      if (showOuterBox == ShowOuterBox.show) {
        topRightRotatingIconPoint = getTopRightPoint(
            projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames[currentFrameNo]
                .singleFrameModel
                .cornerBoxPoints);
        centerPoint = getCenterPointForBoxCornerPoints(
            projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames[currentFrameNo]
                .singleFrameModel
                .cornerBoxPoints);
      }
    } catch (e) {
      showErrorDialog(context,
          "error in getCenterPointForBoxCornerPoints in_DrawingBoardWidgetState $e ");
    }

    return Positioned(
      left: drawingBoardPosition.dx,
      top: drawingBoardPosition.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          if (!isComponent()) {
            drawingBoardPosition = Offset(drawingBoardPosition.dx + d.delta.dx,
                drawingBoardPosition.dy + d.delta.dy);
            TextControllers.drawingaBoard_X_posController.text =
                drawingBoardPosition.dx.toString();
            TextControllers.drawingaBoard_Y_posController.text =
                drawingBoardPosition.dy.toString();
            editPalletProvider.updateUI();
            drawingBoardProvider.updateUI();
            // setState(() {});
          }
        },
        child: Container(
          margin: EdgeInsets.all(6),
          width: drawingBoardSize.width,
          height: drawingBoardSize.height,
          color: Colors.green.shade200,
          child: Stack(children: [
            Transform.rotate(
                angle: finalAngle * 0,
                origin: getCurrentBoxOrigin(),
                child: DrawingPlaneWidget()),
            Positioned(
              right: 50,
              top: 60,
              child: Text(
                  "  ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.cornerBoxPoints.length}"),
            ),
            // Here we can show / hide this box using enum
            if (showOuterBox == ShowOuterBox.show)
              Transform.rotate(
                origin: getCurrentBoxOrigin(),
                angle: finalAngle,
                child: BorderedBoxForShape(
                  borderBoxCorners: projectList[currentProjectNo]
                      .iconSections[currentIconSectionNo]
                      .frames[currentFrameNo]
                      .singleFrameModel
                      .cornerBoxPoints,
                  // get_box_corner_points_for_numerousPoints()
                ),
              ),
            if (showOuterBox == ShowOuterBox.show)
              ...(projectList[currentProjectNo]
                  .iconSections[currentIconSectionNo]
                  .frames[currentFrameNo]
                  .singleFrameModel
                  .cornerBoxPoints
                  .map((e) {
                int pointIndex = projectList[currentProjectNo]
                    .iconSections[currentIconSectionNo]
                    .frames[currentFrameNo]
                    .singleFrameModel
                    .cornerBoxPoints
                    .indexOf(e);
                return Positioned(
                    left: e.x - 4,
                    top: e.y - 4,
                    child: IgnorePointer(
                      ignoring:
                          editShapeVertices != EditShapeVertices.boxVertices,
                      child: ClipRRect(
                        child: Container(
                          width: 8,
                          height: 8,
                          child: GestureDetector(
                            onPanStart: (d) {},
                            onPanUpdate: (d) {},
                            child: Container(
                              width: 8,
                              height: 8,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ),
                    ));
              })),
            //
            if (showOuterBox == ShowOuterBox.show)
              Positioned(
                  // Center poibt
                  left: centerPoint.x - 8,
                  top: centerPoint.y - 8,
                  child: IgnorePointer(
                    ignoring: true,
                    // editShapeVertices != EditShapeVertices.boxVertices,
                    child: ClipRRect(
                      child: Container(
                        width: 16,
                        height: 16,
                        color: Colors.transparent,
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            // log("cornerpointpanup ${d.localPosition}");
                          },
                          // child: const FittedBox(
                          //   child: Icon(
                          //     Icons.rotate_right,
                          //     color: Color.fromARGB(255, 2, 4, 63),
                          //   ),
                          // ),
                        ),
                      ),
                    ),
                  )),
            // if (showOuterBox == ShowOuterBox.show)
            //   Positioned(
            //     // left: topRightRotatingIconPoint.x + 8,
            //     // top: topRightRotatingIconPoint.y - 26,
            //     child: Transform.rotate(
            //       angle: finalAngle,
            //       origin:
            //       // Offset(-topRightRotatingIconPoint.x*0.5 - 4, - topRightRotatingIconPoint.y*0.5 + 13+drawingBoardSize.height*0.5),
            //       // Offset.zero,
            //       getCurrentBoxOrigin(),
            //       // getOffsetFromPoint(centerPoint),
            //       child: IgnorePointer(
            //         ignoring: false,
            //         child: ClipRRect(
            //             child: Container(
            //                width:         drawingBoardSize.width,
            //       height:   drawingBoardSize.height,
            //               // width: 20,
            //               // height: 20,
            //               child: GestureDetector(
            //                 onPanStart: (d) {
            //                   startForRotate = Point.fromOffset(d.globalPosition);
            //                   startDistanceForRotate = (d.globalPosition -
            //                           getOffsetFromPoint(centerPoint))
            //                       .distance;
            //                 },
            //                 onPanUpdate: (d) {
            //                   log("cornerpointpanup ${d.localPosition}");
            //                   if (startDistanceForRotate != 0) {
            //                     newDistanceForRotate = (d.globalPosition -
            //                             getOffsetFromPoint(centerPoint))
            //                         .distance;

            //                     scale =
            //                         newDistanceForRotate / startDistanceForRotate;
            //                     // log('scale $scale / $newDistance  / $startDistance');
            //                   }
            //                   endForRotate = Point.fromOffset(d.globalPosition);

            //                   double angle = angleBetween3Points(
            //                       getOffsetFromPoint(endForRotate),
            //                       getOffsetFromPoint(startForRotate));
            //                   log('angle is $angle');
            //                   startForRotate = Point.fromOffset(d.globalPosition);
            //                   finalAngle += angle;
            //                   drawingBoardProvider.updateUI();
            //                 },
            //                 // child: const FittedBox(
            //                 //   child: Icon(
            //                 //     Icons.rotate_right,
            //                 //     color: Color.fromARGB(255, 2, 4, 63),
            //                 //   ),
            //                 // ),
            //               ),
            //             ),
            //           ),
            //       ),
            //     ),
            //   ),
          ]),
        ),
      ),
    );
  }
}

class BorderedBoxForShape extends StatelessWidget {
  final List<Point> borderBoxCorners;
  const BorderedBoxForShape({Key? key, required this.borderBoxCorners})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // borderBoxCorners.forEach((e) {});
    log("points $borderBoxCorners");
    return IgnorePointer(
      ignoring: editShapeVertices != EditShapeVertices.boxVertices,
      child: GestureDetector(
        onPanUpdate: (d) {
          log("boxp ${d.localPosition}");
        },
        child: Container(
          color: Colors.deepOrange.shade100.withAlpha(5),
          child: Stack(children: [
            CustomPaint(
              size: Size(
                drawingBoardSize.width,
                drawingBoardSize.height,
              ),
              painter: BorderRectPaint(borderBoxCorners),
              //     left: borderBoxCorners.first.x,
              //     top: borderBoxCorners.first.y,
              //     child: Container(
              //       width:  (borderBoxCorners[1].x-borderBoxCorners[0].x).abs() ,
              //             height: ( borderBoxCorners[1].y-borderBoxCorners[2].y).abs() ,
              //        decoration: BoxDecoration(
              //   border: Border.all(width: 1.5),
              //   color: Colors.transparent,
              // ),
            ),
            ...(borderBoxCorners.map((e) {
              return Positioned(
                  left: e.x - 2,
                  top: e.y - 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    color: Colors.red,
                  ));
            }))
          ]),
        ),
      ),
    );
  }
}
