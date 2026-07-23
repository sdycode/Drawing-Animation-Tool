/// The tool registry — the one map from [ToolId] to a live [ToolMode], and the
/// `?? ` fallback that dispatches it (docs/v3/08 §2, §3).
///
/// **A map, not an exhaustive `switch`.** Adding a tool is one entry here and one
/// [ToolId] value; nothing else in the app switches on the tool type, so a new
/// tool cannot break an unrelated panel by making its `switch` non-exhaustive
/// (docs/v3/08 §2 — exhaustive `switch` is allowed only in `anim_core` and
/// `anim_render`). Deleting a tool is deleting its entry and its file, and the
/// app still compiles — that is the deletability §5 buys instead of a feature
/// flag.
///
/// **One registry per composition root, not one global map.** The instances are
/// long-lived — a tool carries its in-progress gesture in a private field
/// (docs/v3/08 §2), and there is exactly one active gesture at a time, so one
/// instance per tool per app is correct and cheap. But *per app*, not per
/// process: a top-level `final` map would share one half-drawn pen path between
/// every `ProviderScope` in a test run, which is the same defect as putting the
/// gesture on a global — just harder to see, because it only appears as one test
/// mysteriously starting with another's anchors.
library;

import '../../state/tool_controller.dart';
import 'direct_select/direct_select_tool.dart';
import 'pen/pen_tool.dart';
import 'select/select_tool.dart';
import 'shape/shape_tool.dart';

/// A fresh set of tools and the resolver over them.
///
/// Installed at composition — `main.dart` and any widget test that drives a real
/// tool override `toolResolverProvider` with the result (see its doc for why
/// `state/` cannot reach in here itself).
///
/// The `?? ` fallback is not decoration: it is what lets a key binding or a
/// toolbar button for a tool that does not exist yet land on Select rather than
/// on a null-tool crash.
ToolMode Function(ToolId) toolRegistry() {
  final tools = <ToolId, ToolMode>{
    ToolId.select: SelectTool(),
    ToolId.directSelect: DirectSelectTool(),
    ToolId.pen: PenTool(),
    ToolId.rect: ShapeTool(ToolId.rect),
    ToolId.ellipse: ShapeTool(ToolId.ellipse),
    ToolId.polygon: ShapeTool(ToolId.polygon),
  };
  final fallback = tools[ToolId.select] ?? SelectTool();
  return (id) => tools[id] ?? fallback;
}
