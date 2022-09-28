import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

void addNewFrame() {
  projectList[currentProjectNo].iconSections[currentIconSectionNo].frames.add(Frame(
      frameNo: projectList[currentProjectNo].iconSections[currentIconSectionNo].frames.length,
      singleFrameModel: SingleFrameModel(
          frameNo:
              projectList[currentProjectNo].iconSections[currentIconSectionNo].frames.length)));

  currentFrameNo =
      projectList[currentProjectNo].iconSections[currentIconSectionNo].frames.length - 1;
}
