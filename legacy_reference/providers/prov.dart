import 'package:flutter/foundation.dart';

class ProvData with ChangeNotifier {
  updateUI() {
    notifyListeners();
  }
}
