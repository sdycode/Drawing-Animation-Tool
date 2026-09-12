/// The export feature's one seam (docs/v3/03 F11.1).
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_json.dart';

/// Save `contents` to the user's disk as `filename`.
typedef DownloadJson = void Function(String filename, String contents);

/// The browser save-as, behind a provider so the button's logic stays testable
/// on the VM.
///
/// The default is the conditionally-exported [downloadJson] — the web build's
/// real Blob/anchor download, and off-web a stub that throws. A widget test
/// overrides this with a capturing function, so it can tap Export and inspect
/// the exact bytes without a browser (AC-11.1.2). It is a plain `Provider`, not
/// tied to a project, because the download mechanism is the same everywhere.
final downloadJsonProvider = Provider<DownloadJson>((ref) => downloadJson);

/// Save arbitrary bytes to the user's disk as [filename].
typedef DownloadBytes = void Function(
    String filename, Uint8List bytes, String mimeType);

/// The binary twin of [downloadJsonProvider], for the player `.zip` (F11.2).
///
/// A separate provider rather than one generalized to bytes: the JSON export is
/// the feature with acceptance criteria on its exact bytes (AC-11.1.2), and a
/// test that overrides one download must not have to care about the other.
final downloadBytesProvider = Provider<DownloadBytes>((ref) => downloadBytes);
