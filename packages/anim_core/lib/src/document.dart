/// The document root (docs/v3/01 §11, docs/v3/02 §3.1).
library;

import 'json.dart';
import 'node.dart';
import 'primitives.dart';
import 'uuid.dart';

/// Thrown when decoded bytes violate an invariant the model guarantees.
///
/// Carries a `path` because "invalid document" with no location is what makes a
/// corrupt file unfixable. The strict decoder proper arrives at M1; this is the
/// one invariant that cannot wait, since the whole keyframe join rests on it.
class DocumentException implements Exception {
  const DocumentException(this.message, {this.path});

  final String message;
  final String? path;

  @override
  String toString() =>
      'DocumentException(${path == null ? '' : '$path: '}$message)';
}

final class Document {
  const Document({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.name,
    required this.artboard,
    this.background = Rgba.transparent,
    required this.root,
    this.rev = 0,
    this.unknownKeys = const {},
  });

  static const int currentSchemaVersion = 3;

  final int schemaVersion;

  /// UUID v4.
  final String id;

  /// Display name. **Not** an identity — two projects may share one.
  final String name;

  /// Document size in units. Origin is top-left, y-down.
  final Vec2 artboard;

  final Rgba background;

  final GroupNode root;

  /// Monotonic save counter, incremented by exactly 1 on every **persisted**
  /// save — never on an in-memory edit, never on undo.
  ///
  /// The only persisted field the evaluator never reads: it is save metadata,
  /// so it lives here (it must survive reload) but sits outside every
  /// evaluation stage. v1 writes and round-trips it; v1.1 turns this same field
  /// into optimistic concurrency, which is what detects the two-tab clobber.
  final int rev;

  /// Forward-compat passthrough (docs/v3/02 §7).
  ///
  /// **`animations` and `defaultAnimationId` currently live in here.** They are
  /// real spec'd fields with no Dart type yet — tracks land at M4 — so rule 6
  /// carries them through byte-for-byte instead of the decoder dropping them.
  /// When `Animation` is modelled, they move to typed fields and out of this
  /// map; `document_test.dart` pins the preservation so the interim cannot
  /// quietly lose an animation authored by a newer build.
  final Map<String, Object?> unknownKeys;

  /// A newer document opens **read-only** and every save path is disabled.
  ///
  /// Key preservation protects syntax, not semantics: a v3 client cannot know
  /// that a v4 `skin` field must stay consistent with the anchors it just let
  /// the user delete.
  bool get isReadOnly => schemaVersion > currentSchemaVersion;

  /// A fresh, empty document with an explicit artboard.
  ///
  /// The artboard is explicit from day one because legacy inferred it from
  /// whatever the first canvas happened to measure, so the same file rendered
  /// at different proportions on different screens.
  factory Document.create({
    required String name,
    Vec2 artboard = const Vec2(450.2, 250.4),
    Rgba background = Rgba.transparent,
  }) =>
      Document(
        id: uuidV4(),
        name: name,
        artboard: artboard,
        background: background,
        root: GroupNode(id: NodeId(uuidV4()), name: 'Root'),
      );

  Document copyWith({
    String? name,
    Vec2? artboard,
    Rgba? background,
    GroupNode? root,
    int? rev,
  }) =>
      Document(
        schemaVersion: schemaVersion,
        id: id,
        name: name ?? this.name,
        artboard: artboard ?? this.artboard,
        background: background ?? this.background,
        root: root ?? this.root,
        rev: rev ?? this.rev,
        unknownKeys: unknownKeys,
      );

  /// The one place `rev` advances. Called by the store on a successful write,
  /// never by an editing command.
  Document bumpRev() => copyWith(rev: rev + 1);

  static const _known = <String>{
    'schemaVersion',
    'id',
    'name',
    'rev',
    'artboard',
    'background',
    'root',
  };

  factory Document.fromJson(Map<String, Object?> j) {
    final doc = Document(
      schemaVersion: i(j['schemaVersion']),
      id: j['id']! as String,
      name: opt(j, 'name', (v) => v as String, ''),
      artboard: Vec2.fromJson(j['artboard']),
      background: opt(j, 'background', Rgba.fromJson, Rgba.transparent),
      root: GroupNode.fromJson(j['root']! as Map<String, Object?>),
      // Absent means written before `rev` existed, which is generation 1 — not
      // 0. A fresh in-memory document starts at 0 and reaches 1 on its first
      // persisted save, so both paths agree on what "saved once" means.
      rev: opt(j, 'rev', i, 1),
      unknownKeys: unknownKeysOf(j, _known),
    );
    doc.validate();
    return doc;
  }

  Map<String, Object?> toJson() => withUnknown(unknownKeys, {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'rev': rev,
        'artboard': artboard.toJson(),
        'background': background.toJson(),
        'root': root.toJson(),
      });

  /// Walks the tree depth-first in paint order.
  Iterable<Node> walk() sync* {
    Iterable<Node> visit(Node n) sync* {
      yield n;
      if (n is GroupNode) {
        for (final c in n.children) {
          yield* visit(c);
        }
      }
    }

    yield* visit(root);
  }

  /// `NodeId` → node, rebuilt on demand and **never persisted**.
  ///
  /// Derived state (docs/v3/01 §11): the tree is the single source of truth for
  /// hierarchy, and this index exists only to make track lookup O(1). M2
  /// memoises it per mutation; at M0 there is nothing to memoise against.
  Map<NodeId, Node> get nodeIndex => {for (final n in walk()) n.id: n};

  /// `NodeId` is unique within a `Document` — governing rule 2 (docs/v3/01 §1).
  ///
  /// Checked at decode rather than trusted: every track lookup and every future
  /// cross-tree reference joins on this id, so a duplicate does not fail loudly
  /// at load, it silently animates the wrong node.
  void validate() {
    final seen = <String>{};
    for (final n in walk()) {
      if (!seen.add(n.id.v)) {
        throw DocumentException('duplicate NodeId "${n.id.v}"',
            path: 'root/${n.name}');
      }
    }
  }
}
