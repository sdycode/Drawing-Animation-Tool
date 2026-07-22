import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        Text('Not yet available',
            key: const Key('inspector-seams'),
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        _seam(context, 'Fill and stroke colours'),
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

  /// Capture the messenger before the await, and **handle `onError`**: anything
  /// that escapes `InspectorCommands._guard` would otherwise complete this
  /// dropped future with an error nobody listens for, which Flutter reports as
  /// an unhandled async error instead of the snackbar this method exists for.
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
