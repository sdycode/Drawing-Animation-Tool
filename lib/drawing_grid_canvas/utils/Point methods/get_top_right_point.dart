import 'dart:math';

import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

Point getTopRightPoint(List<Point> points) {
  if (points.isEmpty) {
    return Point.zero;
  }
  if (points.length == 1) {
    return points.first;
  }
  double minx = points.first.x;
  double maxx = points.first.x;
  double miny = points.first.y;
  double maxy = points.first.y;
  for (var i = 1; i < points.length; i++) {
    minx = min(minx, points[i].x);
    miny = min(miny, points[i].y);
    maxx = max(maxx, points[i].x);
    maxy = max(maxy, points[i].y);
  }
  return Point(x: maxx, y: miny);
}
