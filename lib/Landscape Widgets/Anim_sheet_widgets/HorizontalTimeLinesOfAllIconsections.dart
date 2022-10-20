import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getActualStickserPositionFromPercentValue.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/prov.dart';
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
  @override
  Widget build(BuildContext context) {
    ProvData provider = Provider.of<ProvData>(context);
    log("factot ${animSheetMainBoxWidthFactor.sw(context) * (1 - 0.051)} and ${39 / animSheetMainBoxWidthFactor.sw(context)}");
    return Container(
        width: animSheetMainBoxWidthFactor.sw(context) * (1 - 0.051),
        // 1-0.051
        // height: animSheetHeightFactor.sh(context)-animaBarH,
        padding: EdgeInsets.only(
            left: 0.5.sw(context) - timelineBarH.sw(context) * 0.5),
        child: ListView.builder(
            itemCount: projectList[currentProjectNo].iconSections.length,
            shrinkWrap: true,
            itemBuilder: (BuildContext context, int i) {
              return Container(
                width: animTimelineWidthFactor.sw(context),
                // *(1-0.051),
                // -
                //     0.5.sw(context) -
                //     timelineBarH.sw(context) * 0.5 ,
                height: 34,
                color: Colors.primaries[i % Colors.primaries.length]
                    .withAlpha(150),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constr) {
                    double horzWidth = constr.maxWidth;
                    return Stack(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: horzWidth,
                          height: 0.5,
                          color: Colors.black,
                        ),
                      ),
                      ...List.generate(
                          projectList[currentProjectNo]
                              .iconSections[i]
                              .frames
                              .length, (fi) {
                        Frame frame = projectList[currentProjectNo]
                            .iconSections[i]
                            .frames[fi];
                        double tempPosition =
                            getActualStickserPositionFromPercentValue(
                                frame.singleFrameModel.framePosition, context);
                        return Positioned(
                            left: tempPosition -
                                3 +
                                timelineBarH.sw(context) * 0.5,
                            child: Container(
                              height: constr.maxHeight,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: InkWell(
                                      onTap: () {
                                        currentFrameNo = fi;
                                        setTimeLinePointerXPositionForSelectedFrame(projectList[currentProjectNo].iconSections[i].frames[fi]);
                                        provider.updateUI();
                                      },
                                      child: CircleAvatar(
                                        radius: 3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ));
                      })
                    ]);
                  },
                ),
              );
            }));
  }
  
  void setTimeLinePointerXPositionForSelectedFrame(Frame frame) {
      timeLinePointerXPosition =
                                              getActualStickserPositionFromPercentValue(
                                                 frame
                                                      .singleFrameModel
                                                      .framePosition,
                                                  context);
  }
}
