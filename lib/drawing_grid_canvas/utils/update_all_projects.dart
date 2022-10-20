// ignore_for_file: unnecessary_string_interpolations

import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future updateAllProjects() async {
  int prno = 0;
  String projectId = "Project_$prno";
  log("prlist ${projectList.length}");
  await Future.forEach(projectList, (Project pr) async {
    CollectionReference<Map<String, dynamic>> colref = DataService()
        .usersInstance
        .doc(Shared.getUserName())
        .collection("${projectId}");
    // if(currentProjectNo == prno){}
    pr.width = drawingBoardSize.width;
    pr.height = drawingBoardSize.height;
    pr.position = Point.fromOffset(drawingBoardPosition) ;
    await colref.doc("${projectId}").set(pr.toMap());
    log("prlist ${projectList.length} done for $prno");
    prno++;
    projectId = "Project_$prno";
  });
}
