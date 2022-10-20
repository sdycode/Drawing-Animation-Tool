import 'package:animated_icon_demo/controllers/text_controllers/text_controllers.dart';
import 'package:flutter/material.dart';

bool isComponent() {
  return componentSelectedTypeInTree ==
      ComponentSelectedTypeInTree.drawingObject;
}

bool isPanShape() {
  return shapePanORModify == ShapePanORModify.pan;
}

enum ComponentSelectedTypeInTree { drawingBoard, drawingObject }

enum ShapePanORModify { modify, pan }

ShapePanORModify shapePanORModify = ShapePanORModify.modify;
ComponentSelectedTypeInTree componentSelectedTypeInTree =
    ComponentSelectedTypeInTree.drawingBoard;

enum DrawingType {
  points,
  linepaths,
  pointsAndLines,
  curvePaths,
  closedCustomPath
}

DrawingType drawingType = DrawingType.points;

int drawingtypindex = 0;

enum DrawingObjectType { polyline, triangle, rectangle, polygon, circle }

DrawingObjectType drawingObjectType = DrawingObjectType.polyline;

enum PointType { endPoint, middlePoint }

enum MidpointStatus { selectEndPoints, AddMiddlePoint }

enum ShowOuterBox { show, hide }

ShowOuterBox showOuterBox = ShowOuterBox.show;

enum EditShapeVertices { shapeVerices, boxVertices }

EditShapeVertices editShapeVertices = EditShapeVertices.shapeVerices;

enum ShowAnimationBoard { show, hide }

ShowAnimationBoard showAnimationBoard = ShowAnimationBoard.hide;
// enum WhichTextField {
//   drawingBoard_Pos_X,
//   drawingBoard_Pos_Y,
// }

// Map<TextEditingController, WhichTextField> textControlletToTextFieldEnum = {
//   drawingaBoard_X_posController: WhichTextField.drawingBoard_Pos_X,
//   drawingaBoard_Y_posController: WhichTextField.drawingBoard_Pos_Y,
// };
// WhichTextField whichTextField = WhichTextField.drawingBoard_Pos_X;
