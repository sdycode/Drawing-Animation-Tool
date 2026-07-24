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
export 'src/animation.dart';

/// The `req*` helpers and the `json*` path builders stay internal: they are the
/// decoder's vocabulary, not the domain's, and exporting them would invite a
/// second decoder outside this package.
export 'src/decode.dart' show DecodeWarning, DocumentException, onDecodeWarning;
export 'src/document.dart';
export 'src/easing.dart';
export 'src/eval/evaluate.dart';
export 'src/eval/scene.dart';
export 'src/json.dart' show d, i;
export 'src/node.dart';
export 'src/ops/keyframe_ops.dart';
export 'src/ops/node_ops.dart';
export 'src/ops/paint_ops.dart';
export 'src/ops/path_ops.dart';
export 'src/ops/track_ops.dart';
export 'src/paint.dart';
export 'src/path.dart';
export 'src/primitives.dart';
export 'src/recipe.dart';
export 'src/shape_geometry.dart';
export 'src/track.dart';
export 'src/uuid.dart';

/// The wire-format version this build reads and writes.
///
/// A document with a *higher* `schemaVersion` opens read-only — key
/// preservation protects syntax, not semantics (docs/v3/02 §7).
const int kSchemaVersion = 3;
