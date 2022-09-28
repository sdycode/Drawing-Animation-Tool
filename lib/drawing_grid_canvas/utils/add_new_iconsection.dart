import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

void addNewIconSection() {
  currentIconSectionNo++;
  // framesList.add(
  //     [Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0))]);
  // currentIconSectionsList[currentIconSectionNo]
  //     .frames
  //     .add(Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0)));
  projectList[currentProjectNo].iconSections.add(IconSection(
      iconSectionNo: projectList[currentProjectNo].iconSections.length,
      iconSectionName: "iconSectionName_${projectList[currentProjectNo].iconSections.length}",
      frames:[Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0))]));
}
