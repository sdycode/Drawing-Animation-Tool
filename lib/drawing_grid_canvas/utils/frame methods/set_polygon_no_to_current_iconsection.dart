import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/get_box_corner_points_for_numerousPoints.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/geometric%20functions/get_startpoint_for_polygon_withcenter_side_and_no.dart';

set_polygon_no_to_current_iconsection() {
  if (projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .drawingObjectType ==
      'polygon') {
    for (var i = 0;
        i <
            projectList[currentProjectNo]
                .iconSections[currentIconSectionNo]
                .frames
                .length;
        i++) {
      Box box = getBoxForPoints(projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[i]
          .singleFrameModel
          .cornerBoxPoints);
      double h2wFactor = box.height / box.width;

      tempShapeEndPoints = getNthPointFromInitialAngleWithStepAngle(
        box.width * 0.5,
        box.center,
        box.width,
        box.height,
        noOfSidesOfPolygon,
      );
      projectList[currentProjectNo]
          .iconSections[currentIconSectionNo]
          .frames[i]
          .singleFrameModel
          .points = List.from(tempShapeEndPoints);
    }
  }
}
