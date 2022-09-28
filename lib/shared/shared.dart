import 'package:shared_preferences/shared_preferences.dart';

class Shared {
  static late SharedPreferences pref;
  static Future init() async {
    pref = await SharedPreferences.getInstance();
  }

  static setUserName(String username) {
    if (username.trim().length > 5) {
      pref.setString("username", username);
    }
  }

  static String getUserName() {
    return pref.getString("username") ?? "";
  }
}
