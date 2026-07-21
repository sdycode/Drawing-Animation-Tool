/// Developer convenience: the sign-in form starts pre-filled in debug builds.
///
/// **Debug only.** `kDebugMode` is a compile-time constant, so in
/// `flutter build web --release` this flag folds to `false` and the literals
/// below are tree-shaken out of the bundle entirely.
///
/// Override without editing the file:
/// ```bash
/// flutter run --dart-define=DEV_EMAIL=you@example.com \
///             --dart-define=DEV_PASSWORD=hunter2
/// flutter run --dart-define=DEV_PREFILL=false   # off, even in debug
/// ```
library;

import 'package:flutter/foundation.dart' show kDebugMode;

const _enabled = bool.fromEnvironment('DEV_PREFILL', defaultValue: true);

/// True only in a debug build that has not opted out.
bool get kDevPrefill => kDebugMode && _enabled;

const kDevEmail =
    String.fromEnvironment('DEV_EMAIL', defaultValue: 'shu@gmail.com');

const kDevPassword =
    String.fromEnvironment('DEV_PASSWORD', defaultValue: 'qwertyuiop');
