import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:flutter/material.dart';

Path getContinuousPathForPoints(List<Point> points) {
  Path path = Path();
  path.moveTo(points.first.x, points.first.y);
  for (var i = 1; i < points.length; i++) {
    path.lineTo(points[i].x, points[i].y);
  }
  path.close();
  return path;
}
