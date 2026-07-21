import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../data/providers.dart';

/// The project list for the signed-in user.
///
/// `Async` because it awaits IO — docs/v3/08 §2 requires anything with an
/// `await` to be an `Async*` provider consumed with `.when`, so a throwing load
/// renders an error state instead of rethrowing at every `ref.watch` and
/// killing the tree.
final projectListProvider = FutureProvider<List<ProjectSummary>>((ref) async {
  return ref.watch(projectStoreProvider).list();
});

/// Writes. Kept off [projectListProvider] because a provider that both reads
/// and mutates would re-run its own read mid-write.
final projectActionsProvider = Provider<ProjectActions>(ProjectActions.new);

class ProjectActions {
  ProjectActions(this._ref);

  final Ref _ref;

  /// Creates an empty v3 document and persists it.
  ///
  /// `Document.create` mints a UUID and an **explicit** artboard — legacy
  /// inferred the artboard from whatever the first canvas happened to measure,
  /// so the same file rendered at different proportions on different screens.
  ///
  /// Returns the new id so the caller can navigate to it once an editor exists.
  Future<String> create({required String name}) async {
    // rev 0 means "never persisted". This save is generation 1, and `bumpRev`
    // is the only place the counter moves (docs/v3/01 §11).
    final doc = Document.create(name: name).bumpRev();
    await _ref
        .read(projectStoreProvider)
        .save(doc.id, jsonEncode(doc.toJson()));
    _ref.invalidate(projectListProvider);
    return doc.id;
  }

  Future<void> delete(String id) async {
    await _ref.read(projectStoreProvider).delete(id);
    _ref.invalidate(projectListProvider);
  }

  /// Reads a project back through the seam and decodes it.
  ///
  /// The only place the app proves stored bytes are a *decodable* v3 document
  /// rather than merely present. Null when the project is gone; a
  /// [StoreFailure.corrupt] [StoreException] when the bytes will not decode —
  /// the UI already renders that failure, and a raw `DocumentException`
  /// escaping the data layer would not be handled anywhere.
  Future<Document?> load(String id) async {
    final raw = await _ref.read(projectStoreProvider).load(id);
    if (raw == null) return null;
    try {
      return Document.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object catch (e) {
      throw StoreException(StoreFailure.corrupt, details: '$e');
    }
  }
}
