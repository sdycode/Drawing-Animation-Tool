/// Pure-Dart domain core for the v3 vector-animation format.
///
/// Spec: `docs/v3/01_domain_model.md` (authoritative) · wire format:
/// `docs/v3/02_file_format.md`.
///
/// **Boundary rule (docs/v3/04 §1):** nothing in this package may import
/// `dart:ui`, `package:flutter/*`, `cloud_firestore`, or `http`. Persistence
/// reaches the domain only through `ProjectStore` (String in / String out),
/// which lives in the app, not here. `boundary_test.dart` enforces it.
library;

export 'src/affine.dart';
export 'src/document.dart';
export 'src/json.dart' show d, i;
export 'src/node.dart';
export 'src/primitives.dart';
export 'src/uuid.dart';

/// The wire-format version this build reads and writes.
///
/// A document with a *higher* `schemaVersion` opens read-only — key
/// preservation protects syntax, not semantics (docs/v3/02 §7).
const int kSchemaVersion = 3;
