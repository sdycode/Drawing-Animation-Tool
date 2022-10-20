import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

void addNewFrame(double framePos) {
 
  projectList[currentProjectNo].iconSections[currentIconSectionNo].frames.add(
      Frame(
          frameNo:
              projectList[currentProjectNo]
                  .iconSections[currentIconSectionNo]
                  .frames
                  .length,
          singleFrameModel: SingleFrameModel(
              points:List.from( projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .points),
              framePosition: framePos,
              frameNo: projectList[currentProjectNo]
                  .iconSections[currentIconSectionNo]
                  .frames
                  .length)));

  currentFrameNo = projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames
          .length -
      1;
}
