// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/geometric%20functions/get_startpoint_for_polygon_withcenter_side_and_no.dart';

import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

QuerySnapshot<Map<String, dynamic>>? serverData;
String _username = "";

class UserNamePage extends StatefulWidget {
  UserNamePage({Key? key}) : super(key: key);

  @override
  State<UserNamePage> createState() => _UserNamePageState();
}

class _UserNamePageState extends State<UserNamePage> {
  TextEditingController textEditingController =
      TextEditingController(text: "shubham22");
  @override
  Widget build(BuildContext context) {
    if (Shared.getUserName().isNotEmpty) {}
    // {
    //   Navigator.pushReplacement(
    //       context, MaterialPageRoute(builder: (context) => DrawGridCanvase()));
    // }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: textEditingController,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                  hintText: "Please enter your username",
                  hintStyle: TextStyle(color: Colors.white.withAlpha(180)),
                  enabledBorder: OutlineInputBorder()),
            ),
            ElevatedButton(
                onPressed: () async {
                  if (textEditingController.text.trim().length > 4) {
                    Shared.setUserName(textEditingController.text.trim());
                    serverData = await DataService()
                        .usersInstance
                        .get(GetOptions(source: Source.server));

                    try {
                      await getNewProjectName();
                    } catch (e) {
                      log("err in getNewProjectName : $e");
                    }
                    if (projectList[currentProjectNo]
                            .iconSections[0]
                            .frames
                            .length <
                        2) {
                      projectList[currentProjectNo].iconSections[0].frames.add(
                          Frame(
                              frameNo: 1,
                              singleFrameModel: SingleFrameModel(frameNo: 1)));
                    }

                    log("beforenavi $currentProjectNo :  ${projectList[currentProjectNo].iconSections[0].frames.length}");
                    currentProjectNo = projectList.length-2;
                    loadDataBeforeLoadingLandscapePage();
                    Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => LandscapeLayoutScreen()
                            // DrawGridCanvase()

                            ));
                  }
                },
                child: Text("Go"))
          ],
        ),
      ),
    );
  }

  Future<String> getUpdatedProjectName() async {
    String newProjectSuffix = "_0";
    String newProjectName = Shared.getUserName() + newProjectSuffix;
    serverData?.docs.forEach((e) {
      if (e.id == Shared.getUserName()) {
        List l = e.data()['projects'] ?? [];
        int size = l.length;
        newProjectSuffix = ("_$size");
        newProjectName = e.id + newProjectSuffix;
      }
    });

    await setUserProfile(newProjectName);
    return newProjectName;
  }

  Future<bool> checkIfUserLareadyExist() async {
    bool exist = false;
    serverData?.docs.forEach((e) {
      try {
        dynamic data = e.data()['projects'][0][
            'iconSections']; // IconSection.fromMap(e.data()['projects']['iconSections']);
        log("datas for ${e.id} ::  $data");
      } catch (e) {}

      if (e.id.trim() == Shared.getUserName().trim()) {
        exist = true;
      }
    });

    return exist;
  }

  void loadDataBeforeLoadingLandscapePage() {
    debugLog("currentProjectNo $currentProjectNo");
    for (var i = 0;
        i < projectList[currentProjectNo].iconSections.length;
        i++) {
      // log("framebefore $i : ${getFramePosForthisIconSection(projectList[currentProjectNo].iconSections[i])} ");
      framePosPercentListForAllIconSections[i] = getFramePosForthisIconSection(
          projectList[currentProjectNo].iconSections[i]);
    }
  }
}

List<double> getFramePosForthisIconSection(IconSection iconSection) {
  return [
    ...(iconSection.frames.map((e) {
      return e.singleFrameModel.framePosition;
    }))
  ];
}

Future loadAllProjectsFromServer() async {
  List<int> prnos = await getNewPorjectNo();
  if (prnos.length < 2) {
    log("prns length in loadAllProjectsFromServer ${prnos}");
    await addNewProjectToListAndFirebase();
  }
  List<Project> projectsFromServer = [];
  await Future.forEach(prnos, (no) async {
    String projectId = "Project_$no";
    try {
      QuerySnapshot<Map<String, dynamic>> prdata = await DataService()
          .usersInstance
          .doc(Shared.getUserName())
          .collection(projectId)
          .get();
      try {
        projectsFromServer.add(Project.fromMap(prdata.docs.first.data()));
        // log("prdata of $no added to templist : ${prdata.docs.first.data()}");
      } catch (e) {
        // log("prdata of $no proejct convert failed : error ${e}");
      }

      // log("prdata of $no : ${prdata.docs.first.data()}");
    } catch (e) {
      // log("prdata of $no : error ${e}");
    }
  });
  projectList.clear();
  projectList = List.from(projectsFromServer);
  List<int> newprnos = await getNewPorjectNo();
  if (projectList.length > 1) {
    currentProjectNo = 1;
  }
  // log("prns new length in loadAllProjectsFromServer ${newprnos} / ${projectList.length} / ${currentProjectNo}");

  if (projectList.length > 1) {
    currentProjectNo = 1;
  } else {
    await loadAllProjectsFromServer();
    // currentProjectNo = 0;
  }

  // log("prns after all  length in loadAllProjectsFromServer ${newprnos} / ${projectList.length} / ${currentProjectNo}");
}

Future<String> getNewProjectName() async {
  List<int> prnos = await getNewPorjectNo();
  await DataService().usersInstance.doc("${Shared.getUserName()}").set(
      UserProfile(
              userName: Shared.getUserName(),
              password: "password",
              projects: prnos)
          .toMap());
  String newProjectSuffix = "_0";
  String newProjectName = Shared.getUserName() + newProjectSuffix;

  await setUserProfile(newProjectName);
  try {
    projectList.add(Project(
        projectId: "Project_0",
        projectName: currentProjectName + "_0",
        width: defaultProjectWidth,
        height: defaultProjectHeight,
        iconSections: [
          IconSection(
              iconSectionNo: 0,
              iconSectionName: "Polyline_0",
              frames: [
                Frame(
                    frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0)),
                Frame(
                    frameNo: 1, singleFrameModel: SingleFrameModel(frameNo: 1))
              ],
              position: Point(x: 0, y: 0))
        ]));
  } catch (e) {}
  try {
    await DataService()
        .usersInstance
        .doc(Shared.getUserName())
        .collection("Project_0")
        .doc("Project_0")
        .set(projectList.first.toMap());
  } catch (e) {}

  try {
    await loadAllProjectsFromServer();
  } catch (e) {}

  return "${Shared.getUserName()}_0";
}

Future setUserProfile(
  String newProjectName,
) async {
  List<int> nos = await getNewPorjectNo();
  if (nos.length < 2) {
    log("noss are $nos");
    List<int> getProjectNo = [0];
    DataService().usersInstance.doc("${Shared.getUserName()}").set(UserProfile(
            userName: Shared.getUserName(),
            password: "password",
            projects: getProjectNo)
        .toMap());
  }
}
