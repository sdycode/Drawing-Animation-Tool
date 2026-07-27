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
import '../../state/editor_controller.dart';
import '../../state/recipe_guard.dart';

const String kRejectedInspectorEditMessage = 'That value could not be applied.';

final class InspectorCommands {
  const InspectorCommands(this._ref, this._projectId);

  final WidgetRef _ref;
  final String _projectId;

  DocumentController get _controller =>
      _ref.read(documentControllerProvider(_projectId).notifier);

  /// The keyframe the user is editing right now, read at command time and
  /// captured with the undo snapshot so undo returns them to it (docs/v3/04 §6).
  /// Ephemeral — never serialized (AC-6.2.6). Null when nothing is selected,
  /// which the snapshot reads as "carried none" rather than "clear it".
  KeyframeRef? get _selectedKeyframe =>
      _ref.read(editorControllerProvider).selectedKeyframe;

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

  // --- Keyframe diamonds & edit-at-keyframe (F6.2, AC-6.2.6) ---------------
  //
  // The inspector's keyframe authoring, distinct from the timeline's `K`: the
  // diamond keys a **brand-new** track from the value the field is showing, and
  // an inspector field edit on an already-tracked property upserts the keyframe
  // at the playhead rather than the node's static pose. Every method is a thin
  // wrapper over one `state/command.dart` command, and the value the caller
  // hands in is whatever it is showing — this file evaluates nothing except the
  // one sample [keyCurrent] needs, which reads the track directly (never the
  // world-composed `Scene`, whose nested-node value is the wrong number to write
  // into a node-local track).

  /// Upsert a key at [t] holding [value] — an inspector field edit on a tracked
  /// property (AC-6.2.6, AC-6.2.7). [value] is the exact type the channel's
  /// track expects (a `double`, a `Vec2`, or an `Rgba`); [KeyframeOps.keyAt]
  /// creates the track when absent and **replaces** an existing key at [t].
  Future<String?> keyValue(
          NodeId node, PropertyKey property, double t, Object? value) =>
      _guard(() => _controller.run(KeyframeAtCommand(node, property, t, value),
          keyframe: _selectedKeyframe));

  /// Upsert a `Vec2` key at [t] editing only one channel — a tracked
  /// `position`/`scale` field, where the field owns just `x` or `y`.
  ///
  /// The untouched channel comes from the track's **evaluated value at [t]**, so
  /// editing `x` at a keyframe never clobbers an animated `y`. [fallback] — the
  /// node's static pose value the field is displaying — is used only if the
  /// track cannot be sampled (there is none, or a race dropped it).
  Future<String?> keyVec2(
    NodeId node,
    PropertyKey property,
    double t,
    Vec2 fallback, {
    double? x,
    double? y,
  }) {
    final sampled = _sampleTrackValue(node, property, t);
    final base = sampled is Vec2 ? sampled : fallback;
    return keyValue(node, property, t, Vec2(x ?? base.x, y ?? base.y));
  }

  /// The **diamond's key action**: create a key at [t] holding the property's
  /// current value. On an untracked property that value is [authoredValue] — the
  /// static pose the field shows, and this is the one route by which a brand-new
  /// track is born from the inspector. On a tracked-but-between-keys property it
  /// is the track's evaluated sample at [t] (a no-visual-change "hold" key,
  /// exactly the timeline `K`'s value).
  Future<String?> keyCurrent(
      NodeId node, PropertyKey property, double t, Object? authoredValue) {
    final sampled = _sampleTrackValue(node, property, t);
    return keyValue(node, property, t, sampled ?? authoredValue);
  }

  /// The **path diamond's key action** — the geometry "stopwatch" (F6.1).
  ///
  /// `PropKey.path` is not a value channel: a path key is a `PathPose` that only
  /// `PathOps` may author, so [keyValue]/[KeyframeAtCommand] refuse it. This is
  /// the hand affordance that authors the *first* path keyframe — the defect the
  /// M4 audit found, where a static path could be drawn but never started
  /// animating — and it upserts a "hold" key on an already-tracked one. All the
  /// semantics live in [PathOps.keyPose] via [KeyPathCommand]: untracked → one
  /// key from the rest pose; tracked → the pose evaluated at [t].
  Future<String?> keyPath(NodeId node, double t) => _guard(() =>
      _controller.run(KeyPathCommand(node, t), keyframe: _selectedKeyframe));

  /// Remove key [index] — the **filled diamond**, clicked while the playhead
  /// sits on that key. [index] is the one the diamond resolved from the slice's
  /// key times and the live playhead, so it is always in range for the track.
  ///
  /// **When the removed key is the selected one, the selection is cleared**
  /// (AC-4.2.3's 2nd route): `selectedKeyframe` is a highlight, and a highlight
  /// pointing at a key that no longer exists is exactly what re-seeds a track on
  /// the next drag. The undo snapshot still carries the ref, so undoing the
  /// removal restores both the key and its selection.
  Future<String?> removeKeyAt(
      NodeId node, PropertyKey property, int index) async {
    final selected = _selectedKeyframe;
    final message = await _guard(() => _controller
        .run(RemoveKeyframeCommand(node, property, index), keyframe: selected));
    if (message == null && selected == (node, property, index)) {
      _ref.read(editorControllerProvider.notifier).clearKeyframe();
    }
    return message;
  }

  /// The evaluated value of [property] at [t] on [node], or null when there is
  /// no such (non-path) track. Mirrors the timeline `K` sampler; it is a small
  /// duplicate rather than a cross-feature import, because a feature may not
  /// reach into a sibling feature (docs/v3/08 §3).
  Object? _sampleTrackValue(NodeId node, PropertyKey property, double t) {
    if (property.prop == PropKey.path) return null;
    final doc = _ref.read(documentControllerProvider(_projectId)).valueOrNull;
    final animId = _ref.read(activeAnimationProvider(_projectId));
    if (doc == null || animId == null) return null;
    Track? track;
    for (final animation in doc.animations) {
      if (animation.id == animId) {
        track = animation.tracksFor(node).byKey[property];
        break;
      }
    }
    final at = t.isNaN ? 0.0 : t.clamp(0.0, 1.0).toDouble();
    return switch (track) {
      final Vec2Track v => v.sampleAt(at),
      final ScalarTrack s => s.sampleAt(at),
      final ColorTrack c => c.sampleAt(at),
      final BoolTrack b => b.sampleAt(at),
      _ => null, // a PathTrack (unreachable value) or no track at all
    };
  }

  // --- Shape parameters (AC-4.1.5) -----------------------------------------

  /// Regenerate a node's geometry from an edited [ShapeRecipe] — **the one
  /// sanctioned route** from a shape parameter to geometry (AC-4.1.5).
  ///
  /// The route forks on **one predicate — does the node carry a `path` track?**
  /// ([hasPathTrack]), the same one the canvas reads for the shape tools' re-edit,
  /// so the two features route the same document the same way:
  ///
  /// - **Untracked** → [RegenerateRecipeCommand] regenerates the geometry and
  ///   keeps the recipe as inert metadata, exactly as before.
  /// - **Tracked** → the old in-place regeneration is unrepresentable: it mints
  ///   fresh `AnchorId`s while every existing keyframe poses the old ones, leaving
  ///   the topology and its keyframes disjoint. So it routes through
  ///   [RetopologizeCommand], which rewrites every keyframe onto the recipe's new
  ///   id set by **arc-length correspondence** (AC-4.3.7) and clears the now-stale
  ///   recipe. Retopologize runs once here, from a command — never inside the tick.
  ///
  /// **A recipe with no geometry never reaches the tracked branch either.** An
  /// [UnknownRecipe] builds none (`toPath()` is empty), and so does any recipe
  /// clamped past its own floor — a `RectRecipe` with `w <= 0`, a `PolygonRecipe`
  /// with `sides < 3`. Retopologising onto an empty path rewrites every keyframe
  /// to an empty pose and silently erases the animation, so the fork requires the
  /// recipe's `toPath()` to carry anchors. A degenerate recipe falls through to
  /// [RegenerateRecipeCommand] — which keeps the recipe, leaving the value
  /// recoverable in place exactly like the untracked case, never touching the
  /// keyframes. The field-level clamp (`_clampShapeRecipe`) is the primary
  /// defence and keeps this fork off legal input; this is the routing backstop,
  /// kept **identical** to the canvas's so the two features cannot route the same
  /// document two different ways.
  Future<String?> regenerateRecipe(NodeId node, ShapeRecipe recipe) {
    final document =
        _ref.read(documentControllerProvider(_projectId)).valueOrNull;
    if (document == null) {
      return Future<String?>.value(kRejectedInspectorEditMessage);
    }
    if (hasPathTrack(document, node) &&
        recipe is! UnknownRecipe &&
        recipe.toPath().anchors.isNotEmpty) {
      return _guard(
          () => _controller.run(RetopologizeCommand(node, recipe.toPath())));
    }
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
