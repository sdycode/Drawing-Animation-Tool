import 'dart:convert';

import 'project_store.dart';

/// In-memory [ProjectStore]. Backs widget tests and `BACKEND=memory` local runs.
///
/// Its real job is keeping the M1 test suite free of Firebase: because the seam
/// is String in / String out, a `Map<String, String>` is a complete, honest
/// implementation — no emulator, no network, no fakes to maintain.
class MemoryProjectStore implements ProjectStore {
  MemoryProjectStore([Map<String, String>? seed]) : _docs = {...?seed};

  final Map<String, String> _docs;

  /// Set to make the next operation throw — used to test the save-failure path
  /// without waiting for a real outage.
  StoreFailure? failNext;

  T _guard<T>(T Function() op) {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw StoreException(f);
    }
    return op();
  }

  @override
  Future<List<ProjectSummary>> list() async => _guard(() {
        return _docs.entries.map((e) {
          final decoded = jsonDecode(e.value);
          final map = decoded is Map<String, dynamic> ? decoded : const {};
          return ProjectSummary(
            id: e.key,
            name: (map['name'] as String?) ?? 'Untitled',
            rev: (map['rev'] as num?)?.toInt() ?? 0,
          );
        }).toList();
      });

  @override
  Future<String?> load(String id) async => _guard(() => _docs[id]);

  @override
  Future<void> save(String id, String json) async =>
      _guard(() => _docs[id] = json);

  @override
  Future<void> delete(String id) async => _guard(() => _docs.remove(id));
}
