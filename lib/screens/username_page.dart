// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:developer';

import 'package:animated_icon_demo/Global/global.dart';
import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/geometric%20functions/get_startpoint_for_polygon_withcenter_side_and_no.dart';

import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart';
import 'package:animated_icon_demo/providers/user_page_provider.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

QuerySnapshot<Map<String, dynamic>>? serverData;
String _username = "";

class UserNamePage extends StatefulWidget {
  UserNamePage({Key? key}) : super(key: key);

  @override
  State<UserNamePage> createState() => _UserNamePageState();
}

class _UserNamePageState extends State<UserNamePage> {
  bool showLoading = false;
  bool showError = false;
  TextEditingController textEditingController =
      TextEditingController(text: Shared.getUserName());
  @override
  Widget build(BuildContext context) {
    double logoHeight = h * 0.3;
    UserPageProvider userPageProvider = Provider.of<UserPageProvider>(context);

    double avalableHeight =
        (h * 0.9 - topbarHeight * 2 - 16 - logoHeight - 20).abs();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: logoHeight,
              // color: Colors.green,
              child: Image.asset(
                "assets/logos/annim6.gif",
                fit: BoxFit.cover,
                // https://www5.flamingtext.com/net-fu/jobs/28121823796156965.html
              ),
            ),
            Container(
              margin: EdgeInsets.all(8),
              width: w * 0.4,
              constraints: const BoxConstraints(minWidth: 300),
              child: const Text(
                " Please enter username",
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
            Container(
              margin: EdgeInsets.all(8),
              // height: topbarHeight,
              width: w * 0.4,
              constraints: const BoxConstraints(minWidth: 300),
              child: Center(
                child: TextField(
                  scrollPadding: EdgeInsets.zero,
                  controller: textEditingController,
                  style: TextStyle(color: Colors.white, fontSize: 20),
                  onChanged: (value) {
                    showError = true;
                    setState(() {});
                  },
                  decoration: InputDecoration(
                      errorText:
                          (textEditingController.text.trim().length < 5) &&
                                  showError
                              ? 'Minimum 5 Letters'
                              : null,
                      hintText: "Please enter your username",
                      hintStyle: TextStyle(color: Colors.white.withAlpha(180)),
                      border: OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white))),
                ),
              ),
            ),
            ElevatedButton(
                style: ButtonStyle(
                    backgroundColor: MaterialStateColor.resolveWith((d) {
                  return textEditingController.text.trim().length > 4
                      ? Colors.blue
                      : Colors.grey.withAlpha(180);
                })),
                onPressed: () async {
                  // if (textEditingController.text.trim() == "username") {
                  //   showMessageToUserToEnterNewUserNameDIffThanDefault(context);
                  //   return;
                  // }
                  if (textEditingController.text.trim().length < 5) {
                    setState(() {});
                    return;
                  }
                  showLoading = true;
                  setState(() {});
                  projectList.clear();
                  await getProjectsAndShowOnScreen(userPageProvider);
                  return;
                },
                child: const Text("Go")),
            (projectList.isNotEmpty)
                ? Container(
                    margin: EdgeInsets.all(8),
                    width: w,
                    height: avalableHeight,
                    child: SingleChildScrollView(
                      child: Wrap(
                        children: [
                          ...List.generate(
                              projectList.length,
                              (i) => Container(
                                    width: 150,
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: currentProjectNo == i
                                            ? Colors.grey.withAlpha(180)
                                            : Colors.transparent),
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 130,
                                          height: 130,
                                          child: TapImageIcon(
                                            imagePath: IconsImagesPaths.file,
                                            onTap: () async {
                                              currentProjectNo = i;
                                              Navigator.maybePop(context);

                                              Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (context) =>
                                                          LandscapeLayoutScreen()
                                                      // DrawGridCanvase()

                                                      ));
                                            },
                                          ),
                                        ),
                                        Text(
                                          projectList[i].projectName,
                                          maxLines: 2,
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.visible,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.white),
                                        )
                                      ],
                                    ),
                                  ))
                        ],
                      ),
                    )
                    // GridView(
                    //   padding: const EdgeInsets.all(20),
                    //   gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    //       crossAxisCount: 10, childAspectRatio: 0.8),

                    // ),
                    )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showLoading)
                        Container(
                          width: w,
                          height: avalableHeight,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                    ],
                  )
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

  Future getProjectsAndShowOnScreen(UserPageProvider userPageProvider) async {
    if (textEditingController.text.trim().length > 4) {
      
      Shared.setUserName(textEditingController.text.trim());
      log("username before get data [${Shared.getUserName()}]");
      serverData = await DataService()
          .usersInstance
          .get(const GetOptions(source: Source.server));

      try {
        await getNewProjectName();
      } catch (e) {
        log("err in getNewProjectName : $e");
      }
    }
    log("projectslist ${projectList.length}");
    userPageProvider.updateUI();
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

  log("username in getNewProjectName ${Shared.getUserName()} ");
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
              position: const Point(x: 0, y: 0))
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
/*
Previous Go button code include both get data frpm server an load latest project and go to next screen

                  if (textEditingController.text.trim().length > 4) {
                    Shared.setUserName(textEditingController.text.trim());
                    serverData = await DataService()
                        .usersInstance
                        .get(const GetOptions(source: Source.server));

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
                    if (projectList.isEmpty) {
                      showDialog(
                          context: context,
                          builder: (context) => const Dialog(
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ));
                    }
                    currentProjectNo = 0;
                    loadDataBeforeLoadingLandscapePage();
                    Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => LandscapeLayoutScreen()
                            // DrawGridCanvase()

                            ));
                  }
*/