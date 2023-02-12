import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/update_project_no_list.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

createNewProjectWithNo(int projectNo,
    {String projectName = "Annimation"}) async {
  List<int> prnoList = await getNewPorjectNo();
  projectNo = prnoList.last + 1;
  // log("newPorjet no ${projectNo}");
  prnoList.add(projectNo);
  update_projctno_list(prnoList);
  CollectionReference<Map<String, dynamic>> colref = DataService()
      .usersInstance
      .doc(Shared.getUserName())
      .collection("Project_$projectNo");
// colref.doc("Project_$projectNo").set(data)

  colref.doc("Project_$projectNo").set
  (
    
    Project(
          projectId: "Project_$projectNo",
          projectName: projectName + '_' + "$projectNo",   width: defaultProjectWidth,
      height: defaultProjectHeight,
          iconSections: [
            IconSection(
                iconSectionNo: 0,
                iconSectionName: "Polyline_0",
                position: Point.zero,
                frames: [
                  Frame(
                      frameNo: 0,
                      singleFrameModel: SingleFrameModel(frameNo: 0)),
                  Frame(
                      frameNo: 1,
                      singleFrameModel: SingleFrameModel(frameNo: 1))
                ]),
            IconSection(
                iconSectionNo: 1,
                iconSectionName: "Polyline_1",  position: Point.zero,
                frames: [
                  Frame(
                      frameNo: 0,
                      singleFrameModel: SingleFrameModel(frameNo: 0)),
                  Frame(
                      frameNo: 1,
                      singleFrameModel: SingleFrameModel(frameNo: 1))
                ]),
            IconSection(
                iconSectionNo: 2,
                iconSectionName: "Polyline_2",  position: Point.zero,
                frames: [
                  Frame(
                      frameNo: 0,
                      singleFrameModel: SingleFrameModel(frameNo: 0)),
                  Frame(
                      frameNo: 1,
                      singleFrameModel: SingleFrameModel(frameNo: 1))
                ]),
          ]).toMap()
          );
}
