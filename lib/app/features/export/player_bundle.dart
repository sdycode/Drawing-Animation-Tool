/// The copy-in player bundle: the files, and the archive a user downloads
/// (docs/v3/03 F11.2).
///
/// **Why an asset and not generated Dart source.** The bundle is ~290KB of
/// Dart. Embedding it as string literals would put every byte through the
/// compiler and into the app's own snapshot, for data that is never executed
/// here — it is only ever handed to the user. `tool/build_player.dart` writes
/// it as one JSON manifest instead, so the cost is an asset read on click.
///
/// One asset, not an asset directory: Flutter's asset declarations do not
/// recurse, so shipping the folder would mean a `pubspec.yaml` edit every time
/// the generator adds a file — a coupling that breaks silently, by omitting a
/// file from a download nobody re-checks.
library;

import 'dart:convert';

// `Uint8List` arrives with `services.dart`; a separate dart:typed_data import
// would be redundant.
import 'package:flutter/services.dart';

import 'zip.dart';

/// Where `tool/build_player.dart` writes the manifest.
const String kPlayerBundleAsset = 'assets/player_bundle.json';

/// The generated player, as `path -> contents`.
///
/// Throws [PlayerBundleException] rather than returning an empty map when the
/// asset is missing or malformed: an empty map would archive cleanly into a
/// valid, useless 22-byte zip, and the user would discover that after copying
/// it into their project.
Future<Map<String, String>> loadPlayerBundle(AssetBundle bundle) async {
  final String raw;
  try {
    raw = await bundle.loadString(kPlayerBundleAsset);
  } catch (_) {
    throw const PlayerBundleException(
      'The player bundle asset is missing. Run '
      '`dart run tool/build_player.dart` and rebuild.',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    throw PlayerBundleException('The player bundle is not valid JSON: ${e.message}');
  }
  if (decoded is! Map<String, Object?> || decoded.isEmpty) {
    throw const PlayerBundleException('The player bundle is empty or malformed.');
  }

  final files = <String, String>{};
  decoded.forEach((path, contents) {
    if (contents is! String) {
      throw PlayerBundleException('The player bundle entry "$path" is not text.');
    }
    files[path] = contents;
  });
  return files;
}

/// The bundle as a `.zip`, with every path under a single `anim_player/` root.
///
/// The root directory is not cosmetic: unzipping into `lib/` must produce
/// `lib/anim_player/...` and not 26 loose files among the user's own, which is
/// an unpleasant thing to undo by hand.
Uint8List buildPlayerZip(Map<String, String> files) => buildZip({
      for (final e in files.entries) 'anim_player/${e.key}': e.value,
    });

/// A bundle problem worth telling the user about, rather than shipping a
/// silently incomplete archive.
class PlayerBundleException implements Exception {
  const PlayerBundleException(this.message);
  final String message;

  @override
  String toString() => message;
}
