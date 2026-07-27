import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drawing_animation_tool/app/data/firestore_project_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// AC-10.3.2 — Firestore offline-persistence wiring.
///
/// The observable effect (an IndexedDB cache that queues offline edits and
/// flushes them on reconnect) needs a live Firestore/emulator, which a unit
/// test has no network for — and building a real [FirebaseFirestore] needs an
/// initialised Firebase app. What *is* testable without either, and what
/// actually protects the app, is the wiring itself: offline persistence is
/// requested, the settings are applied exactly once, and a repeat call is a
/// no-op (a second `settings` assignment after first use would throw).
void main() {
  setUp(debugResetFirestorePersistence);

  test('requests offline persistence and applies it exactly once', () {
    final applied = <Settings>[];
    configureFirestorePersistence(applySettings: applied.add);
    configureFirestorePersistence(applySettings: applied.add);

    expect(applied, hasLength(1), reason: 'settings must be applied once');
    expect(applied.single.persistenceEnabled, isTrue);
    expect(applied.single.cacheSizeBytes, Settings.CACHE_SIZE_UNLIMITED);
  });

  test('resetting the guard lets it apply again (a fresh boot)', () {
    var calls = 0;
    configureFirestorePersistence(applySettings: (_) => calls++);
    debugResetFirestorePersistence();
    configureFirestorePersistence(applySettings: (_) => calls++);

    expect(calls, 2);
  });
}
