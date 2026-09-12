/// Flutter rendering layer for [anim_core].
///
/// Spec: `docs/v3/04_architecture.md` §5 (render pipeline).
///
/// **Boundary rule:** this package renders an already-evaluated `Scene`. It does
/// not mutate documents, does not read or write persistence, and does not own
/// editor state. Arrows point inward — `anim_render` depends on `anim_core`,
/// never the reverse.
///
/// **Three painters, and they stay three** (docs/v3/08 §2): `BackgroundPainter`,
/// `ArtboardPainter`, `OverlayPainter`, each destined for its own `CustomPaint`
/// inside its own `RepaintBoundary`. Never merged, whatever a profile says. The
/// overlay is the least-tested code in the app and it dereferences paths undo
/// just deleted; merged, that null takes the artboard with it.
library;

export 'package:anim_core/anim_core.dart' show kSchemaVersion;

export 'src/anim_player.dart';
export 'src/artboard_painter.dart';
export 'src/background_painter.dart';
export 'src/draft_path.dart';
export 'src/group_clip.dart';
export 'src/overlay_painter.dart';
export 'src/paint_translation.dart';
export 'src/path_geometry.dart';
export 'src/render_faults.dart';
