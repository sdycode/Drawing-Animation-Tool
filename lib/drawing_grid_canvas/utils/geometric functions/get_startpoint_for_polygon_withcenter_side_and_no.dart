import 'dart:developer' as d;
import 'dart:math';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/extension/extensions%20on%20number/threshold_extension.dart';

Point get_startpoint_for_polygon_withcenter_side_and_no(
  Point point,
  //int n, double boxSide
) {
  Point firstPoint = Point(x: point.x, y: point.y);
  int n = 4;
  double boxSide = 100;
  // for (double i = 0; i <= 360; i++) {
  //   d.log("sin of $i : ${sin(d2R(i))}");
  // }
  // return firstPoint;

  if (n % 2 == 0) {
    // even
    for (var i = 4; i < 9; i = i + 2) {
      double ang = (2 * pi) * (1 / (i * 2));
      double xdir = boxSide * 0.5 * tan(ang);
      Point _centrPoint = Point.zero;
      Point fP = Point(x: -50, y: 25);
    }
  }
  return Point.zero;
}

List<Point> getNthPointFromInitialAngleWithStepAngle(
    double rad, Point center, double width, double height, int n,
    {double? initAngle}) {
  double initialAngle = initAngle ?? 0;
  if (n < 3) {
    return [Point.zero];
  }
  double stepAngle = (2 * pi) / n;

  double h2wFactor = height / width;
  d.log("h2w $height / $width / $h2wFactor");
  if (initAngle == null) {
    if (n % 4 == 0) {
      initialAngle = stepAngle * 0.5;
    } else if (n % 2 == 0) {
      initialAngle = 0;
    } else {
      int angleinDeg = radianToDegree(stepAngle);
      int newang = 90 % angleinDeg;
      initialAngle = degree2Radian(newang.toDouble());
    }
  }

  List<Point> points = [];

  for (var i = 0; i < n; i++) {
    double x = rad * cos(initialAngle + stepAngle * i).threshold();
    double y = rad * sin(initialAngle + stepAngle * i);
    // if()

    Point p = Point(x: x + center.x, y: y * h2wFactor + center.y);
    points.add(p);
    // d.log(        "point @ $i : [${radianToDegree(initialAngle + stepAngle * i)}] : ${p.toMap()}");
  }

  return points;
}

Point get_3rd_point_from_center_and_clockwise_angle(
    Point centerPoint, Point firstPoint, double angle) {
// We take a general point on the boundary of the circle, say (x, y).
//The line joining this general point and the center of the circle (-h, -k) makes an angle of θ θ .
// The parametric equation of circle can be written as x2 + y2 + 2hx + 2ky + C = 0 where x = -h + rcosθ and y = -k + rsinθ.
  double r = sqrt(pow((centerPoint.x - firstPoint.x), 2) +
      pow((centerPoint.y - firstPoint.y), 2));
  d.log(
      "radis $r / $angle / ${radianToDegree(angle)} /cos ${cos(angle).threshold()} / sin ${sin(angle * 2)}");
  if (cos(angle) < 0) {
    d.log("less than zero");
  } else {
    if (cos(angle) < 0.00000000005) {
      d.log("less than 0.000005");
    }
  }
  Point finalPoint = Point.zero;
//  x = -h + rcosθ
  double x = -centerPoint.x + r * cos(angle).threshold();
  // y = -k + rsinθ.
  double y = -centerPoint.y + r * sin(angle);
  finalPoint = Point(x: x, y: y);
  return finalPoint;
}

radianToDegree(double r) {
  return 180 * r * (1 / pi);
}

degree2Radian(double d) {
  return pi * d * (1 / 180);
}
