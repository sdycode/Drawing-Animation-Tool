import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/HorizontalTimeLinesOfAllIconsections.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/addFrameButtonsColumnInAnimMainBox.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/curretn_time_vertical_stick.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/timeline_bar.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AnimSheetMainBox extends StatefulWidget {
  AnimSheetMainBox({Key? key}) : super(key: key);

  @override
  State<AnimSheetMainBox> createState() => _AnimSheetMainBoxState();
}

class _AnimSheetMainBoxState extends State<AnimSheetMainBox> {
  @override
  Widget build(BuildContext context) {
    AnimSheetProvider animSheetProvider =
        Provider.of<AnimSheetProvider>(context);
    debugLog("AnimSheetMainBox animSheetProvider called");
    return Container(
      width: animSheetMainBoxWidthFactor.sw(context),
      height:

          // animSheetHeightFactor.sh(context)
          (100.sh(context) -
                  topbarHeight -
                  animSheetProvider.animationSheetFromTop +
                  35 +
                  10 -
                  animaBarH)
              .abs(),
      color: Colors.red.shade200,
      padding: EdgeInsets.only(left: 0.5.sw(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 1.sh(context),
          ),
          TimelineBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (p0, box) {
                return Container(
                  // width: box.maxWidth,
                  width: animSheetMainBoxWidthFactor.sw(context),
                  height: box.maxHeight,
                  child: Row(
                    children: [
                      Container(
                        child: Stack(
                          // fit: StackFit.passthrough,
                          children: [
                            HorizontalTimeLinesOfAllIconsections(),
                            CurrentTimeVerticalStick(),
                          ],
                        ),
                      ),
                      AddFrameButtonsColumnInAnimMainBox()
                    ],
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
