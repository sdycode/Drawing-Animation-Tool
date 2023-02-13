import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:flutter/material.dart';

class CurrentTimeVerticalStick extends StatelessWidget {
  const CurrentTimeVerticalStick({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Container(
              height: (100.sh(context) -
                      topbarHeight -
                      animSheetProvider.animationSheetFromTop +
                      35 +
                      10 -
                      animaBarH -
                      1.sh(context) -
                      timelineBarH.sw(context))
                  .abs(),
              width: animTimelineWidthFactor.sw(context),
              color: Colors.yellow.shade100.withAlpha(0),
              child: Stack(
                children: [
                  Positioned(
                      left: (timeLinePointerXPosition +
                          timelineBarH.sw(context) * 0.5 -
                          1).abs(),
                      child: Container(
                        color: Colors.white.withAlpha(150),
                        width: 2,
                        height:

                            // animSheetHeightFactor.sh(context) -

                          (  100.sh(context) -
                                topbarHeight -
                                animSheetProvider.animationSheetFromTop +
                                35 +
                                10 -
                                animaBarH -
                                1.sh(context) -
                                timelineBarH.sw(context)).abs(),
                      )),
                ],
              ));
        },
      ),
    );
  }
}
