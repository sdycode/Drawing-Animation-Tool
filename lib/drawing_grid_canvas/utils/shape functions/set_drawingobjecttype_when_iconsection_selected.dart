import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/enums/enums.dart';

void set_drawingobjecttype_when_iconsection_selected() {
  String drawobj = projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .drawingObjectType;

  switch (drawobj) {
    case "circle":
      drawingObjectType = DrawingObjectType.circle;
      break;
    case "rectangle":
      drawingObjectType = DrawingObjectType.rectangle;

      break;
    case "triangle":
      drawingObjectType = DrawingObjectType.triangle;
      break;
    case "polygon":
      drawingObjectType = DrawingObjectType.polygon;
      break;
    default:
      drawingObjectType = DrawingObjectType.polyline;
  }
}
