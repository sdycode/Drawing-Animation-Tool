import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Future<Project>
Future<Project?> getCurrentProjectInstance() async {
  QuerySnapshot<Map<String, dynamic>> data = await DataService()
      .usersInstance
      .doc(Shared.getUserName())
      .collection("Project_$currentProjectNo")
      .get();
  try {
    log("map for project= ${data.docs}");
    Project project = Project.fromMap(data.docs.first.data());
     log("map for project afer= $project}");
    return project;
    log("map for project ${project.projectId}");
  } catch (e) {
    log("map for project err ${e}");
  }
  return Project(projectId: "Project_$currentProjectNo", projectName: currentProjectName+"_$currentProjectNo", iconSections: []);
  return null;
  // Pro
}
