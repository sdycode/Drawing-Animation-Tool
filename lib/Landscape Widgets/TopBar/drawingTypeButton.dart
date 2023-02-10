import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/top_bar.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_iconsection.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:flutter/material.dart';
drawingTypeButton(ProvData provData, GlobalKey<PopupMenuButtonState>_menuKey ) {
  return PopupMenuButton(
    key: _menuKey,
    tooltip: "Drawing Type",
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
      imagePath: IconsImagesPaths.closeShapeicon,
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