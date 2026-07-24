// `Easing` is declared by both anim_core (the sealed type we author) and
// `package:flutter/material.dart` (its animation-curve constants), and
// `Animation` by both anim_core and Flutter — hide each clashing name from the
// import that does not own it, so the switch over the sealed `Easing` stays
// exhaustive (docs/v3/01 §10; enforced by tool/check_boundaries.dart).
import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Easing;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_controller.dart';
import '../commands.dart';
import '../providers.dart';
import '../timeline_model.dart';

/// The per-node, per-property rows — the body of the timeline (docs/v3/05 §2).
///
/// **Row expansion:** a node collapses to a single summary row (the union of its
/// keys, read-only) and expands to one row per `PropertyKey`; editing is only
/// ever on an expanded property row. Which nodes are expanded is timeline-local
/// UI state and lives here in `_expanded`, not in `EditorState` — it is not
/// shared with the canvas and not worth a notifier hop.
///
/// **Pixels appear only in this widget's paint and hit-test (AC-9.1.4).** Every
/// key sits at `t` across the rail; there is no grid to snap to and no column to
/// align, so node A's keys at 0.0/0.5/1.0 and node B's at 0.13/0.77 draw on
/// their own rows and never line up (AC-6.1.1, AC-6.1.5).
///
/// **`build` is a pure read (AC-6.2.5).** It watches the value-equal
/// [timelineModelProvider] and the ephemeral `selectedKeyframe`; no code path
/// here mutates the document from inside a build. Interaction handlers emit a
/// command; the command returns the next document (docs/v3/08 §1).
class TimelineRows extends ConsumerStatefulWidget {
  const TimelineRows({
    required this.projectId,
    required this.labelWidth,
    super.key,
  });

  final String projectId;
  final double labelWidth;

  @override
  ConsumerState<TimelineRows> createState() => _TimelineRowsState();
}

class _TimelineRowsState extends ConsumerState<TimelineRows> {
  final Set<NodeId> _expanded = <NodeId>{};

  void _toggle(NodeId node) => setState(() {
        if (!_expanded.remove(node)) _expanded.add(node);
      });

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(timelineModelProvider(widget.projectId));
    final selected =
        ref.watch(editorControllerProvider.select((s) => s.selectedKeyframe));
    final scheme = Theme.of(context).colorScheme;

    if (model.nodes.isEmpty) {
      return Center(
        child: Text(
          'No keyframes yet — key a property to animate it.',
          key: const Key('timeline-empty'),
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      );
    }

    // A flat list of rows: one header per node, then its property rows when it
    // is expanded. A ListView so a document taller than the (fixed-height,
    // docs/v3/08 §2) panel scrolls — and scrolling mutates nothing (AC-6.2.5).
    final rows = <Widget>[];
    for (final node in model.nodes) {
      final isExpanded = _expanded.contains(node.node);
      rows.add(_NodeHeaderRow(
        node: node,
        expanded: isExpanded,
        labelWidth: widget.labelWidth,
        onToggle: () => _toggle(node.node),
      ));
      if (isExpanded) {
        for (final row in node.rows) {
          rows.add(_PropertyRow(
            key: ValueKey<String>('row-${row.node.v}-${row.property.wire}'),
            projectId: widget.projectId,
            row: row,
            labelWidth: widget.labelWidth,
            selected: selected,
          ));
        }
      }
    }

    return ListView(
      key: const Key('timeline-rows'),
      padding: EdgeInsets.zero,
      children: rows,
    );
  }
}

/// A node header: the expand toggle, the name, and — while collapsed — the
/// read-only union of the node's keys (docs/v3/05 §2).
class _NodeHeaderRow extends StatelessWidget {
  const _NodeHeaderRow({
    required this.node,
    required this.expanded,
    required this.labelWidth,
    required this.onToggle,
  });

  final TimelineNodeModel node;
  final bool expanded;
  final double labelWidth;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: kTimelineRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: InkWell(
              key: Key('node-${node.node.v}'),
              onTap: onToggle,
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Text(
                      node.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => CustomPaint(
                size: Size(c.maxWidth, kTimelineRowHeight),
                painter: _SummaryPainter(
                  // The union summary is drawn only while collapsed; expanding
                  // replaces it with the editable property rows below.
                  times: expanded ? const <double>[] : node.summary,
                  rail: scheme.outlineVariant,
                  dot: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One expanded property row: dots per key, draggable in time, clickable to
/// select, with a clickable segment between each pair for its easing.
class _PropertyRow extends ConsumerStatefulWidget {
  const _PropertyRow({
    required this.projectId,
    required this.row,
    required this.labelWidth,
    required this.selected,
    super.key,
  });

  final String projectId;
  final TimelinePropertyRow row;
  final double labelWidth;
  final KeyframeRef? selected;

  @override
  ConsumerState<_PropertyRow> createState() => _PropertyRowState();
}

class _PropertyRowState extends ConsumerState<_PropertyRow> {
  /// The key being dragged and its live, un-committed `t`. The preview slides
  /// this dot while the gesture is in flight; **one** [MoveKeyframeCommand] is
  /// issued on release, against the index captured at drag start (AC-6.2.1).
  int? _dragIndex;
  double? _dragT;

  TimelineCommands get _commands => TimelineCommands(ref, widget.projectId);

  void _report(BuildContext context, Future<String?> pending) =>
      _reportVia(ScaffoldMessenger.of(context), pending);

  /// The messenger-captured reporter, with the **`onError` net** every other
  /// reporter has: a failure that is not a `StoreException`/`ArgumentError`
  /// escapes `TimelineCommands._guard` and would otherwise complete this dropped
  /// future as an unhandled async error instead of a snackbar. Split from
  /// [_report] so [_pickEasing] — which must capture the messenger *before* its
  /// menu await — can reuse it.
  void _reportVia(ScaffoldMessengerState messenger, Future<String?> pending) {
    void show(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    pending.then(
      (message) {
        if (message != null) show(message);
      },
      onError: (Object _, StackTrace __) => show(kRejectedKeyframeEditMessage),
    );
  }

  void _select(int index) {
    // Snap the playhead to the key's own `t` (AC-6.2.6) — edit-at-keyframe.
    ref.read(editorControllerProvider.notifier).selectKeyframe(
          widget.row.node,
          widget.row.property,
          index,
          snapT: widget.row.keys[index].t,
        );
  }

  Future<void> _pickEasing(
      BuildContext context, int leftIndex, Offset globalPos) async {
    // Capture the messenger before the async gap — a `BuildContext` may not be
    // used across it, exactly as the shell's shortcut reporter does.
    final messenger = ScaffoldMessenger.of(context);
    final box = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final chosen = await showMenu<Easing>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(1, 1),
        Offset.zero & box.size,
      ),
      items: [
        for (final preset in _easingPresets)
          PopupMenuItem<Easing>(
            key: Key('easing-${preset.id}'),
            value: preset.easing,
            height: 34,
            child: Text(preset.label, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
    if (chosen == null) return;
    // Easing governs the segment LEAVING its key, so a segment is addressed by
    // its LEFT key's index (AC-7.1.1). The preset is already a concrete
    // `Easing` — its four `CubicEasing` numbers, never a symbol (AC-7.1.2).
    //
    // Reported through the captured messenger with `onError` rather than a bare
    // `await`: `context` may not be used across the menu's async gap, and a
    // non-guarded failure must surface as a snackbar, not an unhandled error.
    _reportVia(
        messenger,
        _commands.setEasing(
            widget.row.node, widget.row.property, leftIndex, chosen));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keys = widget.row.keys;

    return SizedBox(
      height: kTimelineRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: widget.labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _propLabel(widget.row.property),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.onSurface),
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final width = c.maxWidth;
                double x(double t) => t.clamp(0.0, 1.0) * width;

                final children = <Widget>[
                  // The baseline rail.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RowRailPainter(rail: scheme.outlineVariant),
                    ),
                  ),
                  // Segments: one clickable span between each pair of dots, each
                  // showing the current easing's glyph and opening the picker.
                  for (var i = 0; i < keys.length - 1; i++)
                    _buildSegment(context, i, x(keys[i].t), x(keys[i + 1].t),
                        keys[i].easing, scheme),
                  // Dots on top of the segments, so a click near a key selects
                  // the key rather than editing the segment.
                  for (var i = 0; i < keys.length; i++)
                    _buildDot(context, i, x, width, scheme),
                ];

                return Stack(
                  key: Key(
                      'rail-${widget.row.node.v}-${widget.row.property.wire}'),
                  clipBehavior: Clip.none,
                  children: children,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(BuildContext context, int leftIndex, double xL,
      double xR, Easing easing, ColorScheme scheme) {
    final w = (xR - xL).clamp(0.0, double.infinity);
    return Positioned(
      left: xL,
      width: w,
      top: 0,
      height: kTimelineRowHeight,
      child: GestureDetector(
        key: Key(
            'seg-${widget.row.node.v}-${widget.row.property.wire}-$leftIndex'),
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) => _pickEasing(context, leftIndex, d.globalPosition),
        child: Center(
          child: Text(
            _easingGlyph(easing),
            style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _buildDot(BuildContext context, int index, double Function(double) x,
      double width, ColorScheme scheme) {
    final t = _dragIndex == index ? _dragT! : widget.row.keys[index].t;
    final isSelected = widget.selected == null
        ? false
        : widget.selected == (widget.row.node, widget.row.property, index);
    const hit = 18.0;
    return Positioned(
      left: x(t) - hit / 2,
      top: 0,
      width: hit,
      height: kTimelineRowHeight,
      child: GestureDetector(
        key: Key('kf-${widget.row.node.v}-${widget.row.property.wire}-$index'),
        behavior: HitTestBehavior.opaque,
        // Start behaviour `down` so the drag delta is measured from the press,
        // not from where the touch-slop was overcome — a dot dropped a known
        // pixel distance lands on a known `t`, with no slop eaten in between.
        dragStartBehavior: DragStartBehavior.down,
        onTap: () => _select(index),
        onHorizontalDragStart: (_) => setState(() {
          _dragIndex = index;
          _dragT = widget.row.keys[index].t;
        }),
        onHorizontalDragUpdate: (d) {
          if (width <= 0) return;
          setState(() {
            _dragT = ((_dragT ?? 0.0) + d.delta.dx / width).clamp(0.0, 1.0);
          });
        },
        onHorizontalDragEnd: (_) {
          final target = _dragT;
          setState(() {
            _dragIndex = null;
            _dragT = null;
          });
          if (target == null) return;
          // ONE command, on release, against the index grabbed at drag start.
          // A drop within minSeparation is rejected by the op and the dot
          // springs back — the model never changed, so it re-renders at the
          // original `t` and the refusal shows as a snackbar.
          _report(
              context,
              _commands.move(
                  widget.row.node, widget.row.property, index, target));
        },
        child: Center(
          child: CustomPaint(
            size: const Size(kTimelineDotRadius * 2, kTimelineDotRadius * 2),
            painter: _DotPainter(
              color: isSelected ? scheme.primary : scheme.tertiary,
              ring: isSelected ? scheme.onPrimary : null,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Layout constants -------------------------------------------------------

/// The left gutter that holds a row's node/property label. Shared by the ruler
/// and the rows so a dot at `t` sits under the playhead at the same `t`.
const double kTimelineLabelWidth = 96.0;
const double kTimelineRowHeight = 22.0;
const double kTimelineDotRadius = 4.5;

// --- Easing presets ---------------------------------------------------------

/// The picker's offerings (docs/v3/05 §4.4). `Linear` and `Hold` are their own
/// easing kinds; the six named curves are `CubicEasing` **constants** — four
/// numbers, no preset symbol — so nothing but concrete easing reaches the model
/// (AC-7.1.2).
typedef _Preset = ({String id, String label, Easing easing});

const List<_Preset> _easingPresets = <_Preset>[
  (id: 'linear', label: 'Linear', easing: LinearEasing()),
  (id: 'hold', label: 'Hold', easing: HoldEasing()),
  (id: 'ease', label: 'Ease', easing: CubicEasing.ease),
  (id: 'easeIn', label: 'Ease In', easing: CubicEasing.easeIn),
  (id: 'easeOut', label: 'Ease Out', easing: CubicEasing.easeOut),
  (id: 'easeInOut', label: 'Ease In-Out', easing: CubicEasing.easeInOut),
  (id: 'backIn', label: 'Back In', easing: CubicEasing.backIn),
  (id: 'backOut', label: 'Back Out', easing: CubicEasing.backOut),
];

String _easingGlyph(Easing e) => switch (e) {
      LinearEasing() => '—',
      HoldEasing() => '⇥',
      CubicEasing() => '∿',
      UnknownEasing() => '?',
    };

String _propLabel(PropertyKey p) => switch (p.prop) {
      PropKey.position => 'position',
      PropKey.scale => 'scale',
      PropKey.rotation => 'rotation',
      PropKey.skewX => 'skew',
      PropKey.opacity => 'opacity',
      PropKey.visible => 'visible',
      PropKey.path => 'path',
      PropKey.fillColor => 'fill',
      PropKey.fillOpacity => 'fill opacity',
      PropKey.strokeColor => 'stroke',
      PropKey.strokeOpacity => 'stroke opacity',
      PropKey.strokeWidth => 'stroke width',
      PropKey.trimStart => 'trim start',
      PropKey.trimEnd => 'trim end',
      PropKey.trimOffset => 'trim offset',
    };

// --- Painters (nothing mutable; the model is unitless `t`) -------------------

class _SummaryPainter extends CustomPainter {
  _SummaryPainter({required this.times, required this.rail, required this.dot});

  final List<double> times;
  final Color rail;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = rail
          ..strokeWidth = 1);
    final p = Paint()..color = dot;
    for (final t in times) {
      if (!t.isFinite) continue;
      canvas.drawCircle(Offset(t.clamp(0.0, 1.0) * size.width, y), 3, p);
    }
  }

  @override
  bool shouldRepaint(_SummaryPainter old) =>
      old.rail != rail ||
      old.dot != dot ||
      old.times.length != times.length ||
      _differ(old.times, times);

  static bool _differ(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }
}

class _RowRailPainter extends CustomPainter {
  _RowRailPainter({required this.rail});

  final Color rail;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = rail
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_RowRailPainter old) => old.rail != rail;
}

class _DotPainter extends CustomPainter {
  _DotPainter({required this.color, this.ring});

  final Color color;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, kTimelineDotRadius, Paint()..color = color);
    final r = ring;
    if (r != null) {
      canvas.drawCircle(
        c,
        kTimelineDotRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = r,
      );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color || old.ring != ring;
}
