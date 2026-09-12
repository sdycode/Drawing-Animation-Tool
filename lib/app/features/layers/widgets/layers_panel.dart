import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../common/editor_toast.dart';

import '../../../state/editor_controller.dart';
import '../commands.dart';
import '../providers.dart';

/// Where a drop lands relative to the row it landed on (docs/v3/05 §4.5 steps
/// 2 and 3).
///
/// **The two outcomes must be distinguishable before the user lets go**, which
/// is why this is a zone and not a guess: `above`/`below` reorder *next to* the
/// row and draw an insertion line on that edge; `inside` drops *into* a group
/// and highlights the whole row. The previous implementation had no zones at
/// all — it tested `dragged.parent == target.parent` before `target.isGroup`,
/// so dropping a layer onto a sibling group reordered the root instead of
/// reparenting, and in a fresh document (where every layer is a root child)
/// "drag a layer into a group" could never happen at all. An empty top-level
/// group was unfillable by any gesture.
enum _DropZone {
  /// In front of the target — the top edge, because the list is front-most
  /// first (AC-2.2.1).
  above,

  /// Into the target group, front-most among its children.
  inside,

  /// Behind the target — the bottom edge.
  below,
}

/// The Layers panel — the tree, z-order, rename, visibility and lock (F2.2,
/// docs/v3/05 §2).
///
/// **Reads named slices only** (docs/v3/08 §2): the value-equal [LayersView],
/// the shared selection set and the [LayersActions] gate, never the whole
/// document. So a scrub or an anchor drag rebuilds nothing here (AC-13.3) —
/// only a change to the tree's shape, names, flags or order does.
///
/// **The list is displayed front-most first** (AC-2.2.1): child index 0 paints
/// back-most, so [LayersView] reverses each level and this widget draws that
/// order top-to-bottom.
///
/// **Selection is the same slice both ways.** Tapping a row selects the node
/// through `EditorController.selectNode`, the identical `EditorState.selectedNodes`
/// the canvas outlines — pick a shape on the canvas and its row lights up, and
/// vice versa.
///
/// **A locked row rejects selection AND drag** (docs/v3/05 §4.5's closing line,
/// AC-2.2.6), while a hidden row still reorders — the two sentences sit side by
/// side in the spec and give the two states opposite treatment. A reorder is an
/// authored `children` splice: it changes paint order and it is persisted, so it
/// is exactly the kind of edit a lock exists to refuse. The lock **inherits down
/// the tree** here as it does on the canvas; reading only the row's own flag was
/// a bypass around AC-2.2.6.
class LayersPanel extends ConsumerWidget {
  const LayersPanel({required this.projectId, super.key});

  final String projectId;

  /// Rebuild counter for the isolation tests (the pattern `CanvasView`
  /// established). docs/v3/08 §2's headline failure — "an anchor commit
  /// rebuilding layers + inspector + timeline" — is only *observable* at the
  /// widget level: a value-equal slice refuses to notify, and the panel rebuilds
  /// anyway if its parent hands it a new instance. Asserting on the projection
  /// alone passes while the mounted panel churns.
  static int debugBuildCount = 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugBuildCount++;
    final view = ref.watch(layersViewProvider(projectId));
    final selected = ref.watch(layersSelectionProvider);
    final actions = ref.watch(layersActionsProvider(projectId));
    final scheme = Theme.of(context).colorScheme;

    return Container(
      key: const Key('layers-panel'),
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, ref, actions),
          Expanded(
            child: view.rows.isEmpty
                ? _emptyHint(context)
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: view.rows.length,
                    itemBuilder: (context, i) {
                      final row = view.rows[i];
                      return _LayerTile(
                        key: ValueKey<String>('layer-row-${row.id.v}'),
                        row: row,
                        selected: selected.contains(row.id),
                        onSelect: () => _select(ref, row),
                        onToggleVisible: () => _report(
                            context,
                            LayersCommands(ref, projectId)
                                .setVisible(row.id, !row.visible)),
                        onToggleLocked: () => _report(
                            context,
                            LayersCommands(ref, projectId)
                                .setLocked(row.id, !row.lockedSelf)),
                        onRename: (name) => _report(
                            context,
                            LayersCommands(ref, projectId)
                                .rename(row.id, name)),
                        canAccept: (dragged) => _canAccept(view, dragged, row),
                        onDropOnto: (dragged, zone) =>
                            _drop(context, ref, dragged, row, zone),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Selection respects the lock gate (AC-2.2.6) and skips an [UnknownNode]
  /// (AC-1.2.4 — a node this build cannot read is not a node it can edit, and
  /// selecting it hands the inspector a form for a document it must not write).
  /// `Shift` adds, matching the canvas, because the two share one selection set.
  void _select(WidgetRef ref, LayerRow row) {
    if (row.locked || row.isUnknown) return;
    final editor = ref.read(editorControllerProvider.notifier);
    final path = ScenePath(row.id);
    if (HardwareKeyboard.instance.isShiftPressed) {
      editor.addToSelection(path);
    } else {
      editor.selectNode(path);
    }
  }

  /// Whether [dragged] may be dropped on [target] **at all**.
  ///
  /// A cycle — dropping a group onto itself or one of its own descendants — is
  /// refused by design in `NodeOps.reparent`, so it is refused *here*, before
  /// the row can highlight as a valid target. Letting it highlight and then
  /// failing was the second half of the `assert(false)`-on-user-input defect:
  /// in debug the assert threw and no snackbar appeared at all.
  bool _canAccept(LayersView view, LayerRow dragged, LayerRow target) {
    if (dragged.id == target.id) return false;
    if (dragged.locked) return false; // a locked row is not draggable either
    return !view.isSelfOrDescendantOf(target.id, dragged.id);
  }

  /// Turn a drop into exactly one command (docs/v3/05 §4.5).
  ///
  /// `inside` → a world-preserving reparent into the target group; the node does
  /// not visually move. `above`/`below` → a reorder within one parent (a pure
  /// `children` splice that leaves the transform byte-identical, AC-2.2.2), or a
  /// reparent into the target's parent at the target's slot when the parents
  /// differ.
  ///
  /// **`isGroup` is tested before same-parent**, which is the inverse of the
  /// order this method used to have, because a group is very often a *sibling*
  /// of the row being dragged — that is the whole "drag a layer into a group"
  /// gesture, and testing same-parent first swallowed it.
  void _drop(BuildContext context, WidgetRef ref, LayerRow dragged,
      LayerRow target, _DropZone zone) {
    if (dragged.id == target.id) return;
    final commands = LayersCommands(ref, projectId);

    if (zone == _DropZone.inside) {
      if (dragged.parent == target.id) {
        // Already inside: this is a z-order change, not a move. Keep it a
        // splice so the transform is not round-tripped through decompose.
        _report(context,
            commands.reorder(target.id, dragged.childIndex, _frontMost));
      } else {
        // A large index clamps to "append", which reads as the top of the
        // group's sublist once the list is drawn front-first.
        _report(context, commands.reparent(dragged.id, target.id, _frontMost));
      }
      return;
    }

    final inFront = zone == _DropZone.above;
    if (dragged.parent == target.parent) {
      _report(
          context,
          commands.reorder(dragged.parent, dragged.childIndex,
              _adjacentIndex(dragged.childIndex, target.childIndex, inFront)));
    } else {
      _report(
          context,
          commands.reparent(dragged.id, target.parent,
              inFront ? target.childIndex + 1 : target.childIndex));
    }
  }

  /// Bigger than any child list; `NodeOps` clamps it to "append" (= front-most).
  static const int _frontMost = 1 << 20;

  /// The child index a same-parent drop should land on.
  ///
  /// `ReorderChildCommand` removes the node first and inserts at the target
  /// index, so the target's own index shifts down by one whenever the dragged
  /// row came from behind it. Front-most is the *highest* index (index 0 paints
  /// back-most, docs/v3/01 §3), and the list is drawn reversed, so "above" means
  /// "one in front of the target".
  static int _adjacentIndex(int from, int target, bool inFront) {
    if (inFront) return from < target ? target : target + 1;
    return from < target ? target - 1 : target;
  }

  /// Capture the messenger before the await so a rejected edit still surfaces
  /// even though this `ConsumerWidget` has no `mounted` to check.
  ///
  /// **`onError` is not optional.** Without it, anything that escapes
  /// `LayersCommands._guard` — historically the `assert(false)` it ran *inside*
  /// its own catch — completes this future with an error nobody listens for,
  /// and Flutter reports an unhandled async error instead of the snackbar this
  /// method exists to show. A dropped future must not be able to take the zone
  /// down with it.
  void _report(BuildContext context, Future<String?> pending) {
    final messenger = ScaffoldMessenger.of(context);
    void show(String message) => showEditorToast(messenger, message);
    pending.then(
      (message) {
        if (message != null) show(message);
      },
      onError: (Object _, StackTrace __) => show(kRejectedLayerEditMessage),
    );
  }

  /// The rail header, and the home of the two affordances M2's exit criterion
  /// needs: **Group** (`Cmd/Ctrl+G`) and **Duplicate** (`Cmd/Ctrl+D`).
  ///
  /// Both are disabled — with the reason in the tooltip — when the selection
  /// cannot take them, rather than being enabled and silently doing nothing.
  /// The same two commands are bound as shortcuts in the shell, which is the one
  /// place a global key binding can live (docs/v3/05 §5).
  Widget _header(BuildContext context, WidgetRef ref, LayersActions actions) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 12, right: 2),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(
            child: Text('Layers',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
          ),
          _headerButton(
            key: const Key('layers-group'),
            icon: Icons.create_new_folder_outlined,
            tooltip: actions.groupBlockedReason ?? 'Group (Ctrl/Cmd+G)',
            scheme: scheme,
            onPressed: actions.canGroup
                ? () => _report(context,
                    LayersCommands(ref, projectId).group(actions.groupMembers))
                : null,
          ),
          _headerButton(
            key: const Key('layers-duplicate'),
            icon: Icons.content_copy_outlined,
            tooltip: actions.duplicateBlockedReason ?? 'Duplicate (Ctrl/Cmd+D)',
            scheme: scheme,
            onPressed: actions.canDuplicate
                ? () => _report(
                    context,
                    LayersCommands(ref, projectId)
                        .duplicate(actions.duplicateTarget!))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required ColorScheme scheme,
    required VoidCallback? onPressed,
  }) =>
      IconButton(
        key: key,
        tooltip: tooltip,
        icon: Icon(icon, size: 15),
        color: scheme.onSurfaceVariant,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: onPressed,
      );

  Widget _emptyHint(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'No layers yet.\nDraw on the canvas to add one.',
        key: const Key('layers-empty'),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// One tree row. Stateful for its inline rename editor and for the drop zone the
/// pointer is currently over — everything else is pushed up as callbacks so the
/// tile watches no provider and rebuilds only when the panel hands it a new
/// [row] or [selected].
class _LayerTile extends StatefulWidget {
  const _LayerTile({
    required this.row,
    required this.selected,
    required this.onSelect,
    required this.onToggleVisible,
    required this.onToggleLocked,
    required this.onRename,
    required this.canAccept,
    required this.onDropOnto,
    super.key,
  });

  final LayerRow row;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLocked;
  final ValueChanged<String> onRename;
  final bool Function(LayerRow dragged) canAccept;
  final void Function(LayerRow dragged, _DropZone zone) onDropOnto;

  @override
  State<_LayerTile> createState() => _LayerTileState();
}

class _LayerTileState extends State<_LayerTile> {
  bool _editing = false;
  TextEditingController? _nameController;
  FocusNode? _nameFocus;

  /// The zone the dragged row is currently hovering, or null when it is not.
  _DropZone? _hoverZone;

  /// When this row was last tapped, for the hand-rolled double-click below.
  DateTime? _lastTapAt;

  /// The platform double-click window. Matches `kDoubleTapTimeout`.
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

  static const double _rowHeight = 34;

  /// A group offers an *inside* zone; a leaf and a **locked** group do not.
  ///
  /// Dropping into a locked group splices that group's authored `children`, so
  /// it is the same protected edit a locked row refuses everywhere else. Making
  /// the zone unavailable (rather than accepting and then failing) keeps the
  /// highlight honest: the row shows an insertion line, never an "inside" fill.
  bool get _acceptsInside => widget.row.isGroup && !widget.row.locked;

  /// Select on the first tap, rename on a second tap inside the window.
  ///
  /// **Why this is not `InkWell.onDoubleTap`.** Registering a double-tap
  /// recognizer alongside the tap one makes the tap wait out the 300 ms
  /// double-tap timer before it fires — and because the recognizer sits above
  /// the whole row, it delays the **eye and lock buttons nested inside it** too.
  /// Selection is the most frequent action in this panel and it must be
  /// instant, so the row registers a tap and nothing else, and the second click
  /// is detected here from its timestamp. Selection still happens on the first
  /// click of a double-click, which is what the user wants anyway: you rename
  /// the row you just selected.
  void _handleTap() {
    if (_editing) return;
    final now = DateTime.now();
    final previous = _lastTapAt;
    _lastTapAt = now;
    if (previous != null && now.difference(previous) < _doubleTapWindow) {
      _lastTapAt = null;
      _beginRename();
      return;
    }
    widget.onSelect();
  }

  void _beginRename() {
    // An unknown node re-emits raw JSON verbatim, so a typed rename would be
    // dropped on save (NodeOps refuses it). Do not offer the editor.
    if (widget.row.isUnknown) return;
    // A locked row rejects every authored edit, and a rename is one — the lock
    // would otherwise protect the child list and leave the name wide open.
    if (widget.row.locked) return;
    _nameController = TextEditingController(text: widget.row.name);
    final focus = FocusNode(debugLabel: 'layer-rename');
    _nameFocus = focus;
    focus.addListener(() {
      if (!focus.hasFocus) _commitRename(releaseFocus: false);
    });
    setState(() => _editing = true);
  }

  /// Commit the rename and **release focus** (docs/v3/05 §5): a rename field that
  /// keeps focus turns the next `Cmd/Ctrl+Z` into a browser text-undo instead of
  /// an editor undo.
  void _commitRename({required bool releaseFocus}) {
    if (!_editing) return;
    final text = _nameController?.text.trim() ?? '';
    final focus = _nameFocus;
    setState(() => _editing = false);
    if (text.isNotEmpty && text != widget.row.name) {
      widget.onRename(text);
    }
    if (releaseFocus) focus?.unfocus();
    _disposeRenameControllers();
  }

  void _disposeRenameControllers() {
    _nameController?.dispose();
    _nameController = null;
    _nameFocus?.dispose();
    _nameFocus = null;
  }

  @override
  void dispose() {
    _disposeRenameControllers();
    super.dispose();
  }

  /// Which zone the pointer sits in, from its offset inside this row.
  ///
  /// A group keeps a narrow "reorder next to me" band at the top and gives the
  /// rest to "drop inside me", because its children are drawn directly below it
  /// — a bottom band there would read as "the front-most child" anyway.
  _DropZone _zoneAt(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? _rowHeight;
    final y = box == null ? 0.0 : box.globalToLocal(globalPosition).dy;
    if (_acceptsInside) {
      return y < height * 0.3 ? _DropZone.above : _DropZone.inside;
    }
    return y < height * 0.5 ? _DropZone.above : _DropZone.below;
  }

  void _updateZone(Offset globalPosition) {
    final zone = _zoneAt(globalPosition);
    if (zone != _hoverZone) setState(() => _hoverZone = zone);
  }

  void _clearZone() {
    if (_hoverZone != null) setState(() => _hoverZone = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = widget.row;

    final tile = InkWell(
      onTap: _handleTap,
      child: Container(
        height: _rowHeight,
        color: widget.selected ? scheme.primaryContainer : Colors.transparent,
        padding: EdgeInsets.only(left: 8.0 + row.depth * 16, right: 4),
        child: Row(
          children: [
            Icon(
              row.isUnknown
                  ? Icons.help_outline
                  : row.isGroup
                      ? Icons.folder_outlined
                      : Icons.polyline_outlined,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
                child: _editing ? _nameEditor(scheme) : _nameLabel(scheme)),
            // AC-1.2.4: an `UnknownNode` keeps its flags in raw JSON, so
            // `NodeOps.setVisible`/`setLocked` refuse it — a toggle here could
            // ONLY fail. Offering a control whose every outcome is an error
            // message is worse than offering none, so the row carries a badge
            // instead and the document from the newer editor survives untouched.
            if (row.isUnknown)
              _unknownBadge(scheme)
            else ...[
              _iconToggle(
                key: Key('layer-visible-${row.id.v}'),
                icon: row.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                active: row.visible,
                tooltip: row.visible ? 'Hide' : 'Show',
                onTap: widget.onToggleVisible,
                scheme: scheme,
              ),
              _iconToggle(
                key: Key('layer-lock-${row.id.v}'),
                icon:
                    row.locked ? Icons.lock_outline : Icons.lock_open_outlined,
                active: row.locked,
                tooltip: row.lockedByAncestor
                    ? 'Locked by a group above it — unlock that group'
                    : row.lockedSelf
                        ? 'Unlock'
                        : 'Lock',
                // A row locked only by an ancestor has nothing useful to
                // toggle: writing its own flag would change nothing visible.
                onTap: row.lockedByAncestor ? null : widget.onToggleLocked,
                scheme: scheme,
              ),
            ],
            _dragHandle(scheme, row),
          ],
        ),
      ),
    );

    return DragTarget<LayerRow>(
      onWillAcceptWithDetails: (details) {
        if (!widget.canAccept(details.data)) return false;
        _updateZone(details.offset);
        return true;
      },
      onMove: (details) => _updateZone(details.offset),
      onLeave: (_) => _clearZone(),
      onAcceptWithDetails: (details) {
        final zone = _zoneAt(details.offset);
        _clearZone();
        widget.onDropOnto(details.data, zone);
      },
      builder: (context, candidate, rejected) {
        final zone = candidate.isEmpty ? null : _hoverZone;
        return Container(
          key: zone == null ? null : Key('layer-drop-${zone.name}-${row.id.v}'),
          decoration: _dropDecoration(zone, scheme),
          child: tile,
        );
      },
    );
  }

  /// An insertion line on the edge the row will be placed against, or a full
  /// highlight when the drop goes *inside* the group. The two must not look
  /// alike: they are different commands with different results.
  BoxDecoration? _dropDecoration(_DropZone? zone, ColorScheme scheme) =>
      switch (zone) {
        null => null,
        _DropZone.above => BoxDecoration(
            border: Border(top: BorderSide(color: scheme.primary, width: 2))),
        _DropZone.below => BoxDecoration(
            border:
                Border(bottom: BorderSide(color: scheme.primary, width: 2))),
        _DropZone.inside => BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.5),
            border: Border.all(color: scheme.primary, width: 2)),
      };

  /// The `⠿` reorder grip of docs/v3/05 §2's panel sketch, and the **only**
  /// draggable part of the row.
  ///
  /// Dragging the whole row instead would put a drag recognizer in the arena
  /// above every tap target in the tile, and it wins: the row would stop
  /// selecting and the eye/lock buttons would stop responding. A dedicated grip
  /// is both what the spec draws and what keeps tap and drag from competing.
  ///
  /// **A locked row has no grip** (docs/v3/05 §4.5: "Locked rows reject
  /// selection *and drag*. Hidden rows still reorder."). A reorder is an
  /// authored `children` splice that changes paint order and is persisted, and a
  /// cross-parent drop rewrites the node's own `Transform2` to preserve its
  /// world position — a locked node ending up with a decomposed rotation and
  /// scale it never authored is precisely what the flag is for. Hidden rows keep
  /// their grip.
  Widget _dragHandle(ColorScheme scheme, LayerRow row) {
    if (row.locked) {
      return Tooltip(
        message: 'Locked — unlock it to reorder',
        child: Icon(
          Icons.drag_indicator,
          key: Key('layer-drag-locked-${row.id.v}'),
          size: 16,
          color: scheme.outlineVariant,
        ),
      );
    }
    return Draggable<LayerRow>(
      data: row,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(row.name.isEmpty ? 'Layer' : row.name,
              style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
        ),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Icon(
          Icons.drag_indicator,
          key: Key('layer-drag-${row.id.v}'),
          size: 16,
          color: scheme.outline,
        ),
      ),
    );
  }

  Widget _unknownBadge(ColorScheme scheme) => Tooltip(
        message: 'Written by a newer editor — preserved, not editable',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('newer',
              key: Key('layer-unknown-${widget.row.id.v}'),
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
        ),
      );

  Widget _nameLabel(ColorScheme scheme) => Text(
        widget.row.name.isEmpty ? 'Untitled' : widget.row.name,
        key: Key('layer-name-${widget.row.id.v}'),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          // A hidden row reads as muted, so the eye toggle's effect is legible
          // without opening the canvas.
          color: widget.row.visible
              ? scheme.onSurface
              : scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      );

  Widget _nameEditor(ColorScheme scheme) => TextField(
        key: Key('layer-rename-${widget.row.id.v}'),
        controller: _nameController,
        focusNode: _nameFocus,
        autofocus: true,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commitRename(releaseFocus: true),
      );

  Widget _iconToggle({
    required Key key,
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback? onTap,
    required ColorScheme scheme,
  }) =>
      IconButton(
        key: key,
        tooltip: tooltip,
        icon: Icon(icon, size: 15),
        color: active ? scheme.onSurface : scheme.onSurfaceVariant,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: onTap,
      );
}
