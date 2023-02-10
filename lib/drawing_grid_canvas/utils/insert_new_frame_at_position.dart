import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

void insertNewFrameAtPosition(int i, double framePos) {
  framePosPercentListForAllIconSections.forEach((key, value) {
    log("insernew $key / $value / ${currentIconSectionNo}");
    // log("in insertn  $framePosPercentListForAllIconSections and $currentIconSectionNo :: ${framePosPercentListForAllIconSections.containsKey(currentIconSection)}");
//
  });

  if (!framePosPercentListForAllIconSections
      .containsKey(currentIconSectionNo)) {
    return;
  }
  framePosPercentListForAllIconSections[currentIconSectionNo]!
      .insert(i, framePos);
  currntframePosPercentList.insert(i, framePos);
  projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames
      .insert(
          i,
          Frame(
              frameNo: projectList[currentProjectNo]
                  .iconSections[currentIconSectionNo]
                  .frames
                  .length,
              singleFrameModel: SingleFrameModel(
                  points: List.from(projectList[currentProjectNo]
                      .iconSections[currentIconSectionNo]
                      .frames[currentFrameNo]
                      .singleFrameModel
                      .points),
                  framePosition: framePos,
                  frameNo: projectList[currentProjectNo]
                      .iconSections[currentIconSectionNo]
                      .frames
                      .length)));

  currentFrameNo = i;
}

void insertNewFrameAtPositionInThisIconsection(
    int i, int iconNo, double framePos) {
  currentIconSectionNo = iconNo;
  framePosPercentListForAllIconSections.forEach((key, value) {
    log("insernew $key / $value / ${iconNo}");
    // log("in insertn  $framePosPercentListForAllIconSections and $currentIconSectionNo :: ${framePosPercentListForAllIconSections.containsKey(currentIconSection)}");
//
  });

  if (!framePosPercentListForAllIconSections.containsKey(iconNo)) {
    return;
  }
  framePosPercentListForAllIconSections[iconNo]!.insert(i, framePos);
  currntframePosPercentList.insert(i, framePos);
  projectList[currentProjectNo].iconSections[iconNo].frames.insert(
      i,
      Frame(
          frameNo:
              projectList[currentProjectNo].iconSections[iconNo].frames.length,
          singleFrameModel: SingleFrameModel(
              points: List.from(projectList[currentProjectNo]
                  .iconSections[iconNo]
                  .frames[currentFrameNo]
                  .singleFrameModel
                  .points),
              framePosition: framePos,
              frameNo: projectList[currentProjectNo]
                  .iconSections[iconNo]
                  .frames
                  .length)));

  currentFrameNo = i;
}
