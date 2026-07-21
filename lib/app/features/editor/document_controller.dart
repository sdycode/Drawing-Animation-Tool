import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../data/providers.dart';

/// Owns the open document and nothing else (docs/v3/04 §4).
///
/// Selection, hover, the playhead and the viewport are **not** here — they are
/// ephemeral editor state, and persisting them is the legacy defect that made
/// documents unloadable (AC-2.2.7). This controller holds only what round-trips
/// to storage.
///
/// `Async` because the first thing it does is await IO (docs/v3/08 §2): the UI
/// consumes it with `.when`, so a failed load renders an error state instead of
/// throwing at every `ref.watch`.
class DocumentController
    extends AutoDisposeFamilyAsyncNotifier<Document, String> {
  @override
  Future<Document> build(String projectId) async {
    final raw = await ref.read(projectStoreProvider).load(projectId);
    if (raw == null) {
      throw const StoreException(StoreFailure.notFound);
    }
    try {
      return Document.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on StoreException {
      rethrow;
    } on Object catch (e) {
      // Anything undecodable is corrupt, not "unknown" — the user gets a real
      // sentence and the developer gets the raw reason.
      throw StoreException(StoreFailure.corrupt, details: '$e');
    }
  }

  Document get _document => state.requireValue;

  /// Appends a node to the root and persists.
  ///
  /// M0 has no `NodeOps` and no undo stack; both arrive at M2. The shape of the
  /// call is already right, though: a mutation produces a **new** `Document`
  /// rather than editing one in place, which is what makes snapshot undo a
  /// later addition instead of a rewrite.
  Future<void> addNode(Node node) async {
    final doc = _document;
    final next = doc.copyWith(
      root: doc.root.copyWith(children: [...doc.root.children, node]),
    );
    await _save(next);
  }

  Future<void> rename(String name) => _save(_document.copyWith(name: name));

  /// `rev` advances here and nowhere else, because this is the only place a
  /// write actually reaches storage (docs/v3/01 §11).
  Future<void> _save(Document next) async {
    final saved = next.bumpRev();
    await ref
        .read(projectStoreProvider)
        .save(saved.id, jsonEncode(saved.toJson()));
    state = AsyncData(saved);
  }
}

final documentControllerProvider = AsyncNotifierProvider.autoDispose
    .family<DocumentController, Document, String>(DocumentController.new);
