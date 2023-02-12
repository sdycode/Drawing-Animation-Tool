import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getActualStickserPositionFromPercentValue.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:animated_icon_demo/widgets/error/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HorizontalTimeLinesOfAllIconsections extends StatefulWidget {
  HorizontalTimeLinesOfAllIconsections({Key? key}) : super(key: key);

  @override
  State<HorizontalTimeLinesOfAllIconsections> createState() =>
      _HorizontalTimeLinesOfAllIconsectionsState();
}

class _HorizontalTimeLinesOfAllIconsectionsState
    extends State<HorizontalTimeLinesOfAllIconsections> {
  // ScrollController horizontalTimeLinesOfAllIconsectionsScrollController =
  //     ScrollController(
  //         initialScrollOffset: iconsectionsTreeinAnimSheetScrollPosition);
  Color bgColor = const Color.fromARGB(255, 41, 39, 39);
  double extraRightSpaceForScrollbar = 20;
  @override
  Widget build(BuildContext context) {
    ProvData provider = Provider.of<ProvData>(context);
    AnimSheetProvider animSheetProvider =
        Provider.of<AnimSheetProvider>(context);
    // for (var i = 0; i < projectList[currentProjectNo]
    //                 .iconSections.length; i++) {
    //   showDialog(
    //               context: context,
    //               builder: (context) {
    //                 return Dialog(
    //                   child: Column(children: [
    //                     IconButton(onPressed: (){
    //                       Navigator.maybePop(context);
    //                     }, icon: Icon(Icons.close)),
    //                     Text("For icon $i : ${ projectList[currentProjectNo]
    //                 .iconSections[i %
    //                     projectList[currentProjectNo].iconSections.length]
    //                 .frames.length}")
    //                   ]),
    //                 );
    //               });
    // }

    debugLog(
        "HorizontalTimeLinesOfAllIconsections animSheetProvider called ${iconsectionsTreeinAnimSheetScrollPosition}");

    // horizontalTimeLinesOfAllIconsectionsScrollController =
    // ScrollController(
    //     initialScrollOffset: iconsectionsTreeinAnimSheetScrollPosition);
    log("factot ${animSheetMainBoxWidthFactor.sw(context) * (1 - 0.051)} and ${39 / animSheetMainBoxWidthFactor.sw(context)}");

    return Container(
        // color: Colors.green,
        width: (animSheetMainBoxWidthFactor.sw(context) * (1 - 0.051) +
                extraRightSpaceForScrollbar)
            .abs(),
        height: (100.sh(context) -
                topbarHeight -
                animSheetProvider.animationSheetFromTop +
                35 +
                10 -
                //  animSheetHeightFactor.sh(context) -
                animaBarH -
                1.sh(context) -
                timelineBarH.sw(context))
            .abs(),
        child: Column(
          children: [
            listOfTimeLinePointsBar(provider),
          ],
        )

        // Expanded(
        //   child: NotificationListener<ScrollNotification>(
        //     onNotification: (ScrollNotification scrollInfo) {
        //       syncScroller.processNotification(scrollInfo, secondScroller);
        //       return true;
        //     },
        //     child: RawScrollbar(
        //       thickness: 2,
        //       radius: Radius.circular(1),
        //       thumbVisibility: false,
        //       trackVisibility: false,
        //       interactive: false,
        //       // isAlwaysShown: false,
        //       child:
        //     ),
        //   ),
        // )
        );
  }

  Widget listOfTimeLinePointsBar(ProvData provider) {
    double horzWidth = (animSheetMainBoxWidthFactor.sw(context) * (1 - 0.051) -
            0.5.sw(context) -
            timelineBarH.sw(context) * 0.5)
        .abs();
    return Expanded(
      child: ListView.builder(
        // controller: secondScroller,
        itemCount: projectList[currentProjectNo].iconSections.length,
        itemBuilder: (c, i) {
          return Container(
              width:
                  (animSheetMainBoxWidthFactor.sw(context) * (1 - 0.051)).abs(),
              height: iconSectionBarHeightInAnimationSheet.abs(),
              color: 
              // Colors.primaries[i + 6],
              bgColor,
              child: Stack(children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: horzWidth + 10,
                    height: 0.5,
                    color: Colors.white54,
                  ),
                ),
                // Positioned(
                //     child: Text(
                //         " frames in $i : ${projectList[currentProjectNo].iconSections[i % projectList[currentProjectNo].iconSections.length].frames.length}")),
                ...List.generate(
                    projectList[currentProjectNo]
                        .iconSections[i %
                            projectList[currentProjectNo].iconSections.length]
                        .frames
                        .length, (fi) {
                  try {
                    if (projectList[currentProjectNo]
                            .iconSections[i %
                                projectList[currentProjectNo]
                                    .iconSections
                                    .length]
                            .frames
                            .length >
                        1) {
                      log("frame pos changing ");
                      projectList[currentProjectNo]
                          .iconSections[i %
                              projectList[currentProjectNo].iconSections.length]
                          .frames
                          .first
                          .singleFrameModel
                          .framePosition = 0;
                      projectList[currentProjectNo]
                          .iconSections[i]
                          .frames
                          .last
                          .singleFrameModel
                          .framePosition = 100;
                    }
                  } catch (e) {
                    showErrorDialog(context, "frame for polygon $e");
                    log("frame for polygon $e");
                  }

                  double tempPosition = 0;
                  try {
                    Frame frame = projectList[currentProjectNo]
                            .iconSections[
                                i %
                                    projectList[currentProjectNo]
                                        .iconSections
                                        .length]
                            .frames[
                        fi %
                            projectList[currentProjectNo]
                                .iconSections[i %
                                    projectList[currentProjectNo]
                                        .iconSections
                                        .length]
                                .frames
                                .length];

                    tempPosition = getActualStickserPositionFromPercentValue(
                        frame.singleFrameModel.framePosition, context);
                    log("frame pos in try $i : $fi ${frame.singleFrameModel.framePosition.toStringAsFixed(2)} and ${tempPosition.toStringAsFixed(2)}");
                  } catch (e) {
                    showErrorDialog(context, "frame $e");
                  }

                  log("frame pos      $i : $fi ${projectList[currentProjectNo].iconSections[i].frames[fi].singleFrameModel.framePosition.toStringAsFixed(2)} and ${tempPosition.toStringAsFixed(2)}");
                  return Positioned(
                    left: tempPosition+4,
                    top: 12,
                    child: InkWell(
                        onTap: () {
                          currentFrameNo = fi;
                          currentIconSectionNo = i;
                          setTimeLinePointerXPositionForSelectedFrame(
                              projectList[currentProjectNo]
                                  .iconSections[i]
                                  .frames[fi]);
                          provider.updateUI();
                        },
                        child: 
                        // Text(projectList[currentProjectNo]
                        //     .iconSections[i]
                        //     .frames[fi]
                        //     .singleFrameModel
                        //     .framePosition
                        //     .toString())
                        CircleAvatar(radius: 4,
                        backgroundColor: Colors.white,
                        )
                        ),
                  );

                  // if (projectList[currentProjectNo]
                  //         .iconSections[i %
                  //             projectList[currentProjectNo].iconSections.length]
                  //         .frames
                  //         .length >
                  //     1) {
                  //   projectList[currentProjectNo]
                  //       .iconSections[i %
                  //           projectList[currentProjectNo].iconSections.length]
                  //       .frames[0]
                  //       .singleFrameModel
                  //       .framePosition = 0;
                  //   projectList[currentProjectNo]
                  //       .iconSections[i]
                  //       .frames
                  //       .last
                  //       .singleFrameModel
                  //       .framePosition = 100;
                  // }

                  // Frame frame = projectList[currentProjectNo]
                  //         .iconSections[i %
                  //             projectList[currentProjectNo].iconSections.length]
                  //         .frames[
                  //     fi %
                  //         projectList[currentProjectNo]
                  //             .iconSections[i %
                  //                 projectList[currentProjectNo]
                  //                     .iconSections
                  //                     .length]
                  //             .frames
                  //             .length];

                  // double tempPosition =
                  //     getActualStickserPositionFromPercentValue(
                  //         frame.singleFrameModel.framePosition, context);
                  // debugLog(
                  //     "frames in $i : ${projectList[currentProjectNo].iconSections[i].frames.length} : $fi : ${frame.singleFrameModel.framePosition} : $tempPosition ");

                  return Positioned(
                      left: i * 50,
                      //  (tempPosition - 3 + timelineBarH.sw(context) * 0.5)
                      // .abs(),
                      top: 2,
                      child: Container(
                        height: 30,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: InkWell(
                                onTap: () {
                                  currentFrameNo = fi;
                                  currentIconSectionNo = i;
                                  setTimeLinePointerXPositionForSelectedFrame(
                                      projectList[currentProjectNo]
                                          .iconSections[i]
                                          .frames[fi]);
                                  provider.updateUI();
                                },
                                child: const CircleAvatar(
                                  radius: 3,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ));
                })
              ]));
        },
      ),
    );
  }

  void setTimeLinePointerXPositionForSelectedFrame(Frame frame) {
    timeLinePointerXPosition = getActualStickserPositionFromPercentValue(
        frame.singleFrameModel.framePosition, context);
  }
}
