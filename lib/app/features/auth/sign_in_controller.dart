import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_service.dart';
import '../../data/providers.dart';

enum AuthMode { signIn, signUp }

class SignInState {
  const SignInState({
    this.mode = AuthMode.signIn,
    this.busy = false,
    this.error,
  });

  final AuthMode mode;
  final bool busy;

  /// Null when there is nothing to show.
  ///
  /// The whole exception is kept, not just the enum: the user sees
  /// `failure.message` (never a provider string, AC-10.4), while a debug build
  /// also shows `error.technical` so an unmapped code is diagnosable instead of
  /// hiding behind "Something went wrong".
  final AuthException? error;

  AuthFailure? get failure => error?.failure;

  SignInState copyWith({AuthMode? mode, bool? busy, AuthException? error}) =>
      SignInState(
        mode: mode ?? this.mode,
        busy: busy ?? this.busy,
        error: error,
      );
}

/// Owns only the sign-in *form*. Session state lives in `authStateProvider`;
/// this controller never stores the user, so a stale copy cannot desync from
/// the real auth state.
class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  void toggleMode() => state = SignInState(
        mode: state.mode == AuthMode.signIn ? AuthMode.signUp : AuthMode.signIn,
      );

  /// Clears the previous error as soon as the user edits, so a stale message
  /// never sits under a field they have already fixed.
  void clearError() {
    if (state.error != null) state = state.copyWith(error: null);
  }

  Future<void> submit({required String email, required String password}) async {
    if (state.busy) return; // double-submit guard
    state = state.copyWith(busy: true, error: null);

    final auth = ref.read(authServiceProvider);
    try {
      if (state.mode == AuthMode.signUp) {
        await auth.signUp(email: email, password: password);
      } else {
        await auth.signIn(email: email, password: password);
      }
      // On success the auth stream drives navigation. Nothing to do here.
      state = state.copyWith(busy: false);
    } on AuthException catch (e) {
      state = state.copyWith(busy: false, error: e);
    }
  }
}

final signInControllerProvider =
    NotifierProvider<SignInController, SignInState>(SignInController.new);
