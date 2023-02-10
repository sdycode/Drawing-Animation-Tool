import 'dart:developer';
import 'dart:math';

import 'package:animated_icon_demo/Global/global.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/Paints/polyline_paint.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/get_top_right_point.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/point_to_offset.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/geometric%20functions/get_startpoint_for_polygon_withcenter_side_and_no.dart';

import 'package:animated_icon_demo/drawing_grid_canvas/utils/getIndexForHoveredPointFromListofAddedPoints.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/radian_to_degree.dart';

import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/on_tap_up.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/pan_update.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/start_draw_shape.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/widgets/control_point_widget.dart';
import 'package:animated_icon_demo/widgets/error/error_dialog.dart';
import 'package:animated_icon_demo/widgets/point_box.dart';
import 'package:animated_icon_demo/widgets/temp_paint.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DrawingPlaneWidget extends StatefulWidget {
  const DrawingPlaneWidget({Key? key}) : super(key: key);

  @override
  State<DrawingPlaneWidget> createState() => _DrawingPlaneWidgetState();
}
//  switch (drawingObjectType) {
//                 case DrawingObjectType.polyline:

//                   break;
//                      case DrawingObjectType.rectangle:

//                   break; case DrawingObjectType.triangle:

//                   break;
//                 default:
//               }
class _DrawingPlaneWidgetState extends State<DrawingPlaneWidget> {
  @override
  Widget build(BuildContext context) {
    ProvData provData = Provider.of(context, listen: false);
    biggerSize = Size(drawingBoardSize.width, drawingBoardSize.height);
    return Container(
      width: biggerSize.width.truncate().toDouble(),
      height: biggerSize.height.truncate().toDouble(),
      color: Colors.purple.shade100.withAlpha(60),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        onHover: (event) {
          hoverPoint = event.position;
          // hoverState(() {
          //   hoverPoint = event.position;
          // },);
          // hoverState(
          //   () {},
          // );
        },
        child: IgnorePointer(
          ignoring: !isComponent(),
          child: GestureDetector(
            onTapUp: (d) {
              // getNthPointFromInitialAngleWithStepAngle(
              //     pi/12, pi / 6, 100, Point.fromOffset(d.localPosition));
              // d.localPosition)
              if (isComponent()) {
                if (isPanShape()) {
                } else {
                  switch (drawingObjectType) {
                    case DrawingObjectType.polyline:
                      globalDynamicContext = context;
                      try {
                        on_tap_up(d);
                      } catch (e) {
                        showErrorDialog(context, e.toString(),
                            title: "ontapup");
                      }
                      try {
                        selectedPointIndex = projectList[currentProjectNo]
                                .iconSections[currentIconSectionNo]
                                .frames[currentFrameNo]
                                .singleFrameModel
                                .points
                                .length -
                            1;
                      } catch (e) {
                        showErrorDialog(context, e.toString(),
                            title: "ontapup selectedPointIndex");
                      }

                      break;
                    case DrawingObjectType.rectangle:
                      break;
                    case DrawingObjectType.triangle:
                      break;
                    default:
                  }
                }

                provData.updateUI();
                AnimSheetProvider animSheetProvider =
                    Provider.of<AnimSheetProvider>(
                  context,
                );
                animSheetProvider.updateUI();
              }
            },
            onPanStart: (d) {
              if (isComponent()) {
                if (isPanShape()) {
                } else {
                  switch (drawingObjectType) {
                    case DrawingObjectType.polyline:
                      panPointIndex =
                          getIndexForHoveredPointFromListofAddedPoints(
                              d.localPosition);
                      break;
                    case DrawingObjectType.rectangle:
                      firstTimeDraw = true;
                      startDrawRectangle(d);

                      break;
                    case DrawingObjectType.triangle:
                      firstTimeDraw = true;
                      startDrawTriangle(d);

                      break;
                    case DrawingObjectType.polygon:
                      firstTimeDraw = true;
                      startDrawPolygon(d, 5);
                      break;
                    default:
                  }
                }

                // log("panPointIndex onPanStart ${d.localPosition}");
              }
            },
            onPanUpdate: (d) {
              if (isComponent()) {
                if (isPanShape()) {
                  translateShapeWithPanUpdate(d);
                } else {
                  switch (drawingObjectType) {
                    case DrawingObjectType.polyline:
                      pan_Update(d);
                      break;
                    case DrawingObjectType.rectangle:
                      updateRectangle(d);
                      break;
                    case DrawingObjectType.triangle:
                      updateTriangle(d);
                      break;
                    case DrawingObjectType.polygon:
                      updatePolygon(d);
                      break;
                    default:
                  }
                }
                provData.updateUI();
              }
            },
            onPanEnd: (d) {
              if (isComponent()) {
                if (isPanShape()) {
                } else {
                  switch (drawingObjectType) {
                    case DrawingObjectType.polyline:
                      panPointIndex = -1;
                      break;
                    case DrawingObjectType.rectangle:
                      break;
                    case DrawingObjectType.triangle:
                      break;
                    default:
                  }
                }
              }
            },
            child: Stack(children: [
              // Text(
              //     "currentfrm ${framePosPercentListForAllIconSections}\n ${currentFrameNo} / ${finalAngle} / ${radianToDegree(finalAngle)}\n ${getOffsetFromPoint(centerPoint)}) / ${getTopRightPoint(projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.cornerBoxPoints)}"),

              projectList[currentProjectNo]
                      .iconSections[currentIconSectionNo]
                      .frames[currentFrameNo]
                      .singleFrameModel
                      .points
                      .isNotEmpty
                  ? Positioned(
                      left: projectList[currentProjectNo]
                              .iconSections[currentIconSectionNo]
                              .frames[currentFrameNo]
                              .singleFrameModel
                              .points[selectedPointIndex]
                              .x -
                          5,
                      top: projectList[currentProjectNo]
                              .iconSections[currentIconSectionNo]
                              .frames[currentFrameNo]
                              .singleFrameModel
                              .points[selectedPointIndex]
                              .y -
                          5,
                      child: BoxPoint(
                        isHovered: true,
                        // isPointHoverPointisInsideBoundryBox(e),
                        isSelected: false,
                        // (pIndex == controlPointAdjecntPair.preIndex) ||
                        //     (pIndex == controlPointAdjecntPair.nextIndex),
                        child: Container(),
                      ))
                  : Container(),
              StatefulBuilder(builder:
                  (BuildContext context, StateSetter _pointsLinePaintState) {
                // pointsLinePaintState = _pointsLinePaintState;

                return CustomPaint(
                  size: Size(
                    biggerSize.width.truncate().toDouble(),
                    biggerSize.height.truncate().toDouble(),
                  ),
                  painter: PointsLinePaint(pointsToOffsets(
                      projectList[currentProjectNo]
                          .iconSections[currentIconSectionNo]
                          .frames[currentFrameNo]
                          .singleFrameModel
                          .points,
                        
                          
                      // currentIconSectionsList[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points
                      ),
                      iconsecIndex: currentIconSectionNo,
                      indexes: [currentIconSectionNo]
                      ),
                );
              }),
// ...List.generate(tempShapeEndPoints.length, (ind) { 

// Point e = tempShapeEndPoints[ind];
//                 double rad = 16;
//                 return Positioned(
//                     left: e.x - rad,
//                     top: e.y - rad,
//                     child: CircleAvatar(
//                       radius: rad,
//                       backgroundColor: Colors.primaries[ind].withAlpha(80),
//                       child: FittedBox(child: Text(ind.toString())),
//                     ));
// }),
              // ...tempShapeEndPoints.map((e) {
               
              // }),
              // ...(projectList[currentProjectNo].iconSections.map((e) {
              //   int ind = projectList[currentProjectNo].iconSections.indexOf(e);
              //   return IgnorePointer(
              //     ignoring: true,
              //     child: TempPaint(
              //         width: biggerSize.width.truncate().toDouble(),
              //         height: biggerSize.height.truncate().toDouble(),
              //         frame:
              //             projectList[currentProjectNo].iconSections[ind].frames[
              //                 currentFrameNo %
              //                     projectList[currentProjectNo]
              //                         .iconSections[ind]
              //                         .frames
              //                         .length],
              //         frameNo: ind),
              //   );
              // }).toList()),
              // StatefulBuilder(
              //     builder: (BuildContext context, StateSetter _hoverState) {
              //   // log(" paintsize in _hoverState  build buld ${100.sw(context).truncate().toDouble()}, //  ${70.sh(context).truncate().toDouble()}");

              //   hoverState = _hoverState;
              //   return CustomPaint(
              //     size: Size(
              //       biggerSize.width.truncate().toDouble(),
              //       biggerSize.height.truncate().toDouble(),
              //     ),
              //     painter: HoverPaint(),
              //   );
              // }),

              // ...(List.generate(points.length, (pIndex) {
              //   Offset e = points[pIndex];
              //   return Positioned(
              //       left: e.dx - 5,
              //       top: e.dy - 5,
              //       child: BoxPoint(
              //         isHovered: isPointHoverPointisInsideBoundryBox(e),
              //         isSelected:
              //             (pIndex == controlPointAdjecntPair.preIndex) ||
              //                 (pIndex == controlPointAdjecntPair.nextIndex),
              //         child: Container(),
              //       ));
              // })),
              if (controlMidPoints.isNotEmpty)
                ControlBoxPoint(
                    controlMidPoints[controlPointAdjecntPair.preIndex] ??
                        const Offset(-50, -50))
            ]),
          ),
        ),
      ),
    );
  }
}
