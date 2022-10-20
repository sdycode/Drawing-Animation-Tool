import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

class AnimatePointsModel {
  List<Point> frame1Points = [];
  List<Point> frame2Points = [];
  List<Point> animatingFramePoints = [];
  AnimatePointsModel();
  AnimatePointsModel.withFramePoints(this.frame1Points, this.frame2Points);
  AnimatePointsModel.withFrameAndAnimePointsPoints(
      this.frame1Points, this.frame2Points, this.animatingFramePoints);
}