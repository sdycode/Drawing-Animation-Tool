// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
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
      TextEditingController(text: "shu223");
  @override
  Widget build(BuildContext context) {
    if (Shared.getUserName().isNotEmpty) {}
    // {
    //   Navigator.pushReplacement(
    //       context, MaterialPageRoute(builder: (context) => DrawGridCanvase()));
    // }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: textEditingController,
            ),
            ElevatedButton(
                onPressed: () async {
                  if (textEditingController.text.trim().length > 4) {
                    Shared.setUserName(textEditingController.text.trim());
                    serverData = await DataService()
                        .usersInstance
                        .get(GetOptions(source: Source.server));
                    // if (await checkIfUserLareadyExist()) {
                    //   await getUpdatedProjectName();
                    // } else {
                    //   await getNewProjectName();
                    // }
                    await getNewProjectName();
                    Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => DrawGridCanvase()));
                  }
                },
                child: Text("Go"))
          ],
        ),
      ),
    );
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
    projectList.add(Project(
        projectId: "Project_0",
        projectName: currentProjectName + "_0",
        iconSections: [
          IconSection(
              iconSectionNo: 0,
              iconSectionName: "iconSectionName_0",
              frames: [
                Frame(
                    frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0))
              ])
        ]));
    await DataService()
        .usersInstance
        .doc(Shared.getUserName())
        .collection("Project_0")
        .doc("Project_0")
        .set(projectList.first.toMap());
    await loadAllProjectsFromServer();

    return "${Shared.getUserName()}_0";
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

  Future setUserProfile(
    String newProjectName,
  ) async {
    List<int> nos = await getNewPorjectNo();
    if (nos.length < 2) {
      log("noss are $nos");
      List<int> getProjectNo = [0];
      DataService().usersInstance.doc("${Shared.getUserName()}").set(
          UserProfile(
                  userName: Shared.getUserName(),
                  password: "password",
                  projects: getProjectNo)
              .toMap());
    }
  }
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
