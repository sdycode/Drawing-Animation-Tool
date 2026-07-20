
  import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' as vector;
double angleBetween3Points(Offset f, Offset s) {
    // log('points are center $offset /  start $s  / end $f');
    double angle1 = math.atan2(f.dy - centerPoint.y,
        f.dx - centerPoint.x);
    double angle2 = math.atan2(s.dy -  centerPoint.y,
        s.dx -  centerPoint.x);
    // log('angles are $angle1 and $angle2 ');
    // double angle1 = math.atan2(f.startOffset.dy - s.startOffset.dy,
    //     f.startOffset.dx - s.startOffset.dx);
    // double angle2 = math.atan2(f.currentOffset.dy - s.currentOffset.dy,
    //     f.currentOffset.dx - s.currentOffset.dx);
    double angle = vector.degrees(angle1 - angle2) % 360;
    if (angle < -180.0) angle += 360.0;
    if (angle > 180.0) angle -= 360.0;
    return vector.radians(angle);
  }