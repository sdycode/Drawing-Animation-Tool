
import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_interpolated_point.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getPercentValueForStickPosition.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/get_index_for_new_frame_for_frameposition.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/get_modified_percentvalue_for_preframeno.dart';
import 'package:animated_icon_demo/widgets/error/error_dialog.dart';
import 'package:flutter/material.dart';

getAnimatedPoints(BuildContext context) {
  List<List<Point>> allsectionSPoints = [];
  double interValue = 0;
  try {
    interValue =
        getPercentValueForStickPosition(timeLinePointerXPosition, context);
  } catch (e) {
    showErrorDialog(
        context, "Error ininterValue getAnimatedPoints interValue  $e");
  }

  for (int iconNo = 0;
      iconNo < projectList[currentProjectNo].iconSections.length;
      iconNo++) {
    log("iconSectionIndexesToIncludeInAnimationList [$iconNo] : ${iconSectionIndexesToIncludeInAnimationList}");
    if (!iconSectionIndexesToIncludeInAnimationList.contains(iconNo)) {
      continue;
    }
    log("iconSectionIndexesToIncludeInAnimationList  [$iconNo] :show ani  ${iconSectionIndexesToIncludeInAnimationList}");
    log("inin with icon $iconNo and $currntframePosPercentList");
    List<Point> animatedPoints = [];
    int preFrameNo = 0;
    try {
      preFrameNo = getIndexForPreFrameForProgressPercentValue(interValue, iconNo);
    } catch (e) {
      log("Error in getAnimatedPoints preFrameNo $preFrameNo:   $e");

      showErrorDialog(
          context, "Error in getAnimatedPoints preFrameNo $preFrameNo:   $e");
    }

    double modifiedPercentValue =
        get_modified_percentvalue_for_preframeno(preFrameNo, interValue, iconNo);
    log("$preFrameNo /${projectList[currentProjectNo].iconSections[iconNo].frames.length} / for iconno $iconNo :  / ${modifiedPercentValue} :  $interValue and // preframe  stick $timeLinePointerXPosition");
    for (var i = 0;
        i <
            projectList[currentProjectNo]
                .iconSections[iconNo]
                .frames[preFrameNo]
                .singleFrameModel
                .points
                .length;
        i++) {
      try {
        if (projectList[currentProjectNo].iconSections[iconNo].frames.length >
            preFrameNo + 1) {
          try {
            log("icon $iconNo :  indexi $i : - ${preFrameNo} - ${preFrameNo + 1} ::: ${projectList[currentProjectNo].iconSections[iconNo].frames[preFrameNo].singleFrameModel.points.length} :: ${projectList[currentProjectNo].iconSections[iconNo].frames[preFrameNo + 1].singleFrameModel.points.length}  ");
          } catch (e) {
            log("indexi errr $e");
          }
          animatedPoints.add(getInterPolatedPoint(
              modifiedPercentValue,
              projectList[currentProjectNo]
                  .iconSections[iconNo]
                  .frames[preFrameNo]
                  .singleFrameModel
                  .points[i],
              projectList[currentProjectNo]
                  .iconSections[iconNo]
                  .frames[preFrameNo + 1]
                  .singleFrameModel
                  .points[i]));
        }
      } catch (e) {
        log("Error in getAnimatedPoints   animatedPoints.add(getInterPolatedPoint( @$i $e");
        showErrorDialog(context,
            "Error in getAnimatedPoints   animatedPoints.add(getInterPolatedPoint(  $e");
      }
    }
    allsectionSPoints.add(animatedPoints);
  }

  return allsectionSPoints;
}
