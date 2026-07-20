/// Flutter rendering layer for [anim_core].
///
/// Spec: `docs/v3/04_architecture.md` §5 (render pipeline).
///
/// **Boundary rule:** this package renders an already-evaluated `Scene`. It does
/// not mutate documents, does not read or write persistence, and does not own
/// editor state. Arrows point inward — `anim_render` depends on `anim_core`,
/// never the reverse.
library;

export 'package:anim_core/anim_core.dart' show kSchemaVersion;
