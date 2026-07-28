import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
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

  /// Persists a caller-supplied [doc] as a brand-new project (F11.4, AC-11.4.2).
  ///
  /// The mirror of [create], but seeded from an already-built [Document] — an
  /// imported bundled sample — instead of `Document.create`. `LegacyImporter`
  /// already minted a fresh UUID on import, so this only turns rev 0 into
  /// generation 1 with the same `bumpRev` [create] uses and saves the bytes.
  /// The sample asset it came from is never touched here — the only read is in
  /// [loadSample] — so it stays byte-for-byte the golden fixture it ships as.
  ///
  /// Returns the new id so the caller opens THAT project, never the sample.
  Future<String> createFrom(Document doc) async {
    final seeded = doc.bumpRev();
    await _ref
        .read(projectStoreProvider)
        .save(seeded.id, jsonEncode(seeded.toJson()));
    _ref.invalidate(projectListProvider);
    return seeded.id;
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

/// A legacy fixture shipped in `assets/library/` and offered in the sample
/// gallery (F11.4, AC-11.4.1).
///
/// **The asset is read-only by construction.** Opening a sample imports it into
/// a fresh v3 [Document] and saves *that* as a new project
/// ([ProjectActions.createFrom]); the bundled file is only ever read
/// ([loadSample]), never written, so it stays the golden fixture F11.3 relies
/// on (AC-11.4.2).
class BundledSample {
  const BundledSample({required this.asset, required this.name});

  /// The `rootBundle` key, e.g. `assets/library/HomeMenu.json`.
  final String asset;

  /// A human-readable name derived from the file stem, e.g. `Home Menu`.
  final String name;
}

/// The file stems of the 8 bundled legacy fixtures (docs/v3/06 §190).
const _sampleStems = <String>[
  'HomeMenu',
  'MultiPolygon',
  'PlayPause',
  'PlayPause1',
  'Squares',
  'circlebounce',
  'circlebounce2',
  'circlebounce3',
];

/// The 8 bundled samples, in gallery order (AC-11.4.1).
final List<BundledSample> bundledSamples = <BundledSample>[
  for (final stem in _sampleStems)
    BundledSample(
      asset: 'assets/library/$stem.json',
      name: sampleFriendlyName(stem),
    ),
];

/// A display name derived from a sample file stem: split camelCase and
/// letter→digit boundaries into words and capitalise each. `HomeMenu` →
/// `Home Menu`, `PlayPause1` → `Play Pause 1`, `circlebounce2` →
/// `Circlebounce 2`.
String sampleFriendlyName(String stem) {
  final spaced = stem
      .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp('([A-Za-z])([0-9])'), (m) => '${m[1]} ${m[2]}');
  return spaced
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Loads a bundled [sample] and imports it into a fresh v3 [Document]
/// (AC-11.4.2).
///
/// The asset is only read — `rootBundle.loadString` cannot write — and
/// `LegacyImporter.import` mints a new UUID, so the returned document is a
/// brand-new project waiting to be persisted by [ProjectActions.createFrom].
/// [bundle] defaults to `rootBundle`; a test may pass its own.
Future<Document> loadSample(BundledSample sample, {AssetBundle? bundle}) async {
  final raw = await (bundle ?? rootBundle).loadString(sample.asset);
  return LegacyImporter.import(jsonDecode(raw) as Map<String, Object?>);
}
