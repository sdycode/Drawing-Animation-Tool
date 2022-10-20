import 'dart:math';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/get_box_corner_points_for_numerousPoints.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/modify_shape_points_asper_h2wfactor.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/geometric%20functions/get_startpoint_for_polygon_withcenter_side_and_no.dart';

create_polygon_points_from_corner_points(List<Point> boxPoints, int n) {
  Box box = getBoxForPoints(projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .cornerBoxPoints);
  double h2wFactor = box.height / box.width;

  tempShapeEndPoints = getNthPointFromInitialAngleWithStepAngle(
      box.width * 0.5, box.center, box.width, box.height, n, );
  projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .points = List.from(tempShapeEndPoints);
  // tempShapeEndPoints=   modify_shape_points_asper_h2wfactor(
  //     tempShapeEndPoints,
  //       // projectList[currentProjectNo]
  //       //     .iconSections[currentIconSectionNo]
  //       //     .frames[currentFrameNo]
  //       //     .singleFrameModel
  //       //     .points,
  //       h2wFactor);
}
