import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../common/theme.dart';

/// `ThemeStore` backed by `SharedPreferences` — `localStorage` on web.
///
/// Lives in `data/` because that is the layer allowed to touch platform storage
/// (docs/v3/08 §3). `common/theme.dart` holds only the interface, so a widget
/// test can build the whole app without a plugin binding.
class PrefsThemeStore implements ThemeStore {
  static const _key = 'themeMode';

  @override
  Future<ThemeMode?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      // Absent, or a value written by a future version. Absent means "never
      // chosen", which is the dark default — not a reason to fail.
      _ => null,
    };
  }

  @override
  Future<void> write(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.light ? 'light' : 'dark');
  }
}
