import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/gestures/drag_details.dart';

import '../drawing_grid_canvas.dart';
import '../drawing_grid_canvas_fields.dart';
import 'getIndexForHoveredPointFromListofAddedPoints.dart';
import 'get_lower_value_from_pair.dart';

void pan_Update(DragUpdateDetails d) {
  List<Offset> points = pointsToOffsets(projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .points);
  if (pointType == PointType.middlePoint &&
      controlMidPoints.containsKey(getLowerFromPair(controlPointAdjecntPair))) {
    controlMidPoints[getLowerFromPair(controlPointAdjecntPair)] =
        d.localPosition;
  }
  if (pointType == PointType.endPoint) {
    log("panPointIndex end po ${panPointIndex} and / ${d.localPosition}");
    if (panPointIndex > -1) {
      projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points[panPointIndex] = Point.fromOffset(d.localPosition);
      points[panPointIndex] = d.localPosition;
    }
  }
}
