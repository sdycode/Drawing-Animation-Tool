import 'package:anim_render/anim_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_shell.dart';
import 'app/common/theme.dart';
import 'app/data/prefs_theme_store.dart';
import 'app/data/providers.dart';
import 'app/features/tools/registry.dart';
import 'app/state/tool_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A dead feature must not take the editor with it (docs/v3/08 §2). The
  // default ErrorWidget is unconstrained, so inside a Row it throws again
  // during layout — that is the literal white screen.
  ErrorWidget.builder = (details) => FeatureFallback(details: details);

  // The painters contain a per-item failure and report it here (docs/v3/08 §1).
  // Installing a sink is a HANDSHAKE, not a courtesy: `RenderFaults.report`
  // returns false when nobody is listening, and the call site asserts on that,
  // so an app with no sink screams in debug rather than losing one node in
  // silence. Reporting is all this does — it must not draw a modal, because a
  // dialog per frame is the legacy behaviour that made a single bad gradient
  // impossible to click past.
  RenderFaults.sink = (fault) => debugPrint('render fault: $fault');

  // Backend chosen at build time; Firebase is initialised inside the data layer
  // so `main.dart` imports no persistence package (docs/v3/08 §3).
  //
  // NOT wrapped in a swallowing try/catch: the legacy app continued booting
  // into a broken state after a failed Firebase init, which turned one clear
  // startup error into an unexplainable app.
  await initBackend();

  // The real theme store is injected here, so `common/theme.dart` imports no
  // plugin and a widget test builds the whole app with the in-memory default.
  //
  // The tool registry is injected for the same reason, and it is what keeps the
  // dependency arrow pointing one way: `state/tool_controller.dart` owns the
  // `ToolMode` contract and imports nothing from `features/`, while
  // `features/tools` supplies the implementations here at composition. Without
  // this override the controller resolves to an inert tool — total, and
  // behaviourally identical while nothing calls the pointer handlers — so a
  // widget test that drives a real tool (M3, once the pen and shape tools have
  // handlers) must install this same override.
  runApp(
    ProviderScope(
      overrides: [
        themeStoreProvider.overrideWithValue(PrefsThemeStore()),
        toolResolverProvider.overrideWithValue(resolveTool),
      ],
      child: const DrawingAnimationToolApp(),
    ),
  );
}
