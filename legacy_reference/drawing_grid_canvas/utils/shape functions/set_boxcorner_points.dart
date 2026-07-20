import 'dart:developer';

import 'package:animated_icon_demo/Global/global.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/get_box_corner_points_for_numerousPoints.dart';
import 'package:animated_icon_demo/widgets/error/error_dialog.dart';

void setBoxCornerPoints() {
  log("setBoxCornerPoints called");
  try {
    projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames[currentFrameNo]
            .singleFrameModel
            .cornerBoxPoints =
        get_box_corner_points_for_numerousPoints(projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames[currentFrameNo]
            .singleFrameModel
            .points);
  } catch (e) {
    showErrorDialog(globalDynamicContext!, e.toString(),
        title: "setBoxCornerPoints");
  }
}
