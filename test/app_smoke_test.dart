import 'package:drawing_animation_tool/app/app_shell.dart';
import 'package:drawing_animation_tool/app/common/theme.dart';
import 'package:drawing_animation_tool/app/data/auth_service.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('auth gate', () {
    late FakeAuthService auth;
    setUp(() => auth = FakeAuthService());
    tearDown(() => auth.dispose());

    Widget harness() => ProviderScope(
          overrides: [authServiceProvider.overrideWithValue(auth)],
          child: const DrawingAnimationToolApp(),
        );

    testWidgets('signed out -> sign-in screen', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(find.text('Projects'), findsNothing);
    });

    testWidgets('signed in -> project list, and sign-out returns to the form',
        (tester) async {
      await auth.signUp(email: 'a@b.com', password: 'secret1');

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('a@b.com'), findsOneWidget);

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-out-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sign-out-confirm')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('sign-out cancel leaves the user signed in', (tester) async {
      await auth.signUp(email: 'a@b.com', password: 'secret1');

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-out-cancel')));
      await tester.pumpAndSettle();

      // Asserts the SESSION survived, not merely that the dialog closed — a
      // dialog that dismisses while still signing out would pass the weaker
      // check.
      expect(find.byKey(const Key('sign-out-dialog')), findsNothing);
      expect(auth.currentUser, isNotNull);
      expect(find.text('Projects'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);
    });
  });

  group('theme', () {
    late FakeAuthService auth;
    setUp(() => auth = FakeAuthService());
    tearDown(() => auth.dispose());

    Widget harness() => ProviderScope(
          overrides: [authServiceProvider.overrideWithValue(auth)],
          child: const DrawingAnimationToolApp(),
        );

    // Reads the brightness actually handed to widgets, not the provider value:
    // a themeMode wired to the wrong MaterialApp slot would pass a provider
    // assertion and still render the wrong theme.
    Brightness renderedBrightness(WidgetTester tester) =>
        Theme.of(tester.element(find.text('Projects'))).brightness;

    testWidgets('defaults to dark', (tester) async {
      await auth.signUp(email: 'a@b.com', password: 'secret1');
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(renderedBrightness(tester), Brightness.dark);
    });

    testWidgets('toggle switches to light and back', (tester) async {
      await auth.signUp(email: 'a@b.com', password: 'secret1');
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('theme-toggle')));
      await tester.pumpAndSettle();
      expect(renderedBrightness(tester), Brightness.light);

      await tester.tap(find.byKey(const Key('theme-toggle')));
      await tester.pumpAndSettle();
      expect(renderedBrightness(tester), Brightness.dark);
    });

    testWidgets('adopts the stored preference on start', (tester) async {
      await auth.signUp(email: 'a@b.com', password: 'secret1');
      final store = MemoryThemeStore();
      await store.write(ThemeMode.light);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(auth),
            themeStoreProvider.overrideWithValue(store),
          ],
          child: const DrawingAnimationToolApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(renderedBrightness(tester), Brightness.light);
    });
  });

  group('FeatureFallback', () {
    // docs/v3/08 §2: the default ErrorWidget takes unbounded size, so inside a
    // Row it throws AGAIN during layout — that second throw is the white screen.
    // These two tests pin the property that makes containment actually work.
    final details = FlutterErrorDetails(exception: Exception('boom'));

    testWidgets('survives tight constraints inside a Row', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              SizedBox(
                width: 40,
                height: 30,
                child: FeatureFallback(details: details),
              ),
              const Expanded(child: Text('sibling still renders')),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('sibling still renders'), findsOneWidget);
    });

    testWidgets('survives an unbounded-height column slot', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SizedBox(
                width: 300,
                height: 200,
                child: FeatureFallback(details: details),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
