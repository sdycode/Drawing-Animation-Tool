// `Easing` is declared by both anim_core (the sealed type we author) and
// `package:flutter/material.dart` (its animation-curve constants), and
// `Animation` by both anim_core and Flutter — hide each clashing name from the
// import that does not own it, so the switch over the sealed `Easing` stays
// exhaustive (docs/v3/01 §10; enforced by tool/check_boundaries.dart).
import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' hide Easing;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/editor_toast.dart';
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

  /// Move the playhead to [t] — what clicking any keyframe dot means.
  ///
  /// The same live/settled pair the ruler's scrub and the bar's `Home`/`End`
  /// keep in step: the notifier write repaints the canvas without rebuilding
  /// anything, and `commitPlayhead` settles `EditorState` so edit-at-keyframe
  /// reads a stable value. **This is not an edit** — the playhead is ephemeral
  /// and never serialized — which is what lets the collapsed summary row stay
  /// read-only (docs/v3/05 §2) while still being clickable.
  void _seek(double t) {
    final clamped = t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
    ref.read(playheadProvider).value = clamped;
    ref.read(editorControllerProvider.notifier).commitPlayhead(clamped);
  }

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
        key: ValueKey<String>('node-row-${node.node.v}'),
        node: node,
        expanded: isExpanded,
        labelWidth: widget.labelWidth,
        onToggle: () => _toggle(node.node),
        onSeek: _seek,
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
/// union of the node's keys (docs/v3/05 §2).
///
/// **The summary dots are real hit targets, not paint.** They used to be circles
/// inside a `CustomPaint` with no gesture anywhere near them — and because every
/// node starts collapsed, those were the *only* dots most users ever saw. Every
/// click on one did nothing, which reads as a broken timeline rather than as a
/// deliberately read-only row.
///
/// Read-only still holds: a summary dot **seeks**, it does not drag. A dot here
/// is the union of however many properties happen to key at that `t`, so there
/// is no single track a drag could address — and moving the playhead is not a
/// document edit at all (the playhead is ephemeral, AC-2.2.7). Editing a key
/// still means expanding the node and using its property row.
class _NodeHeaderRow extends StatefulWidget {
  const _NodeHeaderRow({
    required this.node,
    required this.expanded,
    required this.labelWidth,
    required this.onToggle,
    required this.onSeek,
    super.key,
  });

  final TimelineNodeModel node;
  final bool expanded;
  final double labelWidth;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;

  @override
  State<_NodeHeaderRow> createState() => _NodeHeaderRowState();
}

class _NodeHeaderRowState extends State<_NodeHeaderRow> {
  /// The summary dot under the pointer, or null. Local, ephemeral, and never
  /// read by anything else — hover is not state anyone else has a stake in.
  int? _hovered;

  void _setHovered(int? i) {
    if (_hovered != i) setState(() => _hovered = i);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final node = widget.node;
    return SizedBox(
      height: kTimelineRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: widget.labelWidth,
            child: InkWell(
              key: Key('node-${node.node.v}'),
              onTap: widget.onToggle,
              child: Row(
                children: [
                  Icon(
                    widget.expanded ? Icons.arrow_drop_down : Icons.arrow_right,
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
              builder: (context, c) => Stack(
                key: Key('summary-${node.node.v}'),
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RowRailPainter(rail: scheme.outlineVariant),
                    ),
                  ),
                  // Drawn only while collapsed; expanding replaces the summary
                  // with the editable property rows below it.
                  if (!widget.expanded)
                    for (var i = 0; i < node.summary.length; i++)
                      _KeyDotHitBox(
                        key: Key('summary-kf-${node.node.v}-$i'),
                        dx: node.summary[i].clamp(0.0, 1.0) * c.maxWidth,
                        radius: kTimelineSummaryDotRadius,
                        hovered: _hovered == i,
                        selected: false,
                        tone: scheme.onSurfaceVariant,
                        scheme: scheme,
                        onEnter: () => _setHovered(i),
                        onExit: () => _setHovered(null),
                        onTap: () => widget.onSeek(node.summary[i]),
                      ),
                ],
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

  /// The dot under the pointer, or null. Purely local like the header row's.
  int? _hovered;

  void _setHovered(int? i) {
    if (_hovered != i) setState(() => _hovered = i);
  }

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
    void show(String message) => showEditorToast(messenger, message);
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
    return _KeyDotHitBox(
      key: Key('kf-${widget.row.node.v}-${widget.row.property.wire}-$index'),
      dx: x(t),
      radius: kTimelineDotRadius,
      // A dot stays lit for the whole drag: the pointer routinely leaves the
      // 18 px box while dragging (that is the point of a drag), and letting the
      // highlight drop out mid-gesture reads as losing the grab.
      hovered: _hovered == index || _dragIndex == index,
      selected: isSelected,
      tone: scheme.tertiary,
      scheme: scheme,
      onEnter: () => _setHovered(index),
      onExit: () => _setHovered(null),
      onTap: () => _select(index),
      // Start behaviour `down` so the drag delta is measured from the press,
      // not from where the touch-slop was overcome — a dot dropped a known
      // pixel distance lands on a known `t`, with no slop eaten in between.
      onDragStart: () => setState(() {
        _dragIndex = index;
        _dragT = widget.row.keys[index].t;
      }),
      onDragUpdate: (dx) {
        if (width <= 0) return;
        setState(() {
          _dragT = ((_dragT ?? 0.0) + dx / width).clamp(0.0, 1.0);
        });
      },
      onDragEnd: () {
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
        _report(context,
            _commands.move(widget.row.node, widget.row.property, index, target));
      },
    );
  }
}

/// One keyframe dot: its hit box, its hover reporting and its paint.
///
/// **Both rows use this one widget**, so the summary dot and the property dot
/// can never drift apart in size, in what "hovered" looks like, or in how big
/// the thing you actually have to hit is. The visual radius is [radius]; the
/// *hit* box is [kTimelineDotHitWidth] wide regardless, because a 4.5 px circle
/// is not a click target — that gap between what is drawn and what is clickable
/// is why "I clicked the dot and nothing happened" is worth guarding against
/// even on the rows that always did respond.
///
/// Hover is reported up rather than kept here: the parent already rebuilds for
/// selection and drag, and a dot that owned its own hover would be a second
/// `setState` per pointer move on a widget the parent rebuilds anyway.
///
/// The drag callbacks are optional. The summary row passes none — it seeks and
/// never edits — and with them absent no drag recognizer is created at all, so
/// the row cannot enter a gesture arena it has nothing to win.
class _KeyDotHitBox extends StatelessWidget {
  const _KeyDotHitBox({
    required this.dx,
    required this.radius,
    required this.hovered,
    required this.selected,
    required this.tone,
    required this.scheme,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    super.key,
  });

  /// The dot's centre, in pixels across the rail.
  final double dx;
  final double radius;
  final bool hovered;
  final bool selected;

  /// The resting fill — the property rows' key colour, or the quieter summary
  /// one. Selection and hover both override it.
  final Color tone;
  final ColorScheme scheme;

  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;
  final VoidCallback? onDragStart;
  final ValueChanged<double>? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final draggable = onDragStart != null;
    return Positioned(
      left: dx - kTimelineDotHitWidth / 2,
      top: 0,
      width: kTimelineDotHitWidth,
      height: kTimelineRowHeight,
      child: MouseRegion(
        // `click` on the summary (it only seeks) and the horizontal resize
        // cursor on a property dot, which says "this one moves in time" before
        // the user commits to the drag.
        cursor: draggable
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.click,
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: onTap,
          onHorizontalDragStart: draggable ? (_) => onDragStart!() : null,
          onHorizontalDragUpdate:
              draggable ? (d) => onDragUpdate!(d.delta.dx) : null,
          onHorizontalDragEnd: draggable ? (_) => onDragEnd!() : null,
          child: Center(
            child: CustomPaint(
              // A FIXED box, sized for the halo, so growing the dot on hover
              // repaints and never re-lays-out — a dot that nudged its
              // neighbours when you pointed at it would be unclickable.
              size: const Size.square(
                  (kTimelineDotRadius + kTimelineDotHaloGrow) * 2),
              painter: _DotPainter(
                color: selected ? scheme.primary : tone,
                ring: selected ? scheme.onPrimary : null,
                radius: hovered ? radius + kTimelineDotHoverGrow : radius,
                halo: hovered
                    ? (selected ? scheme.primary : tone)
                        .withValues(alpha: 0.24)
                    : null,
                haloRadius: radius + kTimelineDotHaloGrow,
              ),
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

/// The quieter dot on a collapsed node's union row.
const double kTimelineSummaryDotRadius = 3.5;

/// **How wide a keyframe dot is to the pointer**, as opposed to how wide it
/// looks. A 4.5 px circle is a 9 px target; this is the box that actually
/// receives the click, on every row, so "click the dot" is a gesture a hand can
/// make. Dots closer together than this overlap and the topmost wins, which is
/// the right outcome — the alternative is a gap between them that swallows
/// clicks.
const double kTimelineDotHitWidth = 18.0;

/// Hover feedback: the dot grows by this much, inside a soft halo this much
/// wider again. Both are pure repaint — the hit box never changes size, so
/// pointing at a dot cannot move it or its neighbours out from under the
/// pointer.
const double kTimelineDotHoverGrow = 1.5;
const double kTimelineDotHaloGrow = 4.0;

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

/// A keyframe dot: an optional [halo] behind it, the fill, and an optional
/// selection [ring] on top. [radius] is the fill's, and it varies with hover —
/// the painter's own [size] does not, so none of this ever triggers a layout.
class _DotPainter extends CustomPainter {
  _DotPainter({
    required this.color,
    required this.radius,
    required this.haloRadius,
    this.ring,
    this.halo,
  });

  final Color color;
  final double radius;
  final double haloRadius;
  final Color? ring;
  final Color? halo;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final h = halo;
    if (h != null) {
      canvas.drawCircle(c, haloRadius, Paint()..color = h);
    }
    canvas.drawCircle(c, radius, Paint()..color = color);
    final r = ring;
    if (r != null) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = r,
      );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.color != color ||
      old.ring != ring ||
      old.halo != halo ||
      old.radius != radius ||
      old.haloRadius != haloRadius;
}
