import 'package:shared_preferences/shared_preferences.dart';

import '../common/ui_prefs.dart';

/// [UiPrefs] backed by `SharedPreferences` — `localStorage` on web.
///
/// Lives in `data/` for the same reason `PrefsThemeStore` does: that is the
/// layer allowed to touch platform storage (docs/v3/08 §3), and keeping the
/// plugin out of `common/` is what lets a widget test build the whole editor
/// without a binding.
///
/// **Nothing here throws on a bad value.** An absent key, a value a future
/// version wrote, or a non-finite height all read as "no preference" and the
/// editor's own default stands — the same total-parse discipline the file
/// format uses (docs/v3/02 §4), applied to a preference nobody would miss.
class PrefsUiPrefs implements UiPrefs {
  static const _guideKey = 'guideSeen';
  static const _timelineKey = 'timelineHeight';

  @override
  Future<bool> guideSeen() async {
    final prefs = await SharedPreferences.getInstance();
    // Absent means "never opened the editor", which is exactly the visitor the
    // first-run guide is for.
    return prefs.getBool(_guideKey) ?? false;
  }

  @override
  Future<void> setGuideSeen(bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guideKey, seen);
  }

  @override
  Future<double?> timelineHeight() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(_timelineKey);
    // A NaN or infinity would propagate into a `SizedBox` constraint and take
    // the layout with it; the caller's clamp cannot rescue a NaN (every
    // comparison against it is false).
    if (stored == null || !stored.isFinite) return null;
    return stored;
  }

  @override
  Future<void> setTimelineHeight(double height) async {
    if (!height.isFinite) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_timelineKey, height);
  }
}
