

import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/HorizontalTimeLinesOfAllIconsections.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/addFrameButtonsColumnInAnimMainBox.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/curretn_time_vertical_stick.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/Anim_sheet_widgets/timeline_bar.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:flutter/material.dart';

class AnimSheetMainBox extends StatefulWidget {
  AnimSheetMainBox({Key? key}) : super(key: key);

  @override
  State<AnimSheetMainBox> createState() => _AnimSheetMainBoxState();
}

class _AnimSheetMainBoxState extends State<AnimSheetMainBox> {
  @override
  Widget build(BuildContext context) {
    return Container(
         width: animSheetMainBoxWidthFactor.sw(context),
        height: animSheetHeightFactor.sh(context)-animaBarH,
        color: Colors.red.shade200,
        padding: EdgeInsets.only(left: 0.5.sw(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 1.sh(context),),
            TimelineBar(),
          Row(
            children: [

 
Stack(
  children: [ CurrentTimeVerticalStick(),HorizontalTimeLinesOfAllIconsections()],
),
 AddFrameButtonsColumnInAnimMainBox()
            ],
          )
          ,            

          
          ],
        ),
    );
  }
}
