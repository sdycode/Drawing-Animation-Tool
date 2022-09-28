import 'package:flutter/material.dart';

import '../drawing_grid_canvas_fields.dart';

bool isPointHoverPointisInsideBoundryBox(Offset offset) {
  bool isInX = false;
  bool isInY = false;
  if (hoverPoint.dx > offset.dx - 5 && hoverPoint.dx < offset.dx + 5) {
    isInX = true;
  }
  if (hoverPoint.dy > offset.dy - 5 && hoverPoint.dy < offset.dy + 5) {
    isInY = true;
  }
  if (isInX && isInY) {
    return true;
  }
  return false;
}