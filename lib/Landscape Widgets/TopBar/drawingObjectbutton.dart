import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/TopBar/getIconAsPerSelectedObjectType.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/top_bar.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_iconsection.dart';
import 'package:animated_icon_demo/enums/enums.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_image_icon.dart';
import 'package:flutter/material.dart';
Map<String, DrawingObjectType> drawingObjectTypesPopupMap = {
  IconsImagesPaths.polyCurveicon: DrawingObjectType.polyline,
  IconsImagesPaths.trianlgeicon: DrawingObjectType.triangle,
  IconsImagesPaths.recticon: DrawingObjectType.rectangle,
  IconsImagesPaths.polygonicon: DrawingObjectType.polygon,
  // IconsImagesPaths.circleicon: DrawingObjectType.circle,
};
Map<String, String> drawingObjectTypesNamesPopupMap = {
  IconsImagesPaths.polyCurveicon: "polyline",
  IconsImagesPaths.trianlgeicon: "triangle",
  IconsImagesPaths.recticon: "rectangle",
  IconsImagesPaths.polygonicon: "polygon",
  // IconsImagesPaths.circleicon: "circle",
};
drawingObjectbutton(ProvData provData,GlobalKey<PopupMenuButtonState> _drawingObjectTypeKey ) {
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
