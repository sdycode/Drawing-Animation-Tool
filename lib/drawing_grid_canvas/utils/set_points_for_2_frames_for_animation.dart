import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';

void setPointsFor2FramesForAnimation() {
  if (projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames
              .length -
          1 >
      currentFrameNo) {
    frame1Points = List.from(projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[currentFrameNo]
        .singleFrameModel
        .points);
    frame2Points = List.from(projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[currentFrameNo + 1]
        .singleFrameModel
        .points);
        animatingFramePoints =   List.from(projectList[currentProjectNo]
        .iconSections[currentIconSectionNo]
        .frames[currentFrameNo]
        .singleFrameModel
        .points);
        if(frame1Points.isNotEmpty && frame1Points.length == frame2Points.length){
 framePointsSetForAnimation = true;
        }
   
  }
}
