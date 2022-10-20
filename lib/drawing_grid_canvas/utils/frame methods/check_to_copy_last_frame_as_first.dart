import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/shape%20functions/check_weather_youare_drawing_shape_first_time.dart';

bool check_to_copy_last_frame_as_first(IconSection iconSection) {
  if (iconSection.frames.length == 2) {
    int frmeNo = 1;
    if (currentFrameNo == 1) {
      frmeNo = 0;
    }
    Point p1 = iconSection.frames[frmeNo].singleFrameModel.points.first;
    Point p2 = iconSection.frames[frmeNo].singleFrameModel.points[1];
    double d = getDistBetween2Points(p1, p2);
    if (d < 2) {
      return true;
    } else {
      return false;
    }
  } else {
    return false;
  }
  return false;
}
