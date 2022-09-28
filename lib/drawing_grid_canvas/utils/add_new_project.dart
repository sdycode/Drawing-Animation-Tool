import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/update_project_no_list.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future addNewProjectToListAndFirebase() async {
  List<int> prnos = await getNewPorjectNo();
int projectNo = prnos.last + 1;
  Project newProject = Project(
      projectId: "Project_${projectNo}",
      projectName: currentProjectName + "_${projectNo}",
      iconSections: [
        IconSection(
            iconSectionNo: 0,
            iconSectionName: "iconSectionName_0",
            frames: [
              Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0))
            ])
      ]);

  projectList.add(newProject);
   CollectionReference<Map<String, dynamic>> colref = DataService()
          .usersInstance
          .doc(Shared.getUserName())
          .collection("Project_$projectNo");
          log("project added then prnos $prnos and $projectNo");
            prnos.add(projectNo);
  update_projctno_list(prnos);
      try {
        colref.doc("Project_$projectNo").set(newProject.toMap());
        log("project added");
      } catch (e) {
        log("project add failed $e");
      }

 
  // log("newPorjet no ${projectNo}");

}
