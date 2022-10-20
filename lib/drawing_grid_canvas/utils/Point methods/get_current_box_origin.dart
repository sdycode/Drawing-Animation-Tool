import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/Point%20methods/point_to_offset.dart';
import 'package:flutter/material.dart';

Offset getCurrentBoxOrigin() {
  return Offset(
      getOffsetFromPoint(centerPoint).dx - drawingBoardSize.width * 0.5,
      getOffsetFromPoint(centerPoint).dy - drawingBoardSize.height * 0.5);
}
