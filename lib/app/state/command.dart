/// The command vocabulary — one pure `Document → Document` per edit the editor
/// can make (docs/v3/04 §6).
///
/// **A command is a value, not a closure over a controller.** It names *what*
/// changed (its [Command.label]) and computes the next document from the
/// previous one, and it does nothing else — no IO, no `EditorState`, no
/// `BuildContext`. That is what lets [CommandStack] treat a command's result as
/// a snapshot and undo a hundred-id `DuplicateSubtreeCommand` as **one** entry.
///
/// **One class per edit — no generic `Command` with a `Map` payload, and no
/// `BatchCommand`.** Both are named antipatterns (docs/v3/08 §4): a `Map`
/// payload makes an invariant failure unattributable, and a batch makes
/// `insertAnchor`'s keyframe backfill undo as two entries. Each command below is
/// a thin wrapper over the `anim_core` op that already enforces the invariant,
/// so the throw the op raises is the same throw the command gate catches
/// (docs/v3/08 §1).
library;

import 'package:anim_core/anim_core.dart' hide Animation;

/// The undoable unit. `apply` is pure and may throw [ArgumentError] on an
/// invariant violation — the command layer never swallows that; [CommandStack]
/// runs `apply` and the one catch site (a feature's `commands.dart`) reports it.
abstract interface class Command {
  /// Shown in the UI ("Group", "Duplicate") and in the undo history.
  String get label;

  /// The new document. Pure: same input, same output, no side effects.
  Document apply(Document before);
}

/// Append a freshly built node to the artboard root.
///
/// The whole node is constructed by the caller (the pen tool builds one closed
/// [PathNode]) and appended here, so a document never holds half a gesture. This
/// mirrors the M0 inline append it replaces; the shape was already
/// `Document → Document`, which is why undo is an addition rather than a
/// rewrite.
final class AddNodeCommand implements Command {
  const AddNodeCommand(this.node);

  final Node node;

  @override
  String get label => 'Add ${node.name}';

  @override
  Document apply(Document d) => d.copyWith(
        root: d.root.copyWith(children: <Node>[...d.root.children, node]),
      );
}

/// Wrap [members] in a fresh group without moving a pixel (F2.1).
final class CreateGroupCommand implements Command {
  const CreateGroupCommand(this.members);

  final List<NodeId> members;

  @override
  String get label => 'Group';

  @override
  Document apply(Document d) => NodeOps.createGroup(d, members);
}

/// World-preserving reparent — the drag-reorder of the layers panel (F2.2,
/// docs/v3/05 §4.5).
final class ReparentCommand implements Command {
  const ReparentCommand(this.node, this.newParent, this.index);

  final NodeId node;
  final NodeId newParent;
  final int index;

  @override
  String get label => 'Move layer';

  @override
  Document apply(Document d) => NodeOps.reparent(d, node, newParent, index);
}

/// Deep-copy a subtree under fresh ids — **one** undo entry however many ids it
/// re-mints (F2.1; the M2 exit criterion names this exactly).
final class DuplicateSubtreeCommand implements Command {
  const DuplicateSubtreeCommand(this.node);

  final NodeId node;

  @override
  String get label => 'Duplicate';

  @override
  Document apply(Document d) => NodeOps.duplicateSubtree(d, node);
}

/// Rename a node in the tree — the layers-panel rename (F2.2).
///
/// Distinct from [RenameDocumentCommand]: this touches one node's `name`, that
/// touches the document's. Two edits, two commands, so the undo history reads
/// honestly.
final class RenameNodeCommand implements Command {
  const RenameNodeCommand(this.node, this.name);

  final NodeId node;
  final String name;

  @override
  String get label => 'Rename layer';

  @override
  Document apply(Document d) => NodeOps.setName(d, node, name);
}

/// Toggle a node's authored `visible` flag — the layers-panel eye (F2.2,
/// AC-2.2.4). The AND-down-the-tree is the evaluator's; this command only writes
/// the one field, so there is no derived "effective visibility" to keep in sync
/// (docs/v3/08 §4).
final class SetVisibleCommand implements Command {
  const SetVisibleCommand(this.node, this.visible);

  final NodeId node;
  final bool visible;

  @override
  String get label => visible ? 'Show layer' : 'Hide layer';

  @override
  Document apply(Document d) => NodeOps.setVisible(d, node, visible);
}

/// Set a node's authored `opacity` — the inspector's opacity field (F2.2,
/// AC-2.2.5).
///
/// The PRODUCT down the ancestor chain is the evaluator's, recomputed per frame,
/// so this writes one node's own value and there is no derived effective opacity
/// to desync (docs/v3/08 §4). Clamping lives in [NodeOps.setOpacity] — at the
/// mutation, not at read — because an authored 1.7 is a bad write, while a
/// *sampled* overshoot through an easing curve is legitimate and is clamped
/// separately by the evaluator.
final class SetOpacityCommand implements Command {
  const SetOpacityCommand(this.node, this.opacity);

  final NodeId node;
  final double opacity;

  @override
  String get label => 'Opacity';

  @override
  Document apply(Document d) => NodeOps.setOpacity(d, node, opacity);
}

/// Toggle a node's authored `locked` flag — the layers-panel lock (F2.2,
/// AC-2.2.6). `locked` is a hit-test gate the evaluator never reads, so this is
/// undoable editor structure and not an animation edit.
final class SetLockedCommand implements Command {
  const SetLockedCommand(this.node, this.locked);

  final NodeId node;
  final bool locked;

  @override
  String get label => locked ? 'Lock layer' : 'Unlock layer';

  @override
  Document apply(Document d) => NodeOps.setLocked(d, node, locked);
}

/// Reorder a child within one parent — the layers-panel drag-reorder (F2.2,
/// docs/v3/05 §4.5, AC-2.2.2).
///
/// Z-order **is** child order, so this is a child-list splice, not a move: the
/// node's `Transform2` is untouched. A drop into a *different* group is a
/// [ReparentCommand] instead (world-preserving), never this — reorder is
/// same-parent only, which is why it takes a `parent` and two indices rather
/// than a new parent.
final class ReorderChildCommand implements Command {
  const ReorderChildCommand(this.parent, this.oldIndex, this.newIndex);

  final NodeId parent;
  final int oldIndex;
  final int newIndex;

  @override
  String get label => 'Reorder layer';

  @override
  Document apply(Document d) =>
      NodeOps.reorderChild(d, parent, oldIndex, newIndex);
}

/// Overwrite a node's [Transform2] — the inspector's transform authoring (F3.1).
final class SetTransformCommand implements Command {
  const SetTransformCommand(this.node, this.transform);

  final NodeId node;
  final Transform2 transform;

  @override
  String get label => 'Transform';

  @override
  Document apply(Document d) => NodeOps.setTransform(d, node, transform);
}

/// Move one anchor — the pose edit of docs/v3/01 §12.
///
/// [atT] `null` edits the node's rest pose; non-null writes the pose into the
/// path track keyframe at that `t` (seeding a `t = 0.0` key from the rest pose
/// the first time). All of that lives in [PathOps.moveAnchor]; the command only
/// names the edit.
final class MoveAnchorCommand implements Command {
  const MoveAnchorCommand(this.node, this.anchor, this.to, {this.atT});

  final NodeId node;
  final AnchorId anchor;
  final Vec2 to;
  final double? atT;

  @override
  String get label => 'Move anchor';

  @override
  Document apply(Document d) =>
      PathOps.moveAnchor(d, node, anchor, to, atT: atT);
}

/// Point one anchor's handles — the other half of the pose edit (F4.2,
/// AC-4.2.2), and Direct select's handle drag (docs/v3/05 §3).
///
/// [atT] `null` edits the node's rest pose; non-null writes the tangents into
/// that keyframe alone. [kind] is **not** pose — `AnchorKind` is not animatable
/// (docs/v3/01 §7), so [PathOps.setTangents] writes it onto the node's
/// `PathData` document-wide while the handles it implies stay keyframe-local.
/// All of that lives in the op; the command only names the edit.
///
/// A bare [kind] with no handles is the **straighten** affordance: `corner`
/// zeroes both handles and the segment renders as the degenerate straight
/// cubic (AC-4.1.3).
final class SetTangentsCommand implements Command {
  const SetTangentsCommand(
    this.node,
    this.anchor, {
    this.inT,
    this.outT,
    this.kind,
    this.atT,
  });

  final NodeId node;
  final AnchorId anchor;
  final Vec2? inT;
  final Vec2? outT;
  final AnchorKind? kind;
  final double? atT;

  @override
  String get label => inT == null && outT == null ? 'Anchor kind' : 'Handles';

  @override
  Document apply(Document d) => PathOps.setTangents(
        d,
        node,
        anchor,
        inT: inT,
        outT: outT,
        kind: kind,
        atT: atT,
      );
}

/// Regenerate a node's geometry from an edited [ShapeRecipe] — **the one route**
/// a recipe parameter edit may take to reach geometry (AC-4.1.5).
///
/// The shape *tools* do not use this: they build a whole new node, which needs
/// no op at all. This exists for the inspector's shape-parameter fields, and it
/// exists as a command rather than as a call so that the refusal it can raise is
/// caught at the one gate every other edit is caught at (docs/v3/08 §1).
///
/// [PathOps.regenerateRecipe] **throws, naming M5**, on a node that already
/// carries path keyframes: the recipe mints fresh `AnchorId`s and every existing
/// keyframe poses the old ones, so a raw replacement would leave the topology
/// and its keyframes disjoint. Arc-length correspondence (`PathOps.retopologize`)
/// is the correct answer and it is M5's, so the refusal is surfaced to the user
/// rather than approximated.
final class RegenerateRecipeCommand implements Command {
  const RegenerateRecipeCommand(this.node, this.recipe);

  final NodeId node;
  final ShapeRecipe recipe;

  @override
  String get label => 'Shape';

  @override
  Document apply(Document d) => PathOps.regenerateRecipe(d, node, recipe);
}

// ---------------------------------------------------------------------------
// Paint — F5.1. One class per edit, and **no `PaintSource` anywhere.**
//
// AC-5.1.3 and docs/v3/06 M3's scope-leak warning are the same rule seen from
// two sides: gradients are rendered and never authored. `PaintOps` takes an
// [Rgba] and produces a `SolidPaint`; there is deliberately no op that accepts a
// [PaintSource], so there is nothing here for a gradient command to wrap. A
// command that took one would be the first half of a week-long feature nobody
// scheduled.
//
// **Fills paint before strokes, always.** That ordering is the renderer's and is
// expressed by `fills` and `strokes` being two fields, so there is no reorder
// command, no z-index and no "bring to front" — a stored ordering number beside
// an authoritative list is the derived-state desync docs/v3/08 §4 forbids.
//
// Every edit below addresses its paint by [PaintId], never by list index. A
// `PaintId` is a track's `subjectId`; indices shift the moment a document from a
// newer client carries two fills, and the edit would then land on the wrong one.
// ---------------------------------------------------------------------------

/// Append a solid black [Fill] (AC-5.1.1).
///
/// The minted [PaintId] is discarded here rather than plumbed out: a command is
/// a pure `Document → Document` value, and the panel addresses the new fill by
/// reading it back off the document it just committed. The colour and rule
/// defaults are `PaintOps`' own — a second set of defaults in the UI is a second
/// answer to "what is a new fill" for the importer to disagree with later.
final class AddFillCommand implements Command {
  const AddFillCommand(this.node);

  final NodeId node;

  @override
  String get label => 'Add fill';

  @override
  Document apply(Document d) => PaintOps.addFill(d, node).$1;
}

/// Remove one fill, and with it every track addressed to its [PaintId].
final class RemoveFillCommand implements Command {
  const RemoveFillCommand(this.node, this.fill);

  final NodeId node;
  final PaintId fill;

  @override
  String get label => 'Remove fill';

  @override
  Document apply(Document d) => PaintOps.removeFill(d, node, fill);
}

/// Replace one fill's colour (AC-5.1.1).
///
/// [PaintOps.setFillColor] **throws** when the fill is not a `SolidPaint`, and
/// that throw is a feature: flattening a gradient this build cannot recreate is
/// a destructive edit dressed up as a colour change. The panel never issues this
/// against a gradient — it shows the paint read-only instead — so the throw
/// stays the backstop for a future call site rather than a path users reach.
final class SetFillColorCommand implements Command {
  const SetFillColorCommand(this.node, this.fill, this.color);

  final NodeId node;
  final PaintId fill;
  final Rgba color;

  @override
  String get label => 'Fill colour';

  @override
  Document apply(Document d) => PaintOps.setFillColor(d, node, fill, color);
}

/// Toggle one fill's winding rule (AC-5.1.4).
final class SetFillRuleCommand implements Command {
  const SetFillRuleCommand(this.node, this.fill, this.rule);

  final NodeId node;
  final PaintId fill;
  final FillRule rule;

  @override
  String get label => 'Fill rule';

  @override
  Document apply(Document d) => PaintOps.setFillRule(d, node, fill, rule);
}

/// Set one fill's authored opacity. Clamping to 0..1 lives in the op, at the
/// mutation, for the reason [SetOpacityCommand] documents.
final class SetFillOpacityCommand implements Command {
  const SetFillOpacityCommand(this.node, this.fill, this.opacity);

  final NodeId node;
  final PaintId fill;
  final double opacity;

  @override
  String get label => 'Fill opacity';

  @override
  Document apply(Document d) => PaintOps.setFillOpacity(d, node, fill, opacity);
}

/// Show or hide one fill without discarding it — a hidden fill keeps its
/// [PaintId], so its tracks survive the toggle and come back with it.
final class SetFillVisibleCommand implements Command {
  const SetFillVisibleCommand(this.node, this.fill, this.visible);

  final NodeId node;
  final PaintId fill;
  final bool visible;

  @override
  String get label => visible ? 'Show fill' : 'Hide fill';

  @override
  Document apply(Document d) => PaintOps.setFillVisible(d, node, fill, visible);
}

/// Append a solid black [Stroke] (AC-5.1.2).
final class AddStrokeCommand implements Command {
  const AddStrokeCommand(this.node);

  final NodeId node;

  @override
  String get label => 'Add stroke';

  @override
  Document apply(Document d) => PaintOps.addStroke(d, node).$1;
}

/// Remove one stroke, and with it every track addressed to its [PaintId].
final class RemoveStrokeCommand implements Command {
  const RemoveStrokeCommand(this.node, this.stroke);

  final NodeId node;
  final PaintId stroke;

  @override
  String get label => 'Remove stroke';

  @override
  Document apply(Document d) => PaintOps.removeStroke(d, node, stroke);
}

/// Replace one stroke's colour. Refuses a non-solid paint for the reason
/// [SetFillColorCommand] documents.
final class SetStrokeColorCommand implements Command {
  const SetStrokeColorCommand(this.node, this.stroke, this.color);

  final NodeId node;
  final PaintId stroke;
  final Rgba color;

  @override
  String get label => 'Stroke colour';

  @override
  Document apply(Document d) => PaintOps.setStrokeColor(d, node, stroke, color);
}

/// Set one stroke's width in node-local units (AC-5.1.2). Zero is a hairline;
/// negative is refused at the op, because it reaches the rasteriser as an
/// inverted outline rather than as a thin one.
final class SetStrokeWidthCommand implements Command {
  const SetStrokeWidthCommand(this.node, this.stroke, this.width);

  final NodeId node;
  final PaintId stroke;
  final double width;

  @override
  String get label => 'Stroke width';

  @override
  Document apply(Document d) => PaintOps.setStrokeWidth(d, node, stroke, width);
}

/// Set one stroke's end cap (AC-5.1.2).
final class SetStrokeCapCommand implements Command {
  const SetStrokeCapCommand(this.node, this.stroke, this.cap);

  final NodeId node;
  final PaintId stroke;
  final StrokeCap cap;

  @override
  String get label => 'Stroke cap';

  @override
  Document apply(Document d) => PaintOps.setStrokeCap(d, node, stroke, cap);
}

/// Set one stroke's corner join (AC-5.1.2).
final class SetStrokeJoinCommand implements Command {
  const SetStrokeJoinCommand(this.node, this.stroke, this.join);

  final NodeId node;
  final PaintId stroke;
  final StrokeJoin join;

  @override
  String get label => 'Stroke join';

  @override
  Document apply(Document d) => PaintOps.setStrokeJoin(d, node, stroke, join);
}

/// Set the ratio at which a miter join's spike is cut back to a bevel. Below 1
/// describes a miter shorter than the stroke is wide, which is geometrically
/// meaningless and answered differently by each rasteriser — so the op refuses
/// it rather than letting the backend decide.
final class SetStrokeMiterLimitCommand implements Command {
  const SetStrokeMiterLimitCommand(this.node, this.stroke, this.miterLimit);

  final NodeId node;
  final PaintId stroke;
  final double miterLimit;

  @override
  String get label => 'Miter limit';

  @override
  Document apply(Document d) =>
      PaintOps.setStrokeMiterLimit(d, node, stroke, miterLimit);
}

/// Set one stroke's authored opacity, clamped at the mutation.
final class SetStrokeOpacityCommand implements Command {
  const SetStrokeOpacityCommand(this.node, this.stroke, this.opacity);

  final NodeId node;
  final PaintId stroke;
  final double opacity;

  @override
  String get label => 'Stroke opacity';

  @override
  Document apply(Document d) =>
      PaintOps.setStrokeOpacity(d, node, stroke, opacity);
}

/// Show or hide one stroke without discarding it or its tracks.
final class SetStrokeVisibleCommand implements Command {
  const SetStrokeVisibleCommand(this.node, this.stroke, this.visible);

  final NodeId node;
  final PaintId stroke;
  final bool visible;

  @override
  String get label => visible ? 'Show stroke' : 'Hide stroke';

  @override
  Document apply(Document d) =>
      PaintOps.setStrokeVisible(d, node, stroke, visible);
}

/// Rename the document itself.
///
/// Not in the F2.1/F2.2 op list, but every mutation routes through a command so
/// the controller can keep having no public setter (docs/v3/04 §6) — the
/// document title field cannot be an exception, or it becomes the one call site
/// that assigns `state = newDoc` directly.
final class RenameDocumentCommand implements Command {
  const RenameDocumentCommand(this.name);

  final String name;

  @override
  String get label => 'Rename';

  @override
  Document apply(Document d) => d.copyWith(name: name);
}
