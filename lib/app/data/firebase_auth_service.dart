import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Keep the session across reloads, tab closes, and browser restarts — the
/// mobile-app behaviour, on web.
///
/// Firebase stores the refresh token in IndexedDB under [fb.Persistence.LOCAL]
/// and silently mints a new ID token on boot, which is why `authStateChanges()`
/// re-emits the signed-in user with no password prompt. LOCAL is already the
/// web default; stating it means a changed upstream default (or a stray
/// `SESSION` elsewhere) cannot quietly start signing everyone out on refresh.
///
/// Native platforms persist unconditionally and reject `setPersistence`, hence
/// the [kIsWeb] guard.
Future<void> configureAuthPersistence() async {
  if (!kIsWeb) return;
  await fb.FirebaseAuth.instance.setPersistence(fb.Persistence.LOCAL);
}

/// Firebase-backed [AuthService]. The only file that knows `firebase_auth`
/// exists (docs/v3/08 §3).
///
/// Its whole job is to translate: Firebase error codes in, [AuthFailure] out.
/// Nothing above this layer ever sees a `FirebaseAuthException`, so the UI
/// cannot accidentally render a provider error string at the user.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService([fb.FirebaseAuth? auth])
      : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  static AuthUser? _toUser(fb.User? u) =>
      u == null ? null : AuthUser(uid: u.uid, email: u.email ?? '');

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_toUser);

  /// Firebase code -> our closed set.
  ///
  /// `invalid-credential` is what modern Firebase returns instead of
  /// `wrong-password` / `user-not-found` when email enumeration protection is
  /// on (the default for new projects) — mapping it is why a correct password
  /// typo shows "Incorrect email or password" rather than "Something went
  /// wrong".
  static AuthFailure _map(String code) => switch (code) {
        'invalid-email' => AuthFailure.invalidEmail,
        'weak-password' => AuthFailure.weakPassword,
        'email-already-in-use' => AuthFailure.emailAlreadyInUse,
        'wrong-password' || 'invalid-credential' => AuthFailure.wrongPassword,
        'user-not-found' || 'user-disabled' => AuthFailure.userNotFound,
        'network-request-failed' => AuthFailure.network,
        'operation-not-allowed' => AuthFailure.notEnabled,
        _ => AuthFailure.unknown,
      };

  Future<void> _run(Future<void> Function() op) async {
    try {
      await op();
    } on fb.FirebaseAuthException catch (e, st) {
      // Always log the raw provider error. A mapped-to-`unknown` failure with
      // no trace of what actually happened is undebuggable, and `unknown` is
      // by definition the case where the mapping above fell short.
      debugPrint('[auth] FirebaseAuthException ${e.code}: ${e.message}');
      if (_map(e.code) == AuthFailure.unknown) {
        debugPrint('[auth] UNMAPPED code "${e.code}" — add it to _map()');
        debugPrintStack(stackTrace: st, maxFrames: 6);
      }
      throw AuthException(_map(e.code), code: e.code, details: e.message);
    } catch (e, st) {
      debugPrint('[auth] non-Firebase failure: $e');
      debugPrintStack(stackTrace: st, maxFrames: 6);
      throw AuthException(
        AuthFailure.unknown,
        code: e.runtimeType.toString(),
        details: '$e',
      );
    }
  }

  @override
  Future<void> signUp({required String email, required String password}) =>
      _run(() => _auth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          ));

  @override
  Future<void> signIn({required String email, required String password}) =>
      _run(() => _auth.signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          ));

  @override
  Future<void> signOut() => _run(_auth.signOut);
}
