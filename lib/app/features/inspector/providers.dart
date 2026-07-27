/// The inspector feature's named slices (docs/v3/08 §2).
///
/// The inspector owns numeric/typed editing of the selected node's values
/// (docs/v3/05 §2). It reads the document through **one value-projected slice**
/// keyed by the selected node, so editing an anchor on some *other* node — or
/// scrubbing the playhead — rebuilds nothing here (AC-13.3). Selection is the
/// same `EditorState.selectedNodes` set the canvas and the layers panel read.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';

/// The selected nodes as `NodeId`s — the same shared editor slice the canvas and
/// layers panel read, projected off `ScenePath` (`instancePath` is `const []` in
/// v1). Watching `s.selectedNodes` alone keeps a viewport pan or a scrub from
/// rebuilding the inspector.
final inspectorSelectionProvider = Provider.autoDispose<Set<NodeId>>((ref) {
  final paths =
      ref.watch(editorControllerProvider.select((s) => s.selectedNodes));
  return <NodeId>{for (final p in paths) p.nodeId};
});

/// Just the one selected node's `Transform2` (plus its name and kind), by value.
///
/// A value type so the `.select` below dedups: `Transform2` compares by value,
/// so an edit elsewhere that leaves this node's transform alone yields an equal
/// view and no rebuild.
@immutable
final class NodeTransformView {
  const NodeTransformView({
    required this.id,
    required this.name,
    required this.transform,
    required this.opacity,
    required this.isUnknown,
  });

  final NodeId id;
  final String name;
  final Transform2 transform;

  /// The node's **own authored** `opacity`, never a product with its ancestors'.
  ///
  /// `worldOpacity` is a PRODUCT down the chain (AC-2.2.5) and it is the
  /// evaluator's, recomputed per frame. Projecting an "effective" opacity here
  /// would store a derived value beside the authored one — the exact desync
  /// docs/v3/08 §4 forbids — and it would also be uneditable: there is no
  /// inverse for "0.25 effective" that does not silently rewrite an ancestor.
  final double opacity;

  /// An `UnknownNode` re-emits raw JSON verbatim, so a typed transform written to
  /// it would be dropped on save (`NodeOps.setTransform` refuses one). The panel
  /// shows it read-only rather than offering fields that silently do nothing.
  final bool isUnknown;

  @override
  bool operator ==(Object other) =>
      other is NodeTransformView &&
      other.id == id &&
      other.name == name &&
      other.transform == transform &&
      other.opacity == opacity &&
      other.isUnknown == isUnknown;

  @override
  int get hashCode => Object.hash(id, name, transform, opacity, isUnknown);
}

/// What the inspector should show: exactly one node's transform, or a calm
/// summary of a 0-or-many selection.
@immutable
final class InspectorTarget {
  const InspectorTarget._(this.node, this.selectionCount);

  /// Show one node's editable transform.
  const InspectorTarget.node(NodeTransformView view) : this._(view, 1);

  /// Show the empty/summary state for [count] selected nodes (0 or >1).
  const InspectorTarget.summary(int count) : this._(null, count);

  /// Non-null exactly when [selectionCount] is 1 and the node resolves.
  final NodeTransformView? node;
  final int selectionCount;

  @override
  bool operator ==(Object other) =>
      other is InspectorTarget &&
      other.node == node &&
      other.selectionCount == selectionCount;

  @override
  int get hashCode => Object.hash(node, selectionCount);
}

/// The inspector's single read. Exactly one selected node → its transform view;
/// otherwise a summary. A dangling selection path (its node was deleted) is
/// resolved, never repaired: it simply resolves to null here and shows the
/// summary state, never a crash (docs/v3/08 §2).
final inspectorTargetProvider =
    Provider.autoDispose.family<InspectorTarget, String>((ref, projectId) {
  final ids = ref.watch(inspectorSelectionProvider);
  if (ids.length != 1) return InspectorTarget.summary(ids.length);

  final id = ids.single;
  final view = ref.watch(documentControllerProvider(projectId).select((async) {
    final node = async.valueOrNull?.nodeIndex[id];
    if (node == null) return null;
    return NodeTransformView(
      id: id,
      name: node.name,
      transform: node.transform,
      opacity: node.opacity,
      isUnknown: node is UnknownNode,
    );
  }));

  return view == null
      ? const InspectorTarget.summary(1)
      : InspectorTarget.node(view);
});

// ---------------------------------------------------------------------------
// Keyframe diamonds — F6.2, AC-6.2.6 (the edit-at-keyframe authoring surface)
// ---------------------------------------------------------------------------

/// Which of the selected node's animatable channels are tracked, and each
/// track's key times — the one read behind every inspector keyframe **diamond**
/// and the tracked-vs-static routing of every inspector field.
///
/// **A named slice, keyed by wire string** (docs/v3/08 §2): a property absent
/// from [keyTimes] has no track, so its diamond shows empty and its field writes
/// the static pose; a property present is tracked, so its diamond reflects the
/// playhead and its field upserts the keyframe. The slice never reads the
/// playhead — the diamond leaf combines these key times with the live
/// `playheadProvider` to tell "on a key" from "between keys", so **scrubbing
/// rebuilds nothing here** (AC-13.3), only the diamond leaf repaints.
///
/// It is value-projected so an edit that leaves every key list untouched (a
/// colour changed, a node dragged) yields an equal view and no rebuild.
@immutable
final class InspectorTracksView {
  const InspectorTracksView(this.keyTimes);

  static const InspectorTracksView empty =
      InspectorTracksView(<String, List<double>>{});

  /// `PropertyKey.wire` → the track's key times, in order. Absent = untracked.
  final Map<String, List<double>> keyTimes;

  /// The key times for [property], or null when it has no track.
  List<double>? operator [](PropertyKey property) => keyTimes[property.wire];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InspectorTracksView) return false;
    if (other.keyTimes.length != keyTimes.length) return false;
    for (final entry in keyTimes.entries) {
      final theirs = other.keyTimes[entry.key];
      if (theirs == null || theirs.length != entry.value.length) return false;
      for (var i = 0; i < theirs.length; i++) {
        if (theirs[i] != entry.value[i]) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var h = 0;
    // XOR so the hash is independent of the map's iteration order.
    for (final entry in keyTimes.entries) {
      h ^= Object.hash(entry.key, Object.hashAll(entry.value));
    }
    return h;
  }
}

/// The animatable channels the inspector draws a diamond for, on the one
/// selected node, in the active animation. `pivot`, `visible` and the trim
/// channels are deliberately absent: `pivot`/`visible` have no inspector field
/// and trim is a still-unbuilt seam. `path` **is** present — it has no *field*
/// (a `PathPose` is edited on the canvas by direct-select), but it carries the
/// inspector's path **diamond**, the one hand affordance that authors the first
/// path keyframe (F6.1). A dangling or many/zero selection resolves to
/// [InspectorTracksView.empty] — every diamond empty, never a crash
/// (docs/v3/08 §2).
final inspectorTracksProvider =
    Provider.autoDispose.family<InspectorTracksView, String>((ref, projectId) {
  final ids = ref.watch(inspectorSelectionProvider);
  if (ids.length != 1) return InspectorTracksView.empty;
  final id = ids.single;
  final animationId = ref.watch(activeAnimationProvider(projectId));

  return ref.watch(documentControllerProvider(projectId).select((async) {
    final doc = async.valueOrNull;
    final node = doc?.nodeIndex[id];
    if (doc == null || node == null || animationId == null) {
      return InspectorTracksView.empty;
    }

    var tracks = TrackSet.empty;
    for (final animation in doc.animations) {
      if (animation.id == animationId) {
        tracks = animation.tracksFor(id);
        break;
      }
    }

    final times = <String, List<double>>{};
    void add(PropertyKey key) {
      final track = tracks.byKey[key];
      if (track != null) {
        times[key.wire] = List<double>.unmodifiable(track.keyTimes);
      }
    }

    add(const PropertyKey(PropKey.position));
    add(const PropertyKey(PropKey.scale));
    add(const PropertyKey(PropKey.rotation));
    add(const PropertyKey(PropKey.skewX));
    add(const PropertyKey(PropKey.opacity));
    if (node is PathNode) {
      // The path diamond's key times — the row has no field, but the diamond
      // reads this exactly like every other channel.
      add(const PropertyKey(PropKey.path));
      if (node.fills.isNotEmpty) {
        final fillId = node.fills.first.id.v;
        add(PropertyKey(PropKey.fillColor, fillId));
        add(PropertyKey(PropKey.fillOpacity, fillId));
      }
      if (node.strokes.isNotEmpty) {
        final strokeId = node.strokes.first.id.v;
        add(PropertyKey(PropKey.strokeColor, strokeId));
        add(PropertyKey(PropKey.strokeOpacity, strokeId));
        add(PropertyKey(PropKey.strokeWidth, strokeId));
      }
    }
    return InspectorTracksView(Map<String, List<double>>.unmodifiable(times));
  }));
});

// ---------------------------------------------------------------------------
// Sampled field values — the WYSIWYG half of edit-at-keyframe (AC-6.2.6)
// ---------------------------------------------------------------------------

/// The selected node's typed tracks for its **numeric/colour fields**, so a
/// tracked field can show the value the canvas is showing — sampled at the live
/// playhead — instead of the static rest pose (AC-6.2.6, UX §3 "that keyframe
/// loads onto the field").
///
/// **A leaf reads this and samples inside a `ValueListenableBuilder` on the
/// playhead** (the diamond's pattern), so a scrub repaints only the field's text
/// and rebuilds no panel (AC-13.3): the view here does not read the playhead and
/// so does not change on a scrub.
///
/// **Value-equal by track *identity*.** anim_core's ops thread the `animations`
/// list through untouched on an edit that does not touch a track, so an unrelated
/// commit (a node dragged, the rest pose moved) yields the *same* `Track` objects
/// and an equal view — nothing rebuilds. A keyframe *value* edit mints a new
/// track object, which is exactly when the field must re-read, so the view is
/// then unequal and the leaf rebuilds. `path` is absent: it has a diamond, not a
/// field, and nothing samples it here.
@immutable
final class InspectorSamplesView {
  const InspectorSamplesView(this.tracks);

  static const InspectorSamplesView empty =
      InspectorSamplesView(<PropertyKey, Track>{});

  final Map<PropertyKey, Track> tracks;

  /// The track for [property], or null when it is untracked.
  Track? operator [](PropertyKey property) => tracks[property];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InspectorSamplesView) return false;
    if (other.tracks.length != tracks.length) return false;
    for (final entry in tracks.entries) {
      if (!identical(other.tracks[entry.key], entry.value)) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var h = 0;
    // XOR so the hash is independent of iteration order.
    for (final entry in tracks.entries) {
      h ^= Object.hash(entry.key, identityHashCode(entry.value));
    }
    return h;
  }
}

/// The typed tracks behind the one selected node's fields — the read every
/// tracked field's displayed value is sampled from. Same walk as
/// [inspectorTracksProvider], but keeping the track objects (not just key times)
/// and comparing by identity, because it feeds *values*, not dot positions.
final inspectorSamplesProvider =
    Provider.autoDispose.family<InspectorSamplesView, String>((ref, projectId) {
  final ids = ref.watch(inspectorSelectionProvider);
  if (ids.length != 1) return InspectorSamplesView.empty;
  final id = ids.single;
  final animationId = ref.watch(activeAnimationProvider(projectId));

  return ref.watch(documentControllerProvider(projectId).select((async) {
    final doc = async.valueOrNull;
    final node = doc?.nodeIndex[id];
    if (doc == null || node == null || animationId == null) {
      return InspectorSamplesView.empty;
    }

    var tracks = TrackSet.empty;
    for (final animation in doc.animations) {
      if (animation.id == animationId) {
        tracks = animation.tracksFor(id);
        break;
      }
    }

    final out = <PropertyKey, Track>{};
    void add(PropertyKey key) {
      final track = tracks.byKey[key];
      if (track != null) out[key] = track;
    }

    add(const PropertyKey(PropKey.position));
    add(const PropertyKey(PropKey.scale));
    add(const PropertyKey(PropKey.rotation));
    add(const PropertyKey(PropKey.skewX));
    add(const PropertyKey(PropKey.opacity));
    if (node is PathNode) {
      if (node.fills.isNotEmpty) {
        final fillId = node.fills.first.id.v;
        add(PropertyKey(PropKey.fillColor, fillId));
        add(PropertyKey(PropKey.fillOpacity, fillId));
      }
      if (node.strokes.isNotEmpty) {
        final strokeId = node.strokes.first.id.v;
        add(PropertyKey(PropKey.strokeColor, strokeId));
        add(PropertyKey(PropKey.strokeOpacity, strokeId));
        add(PropertyKey(PropKey.strokeWidth, strokeId));
      }
    }
    return InspectorSamplesView(Map<PropertyKey, Track>.unmodifiable(out));
  }));
});

// ---------------------------------------------------------------------------
// Paint — F5.1
// ---------------------------------------------------------------------------

/// Why a paint is shown read-only instead of with a colour control, or null when
/// it is an ordinary solid colour.
///
/// **This is the gradient guard, at the UI end** (AC-5.1.3).
/// `PaintOps.setFillColor` / `setStrokeColor` *throw* on a non-solid paint,
/// deliberately: overwriting a gradient with one flat colour is a destructive
/// edit this build could not undo by re-authoring, because there is no gradient
/// UI to put it back with. So the panel does not offer a control that would
/// throw — it says why in plain language and leaves the paint alone.
///
/// No exhaustive `switch` (docs/v3/08 §2 bans them in `lib/app/`): a fourth
/// `PaintSource` variant added in v2 must degrade to the last line here, not
/// stop this file compiling.
String? paintReadOnlyReason(PaintSource paint) {
  if (paint is SolidPaint) return null;
  if (paint is LinearGradientPaint || paint is RadialGradientPaint) {
    return kGradientPaintMessage;
  }
  return kUnreadablePaintMessage;
}

/// Shown in place of the colour control for a gradient-painted node.
///
/// Names no roadmap code and makes no promise about when — the person
/// docs/v3/00 §5 sends through the ship gate needs to know that what they see is
/// the file's real appearance and that this editor will not damage it, which is
/// the whole answer.
const String kGradientPaintMessage =
    'This paint is a gradient. It is drawn exactly as it was saved, but it '
    'cannot be edited here — replacing it with a single colour would throw away '
    'colours this editor has no way to put back.';

/// Shown for a `paint.type` this build has never heard of (docs/v3/02 §7).
const String kUnreadablePaintMessage =
    'This paint was written by a newer editor. It is kept exactly as it was '
    'saved, and it cannot be edited here.';

/// One fill, projected to values the panel can compare (`Fill` has no `==`).
@immutable
final class FillView {
  const FillView({
    required this.id,
    required this.color,
    required this.readOnlyReason,
    required this.rule,
    required this.opacity,
    required this.visible,
  });

  /// The **`PaintId`, never a list index** — a `PaintId` is a track's
  /// `subjectId` and it is what every edit is addressed by. Indices shift the
  /// moment a document from a newer client carries two fills (AC-5.1.6), and an
  /// index-addressed edit would then land on the wrong paint.
  final PaintId id;

  /// Null exactly when [readOnlyReason] is non-null.
  final Rgba? color;
  final String? readOnlyReason;

  final FillRule rule;
  final double opacity;
  final bool visible;

  @override
  bool operator ==(Object other) =>
      other is FillView &&
      other.id == id &&
      other.color == color &&
      other.readOnlyReason == readOnlyReason &&
      other.rule == rule &&
      other.opacity == opacity &&
      other.visible == visible;

  @override
  int get hashCode =>
      Object.hash(id, color, readOnlyReason, rule, opacity, visible);
}

/// One stroke, projected to values the panel can compare (`Stroke` has no `==`).
@immutable
final class StrokeView {
  const StrokeView({
    required this.id,
    required this.color,
    required this.readOnlyReason,
    required this.width,
    required this.cap,
    required this.join,
    required this.miterLimit,
    required this.opacity,
    required this.visible,
  });

  final PaintId id;
  final Rgba? color;
  final String? readOnlyReason;
  final double width;
  final StrokeCap cap;
  final StrokeJoin join;
  final double miterLimit;
  final double opacity;
  final bool visible;

  @override
  bool operator ==(Object other) =>
      other is StrokeView &&
      other.id == id &&
      other.color == color &&
      other.readOnlyReason == readOnlyReason &&
      other.width == width &&
      other.cap == cap &&
      other.join == join &&
      other.miterLimit == miterLimit &&
      other.opacity == opacity &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(id, color, readOnlyReason, width, cap, join,
      miterLimit, opacity, visible);
}

/// The selected path node's paint — **at most one fill and one stroke**, plus
/// the honest counts.
///
/// The v1 UI caps each list at 0 or 1 (docs/v3/01 §6) and edits the *first*
/// (AC-5.1.6). [fillCount] / [strokeCount] exist so a document from a newer
/// client with two fills can say so rather than pretending the second is not
/// there — the acceptance criterion is "both fills round-trip, the UI edits only
/// the first, **no silent truncation**", and silence is the part that would make
/// a user delete work they cannot see.
@immutable
final class NodePaintView {
  const NodePaintView({
    required this.node,
    required this.fill,
    required this.stroke,
    required this.fillCount,
    required this.strokeCount,
  });

  final NodeId node;
  final FillView? fill;
  final StrokeView? stroke;
  final int fillCount;
  final int strokeCount;

  @override
  bool operator ==(Object other) =>
      other is NodePaintView &&
      other.node == node &&
      other.fill == fill &&
      other.stroke == stroke &&
      other.fillCount == fillCount &&
      other.strokeCount == strokeCount;

  @override
  int get hashCode => Object.hash(node, fill, stroke, fillCount, strokeCount);
}

/// Paint for the one selected `PathNode`, or null when the selection is not
/// exactly one path node.
///
/// A **second named slice** rather than a wider [inspectorTargetProvider]: a
/// transform commit and a paint commit then rebuild different sub-trees, which
/// is the whole point of reading slices (docs/v3/08 §2). A group is null here
/// because paint hangs off path nodes only — `PaintOps` refuses anything else,
/// and offering an "Add fill" button that throws would be a stub that reads as a
/// bug.
final inspectorPaintProvider =
    Provider.autoDispose.family<NodePaintView?, String>((ref, projectId) {
  final ids = ref.watch(inspectorSelectionProvider);
  if (ids.length != 1) return null;
  final id = ids.single;

  return ref.watch(documentControllerProvider(projectId).select((async) {
    final node = async.valueOrNull?.nodeIndex[id];
    if (node is! PathNode) return null;

    final fill = node.fills.isEmpty ? null : node.fills.first;
    final stroke = node.strokes.isEmpty ? null : node.strokes.first;
    return NodePaintView(
      node: id,
      fill: fill == null
          ? null
          : FillView(
              id: fill.id,
              color: fill.paint is SolidPaint
                  ? (fill.paint as SolidPaint).color
                  : null,
              readOnlyReason: paintReadOnlyReason(fill.paint),
              rule: fill.rule,
              opacity: fill.opacity,
              visible: fill.visible,
            ),
      stroke: stroke == null
          ? null
          : StrokeView(
              id: stroke.id,
              color: stroke.paint is SolidPaint
                  ? (stroke.paint as SolidPaint).color
                  : null,
              readOnlyReason: paintReadOnlyReason(stroke.paint),
              width: stroke.width,
              cap: stroke.cap,
              join: stroke.join,
              miterLimit: stroke.miterLimit,
              opacity: stroke.opacity,
              visible: stroke.visible,
            ),
      fillCount: node.fills.length,
      strokeCount: node.strokes.length,
    );
  }));
});

// ---------------------------------------------------------------------------
// Shape parameters — AC-4.1.5
// ---------------------------------------------------------------------------

/// Shown for a recipe this build cannot read (docs/v3/02 §7).
///
/// `PathOps.regenerateRecipe` refuses an `UnknownRecipe` because regenerating
/// from one would replace real geometry with nothing — the user's artwork
/// vanishing on a re-edit. There are also no parameters to draw fields for, so
/// the section is a sentence and nothing else.
const String kUnreadableRecipeMessage =
    'This shape was created by a newer editor. Its outline is kept exactly as '
    'it was saved, but its settings cannot be changed here.';

/// The selected node's `ShapeRecipe` and whether it may be regenerated.
@immutable
final class NodeShapeView {
  const NodeShapeView({
    required this.node,
    required this.recipe,
    required this.refusal,
  });

  final NodeId node;

  /// Value-equal for all four variants, so this view dedups like the rest.
  final ShapeRecipe recipe;

  /// Non-null means **the fields render disabled and carry this sentence**.
  ///
  /// The only refusal left after M5 is a recipe this build cannot read
  /// ([kUnreadableRecipeMessage]): a tracked node is no longer refused — its edit
  /// routes through `PathOps.retopologize` — so tracked-ness never disables a
  /// field here. An [UnknownRecipe] draws no fields at all, so nothing beneath
  /// this sentence could be committed; `PathOps.regenerateRecipe` refuses one as
  /// the backstop, and the control the user sees and the write behind it agree.
  final String? refusal;

  @override
  bool operator ==(Object other) =>
      other is NodeShapeView &&
      other.node == node &&
      other.recipe == recipe &&
      other.refusal == refusal;

  @override
  int get hashCode => Object.hash(node, recipe, refusal);
}

/// The one selected node's shape parameters, or null when it has no recipe.
///
/// Null is the normal state: everything the pen tool draws has no recipe, and
/// `PathOps.moveAnchor` nulls it the moment an anchor is edited by hand
/// (docs/v3/01 §5's authority rule). The section simply is not there, rather
/// than being there and empty.
final inspectorShapeProvider =
    Provider.autoDispose.family<NodeShapeView?, String>((ref, projectId) {
  final ids = ref.watch(inspectorSelectionProvider);
  if (ids.length != 1) return null;
  final id = ids.single;

  return ref.watch(documentControllerProvider(projectId).select((async) {
    final doc = async.valueOrNull;
    final node = doc?.nodeIndex[id];
    if (doc == null || node is! PathNode) return null;
    final recipe = node.recipe;
    if (recipe == null) return null;
    return NodeShapeView(
      node: id,
      recipe: recipe,
      // A tracked node is **no longer refused** — its regeneration routes through
      // `PathOps.retopologize` (AC-4.1.5, see `InspectorCommands.regenerateRecipe`),
      // so its fields are editable. The only refusal left is an `UnknownRecipe`:
      // this build cannot read it, so it must never overwrite the outline it did
      // not create (docs/v3/02 §7).
      refusal: recipe is UnknownRecipe ? kUnreadableRecipeMessage : null,
    );
  }));
});
