/// The one entry point for "save these bytes to the user's disk" (docs/v3/03
/// F11.1, docs/v3/05 §4.10).
///
/// Contract, provided by whichever implementation is linked:
///
/// ```dart
/// void downloadJson(String filename, String contents);
/// ```
///
/// The conditional export is what keeps `package:web`/`dart:js_interop` out of
/// the VM: `flutter test` links `download_json_stub.dart` (those libraries are
/// absent there and would fail to load), while `flutter build web` links
/// `download_json_web.dart`, the real Blob + object-URL + anchor-click save-as.
/// Nothing else in `lib/` may import `package:web` directly — this trio is the
/// whole web surface.
library;

export 'download_json_stub.dart'
    if (dart.library.js_interop) 'download_json_web.dart';
