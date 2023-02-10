import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/timeline_bar.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getActualStickserPositionFromPercentValue.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/set_drawingobjecttype_when_iconsection_selected.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
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
  // iconsectionsTreeinAnimSheetScrollPosition
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    // iconsectionsTreeinAnimSheetScrollController.addListener(() {
    //   if (iconsectionsTreeinAnimSheetScrollController.hasClients) {
    //     iconsectionsTreeinAnimSheetScrollPosition =
    //         iconsectionsTreeinAnimSheetScrollController.offset;
    //     debugLog(
    //         "iconsectionsTreeinAnimSheetScrollController ${iconsectionsTreeinAnimSheetScrollController.offset}");
    //   }
    // });
  }

  @override
  Widget build(BuildContext context) {
    ProvData provData = Provider.of<ProvData>(
      context,
    );

    return Container(
      width: animIconSectionTreeWidthFactor.sw(context),
      height: 100.sh(context) -
          topbarHeight -
          animSheetProvider.animationSheetFromTop +
          35
          //  animSheetHeightFactor.sh(context)

          -
          animaBarH,
      // color: Colors.amber.shade200,
      child: Container(
          width: animIconSectionTreeWidthFactor.sw(context),
          height:
              // animSheetHeightFactor.sh(context) -
              100.sh(context) -
                  topbarHeight -
                  animSheetProvider.animationSheetFromTop +
                  35 +

                  // Before
                  animaBarH -
                  1.sh(context) -
                  timelineBarH.sw(context),
          // color: Colors.green.shade200,
          child: Column(
            children: [
              // SizedBox(height: 10,),
              Transform.translate(
                offset: Offset(0, -timelineBarH.sw(context) * 0.2),
                child: Container(
                  height: timelineBarH.sw(context),
                  //  + 1.sh(context),
                  width: animIconSectionTreeWidthFactor.sw(context),
                  child: Row(
                    children: [
                      TapIcon(
                        icon: Icon(
                          Icons.play_arrow,
                          size: timelineBarH.sw(context) * 1.2,color: Colors.black,
                        ),
                        onTap: () {
                          newanimationController.forward();
                        },
                      ),
                      TapIcon(
                        icon: Icon(
                          Icons.stop,
                          size: timelineBarH.sw(context) * 1.2,color: Colors.black,
                        ),
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
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification scrollInfo) {
                    syncScroller.processNotification(scrollInfo, firstScroller);
                    return true;
                  },
                  child: ListView.builder(
                      controller: firstScroller,
                      itemCount:
                          projectList[currentProjectNo].iconSections.length,
                      shrinkWrap: true,
                      itemBuilder: (c, i) {
                        return Container(
                            // height: animFrameAddbtnHeight.sh(context),
                            alignment: Alignment.center,
                            child: Container(
                              height: iconSectionBarHeightInAnimationSheet,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade100),
                                color: Color.fromARGB(255, 38, 37, 37),
                              ),

                              // Colors.primaries[i % Colors.primaries.length],
                              child: true
                                  ? Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            projectList[currentProjectNo]
                                                .iconSections[i]
                                                .iconSectionName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12),
                                          ),
                                        ),
                                        // Spacer(),
                                        // TapIcon(

                                        //     onTap: () {
                                        //       provData.updateUI();
                                        //       if (!iconSectionIndexesToIncludeInAnimationList
                                        //           .contains(i)) {
                                        //         iconSectionIndexesToIncludeInAnimationList
                                        //             .add(i);
                                        //       } else {
                                        //         iconSectionIndexesToIncludeInAnimationList
                                        //             .remove(i);
                                        //       }
                                        //     },
                                        //     icon: Icon(
                                        //         iconSectionIndexesToIncludeInAnimationList
                                        //                 .contains(i)
                                        //             ? Icons.check_box
                                        //             : Icons.check_box_outline_blank, size: 15,))
                                      ],
                                    )
                                  : ExpansionTile(
                                      title: Row(
                                        children: [
                                          Text(
                                            projectList[currentProjectNo]
                                                .iconSections[i]
                                                .iconSectionName,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12),
                                          ),
                                          Spacer(),
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
                                                    : Icons
                                                        .check_box_outline_blank,
                                                size: 15,
                                              ))
                                        ],
                                      ),
                                      children: [
                                        Container(
                                          height:
                                              animFrameAddbtnHeight.sh(context),
                                          width: double.infinity,
                                          child: ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              itemCount:
                                                  projectList[currentProjectNo]
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
                                                            projectList[
                                                                    currentProjectNo]
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
                                                      padding:
                                                          const EdgeInsets.all(
                                                              8.0),
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
                ),
              ),
            ],
          )),
    );
  }
}
