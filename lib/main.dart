import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_shell.dart';
import 'app/data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A dead feature must not take the editor with it (docs/v3/08 §2). The
  // default ErrorWidget is unconstrained, so inside a Row it throws again
  // during layout — that is the literal white screen.
  ErrorWidget.builder = (details) => FeatureFallback(details: details);

  // Backend chosen at build time; Firebase is initialised inside the data layer
  // so `main.dart` imports no persistence package (docs/v3/08 §3).
  //
  // NOT wrapped in a swallowing try/catch: the legacy app continued booting
  // into a broken state after a failed Firebase init, which turned one clear
  // startup error into an unexplainable app.
  await initBackend();

  runApp(const ProviderScope(child: DrawingAnimationToolApp()));
}
