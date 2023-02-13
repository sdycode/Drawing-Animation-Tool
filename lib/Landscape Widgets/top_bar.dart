// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:typed_data';

import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/drawingObjectbutton.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/drawingTypeButton.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/fileButton.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/libraryButton.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/update_framePos_list.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/screens/username_page.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:animated_icon_demo/utils/text_field_methods/toggle%20methods/toggleShowAnimationBoard.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:annimation/annimation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:html' as html;

class TopBar extends StatefulWidget {
  TopBar({Key? key}) : super(key: key);

  @override
  State<TopBar> createState() => _TopBarState();
}

TextEditingController projectNameTextController = TextEditingController();

class _TopBarState extends State<TopBar> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    if (projectList.length > currentProjectNo) {
      projectNameTextController.text =
          projectList[currentProjectNo].projectName;
    }
  }

  @override
  Widget build(BuildContext context) {
    ProvData provData = Provider.of<ProvData>(context, listen: false);
    AnimSheetProvider animSheetProvider =
        Provider.of<AnimSheetProvider>(context);

    return InkWell(
      onTap: () {
        // setState(() {});
      },
      child: Container(
        width: double.infinity,
        height: topbarHeight,
        color: const Color.fromARGB(255, 14, 15, 47),
        child: Row(
          children: [
            IconButton(
                onPressed: () async {
                  Navigator.pushReplacement(context, MaterialPageRoute(
                    builder: (context) {
                      return UserNamePage();
                    },
                  ));
                },
                icon: Icon(Icons.arrow_back)),
            if (projectList.length > currentProjectNo)
              Tooltip(
                message: "Project Name",
                child: TextButton.icon(
                    onPressed: () async {
                      debugLog(
                          "pname  :  ${currentProjectNo} :    projectNameTextController.text ");

                      if (projectList.length > currentProjectNo) {
                        projectNameTextController.text =
                            projectList[currentProjectNo].projectName;
                        debugLog(
                            "pname ${projectList[currentProjectNo].projectName} :  ${currentProjectNo} :    projectNameTextController.text ");
                      }

                      await showProjectNameEditDialog(
                          context, animSheetProvider);

                      animSheetProvider.updateUI();
                    },
                    icon: const Icon(Icons.file_copy),
                    label: Text(projectList[currentProjectNo].projectName)),
              ),

            fileButton(provData, _fileOperationKey, context),
            // Container(
            //   width: 2,
            //   height: 20,
            //   color: Colors.white,
            // ),
            Container(
              // margin: EdgeInsets.only(left: 4),
              margin: EdgeInsets.all(4),
              width: topbarHeight - 8,
              height: topbarHeight - 8,
              decoration: BoxDecoration(
                  border: shapePanORModify == ShapePanORModify.modify
                      ? null
                      : Border.all(),
                  borderRadius: BorderRadius.circular(8),
                  color: shapePanORModify == ShapePanORModify.modify
                      ? Colors.transparent
                      : Colors.blue.shade400.withAlpha(80)),
              child: FittedBox(
                child: IconButton(
                    // iconSize: topbarHeight*0.36,
                    tooltip: "Pan",
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      if (shapePanORModify == ShapePanORModify.modify) {
                        shapePanORModify = ShapePanORModify.pan;
                      } else {
                        shapePanORModify = ShapePanORModify.modify;
                      }
                      provData.updateUI();
                    },
                    icon: const Icon(
                      Icons.pan_tool,
                      // size: topbarHeight*0.36,
                    )),
              ),
            ),
            drawingTypeButton(provData, _menuKey),
            drawingObjectbutton(provData, _drawingObjectTypeKey),
            IconButton(
              padding: EdgeInsets.zero,
              tooltip: "Export",
              onPressed: () async {
                exportProjectToJson();
              },
              icon: Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(220),
                      ),
                      child: Image.asset(IconsImagesPaths.export)),
                ),
              ),
            ),
            const Spacer(),

            libraryButton(context, animSheetProvider, provData),
            youtubeButton(context),
            Padding(
              padding: const EdgeInsets.all(0),
              child: RawChip(
                onPressed: () {
                  toggleShowAnimationBoard();
                  if (showAnimationBoard == ShowAnimationBoard.show) {
                    animSheetProvider.animationSheetFromTop = 500;
                    // animSheetProvider.updateUI();
                  }

                  provData.updateUI();
                },
                label: const Text("Animation Board"),
                // onDeleted: (){ toggleShowAnimationBoard();
                //         provData.updateUI();},
                avatar: Container(
                  margin: const EdgeInsets.only(right: 2, left: 2),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2, right: 2),
                    child: TapIcon(
                        onTap: () {
                          toggleShowAnimationBoard();
                          provData.updateUI();
                        },
                        icon: Icon(
                          showAnimationBoard == ShowAnimationBoard.show
                              ? Icons.check_circle
                              : Icons.check_circle_outline_outlined,
                          size: 20,
                        )),
                  ),
                ),
              ),
            ),

            IconButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  scaffoldKey.currentState!.openEndDrawer();
                },
                icon: const Icon(Icons.menu)),
          ],
        ),
      ),
    );
  }

  showProjectNameEditDialog(
      BuildContext context, AnimSheetProvider animSheetProvider) async {
    await showDialog(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Please enter project name",
                    style: TextStyle(
                      color: Colors.black,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(8),

                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8)),
                  // height: topbarHeight,
                  constraints: BoxConstraints(maxHeight: 100),
                  width: 200,
                  child: TextField(
                    scrollPadding: EdgeInsets.zero,
                    keyboardType: TextInputType.text,
                    maxLines: 1,
                    decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8))),
                    onChanged: (value) {},
                    style: const TextStyle(color: Colors.white),
                    controller: projectNameTextController,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                      onPressed: () {
                        if (projectNameTextController.text.trim().isNotEmpty) {
                          projectList[currentProjectNo].projectName =
                              projectNameTextController.text.trim();
                        }
                        animSheetProvider.updateUI();
                        Navigator.maybePop(context);
                      },
                      child: const Text("Done")),
                )
              ],
            ),
          );
        });
  }
}

youtubeButton(BuildContext context) {
  return Container(
    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white),
      // color:topbarColor,
      borderRadius: BorderRadius.circular(topbarHeight * 0.5),
      //  boxShadow: [BoxShadow(color: Colors.blue, spreadRadius: 1, blurRadius: 3, offset: Offset(0,0))]
    ),
    child: TextButton.icon(
        onPressed: () async {
          html.window.open('https://youtu.be/m_NibA9HXW8', "_blank");
        },
        icon: Container(
            height: topbarHeight * 0.7,
            child: Image.asset(
              "assets/icons/youtube.png",
              fit: BoxFit.contain,
            )),
        label: const Text(
          "Tutorial",
          style: TextStyle(
            fontWeight: FontWeight.bold, color: Colors.white,
            // fontSize: topbarHeight*0.4
          ),
        )),
  );
}


void exportProjectToJson() async {
  String jsonDecodedString = jsonEncode(projectList[currentProjectNo].toMap());
  List<int> list = jsonDecodedString.codeUnits;
  Uint8List jsonDataAsUint8List = Uint8List.fromList(list);

  await FileSaver.instance.saveFile(
      projectList[currentProjectNo].projectName.trim(),
      jsonDataAsUint8List,
      ".json",
      mimeType: MimeType.JSON);
}

void clickOnFileIcon(BuildContext context) {}

final GlobalKey<PopupMenuButtonState> _menuKey =
    GlobalKey<PopupMenuButtonState>();
final GlobalKey<PopupMenuButtonState> _fileOperationKey =
    GlobalKey<PopupMenuButtonState>();
BuildContext? thisContext;
// Menu Option for drawing object selection like rect, circle trianlge etc

final GlobalKey<PopupMenuButtonState> _drawingObjectTypeKey =
    GlobalKey<PopupMenuButtonState>();
