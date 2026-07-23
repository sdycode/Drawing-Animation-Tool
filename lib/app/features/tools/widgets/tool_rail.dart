/// The toolbar — the left rail of docs/v3/05 §2's layout.
///
/// **Modal, exactly one active** (docs/v3/05 §3). It owns the active tool and
/// nothing else: it never reads or writes the selection, never touches the
/// document, and holds no state of its own. Pressing a button is one call to
/// [ToolController.activate], which is the same call the `V`/`A`/`P`/`R`/`O`/`G`
/// bindings in the shell make — one route, so a key and a click cannot leave the
/// rail showing one tool while another is live.
///
/// **Pan and Zoom are not here.** docs/v3/05 §3 is explicit that they are
/// ephemeral viewport gestures — hold `Space`, middle-drag, `Cmd`+scroll — that
/// mutate nothing. Making either a modal tool would give the camera a mode that
/// swallows clicks meant for Select, which is exactly the trap the "Mutates via:
/// *Nothing. Ephemeral only.*" row exists to close.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/tool_controller.dart';

/// One row of the rail: what it looks like and what it is called.
///
/// A **map with a `?? ` fallback**, not an exhaustive `switch` (docs/v3/08 §2):
/// a tool added in v2 without a rail entry simply does not get a button, rather
/// than making this widget stop compiling.
const Map<ToolId, ({IconData icon, String label, String key})> kToolButtons = {
  ToolId.select: (icon: Icons.near_me_outlined, label: 'Select', key: 'V'),
  ToolId.directSelect: (
    icon: Icons.polyline_outlined,
    label: 'Direct select',
    key: 'A',
  ),
  ToolId.pen: (icon: Icons.draw_outlined, label: 'Pen', key: 'P'),
  ToolId.rect: (icon: Icons.crop_square, label: 'Rectangle', key: 'R'),
  ToolId.ellipse: (icon: Icons.circle_outlined, label: 'Ellipse', key: 'O'),
  ToolId.polygon: (icon: Icons.pentagon_outlined, label: 'Polygon', key: 'G'),
};

class ToolRail extends ConsumerWidget {
  const ToolRail({super.key});

  /// Fixed, like every other panel's slot (docs/v3/08 §2, last row) — a rail
  /// that took a flex share would steal width from the canvas.
  static const double width = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A named slice: the rail rebuilds when the active tool *id* changes and at
    // no other time. Watching the whole `ToolMode` would rebuild it on nothing
    // (the object is identical across a gesture) and watching the document or
    // the editor state would rebuild it on everything.
    final active = ref.watch(toolControllerProvider.select((t) => t.id));
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      color: scheme.surfaceContainerHighest,
      child: Column(
        children: [
          const SizedBox(height: 6),
          for (final entry in kToolButtons.entries)
            _ToolButton(
              id: entry.key,
              icon: entry.value.icon,
              tooltip: '${entry.value.label} (${entry.value.key})',
              selected: entry.key == active,
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends ConsumerWidget {
  const _ToolButton({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.selected,
  });

  final ToolId id;
  final IconData icon;
  final String tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: IconButton(
        key: Key('tool-${id.name}'),
        tooltip: tooltip,
        isSelected: selected,
        iconSize: 18,
        style: IconButton.styleFrom(
          backgroundColor: selected ? scheme.primaryContainer : null,
          foregroundColor:
              selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
        icon: Icon(icon),
        onPressed: () => ref.read(toolControllerProvider.notifier).activate(id),
      ),
    );
  }
}
