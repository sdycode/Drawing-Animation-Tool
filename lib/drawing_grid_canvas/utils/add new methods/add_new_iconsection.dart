import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/set_drawingobjecttype_when_iconsection_selected.dart';

void addNewIconSection() {
  currentIconSectionNo++;
  // framesList.add(
  //     [Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0))]);
  // currentIconSectionsList[currentIconSectionNo]
  //     .frames
  //     .add(Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0)));
  projectList[currentProjectNo].iconSections.add(IconSection(
          iconSectionNo: projectList[currentProjectNo].iconSections.length,
          iconSectionName:
              "Polyline_${projectList[currentProjectNo].iconSections.length}",
          position: Point.zero,
          frames: [
            Frame(
              frameNo: 0,
              singleFrameModel:
                  SingleFrameModel(frameNo: 0, framePosition: 0.0),
            ),
            Frame(
                frameNo: 1,
                singleFrameModel:
                    SingleFrameModel(frameNo: 1, framePosition: 100.0)),
          ]));
  set_drawingobjecttype_when_iconsection_selected();
}

void addNewIconSectionAsRectangle() {
  String drawingObjType = "rectangle";
  currentIconSectionNo++;
  List<Point> points = List.generate(4, (index) => Point.zero);

  projectList[currentProjectNo].iconSections.add(IconSection(
          iconSectionNo: projectList[currentProjectNo].iconSections.length,
          iconSectionName:
              "${drawingObjType}_${projectList[currentProjectNo].iconSections.length}",
          position: Point.zero,
          drawingObjectType: drawingObjType,
          frames: [
            Frame(
              frameNo: 0,
              singleFrameModel: SingleFrameModel(
                  frameNo: 0, framePosition: 0.0, points: points),
            ),
            Frame(
                frameNo: 1,
                singleFrameModel: SingleFrameModel(
                    frameNo: 1, framePosition: 100.0, points:List.from(points) )),
          ]));
  set_drawingobjecttype_when_iconsection_selected();
}

void addNewIconSectionPolygon(int i) {
  if (i < 3) {
    return;
  }
  String drawingObjType = "rectangle";
  switch (i) {
    case 3:
      drawingObjType = "triangle";
      break;
    case 4:
      drawingObjType = "rectangle";
      break;

    default:
      drawingObjType = "polygon";
  }

  currentIconSectionNo++;
  List<Point> points = List.generate(i, (index) => Point.zero);

  projectList[currentProjectNo].iconSections.add(IconSection(
          iconSectionNo: projectList[currentProjectNo].iconSections.length,
          iconSectionName:
              "${drawingObjType}_${projectList[currentProjectNo].iconSections.length}",
          position: Point.zero,
          drawingObjectType: drawingObjType,
          frames: [
            Frame(
              frameNo: 0,
              singleFrameModel: SingleFrameModel(
                  frameNo: 0, framePosition: 0.0, points: points),
            ),
            Frame(
                frameNo: 1,
                singleFrameModel: SingleFrameModel(
                    frameNo: 1, framePosition: 100.0, points:List.from(points))),
          ]));
  set_drawingobjecttype_when_iconsection_selected();
}
