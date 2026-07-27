import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
// `StrokeCap` and `StrokeJoin` are `dart:ui`'s here and anim_core's in the
// domain — the same landmine `hide Animation` defuses one line up. The
// inspector authors the *domain* enums and paints nothing, so Flutter's lose.
import 'package:flutter/material.dart' hide StrokeCap, StrokeJoin;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/color_field.dart';
import '../../../common/number_field.dart';
import '../../../state/editor_controller.dart';
import '../commands.dart';
import '../providers.dart';

// The animatable channels the inspector draws a diamond for. Paint channels
// carry a `PaintId` subject and are built at their call site off the shown
// paint; these five are subject-less.
const PropertyKey _kPosition = PropertyKey(PropKey.position);
const PropertyKey _kScale = PropertyKey(PropKey.scale);
const PropertyKey _kRotation = PropertyKey(PropKey.rotation);
const PropertyKey _kSkewX = PropertyKey(PropKey.skewX);
const PropertyKey _kOpacity = PropertyKey(PropKey.opacity);

/// The geometry channel — a diamond-only row (no field: a `PathPose` is edited
/// on the canvas by direct-select, F4.2). It is the one hand affordance that
/// authors the first path keyframe.
const PropertyKey _kPath = PropertyKey(PropKey.path);

/// The live playhead, normalised — read (never watched) at commit/click time, so
/// a keyframe lands at the `t` the canvas and timeline are showing.
double _playheadT(WidgetRef ref) {
  final t = ref.read(playheadProvider).value;
  return t.isNaN ? 0.0 : t.clamp(0.0, 1.0).toDouble();
}

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
    // Tracked-ness for every diamond and every field's routing, read as a named
    // slice (docs/v3/08 §2). It changes when a track is keyed or removed — not
    // when the playhead scrubs, so the fields never rebuild on a scrub.
    final tracks = ref.watch(inspectorTracksProvider(projectId));
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
                : _transformEditor(context, ref, target.node!, tracks),
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

  Widget _transformEditor(BuildContext context, WidgetRef ref,
      NodeTransformView view, InspectorTracksView tracks) {
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

    final cmds = InspectorCommands(ref, projectId);
    bool tracked(PropertyKey p) => tracks[p] != null;

    // The keyframe toggle for one channel: empty until keyed, then filled on a
    // key / hollow between keys (the diamond itself reads the live playhead).
    Widget diamond(PropertyKey property, Object? authored) => _KeyframeDiamond(
          keyName: 'kf-${property.wire}',
          keyTimes: tracks[property],
          onKey: () => _report(context,
              cmds.keyCurrent(view.id, property, _playheadT(ref), authored)),
          onRemoveAt: (index) =>
              _report(context, cmds.removeKeyAt(view.id, property, index)),
        );

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
        // Each animatable field carries a diamond and routes by tracked-ness:
        // tracked → upsert the keyframe at the playhead (edit-at-keyframe,
        // AC-6.2.6); untracked → write the static pose exactly as before. The
        // diamond and the field read the same `tracks` slice, so they never
        // disagree about which world they are in.
        _pair(
          label: 'Position',
          leading: diamond(_kPosition, t.position),
          xField: _numberField(
            projectId: projectId,
            fieldKey: 'inspector-position-x',
            label: 'X',
            tracked: tracked(_kPosition),
            property: _kPosition,
            staticDisplay: t.position.x,
            toDisplay: (s) => s is Vec2 ? s.x : t.position.x,
            onCommit: tracked(_kPosition)
                ? (v) => _report(
                    context,
                    cmds.keyVec2(
                        view.id, _kPosition, _playheadT(ref), t.position,
                        x: v))
                : (v) => commit(t.copyWith(position: Vec2(v, t.position.y))),
          ),
          yField: _numberField(
            projectId: projectId,
            fieldKey: 'inspector-position-y',
            label: 'Y',
            tracked: tracked(_kPosition),
            property: _kPosition,
            staticDisplay: t.position.y,
            toDisplay: (s) => s is Vec2 ? s.y : t.position.y,
            onCommit: tracked(_kPosition)
                ? (v) => _report(
                    context,
                    cmds.keyVec2(
                        view.id, _kPosition, _playheadT(ref), t.position,
                        y: v))
                : (v) => commit(t.copyWith(position: Vec2(t.position.x, v))),
          ),
        ),
        _pair(
          label: 'Scale',
          leading: diamond(_kScale, t.scale),
          xField: _numberField(
            projectId: projectId,
            fieldKey: 'inspector-scale-x',
            label: 'X',
            tracked: tracked(_kScale),
            property: _kScale,
            staticDisplay: t.scale.x,
            toDisplay: (s) => s is Vec2 ? s.x : t.scale.x,
            onCommit: tracked(_kScale)
                ? (v) => _report(
                    context,
                    cmds.keyVec2(view.id, _kScale, _playheadT(ref), t.scale,
                        x: v))
                : (v) => commit(t.copyWith(scale: Vec2(v, t.scale.y))),
          ),
          yField: _numberField(
            projectId: projectId,
            fieldKey: 'inspector-scale-y',
            label: 'Y',
            tracked: tracked(_kScale),
            property: _kScale,
            staticDisplay: t.scale.y,
            toDisplay: (s) => s is Vec2 ? s.y : t.scale.y,
            onCommit: tracked(_kScale)
                ? (v) => _report(
                    context,
                    cmds.keyVec2(view.id, _kScale, _playheadT(ref), t.scale,
                        y: v))
                : (v) => commit(t.copyWith(scale: Vec2(t.scale.x, v))),
          ),
        ),
        _pair(
          // Pivot is NOT animatable (docs/v3/01 §7 / §4), so it carries no
          // diamond and always writes the static transform.
          label: 'Pivot',
          // A pivot edit re-renders the node about the new pivot without touching
          // its untransformed geometry — that falls out of Transform2, we only
          // write the field (AC-3.1.3).
          xField: CommittedNumberField(
            key: const Key('inspector-pivot-x'),
            label: 'X',
            value: t.pivot.x,
            onCommit: (v) => commit(t.copyWith(pivot: Vec2(v, t.pivot.y))),
          ),
          yField: CommittedNumberField(
            key: const Key('inspector-pivot-y'),
            label: 'Y',
            value: t.pivot.y,
            onCommit: (v) => commit(t.copyWith(pivot: Vec2(t.pivot.x, v))),
          ),
        ),
        _single(
          label: 'Rotation (°)',
          leading: diamond(_kRotation, t.rotation),
          field: _numberField(
            projectId: projectId,
            fieldKey: 'inspector-rotation',
            tracked: tracked(_kRotation),
            property: _kRotation,
            staticDisplay: t.rotation * _radToDeg,
            toDisplay: (s) =>
                s is double ? s * _radToDeg : t.rotation * _radToDeg,
            onCommit: tracked(_kRotation)
                ? (deg) => _report(
                    context,
                    cmds.keyValue(
                        view.id, _kRotation, _playheadT(ref), deg * _degToRad))
                : (deg) => commit(t.copyWith(rotation: deg * _degToRad)),
          ),
        ),
        _single(
          label: 'Skew X (°)',
          leading: diamond(_kSkewX, t.skewX),
          field: _numberField(
            projectId: projectId,
            fieldKey: 'inspector-skewx',
            tracked: tracked(_kSkewX),
            property: _kSkewX,
            staticDisplay: t.skewX * _radToDeg,
            toDisplay: (s) => s is double ? s * _radToDeg : t.skewX * _radToDeg,
            onCommit: tracked(_kSkewX)
                ? (deg) => _report(
                    context,
                    cmds.keyValue(
                        view.id, _kSkewX, _playheadT(ref), deg * _degToRad))
                : (deg) => commit(t.copyWith(skewX: deg * _degToRad)),
          ),
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
          leading: diamond(_kOpacity, view.opacity),
          field: _numberField(
            projectId: projectId,
            fieldKey: 'inspector-opacity',
            tracked: tracked(_kOpacity),
            property: _kOpacity,
            staticDisplay: view.opacity * 100,
            toDisplay: (s) => s is double ? s * 100 : view.opacity * 100,
            onCommit: tracked(_kOpacity)
                ? (percent) => _report(
                    context,
                    cmds.keyValue(view.id, _kOpacity, _playheadT(ref),
                        (percent / 100).clamp(0.0, 1.0)))
                : (percent) => _commitOpacity(context, ref, view.id, percent),
          ),
        ),
        const SizedBox(height: 16),
        // The geometry "stopwatch" — a diamond-only row that authors the first
        // path keyframe (F6.1). It sits with the geometry, above the paint it
        // does not touch.
        _PathSection(projectId: projectId),
        // Fill above stroke, because **fills paint before strokes, always**
        // (docs/v3/01 §6, AC-5.1.5). The ordering is the renderer's, expressed
        // by `fills` and `strokes` being two fields — so the panel reads top to
        // bottom in paint order and offers no reorder, no z-index and no "bring
        // to front" to disagree with it.
        _PaintSection(projectId: projectId),
        // Draw-on / reveal (F8.1). SHIPPED in M6 — the "Draw-on trim — not yet
        // available" seam this replaced is gone; the row now authors a real
        // `PathTrim` per PathNode (AC-8.1.10). It sits below the paint it reveals
        // and reads its own named slice, so a trim commit rebuilds a different
        // sub-tree (docs/v3/08 §2).
        _TrimSection(projectId: projectId),
        _ShapeSection(projectId: projectId),
        const SizedBox(height: 16),
        // Easing and anchor-kind editing SHIPPED (M4 timeline, M3 direct-select),
        // so these rows point at where the feature lives rather than claiming it
        // is "not yet available" as they used to — that read as a broken tool to
        // the ship-gate stranger (docs/v3/00 §5). After M6's trim there is no
        // "not yet available" seam left at all.
        _hint(context, 'Easing — set it per segment on the timeline'),
        _hint(context,
            'Corner and smooth anchors — Alt-click an anchor with Direct Select'),
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

  /// An X/Y row. It lays out two **already-built** fields — a plain
  /// `CommittedNumberField` when untracked, or a leaf that samples the track at
  /// the playhead when tracked (see [_numberField]) — so the WYSIWYG wrapping is
  /// decided at the call site and this helper stays layout-only.
  Widget _pair({
    required String label,
    required Widget xField,
    required Widget yField,
    Widget? leading,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelRow(label, leading),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: xField),
                const SizedBox(width: 8),
                Expanded(child: yField),
              ],
            ),
          ],
        ),
      );

  Widget _single({
    required String label,
    required Widget field,
    Widget? leading,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelRow(label, leading),
            const SizedBox(height: 4),
            field,
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

  /// A field label, optionally preceded by its keyframe diamond. The label is
  /// `Expanded` so a long name never pushes the diamond off the row.
  Widget _labelRow(String label, Widget? leading) => Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 6)],
          Expanded(child: _fieldLabel(label)),
        ],
      );

  /// A pointer to a feature that **is** built but lives on another surface — the
  /// honest replacement for a "not yet available" row on a shipped feature.
  Widget _hint(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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

// ---------------------------------------------------------------------------
// WYSIWYG tracked fields (AC-6.2.6) — the field shows what the canvas shows
// ---------------------------------------------------------------------------
//
// A tracked property's field must display the value SAMPLED AT THE PLAYHEAD —
// the keyframe/interpolated value the canvas is drawing — not the static rest
// pose, or scrubbing to a key that holds 170° shows the field at 0° and typing
// 5 silently jumps the key by 165° (AC-6.2.6, UX §3). The commit still writes
// to the playhead's key; only the *display* changes.
//
// **Hot-path-safe.** The sampled value lives in a leaf [_SampledValue] that
// watches the value-equal [inspectorSamplesProvider] (which changes on a key
// edit, never on a scrub) and re-reads the live playhead in a
// `ValueListenableBuilder` — so a scrub repaints only the field's text and
// rebuilds no panel (AC-13.3), the same pattern the diamond and the timeline
// readout use.

/// The node-local sampled value of a typed track at [t]. Mirrors the timeline
/// `K` / `keyCurrent` sampler; a small duplicate rather than a cross-feature
/// import (docs/v3/08 §3). A `PathTrack` (unreachable value) or no track yields
/// null, and the caller falls back to the static pose.
Object? _sampleTrack(Track? track, double t) => switch (track) {
      final Vec2Track v => v.sampleAt(t),
      final ScalarTrack s => s.sampleAt(t),
      final ColorTrack c => c.sampleAt(t),
      _ => null,
    };

/// A number field that is WYSIWYG when [tracked] and plain otherwise.
///
/// Untracked: a plain [CommittedNumberField] showing [staticDisplay], exactly as
/// before. Tracked: a leaf that samples [property] at the live playhead and maps
/// the sample to the display unit with [toDisplay] (radians→degrees, 0..1→%),
/// falling back to [staticDisplay] when the sample is unavailable. [onCommit]
/// still writes absolutely to the playhead's key.
Widget _numberField({
  required String projectId,
  required String fieldKey,
  required bool tracked,
  required PropertyKey property,
  required double staticDisplay,
  required double Function(Object sampled) toDisplay,
  required ValueChanged<double> onCommit,
  String? label,
}) {
  if (!tracked) {
    return CommittedNumberField(
        key: Key(fieldKey),
        label: label,
        value: staticDisplay,
        onCommit: onCommit);
  }
  return _SampledValue<double>(
    projectId: projectId,
    property: property,
    fallback: staticDisplay,
    project: toDisplay,
    builder: (value) => CommittedNumberField(
        key: Key(fieldKey), label: label, value: value, onCommit: onCommit),
  );
}

/// The colour twin of [_numberField]: WYSIWYG at the playhead when tracked.
Widget _colorField({
  required String projectId,
  required String fieldKey,
  required bool tracked,
  required PropertyKey property,
  required Rgba staticColor,
  required ValueChanged<Rgba> onCommit,
}) {
  if (!tracked) {
    return CommittedColorField(
        key: Key(fieldKey), value: staticColor, onCommit: onCommit);
  }
  return _SampledValue<Rgba>(
    projectId: projectId,
    property: property,
    fallback: staticColor,
    project: (s) => s is Rgba ? s : staticColor,
    builder: (value) => CommittedColorField(
        key: Key(fieldKey), value: value, onCommit: onCommit),
  );
}

/// Resolves a tracked field's displayed value at the **live** playhead and hands
/// it to [builder]. Watches only [inspectorSamplesProvider] (a key edit, not a
/// scrub) and the playhead notifier, so a scrub repaints just the field.
class _SampledValue<T> extends ConsumerWidget {
  const _SampledValue({
    required this.projectId,
    required this.property,
    required this.fallback,
    required this.project,
    required this.builder,
  });

  final String projectId;
  final PropertyKey property;
  final T fallback;

  /// Maps a non-null sample (a `double`, `Vec2` or `Rgba`) to the display type.
  final T Function(Object sampled) project;
  final Widget Function(T value) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The samples slice's identity is what changes on a key edit; the playhead
    // notifier's value is what changes on a scrub. Neither is read from the
    // panel, so the panel does not rebuild for either.
    final track = ref.watch(inspectorSamplesProvider(projectId))[property];
    final playhead = ref.watch(playheadProvider);
    return ValueListenableBuilder<double>(
      valueListenable: playhead,
      builder: (context, raw, _) {
        final t = raw.isNaN ? 0.0 : raw.clamp(0.0, 1.0).toDouble();
        final sampled = _sampleTrack(track, t);
        return builder(sampled == null ? fallback : project(sampled));
      },
    );
  }
}

/// The geometry "stopwatch" — a **diamond-only** row that authors the first path
/// keyframe and removes them (F6.1, AC-6.2.6).
///
/// There is no path *field*: a `PathPose` is edited on the canvas by
/// direct-select (F4.2). So this is the one hand affordance the audit found
/// missing — [MoveAnchorCommand]/[SetTangentsCommand] only mint a path track as
/// a side effect of *moving* an anchor (and after the AC-4.2.3 fix a drag on a
/// static node edits the rest pose and makes none), so a user could draw a curve
/// and never start animating it. The empty diamond runs [KeyPathCommand]
/// (`PathOps.keyPose`) to seed one key from the rest pose; a filled one removes
/// the key under the playhead.
///
/// Its own `ConsumerWidget` reading [inspectorPaintProvider] for the node id (it
/// is non-null for any single selected `PathNode`) so a paint or transform
/// commit rebuilds a different sub-tree (docs/v3/08 §2).
class _PathSection extends ConsumerWidget {
  const _PathSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(inspectorPaintProvider(projectId));
    if (view == null) return const SizedBox.shrink();
    final tracks = ref.watch(inspectorTracksProvider(projectId));
    final scheme = Theme.of(context).colorScheme;
    final commands = InspectorCommands(ref, projectId);

    return Column(
      key: const Key('inspector-path'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _groupLabel(context, 'Path'),
        Row(
          children: [
            _KeyframeDiamond(
              keyName: 'kf-${_kPath.wire}',
              keyTimes: tracks[_kPath],
              // The diamond keys a hold (or the first key) with `keyPose`, which
              // owns both cases; a filled one removes the key under the playhead.
              onKey: () => _report(
                  context, commands.keyPath(view.node, _playheadT(ref))),
              onRemoveAt: (index) => _report(
                  context, commands.removeKeyAt(view.node, _kPath, index)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Shape',
                  style:
                      TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Key the whole outline here, then move anchors on the canvas with '
          'Direct Select — each edit lands on the keyframe at the playhead.',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Draw-on / reveal authoring — the `PathTrim` row (F8.1, docs/v3/05 §2).
///
/// Three percentage fields — **Trim start / Trim end / Trim offset** — each
/// display `%` and store the underlying `0..1` fraction of total arc length (the
/// same display-vs-store split rotation and opacity use), each `0..100`. Each
/// carries a keyframe diamond backed by its `trimStart`/`trimEnd`/`trimOffset`
/// `ScalarTrack`, and routes static-vs-keyframe **exactly** like the
/// transform/paint fields — reading the SAME [inspectorTracksProvider] slice so
/// the diamond and field can never disagree:
///   * UNtracked → editing writes the static `PathTrim` via
///     `InspectorCommands.setTrim`; the empty diamond keys the current value
///     (`keyCurrent`, creating the `ScalarTrack`).
///   * TRACKED → editing upserts the keyframe at the playhead (edit-at-keyframe,
///     `keyValue`), and the field is WYSIWYG — it shows the value sampled at the
///     playhead via the leaf [_numberField] `ValueListenableBuilder`, so a scrub
///     repaints only the field text and rebuilds no panel (AC-13.3). A filled
///     diamond removes the key under the playhead.
///
/// **Its own `ConsumerWidget` reading [inspectorTrimProvider]**, so a trim commit
/// rebuilds a different sub-tree than a transform/paint commit (docs/v3/08 §2).
/// Present for any single `PathNode`; absent for a group or a many/zero
/// selection — trim is per-`PathNode` (AC-8.1.10): no per-subpath, no
/// group-level, no `Stroke.dash`.
class _TrimSection extends ConsumerWidget {
  const _TrimSection({required this.projectId});

  final String projectId;

  static const PropertyKey _kTrimStart = PropertyKey(PropKey.trimStart);
  static const PropertyKey _kTrimEnd = PropertyKey(PropKey.trimEnd);
  static const PropertyKey _kTrimOffset = PropertyKey(PropKey.trimOffset);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(inspectorTrimProvider(projectId));
    if (view == null) return const SizedBox.shrink();
    // The same tracked-ness slice the transform/paint rows read — so the trim
    // diamonds and fields agree with them about which world they are in.
    final tracks = ref.watch(inspectorTracksProvider(projectId));
    final commands = InspectorCommands(ref, projectId);
    final node = view.node;
    final trim = view.trim;

    Widget diamond(PropertyKey property, double authored) => _KeyframeDiamond(
          keyName: 'kf-${property.wire}',
          keyTimes: tracks[property],
          onKey: () => _report(context,
              commands.keyCurrent(node, property, _playheadT(ref), authored)),
          onRemoveAt: (index) =>
              _report(context, commands.removeKeyAt(node, property, index)),
        );

    // One trim channel's field: percent in, 0..1 stored. Untracked writes the
    // whole next `PathTrim` (the one channel replaced) via `setTrim`; tracked
    // upserts the keyframe at the playhead, pre-clamped to 0..1 (the static path
    // clamps in `NodeOps.setTrim`, but `keyValue → KeyframeOps.keyAt` does not,
    // matching how tracked opacity/width are pre-clamped in the paint section).
    Widget field({
      required String fieldKey,
      required PropertyKey property,
      required double stored,
      required PathTrim Function(double fraction) rebuild,
    }) =>
        _numberField(
          projectId: projectId,
          fieldKey: fieldKey,
          tracked: tracks[property] != null,
          property: property,
          staticDisplay: stored * 100,
          toDisplay: (s) => s is double ? s * 100 : stored * 100,
          onCommit: tracks[property] != null
              ? (percent) => _report(
                  context,
                  commands.keyValue(node, property, _playheadT(ref),
                      (percent / 100).clamp(0.0, 1.0)))
              : (percent) => _report(
                  context, commands.setTrim(node, rebuild(percent / 100))),
        );

    return Column(
      key: const Key('inspector-trim'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _groupLabel(context, 'Trim'),
        _labelled(
          'Start (%)',
          field(
            fieldKey: 'inspector-trim-start',
            property: _kTrimStart,
            stored: trim.start,
            rebuild: (f) =>
                PathTrim(start: f, end: trim.end, offset: trim.offset),
          ),
          leading: diamond(_kTrimStart, trim.start),
        ),
        _labelled(
          'End (%)',
          field(
            fieldKey: 'inspector-trim-end',
            property: _kTrimEnd,
            stored: trim.end,
            rebuild: (f) =>
                PathTrim(start: trim.start, end: f, offset: trim.offset),
          ),
          leading: diamond(_kTrimEnd, trim.end),
        ),
        _labelled(
          'Offset (%)',
          field(
            fieldKey: 'inspector-trim-offset',
            property: _kTrimOffset,
            stored: trim.offset,
            rebuild: (f) =>
                PathTrim(start: trim.start, end: trim.end, offset: f),
          ),
          leading: diamond(_kTrimOffset, trim.offset),
        ),
      ],
    );
  }
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
    // Tracked-ness for the paint diamonds and the paint fields' routing — the
    // same slice the transform section reads, so the two agree on scope.
    final tracks = ref.watch(inspectorTracksProvider(projectId));
    return Column(
      key: const Key('inspector-paint'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupLabel(context, 'Fill'),
        _fill(context, ref, view, tracks),
        const SizedBox(height: 12),
        _groupLabel(context, 'Stroke'),
        _stroke(context, ref, view, tracks),
      ],
    );
  }

  InspectorCommands _commands(WidgetRef ref) =>
      InspectorCommands(ref, projectId);

  /// One paint channel's keyframe diamond, keyed by its `PaintId`-subject
  /// `PropertyKey`. Only ever built for a **solid** paint (the read-only branch
  /// returns before any diamond), so [authored] is a real value, never null.
  Widget _paintDiamond(BuildContext context, WidgetRef ref, NodeId node,
          PropertyKey property, InspectorTracksView tracks, Object? authored) =>
      _KeyframeDiamond(
        keyName: 'kf-${property.wire}',
        keyTimes: tracks[property],
        onKey: () => _report(
            context,
            _commands(ref)
                .keyCurrent(node, property, _playheadT(ref), authored)),
        onRemoveAt: (index) =>
            _report(context, _commands(ref).removeKeyAt(node, property, index)),
      );

  Widget _fill(BuildContext context, WidgetRef ref, NodePaintView view,
      InspectorTracksView tracks) {
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
    // Non-null past the read-only branch (a solid paint) — captured to a local
    // so the diamonds and field read it without a bare `!`.
    final color = fill.color;
    if (color == null) return const SizedBox.shrink();

    final commands = _commands(ref);
    final colorKey = PropertyKey(PropKey.fillColor, fill.id.v);
    final opacityKey = PropertyKey(PropKey.fillOpacity, fill.id.v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.fillCount > 1) _extraPaints(context, 'fill', view.fillCount),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              _paintDiamond(context, ref, view.node, colorKey, tracks, color),
              const SizedBox(width: 6),
              Expanded(
                child: _colorField(
                  projectId: projectId,
                  fieldKey: 'inspector-fill-color',
                  tracked: tracks[colorKey] != null,
                  property: colorKey,
                  staticColor: color,
                  onCommit: tracks[colorKey] != null
                      ? (next) => _report(
                          context,
                          commands.keyValue(
                              view.node, colorKey, _playheadT(ref), next))
                      : (next) => _report(context,
                          commands.setFillColor(view.node, fill.id, next)),
                ),
              ),
            ],
          ),
        ),
        _labelled(
          'Opacity (%)',
          _numberField(
            projectId: projectId,
            fieldKey: 'inspector-fill-opacity',
            tracked: tracks[opacityKey] != null,
            property: opacityKey,
            staticDisplay: fill.opacity * 100,
            toDisplay: (s) => s is double ? s * 100 : fill.opacity * 100,
            onCommit: tracks[opacityKey] != null
                ? (percent) => _report(
                    context,
                    commands.keyValue(view.node, opacityKey, _playheadT(ref),
                        (percent / 100).clamp(0.0, 1.0)))
                : (percent) => _report(context,
                    commands.setFillOpacity(view.node, fill.id, percent / 100)),
          ),
          leading: _paintDiamond(
              context, ref, view.node, opacityKey, tracks, fill.opacity),
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

  Widget _stroke(BuildContext context, WidgetRef ref, NodePaintView view,
      InspectorTracksView tracks) {
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
    final color = stroke.color;
    if (color == null) return const SizedBox.shrink();

    final commands = _commands(ref);
    final colorKey = PropertyKey(PropKey.strokeColor, stroke.id.v);
    final widthKey = PropertyKey(PropKey.strokeWidth, stroke.id.v);
    final opacityKey = PropertyKey(PropKey.strokeOpacity, stroke.id.v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.strokeCount > 1)
          _extraPaints(context, 'stroke', view.strokeCount),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              _paintDiamond(context, ref, view.node, colorKey, tracks, color),
              const SizedBox(width: 6),
              Expanded(
                child: _colorField(
                  projectId: projectId,
                  fieldKey: 'inspector-stroke-color',
                  tracked: tracks[colorKey] != null,
                  property: colorKey,
                  staticColor: color,
                  onCommit: tracks[colorKey] != null
                      ? (next) => _report(
                          context,
                          commands.keyValue(
                              view.node, colorKey, _playheadT(ref), next))
                      : (next) => _report(context,
                          commands.setStrokeColor(view.node, stroke.id, next)),
                ),
              ),
            ],
          ),
        ),
        _labelled(
          'Width',
          _numberField(
            projectId: projectId,
            fieldKey: 'inspector-stroke-width',
            tracked: tracks[widthKey] != null,
            property: widthKey,
            staticDisplay: stroke.width,
            toDisplay: (s) => s is double ? s : stroke.width,
            onCommit: tracks[widthKey] != null
                // Pre-clamp on the tracked path: the static path clamps in
                // `PaintOps.setStrokeWidth`, but `keyValue → KeyframeOps.keyAt`
                // does not, so a negative width would otherwise be stored in a
                // keyframe (matching how tracked opacity is pre-clamped above).
                ? (width) => _report(
                    context,
                    commands.keyValue(view.node, widthKey, _playheadT(ref),
                        width.clamp(0.0, double.infinity)))
                : (width) => _report(context,
                    commands.setStrokeWidth(view.node, stroke.id, width)),
          ),
          leading: _paintDiamond(
              context, ref, view.node, widthKey, tracks, stroke.width),
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
        // A ratio of miter length to stroke width, so it is meaningless below 1;
        // the op clamps a sub-1 entry up to 1 rather than throwing, the same way
        // opacity clamps — a bad keystroke must not trip the command gate's
        // `assert(false)` on legal user data (docs/v3/08 §1). Shown next to
        // `Join` because it only does anything for a miter join.
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
          _numberField(
            projectId: projectId,
            fieldKey: 'inspector-stroke-opacity',
            tracked: tracks[opacityKey] != null,
            property: opacityKey,
            staticDisplay: stroke.opacity * 100,
            toDisplay: (s) => s is double ? s * 100 : stroke.opacity * 100,
            onCommit: tracks[opacityKey] != null
                ? (percent) => _report(
                    context,
                    commands.keyValue(view.node, opacityKey, _playheadT(ref),
                        (percent / 100).clamp(0.0, 1.0)))
                : (percent) => _report(
                    context,
                    commands.setStrokeOpacity(
                        view.node, stroke.id, percent / 100)),
          ),
          leading: _paintDiamond(
              context, ref, view.node, opacityKey, tracks, stroke.opacity),
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

/// The floor a shape's extent (`w`/`h`/`rx`/`ry`/`radius`) is clamped to at the
/// field, before a recipe is committed.
///
/// `toPath()` collapses to `PathData.empty` for a non-positive or non-finite
/// extent, or for `sides < 3` (`shape_geometry.dart`). On a path-TRACKED node
/// that empty path routes to `retopologize`, which rewrites every keyframe onto
/// nothing and **silently erases the animation** — the M5 defect this floor
/// closes. So the shape fields clamp, at the mutation, the same way the stroke
/// width/miter fields do: a degenerate recipe can no longer be authored from a
/// number field, tracked or not. `1` (not a sub-pixel epsilon) so a fat-fingered
/// `0` parks the shape at a value the user can *see* and correct in place.
const double _kMinShapeExtent = 1.0;

/// [v] pinned to a finite value at or above [_kMinShapeExtent]. A non-finite
/// entry — `1e999` parses to infinity, which `toPath` reads as degenerate just as
/// it does `0` — drops to the floor rather than falling through to empty geometry.
double _shapeExtent(double v) =>
    v.isFinite ? math.max(v, _kMinShapeExtent) : _kMinShapeExtent;

/// The recipe a shape field built, clamped out of every degenerate corner that
/// `toPath()` returns [PathData.empty] for (see [_kMinShapeExtent]).
///
/// Non-extent parameters clamp to their own valid ranges: `cornerRadius >= 0`
/// (0 is a plain rectangle, and the geometry already caps it at `min(w, h) / 2`),
/// `innerRatio` into `0..1` (outside it inverts the star, and the geometry clamps
/// there anyway), `sides >= 3` (two is a line, one a point). An [UnknownRecipe]
/// has no readable parameters and is passed through untouched — the routing
/// backstop refuses it, and no field ever builds one.
ShapeRecipe _clampShapeRecipe(ShapeRecipe recipe) => switch (recipe) {
      final RectRecipe r => RectRecipe(
          w: _shapeExtent(r.w),
          h: _shapeExtent(r.h),
          cornerRadius:
              r.cornerRadius.isFinite ? math.max(r.cornerRadius, 0.0) : 0.0,
          unknownKeys: r.unknownKeys,
        ),
      final EllipseRecipe e => EllipseRecipe(
          rx: _shapeExtent(e.rx),
          ry: _shapeExtent(e.ry),
          unknownKeys: e.unknownKeys,
        ),
      final PolygonRecipe p => PolygonRecipe(
          sides: math.max(p.sides, 3),
          radius: _shapeExtent(p.radius),
          star: p.star,
          innerRatio: p.innerRatio.isFinite
              ? p.innerRatio.clamp(0.0, 1.0).toDouble()
              : 0.0,
          unknownKeys: p.unknownKeys,
        ),
      UnknownRecipe() => recipe,
    };

/// Shape-parameter re-editing — AC-4.1.5.
///
/// A [ShapeRecipe] is inert metadata about how a shape tool generated the node's
/// anchors, so "make that rectangle 20 units wider" stays a one-field edit
/// instead of a manual drag of four anchors. Editing one regenerates the
/// geometry through the **one sanctioned route**, `InspectorCommands.regenerateRecipe`.
///
/// **Enabled on a tracked node — that is M5's whole point.** An animated path was
/// refused until `PathOps.retopologize` existed; now the edit routes through it
/// (arc-length correspondence rewrites every keyframe onto the recipe's new id
/// set and clears the recipe), so tracked-ness no longer disables anything. The
/// one thing still shown read-only is a recipe this build cannot read
/// ([kUnreadableRecipeMessage]): it has no parameters to draw a field for, and
/// `PathOps.regenerateRecipe` refuses it as the backstop — so a field can never
/// look editable while the write behind it is refused.
class _ShapeSection extends ConsumerWidget {
  const _ShapeSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(inspectorShapeProvider(projectId));
    if (view == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final enabled = view.refusal == null;

    // Clamp the recipe the field built out of every degenerate corner before it
    // reaches the command (see [_clampShapeRecipe]). This is the primary guard
    // for the M5 erase-on-degenerate defect: a `w = 0` / `sides = 2` recipe whose
    // `toPath()` is empty would, on a path-TRACKED node, retopologize every
    // keyframe onto nothing and silently wipe the animation.
    void commit(ShapeRecipe next) => _report(
        context,
        InspectorCommands(ref, projectId)
            .regenerateRecipe(view.node, _clampShapeRecipe(next)));

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
        // `v.round()` throws on a non-finite entry (a `1e999` parses to infinity
        // in the field), so the double is settled before it becomes a side count;
        // [_clampShapeRecipe] then applies the `>= 3` floor.
        _number(
            'Sides',
            'inspector-shape-sides',
            recipe.sides.toDouble(),
            enabled,
            (v) => commit(next(sides: v.isFinite ? v.round() : recipe.sides))),
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

Widget _labelled(String label, Widget field, {Widget? leading}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 6)],
              Expanded(
                child: Builder(
                  builder: (context) => Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          field,
        ],
      ),
    );

// ---------------------------------------------------------------------------
// The keyframe diamond (F6.2, AC-6.2.6) — the AE/Figma keyframe toggle.
// ---------------------------------------------------------------------------

enum _DiamondState { empty, between, onKey }

/// One property's keyframe toggle. **A leaf that watches the live playhead** so
/// scrubbing repaints only this 11-px widget, never the field beside it or the
/// panel around it (AC-13.3): the field and the panel read the value-equal
/// `inspectorTracksProvider` slice, which does not change on a scrub.
///
/// - No track ([keyTimes] null) → **empty** diamond; a tap keys the current
///   value at the playhead ([onKey]), which creates the track.
/// - Tracked, playhead on a key → **filled**; a tap removes that key
///   ([onRemoveAt]).
/// - Tracked, playhead between keys → **hollow**; a tap keys a hold there
///   ([onKey]).
class _KeyframeDiamond extends ConsumerWidget {
  const _KeyframeDiamond({
    required this.keyName,
    required this.keyTimes,
    required this.onKey,
    required this.onRemoveAt,
  });

  final String keyName;
  final List<double>? keyTimes;
  final VoidCallback onKey;
  final void Function(int index) onRemoveAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `playheadProvider`'s identity is stable, so watching it never rebuilds
    // this ConsumerWidget; the `ValueListenableBuilder` repaints on each tick.
    final playhead = ref.watch(playheadProvider);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: playhead,
      builder: (context, raw, _) {
        final t = raw.isNaN ? 0.0 : raw.clamp(0.0, 1.0).toDouble();
        final times = keyTimes;
        final onKeyIndex = times == null ? null : _indexAt(times, t);

        final _DiamondState state;
        final VoidCallback tap;
        if (times == null) {
          state = _DiamondState.empty;
          tap = onKey;
        } else if (onKeyIndex != null) {
          state = _DiamondState.onKey;
          final index = onKeyIndex; // promoted non-null — no bare `!`
          tap = () => onRemoveAt(index);
        } else {
          state = _DiamondState.between;
          tap = onKey;
        }

        return InkWell(
          key: Key(keyName),
          onTap: tap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CustomPaint(
              size: const Size(11, 11),
              painter: _DiamondPainter(
                state: state,
                on: scheme.primary,
                idle: scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }

  /// The index of the key the playhead sits on, or null when it is between keys.
  /// The tolerance is `TrackOps.minSeparation`, the same coincidence threshold
  /// the sampler and the timeline's `Shift+K` use.
  static int? _indexAt(List<double> times, double t) {
    for (var i = 0; i < times.length; i++) {
      if ((times[i] - t).abs() <= TrackOps.minSeparation) return i;
    }
    return null;
  }
}

class _DiamondPainter extends CustomPainter {
  _DiamondPainter({required this.state, required this.on, required this.idle});

  final _DiamondState state;
  final Color on;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    switch (state) {
      case _DiamondState.empty:
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = idle);
      case _DiamondState.between:
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = on);
      case _DiamondState.onKey:
        canvas.drawPath(path, Paint()..color = on);
    }
  }

  @override
  bool shouldRepaint(_DiamondPainter old) =>
      old.state != state || old.on != on || old.idle != idle;
}

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
