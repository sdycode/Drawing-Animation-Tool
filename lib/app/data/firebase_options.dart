// Firebase configuration for the v3 app.
//
// Same Firebase project as the legacy app (`animate-widget-tool`) but a
// different data namespace: v3 writes only under `appData/v3/...` and never
// touches legacy `users/` or `appData/v2` (docs/v3/02 §9).
//
// These values are NOT secrets. A Firebase web apiKey identifies the project to
// Google's endpoints and ships in every client bundle by design; access control
// is Firestore security rules, not key secrecy.
//
// Lives in data/ because that is the only layer allowed to import Firebase
// (docs/v3/08 §3, enforced by tool/check_boundaries.dart).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'v3 is Flutter Web only (docs/v3/00 §6). No other platform is configured.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDPwlTf0-vYkjT7M2rfM7ANqdtgz0tknOQ',
    appId: '1:527498934912:web:77cd249da45759857d4465',
    messagingSenderId: '527498934912',
    projectId: 'animate-widget-tool',
    authDomain: 'animate-widget-tool.firebaseapp.com',
    storageBucket: 'animate-widget-tool.appspot.com',
    measurementId: 'G-QTS8MRVKTB',
  );
}
