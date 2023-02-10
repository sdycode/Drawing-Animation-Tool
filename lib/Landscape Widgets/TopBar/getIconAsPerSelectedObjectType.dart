import 'package:animated_icon_demo/Images/icons_paths.dart';
import 'package:animated_icon_demo/enums/enums.dart';

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

    default:
      return IconsImagesPaths.polyCurveicon;
  }
}