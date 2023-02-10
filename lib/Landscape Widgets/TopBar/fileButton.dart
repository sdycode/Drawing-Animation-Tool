import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/showProjecListInDialog.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/top_bar.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/update_all_projects.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/screens/username_page.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:flutter/material.dart';

fileButton(ProvData provData,
    GlobalKey<PopupMenuButtonState> _fileButtonMenuKey, BuildContext context) {
  return PopupMenuButton(
    key: _fileButtonMenuKey,
    tooltip: "Files",
    itemBuilder: (_) => <PopupMenuItem<FileOperationType>>[
      ...(fileOperationTypsPopupMap.entries
          .map((MapEntry<String, FileOperationType> item) {
        return PopupMenuItem<FileOperationType>(
            padding: const EdgeInsets.all(4),
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
          addNewProjectToListAndFirebase();

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
        _fileButtonMenuKey.currentState!.showButtonMenu();
      },
      height: topbarHeight,
      width: topbarHeight,
      padding: EdgeInsets.all(6),
      cornerRadius: 4,
    ),
  );
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
