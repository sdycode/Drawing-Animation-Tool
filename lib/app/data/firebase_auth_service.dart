import 'package:firebase_auth/firebase_auth.dart' as fb;

import 'auth_service.dart';

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
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(_map(e.code));
    } catch (_) {
      throw const AuthException(AuthFailure.unknown);
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
