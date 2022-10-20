import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_iconsection.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/update_all_projects.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/utils/text_field_methods/toggle%20methods/toggleShowAnimationBoard.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TopBar extends StatefulWidget {
  TopBar({Key? key}) : super(key: key);

  @override
  State<TopBar> createState() => _TopBarState();
}

Map<String, DrawingType> drawingTypesPopupMap = {
  IconsImagesPaths.dotsicon: DrawingType.points,
  IconsImagesPaths.linesThickicon: DrawingType.pointsAndLines,
  IconsImagesPaths.closeShapeicon: DrawingType.closedCustomPath,
};
Map<String, String> drawingTypesNamesPopupMap = {
  IconsImagesPaths.dotsicon: "Points",
  IconsImagesPaths.linesThickicon: "Lines",
  IconsImagesPaths.closeShapeicon: "Closed",
};
final GlobalKey<PopupMenuButtonState> _menuKey =
    GlobalKey<PopupMenuButtonState>();
button(ProvData provData) {
  return PopupMenuButton(
    key: _menuKey,
    tooltip: "Drawing",
    itemBuilder: (_) => <PopupMenuItem<DrawingType>>[
      ...(drawingTypesPopupMap.entries
          .map((MapEntry<String, DrawingType> item) {
        return PopupMenuItem<DrawingType>(
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
                Spacer(),
                Container(
                  // padding: EdgeInsets.only(right: 6),
                  child: Text(
                    drawingTypesNamesPopupMap[item.key] ?? "",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                Spacer(),
              ],
            ));
      })),
    ],
    onSelected: (DrawingType d) {
      switch (d) {
        case DrawingType.points:
          drawingType = DrawingType.points;

          break;
        case DrawingType.closedCustomPath:
          drawingType = DrawingType.closedCustomPath;

          break;
        case DrawingType.pointsAndLines:
          drawingType = DrawingType.pointsAndLines;

          break;
        default:
          drawingType = DrawingType.points;
      }
      provData.updateUI();
    },
    child: TapImageIcon(
      imagePath: IconsImagesPaths.linesThickicon,
      onTap: () {
        _menuKey.currentState!.showButtonMenu();
      },
      height: topbarHeight,
      width: topbarHeight,
      padding: EdgeInsets.all(6),
      cornerRadius: 4,
    ),
  );
}

BuildContext? thisContext;
// Menu Option for drawing object selection like rect, circle trianlge etc

Map<String, DrawingObjectType> drawingObjectTypesPopupMap = {
  IconsImagesPaths.polyCurveicon: DrawingObjectType.polyline,
  IconsImagesPaths.trianlgeicon: DrawingObjectType.triangle,
  IconsImagesPaths.recticon: DrawingObjectType.rectangle,
  IconsImagesPaths.polygonicon: DrawingObjectType.polygon,
  IconsImagesPaths.circleicon: DrawingObjectType.circle,
};
Map<String, String> drawingObjectTypesNamesPopupMap = {
  IconsImagesPaths.polyCurveicon: "polyline",
  IconsImagesPaths.trianlgeicon: "triangle",
  IconsImagesPaths.recticon: "rectangle",
  IconsImagesPaths.polygonicon: "polygon",
  IconsImagesPaths.circleicon: "circle",
};

final GlobalKey<PopupMenuButtonState> _drawingObjectTypeKey =
    GlobalKey<PopupMenuButtonState>();
drawingObjectbutton(ProvData provData) {
  return PopupMenuButton(
    key: _drawingObjectTypeKey,
    tooltip: "Shapes",
    itemBuilder: (_) => <PopupMenuItem<DrawingObjectType>>[
      ...(drawingObjectTypesPopupMap.entries
          .map((MapEntry<String, DrawingObjectType> item) {
        return PopupMenuItem<DrawingObjectType>(
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
              
                Spacer(),
                Container(
                  // padding: EdgeInsets.only(right: 6),
                  child: Text(
                    drawingObjectTypesNamesPopupMap[item.key] ?? "",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                Spacer(),
              ],
            ));
      })),
    ],
    onSelected: (DrawingObjectType d) {
      switch (d) {
        case DrawingObjectType.polyline:
          drawingObjectType = DrawingObjectType.polyline;

          break;
        case DrawingObjectType.triangle:
          drawingObjectType = DrawingObjectType.triangle;

          addNewIconSectionPolygon(3);
          break;
        case DrawingObjectType.rectangle:
          drawingObjectType = DrawingObjectType.rectangle;
          addNewIconSectionAsRectangle();

          break;
        case DrawingObjectType.polygon:
          drawingObjectType = DrawingObjectType.polygon;
          addNewIconSectionPolygon(5);
          break;
        case DrawingObjectType.circle:
          drawingObjectType = DrawingObjectType.circle;

          break;
        default:
          drawingObjectType = DrawingObjectType.polyline;
      }
      provData.updateUI();
    },
    child: TapImageIcon(
      imagePath: getIconAsPerSelectedObjectType(),
      // IconsImagesPaths.polyCurveicon,
      onTap: () {
        _drawingObjectTypeKey.currentState!.showButtonMenu();
      },
      height: topbarHeight,
      width: topbarHeight,
      padding: EdgeInsets.all(6),
      cornerRadius: 4,
    ),
  );
}

getIconAsPerSelectedObjectType() {
  switch (drawingObjectType) {
    case DrawingObjectType.circle:
      return IconsImagesPaths.circleicon;

  
    case DrawingObjectType.polygon:
      return IconsImagesPaths.polygonicon;
    case DrawingObjectType.polyline:
      return IconsImagesPaths.polyCurveicon;
    case DrawingObjectType.rectangle:
      return IconsImagesPaths.recticon;
    case DrawingObjectType.triangle:
      return IconsImagesPaths.trianlgeicon;

    default:return IconsImagesPaths.polyCurveicon;
  }
}

class _TopBarState extends State<TopBar> {
  @override
  Widget build(BuildContext context) {
    ProvData provData = Provider.of<ProvData>(context, listen: false);
    return InkWell(
      onTap: () {
        // setState(() {});
      },
      child: Container(
        width: double.infinity,
        height: topbarHeight,
        color: Color.fromARGB(255, 235, 177, 173),
        child: Row(
          children: [
            TapIcon(
              onTap: () {
                if (shapePanORModify == ShapePanORModify.modify) {
                  shapePanORModify = ShapePanORModify.pan;
                } else {
                  shapePanORModify = ShapePanORModify.modify;
                }
                provData.updateUI();
              },
              icon: Icon(shapePanORModify == ShapePanORModify.modify
                  ? Icons.handshake
                  : Icons.pan_tool),
            ),
            button(provData),
            drawingObjectbutton(provData),
            IconButton(onPressed: () {}, icon: Icon(Icons.abc)),

            IconButton(onPressed: () {}, icon: Icon(Icons.abc)),
            // Text(componentSelectedTypeInTree.name),
            Container(
              height: topbarHeight,
              width: 60.sw(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...(projectList[currentProjectNo]
                      .iconSections[currentIconSectionNo]
                      .frames[currentFrameNo]
                      .singleFrameModel
                      .cornerBoxPoints
                      .map((Point e) {
                    return
                        // Text("data");
                        Text(
                            "[ ${e.x.toStringAsFixed(2)} / ${e.y.toStringAsFixed(2)} ]");
                  }).toList())
                ],
              ),
            ),  Text(drawingObjectType.toString()),
            Spacer(),
            RawChip(
              onPressed: () {
                toggleShowAnimationBoard();
                provData.updateUI();
              },
              label: Text("Animation Board"),
              // onDeleted: (){ toggleShowAnimationBoard();
              //         provData.updateUI();},
              avatar: Container(
                margin: EdgeInsets.only(right: 2),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, right: 2),
                  child: TapIcon(
                      onTap: () {
                        toggleShowAnimationBoard();
                        provData.updateUI();
                      },
                      icon: Icon(
                        showAnimationBoard == ShowAnimationBoard.show
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 20,
                      )),
                ),
              ),
            ),
            TapIcon(
              icon: Icon(Icons.save),
              onTap: () {
                updateAllProjects();
              },
            )
          ],
        ),
      ),
    );
  }
}
