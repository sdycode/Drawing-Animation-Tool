import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';

void resetSelectedPointIndexAfterAnyChange() {
 
  selectedPointIndex = projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[currentFrameNo]
          .singleFrameModel
          .points
          .length -
      1;
}
