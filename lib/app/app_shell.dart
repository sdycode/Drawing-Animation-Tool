import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common/theme.dart';
import 'data/providers.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/projects/project_list_screen.dart';

/// The one file that composes panels (docs/v3/08 §3).
///
/// Deleting a feature stays one line here plus one folder — the compiler-checked
/// kill switch that docs/v3/08 §5 prefers over a feature-flag registry.
class DrawingAnimationToolApp extends ConsumerWidget {
  const DrawingAnimationToolApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Drawing Animation Tool',
      debugShowCheckedModeBanner: false,
      // Dark is the default and the designed-for surface; light is opt-in and
      // remembered (app/common/theme.dart).
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      home: const _AuthGate(),
    );
  }
}

/// Signed out -> sign-in. Signed in -> project list.
///
/// Consumed with `.when`, never `.requireValue` (docs/v3/08 §2): the auth stream
/// is async, and a `.requireValue` on the first frame throws before any user has
/// had a chance to exist.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authStateProvider).when(
          loading: () => const _Splash(),
          error: (e, _) => _Splash(message: 'Sign-in unavailable: $e'),
          data: (user) =>
              user == null ? const SignInScreen() : const ProjectListScreen(),
        );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Replaces Flutter's default `ErrorWidget` so a thrown build contains itself
/// (docs/v3/08 §2, last row).
///
/// The default error widget takes unbounded size, so when it appears inside a
/// `Row` it throws *again* during layout — that second throw is the white
/// screen. This one accepts whatever constraints its parent gives it, so a dead
/// timeline leaves the canvas usable.
class FeatureFallback extends StatelessWidget {
  const FeatureFallback({required this.details, super.key});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    // Loud in debug, contained in release (docs/v3/08 §1).
    assert(() {
      debugPrint('FeatureFallback caught: ${details.exception}');
      return true;
    }());

    // This widget is `ErrorWidget.builder`, so it can be built with no `Theme`
    // ancestor or inside an already-broken tree. A throw *here* is the second
    // throw that produces the white screen docs/v3/08 §2 exists to prevent.
    //
    // `Theme.of` is safe for that: unlike `MediaQuery.of` it does not assert on
    // a missing ancestor, it falls back to `_kFallbackTheme`
    // (flutter/src/material/theme.dart — `inheritedTheme?.theme.data ?? …`).
    // So this reads the real error colours when a theme exists and still
    // renders something legible when one does not.
    final scheme = Theme.of(context).colorScheme;
    final background = scheme.errorContainer;
    final foreground = scheme.onErrorContainer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 80 || constraints.maxWidth < 160;
        return Container(
          color: background,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          child: compact
              ? Icon(Icons.warning_amber_rounded, size: 16, color: foreground)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: foreground),
                    const SizedBox(height: 4),
                    Text(
                      'This panel failed to render.\nThe rest of the editor is unaffected.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: foreground),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
