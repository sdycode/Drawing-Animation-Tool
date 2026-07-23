import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
// `StrokeCap` and `StrokeJoin` are `dart:ui`'s here and anim_core's in the
// domain — the same landmine `hide Animation` defuses one line up. The
// inspector authors the *domain* enums and paints nothing, so Flutter's lose.
import 'package:flutter/material.dart' hide StrokeCap, StrokeJoin;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/color_field.dart';
import '../../../common/number_field.dart';
import '../commands.dart';
import '../providers.dart';

/// The Inspector — numeric/typed editing of the selected node's values
/// (docs/v3/05 §2, F3.1).
///
/// **Reads one named slice** (docs/v3/08 §2): [inspectorTargetProvider], which is
/// value-projected, so editing an anchor on another node or scrubbing rebuilds
/// nothing here. With exactly one node selected it shows that node's
/// `Transform2`; with 0 or >1 it shows a calm summary, never a crash.
///
/// **Degrees in, radians stored.** Rotation and skew are shown in degrees for
/// humans but committed as **unbounded radians** — typing 720 stores `4π`, no
/// wrap, no shortest-arc (AC-3.1.2). The panel never re-implements `toAffine`;
/// it writes fields and lets anim_core compose (AC-3.1.1). **Percent in, 0..1
/// stored** for opacity is the same split, and the value shown is always the
/// node's *own* — the PRODUCT down the ancestor chain (AC-2.2.5) is the
/// evaluator's and is never mirrored here (docs/v3/08 §4).
///
/// **Every field releases focus on commit.** [CommittedNumberField] unfocuses on
/// Enter/blur so the next `Cmd/Ctrl+Z` reaches the editor's undo and not the
/// browser's text-field undo (docs/v3/05 §5).
class InspectorPanel extends ConsumerWidget {
  const InspectorPanel({required this.projectId, super.key});

  final String projectId;

  static const double _radToDeg = 180.0 / math.pi;
  static const double _degToRad = math.pi / 180.0;

  /// Rebuild counter for the isolation tests (the pattern `CanvasView`
  /// established). The slice below is value-projected and refuses to notify on
  /// an unrelated commit — but a panel whose *parent* rebuilt rebuilds anyway,
  /// and only a mounted-widget assertion can see the difference. It fired once
  /// per committed keystroke before the shell stopped handing the document down.
  static int debugBuildCount = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugBuildCount++;
    final target = ref.watch(inspectorTargetProvider(projectId));
    final scheme = Theme.of(context).colorScheme;

    return Container(
      key: const Key('inspector-panel'),
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _railHeader(context, 'Inspector'),
          Expanded(
            child: target.node == null
                ? _summary(context, target.selectionCount)
                : _transformEditor(context, ref, target.node!),
          ),
        ],
      ),
    );
  }

  /// The calm 0-or-many state (docs/v3/05 §2). No crash, no half-populated form.
  Widget _summary(BuildContext context, int count) {
    final scheme = Theme.of(context).colorScheme;
    final message = count == 0
        ? 'Select a layer to edit its transform.'
        : '$count layers selected.\nSelect one to edit its transform.';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        key: const Key('inspector-summary'),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _transformEditor(
      BuildContext context, WidgetRef ref, NodeTransformView view) {
    final scheme = Theme.of(context).colorScheme;
    final t = view.transform;

    if (view.isUnknown) {
      // An unknown node's transform lives in raw JSON; editing it would be
      // dropped on save, so it is read-only by design, not by omission.
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'This layer was written by a newer editor and is read-only.',
          key: const Key('inspector-unknown'),
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      );
    }

    void commit(Transform2 next) => _commit(context, ref, view.id, next);

    return ListView(
      key: const Key('inspector-transform'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        Text(view.name.isEmpty ? 'Untitled' : view.name,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        const SizedBox(height: 4),
        Text('Transform',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        _pair(
          label: 'Position',
          xKey: 'inspector-position-x',
          yKey: 'inspector-position-y',
          x: t.position.x,
          y: t.position.y,
          onX: (v) => commit(t.copyWith(position: Vec2(v, t.position.y))),
          onY: (v) => commit(t.copyWith(position: Vec2(t.position.x, v))),
        ),
        _pair(
          label: 'Scale',
          xKey: 'inspector-scale-x',
          yKey: 'inspector-scale-y',
          x: t.scale.x,
          y: t.scale.y,
          onX: (v) => commit(t.copyWith(scale: Vec2(v, t.scale.y))),
          onY: (v) => commit(t.copyWith(scale: Vec2(t.scale.x, v))),
        ),
        _pair(
          label: 'Pivot',
          xKey: 'inspector-pivot-x',
          yKey: 'inspector-pivot-y',
          x: t.pivot.x,
          y: t.pivot.y,
          // A pivot edit re-renders the node about the new pivot without touching
          // its untransformed geometry — that falls out of Transform2, we only
          // write the field (AC-3.1.3).
          onX: (v) => commit(t.copyWith(pivot: Vec2(v, t.pivot.y))),
          onY: (v) => commit(t.copyWith(pivot: Vec2(t.pivot.x, v))),
        ),
        _single(
          label: 'Rotation (°)',
          fieldKey: 'inspector-rotation',
          value: t.rotation * _radToDeg,
          onCommit: (deg) => commit(t.copyWith(rotation: deg * _degToRad)),
        ),
        _single(
          label: 'Skew X (°)',
          fieldKey: 'inspector-skewx',
          value: t.skewX * _radToDeg,
          onCommit: (deg) => commit(t.copyWith(skewX: deg * _degToRad)),
        ),
        const SizedBox(height: 8),
        Text('Appearance',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        // **This node's own opacity, shown as percent and stored as 0..1** —
        // the same display-vs-storage split rotation makes between degrees and
        // radians. AC-2.2.5's `worldOpacity` PRODUCT over the ancestor chain is
        // the evaluator's and is deliberately NOT shown here: a second,
        // "effective" number beside the authored one is the derived-state
        // desync docs/v3/08 §4 forbids, and it would not be editable anyway.
        // Until this field existed the rule was unobservable in the product —
        // M2's contents row claimed the `opacity` PRODUCT with no control able
        // to set either factor.
        _single(
          label: 'Opacity (%)',
          fieldKey: 'inspector-opacity',
          value: view.opacity * 100,
          onCommit: (percent) => _commitOpacity(context, ref, view.id, percent),
        ),
        const SizedBox(height: 16),
        // Fill above stroke, because **fills paint before strokes, always**
        // (docs/v3/01 §6, AC-5.1.5). The ordering is the renderer's, expressed
        // by `fills` and `strokes` being two fields — so the panel reads top to
        // bottom in paint order and offers no reorder, no z-index and no "bring
        // to front" to disagree with it.
        _PaintSection(projectId: projectId),
        _ShapeSection(projectId: projectId),
        const SizedBox(height: 16),
        Text('Not yet available',
            key: const Key('inspector-seams'),
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        _seam(context, 'Draw-on trim'),
        _seam(context, 'Easing between keyframes'),
        _seam(context, 'Corner and smooth anchors'),
      ],
    );
  }

  /// One field edit is one whole `Transform2` and one undo entry — the panel
  /// composes the next value and lets anim_core compose the matrix (AC-3.1.1).
  void _commit(
      BuildContext context, WidgetRef ref, NodeId id, Transform2 next) {
    _report(context, InspectorCommands(ref, projectId).setTransform(id, next));
  }

  /// Percent in, **0..1 stored**. Out-of-range typing is clamped by
  /// `NodeOps.setOpacity` at the mutation rather than by the field, so the
  /// document never holds an authored 1.7 and the user still sees what took.
  void _commitOpacity(
      BuildContext context, WidgetRef ref, NodeId id, double percent) {
    _report(context,
        InspectorCommands(ref, projectId).setOpacity(id, percent / 100));
  }

  Widget _pair({
    required String label,
    required String xKey,
    required String yKey,
    required double x,
    required double y,
    required ValueChanged<double> onX,
    required ValueChanged<double> onY,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(label),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: CommittedNumberField(
                    key: Key(xKey),
                    label: 'X',
                    value: x,
                    onCommit: onX,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CommittedNumberField(
                    key: Key(yKey),
                    label: 'Y',
                    value: y,
                    onCommit: onY,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _single({
    required String label,
    required String fieldKey,
    required double value,
    required ValueChanged<double> onCommit,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(label),
            const SizedBox(height: 4),
            CommittedNumberField(
              key: Key(fieldKey),
              value: value,
              onCommit: onCommit,
            ),
          ],
        ),
      );

  Widget _fieldLabel(String text) => Builder(
        builder: (context) => Text(
          text,
          style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  /// A named-but-absent editor, in **plain language**.
  ///
  /// These rows used to read "Fill / M3" and "Path trim / M4". A milestone code
  /// is this project's internal vocabulary; the person docs/v3/00 §5 sends
  /// through the ship gate has never read the roadmap, and "M4" beside a
  /// control tells them nothing about whether the tool is broken or unfinished.
  /// They stay non-interactive on purpose: a stub that opens an empty editor
  /// would be a worse lie than an honest absence.
  Widget _seam(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('$title — not yet available',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ),
    );
  }

  Widget _railHeader(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: scheme.surfaceContainerHigh,
      child: Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant)),
    );
  }
}

/// Capture the messenger before the await, and **handle `onError`**: anything
/// that escapes `InspectorCommands._guard` would otherwise complete this dropped
/// future with an error nobody listens for, which Flutter reports as an
/// unhandled async error instead of the snackbar this function exists for.
///
/// Top-level and shared by every section in this file, so a new control cannot
/// be wired up with a bare `unawaited(...)` that loses the refusal — which is
/// the only way a user would ever learn that an edit did not take.
void _report(BuildContext context, Future<String?> pending) {
  final messenger = ScaffoldMessenger.of(context);
  void show(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));
  pending.then(
    (message) {
      if (message != null) show(message);
    },
    onError: (Object _, StackTrace __) => show(kRejectedInspectorEditMessage),
  );
}

/// Solid fill and solid stroke authoring — F5.1.
///
/// **Its own `ConsumerWidget` reading its own named slice**
/// ([inspectorPaintProvider]), so a transform commit and a paint commit rebuild
/// different sub-trees and neither rebuilds the other (docs/v3/08 §2). It is
/// absent entirely for a group: paint hangs off path nodes only, and an "Add
/// fill" button that threw would be a stub that reads as a bug.
///
/// **One fill and one stroke, and no more** (docs/v3/01 §6). They are lists in
/// the model so widening is additive, but this build authors the first of each
/// and *says so* when a document from a newer client carries more — AC-5.1.6's
/// requirement is round-trip plus no silent truncation, and silence is the half
/// that makes a user delete work they cannot see.
class _PaintSection extends ConsumerWidget {
  const _PaintSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(inspectorPaintProvider(projectId));
    if (view == null) return const SizedBox.shrink();
    return Column(
      key: const Key('inspector-paint'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupLabel(context, 'Fill'),
        _fill(context, ref, view),
        const SizedBox(height: 12),
        _groupLabel(context, 'Stroke'),
        _stroke(context, ref, view),
      ],
    );
  }

  InspectorCommands _commands(WidgetRef ref) =>
      InspectorCommands(ref, projectId);

  Widget _fill(BuildContext context, WidgetRef ref, NodePaintView view) {
    final fill = view.fill;
    if (fill == null) {
      return _addButton(
        keyName: 'inspector-add-fill',
        label: 'Add fill',
        onPressed: () => _report(context, _commands(ref).addFill(view.node)),
      );
    }
    final reason = fill.readOnlyReason;
    if (reason != null) {
      return _readOnlyPaint(context, 'inspector-fill-readonly', reason);
    }

    final commands = _commands(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.fillCount > 1) _extraPaints(context, 'fill', view.fillCount),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CommittedColorField(
            key: const Key('inspector-fill-color'),
            value: fill.color!,
            onCommit: (color) => _report(
                context, commands.setFillColor(view.node, fill.id, color)),
          ),
        ),
        _labelled(
          'Opacity (%)',
          CommittedNumberField(
            key: const Key('inspector-fill-opacity'),
            value: fill.opacity * 100,
            onCommit: (percent) => _report(context,
                commands.setFillOpacity(view.node, fill.id, percent / 100)),
          ),
        ),
        // AC-5.1.4 — the winding rule of a self-intersecting outline. It is a
        // property of the fill, not of the path: two fills on one shape may
        // legitimately disagree about it.
        _enumRow<FillRule>(
          label: 'Rule',
          keyPrefix: 'inspector-fill-rule',
          values: FillRule.values,
          selected: fill.rule,
          labels: _fillRuleLabels,
          onSelect: (rule) =>
              _report(context, commands.setFillRule(view.node, fill.id, rule)),
        ),
        _toggleRow(
          label: 'Visible',
          keyName: 'inspector-fill-visible',
          value: fill.visible,
          onChanged: (visible) => _report(
              context, commands.setFillVisible(view.node, fill.id, visible)),
        ),
        _removeButton(
          keyName: 'inspector-fill-remove',
          label: 'Remove fill',
          onPressed: () =>
              _report(context, commands.removeFill(view.node, fill.id)),
        ),
      ],
    );
  }

  Widget _stroke(BuildContext context, WidgetRef ref, NodePaintView view) {
    final stroke = view.stroke;
    if (stroke == null) {
      return _addButton(
        keyName: 'inspector-add-stroke',
        label: 'Add stroke',
        onPressed: () => _report(context, _commands(ref).addStroke(view.node)),
      );
    }
    final reason = stroke.readOnlyReason;
    if (reason != null) {
      return _readOnlyPaint(context, 'inspector-stroke-readonly', reason);
    }

    final commands = _commands(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.strokeCount > 1)
          _extraPaints(context, 'stroke', view.strokeCount),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CommittedColorField(
            key: const Key('inspector-stroke-color'),
            value: stroke.color!,
            onCommit: (color) => _report(
                context, commands.setStrokeColor(view.node, stroke.id, color)),
          ),
        ),
        _labelled(
          'Width',
          CommittedNumberField(
            key: const Key('inspector-stroke-width'),
            value: stroke.width,
            onCommit: (width) => _report(
                context, commands.setStrokeWidth(view.node, stroke.id, width)),
          ),
        ),
        _enumRow<StrokeCap>(
          label: 'Cap',
          keyPrefix: 'inspector-stroke-cap',
          values: StrokeCap.values,
          selected: stroke.cap,
          labels: _capLabels,
          onSelect: (cap) => _report(
              context, commands.setStrokeCap(view.node, stroke.id, cap)),
        ),
        _enumRow<StrokeJoin>(
          label: 'Join',
          keyPrefix: 'inspector-stroke-join',
          values: StrokeJoin.values,
          selected: stroke.join,
          labels: _joinLabels,
          onSelect: (join) => _report(
              context, commands.setStrokeJoin(view.node, stroke.id, join)),
        ),
        // A ratio of miter length to stroke width, so it is meaningless below 1
        // and the op refuses it there. Shown next to `Join` because it only does
        // anything for a miter join.
        _labelled(
          'Miter limit',
          CommittedNumberField(
            key: const Key('inspector-stroke-miter'),
            value: stroke.miterLimit,
            onCommit: (limit) => _report(context,
                commands.setStrokeMiterLimit(view.node, stroke.id, limit)),
          ),
        ),
        _labelled(
          'Opacity (%)',
          CommittedNumberField(
            key: const Key('inspector-stroke-opacity'),
            value: stroke.opacity * 100,
            onCommit: (percent) => _report(context,
                commands.setStrokeOpacity(view.node, stroke.id, percent / 100)),
          ),
        ),
        _toggleRow(
          label: 'Visible',
          keyName: 'inspector-stroke-visible',
          value: stroke.visible,
          onChanged: (visible) => _report(context,
              commands.setStrokeVisible(view.node, stroke.id, visible)),
        ),
        _removeButton(
          keyName: 'inspector-stroke-remove',
          label: 'Remove stroke',
          onPressed: () =>
              _report(context, commands.removeStroke(view.node, stroke.id)),
        ),
      ],
    );
  }

  /// A gradient or an unrecognised paint: **shown, explained, and left alone**
  /// (AC-5.1.3).
  ///
  /// There is no control at all here — not a colour field, not opacity, not
  /// even a remove button. `PaintOps.setFillColor` throws on a non-solid paint
  /// on purpose, and every control this section could draw would either trip
  /// that throw or invite the user to discard authoring this build has no way to
  /// recreate. The row says which, in a sentence, and stops.
  Widget _readOnlyPaint(BuildContext context, String keyName, String reason) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: Key(keyName),
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(reason,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    );
  }

  /// AC-5.1.6's anti-truncation notice.
  Widget _extraPaints(BuildContext context, String what, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: Key('inspector-extra-${what}s'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'This layer has $count ${what}s. The first is shown here; the others '
        'are kept exactly as they were saved.',
        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Shape-parameter re-editing — AC-4.1.5.
///
/// A [ShapeRecipe] is inert metadata about how a shape tool generated the node's
/// anchors, so "make that rectangle 20 units wider" stays a one-field edit
/// instead of a manual drag of four anchors. Editing one regenerates the
/// geometry through the **one sanctioned route**, `PathOps.regenerateRecipe`.
///
/// **Disabled, with the reason on screen, on a node whose path is animated.**
/// The op refuses that case because regeneration mints fresh `AnchorId`s while
/// every existing keyframe poses the old ones; the correct answer is arc-length
/// correspondence, which does not exist yet. The predicate and its sentence come
/// from `state/recipe_guard.dart` — the same ones the command gate uses — so a
/// field can never look editable while the write behind it is refused.
class _ShapeSection extends ConsumerWidget {
  const _ShapeSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(inspectorShapeProvider(projectId));
    if (view == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final enabled = view.refusal == null;

    void commit(ShapeRecipe next) => _report(context,
        InspectorCommands(ref, projectId).regenerateRecipe(view.node, next));

    return Column(
      key: const Key('inspector-shape'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _groupLabel(context, 'Shape'),
        if (view.refusal != null)
          Padding(
            key: const Key('inspector-shape-disabled'),
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(view.refusal!,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
        ..._fields(view.recipe, enabled, commit),
      ],
    );
  }

  /// Dispatch by recipe kind **without an exhaustive switch** (docs/v3/08 §2):
  /// a fourth shape added in v2 must fall through to "no fields", not stop this
  /// panel compiling. An `UnknownRecipe` has no readable parameters at all, so
  /// the section above it is the whole answer.
  List<Widget> _fields(
      ShapeRecipe recipe, bool enabled, ValueChanged<ShapeRecipe> commit) {
    if (recipe is RectRecipe) {
      return [
        _number(
            'Width',
            'inspector-shape-w',
            recipe.w,
            enabled,
            (v) => commit(RectRecipe(
                w: v, h: recipe.h, cornerRadius: recipe.cornerRadius))),
        _number(
            'Height',
            'inspector-shape-h',
            recipe.h,
            enabled,
            (v) => commit(RectRecipe(
                w: recipe.w, h: v, cornerRadius: recipe.cornerRadius))),
        _number(
            'Corner radius',
            'inspector-shape-corner',
            recipe.cornerRadius,
            enabled,
            (v) =>
                commit(RectRecipe(w: recipe.w, h: recipe.h, cornerRadius: v))),
      ];
    }
    if (recipe is EllipseRecipe) {
      return [
        _number('Radius X', 'inspector-shape-rx', recipe.rx, enabled,
            (v) => commit(EllipseRecipe(rx: v, ry: recipe.ry))),
        _number('Radius Y', 'inspector-shape-ry', recipe.ry, enabled,
            (v) => commit(EllipseRecipe(rx: recipe.rx, ry: v))),
      ];
    }
    if (recipe is PolygonRecipe) {
      PolygonRecipe next(
              {int? sides, double? radius, bool? star, double? inner}) =>
          PolygonRecipe(
            // The one deliberate `int` in the recipe types — a polygon with 5.5
            // sides is not a shape, so the field's double is rounded here rather
            // than truncated at the wire.
            sides: sides ?? recipe.sides,
            radius: radius ?? recipe.radius,
            star: star ?? recipe.star,
            innerRatio: inner ?? recipe.innerRatio,
          );
      return [
        _number('Sides', 'inspector-shape-sides', recipe.sides.toDouble(),
            enabled, (v) => commit(next(sides: v.round()))),
        _number('Radius', 'inspector-shape-radius', recipe.radius, enabled,
            (v) => commit(next(radius: v))),
        _toggleRow(
          label: 'Star',
          keyName: 'inspector-shape-star',
          value: recipe.star,
          onChanged: enabled ? (v) => commit(next(star: v)) : null,
        ),
        _number('Inner ratio', 'inspector-shape-inner', recipe.innerRatio,
            enabled, (v) => commit(next(inner: v))),
      ];
    }
    return const <Widget>[];
  }

  Widget _number(String label, String keyName, double value, bool enabled,
          ValueChanged<double> onCommit) =>
      _labelled(
        label,
        CommittedNumberField(
          key: Key(keyName),
          value: value,
          enabled: enabled,
          onCommit: onCommit,
        ),
      );
}

// ---------------------------------------------------------------------------
// Row helpers shared by the sections above
// ---------------------------------------------------------------------------

/// Enum labels as **maps with a fallback**, never an exhaustive `switch`
/// (docs/v3/08 §2): a `StrokeCap.squareRound` added in v2 should render as
/// `squareRound` and still be selectable, not break the build of five panels.
const Map<FillRule, String> _fillRuleLabels = {
  FillRule.nonZero: 'Nonzero',
  FillRule.evenOdd: 'Even-odd',
};

const Map<StrokeCap, String> _capLabels = {
  StrokeCap.butt: 'Butt',
  StrokeCap.round: 'Round',
  StrokeCap.square: 'Square',
};

const Map<StrokeJoin, String> _joinLabels = {
  StrokeJoin.miter: 'Miter',
  StrokeJoin.round: 'Round',
  StrokeJoin.bevel: 'Bevel',
};

Widget _groupLabel(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );

Widget _labelled(String label, Widget field) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(
            builder: (context) => Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 4),
          field,
        ],
      ),
    );

/// One row of mutually exclusive choices, one button per enum value.
///
/// Buttons rather than a dropdown because every option is visible without a
/// gesture — three short words fit the rail, and a menu that has to be opened to
/// see what the current join even is costs more than it saves.
Widget _enumRow<T extends Enum>({
  required String label,
  required String keyPrefix,
  required List<T> values,
  required T selected,
  required Map<T, String> labels,
  required ValueChanged<T> onSelect,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(
            builder: (context) => Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final value in values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Builder(builder: (context) {
                      final scheme = Theme.of(context).colorScheme;
                      final isSelected = value == selected;
                      return OutlinedButton(
                        key: Key('$keyPrefix-${value.name}'),
                        onPressed: () => onSelect(value),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: isSelected
                              ? scheme.secondaryContainer
                              : Colors.transparent,
                          foregroundColor: isSelected
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        child: Text(
                          labels[value] ?? value.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

/// A labelled switch. `null` [onChanged] is the disabled state — Flutter's own
/// idiom, so there is no second "enabled" flag to disagree with it.
Widget _toggleRow({
  required String label,
  required String keyName,
  required bool value,
  required ValueChanged<bool>? onChanged,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Builder(
              builder: (context) => Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          Switch(
            key: Key(keyName),
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );

Widget _addButton({
  required String keyName,
  required String label,
  required VoidCallback onPressed,
}) =>
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton(
        key: Key(keyName),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );

Widget _removeButton({
  required String keyName,
  required String label,
  required VoidCallback onPressed,
}) =>
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: Key(keyName),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
