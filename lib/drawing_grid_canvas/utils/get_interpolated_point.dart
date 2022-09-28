import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

Point getInterPolatedPoint(
    double progessValue, Point initialPoint, Point lastPoint) {
 
  double x = (initialPoint.x * (1.0-progessValue)+ lastPoint.x * (progessValue));

  double y = (initialPoint.y * (1.0-progessValue)+ lastPoint.y * (progessValue));
return   Point(x: x, y: y);
}
