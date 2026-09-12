import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Editor chrome the user adjusts but the document never holds — whether the
/// how-to guide has already been seen, and how tall they dragged the timeline.
///
/// **A seam, and the same one [ThemeStore] is** (`common/theme.dart`): the
/// interface lives here so a widget test builds the whole editor against the
/// in-memory default and never reaches a platform binding, while `main.dart`
/// injects the `SharedPreferences` implementation from `data/` — the one layer
/// allowed to touch storage (docs/v3/08 §3).
///
/// **Deliberately not a fourth controller** beside Document/Editor/Tool
/// (docs/v3/04 §4). Nothing here is undoable, nothing here is serialized into a
/// `Document`, and nothing here changes what the renderer draws — it is chrome,
/// exactly like the theme.
abstract class UiPrefs {
  /// False only for someone who has never opened the editor. The guide
  /// auto-opens on that one visit; every later visit is button-only.
  Future<bool> guideSeen();

  Future<void> setGuideSeen(bool seen);

  /// The timeline height the user dragged to, in logical pixels — or null when
  /// they never dragged it, which reads as "the editor's default stands" rather
  /// than as a stored zero.
  Future<double?> timelineHeight();

  Future<void> setTimelineHeight(double height);
}

/// The default, used by tests and by `BACKEND=memory`.
///
/// **`guideSeen` defaults to `true`, and that is load-bearing.** Every widget
/// test in `test/` builds `EditorShell` without overriding this provider; a
/// default of "never seen" would drop a modal over all of them and turn one new
/// feature into a suite-wide failure. A test that wants the first-run path asks
/// for it explicitly (`MemoryUiPrefs(seenGuide: false)`), which is also the only
/// honest way to *test* the first-run path.
class MemoryUiPrefs implements UiPrefs {
  MemoryUiPrefs({bool seenGuide = true, double? timeline})
      : _seen = seenGuide,
        _timeline = timeline;

  bool _seen;
  double? _timeline;

  @override
  Future<bool> guideSeen() async => _seen;

  @override
  Future<void> setGuideSeen(bool seen) async => _seen = seen;

  @override
  Future<double?> timelineHeight() async => _timeline;

  @override
  Future<void> setTimelineHeight(double height) async => _timeline = height;
}

/// Overridden in `main()` with the real `SharedPreferences`-backed store, so
/// this file imports no plugin and stays testable in a plain `flutter test`.
final uiPrefsProvider = Provider<UiPrefs>((ref) => MemoryUiPrefs());

/// Read a preference without letting a broken one cost the user the feature.
///
/// Storage is the IO boundary docs/v3/08 §1 puts guards at: `localStorage` can
/// be disabled, full, or hold a value a future version wrote. A failure here
/// means "no preference", never a dead editor — and it is loud in debug so a
/// genuinely broken store is not invisible during development.
Future<T?> readPref<T>(Future<T> Function() read, String what) async {
  try {
    return await read();
  } catch (e) {
    assert(() {
      debugPrint('UI preference "$what" unreadable, using the default: $e');
      return true;
    }());
    return null;
  }
}

/// The write half of [readPref]. The setting still holds for this session; only
/// persistence failed, and a modal about it would be worse than the loss.
Future<void> writePref(Future<void> Function() write, String what) async {
  try {
    await write();
  } catch (e) {
    assert(() {
      debugPrint('UI preference "$what" unwritable: $e');
      return true;
    }());
  }
}
