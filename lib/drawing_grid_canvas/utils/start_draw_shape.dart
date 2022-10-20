import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/check_weather_youare_drawing_shape_first_time.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:flutter/material.dart';

void startDrawRectangle(DragStartDetails d) {
  log("rectstart $currentFrameNo");
  log("start updaterect frame 0 ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[0].singleFrameModel.points[2].x}");
  log("start updaterect frame 1 ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[1].singleFrameModel.points[2].x}");

  if (check_weather_youare_drawing_shape_first_time()) {
    var tPoint = projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[currentFrameNo]
        .singleFrameModel
        .points;
    log("pointt ${d.localPosition} / ${tPoint.length}   ${tPoint.first.x}      ${tPoint.first.y} != 0");

    log("rectstart in firsttime $currentFrameNo");
    if (tPoint.length == 4 && tPoint.first.x == 0 && tPoint.first.y == 0) {
      for (var i = 0;
          i <
              projectList[currentProjectNo]
                  .iconSections[currentIconSectionNo]
                  .frames[currentFrameNo]
                  .singleFrameModel
                  .points
                  .length;
          i++) {
        projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames[currentFrameNo]
            .singleFrameModel
            .points[i] = Point.fromOffset(d.localPosition);
      }
    }
  }
}

void startDrawTriangle(DragStartDetails d) {
  List<Point> tPoint = projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .points;

  if (tPoint.length > 1) {
    log("update start $currentFrameNo points are 1] ${tPoint[0].x}  and 2] ${tPoint[1].x} ");
  }
  if (tPoint.length == 3 && tPoint.first.x == 0 && tPoint.first.y == 0) {
    log("update start first contioindonnnnn acheived $currentFrameNo points are 1] ${tPoint[0].x}  and 2] ${tPoint[1].x} ");

    for (var i = 0;
        i <
            projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames[currentFrameNo]
                .singleFrameModel
                .points
                .length;
        i++) {
      projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points[i] = Point.fromOffset(d.localPosition);
    }
  }
}

void startDrawPolygon(DragStartDetails d, int n) {
  if (check_weather_youare_drawing_shape_first_time()) {
    log("firstime polygonpoints $n : ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points.length}");
    //   for (var i = 0;
    //   i <
    //       projectList[currentProjectNo]
    //           .iconSections[currentIconSectionNo]
    //           .frames[currentFrameNo]
    //           .singleFrameModel
    //           .points
    //           .length;
    //   i++) {
    // projectList[currentProjectNo]
    //     .iconSections[currentIconSectionNo]
    //     .frames[currentFrameNo]
    //     .singleFrameModel
    //     .points[i] = Point.fromOffset(d.localPosition);
    // }
    // for (var i = 0;
    //     i <
    //         projectList[currentProjectNo]
    //             .iconSections[currentIconSectionNo]
    //             .frames[currentFrameNo]
    //             .singleFrameModel
    //             .cornerBoxPoints
    //             .length;
    //     i++) {

    // }

    projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames[currentFrameNo]
            .singleFrameModel
            .cornerBoxPoints =
        List.filled(
            projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames[currentFrameNo]
                .singleFrameModel
                .cornerBoxPoints
                .length,
            Point.fromOffset(d.localPosition));
    int c = 0;
    projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[currentFrameNo]
        .singleFrameModel
        .cornerBoxPoints
        .forEach((e) {
      log("polygonpoints startp $c : ${e.toMap()}");
      c++;
    });
  } else {
    log("not firstime");
  }
}
