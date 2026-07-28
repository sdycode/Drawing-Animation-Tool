/// Browser save-as for the JSON export (docs/v3/03 F11.1, docs/v3/05 §4.10).
///
/// Only the **web build** links this file — `download_json.dart` selects it via
/// `if (dart.library.js_interop)`. It is kept out of the VM/test path on purpose:
/// `package:web` and `dart:js_interop` have no VM implementation, so importing
/// them unconditionally would break `flutter test`.
///
/// The mechanism is the standard one: wrap the bytes in a `Blob`, mint an object
/// URL, click a hidden `<a download>`, then revoke the URL so it is not leaked.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

void downloadJson(String filename, String contents) {
  final blob = web.Blob(
    <JSAny>[contents.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
