// ignore_for_file: unnecessary_string_interpolations


import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/data/project_repository.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/shared/shared.dart';

Future updateAllProjects() async {
  int prno = 0;
  // log("prlist ${projectList.length}");
  await Future.forEach(projectList, (Project pr) async {
    // if(currentProjectNo == prno){}
    pr.width = drawingBoardSize.width;
    pr.height = drawingBoardSize.height;
    pr.position = Point.fromOffset(drawingBoardPosition);
    await ProjectRepository().saveProject(Shared.getUserName(), prno, pr);
    // log("prlist ${projectList.length} done for $prno");
    prno++;
  });
}
