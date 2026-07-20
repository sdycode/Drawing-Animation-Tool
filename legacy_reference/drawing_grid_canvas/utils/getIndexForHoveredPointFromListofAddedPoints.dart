import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:flutter/material.dart';

import '../drawing_grid_canvas_fields.dart';
import 'check_this_point_is_inside_given_point_box.dart';

int getIndexForHoveredPointFromListofAddedPoints(Offset currentHoverPoint) {
  List<Offset> points =  pointsToOffsets(
       projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points);
  int count = 0;
  for (Offset point in points) {
    if (isThisPointisInsideBoundryBox(currentHoverPoint, point)) {
      return count;
    }
    count++;
  }
  return -2;
}
