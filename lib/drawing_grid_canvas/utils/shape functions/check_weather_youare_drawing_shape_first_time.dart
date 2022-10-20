import 'dart:developer' as dev;
import 'dart:math';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/enums/enums.dart';

bool check_weather_youare_drawing_shape_first_time() {
  bool allZero = true;
  if ([
    DrawingObjectType.polygon,
    DrawingObjectType.rectangle,
    DrawingObjectType.triangle
  ].contains(drawingObjectType)) {
    if (projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames
            .first
            .singleFrameModel
            .points
            .length >
        1) {
      Point p1 = projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames
          .first
          .singleFrameModel
          .points
          .first;
      Point p2 = projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames
          .first
          .singleFrameModel
          .points[1];
      double d = getDistBetween2Points(p1, p2);
      if (d > 2) {
        return false;
      } else {
        return true;
      }
    } else {}
    if (projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames
            .first
            .singleFrameModel
            .points
            .length ==
        projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames[1]
            .singleFrameModel
            .points
            .length) {
      if (projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames
              .first
              .singleFrameModel
              .points
              .length >
          1) {
        if (projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames
                .first
                .singleFrameModel
                .points
                .first !=
            projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames
                .first
                .singleFrameModel
                .points[1]) {
          return false;
        }
      }

      for (var i = 0;
          i <
              projectList[currentProjectNo]
                  .iconSections[currentIconSectionNo]
                  .frames
                  .first
                  .singleFrameModel
                  .points
                  .length;
          i++) {
        Point frst = projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames
            .first
            .singleFrameModel
            .points[i];
        Point sec = projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames
            .first
            .singleFrameModel
            .points[i];
        if (frst.x != 0 || frst.y != 0 || sec.x != 0 || sec.y != 0) {
          allZero = false;
          break;
        }
      }
    }
  }
  if (!allZero) {
    firstTimeDraw = false;
  }
  dev.log("isFirstime $allZero");
  return allZero;
}

double getDistBetween2Points(Point p1, Point p2) {
  double d = sqrt(pow((p1.x - p2.x), 2) + pow((p1.y - p2.y), 2));
  return d;
}

copyFramePointsFromSouceToDest(int src, int dest) {
  if (src <
          projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames
              .length &&
      dest <
          projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames
              .length &&
      (src != dest) &&
      src > -1 &&
      dest > -1) {
    // log("copyframe called ");
    List<Point> tempFramePoints = List.from(projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[src]
        .singleFrameModel
        .points);
    projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[dest]
        .singleFrameModel
        .points = tempFramePoints;
  }
}
