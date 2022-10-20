import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/add%20new%20methods/add_new_frame.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/insert_new_frame_at_position.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getPercentValueForStickPosition.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/get_index_for_new_frame_for_frameposition.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddFrameButtonsColumnInAnimMainBox extends StatelessWidget {
  const AddFrameButtonsColumnInAnimMainBox({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    AnimSheetProvider animSheetProvider =
        Provider.of<AnimSheetProvider>(context);
    return Container(
      width: 2.sw(context),
      height: animSheetHeightFactor.sh(context) -
          animaBarH -
          1.sh(context) -
          timelineBarH.sw(context),
      color: Colors.green.shade200,
      child: ListView.builder(
          itemCount: projectList[currentProjectNo].iconSections.length,
          shrinkWrap: true,
          itemBuilder: (c, i) {
            return InkWell(
              onTap: () {
                //  }\n
                // ${animTimelineWidthFactor.sw(context)-timelineBarH.sw(context)
                if (timeLinePointerXPosition > 4 &&
                    (timeLinePointerXPosition <
                        (animTimelineWidthFactor.sw(context) -
                            timelineBarH.sw(context) -
                            4))) {
                  //  get_index_for_new_frame_for_frameposition
                  log("insert framed called on $i with  $currentIconSectionNo ;; ${ get_index_for_new_frame_for_frameposition(
                          projectList[currentProjectNo]
                              .iconSections[currentIconSectionNo]
                              .frames,
                          getPercentValueForStickPosition(
                              timeLinePointerXPosition, context))} // perc ${ getPercentValueForStickPosition(
                          timeLinePointerXPosition, context)}");
                  insertNewFrameAtPosition(
                      get_index_for_new_frame_for_frameposition(
                          projectList[currentProjectNo]
                              .iconSections[currentIconSectionNo]
                              .frames,
                          getPercentValueForStickPosition(
                              timeLinePointerXPosition, context)),
                      getPercentValueForStickPosition(
                          timeLinePointerXPosition, context));
                  // addNewFrame(getPercentValueForStickPosition(
                  //     timeLinePointerXPosition, context));
                  animSheetProvider.updateUI();
                }
              },
              child: Container(
                height: 
                34,
                // animFrameAddbtnHeight.sh(context),
                width: 2.sw(context),
                color: Colors.primaries[i%Colors.primaries.length],
                child: true
                    ? Text(
                        "${projectList[currentProjectNo].iconSections[i].frames.length}")
                    : TapIcon(
                        icon: Icon(
                        Icons.add,
                        size: animFrameAddbtnHeight.sh(context),
                      )),
              ),
            );
          }),
    );
  }
}
