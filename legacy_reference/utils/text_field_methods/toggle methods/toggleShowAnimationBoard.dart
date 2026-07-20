import 'dart:developer';

import 'package:animated_icon_demo/enums/enums.dart';

void toggleShowAnimationBoard() {
  log("showAnimationBoard $showAnimationBoard");
  if (showAnimationBoard == ShowAnimationBoard.hide) {
    showAnimationBoard = ShowAnimationBoard.show;
  } else {
    showAnimationBoard = ShowAnimationBoard.hide;
  }
}
