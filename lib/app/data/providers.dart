import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dev_credentials.dart';
import 'auth_service.dart';
import 'firebase_auth_service.dart';
import 'firebase_options.dart';
import 'firestore_project_store.dart';
import 'memory_project_store.dart';
import 'project_store.dart';

/// The one place implementations are chosen (docs/v3/04 §2).
///
/// Selected at **build time**, not runtime:
/// ```bash
/// flutter run --dart-define=BACKEND=firestore   # v1, default
/// flutter run --dart-define=BACKEND=memory      # no network, no auth
/// flutter run --dart-define=BACKEND=api         # v1.1, Go service — not built yet
/// ```
/// Compile-time means the unused implementation tree-shakes out. It is also the
/// only flag docs/v3/08 §5 considers worth having — a runtime flag registry
/// ships every path in the bundle and is the framework-first trap.
const kBackend = String.fromEnvironment('BACKEND', defaultValue: 'firestore');

bool get kUsesFirebase => kBackend == 'firestore';

/// Called from `main()` before `runApp`. Keeps `firebase_core` out of
/// `main.dart` so the boundary check stays honest.
Future<void> initBackend() async {
  if (!kUsesFirebase) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Offline persistence (AC-10.3.2): set once here, before any store read/write,
  // so edits made offline queue and flush on reconnect. Assigning `settings` is
  // the modern, non-deprecated replacement for `enablePersistence()`.
  configureFirestorePersistence();
  // Before runApp: the auth gate reads the stream on the first frame, and the
  // restored session must already be on its way by then.
  await configureAuthPersistence();
}

final authServiceProvider = Provider<AuthService>((ref) {
  // The memory backend has no accounts, so the pre-filled form would bounce off
  // `user-not-found`. Seed the same credentials it offers.
  if (!kUsesFirebase) {
    return FakeAuthService(
      accounts: kDevPrefill ? {kDevEmail: kDevPassword} : null,
    );
  }
  return FirebaseAuthService();
});

/// Null while signing in, and while the very first auth state is still unknown.
final authStateProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// The store is per-user, because `uid` is what scopes the Firestore path.
/// Reading it while signed out is a programming error, not a runtime condition
/// — the auth gate guarantees a user exists before any feature asks for it.
final projectStoreProvider = Provider<ProjectStore>((ref) {
  if (!kUsesFirebase) return MemoryProjectStore();

  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) {
    throw StateError(
      'projectStoreProvider read while signed out. The auth gate in '
      'app_shell.dart must render a signed-in screen before any feature '
      'reaches the store.',
    );
  }
  return FirestoreProjectStore(uid: uid);
});
