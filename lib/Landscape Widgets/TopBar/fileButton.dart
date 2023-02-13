// ignore_for_file: use_build_context_synchronously

import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/showProjecListInDialog.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/top_bar.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/update_all_projects.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/screens/username_page.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:flutter/material.dart';

fileButton(ProvData provData, GlobalKey<PopupMenuButtonState> fileButtonMenuKey,
    BuildContext context) {
  return PopupMenuButton(
    offset:const  Offset(5,5),
    position: PopupMenuPosition.under,
    key: fileButtonMenuKey,
    tooltip: "Files",
    itemBuilder: (_) => <PopupMenuItem<FileOperationType>>[
      ...(fileOperationTypsPopupMap.entries
          .map((MapEntry<String, FileOperationType> item) {
        return PopupMenuItem<FileOperationType>(
            padding: const EdgeInsets.all(2),
            value: item.value,
            child: Row(
              children: [
                TapImageIcon(
                  tapEnabled: false,
                  padding: const EdgeInsets.all(3),
                  imagePath: item.key,
                  height: topbarHeight * 0.75,
                  width: topbarHeight * 0.75,
                ),
                Container(
                  // padding: EdgeInsets.only(right: 6),
                  child: Text(
                    drawingTypesNamesPopupMap[item.key] ?? "",
                    textAlign: TextAlign.left,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                Spacer(),
              ],
            ));
      })),
    ],
    onSelected: (FileOperationType d) async {
      switch (d) {
        case FileOperationType.export:
          exportProjectToJson();
          break;
        case FileOperationType.New:
          fileOperationType = FileOperationType.New;

          List<int> prnos = await getNewPorjectNo();
          int projectNo = prnos.last + 1;
          String newProjectName = currentProjectName + "_${projectNo}";

          newProjectName =
              await getProjectNameFromUser(context, newProjectName)??newProjectName;currentProjectNo = projectList.length - 1;
        await  addNewProjectToListAndFirebase(newProjectName);

          currentProjectNo = projectList.length - 1;
          // Navigator.maybePop(context);

          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => LandscapeLayoutScreen()
                  // DrawGridCanvase()

                  ));
          break;
        case FileOperationType.save:
          fileOperationType = FileOperationType.save;
          updateAllProjects();

          break;
        case FileOperationType.open:
          fileOperationType = FileOperationType.open;
          showProjecListInDialog(context);

          break;

        default:
          fileOperationType = FileOperationType.save;
      }
      provData.updateUI();
    },
    child: TapImageIcon(
      imagePath: IconsImagesPaths.file,
      onTap: () {
        fileButtonMenuKey.currentState!.showButtonMenu();
      },
      height: topbarHeight * 0.88,
      width: topbarHeight * 0.88,
      padding: EdgeInsets.all(6),
      cornerRadius: 4,
    ),
  );
}

Future<String?> getProjectNameFromUser(
    BuildContext context, String newProjectName) async {
  TextEditingController controller =
      TextEditingController(text: newProjectName);
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
                  controller: controller,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty) {
                        // projectList[currentProjectNo].projectName =
                        //     projectNameTextController.text.trim();

                        newProjectName = controller.text.trim();
                      }

                      Navigator.maybePop(context);
                    },
                    child: const Text("Done")),
              )
            ],
          ),
        );
      });
  return newProjectName;

  return null;
}

Map<String, FileOperationType> fileOperationTypsPopupMap = {
  IconsImagesPaths.newfile: FileOperationType.New,
  IconsImagesPaths.save: FileOperationType.save,
  IconsImagesPaths.openfile: FileOperationType.open,
  IconsImagesPaths.export: FileOperationType.export
};
Map<String, String> drawingTypesNamesPopupMap = {
  IconsImagesPaths.newfile: "New",
  IconsImagesPaths.save: "Save",
  IconsImagesPaths.openfile: "Open",
  IconsImagesPaths.export: "Export"
};
