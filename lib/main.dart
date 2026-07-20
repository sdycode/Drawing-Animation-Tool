import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_shell.dart';

/// M0 step 1 — deploy first (docs/v3/06 M0).
///
/// This is deliberately a hello-world. Hosting, base href and CanvasKit loading
/// are the highest-variance part of M0 and the only part that cannot be
/// unit-tested; proving them on a public URL before any domain code means every
/// later commit is deployable.
void main() {
  // A dead feature must not take the editor with it (docs/v3/08 §2). The
  // default ErrorWidget is unconstrained, so inside a Row it throws again
  // during layout — that is the literal white screen.
  ErrorWidget.builder = (details) => FeatureFallback(details: details);

  runApp(const ProviderScope(child: DrawingAnimationToolApp()));
}
