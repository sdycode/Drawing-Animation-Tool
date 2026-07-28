/// Non-web fallback for the browser save-as (docs/v3/03 F11.1, docs/v3/05 §4.10).
///
/// This is the implementation the **Dart VM** — and therefore `flutter test` —
/// links, because `dart:js_interop` is absent there. Pulling `package:web` in
/// directly would break every VM test in this repo, so the real Blob/anchor
/// download lives in `download_json_web.dart` behind the conditional export in
/// `download_json.dart`, and this stub stands in its place off-web.
///
/// It throws rather than silently no-ops: the app never reaches it (the seam is
/// `downloadJsonProvider`, overridden in tests and swapped for the web impl in
/// the browser build), so an actual call here means a wiring mistake worth
/// surfacing, not swallowing.
void downloadJson(String filename, String contents) {
  throw UnsupportedError(
    'downloadJson requires a browser (dart:js_interop). Off-web the download '
    'seam is provided by downloadJsonProvider — override it in a test or ship '
    'the web build, which links download_json_web.dart.',
  );
}
