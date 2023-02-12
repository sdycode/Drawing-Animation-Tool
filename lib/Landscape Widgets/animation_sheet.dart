import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/addFrameButtonsColumnInAnimMainBox.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/animsheet_main_box.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/icon_sections_tree_in_animsheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SyncScrollController {
  List<ScrollController> _registeredScrollControllers = [];

  ScrollController? _scrollingController;
  bool _scrollingActive = false;

  SyncScrollController(List<ScrollController> controllers) {
    controllers.forEach((controller) => registerScrollController(controller));
  }

  void registerScrollController(ScrollController controller) {
    _registeredScrollControllers.add(controller);
  }

  void processNotification(
      ScrollNotification notification, ScrollController sender) {
    if (notification is ScrollStartNotification && !_scrollingActive) {
      _scrollingController = sender;
      _scrollingActive = true;
      return;
    }

    if (identical(sender, _scrollingController) && _scrollingActive) {
      if (notification is ScrollEndNotification) {
        _scrollingController = null;
        _scrollingActive = false;
        return;
      }

      if (notification is ScrollUpdateNotification) {
        _registeredScrollControllers.forEach((controller) => {
              if (!identical(_scrollingController, controller))
                controller..jumpTo(_scrollingController!.offset)
            });
        return;
      }
    }
  }
}

ScrollController firstScroller = ScrollController();
ScrollController secondScroller = ScrollController();
ScrollController thirdScroller = ScrollController();

SyncScrollController syncScroller =
    SyncScrollController([firstScroller, secondScroller, thirdScroller]);
double iconSectionBarHeightInAnimationSheet = 34;
double animaBarH = 10;
double animSheetHeightFactor = 75;
double animIconSectionTreeWidthFactor = 20;
double animSheetMainBoxWidthFactor = 80;
double animTimelineWidthFactor = 76;
double timelineBarH = 1;
double timeLinePointerXPosition = 0;
double xSpanForTime = 74;
double animFrameAddbtnHeight = 4;
List<int> iconSectionIndexesToIncludeInAnimationList = [0];
double iconsectionsTreeinAnimSheetScrollPosition = 0;
Map<int, List<double>> framePosPercentListForAllIconSections = {
  0: [0, 100]
};
List<double> currntframePosPercentList = [0, 100];

class AnimationSheetWidget extends StatefulWidget {
  AnimationSheetWidget({Key? key}) : super(key: key);

  @override
  State<AnimationSheetWidget> createState() => _AnimationSheetWidgetState();
}

late AnimSheetProvider animSheetProvider;

class _AnimationSheetWidgetState extends State<AnimationSheetWidget> {
  @override
  void initState() {
    syncScroller =
        SyncScrollController([firstScroller, secondScroller, thirdScroller]);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    animSheetProvider = Provider.of<AnimSheetProvider>(context);
    // animaBarH = animSheetProvider.animationSheetFromTop;
    debugLog(
        "animSheetHeightFactor.sh(context)  ${animSheetHeightFactor.sh(context)} /  ${100.sh(context) - topbarHeight - animSheetProvider.animationSheetFromTop}");
    return Positioned(
      top: animSheetProvider.animationSheetFromTop,
      child: Container(
        width: 100.sw(context),
        height:( 100.sh(context) -
            topbarHeight -
            animSheetProvider.animationSheetFromTop +
            35 +
            10).abs(),
        //  animSheetHeightFactor.sh(context),
        color: Colors.pink.shade100.withAlpha(255),
        child: Column(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _animBar(),
                Row(
                  children: [
                    IconsectionsTreeinAnimSheet(), 
                  AnimSheetMainBox()
                  ],
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  _animBar() {
    return GestureDetector(
      onTap: () {
        if (animSheetProvider.animationSheetFromTop >=
            (100.sh(context) - animaBarH)) {
          animSheetProvider.animationSheetFromTop =
              (25.sh(context) + animaBarH * 0.5);
        } else {
          animSheetProvider.animationSheetFromTop =
              (100.sh(context) - animaBarH);
        }

        animSheetProvider.updateUI();
      },
      onPanStart: (d) {},
      onPanUpdate: (d) {
        double percentValue =
            animSheetProvider.animationSheetFromTop / (1.sh(context));
        // ${d.delta} / ${animSheetProvider.animationSheetFromTop / (1.sh(context)).toInt()}
        // if(percentValue )
        log("chng ${animSheetProvider.animationSheetFromTop} //// ${25.sh(context)} +  ${animSheetHeightFactor.sh(context)} = ${100.sh(context) - animaBarH}");
        log("upper ${animSheetProvider.animationSheetFromTop >= (25.sh(context))} // delat : ${d.delta.dy} ");
        if (animSheetProvider.animationSheetFromTop <=
                (100.sh(context) - animaBarH) &&
            (animSheetProvider.animationSheetFromTop >=
                (25.sh(context) + animaBarH * 0.5))) {
          animSheetProvider.animationSheetFromTop += d.delta.dy;
          if ((animSheetProvider.animationSheetFromTop <
              (25.sh(context) + animaBarH * 0.5))) {
            animSheetProvider.animationSheetFromTop =
                (25.sh(context) + animaBarH * 0.5);
          }
          if (animSheetProvider.animationSheetFromTop >
              (100.sh(context) - animaBarH)) {
            animSheetProvider.animationSheetFromTop =
                (100.sh(context) - animaBarH);
          }
          animSheetProvider.updateUI();
        }
      },
      child: Container(
        height: animaBarH,
        width: double.infinity,
        color: Colors.grey,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Animation",
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
            ),
            TapIcon(
              onTap: () {
                if (animSheetProvider.animationSheetFromTop >=
                    (100.sh(context) - animaBarH)) {
                  animSheetProvider.animationSheetFromTop =
                      (25.sh(context) + animaBarH * 0.5);
                } else {
                  animSheetProvider.animationSheetFromTop =
                      (100.sh(context) - animaBarH);
                }

                animSheetProvider.updateUI();
              },
              icon: Icon(
                animSheetProvider.animationSheetFromTop >=
                        (100.sh(context) - animaBarH)
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 10,
                color: Colors.black,
              ),
            )
          ],
        ),
      ),
    );
  }
}
