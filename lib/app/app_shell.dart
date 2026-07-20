import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/projects/project_list_screen.dart';

/// The one file that composes panels (docs/v3/08 §3).
///
/// Deleting a feature stays one line here plus one folder — the compiler-checked
/// kill switch that docs/v3/08 §5 prefers over a feature-flag registry.
class DrawingAnimationToolApp extends StatelessWidget {
  const DrawingAnimationToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drawing Animation Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
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
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFEF9A9A)),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 80 || constraints.maxWidth < 160;
        return Container(
          color: const Color(0xFF3A1F1F),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          child: compact
              ? const Icon(Icons.warning_amber_rounded,
                  size: 16, color: Color(0xFFFFAB91))
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: Color(0xFFFFAB91)),
                    SizedBox(height: 4),
                    Text(
                      'This panel failed to render.\nThe rest of the editor is unaffected.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFFFFAB91)),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
