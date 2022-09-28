import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/hover_paint.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/converted_songle_frame_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add_new_frame.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add_new_iconsection.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/check_if_hoverpoint_inside_boundarybox.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/check_is_there_any_project_or_not.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/create_new_empty_project_with_next_id_name.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/create_single_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_current_project_instance.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_interpolated_point.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/load_project_to_current.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/pan_update.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/points_to_offsets.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/set_points_for_2_frames_for_animation.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/updateProject.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/update_all_projects.dart';
import 'package:animated_icon_demo/screens/username_page.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:animated_icon_demo/widgets/animated_paint.dart';
import 'package:animated_icon_demo/widgets/control_point_widget.dart';
import 'package:animated_icon_demo/widgets/point_box.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/widgets/temp_paint.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'models/pair_model.dart';
import 'polyline_paint.dart';
import 'utils/add_control_point.dart';
import 'utils/check_this_point_is_inside_given_point_box.dart';
import 'utils/getIndexForHoveredPointFromListofAddedPoints.dart';
import 'utils/get_lower_value_from_pair.dart';
import 'utils/on_tap_up.dart';

enum DrawingType {
  points,
  linepaths,
  pointsAndLines,
  curvePaths,
  closedCustomPath
}

enum PointType { endPoint, middlePoint }

enum MidpointStatus { selectEndPoints, AddMiddlePoint }

Map<int, int> pointRoundedValuesofX = {};
Map<int, int> pointRoundedValuesofY = {};
int indexForHoveredPoint = 0;
PointType pointType = PointType.endPoint;
MidpointStatus midpointStatus = MidpointStatus.selectEndPoints;
List<String> drawingTypeNames = [
  'points',
  'linepaths',
  'pointsAndLines',
  'curvePaths',
  'closedCustomPath'
];
DrawingType drawingType = DrawingType.points;
int drawingtypindex = 0;

class DrawGridCanvase extends StatefulWidget {
  DrawGridCanvase({Key? key}) : super(key: key);

  @override
  State<DrawGridCanvase> createState() => _DrawGridCanvaseState();
}

void clearAll() {
  resetControlPointAdjecntPair();
  projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .points
      .clear();

  controlMidPoints.clear();
}

void resetControlPointAdjecntPair() {
  controlPointAdjecntPair = Pair(0, 1);
}

class _DrawGridCanvaseState extends State<DrawGridCanvase>
    with TickerProviderStateMixin {
  late AnimationController animationController;

  ScrollController iconSectionScrollController = ScrollController();
  ScrollController framesScrollController = ScrollController();
  ScrollController pointsScrollController = ScrollController();
  ScrollController projectsListScrollController = ScrollController();
  List<Offset> points = pointsToOffsets(projectList[currentProjectNo]
      .iconSections[currentIconSectionNo]
      .frames[currentFrameNo]
      .singleFrameModel
      .points);
  StateSetter hoverState = (d) {};
  StateSetter pointsLinePaintState = (d) {};
  String currntString = 'nodata';
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    animationController = AnimationController(
        vsync: this, duration: Duration(milliseconds: 3000));
    // .animateTo(1.0, duration: Duration(seconds: 3));
  }

  @override
  Widget build(BuildContext context) {
    if (selectedPointIndex >=
        projectList[currentProjectNo]
            .iconSections[currentIconSectionNo]
            .frames[currentFrameNo]
            .singleFrameModel
            .points
            .length) {
      selectedPointIndex = projectList[currentProjectNo]
              .iconSections[currentIconSectionNo]
              .frames[currentFrameNo]
              .singleFrameModel
              .points
              .length -
          1;
    }
    if (selectedPointIndex < 0) {
      selectedPointIndex = 0;
    }
    biggerSize = Size(40.sh(context), 40.sh(context));
    // reInitSingleModel();

    // log(" paintsize  /  /$currentIconSectionNo / $currentFrameNo /${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points.length}");
    return Scaffold(
        body:

            // FutureBuilder(

            //   builder: (context, snapshot) {

            // },
            SingleChildScrollView(
      child: Column(
        children: [
          Text(
            Shared.getUserName(),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          Container(
            width: biggerSize.width.truncate().toDouble(),
            height: biggerSize.height.truncate().toDouble(),
            color: Colors.purple.shade100.withAlpha(60),
            child: MouseRegion(
              cursor: SystemMouseCursors.help,
              onHover: (event) {
                hoverPoint = event.position;
                // hoverState(() {
                //   hoverPoint = event.position;
                // },);
                hoverState(
                  () {},
                );
              },
              child: GestureDetector(
                onTapUp: (d) {
                  on_tap_up(d);
                  selectedPointIndex = projectList[currentProjectNo]
                          .iconSections[currentIconSectionNo]
                          .frames[currentFrameNo]
                          .singleFrameModel
                          .points
                          .length -
                      1;
                  setState(() {});
                },
                onPanStart: (d) {
                  panPointIndex = getIndexForHoveredPointFromListofAddedPoints(
                      d.localPosition);
                  log("panPointIndex onPanStart ${d.localPosition}");
                },
                onPanUpdate: (d) {
                  log("panPointIndex before ${d.localPosition}");
                  pan_Update(d);

                  setState(() {});
                },
                onPanEnd: (d) {
                  panPointIndex = -1;
                },
                child: Stack(children: [
                  projectList[currentProjectNo]
                          .iconSections[currentIconSectionNo]
                          .frames[currentFrameNo]
                          .singleFrameModel
                          .points
                          .isNotEmpty
                      ? Positioned(
                          left:
                              // (100.sw(context) -
                              //             biggerSize.width.truncate().toDouble()) *
                              //         0.5 -
                              //     5 +
                              projectList[currentProjectNo]
                                      .iconSections[currentIconSectionNo]
                                      .frames[currentFrameNo]
                                      .singleFrameModel
                                      .points[selectedPointIndex]
                                      .x -
                                  5,
                          top: projectList[currentProjectNo]
                                  .iconSections[currentIconSectionNo]
                                  .frames[currentFrameNo]
                                  .singleFrameModel
                                  .points[selectedPointIndex]
                                  .y -
                              5,
                          child: BoxPoint(
                            isHovered: true,
                            // isPointHoverPointisInsideBoundryBox(e),
                            isSelected: false,
                            // (pIndex == controlPointAdjecntPair.preIndex) ||
                            //     (pIndex == controlPointAdjecntPair.nextIndex),
                            child: Container(),
                          ))
                      : Container(),
                  StatefulBuilder(builder: (BuildContext context,
                      StateSetter _pointsLinePaintState) {
                    pointsLinePaintState = _pointsLinePaintState;

                    return CustomPaint(
                      size: Size(
                        biggerSize.width.truncate().toDouble(),
                        biggerSize.height.truncate().toDouble(),
                      ),
                      painter: PointsLinePaint(pointsToOffsets(
                          projectList[currentProjectNo]
                              .iconSections[currentIconSectionNo]
                              .frames[currentFrameNo]
                              .singleFrameModel
                              .points
                          // currentIconSectionsList[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points
                          )),
                    );
                  }),
                  StatefulBuilder(
                      builder: (BuildContext context, StateSetter _hoverState) {
                    // log(" paintsize in _hoverState  build buld ${100.sw(context).truncate().toDouble()}, //  ${70.sh(context).truncate().toDouble()}");

                    hoverState = _hoverState;
                    return CustomPaint(
                      size: Size(
                        biggerSize.width.truncate().toDouble(),
                        biggerSize.height.truncate().toDouble(),
                      ),
                      painter: HoverPaint(),
                    );
                  }),

                  // ...(List.generate(points.length, (pIndex) {
                  //   Offset e = points[pIndex];
                  //   return Positioned(
                  //       left: e.dx - 5,
                  //       top: e.dy - 5,
                  //       child: BoxPoint(
                  //         isHovered: isPointHoverPointisInsideBoundryBox(e),
                  //         isSelected:
                  //             (pIndex == controlPointAdjecntPair.preIndex) ||
                  //                 (pIndex == controlPointAdjecntPair.nextIndex),
                  //         child: Container(),
                  //       ));
                  // })),
                  if (controlMidPoints.isNotEmpty)
                    ControlBoxPoint(
                        controlMidPoints[controlPointAdjecntPair.preIndex] ??
                            const Offset(-50, -50))
                ]),
              ),
            ),
          ),
          TextButton(
              onPressed: () {
                setState(() {
                  showAnimationPanel = !showAnimationPanel;
                  framePointsSetForAnimation = false;
                });
              },
              child: Text(showAnimationPanel
                  ? "Show Aimation Panel"
                  : "Hide Aimation Panel")),
          if (!showAnimationPanel)
            TextButton(
              child: Text("Run Animation",
                  style: TextStyle(
                      color: framePointsSetForAnimation == true
                          ? Colors.purple
                          : Colors.red)),
              onPressed: () {
                setPointsFor2FramesForAnimation();
                animationController.reset();
                animationController.forward();
                setState(() {});
              },
            ),
          if (!showAnimationPanel && animatingFramePoints.length > 1)
            StatefulBuilder(
                builder: (BuildContext context, StateSetter animState) {
              animationController.addListener(() {
                for (var i = 0; i < animatingFramePoints.length; i++) {
                  Point interPoint = getInterPolatedPoint(
                      animationController.value,
                      frame1Points[i],
                      frame2Points[i]);
                  animatingFramePoints[i] = interPoint;
                }
                if (mounted) {
                  setState(() {
                    
                  });
                //      animState(
                //   () {
                //     // log("interpoint @ ${animationController.value} : ${interPoint} ");
                //   },
                // );
                }
             
              });
              return Container(
                width: biggerSize.width,
                height: biggerSize.height,
                color: Colors.green.shade100,
                child: Stack(children: [
                           ...(List.generate(animatingFramePoints.length, (int i) {
                    return Positioned(
                        left: animatingFramePoints[i].x,
                        top: animatingFramePoints[i].y,
                        child: Container(
                          width: 5,
                          height: 5,
                          color: Colors.pink,
                        ));
                  })),
                  AnimatedMyPaint(
                    width: biggerSize.width,
                    height: biggerSize.height,
                    animPoints: pointsToOffsets(animatingFramePoints),
                  ),
                  // ...(List.generate(animatingFramePoints.length, (int i) {
                  //   return Positioned(
                  //       left: animatingFramePoints[i].x,
                  //       top: animatingFramePoints[i].y,
                  //       child: Container(
                  //         width: 5,
                  //         height: 5,
                  //         color: Colors.pink,
                  //       ));
                  // }))
                ]),
              );
            }),
          if (showAnimationPanel)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ...(List.from(drawingTypeNames).map((e) {
                  int i = drawingTypeNames.indexOf(e);
                  return InkWell(
                      onTap: () {
                        setState(() {
                          drawingType = DrawingType.values[i];
                          drawingtypindex = i;
                        });
                      },
                      child: Container(
                          color: i == drawingtypindex
                              ? Colors.pink.shade200
                              : null,
                          child: Text(e)));
                }))
              ],
            ),
          const SizedBox(
            height: 10,
          ),

          if (showAnimationPanel)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                InkWell(
                  onTap: () {
                    pointType = PointType.endPoint;
                    setState(() {});
                  },
                  child: Container(
                      color: pointType == PointType.endPoint
                          ? Colors.pink.shade200
                          : null,
                      child: Text("EndPoint")),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      clearAll();
                    });
                  },
                  child: Text("Clear"),
                ),
                InkWell(
                  onTap: () {
                    pointType = PointType.middlePoint;
                    setState(() {});
                  },
                  child: Container(
                      color: pointType == PointType.middlePoint
                          ? Colors.pink.shade200
                          : null,
                      child: Text("MidPoint")),
                ),
              ],
            ),
          if (showAnimationPanel)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                InkWell(
                  onTap: () async {
                    await loadAllProjectsFromServer();
                    setState(() {});
                  },
                  child: Text("Load all projects"),
                ),
                InkWell(
                    onTap: () async {
                      updateAllProjects();
                      // updateProjectData();
                    },
                    child: Text("save data")),
                const SizedBox(
                  height: 10,
                ),
              ],
            ),
          Divider(),
          if (showAnimationPanel)
            Container(
              height: 40,
              width: double.infinity,
              child: Scrollbar(
                controller: pointsScrollController,
                child: ListView.builder(
                    itemCount: projectList[currentProjectNo]
                        .iconSections[currentIconSectionNo]
                        .frames[currentFrameNo]
                        .singleFrameModel
                        .points
                        .length,
                    controller: pointsScrollController,
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (c, i) {
                      return Padding(
                        padding: EdgeInsets.all(4),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              selectedPointIndex = i;
                            });
                          },
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: i == selectedPointIndex
                                ? Colors.deepOrange
                                : Colors.orange,
                            child: Text(
                              i.toString(),
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      );
                    }),
              ),
            ),
          if (showAnimationPanel)
            TextButton.icon(
                onPressed: () {
                  projectList[currentProjectNo]
                      .iconSections[currentIconSectionNo]
                      .frames[currentFrameNo]
                      .singleFrameModel
                      .points
                      .removeAt(selectedPointIndex);
                  setState(() {});
                },
                icon: Icon(
                  Icons.delete,
                  color: Colors.red,
                ),
                label: Text(
                  "Delete Point",
                  style: TextStyle(
                    color: Colors.red,
                  ),
                )),
          Divider(),
          if (showAnimationPanel) Text("Projects"),
          if (showAnimationPanel)
            Container(
                height: 30 + 20,
                width: double.infinity,
                child: Row(
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: projectsListScrollController,
                        child: ListView.builder(
                            controller: projectsListScrollController,
                            itemCount: projectList.length,
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (c, i) {
                              return InkWell(
                                onTap: () async {
                                  oldProjectNo = currentProjectNo;
                                  currentProjectNo = i;

                                  await loadDataOfSelectedProject();
                                  setState(() {});
                                },
                                child: i == 0
                                    ? Container()
                                    : Container(
                                        margin: EdgeInsets.all(10),
                                        height: 40,
                                        decoration: BoxDecoration(
                                          border: i == currentProjectNo
                                              ? Border.all()
                                              : null,
                                          color: Colors.pink.shade100
                                              .withAlpha(150),
                                        ),
                                        child: Text("Project $i"),
                                      ),
                              );
                            }),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await addNewProjectToListAndFirebase();
                        oldProjectNo = currentProjectNo;
                        currentProjectNo = projectList.length - 1;
                        loadDataOfSelectedProject();
                        setState(() {});
                      },
                      icon: Icon(Icons.add),
                    )
                  ],
                )),
          if (showAnimationPanel) Text("Icon Secations"),
          if (showAnimationPanel)
            Container(
                height: 30 + 20,
                width: double.infinity,
                child: Row(
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: iconSectionScrollController,
                        child: ListView.builder(
                            controller: iconSectionScrollController,
                            itemCount: projectList[currentProjectNo]
                                .iconSections
                                .length,
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (c, i) {
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    reInitiliaseFramePoints();
                                    currentIconSectionNo = i;
                                    currentFrameNo = 0;
                                  });
                                },
                                child: Container(
                                  margin: EdgeInsets.all(10),
                                  height: 40,
                                  decoration: BoxDecoration(
                                    border: i == currentIconSectionNo
                                        ? Border.all()
                                        : null,
                                    color: Colors.pink.shade100.withAlpha(150),
                                  ),
                                  child: Text("IconSection $i"),
                                ),
                              );
                            }),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        currentFrameNo = 0;
                        addNewIconSection();
                        setState(() {});
                      },
                      icon: Icon(Icons.add),
                    )
                  ],
                )),
          //  projectList[currentProjectNo].iconSections[currentIconSectionNo]
          if (showAnimationPanel || true) Text("Frames"),
          if (showAnimationPanel || true)
            Container(
                height: 150 + 20,
                child: Row(
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: framesScrollController,
                        child: ListView.builder(
                            controller: framesScrollController,
                            itemCount: projectList[currentProjectNo]
                                .iconSections[currentIconSectionNo]
                                .frames
                                .length,
                            //  framesList[currentIconSectionNo].length,
                            scrollDirection: Axis.horizontal,
                            itemBuilder: (c, i) {
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    currentFrameNo = i;
                                  });

                                  // reInitiliaseFramePoints(); clearAll();
                                },
                                child: Container(
                                    margin: EdgeInsets.all(10),
                                    height: 150,
                                    width: 150,
                                    decoration: BoxDecoration(
                                      border: i == currentFrameNo
                                          ? Border.all()
                                          : null,
                                      color:
                                          Colors.amber.shade100.withAlpha(150),
                                    ),
                                    child: Stack(
                                      children: [
                                        TempPaint(
                                            height: 300,
                                            width: 300,
                                            frame: projectList[currentProjectNo]
                                                .iconSections[
                                                    currentIconSectionNo]
                                                .frames[i]
                                            //  currentIconSectionsList[
                                            //         currentIconSectionNo]
                                            //     .frames[i]
                                            // framesList[currentIconSectionNo]
                                            //     [i]

                                            ),
                                        Align(
                                          alignment: Alignment.topCenter,
                                          child: Text(
                                              "${currentIconSectionNo}_${i} / ${projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points.length}"),
                                        )
                                      ],
                                    )

                                    //  Text(
                                    //   "Frame $i"
                                    // ),
                                    ),
                              );
                            }),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        addNewFrame();
                        setState(() {});
                      },
                      icon: Icon(Icons.add),
                    )
                  ],
                )),
        ],
      ),
    ));
  }

  Future loadDataOfSelectedProject() async {
    currentIconSectionNo = 0;
    currentFrameNo = 0;
    log("list before $currentProjectNo /  ${projectList[currentProjectNo].iconSections.length}");
    // projectList[currentProjectNo].iconSections = [
    //   IconSection(
    //       iconSectionNo: 0,
    //       iconSectionName: "iconSectionName_0",
    //       frames: [
    //         Frame(frameNo: 0, singleFrameModel: SingleFrameModel(frameNo: 0))
    //       ])
    // ];
    // await saveCurrentDataToCurrentProject();
    log("list after  $currentProjectNo / ${projectList[currentProjectNo].iconSections.length}");

    // currentIconSectionsList =
    //     List.from(projectList[currentProjectNo].iconSections);
    // List<IconSection> icons = List.from(currentIconSectionsList);
    // int sectno = 0;
  }

  Future saveCurrentDataToCurrentProject() async {
    int sectno = 0;
    List<IconSection> icons =
        List.from(projectList[currentProjectNo].iconSections);

    projectList[oldProjectNo].iconSections =
        List.from(projectList[currentProjectNo].iconSections);

    // projectList[currentProjectNo].iconSections.forEach((element) { })
  }
}




/*
  if (pointType == PointType.middlePoint)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () {
                  midpointStatus = MidpointStatus.selectEndPoints;
                  ;
                  setState(() {});
                },
                child: Container(
                    color: midpointStatus == MidpointStatus.selectEndPoints
                        ? Colors.pink.shade200
                        : null,
                    child: Text("Select EndPoints")),
              ),
              const SizedBox(
                width: 10,
              ),
              InkWell(
                onTap: () {
                  midpointStatus = MidpointStatus.AddMiddlePoint;
                  setState(() {});
                },
                child: Container(
                    color: midpointStatus == MidpointStatus.AddMiddlePoint
                        ? Colors.pink.shade200
                        : null,
                    child: Text("Add new MidPoint")),
              )
            ],
          )
    
*/