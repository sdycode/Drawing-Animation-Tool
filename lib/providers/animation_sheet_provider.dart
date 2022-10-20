import 'package:flutter/foundation.dart';

class AnimSheetProvider with ChangeNotifier {
    double animationSheetFromTop = 10;
  updateUI() {
    notifyListeners();
  }
}
