import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Light and dark themes, and the controller that switches between them.
///
/// Lives in `common/` because both the auth screen and the project list need it
/// and neither owns it — `common/` may not import `features/` (docs/v3/08 §3).
///
/// Deliberately **not** a fourth controller beside Document/Editor/Tool
/// (docs/v3/04 §4): those three hold *editor* state and two of them are
/// undoable. Theme is app chrome — never undoable, never persisted into the
/// `Document`, and readable while signed out.
class AppTheme {
  const AppTheme._();

  /// One seed for both themes so light and dark read as the same product.
  static const _seed = Color(0xFF6D8FE8);

  static final dark = _build(Brightness.dark);
  static final light = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // The canvas is the product; chrome stays quiet in both modes.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
    );
  }
}

/// Persists the chosen mode across reloads.
///
/// A seam, not an abstraction for its own sake: widget tests override this so
/// they never touch real platform storage (`SharedPreferences` on web is
/// `localStorage`, which a test environment does not have).
abstract class ThemeStore {
  Future<ThemeMode?> read();
  Future<void> write(ThemeMode mode);
}

/// In-memory default used by tests and by `BACKEND=memory`.
class MemoryThemeStore implements ThemeStore {
  ThemeMode? _mode;

  @override
  Future<ThemeMode?> read() async => _mode;

  @override
  Future<void> write(ThemeMode mode) async => _mode = mode;
}

/// Overridden in `main()` with the real `SharedPreferences`-backed store, so
/// this file imports no plugin and stays testable in a plain `flutter test`.
final themeStoreProvider = Provider<ThemeStore>((ref) => MemoryThemeStore());

/// Dark until storage says otherwise.
///
/// Starting dark and adopting the stored value on arrival is what prevents a
/// light-flash-then-dark on every reload. A storage failure is swallowed *here*,
/// at the IO boundary where docs/v3/08 §1 says guards belong — a broken
/// preference must not cost the user the app.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.dark;
  }

  Future<void> _restore() async {
    try {
      final stored = await ref.read(themeStoreProvider).read();
      if (stored != null) state = stored;
    } catch (e) {
      assert(() {
        debugPrint('Theme preference unreadable, staying dark: $e');
        return true;
      }());
    }
  }

  /// Two states only. The user asked for a straight light/dark switch, so
  /// `ThemeMode.system` is never written and never shown.
  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = next;
    try {
      await ref.read(themeStoreProvider).write(next);
    } catch (e) {
      // The mode still changed for this session; only persistence failed.
      assert(() {
        debugPrint('Theme preference unwritable: $e');
        return true;
      }());
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// The one toggle. An icon in the app bar, not a settings screen — docs/v3/05
/// §1 rules a fourth screen out.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    return IconButton(
      key: const Key('theme-toggle'),
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          size: 18),
      onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
    );
  }
}
