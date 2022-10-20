import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/timeline_bar.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getActualStickserPositionFromPercentValue.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/set_drawingobjecttype_when_iconsection_selected.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/widgets/animation_showing_box_widget.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class IconsectionsTreeinAnimSheet extends StatefulWidget {
  IconsectionsTreeinAnimSheet({Key? key}) : super(key: key);

  @override
  State<IconsectionsTreeinAnimSheet> createState() =>
      _IconsectionsTreeinAnimSheetState();
}

class _IconsectionsTreeinAnimSheetState
    extends State<IconsectionsTreeinAnimSheet> {
  @override
  Widget build(BuildContext context) {
    ProvData provData = Provider.of<ProvData>(
      context,
    );
    return Container(
      width: animIconSectionTreeWidthFactor.sw(context),
      height: animSheetHeightFactor.sh(context) - animaBarH,
      color: Colors.amber.shade200,
      child: Container(
          width: animIconSectionTreeWidthFactor.sw(context),
          height: animSheetHeightFactor.sh(context) -
              animaBarH -
              1.sh(context) -
              timelineBarH.sw(context),
          color: Colors.green.shade200,
          child: Column(
            children: [
              Container(
                height: timelineBarH.sw(context) + 1.sh(context),
                width: animIconSectionTreeWidthFactor.sw(context),
                child: Row(
                  children: [
                    TapIcon(
                      icon: const Icon(Icons.play_arrow),
                      onTap: () {
                        newanimationController.forward();
                      },
                    ),
                    TapIcon(
                      icon: const Icon(Icons.stop),
                      onTap: () {
                        newanimationController.reset();
                      },
                    ),
                  ],
                ),
                // child: Text(
                //   "timeLinePointerXPosition ${timeLinePointerXPosition}\n${animTimelineWidthFactor.sw(context) - timelineBarH.sw(context)}",
                //   style: TextStyle(fontSize: 12),
                // ),
              ),
              ListView.builder(
                  itemCount: projectList[currentProjectNo].iconSections.length,
                  shrinkWrap: true,
                  itemBuilder: (c, i) {
                    return Container(
                        // height: animFrameAddbtnHeight.sh(context),
                        alignment: Alignment.center,
                        child: Container(
                          height: 34,
                          color: Colors.primaries[i%Colors.primaries.length],
                          child: 
                           true ?Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    projectList[currentProjectNo]
                                        .iconSections[i]
                                        .iconSectionName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                                // Spacer(),
                                TapIcon(
                                  
                                    onTap: () {
                                      provData.updateUI();
                                      if (!iconSectionIndexesToIncludeInAnimationList
                                          .contains(i)) {
                                        iconSectionIndexesToIncludeInAnimationList
                                            .add(i);
                                      } else {
                                        iconSectionIndexesToIncludeInAnimationList
                                            .remove(i);
                                      }
                                    },
                                    icon: Icon(
                                        iconSectionIndexesToIncludeInAnimationList
                                                .contains(i)
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank, size: 15,))
                              ],
                            ) :
                          
                          
                          ExpansionTile(
                            title: Row(
                              children: [
                                Text(
                                  projectList[currentProjectNo]
                                      .iconSections[i]
                                      .iconSectionName,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),Spacer(),
                                TapIcon(
                                  
                                    onTap: () {
                                      provData.updateUI();
                                      if (!iconSectionIndexesToIncludeInAnimationList
                                          .contains(i)) {
                                        iconSectionIndexesToIncludeInAnimationList
                                            .add(i);
                                      } else {
                                        iconSectionIndexesToIncludeInAnimationList
                                            .remove(i);
                                      }
                                    },
                                    icon: Icon(
                                        iconSectionIndexesToIncludeInAnimationList
                                                .contains(i)
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank, size: 15,))
                              ],
                            ),
                            children: [
                              Container(
                                height: animFrameAddbtnHeight.sh(context),
                                width: double.infinity,
                                child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: projectList[currentProjectNo]
                                        .iconSections[i]
                                        .frames
                                        .length,
                                    itemBuilder: (c, fi) {
                                      return InkWell(
                                        onTap: () {
                                          currentFrameNo = fi;
                                          currentIconSectionNo = i;
                                            set_drawingobjecttype_when_iconsection_selected();
                                          timeLinePointerXPosition =
                                              getActualStickserPositionFromPercentValue(
                                                  projectList[currentProjectNo]
                                                      .iconSections[i]
                                                      .frames[fi]
                                                      .singleFrameModel
                                                      .framePosition,
                                                  context);
                                          provData.updateUI();
                                        },
                                        child: Container(
                                          color: currentFrameNo == fi
                                              ? Colors.green.shade100
                                                  .withAlpha(150)
                                              : Colors.transparent,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                                "${projectList[currentProjectNo].iconSections[i].frames[fi].singleFrameModel.points.length}"),
                                          ),
                                        ),
                                      );
                                    }),
                              )
                            ],
                          ),
                        ));
                  }),
            ],
          )),
    );
  }
}
