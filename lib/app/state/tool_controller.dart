/// Tool mode — the third of the three controllers (docs/v3/04 §4).
///
/// **Why the contract lives in `state/` and the tools live in `features/tools/`.**
/// The canvas (a feature) must reach the active tool, and a feature may not
/// import a sibling feature (docs/v3/08 §3). So the *vocabulary* every feature
/// shares — the [ToolMode] contract, the [PointerCtx] a tool is handed, the
/// [ToolId] the toolbar switches on, and the [toolControllerProvider] the canvas
/// watches — lives here in the controller layer, which is not a feature and is
/// therefore reachable from all of them. The canvas never names `SelectTool`: it
/// watches this provider, gets a [ToolMode], and calls through the contract.
///
/// **The dependency points one way, and that is load-bearing.** This file
/// imports nothing from `features/`. An earlier version imported
/// `features/tools/registry.dart` for `resolveTool`, reasoning that the boundary
/// check forbids only *feature → sibling-feature* and `state/` is not a feature.
/// That reading is true of the checker and false of the architecture: it made the
/// real edge `features/canvas → state/ → features/tools/select`, laundered
/// through the controller layer, and it cost the property docs/v3/08 §5 sells as
/// the alternative to a feature-flag registry — deleting `features/tools/` did
/// **not** leave a compiling app, it broke `state/` and through it the canvas.
/// So the concrete tools are injected at composition ([toolResolverProvider])
/// instead, and the arrow now runs `features/tools → state/`, never back.
///
/// **Not a Dart `sealed` class, deliberately.** docs/v3/04 §4 calls it a "sealed
/// class ToolMode", but a Dart `sealed` type requires every variant in the same
/// library, which contradicts the directory law that splits the tools across
/// `select/select_tool.dart`, `pen/pen_tool.dart` and `shape/shape_tool.dart`
/// (docs/v3/08 §3). `sealed`'s only payoff is exhaustive `switch` — and
/// exhaustive `switch` on a tool type in app code is exactly what docs/v3/08 §2
/// bans (dispatch through a map with a `?? ` fallback instead). So the closed set
/// is enforced by the registry, not by the compiler, and this stays an
/// `abstract interface class`.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'command.dart';
import 'editor_controller.dart';

/// The tools the toolbar can switch between (docs/v3/05 §3). Pan and Zoom are
/// **not** here — they are ephemeral viewport gestures the canvas applies through
/// [EditorController.panBy]/[EditorController.zoomAround], and mutate nothing, so
/// they never become a modal tool that could swallow a click meant for Select.
enum ToolId {
  select,

  /// M3 seam. The injected resolver ([toolResolverProvider]) falls back to
  /// [select] until `PenTool` ships, so a key binding wired early lands on a
  /// real tool rather than a crash.
  pen,

  /// M3 seam. Same fallback as [pen].
  shape,
}

/// Everything a tool may read on a pointer event, and **nothing it may write**
/// (docs/v3/08 §2). A tool observes the world and returns a [Command] (a
/// `Document` edit) or null; it never touches `Document` or `EditorState`
/// directly. That read-only shape is what stops a tool from editing the document
/// inside a gesture handler — the legacy defect where `build()`/`paint()` mutated
/// state (docs/v3/05 §3 rule 2).
final class PointerCtx {
  const PointerCtx({
    required this.docPoint,
    required this.scene,
    required this.doc,
    required this.editor,
  });

  /// Pointer position in **document space** — the canvas has already inverted the
  /// single composed `viewportTransform ∘ artboardFit` matrix (docs/v3/05 §3),
  /// so a tool never re-derives the transform and never invents a second one
  /// (AC-3.1.4).
  final Vec2 docPoint;

  /// The evaluated scene at the settled playhead — for hit-testing against posed
  /// geometry, keyed by `ScenePath`.
  final Scene scene;

  /// The current document, for a tool that needs a node's authored `Transform2`
  /// or `PathData` (the overlay draws *authored* anchors, never `Scene`'s
  /// synthetic ones — docs/v3/04 §5).
  final Document doc;

  /// The current ephemeral state — the existing selection a drag operates on.
  final EditorState editor;
}

/// One tool. **In-progress gesture state is a private field of the implementing
/// class — never on `Document`, never on `EditorState`** (docs/v3/08 §2). An
/// unfinished drag that leaked into either would be autosaved or would survive an
/// undo; keeping it private to the tool is what makes a half-finished gesture
/// unrepresentable in the persisted or undoable world.
///
/// Every pointer handler returns a [Command] to mutate the document, or null when
/// the gesture changed nothing the document owns. **Selection is not a [Command]**
/// — it is `EditorState`, applied by the canvas gesture layer through
/// [EditorController]; a tool signals a pure selection by returning null.
abstract interface class ToolMode {
  ToolId get id;

  Command? onPointerDown(PointerCtx ctx);
  Command? onPointerMove(PointerCtx ctx);
  Command? onPointerUp(PointerCtx ctx);
}

/// Holds the one active tool. Modal: exactly one at a time (docs/v3/05 §3).
///
/// A plain [Notifier] (not `Async`, not a family): the tool is process-local UI
/// state with no IO and no per-project identity — switching tools must not
/// invalidate the document or the editor state, which is the whole point of
/// keeping the three controllers apart (docs/v3/04 §4).
class ToolController extends Notifier<ToolMode> {
  @override
  ToolMode build() => ref.watch(toolResolverProvider)(ToolId.select);

  /// Switch tools (the toolbar / a key binding). Goes through the injected
  /// resolver so an id with no tool yet (`pen`/`shape` before M3) resolves to
  /// something usable rather than null.
  void activate(ToolId id) => state = ref.read(toolResolverProvider)(id);
}

final toolControllerProvider =
    NotifierProvider<ToolController, ToolMode>(ToolController.new);

/// Maps a [ToolId] to the live tool that implements it.
///
/// **Overridden at composition** — `main.dart` supplies `features/tools`'
/// registry. That override is the whole reason `state/` imports no feature: the
/// implementations plug into this contract, the contract never reaches for them.
///
/// The default below is deliberately **inert, not absent**. A tool that returns
/// no [Command] is a tool that changes nothing, which is exactly right for a
/// build (or a widget test) that has not installed the registry — whereas a null
/// tool or a throwing default would make the canvas's `ref.watch` a crash site,
/// and docs/v3/08 §2 requires provider bodies to be provably total.
///
/// It preserves the requested `id`, so everything that reads `tool.id` — which
/// at M2 is everything, since the canvas implements select/move inline and no
/// code path calls the pointer handlers yet — behaves identically with or
/// without the override. When M3 gives the pen and shape tools real handlers, a
/// widget test that drives them must install the same override `main.dart` does.
final toolResolverProvider = Provider<ToolMode Function(ToolId)>(
  (ref) => (id) => _InertTool(id),
);

/// A tool that does nothing, for the un-composed case. Not a seam and not a
/// stub for a future tool — its only job is to keep [toolResolverProvider]
/// total.
final class _InertTool implements ToolMode {
  const _InertTool(this.id);

  @override
  final ToolId id;

  @override
  Command? onPointerDown(PointerCtx ctx) => null;

  @override
  Command? onPointerMove(PointerCtx ctx) => null;

  @override
  Command? onPointerUp(PointerCtx ctx) => null;
}
