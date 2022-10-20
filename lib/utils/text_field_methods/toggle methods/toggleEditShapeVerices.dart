import 'package:animated_icon_demo/enums/enums.dart';

void toggleEditShapeVerices() {
  if (editShapeVertices == EditShapeVertices.boxVertices) {
     editShapeVertices = EditShapeVertices.shapeVerices;
  } else {
    editShapeVertices = EditShapeVertices.boxVertices;
  }
}
