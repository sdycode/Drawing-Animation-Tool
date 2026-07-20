import 'dart:developer';

import 'package:flutter/foundation.dart';

void debugLog(String s) {
  if (kDebugMode) {
    log(s);
  }
}
