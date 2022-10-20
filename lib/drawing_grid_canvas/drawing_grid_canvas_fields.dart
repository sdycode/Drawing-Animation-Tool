import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/animate_points_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/cast_control_points.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:flutter/material.dart';

import 'models/pair_model.dart';

int noOfSidesOfPolygon = 5;
Point centerPoint = Point.zero;
double finalAngle = 0.0;
double oldAngle = 0.0;
double upsetAngle = 0.0;
Point startForRotate = Point.zero;
Point endForRotate = Point.zero;
double startDistanceForRotate = 0;
double newDistanceForRotate = 0;
double scale = 1.0;
double animTotalTime = 2000;
List<Point> tempShapeEndPoints = [];
bool firstTimeDraw = true;
const List<Color> myColors = [...(Colors.primaries)];
List<int> iconSectionNosIncludedInAnimation = [];
List<AnimatePointsModel> animatePointsModels = [];
List<Point> frame1Points = [];
List<Point> frame2Points = [];
List<Point> animatingFramePoints = [];
bool framePointsSetForAnimation = false;
bool framePointsForMultiSectionsAreSetForAnimation = false;
bool showAnimationPanel = true;
int selectedPointIndex = 0;
int currentProjectNo = 0;
int oldProjectNo = 0;
int currentIconSectionNo = 0;
int currentFrameListNo = 0;
int currentFrameNo = 0;
List<Project> projectList = [];
// List<IconSection> currentIconSectionsList = [currentIconSection];
IconSection currentIconSection = IconSection(
    iconSectionNo: currentIconSectionNo,
    iconSectionName: "Polyline_${currentIconSectionNo}",
    position: Point.zero,
    frames: [currentFrame]);
Frame currentFrame = Frame(
    frameNo: currentSingleFrameModel.frameNo,
    singleFrameModel: currentSingleFrameModel);
String currentProjectName = "AnimatedIconProject";
TextEditingController userNameController = TextEditingController();
Offset hoverPoint = Offset.zero;
Size biggerSize = Size(200, 200);
Pair controlPointAdjecntPair = Pair(0, 1);
Map<int, Offset> controlMidPoints = {};
// List<Offset> points = [];
int panPointIndex = -1;
bool close = false;
// Project level fields
SingleFrameModel currentSingleFrameModel = SingleFrameModel(frameNo: 0);
reInitiliaseFramePoints() {
  // points = pointsToOffsets(
  //     framesList[currentIconSectionNo][currentFrameNo].singleFrameModel.points);
}

reInitSingleModel() {
  currentSingleFrameModel.controlMidPoints =
      castControlPoints(controlMidPoints);
  currentSingleFrameModel.controlPointAdjecntPair =
      ControlPointAdjecntPair.fromPair(controlPointAdjecntPair);
  currentSingleFrameModel.frameNo = currentFrameNo;
  currentSingleFrameModel.hoverPoint = Point.fromOffset(hoverPoint);
  currentSingleFrameModel.panPointIndex = panPointIndex;
  // currentSingleFrameModel.points = points.map((Offset e) {
  //   return Point.fromOffset(e);
  // }).toList();
  currentFrame = Frame(
      frameNo: currentSingleFrameModel.frameNo,
      singleFrameModel: currentSingleFrameModel);
  // framesList[currentIconSectionNo][currentFrameNo].singleFrameModel.points =
  //  offsetsToPoints(   points);
}

// List<List<Frame>> framesList = [
//   [
//     Frame(
//         frameNo: currentSingleFrameModel.frameNo,
//         singleFrameModel: currentSingleFrameModel),
//   ]
// ];
Project currentProject = Project(
    projectId: "Project_$currentProjectNo",
    projectName: currentProjectName + '_' + "$currentProjectNo",
    width: defaultProjectWidth,
    height: defaultProjectHeight,
    iconSections: [
      IconSection(
          iconSectionNo: 0,
          iconSectionName: "Polyline_0",
          frames: projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames,
          position: Point(x: 0, y: 0)),

      //     iconSectionNo: 1,
      //     iconSectionName: "Polyline_1",
      //     frames: [
      //       Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0)),
      //       Frame(frameNo: 1, singleFrameModel: SingleFrameModel(frameNo: 1))
      //     ]),
      // IconSection(
      //     iconSectionNo: 2,
      //     iconSectionName: "Polyline_2",
      //     frames: [
      //       Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0)),
      //       Frame(frameNo: 1, singleFrameModel: SingleFrameModel(frameNo: 1))
      //     ]),
    ]);
