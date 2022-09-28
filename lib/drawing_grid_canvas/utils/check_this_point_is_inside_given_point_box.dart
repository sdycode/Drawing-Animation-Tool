
import 'package:flutter/material.dart';

bool isThisPointisInsideBoundryBox(
    Offset currentHoverPoint, Offset centerPoint) {
  bool isInX = false;
  bool isInY = false;
  if (currentHoverPoint.dx > centerPoint.dx - 5 &&
      currentHoverPoint.dx < centerPoint.dx + 5) {
    isInX = true;
  }
  if (currentHoverPoint.dy > centerPoint.dy - 5 &&
      currentHoverPoint.dy < centerPoint.dy + 5) {
    isInY = true;
  }
  if (isInX && isInY) {
    return true;
  }
  return false;
}