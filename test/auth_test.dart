import 'package:drawing_animation_tool/app/data/auth_service.dart';
import 'package:drawing_animation_tool/app/dev_credentials.dart';
import 'package:drawing_animation_tool/app/data/providers.dart';
import 'package:drawing_animation_tool/app/features/auth/sign_in_controller.dart';
import 'package:drawing_animation_tool/app/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Auth is testable without Firebase because the UI depends on the
/// `AuthService` interface, not on `firebase_auth` (docs/v3/08 §3).
void main() {
  late FakeAuthService auth;

  ProviderContainer containerWith(FakeAuthService a) => ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(a)],
      );

  setUp(() => auth = FakeAuthService());
  tearDown(() => auth.dispose());

  group('SignInController', () {
    test('sign-up then sign-in restores the same session', () async {
      final c = containerWith(auth);
      addTearDown(c.dispose);
      final ctrl = c.read(signInControllerProvider.notifier);

      ctrl.toggleMode(); // -> signUp
      await ctrl.submit(email: 'a@b.com', password: 'secret1');
      expect(auth.currentUser?.email, 'a@b.com');

      await auth.signOut();
      expect(auth.currentUser, isNull);

      ctrl.toggleMode(); // back to signIn
      await ctrl.submit(email: 'a@b.com', password: 'secret1');
      expect(auth.currentUser?.email, 'a@b.com');
    });

    // AC-10.0.4 — every failure renders a distinct message, never a raw
    // exception string.
    test('maps each failure to a distinct user-facing message', () async {
      final c = containerWith(auth);
      addTearDown(c.dispose);
      final ctrl = c.read(signInControllerProvider.notifier);

      await ctrl.submit(email: 'nope', password: 'secret1');
      expect(
          c.read(signInControllerProvider).failure, AuthFailure.invalidEmail);

      await ctrl.submit(email: 'a@b.com', password: '123');
      expect(
          c.read(signInControllerProvider).failure, AuthFailure.weakPassword);

      await ctrl.submit(email: 'ghost@b.com', password: 'secret1');
      expect(
          c.read(signInControllerProvider).failure, AuthFailure.userNotFound);

      ctrl.toggleMode();
      await ctrl.submit(email: 'a@b.com', password: 'secret1');
      await ctrl.submit(email: 'a@b.com', password: 'secret1');
      expect(c.read(signInControllerProvider).failure,
          AuthFailure.emailAlreadyInUse);

      ctrl.toggleMode();
      await ctrl.submit(email: 'a@b.com', password: 'wrongpass');
      expect(
          c.read(signInControllerProvider).failure, AuthFailure.wrongPassword);

      // Distinctness is the actual guarantee: identical copy for two different
      // causes is the bug this test exists to catch.
      final messages = AuthFailure.values.map((f) => f.message).toSet();
      // wrongPassword and userNotFound intentionally share copy (anti-user-
      // enumeration), so expect exactly one collision.
      expect(messages.length, AuthFailure.values.length - 1);
    });

    // Two audiences, two messages. The user must never see a provider string;
    // the developer must never be left with only "Something went wrong".
    test('keeps the raw provider code alongside the friendly message', () {
      const e = AuthException(
        AuthFailure.unknown,
        code: 'operation-not-allowed',
        details: 'Password sign-in is disabled for this project.',
      );

      expect(e.failure.message, 'Something went wrong. Please try again.');
      expect(e.technical, contains('operation-not-allowed'));
      expect(e.technical, contains('disabled for this project'));
      // toString is what the copy button puts on the clipboard.
      expect(e.toString(), contains('operation-not-allowed'));
    });

    test('clearError wipes a stale message once the user edits', () async {
      final c = containerWith(auth);
      addTearDown(c.dispose);
      final ctrl = c.read(signInControllerProvider.notifier);

      await ctrl.submit(email: 'nope', password: 'secret1');
      expect(c.read(signInControllerProvider).failure, isNotNull);

      ctrl.clearError();
      expect(c.read(signInControllerProvider).failure, isNull);
    });
  });

  group('SignInScreen', () {
    Widget harness(FakeAuthService a) => ProviderScope(
          overrides: [authServiceProvider.overrideWithValue(a)],
          child: const MaterialApp(home: SignInScreen()),
        );

    testWidgets('offers no social buttons and no password reset (AC-10.0.5)',
        (tester) async {
      await tester.pumpWidget(harness(auth));

      for (final banned in const [
        'Google',
        'GitHub',
        'Forgot',
        'forgot',
        'Reset',
        'Continue as guest',
      ]) {
        expect(find.textContaining(banned), findsNothing,
            reason: '$banned is a v1 non-goal (docs/v3/00 §4)');
      }
    });

    testWidgets('shows an inline error, not a dialog', (tester) async {
      await tester.pumpWidget(harness(auth));

      await tester.enterText(
          find.byType(TextFormField).first, 'ghost@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'secret1');
      // widgetWithText, not find.text: 'Sign in' also appears as the subtitle.
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth-error')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shows the raw provider detail in debug builds',
        (tester) async {
      await tester.pumpWidget(harness(auth));

      await tester.enterText(
          find.byType(TextFormField).first, 'ghost@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'secret1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      // Tests run in debug, so the panel is present. In release `kDebugMode` is
      // a const false and the whole widget tree-shakes away.
      expect(find.byKey(const Key('auth-error-technical')), findsOneWidget);
    });

    // Tests run in debug, so the prefill is live here. The release build folds
    // `kDevPrefill` to false and tree-shakes the literals — not observable from
    // a test, which is exactly why the flag is a compile-time const and not a
    // runtime setting that could be flipped on in production.
    testWidgets('pre-fills the dev account in debug builds', (tester) async {
      await tester.pumpWidget(harness(auth));

      expect(kDevPrefill, isTrue);
      expect(find.text(kDevEmail), findsOneWidget);
      expect(find.byKey(const Key('dev-prefill-banner')), findsOneWidget);

      // Submitting untouched must reach the service, not bounce off local
      // validation — the whole point is one click to a signed-in state.
      await auth.signUp(email: kDevEmail, password: kDevPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('auth-error')), findsNothing);
      expect(auth.currentUser?.email, kDevEmail);
    });

    testWidgets('toggles between sign in and sign up', (tester) async {
      await tester.pumpWidget(harness(auth));
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);

      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();
      expect(
          find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
    });
  });
}
