import 'package:flutter/material.dart';

/// The one file that composes panels (docs/v3/08 §3).
///
/// At M0 there are no panels yet — this is the deploy-first placeholder. It
/// grows a `Row` of feature widgets from M2 onward, and stays the *only* place
/// features are wired together, so deleting a feature is one line here plus one
/// folder (docs/v3/08 §5).
class DrawingAnimationToolApp extends StatelessWidget {
  const DrawingAnimationToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drawing Animation Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const _M0Placeholder(),
    );
  }
}

class _M0Placeholder extends StatelessWidget {
  const _M0Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Drawing Animation Tool',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('v3 · M0 walking skeleton',
                style: TextStyle(fontSize: 14, color: Colors.white54)),
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
