import 'dart:developer';

import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/animsheet_main_box.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/icon_sections_tree_in_animsheet.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/widgets/res/Icons/tap_icon.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

double animaBarH = 10;
double animSheetHeightFactor = 75;
double animIconSectionTreeWidthFactor = 20;
double animSheetMainBoxWidthFactor = 80;
double animTimelineWidthFactor = 76;
double timelineBarH = 1;
double timeLinePointerXPosition = 0;
double xSpanForTime = 74;
double animFrameAddbtnHeight = 4;
List<int> iconSectionIndexesToIncludeInAnimationList = [];
Map<int,List<double>> framePosPercentListForAllIconSections = {
  0:[0,100]
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
  Widget build(BuildContext context) {
    animSheetProvider = Provider.of<AnimSheetProvider>(context);
    // animaBarH = animSheetProvider.animationSheetFromTop;
    return Positioned(
      top: animSheetProvider.animationSheetFromTop,
      child: Container(
        width: 100.sw(context),
        height: animSheetHeightFactor.sh(context),
        color: Colors.pink.shade100.withAlpha(255),
        child: Column(
          children: [
            Transform.scale(
              scaleY: 1,
              child: GestureDetector(
                child: Transform.scale(
                    scaleY: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _animBar(),
                        Row(
                          children: [
                            IconsectionsTreeinAnimSheet(),
                            AnimSheetMainBox()
                          ],
                        )
                      ],
                    )),
              ),
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
