import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/animate_points_model.dart';

void setAnimatingPointsForMultisectionsWith2frames() {
   log("checkcnt ${checkNoofFramesAndPointsAreCorrectForMultiSectionAnimation()}");
  // if (!checkNoofFramesAndPointsAreCorrectForMultiSectionAnimation()) {
  //   log("checkcnt true");
  //   framePointsForMultiSectionsAreSetForAnimation = false;
  //   return;
  // }

  currentFrameNo = 0;
  animatePointsModels.clear();
  iconSectionNosIncludedInAnimation.forEach((no) {
    log("iconno $no");
    frame1Points = List.from(projectList[currentProjectNo]
        .iconSections[no]
        .frames[currentFrameNo]
        .singleFrameModel
        .points);
    frame2Points = List.from(projectList[currentProjectNo]
        .iconSections[no]
        .frames[currentFrameNo + 1]
        .singleFrameModel
        .points);
    animatingFramePoints = List.from(projectList[currentProjectNo]
        .iconSections[no]
        .frames[currentFrameNo]
        .singleFrameModel
        .points);
    AnimatePointsModel animatePointsModel =
        AnimatePointsModel.withFrameAndAnimePointsPoints(
            frame1Points, frame2Points, animatingFramePoints);
    animatePointsModels.add(animatePointsModel);
  });
  int c = 0;
  animatePointsModels.forEach((e) {
    log("cnt $c : ${e.frame1Points.length} / ${e.frame2Points.length} /  ${e.animatingFramePoints.length}");
    c++;
  });
}

bool checkNoofFramesAndPointsAreCorrectForMultiSectionAnimation() {
  bool allOk = false;
  // Check Frame Nos
  iconSectionNosIncludedInAnimation.forEach((no) {
    if (projectList[currentProjectNo].iconSections[no].frames.length < 2) {
      allOk = false;
      return;
    }
  });
  allOk = true;
  iconSectionNosIncludedInAnimation.forEach((no) {
    if (projectList[currentProjectNo]
            .iconSections[no]
            .frames[0]
            .singleFrameModel
            .points
            .length !=
        projectList[currentProjectNo]
            .iconSections[no]
            .frames[1]
            .singleFrameModel
            .points
            .length) {
      allOk = false;
      return;
    }
  });

  return allOk;
}
