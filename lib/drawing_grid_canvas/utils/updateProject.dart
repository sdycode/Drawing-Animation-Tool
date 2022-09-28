import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/create_new_empty_project_with_next_id_name.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_current_project_instance.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
          projectName: curProject.projectName,
          iconSections: projectList[currentProjectNo].iconSections);
      curProject = currentProject;
      // getNewPorjectNo();
      int projectNo = 0;
      CollectionReference<Map<String, dynamic>> colref = DataService()
          .usersInstance
          .doc(Shared.getUserName())
          .collection("Project_$projectNo");
      try {
        colref.doc("Project_$projectNo").set(updatingProject.toMap());
        log("project updated");
      } catch (e) {
        log("project update failed $e");
      }

      // updateProject(updatingProject);
    }
  }