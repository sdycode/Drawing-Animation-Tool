/// The persistence seam (docs/v3/04 §2, ADR: `ProjectStore` with String in/out).
///
/// **String in, String out — never `Map`.** That is the whole point: no
/// `cloud_firestore` type, and no storage-shaped `Map`, ever reaches the domain
/// layer. The payload is exactly the bytes `Document.toJson()` produces, which
/// is also exactly what file export writes. One wire contract, one code path.
///
/// This is what makes the v1.1 swap to Go + PostgreSQL a new *implementation*
/// rather than a migration: `HttpProjectStore` is added beside
/// `FirestoreProjectStore`, on the same branch, selected by
/// `--dart-define=BACKEND=` (docs/v3/07).
library;

/// Enough to render a project card without decoding the whole document.
///
/// These fields are denormalised projections of values inside the document
/// body; the body stays authoritative (docs/v3/02 §9b).
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.rev,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// Monotonic, incremented once per persisted save. v1 writes and reads it;
  /// v1.1 turns this same field into optimistic concurrency with no schema
  /// break (docs/v3/00 §3 item 19).
  final int rev;

  final DateTime? updatedAt;
}

/// Why a store operation failed. Closed set so the UI can show a real message
/// and the autosave loop can decide whether to retry (docs/v3/08 §2, last row).
enum StoreFailure {
  notFound,
  permissionDenied,
  network,

  /// The stored bytes are not decodable as a v3 document.
  corrupt,

  /// The document's `schemaVersion` is newer than this build reads, so it
  /// opened read-only and every save path is disabled (docs/v3/02 §1 rule 7).
  ///
  /// A store *failure* rather than a silent no-op because the write really did
  /// not happen and the user has to be told: key preservation protects syntax,
  /// not semantics, so saving would strip v4 fields this build cannot model —
  /// `unknownKeys` deliberately does not exist at `Anchor`, `PathData`, `Fill`,
  /// `Stroke` or `Transform2` level, and a v4 addition there is a version bump.
  readOnly,
  unknown;

  String get message => switch (this) {
        notFound => 'That project no longer exists.',
        permissionDenied => 'You do not have access to that project.',
        network => 'Network unavailable. Your work is still here — retrying.',
        corrupt => 'That project could not be read.',
        readOnly => 'This project was made by a newer version of the editor, '
            'so it is open read-only.',
        unknown => 'Could not reach storage. Your work is still here.',
      };
}

class StoreException implements Exception {
  const StoreException(this.failure, {this.code, this.details});

  final StoreFailure failure;

  /// The backend's raw error code, e.g. Firestore's `permission-denied`.
  final String? code;

  /// The backend's raw message, verbatim.
  final String? details;

  /// What a developer needs and [StoreFailure.message] deliberately hides.
  String get technical => [
        if (code != null) 'code: $code',
        if (details != null) details,
      ].join('\n');

  @override
  String toString() => 'StoreException(${failure.name}'
      '${code == null ? '' : ', $code'}'
      '${details == null ? '' : ': $details'})';
}

abstract class ProjectStore {
  Future<List<ProjectSummary>> list();

  /// Raw `jsonEncode` output, or null if the project does not exist.
  Future<String?> load(String id);

  Future<void> save(String id, String json);

  Future<void> delete(String id);
}
