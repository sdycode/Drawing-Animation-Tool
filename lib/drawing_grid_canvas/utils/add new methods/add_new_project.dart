import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/data/project_repository.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/update_project_no_list.dart';
import 'package:animated_icon_demo/shared/shared.dart';

Future addNewProjectToListAndFirebase([String? projName]) async {
  List<int> prnos = await getNewPorjectNo();
  int projectNo = prnos.last + 1;
  Project newProject = Project(
      projectId: "Project_$projectNo",
      projectName: projName ?? "${currentProjectName}_$projectNo",
      width: defaultProjectWidth,
      height: defaultProjectHeight,
      iconSections: [
        IconSection(
            iconSectionNo: 0,
            iconSectionName: "Polyline_0",
            frames: [
              Frame(
                  frameNo: 0,
                  singleFrameModel:
                      SingleFrameModel(frameNo: 0, framePosition: 0.0)),
              Frame(
                  frameNo: 1,
                  singleFrameModel:
                      SingleFrameModel(frameNo: 1, framePosition: 100.0))
            ],
            position: const Point(x: 0, y: 0))
      ]);

  projectList.add(newProject);
  log("project added then prnos $prnos and $projectNo");
  prnos.add(projectNo);
  await update_projctno_list(prnos);
  try {
    await ProjectRepository()
        .saveProject(Shared.getUserName(), projectNo, newProject);
    log("project added");
  } catch (e) {
    log("project add failed in addNewProjectToListAndFirebase $e");
  }

  // log("newPorjet no ${projectNo}");
}
