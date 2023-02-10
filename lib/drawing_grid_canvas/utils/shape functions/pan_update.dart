import 'dart:developer' as dev;

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/create_polygon_points_from_corner_points.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/frame%20methods/check_to_copy_last_frame_as_first.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_lower_value_from_pair.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/check_weather_youare_drawing_shape_first_time.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/set_boxcorner_points.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:flutter/material.dart';

void pan_Update(DragUpdateDetails d) {
  dev.log("update pan called normal");
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
    // log("panPointIndex end po ${panPointIndex} and / ${d.localPosition}");
    if (panPointIndex > -1) {
      projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points[panPointIndex] = Point.fromOffset(d.localPosition);
      points[panPointIndex] = d.localPosition;
      setBoxCornerPoints();
    }
  }
}

void updateTriangle(DragUpdateDetails d) {
  dev.log("updateTriangle $currentFrameNo ");

  if (projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points
          .length ==
      3) {
    for (var i = 1; i < 3; i++) {
      Point orgPoint = projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points[i];

      switch (i) {
        case 0:
          break;
        case 1:
          orgPoint = Point(x: orgPoint.x + d.delta.dx, y: orgPoint.y);
          break;
        case 2:
          orgPoint =
              Point(x: orgPoint.x + d.delta.dx, y: orgPoint.y + d.delta.dy);
          break;
        case 3:
          orgPoint = Point(x: orgPoint.x, y: orgPoint.y + d.delta.dy);
          break;
        default:
      }

      projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points[i] = orgPoint;
    }
    if (projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames
                .length >=
            2 &&
        projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames
                .first
                .singleFrameModel
                .points
                .length >
            2) {
      for (var i = 0;
          i <
              projectList[currentProjectNo]
                  .iconSections[currentIconSectionNo]
                  .frames
                  .length;
          i++) {}
      if (firstTimeDraw) {
        copyFramePointsFromSouceToDest(0, 1);
      }
      setBoxCornerPoints();
    }
  }
}

void updateRectangle(DragUpdateDetails d) {
  // log("updaterect $currentFrameNo");
  Point firstCornerPoint = projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .points
      .first;
  if (projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points
          .length ==
      4) {
    for (var i = 1; i < 4; i++) {
      Point orgPoint = Point(
          x: projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames[currentFrameNo]
              .singleFrameModel
              .points[i]
              .x,
          y: projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames[currentFrameNo]
              .singleFrameModel
              .points[i]
              .y);

      switch (i) {
        case 0:
          break;
        case 1:
          orgPoint = Point(x: orgPoint.x + d.delta.dx, y: orgPoint.y);
          break;
        case 2:
          orgPoint =
              Point(x: orgPoint.x + d.delta.dx, y: orgPoint.y + d.delta.dy);
          break;
        case 3:
          orgPoint = Point(x: orgPoint.x, y: orgPoint.y + d.delta.dy);
          break;
        default:
      }

      projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points[i] = orgPoint;
    }
    if (firstTimeDraw) {
      copyFramePointsFromSouceToDest(0, 1);
    }
    // log("rect firstt $firstTimeDraw");
    // log("updaterect frame 0 ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[0].singleFrameModel.points[2].x}");
    // log("updaterect frame 1 ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[1].singleFrameModel.points[2].x}");

    setBoxCornerPoints();
  }
}

void updatePolygon(DragUpdateDetails d) {
  debugLog(
      "framesinpolygon ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames.length}");
  int c = 0;
  projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .cornerBoxPoints
      .forEach((element) {
    dev.log("poins $c :  ${element.toMap()}");
    c++;
  });
  List<Point> tempPoints = List.from(projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .cornerBoxPoints);
  for (var i = 1; i < 4; i++) {
    Point orgPoint = Point.zero;

    try {
      orgPoint = Point(
          x: projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames[currentFrameNo]
              .singleFrameModel
              .cornerBoxPoints[i]
              .x,
          y: projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames[currentFrameNo]
              .singleFrameModel
              .cornerBoxPoints[i]
              .y);
    } catch (e) {
      dev.log("err r $e");
    }

    switch (i) {
      case 0:
        break;
      case 1:
        orgPoint = Point(x: orgPoint.x + d.delta.dx, y: orgPoint.y);
        break;
      case 2:
        orgPoint =
            Point(x: orgPoint.x + d.delta.dx, y: orgPoint.y + d.delta.dy);
        break;
      case 3:
        orgPoint = Point(x: orgPoint.x, y: orgPoint.y + d.delta.dy);
        break;
      default:
    }
    dev.log("index $i : ${orgPoint.toMap()}");
    // dev.log(
    //     "ordpan $i : ${orgPoint.toMap()} ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.cornerBoxPoints.length}");
    tempPoints[i] = Point.fromPoint(orgPoint);
  }
  try {
    projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[currentFrameNo]
        .singleFrameModel
        .cornerBoxPoints = List.from(tempPoints);
  } catch (e) {
    dev.log(
        "err ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.cornerBoxPoints.length} cornerBoxPoints r $e");
  }

  create_polygon_points_from_corner_points(
      projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .cornerBoxPoints,
      projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points
          .length);
  if (check_to_copy_last_frame_as_first(
      projectList[currentProjectNo].iconSections[currentIconSectionNo])) {
    dev.log("copy frame from 1 to other ${currentFrameNo}");
    int frmeNo = 1;
    if (currentFrameNo == 1) {
      frmeNo = 0;
    }
    projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames[frmeNo]
            .singleFrameModel =
        SingleFrameModel.withAllPointsButNOtFrameNo(
            projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames[(frmeNo + 1) % 2]
                .singleFrameModel,
            frmeNo);
  }
}

translateShapeWithPanUpdate(DragUpdateDetails d) {
  debugLog(
      "translateShapeWithPanUpdate called ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames.length}");
  for (var i = 0;
      i <
          projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames[currentFrameNo]
              .singleFrameModel
              .points
              .length;
      i++) {
    Point p = projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[currentFrameNo]
        .singleFrameModel
        .points[i];
    projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[currentFrameNo]
        .singleFrameModel
        .points[i] = Point(x: p.x + d.delta.dx, y: p.y + d.delta.dy);
  }
  setBoxCornerPoints();
}
