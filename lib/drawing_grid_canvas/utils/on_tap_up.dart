import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/gestures/drag_details.dart';
import 'package:flutter/src/gestures/tap.dart';

import '../drawing_grid_canvas.dart';
import '../drawing_grid_canvas_fields.dart';
import '../models/pair_model.dart';
import 'add_control_point.dart';
import 'getIndexForHoveredPointFromListofAddedPoints.dart';
import 'get_lower_value_from_pair.dart';

void on_tap_up(TapUpDetails d) {
  List<Offset> points = pointsToOffsets(
        projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points);
  if (pointType == PointType.endPoint) {
    if (
      false
      // getIndexForHoveredPointFromListofAddedPoints(d.localPosition) > -1
      ) {
    } else {
      // log("pointtapped else ${framesList[currentIconSectionNo][currentFrameNo].singleFrameModel.points.length}");
      // pointRoundedValuesofX[d.localPosition.dx.truncate()] = points.length;
      // pointRoundedValuesofY[d.localPosition.dy.truncate()] = points.length;
      points.add(d.localPosition);
        projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points =
          offsetsToPoints(points);
      // .add(Point.fromOffset(d.localPosition));
    }
  } else {
    // log("hovedtap ${hoverPoint} // ${d.localPosition} //${ isPointHoverPointisInsideBoundryBox(d.localPosition)}");

    int tappedIndex =
        getIndexForHoveredPointFromListofAddedPoints(d.localPosition);

    if (tappedIndex != -2) {
      log("hovedtapindex $tappedIndex /  ${hoverPoint} // ${d.localPosition}");
      if (tappedIndex != controlPointAdjecntPair.preIndex &&
          tappedIndex != controlPointAdjecntPair.nextIndex) {
        if (((controlPointAdjecntPair.preIndex - tappedIndex).abs() > 1) ||
            ((controlPointAdjecntPair.nextIndex - tappedIndex).abs() > 1)) {
          // Clicked point is AWAY from selected pair points
          if (tappedIndex + 1 < controlMidPoints.length) {
            controlPointAdjecntPair.preIndex = tappedIndex;
            controlPointAdjecntPair.nextIndex = tappedIndex + 1;
          } else {
            controlPointAdjecntPair.preIndex = tappedIndex - 1;
            controlPointAdjecntPair.nextIndex = tappedIndex;
          }
        }
        if (controlPointAdjecntPair.preIndex + 1 <= controlMidPoints.length) {
          controlPointAdjecntPair.preIndex = tappedIndex;
        }

        if (tappedIndex == controlPointAdjecntPair.nextIndex + 1) {
          controlPointAdjecntPair =
              Pair(controlPointAdjecntPair.nextIndex, tappedIndex);
        }
        if (tappedIndex == controlPointAdjecntPair.preIndex - 1) {
          controlPointAdjecntPair =
              Pair(tappedIndex, controlPointAdjecntPair.preIndex);
        }
      }
    } else {
      addControlPointIfNeeded(d);
    }
  }
}
