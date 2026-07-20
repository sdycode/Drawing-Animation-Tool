/// The authentication seam.
///
/// v1 is Firebase **email/password and nothing else** — no social providers, no
/// anonymous auth, no password reset, no email verification (docs/v3/00 §4).
/// Anonymous was rejected outright: it mints a new uid per browser and per
/// data-clear, scattering one person's work across orphaned accounts.
///
/// The UI depends on this interface, never on `firebase_auth`, so the whole
/// sign-in flow is testable with [FakeAuthService] and no network.
library;

import 'dart:async';

/// A signed-in user. `uid` is what scopes every Firestore path.
class AuthUser {
  const AuthUser({required this.uid, required this.email});

  final String uid;
  final String email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.uid == uid && other.email == email;

  @override
  int get hashCode => Object.hash(uid, email);
}

/// Every way authentication can fail, as a closed set.
///
/// Closed because the sign-in form must render a distinct inline message for
/// each (AC-10.0.4) — a raw exception string reaching the user is the failure
/// this enum exists to prevent.
enum AuthFailure {
  invalidEmail,
  weakPassword,
  emailAlreadyInUse,
  wrongPassword,
  userNotFound,
  network,
  notEnabled,
  unknown;

  /// Copy shown inline under the form field.
  String get message => switch (this) {
        invalidEmail => 'That does not look like a valid email address.',
        weakPassword => 'Password must be at least 6 characters.',
        emailAlreadyInUse => 'An account with this email already exists.',
        wrongPassword => 'Incorrect email or password.',
        userNotFound => 'Incorrect email or password.',
        network => 'Network unavailable. Check your connection and try again.',
        notEnabled => 'Email sign-in is not enabled for this project yet.',
        unknown => 'Something went wrong. Please try again.',
      };
}

class AuthException implements Exception {
  const AuthException(this.failure);
  final AuthFailure failure;

  @override
  String toString() => 'AuthException(${failure.name})';
}

abstract class AuthService {
  /// Emits the current user, then every change. Null means signed out.
  Stream<AuthUser?> authStateChanges();

  AuthUser? get currentUser;

  /// Throws [AuthException] on failure — never a raw provider exception.
  Future<void> signUp({required String email, required String password});

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}

/// In-memory implementation. Backs widget tests and any future offline mode;
/// keeps the M1 test suite from ever needing a network or a Firebase project.
class FakeAuthService implements AuthService {
  FakeAuthService({Map<String, String>? accounts})
      : _accounts = accounts ?? <String, String>{};

  final Map<String, String> _accounts; // email -> password
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _current;
  int _uidSeq = 0;

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  void _emit(AuthUser? user) {
    _current = user;
    _controller.add(user);
  }

  static void _validate(String email, String password) {
    if (!email.contains('@') || email.trim().isEmpty) {
      throw const AuthException(AuthFailure.invalidEmail);
    }
    if (password.length < 6) {
      throw const AuthException(AuthFailure.weakPassword);
    }
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    _validate(email, password);
    if (_accounts.containsKey(email)) {
      throw const AuthException(AuthFailure.emailAlreadyInUse);
    }
    _accounts[email] = password;
    _emit(AuthUser(uid: 'fake-uid-${_uidSeq++}', email: email));
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _validate(email, password);
    final stored = _accounts[email];
    if (stored == null) throw const AuthException(AuthFailure.userNotFound);
    if (stored != password) {
      throw const AuthException(AuthFailure.wrongPassword);
    }
    _emit(AuthUser(uid: 'fake-uid-$email', email: email));
  }

  @override
  Future<void> signOut() async => _emit(null);

  void dispose() => _controller.close();
}
