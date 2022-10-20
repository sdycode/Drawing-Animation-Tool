import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:flutter/material.dart';

List<Offset> pointsToOffsets(List<Point> points) {
  if (points.isEmpty) {
    return [];
  }
  return points.map((e) {
    Offset of = Offset(e.x, e.y);

    return of;
  }).toList();
}

List<Point> offsetsToPoints(List<Offset> offsets){
  if (offsets.isEmpty) {
    return [];
  }
  return offsets.map((e) {
    Point po = Point(x:e.dx, y:e.dy);

    return po;
  }).toList();
}
// addTwoPoints(orgPoint, Point.fromOffset(d.delta));