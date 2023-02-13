import 'dart:convert';

import 'package:animated_icon_demo/Global/global.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/libraryButton.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/update_framePos_list.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/container.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:provider/provider.dart';

class LibrarySamples extends StatefulWidget {
  const LibrarySamples({super.key});

  @override
  State<LibrarySamples> createState() => _LibrarySamplesState();
}

class _LibrarySamplesState extends State<LibrarySamples> {
  @override
  Widget build(BuildContext context) {
    List<String> jsonFilesPaths = [
      "assets/library/HomeMenu.json",
      "assets/library/MultiPolygon.json",
      "assets/library/PlayPause.json",
      "assets/library/Squares.json"
    ];
    ProvData provData = Provider.of<ProvData>(
      context,
    );
    AnimSheetProvider animSheetProvider =
        Provider.of<AnimSheetProvider>(context);
    return Positioned(
      left: w * 0.1,
      top: h * 0.15,
      child: Container(
          width: w * 0.8,
          height: h * 0.86,
          color: Colors.white,
          child: Stack(
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: w * 0.8,
                  height: h * 0.86-30,
                  child: SingleChildScrollView(
                    child: Wrap(
                      children: [
                        ...List.generate(jsonFilesPaths.length, (i) {
                          return Column(
                            children: [
                              LibrarySampleWidget(
                                jsonFilePath: jsonFilesPaths[i],
                              ),
                              ElevatedButton(
                                  onPressed: () async {
                                    Map<String, dynamic> proj = {};

                                    try {
                                      String data =
                                          await DefaultAssetBundle.of(context)
                                              .loadString(jsonFilesPaths[i]);

                                      proj = json.decode(data);

                                      Project project = Project.fromMap(proj);

                                      project.projectName =
                                          "Library_" + project.projectName;

                                      // _projectList.clear();

                                      // _projectList.add(project);

                                      projectList[currentProjectNo] = project;

                                      iconSectionIndexesToIncludeInAnimationList
                                          .clear();

                                      for (var i = 0;
                                          i <
                                              projectList[currentProjectNo]
                                                  .iconSections
                                                  .length;
                                          i++) {
                                        iconSectionIndexesToIncludeInAnimationList
                                            .add(i);
                                      }

                                      updateFramePostList();

                                      showLibrary = false;

                                      provData.updateUI();

                                      animSheetProvider.updateUI();
                                    } catch (e) {}
                                  },
                                  child: Text("Go"))
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                    onPressed: () {
                      showLibrary = false;    provData.updateUI();

                                      animSheetProvider.updateUI();
                    },
                    icon: Icon(Icons.close, color: Colors.red,)),
              )
            ],
          )),
    );
  }
}
