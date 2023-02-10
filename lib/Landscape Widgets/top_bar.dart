import 'dart:convert';
import 'dart:typed_data';

import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/drawingObjectbutton.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/drawingTypeButton.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/fileButton.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_iconsection.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/update_all_projects.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/utils/text_field_methods/toggle%20methods/toggleShowAnimationBoard.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_saver/file_saver.dart';

class TopBar extends StatefulWidget {
  TopBar({Key? key}) : super(key: key);

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> {
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
        color: Color.fromARGB(255, 14, 15, 47),
        child: Row(
          children: [
            fileButton(provData, _fileOperationKey, context),
            // Container(
            //   width: 2,
            //   height: 20,
            //   color: Colors.white,
            // ),
            Container(
              // margin: EdgeInsets.only(left: 4),
              // padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: shapePanORModify == ShapePanORModify.modify
                      ? Colors.transparent
                      : Colors.blue.shade400.withAlpha(150)),
              child: IconButton(
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
                  icon: Icon(Icons.pan_tool)),
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
                padding: const EdgeInsets.all(4.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(220),
                      ),
                      child: Image.asset(IconsImagesPaths.export)),
                ),
              ),
            ),
            Spacer(),
            RawChip(
              onPressed: () {
                toggleShowAnimationBoard();
                if (showAnimationBoard == ShowAnimationBoard.show) {
                  animSheetProvider.animationSheetFromTop = 500;
                  // animSheetProvider.updateUI();
                }

                provData.updateUI();
              },
              label: Text("Animation Board"),
              // onDeleted: (){ toggleShowAnimationBoard();
              //         provData.updateUI();},
              avatar: Container(
                margin: EdgeInsets.only(right: 2, left: 2),
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
                            : Icons. check_circle_outline_outlined ,
                        size: 20,
                      )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/*

  // Text(componentSelectedTypeInTree.name),
            // Container(
            //   height: topbarHeight,
            //   width: 60.sw(context),
            //   child: Row(
            //     mainAxisSize: MainAxisSize.min,
            //     children: [
            //       ...(projectList[currentProjectNo]
            //           .iconSections[currentIconSectionNo]
            //           .frames[currentFrameNo]
            //           .singleFrameModel
            //           .cornerBoxPoints
            //           .map((Point e) {
            //         return
            //             // Text("data");
            //             Text(
            //                 "[ ${e.x.toStringAsFixed(2)} / ${e.y.toStringAsFixed(2)} ]");
            //       }).toList())
            //     ],
            //   ),
            // ),

            // Text(drawingObjectType.toString()),
            // */
