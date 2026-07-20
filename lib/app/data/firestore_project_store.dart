import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'project_store.dart';

/// Firestore-backed [ProjectStore] — the v1 implementation.
///
/// Layout (docs/v3/02 §9):
/// ```
/// appData/v3/users/{uid}/projects/{projectId}
/// ```
/// Legacy `users/` and `appData/v2` are **never read and never written**. That
/// isolation is the reason the old deployed app keeps working untouched while
/// v3 develops against the same Firebase project.
class FirestoreProjectStore implements ProjectStore {
  FirestoreProjectStore({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  /// The single chokepoint for path construction. Nothing else in the codebase
  /// builds a Firestore path, so the namespace cannot drift.
  static const _root = 'appData';
  static const _version = 'v3';

  CollectionReference<Map<String, dynamic>> get _projects => _db
      .collection(_root)
      .doc(_version)
      .collection('users')
      .doc(uid)
      .collection('projects');

  /// The document body is stored as one JSON string under `body`, so the bytes
  /// Firestore holds are byte-identical to what export writes. Firestore's
  /// int/double normalisation cannot touch a string, which sidesteps the
  /// numeric-hygiene trap in docs/v3/02 §6 entirely for the persistence path.
  static const _body = 'body';

  Future<T> _run<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on FirebaseException catch (e, st) {
      // Always log the raw error — a mapped-to-`unknown` failure with no trace
      // of what happened is undebuggable, and `unknown` is by definition where
      // the mapping fell short.
      debugPrint('[store] FirebaseException ${e.code}: ${e.message}');
      final failure = switch (e.code) {
        'permission-denied' => StoreFailure.permissionDenied,
        'not-found' => StoreFailure.notFound,
        'unavailable' || 'deadline-exceeded' => StoreFailure.network,
        _ => StoreFailure.unknown,
      };
      if (failure == StoreFailure.unknown) {
        debugPrint('[store] UNMAPPED code "${e.code}" — add it to _run()');
        debugPrintStack(stackTrace: st, maxFrames: 6);
      }
      throw StoreException(failure, code: e.code, details: e.message);
    } catch (e, st) {
      debugPrint('[store] non-Firebase failure: $e');
      debugPrintStack(stackTrace: st, maxFrames: 6);
      throw StoreException(
        StoreFailure.unknown,
        code: e.runtimeType.toString(),
        details: '$e',
      );
    }
  }

  @override
  Future<List<ProjectSummary>> list() => _run(() async {
        final snap = await _projects.get();
        return snap.docs.map((d) {
          final data = d.data();
          return ProjectSummary(
            id: d.id,
            name: (data['name'] as String?) ?? 'Untitled',
            rev: (data['rev'] as num?)?.toInt() ?? 0,
            updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
          );
        }).toList();
      });

  @override
  Future<String?> load(String id) => _run(() async {
        final doc = await _projects.doc(id).get();
        if (!doc.exists) return null;
        return doc.data()?[_body] as String?;
      });

  @override
  Future<void> save(String id, String json) => _run(() async {
        // Summary fields are denormalised projections of the body so `list()`
        // never has to decode every document. The body stays authoritative
        // (docs/v3/02 §9b) — if they ever disagree, the body wins.
        final decoded = jsonDecode(json);
        final map = decoded is Map<String, dynamic> ? decoded : const {};

        await _projects.doc(id).set({
          _body: json,
          'name': map['name'] ?? 'Untitled',
          'rev': map['rev'] ?? 0,
          'schemaVersion': map['schemaVersion'] ?? 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

  @override
  Future<void> delete(String id) => _run(() => _projects.doc(id).delete());
}
