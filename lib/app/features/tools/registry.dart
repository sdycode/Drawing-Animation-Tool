/// The tool registry — the one map from [ToolId] to a live [ToolMode], and the
/// `?? ` fallback that dispatches it (docs/v3/08 §2, §3).
///
/// **A map, not an exhaustive `switch`.** Adding a tool is one entry here and one
/// `ToolId` value; nothing else in the app switches on the tool type, so a new
/// tool cannot break an unrelated panel by making its `switch` non-exhaustive
/// (docs/v3/08 §2 — exhaustive `switch` is allowed only in `anim_core` and
/// `anim_render`). Deleting a tool is deleting its entry and its file, and the
/// app still compiles — that is the deletability §5 buys instead of a feature
/// flag.
///
/// The instances are **long-lived singletons**: a tool carries its in-progress
/// gesture state in a private field (docs/v3/08 §2), and there is exactly one
/// active gesture at a time, so one shared instance per tool is correct and
/// cheap. [resolveTool] hands back the same object each call.
library;

import '../../state/tool_controller.dart';
import 'select/select_tool.dart';

/// One instance per implemented tool. `pen`/`shape` are **named seams** (M3):
/// their `ToolId`s exist and `resolveTool` covers them via the fallback, but no
/// entry is added until the tool is built — a missing tool must resolve to
/// Select, never to null.
final Map<ToolId, ToolMode> kTools = <ToolId, ToolMode>{
  ToolId.select: SelectTool(),
  // ToolId.pen: PenTool(),      // M3
  // ToolId.shape: ShapeTool(),  // M3
};

/// The tool for [id], or Select when [id] has no tool yet. The fallback is what
/// lets a `P`/`R` key binding be wired before the pen/shape tools exist without
/// risking a null-tool crash (docs/v3/08 §2).
ToolMode resolveTool(ToolId id) => kTools[id] ?? kTools[ToolId.select]!;
