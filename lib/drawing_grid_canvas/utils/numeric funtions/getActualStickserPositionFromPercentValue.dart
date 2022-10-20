
import 'package:animated_icon_demo/Landscape%20Widgets/animation_sheet.dart';
import 'package:animated_icon_demo/extensions.dart';
import 'package:flutter/material.dart';

double getActualStickserPositionFromPercentValue(double percentValue, BuildContext context) {
  double range = animTimelineWidthFactor.sw(context) - timelineBarH.sw(context);
  
  return (range)*(percentValue /100);
}