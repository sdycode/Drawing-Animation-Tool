import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/timeline_bar.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/numeric%20funtions/getActualStickserPositionFromPercentValue.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/set_drawingobjecttype_when_iconsection_selected.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
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
    );  animSheetProvider =
                                Provider.of<AnimSheetProvider>(context);

    return Container(
      width: animIconSectionTreeWidthFactor.sw(context) - 50,
      height: (100.sh(context) -
          topbarHeight -
          animSheetProvider.animationSheetFromTop +
          35

          -
          animaBarH).abs(),
      // color: Colors.amber.shade200,
      child: Container(
          width: animIconSectionTreeWidthFactor.sw(context) - 50,
          height:
              // animSheetHeightFactor.sh(context) -
              (100.sh(context) -
                  topbarHeight -
                  animSheetProvider.animationSheetFromTop +
                  35 +

                
                  animaBarH -
                  1.sh(context) -
                  timelineBarH.sw(context)).abs(),
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
                          size: timelineBarH.sw(context) * 1.2,
                          color: Colors.black,
                        ),
                        onTap: () {
                          newanimationController.forward();
                        },
                      ),
                      TapIcon(
                        icon: Icon(
                          Icons.stop,
                          size: timelineBarH.sw(context) * 1.2,
                          color: Colors.black,
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
                        return InkWell(
                          onTap: () {
                          
                            animSheetProvider.updateUI();
                          },
                          child: Container(
                              // height: animFrameAddbtnHeight.sh(context),
                              alignment: Alignment.center,
                              child: Container(
                                  height: iconSectionBarHeightInAnimationSheet,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    border:
                                        Border.all(color: Colors.grey.shade100),
                                    color: Color.fromARGB(255, 38, 37, 37),
                                  ),
                  
                                  // Colors.primaries[i % Colors.primaries.length],
                                  child: Row(
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
                                    ],
                                  ))),
                        );
                      }),
                ),
              ),
            ],
          )),
    );
  }
}
