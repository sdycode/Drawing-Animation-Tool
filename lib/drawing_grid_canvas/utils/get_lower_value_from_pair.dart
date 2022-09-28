import 'package:animated_icon_demo/drawing_grid_canvas/models/single_frame_model.dart';

import '../models/pair_model.dart';

int getLowerFromPair(Pair pair) {
  if (pair.preIndex < pair.nextIndex) {
    return pair.preIndex;
  }
  return pair.nextIndex;
 
}