
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/cast_control_points.dart';

void createSingleModel() async {
  SingleFrameModel singleFrameModel = SingleFrameModel(frameNo: 1);
  singleFrameModel.controlMidPoints = castControlPoints(controlMidPoints);
  singleFrameModel.points =
        projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points;
  
  // currntString = singleFrameModel.controlMidPoints.toString();
  String currntString = "\n${singleFrameModel.toMap()}\n";
  // String UserName = "Shubham22";
  // (legacy whole-collection read removed — result was unused; see ProjectRepository)
  // data.docs.forEach(
  //   (e) {
  //     if (e.id.trim().toLowerCase() == userNameController.text .trim().toLowerCase()) {
  //       userNameAlreadyExist = true;
  //     }
  //   },
  // );
  // if (!userNameAlreadyExist) {
  //   DataService().usersInstance.doc(userNameController.text ).set(singleFrameModel.toMap());
  // }
  // if(userNameController.text.length >4){ DataService().usersInstance.doc(userNameController.text ).set(singleFrameModel.toMap());}
}
