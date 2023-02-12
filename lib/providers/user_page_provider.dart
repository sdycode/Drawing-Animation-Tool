import 'package:flutter/foundation.dart';

class UserPageProvider with ChangeNotifier {
  updateUI() {
    notifyListeners();
  }
}
