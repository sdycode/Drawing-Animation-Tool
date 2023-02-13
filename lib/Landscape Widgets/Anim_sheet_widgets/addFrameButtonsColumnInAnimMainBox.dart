import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_frame.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/insert_new_frame_at_position.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getPercentValueForStickPosition.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/get_index_for_new_frame_for_frameposition.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddFrameButtonsColumnInAnimMainBox extends StatefulWidget {
  AddFrameButtonsColumnInAnimMainBox({Key? key}) : super(key: key);

  @override
  State<AddFrameButtonsColumnInAnimMainBox> createState() =>
      _AddFrameButtonsColumnInAnimMainBoxState();
}

class _AddFrameButtonsColumnInAnimMainBoxState
    extends State<AddFrameButtonsColumnInAnimMainBox> {
 
  @override
  Widget build(BuildContext context) {
    AnimSheetProvider animSheetProvider =
        Provider.of<AnimSheetProvider>(context);

    debugLog("AddFrameButtonsColumnInAnimMainBox animSheetProvider called ${iconsectionsTreeinAnimSheetScrollPosition}");
    // addFrameButtonsColumnInAnimMainBoxScrollController = ScrollController(
    //     initialScrollOffset: iconsectionsTreeinAnimSheetScrollPosition);
    return Container(
      width: 2.sw(context),
      height: (100.sh(context) -
          topbarHeight -
          animSheetProvider.animationSheetFromTop +
          35 +
          10 -
         
          animaBarH -
          1.sh(context) -
          timelineBarH.sw(context)).abs(),
      color: Colors.green.shade200,
      child: NotificationListener<ScrollNotification>(  onNotification: (ScrollNotification scrollInfo) {
                    syncScroller.processNotification(scrollInfo, thirdScroller);
                    return true;
                  },
        child: ListView.builder(
            controller: thirdScroller,
            itemCount: projectList[currentProjectNo].iconSections.length,
            shrinkWrap: true,
            itemBuilder: (c, i) {
              return Container(
                height: iconSectionBarHeightInAnimationSheet,
                // animFrameAddbtnHeight.sh(context),
                width: 2.sw(context),
                color: Colors.primaries[i % Colors.primaries.length],
                child: false
                    ? Text(
                        "${projectList[currentProjectNo].iconSections[i].frames.length}")
                    : Center(
                        child: TapIcon(
                            onTap: () {
                              debugLog("timeLinePointerXPosition iconbo  ${i} $timeLinePointerXPosition");
      
                              //  }\n
                              // ${animTimelineWidthFactor.sw(context)-timelineBarH.sw(context)
                              if (timeLinePointerXPosition > 4 &&
                                  (timeLinePointerXPosition <
                                      (animTimelineWidthFactor.sw(context) -
                                          timelineBarH.sw(context) -
                                          4))) {
                                //  get_index_for_new_frame_for_frameposition
                                debugLog("insert framed called on $i with  $currentIconSectionNo ;; ${get_index_for_new_frame_for_frameposition(projectList[currentProjectNo].iconSections[i].frames, getPercentValueForStickPosition(timeLinePointerXPosition, context))} // perc ${getPercentValueForStickPosition(timeLinePointerXPosition, context)}");
      
                                insertNewFrameAtPositionInThisIconsection(
                                    get_index_for_new_frame_for_frameposition(
                                        projectList[currentProjectNo]
                                            .iconSections[i]
                                            .frames,
                                        getPercentValueForStickPosition(
                                            timeLinePointerXPosition, context)),
                                    i,
                                    getPercentValueForStickPosition(
                                        timeLinePointerXPosition, context));
      
                                animSheetProvider.updateUI();
                              }
                            },
                            icon: Icon(
                              Icons.add_rounded,
                              size: animFrameAddbtnHeight.sh(context) * 0.6,
                            )),
                      ),
              );
            }),
      ),
    );
  }
}
