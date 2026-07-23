/// Every document mutation the inspector can cause, and the only place it
/// catches (docs/v3/08 §1).
///
/// M2 authored a node's `Transform2` and its own `opacity`. M3 adds solid fill
/// and stroke (F5.1) and shape-parameter re-editing (AC-4.1.5). Trim, easing and
/// anchor-kind editing are still labelled seams in the panel, not stubbed here —
/// a command that pretended to write them would be worse than its absence.
/// Nothing here builds a `Document` by hand and nothing here touches
/// `EditorState`.
///
/// **There is no gradient method, and there is no `PaintSource` parameter.**
/// AC-5.1.3 and docs/v3/06 M3's scope-leak warning are the same rule: gradients
/// are rendered, never authored. Every colour method below takes an `Rgba`,
/// exactly as `PaintOps` does.
library;

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../state/command.dart';
import '../../state/document_controller.dart';
import '../../state/recipe_guard.dart';

const String kRejectedInspectorEditMessage = 'That value could not be applied.';

final class InspectorCommands {
  const InspectorCommands(this._ref, this._projectId);

  final WidgetRef _ref;
  final String _projectId;

  DocumentController get _controller =>
      _ref.read(documentControllerProvider(_projectId).notifier);

  /// Overwrite the selected node's `Transform2` (F3.1, AC-3.1.1).
  ///
  /// **One field edit is one command and one undo entry.** The panel builds the
  /// whole next `Transform2` (via `copyWith` on the current one) and hands it
  /// here, so composition order stays anim_core's golden-tested `toAffine` and
  /// this layer never re-derives a matrix. Rotation arrives already converted to
  /// **unbounded radians** — the panel shows degrees but stores radians with no
  /// wrap and no shortest-arc (AC-3.1.2).
  Future<String?> setTransform(NodeId node, Transform2 transform) =>
      _guard(() => _controller.run(SetTransformCommand(node, transform)));

  /// Author one node's own `opacity` (F2.2's `opacity` PRODUCT row, AC-2.2.5).
  ///
  /// [opacity] is the stored **0..1** value; the panel shows percent and
  /// converts, the same display-vs-storage split rotation uses for degrees vs
  /// radians. The product down the ancestor chain belongs to the evaluator, so
  /// nothing here reads or writes an effective opacity — one field, one write,
  /// one undo entry. Range clamping lives in `NodeOps.setOpacity`, at the
  /// mutation.
  Future<String?> setOpacity(NodeId node, double opacity) =>
      _guard(() => _controller.run(SetOpacityCommand(node, opacity)));

  // --- Fill (F5.1) ---------------------------------------------------------
  //
  // Every method takes the fill's `PaintId`, which the panel reads off the
  // document it is displaying. Never a list index: a `PaintId` is a track's
  // `subjectId`, and an index-addressed edit lands on the wrong paint the moment
  // a document from a newer client carries two fills (AC-5.1.6).

  Future<String?> addFill(NodeId node) =>
      _guard(() => _controller.run(AddFillCommand(node)));

  Future<String?> removeFill(NodeId node, PaintId fill) =>
      _guard(() => _controller.run(RemoveFillCommand(node, fill)));

  /// [color] is straight sRGB 0..1 (docs/v3/01 §2). Only ever called for a fill
  /// the panel has already shown as solid — `PaintOps.setFillColor` throws on a
  /// gradient, and the panel renders those read-only rather than offering a
  /// control that would trip the `assert` below.
  Future<String?> setFillColor(NodeId node, PaintId fill, Rgba color) =>
      _guard(() => _controller.run(SetFillColorCommand(node, fill, color)));

  Future<String?> setFillRule(NodeId node, PaintId fill, FillRule rule) =>
      _guard(() => _controller.run(SetFillRuleCommand(node, fill, rule)));

  /// [opacity] is the stored **0..1** value; the panel shows percent and
  /// converts, the same display-vs-storage split rotation makes between degrees
  /// and radians. Clamping lives in the op, at the mutation.
  Future<String?> setFillOpacity(NodeId node, PaintId fill, double opacity) =>
      _guard(() => _controller.run(SetFillOpacityCommand(node, fill, opacity)));

  Future<String?> setFillVisible(NodeId node, PaintId fill, bool visible) =>
      _guard(() => _controller.run(SetFillVisibleCommand(node, fill, visible)));

  // --- Stroke (F5.1) -------------------------------------------------------

  Future<String?> addStroke(NodeId node) =>
      _guard(() => _controller.run(AddStrokeCommand(node)));

  Future<String?> removeStroke(NodeId node, PaintId stroke) =>
      _guard(() => _controller.run(RemoveStrokeCommand(node, stroke)));

  Future<String?> setStrokeColor(NodeId node, PaintId stroke, Rgba color) =>
      _guard(() => _controller.run(SetStrokeColorCommand(node, stroke, color)));

  Future<String?> setStrokeWidth(NodeId node, PaintId stroke, double width) =>
      _guard(() => _controller.run(SetStrokeWidthCommand(node, stroke, width)));

  Future<String?> setStrokeCap(NodeId node, PaintId stroke, StrokeCap cap) =>
      _guard(() => _controller.run(SetStrokeCapCommand(node, stroke, cap)));

  Future<String?> setStrokeJoin(NodeId node, PaintId stroke, StrokeJoin join) =>
      _guard(() => _controller.run(SetStrokeJoinCommand(node, stroke, join)));

  Future<String?> setStrokeMiterLimit(
          NodeId node, PaintId stroke, double miterLimit) =>
      _guard(() => _controller
          .run(SetStrokeMiterLimitCommand(node, stroke, miterLimit)));

  Future<String?> setStrokeOpacity(
          NodeId node, PaintId stroke, double opacity) =>
      _guard(() =>
          _controller.run(SetStrokeOpacityCommand(node, stroke, opacity)));

  Future<String?> setStrokeVisible(NodeId node, PaintId stroke, bool visible) =>
      _guard(() =>
          _controller.run(SetStrokeVisibleCommand(node, stroke, visible)));

  // --- Shape parameters (AC-4.1.5) -----------------------------------------

  /// Regenerate a node's geometry from an edited [ShapeRecipe] — **the one
  /// sanctioned route** from a shape parameter to geometry.
  ///
  /// **The refusal is pre-checked, not caught from the op.** A node carrying
  /// path keyframes is legal data, so the answer is a sentence the user can act
  /// on rather than an `ArgumentError` through [_guard]'s `assert`. The
  /// predicate and its message live in `state/recipe_guard.dart` because the
  /// canvas needs the same gate and a feature may not import a sibling feature
  /// (docs/v3/08 §3) — one predicate, two call sites, no drift.
  ///
  /// The panel disables the fields using the same predicate, so this is the
  /// backstop rather than the path a user reaches: a refusal only visible after
  /// typing into a field that looked editable is a trap.
  Future<String?> regenerateRecipe(NodeId node, ShapeRecipe recipe) {
    final document =
        _ref.read(documentControllerProvider(_projectId)).valueOrNull;
    if (document == null) {
      return Future<String?>.value(kRejectedInspectorEditMessage);
    }
    final refusal = recipeRegenerationRefusal(document, node);
    if (refusal != null) return Future<String?>.value(refusal);
    return _guard(() => _controller.run(RegenerateRecipeCommand(node, recipe)));
  }

  static Future<String?> _guard(Future<void> Function() run) async {
    try {
      await run();
      return null;
    } on StoreException catch (e) {
      return e.failure.message;
    } on ArgumentError catch (e) {
      assert(false, 'inspector command rejected by an op: $e');
      return kRejectedInspectorEditMessage;
    }
  }
}
