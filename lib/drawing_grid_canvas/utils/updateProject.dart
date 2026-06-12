import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/data/project_repository.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_current_project_instance.dart';
import 'package:animated_icon_demo/shared/shared.dart';

// Future updateProject(Project project) async {
//   List<String> list = project.projectId.split('_');
//   int projectNo = list.length > 1 ? int.parse(list[1]) : 0;
//   createNewProjectWithNo(projectNo);
// }


  void updateProjectData() async {
    Project? curProject = await getCurrentProjectInstance();
    if (curProject != null) {
      Project updatingProject = Project(
          projectId: curProject.projectId,
          projectName: curProject.projectName,   width: defaultProjectWidth,
      height: defaultProjectHeight,
          iconSections: projectList[currentProjectNo].iconSections);
      curProject = currentProject;
      // getNewPorjectNo();
      int projectNo = 0;
      try {
        await ProjectRepository()
            .saveProject(Shared.getUserName(), projectNo, updatingProject);
        log("project updated");
      } catch (e) {
        log("project update failed $e");
      }

      // updateProject(updatingProject);
    }
  }