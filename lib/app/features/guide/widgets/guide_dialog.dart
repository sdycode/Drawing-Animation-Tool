/// **The how-to-use-it surface for the editor** — the one screen that explains
/// the flows the UI can only hint at (docs/v3/05 §4), above all *how a keyframe
/// is made*.
///
/// It exists because the editor is discoverable only if you already know the
/// convention: the ◇ beside a property is After Effects' stopwatch, and nothing
/// on screen says so. A stranger who cannot find that switch concludes the tool
/// cannot animate at all — the docs/v3/00 §5 ship-gate failure, in the one place
/// it costs the most.
///
/// **A feature that imports nothing.** It reads no provider, runs no command and
/// touches no `Document`; the chapters are prose and the only state is which one
/// is open. So it cannot desync from the editor at runtime, it cannot break a
/// panel, and deleting `features/guide/` is one import in `editor_shell.dart`
/// plus this folder (docs/v3/08 §5). The cost of that independence is that the
/// text is a *copy* of the bindings rather than a projection of them — so
/// everything below is what the editor actually does today, and a changed
/// binding has to be changed here too.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Open the guide. Returns when it is dismissed.
///
/// `showDialog`'s barrier and `Esc` both close it; there is nothing to save, so
/// there is nothing to confirm on the way out.
Future<void> showEditorGuide(BuildContext context, {int chapter = 0}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EditorGuideDialog(initialChapter: chapter),
  );
}

/// The app-bar entry point. Always enabled — the guide does not need a loaded
/// document, and the moment someone most needs it is the moment nothing is on
/// screen yet.
class GuideButton extends StatelessWidget {
  const GuideButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('editor-guide'),
      tooltip: 'How to use the editor (F1)',
      icon: const Icon(Icons.help_outline, size: 18),
      onPressed: () => showEditorGuide(context),
    );
  }
}

class EditorGuideDialog extends StatefulWidget {
  const EditorGuideDialog({this.initialChapter = 0, super.key});

  final int initialChapter;

  @override
  State<EditorGuideDialog> createState() => _EditorGuideDialogState();
}

class _EditorGuideDialogState extends State<EditorGuideDialog> {
  late int _index = widget.initialChapter.clamp(0, _chapters.length - 1);

  /// One controller reused across chapters, reset to the top on each move — a
  /// chapter that opened halfway down because the last one was long reads as a
  /// rendering bug.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() => _index = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    // Bounded on both axes, and never larger than the window it sits in: an
    // unconstrained dialog on a short laptop screen clips its own footer, which
    // is where Next lives.
    final width = math.min(920.0, math.max(320.0, screen.width - 48));
    final height = math.min(640.0, math.max(320.0, screen.height - 80));
    final narrow = width < 720;
    final chapter = _chapters[_index];

    return Dialog(
      key: const Key('editor-guide-dialog'),
      backgroundColor: scheme.surface,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            if (narrow) _chips(context),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!narrow) ...[
                    SizedBox(width: 208, child: _nav(context)),
                    VerticalDivider(width: 1, color: scheme.outlineVariant),
                  ],
                  Expanded(
                    child: Scrollbar(
                      controller: _scroll,
                      child: ListView(
                        key: ValueKey<int>(_index),
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                        children: [
                          Text(
                            chapter.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            chapter.blurb,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 18),
                          ...chapter.build(context),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'How to use the editor',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            key: const Key('editor-guide-close'),
            tooltip: 'Close',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// The wide-window chapter list.
  Widget _nav(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _chapters.length,
        itemBuilder: (context, i) {
          final selected = i == _index;
          final chapter = _chapters[i];
          return InkWell(
            key: Key('guide-chapter-$i'),
            onTap: () => _go(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : null,
                border: Border(
                  left: BorderSide(
                    width: 3,
                    color: selected ? scheme.primary : Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    chapter.icon,
                    size: 16,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The narrow-window chapter list: the same targets, laid out as a scrolling
  /// strip so the content keeps the width.
  Widget _chips(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      color: scheme.surfaceContainerLow,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _chapters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final selected = i == _index;
          return InkWell(
            key: Key('guide-chip-$i'),
            onTap: () => _go(i),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected ? scheme.primaryContainer : null,
                border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant),
              ),
              child: Text(
                _chapters[i].title,
                style: TextStyle(
                  fontSize: 11,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _index == _chapters.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      child: Row(
        children: [
          Text(
            '${_index + 1} of ${_chapters.length}',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          TextButton(
            key: const Key('guide-back'),
            onPressed: _index == 0 ? null : () => _go(_index - 1),
            child: const Text('Back'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            key: const Key('guide-next'),
            onPressed: last
                ? () => Navigator.of(context).pop()
                : () => _go(_index + 1),
            child: Text(last ? 'Start animating' : 'Next'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chapters
// ---------------------------------------------------------------------------

typedef _Chapter = ({
  String title,
  IconData icon,
  String blurb,
  List<Widget> Function(BuildContext) build,
});

/// Ordered as a first session runs: what am I looking at → draw something →
/// change it → **animate it** → refine the timing → paint it → play and export.
final List<_Chapter> _chapters = <_Chapter>[
  (
    title: 'The layout',
    icon: Icons.dashboard_outlined,
    blurb: 'Six panels. Each one owns exactly one job, and they never disagree '
        'about the document underneath.',
    build: (context) => [
      const _LayoutMap(),
      const SizedBox(height: 20),
      const _Bullets([
        ('Tools', 'The left rail — pick what a drag on the canvas does.'),
        (
          'Layers',
          'The document tree. Select, rename, reorder, group, duplicate — and '
              'hide, lock or delete any row from its own buttons.'
        ),
        (
          'Canvas',
          'Draw and direct-manipulate. It always shows the frame at the '
              'playhead, not the resting shape.'
        ),
        (
          'Inspector',
          'Numbers for the selected layer — and the ◇ switches that turn any of '
              'them into an animation.'
        ),
        (
          'Transport',
          'Play / pause, loop mode and the duration in seconds.'
        ),
        (
          'Timeline',
          'Every keyframe in the document. Scrub the ruler, drag the keys, and '
              'drag its top edge to make it taller.'
        ),
      ]),
    ],
  ),
  (
    title: 'Draw a shape',
    icon: Icons.draw_outlined,
    blurb: 'Three parametric shapes and a full bezier pen. Everything you draw '
        'becomes a layer.',
    build: (context) => [
      const _Steps([
        'Press [R], [O] or [G] for rectangle, ellipse or polygon, then drag on '
            'the canvas.',
        'Or press [P] for the pen: click to drop an anchor, or press-and-drag '
            'to pull a curve out of it.',
        'Close a pen path by clicking its first anchor again. [Esc] or [Enter] '
            'finishes it instead, leaving it open.',
        'Press [V] to go back to Select. The new layer is already selected and '
            'listed in Layers.',
      ]),
      const SizedBox(height: 16),
      const _Callout(
        icon: Icons.tune,
        title: 'Shapes stay editable',
        body: 'A rectangle, ellipse or polygon keeps its recipe: the Shape '
            'section of the inspector re-edits Width, Radius, Sides or Corner '
            'radius long after you drew it, and the outline is rebuilt from '
            'those numbers.',
      ),
    ],
  ),
  (
    title: 'Select and reshape',
    icon: Icons.near_me_outlined,
    blurb: 'Two selection tools: one moves whole layers, the other moves the '
        'points inside them.',
    build: (context) => [
      const _Keys([
        ('V', 'Select — click a layer, drag to move it.'),
        ('A', 'Direct select — drag individual anchors and their handles.'),
        ('Alt-click', 'On an anchor with Direct select: corner ↔ smooth.'),
        ('Del', 'With Direct select and an anchor picked, removes the '
            'anchor. Otherwise deletes the selected layer(s).'),
        ('Cmd/Ctrl+D', 'Duplicate the selection as one undo step.'),
        ('Cmd/Ctrl+G', 'Group the selection.'),
        ('Cmd/Ctrl+Z', 'Undo. One edit — or one whole drag — is one step.'),
      ]),
      const SizedBox(height: 16),
      const _Callout(
        icon: Icons.pan_tool_outlined,
        title: 'Moving the camera never changes the document',
        body: 'Hold [Space] and drag to pan, [Cmd/Ctrl] + scroll to zoom at the '
            'cursor, [Cmd/Ctrl+0] to fit the artboard and [Cmd/Ctrl+1] for '
            '100%. None of it is undoable, because none of it is an edit.',
      ),
    ],
  ),
  (
    title: 'Your first keyframe',
    icon: Icons.diamond_outlined,
    blurb: 'Nothing animates until one property holds two values at two '
        'different times. That is all a keyframe is — a value, pinned to a '
        'moment.',
    build: (context) => [
      const _KeyframeDiagram(),
      const SizedBox(height: 20),
      const _Steps([
        'Select the layer — on the canvas with [V], or in Layers.',
        'Send the playhead to the start: press [Home], or drag the handle in '
            'the timeline ruler (the marker showing the time) all the way '
            'left.',
        'In the Inspector, click the ◇ beside the property you want to animate '
            '— say Position. It fills in: that is keyframe 1, holding the value '
            'the layer has right now. The panel switches to "Editing at 0.00 s".',
        'Now move the playhead to a LATER time — press [End], or drag the '
            'handle to, say, 0.50 s. Nothing else changes yet.',
        'With the playhead there, change the value: type a number in the field, '
            'click its ▲▼ steppers, or drag the shape on the canvas. That is '
            'keyframe 2 — written at the time the playhead is showing.',
        'Press [Enter] — or ▶ — to play it back. The shape moves between the '
            'two values you set.',
      ]),
      const SizedBox(height: 16),
      const _Callout(
        icon: Icons.science_outlined,
        title: 'Worked example — slide a square across',
        body: 'Draw a square with [R]. Press [Home]. Click the ◇ beside '
            'Position → one keyframe at 0.00 s. Press [End]. Type 300 into '
            'Position X → a second keyframe at 1.00 s. Press [Enter]. The '
            'square slides from where you drew it to x = 300 over one second. '
            'Every animation in this tool is that, repeated.',
      ),
      const SizedBox(height: 20),
      const _DiamondLegend(),
      const SizedBox(height: 16),
      const _Callout(
        icon: Icons.edit_outlined,
        title: 'Once a property has keys, the field edits the key',
        body: 'Typing into an animated field writes to the key under the '
            'playhead instead of the resting value — and the field always '
            'shows what the canvas is showing at that instant, so the number '
            'and the picture can never drift apart.',
      ),
      const SizedBox(height: 10),
      const _Callout(
        icon: Icons.timeline,
        title: 'Animating the outline itself',
        body: 'The ◇ in the Path section keys the whole shape. Key it once, '
            'then move the playhead and drag anchors with Direct select — '
            'every anchor edit lands on the key at the playhead, so the '
            'outline morphs instead of jumping.',
      ),
    ],
  ),
  (
    title: 'The timeline',
    icon: Icons.linear_scale,
    blurb: 'Every key in the document, one row per animated property. This is '
        'where timing and easing live.',
    build: (context) => [
      const _Steps([
        'Read the ruler: it is labelled in seconds, and the handle on it shows '
            'the exact time the playhead is on. Drag that handle to move '
            'through the animation.',
        'Click the ▸ on a layer row to expand it into one row per animated '
            'property.',
        'Drag a dot sideways to retime that key. Dropping it on top of its '
            'neighbour is refused and the dot springs back.',
        'Click the span between two dots to set that segment\'s easing — '
            'Linear, Hold, Ease, Ease In / Out / In-Out, Back In / Out.',
        'Click a dot to select its row, then use the row keys below.',
      ]),
      const SizedBox(height: 16),
      const _Keys([
        (', / .', 'Jump to the previous / next key on the selected row.'),
        ('K', 'Key the selected property at the playhead, with the value it '
            'already has (a hold).'),
        ('Shift+K', 'Delete the key under the playhead.'),
        ('Home / End', 'Send the playhead to the start / end.'),
      ]),
      const SizedBox(height: 16),
      const _Callout(
        icon: Icons.drag_handle,
        title: 'Make the timeline taller',
        body: 'Drag the grip on the timeline\'s top edge to resize it — enough '
            'room for several layers at once. Double-click the grip to snap it '
            'back to the default height.',
      ),
    ],
  ),
  (
    title: 'Colour and draw-on',
    icon: Icons.palette_outlined,
    blurb: 'Fill, stroke and trim. All of it animates the same way the '
        'transform does.',
    build: (context) => [
      const _Bullets([
        (
          'Fill',
          'Add fill, then set the colour by swatch or by typing #RRGGBB, plus '
              'opacity and the winding rule for self-intersecting outlines.'
        ),
        (
          'Stroke',
          'Width, cap, join, miter limit, colour and opacity — each with its '
              'own ◇, so a colour or a width can animate on its own.'
        ),
        (
          'Trim',
          'Start, End and Offset are percentages of the outline\'s length. '
              'They reveal a path the way a pen draws it.'
        ),
      ]),
      const SizedBox(height: 16),
      const _Callout(
        icon: Icons.gesture,
        title: 'The classic draw-on, in two keys',
        body: 'Key Trim End at 0% at the start of the animation, move the '
            'playhead to the end, and set it to 100%. The stroke draws itself '
            'on. Animating Offset instead makes a dash chase around the shape.',
      ),
    ],
  ),
  (
    title: 'Play, save, export',
    icon: Icons.play_circle_outline,
    blurb: 'Playback is a preview of the real thing — the same evaluator the '
        'exported file describes.',
    build: (context) => [
      const _Bullets([
        (
          'Transport',
          '▶ / [Enter] plays and pauses, the loop selector picks once / loop / '
              'ping-pong, and duration is in seconds.'
        ),
        (
          'Duration retimes everything',
          'Keys are stored as a fraction of the animation, not as frames, so '
              'changing the duration speeds the whole thing up or slows it '
              'down without touching a single key.'
        ),
        (
          'Saving',
          'Automatic. The indicator in the top bar reads Saved, Unsaved, '
              'Saving… or Save failed — and a failed save keeps your work in '
              'memory and retries, it never rolls an edit back.'
        ),
        (
          'Export .json',
          'Downloads the document in the editor\'s own format — the same bytes '
              'it saves, so re-opening the file gives you exactly this project '
              'back.'
        ),
      ]),
    ],
  ),
  (
    title: 'All shortcuts',
    icon: Icons.keyboard_outlined,
    blurb: 'Figma and After Effects conventions, so most of these are already '
        'in your fingers.',
    build: (context) => [
      const _KeySection('Tools', [
        ('V', 'Select'),
        ('A', 'Direct select'),
        ('P', 'Pen'),
        ('R / O / G', 'Rectangle / Ellipse / Polygon'),
        ('Esc', 'Finish the pen path, or deselect'),
      ]),
      const _KeySection('Edit', [
        ('Cmd/Ctrl+Z', 'Undo'),
        ('Cmd/Ctrl+Shift+Z', 'Redo'),
        ('Cmd/Ctrl+D', 'Duplicate'),
        ('Cmd/Ctrl+G', 'Group'),
        ('Del / Backspace',
            'Delete selected anchors (Direct select), else selected layers'),
      ]),
      const _KeySection('View', [
        ('Space + drag', 'Pan'),
        ('Cmd/Ctrl + scroll', 'Zoom at the cursor'),
        ('Cmd/Ctrl + / -', 'Zoom in / out'),
        ('Cmd/Ctrl+0', 'Fit the artboard'),
        ('Cmd/Ctrl+1', 'Zoom to 100%'),
      ]),
      const _KeySection('Animation', [
        ('Enter', 'Play / pause (with the canvas unfocused)'),
        ('Home / End', 'Playhead to the start / end'),
        (', / .', 'Previous / next key on the selected row'),
        ('K', 'Key the selected property at the playhead'),
        ('Shift+K', 'Delete the key under the playhead'),
        ('↑ / ↓', 'Step a number field (Shift ×10, Alt ÷10)'),
      ]),
      const _KeySection('Help', [
        ('F1', 'Open this guide'),
      ]),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Content blocks
// ---------------------------------------------------------------------------

/// A numbered instruction list — the shape every "how do I…" answer takes.
class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primaryContainer,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _richLine(context, steps[i])),
              ],
            ),
          ),
      ],
    );
  }
}

/// A term and what it is — used where the reader is orienting rather than
/// following a sequence.
class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (term, body) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  term,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                _richLine(context, body),
              ],
            ),
          ),
      ],
    );
  }
}

/// A key and what it does.
class _Keys extends StatelessWidget {
  const _Keys(this.rows);

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (key, body) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: Wrap(children: [_KeyCap(key)]),
                ),
                const SizedBox(width: 10),
                Expanded(child: _richLine(context, body)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A titled group of key rows, for the reference chapter.
class _KeySection extends StatelessWidget {
  const _KeySection(this.title, this.rows);

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          _Keys(rows),
        ],
      ),
    );
  }
}

/// A tinted aside — the "and here is the thing nobody guesses" box.
class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                _richLine(context, body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// **What two keyframes look like**, as a picture of one property row.
///
/// The chapter's text said "change the value at another time" and readers still
/// asked how — because the sentence describes a *shape* (one row, two moments,
/// two values) that prose makes you assemble in your head. Twenty lines of
/// boxes and a line make it something you recognise on the real timeline.
class _KeyframeDiagram extends StatelessWidget {
  const _KeyframeDiagram();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget moment(String time, String value, Alignment align) => Column(
          crossAxisAlignment: align == Alignment.centerLeft
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Text(time,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                )),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ],
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text('position',
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
              ),
              Expanded(
                child: SizedBox(
                  height: 18,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(height: 1, color: scheme.outlineVariant),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _Dot(color: scheme.primary),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _Dot(color: scheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                moment('0.00 s', 'X 0', Alignment.centerLeft),
                moment('1.00 s', 'X 300', Alignment.centerRight),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Two keys on one row. The editor fills in every frame between them '
            '— you only ever set the ends.',
            style: TextStyle(
                fontSize: 10, height: 1.4, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// The three diamond states, drawn the way the inspector draws them.
///
/// A copy of the inspector's painter rather than an import: a feature may not
/// reach into a sibling feature (docs/v3/08 §3), and eleven pixels of geometry
/// is a cheaper duplicate than the coupling would be.
class _DiamondLegend extends StatelessWidget {
  const _DiamondLegend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const rows = <(int, String, String)>[
      (0, 'Not animated', 'Click it to write the first key at the playhead.'),
      (
        2,
        'On a key',
        'The playhead sits exactly on a key. Click it to delete that key.'
      ),
      (
        1,
        'Between keys',
        'Animated, but the playhead is between keys. Click it to hold the '
            'current value with a new key here.'
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT THE DIAMOND IS TELLING YOU',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          for (final (state, title, body) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: CustomPaint(
                      size: const Size(12, 12),
                      painter: _GuideDiamondPainter(
                        state: state,
                        on: scheme.primary,
                        idle: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _richLine(context, body),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 0 = empty (untracked), 1 = outlined (tracked, between keys), 2 = filled (on
/// a key) — the inspector's three states, in its own order of drawing.
class _GuideDiamondPainter extends CustomPainter {
  _GuideDiamondPainter(
      {required this.state, required this.on, required this.idle});

  final int state;
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
      case 2:
        canvas.drawPath(path, Paint()..color = on);
      case 1:
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = on);
      default:
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = idle);
    }
  }

  @override
  bool shouldRepaint(_GuideDiamondPainter old) =>
      old.state != state || old.on != on || old.idle != idle;
}

/// A map of the editor, in the editor's own proportions.
class _LayoutMap extends StatelessWidget {
  const _LayoutMap();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 176,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _MapBox(label: 'Tools', width: 34, scheme: scheme),
                _MapBox(label: 'Layers', flex: 3, scheme: scheme),
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      _MapBox(label: 'Canvas', flex: 4, accent: true,
                          scheme: scheme),
                      _MapBox(label: 'Transport', height: 26, scheme: scheme),
                    ],
                  ),
                ),
                _MapBox(label: 'Inspector', flex: 3, accent: true,
                    scheme: scheme),
              ],
            ),
          ),
          _MapBox(label: 'Timeline', height: 44, accent: true, scheme: scheme),
        ],
      ),
    );
  }
}

class _MapBox extends StatelessWidget {
  const _MapBox({
    required this.label,
    required this.scheme,
    this.flex = 1,
    this.width,
    this.height,
    this.accent = false,
  });

  final String label;
  final ColorScheme scheme;
  final int flex;
  final double? width;
  final double? height;

  /// The three panels the guide keeps sending the reader back to.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      margin: const EdgeInsets.all(2),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: accent ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: accent ? scheme.primary : scheme.outlineVariant, width: 1),
      ),
      child: FittedBox(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
            color:
                accent ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (width != null || height != null) return box;
    return Expanded(flex: flex, child: box);
  }
}

// ---------------------------------------------------------------------------
// Inline key caps
// ---------------------------------------------------------------------------

/// Body text where `[Cmd/Ctrl+Z]` renders as a key cap.
///
/// A two-token split rather than a markdown dependency: the guide is prose with
/// keys in it, and a parser that can only do one thing cannot mis-render the
/// rest of the sentence.
Widget _richLine(BuildContext context, String text) {
  final scheme = Theme.of(context).colorScheme;
  final style = TextStyle(
      fontSize: 12, height: 1.5, color: scheme.onSurfaceVariant);
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'\[([^\]]+)\]');
  var at = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > at) {
      spans.add(TextSpan(text: text.substring(at, match.start)));
    }
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _KeyCap(match.group(1)!),
    ));
    at = match.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return Text.rich(TextSpan(style: style, children: spans));
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
