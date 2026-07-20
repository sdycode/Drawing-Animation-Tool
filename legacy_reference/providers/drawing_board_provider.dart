import 'package:flutter/foundation.dart';

class DrawingBoardProvider with ChangeNotifier {
  updateUI() {
    notifyListeners();
  }
}
