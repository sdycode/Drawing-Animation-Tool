import 'dart:math';

import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

List<Point> get_box_corner_points_for_numerousPoints(List<Point> points) {
  // List<Point> cornerPoints = [...List.generate(4, (index) => Point.zero)];
  if (points.length < 2) {
    return [...List.generate(4, (index) => Point.zero)];
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
  return [
    Point(x: minx, y: miny),
    Point(x: maxx, y: miny),
    Point(x: maxx, y: maxy),
    Point(x: minx, y: maxy),
  ];
}

Box getBoxForPoints(List<Point> points) {
  if (points.isEmpty) {
    return Box(0, 0, Point.zero);
  }
  if (points.length == 1) {
    return Box(0, 0, points.first);
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
  return Box((maxx - minx).abs(), (maxy - miny).abs(), Point(x: minx +(maxx - minx).abs()*0.5 ,y: miny +(maxy - miny).abs()*0.5));
}

class Box {
  double width;
  double height;
  Point center;
  Box(this.width, this.height, this.center);
}
