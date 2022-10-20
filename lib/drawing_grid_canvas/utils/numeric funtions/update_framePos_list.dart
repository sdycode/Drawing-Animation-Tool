import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';

void updateFramePostList() {
  currntframePosPercentList.clear();
  projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames
      .forEach((e) {
    // log("fore ${e.frameNo}");
    currntframePosPercentList.add(e.singleFrameModel.framePosition);
  });

  List<double> templist = List.from(currntframePosPercentList);
  log("fore ${templist}");
  templist.sort();
  currntframePosPercentList = List.from(templist);
  log("foreafte ${templist}");
  framePosPercentListForAllIconSections[currentIconSectionNo] =
      List.from(templist);
}
