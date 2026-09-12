import 'package:anim_core/anim_core.dart' show Rgba;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'color_picker.dart';

/// A colour control: a **swatch that opens an HSV picker** beside a hex field
/// that commits on **submit or blur** and **releases focus on commit** —
/// `CommittedNumberField`'s twin for [Rgba] (docs/v3/05 §5).
///
/// Lives in `common/` because the inspector's fill and stroke rows both need it
/// and neither owns it; `common/` may not import a feature (docs/v3/08 §3), so
/// this file imports only Flutter, [ColorPickerSurface] beside it, and the one
/// domain value type it edits.
///
/// **Why both a picker and a hex field.** AC-5.1.1 is "a colour is picked", and
/// picking is what a saturation square and a hue rail are for: you cannot type
/// your way to the orange that *looks* right, you drag to it with the canvas
/// updating underneath. The hex field stays because the other half of colour
/// authoring is exactness — pasting a brand code, or reading back what is in
/// force — which no picker does well. Neither replaces the other, and the hex
/// field is also the half that is *testable* without pixel-probing a gradient.
///
/// **Why release focus on commit.** `Cmd/Ctrl+Z` is interceptable, but while a
/// DOM `<input>` holds focus it hits the *browser's text-field undo* instead of
/// the editor's (docs/v3/05 §5). A colour field that keeps focus after Enter
/// turns the very next undo into a character delete.
///
/// **Straight (non-premultiplied) sRGB, 0..1** — [Rgba]'s contract
/// (docs/v3/01 §2). `#RRGGBB` leaves the current alpha alone; `#RRGGBBAA` sets
/// it. Six digits preserving alpha is what makes pasting a brand hex safe: the
/// alternative silently re-opaques a colour the user deliberately made
/// translucent.
class CommittedColorField extends StatefulWidget {
  const CommittedColorField({
    required this.value,
    required this.onCommit,
    this.label,
    this.enabled = true,
    this.onPickStart,
    this.onPickEnd,
    super.key,
  });

  final Rgba value;

  /// Called once per commit, only when the typed colour actually differs from
  /// the one in force — so an Enter-without-change writes no command and leaves
  /// no empty undo entry.
  final ValueChanged<Rgba> onCommit;

  final String? label;
  final bool enabled;

  /// Bracket a picker drag so its stream of [onCommit] calls collapses into one
  /// undo entry and one save — see [ColorPickerSurface.onPickStart]. Optional,
  /// because a host with no coalescing span still gets a working picker; it
  /// just gets an undo entry per frame of the drag.
  final VoidCallback? onPickStart;
  final VoidCallback? onPickEnd;

  @override
  State<CommittedColorField> createState() => _CommittedColorFieldState();
}

class _CommittedColorFieldState extends State<CommittedColorField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  late final FocusNode _focus = FocusNode(debugLabel: 'color-field');

  @override
  void initState() {
    super.initState();
    // Blur is a commit: losing focus (a click on the canvas, a tab away)
    // settles whatever was typed, exactly as pressing Enter would. Committing
    // only on Enter leaves the field showing a colour the document does not
    // have, which is the drift that makes an inspector feel broken.
    _focus.addListener(_onFocusChange);
  }

  /// The colour this field has already handed to [CommittedColorField.onCommit]
  /// but which the document has not echoed back yet.
  ///
  /// Without it the Enter path commits **twice**: `onSubmitted` commits and then
  /// calls `unfocus()`, which fires the blur listener while the command is still
  /// in flight — so `widget.value` is still the *old* colour, the blur sees a
  /// difference, and issues the same edit again. Two commands, two undo entries,
  /// one keystroke, and undo appearing to do nothing on the first press. This is
  /// the bug that was already found and fixed once in `CommittedNumberField`;
  /// the same shape of state is the same fix.
  Rgba? _pending;

  Rgba get _effectiveValue => _pending ?? widget.value;

  /// The picker popover, and the link that keeps it pinned to the swatch while
  /// the inspector scrolls under it.
  ///
  /// **An `OverlayEntry`, not an `OverlayPortal`.** A portal's overlay child is
  /// still a *descendant element* of the field, so an open picker would land
  /// inside every `find.descendant(of: byKey('inspector-fill-color'))` — and
  /// inside the field's own focus scope, where its taps would fight the text
  /// field's blur-commit. An entry is a sibling of the app, which is what a
  /// popover actually is.
  final LayerLink _link = LayerLink();
  OverlayEntry? _picker;

  @override
  void didUpdateWidget(CommittedColorField old) {
    super.didUpdateWidget(old);
    // Adopt an externally changed value — undo/redo, selecting a different node
    // — but only while unfocused, so it never yanks the text out mid-type.
    if (widget.value != old.value) {
      _pending = null; // the document caught up (or moved somewhere else)
      if (!_focus.hasFocus) _controller.text = _format(widget.value);
      // The entry builds from `_effectiveValue`; nothing rebuilds an overlay
      // for us, so an undo taken with the picker open must be pushed into it.
      //
      // **Post-frame, not now.** `didUpdateWidget` runs *during* the build
      // phase, and an overlay entry is not a descendant of this element — the
      // framework has already decided whether to visit it, so marking it here
      // trips `setState() called during build`. One frame of latency on an
      // echo the picker has usually already drawn itself is the cheap side of
      // that trade.
      _schedulePickerRebuild();
    }
  }

  @override
  void dispose() {
    // Before anything else: an entry outlives its field, so a node deselected
    // with the picker open would leave a popover floating over the editor with
    // no owner to close it.
    _removePicker();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  // --- The picker popover ----------------------------------------------------

  void _togglePicker() {
    if (_picker != null) {
      _removePicker();
      setState(() {});
      return;
    }
    // Committing first means a half-typed hex is settled (or reverted) before
    // the picker takes over as the authority, rather than being flushed on top
    // of the picked colour when the field later blurs.
    if (_focus.hasFocus) _commit(releaseFocus: true);

    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (box == null || !box.hasSize || overlay == null) return;

    // Flip above the field when there is no room below, and slide left when the
    // popover would run off the right edge — the inspector is the *right* rail,
    // so unshifted it always would.
    final overlaySize =
        (overlay.context.findRenderObject() as RenderBox?)?.size ??
            MediaQuery.sizeOf(context);
    final origin = box.localToGlobal(Offset.zero);
    final below = origin.dy + box.size.height + _kGap + _kPickerHeight <=
        overlaySize.height;
    final overflowRight =
        (origin.dx + _kPickerWidth) - (overlaySize.width - _kGap);
    final dx = overflowRight > 0 ? -overflowRight : 0.0;
    final offset = Offset(dx, below ? box.size.height + _kGap : -_kGap);

    _picker = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // The dismiss barrier: invisible, full-bleed, and *behind* the
          // popover in paint order so it never eats the picker's own pointers.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closePickerFromOverlay,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: below ? Alignment.bottomLeft : Alignment.topLeft,
            followerAnchor: below ? Alignment.topLeft : Alignment.bottomLeft,
            offset: offset,
            // The card is the follower's ONLY child and sizes itself: an
            // `Align` (or anything else that takes the Stack's loose
            // constraints at face value) makes the follower overlay-sized, and
            // then `followerAnchor: bottomLeft` hangs a full-screen box off the
            // anchor and parks the card hundreds of pixels off-screen.
            child: _pickerCard(context),
          ),
        ],
      ),
    );
    overlay.insert(_picker!);
    setState(() {}); // the swatch draws itself as pressed while open
  }

  /// The barrier's close path. It runs during the overlay's build/gesture pass,
  /// where a `setState` on *this* element is legal but the entry removal is
  /// what actually matters; the frame it schedules repaints the swatch.
  void _closePickerFromOverlay() {
    _removePicker();
    if (mounted) setState(() {});
  }

  void _schedulePickerRebuild() {
    if (_picker == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _picker?.markNeedsBuild();
    });
  }

  void _removePicker() {
    _picker?.remove();
    _picker?.dispose();
    _picker = null;
  }

  Widget _pickerCard(BuildContext overlayContext) {
    // The field's own theme, not the overlay's: the root overlay sits above
    // `MaterialApp`'s theme, so a picker built from `overlayContext` alone
    // would render light chrome in a dark editor.
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: _kPickerWidth,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ColorPickerSurface(
          key: const Key('color-picker'),
          width: _kPickerWidth - 24,
          value: _effectiveValue,
          onPickStart: widget.onPickStart,
          onPickEnd: widget.onPickEnd,
          onChanged: (next) {
            // Same guard the typed path uses: quantized compare, so a drag that
            // re-lands on the colour already in force writes no command.
            if (_quantize(next) == _quantize(_effectiveValue)) return;
            setState(() => _pending = next);
            _controller.text = _format(next);
            widget.onCommit(next);
          },
        ),
      ),
    );
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit(releaseFocus: false);
  }

  /// Parse, and either commit the new colour or revert to the last good one.
  ///
  /// [releaseFocus] is true only on the Enter path — a blur commit has already
  /// lost focus, and calling `unfocus()` again from inside a focus-change
  /// callback would re-enter the listener.
  void _commit({required bool releaseFocus}) {
    final parsed = _parse(_controller.text, _effectiveValue);
    // Compared against the **quantized** current value, not the raw one: this
    // field is 8 bits per channel, so a colour authored at 0.3333 by a newer
    // client displays as `#55…` and would otherwise be rewritten to 0.3333…
    // the moment anyone so much as tabbed through the field. An inspector that
    // edits a value because you looked at it is worse than one that cannot edit
    // it at all — and it would leave an undo entry to prove it.
    if (parsed == null || parsed == _quantize(_effectiveValue)) {
      _controller.text = _format(_effectiveValue);
    } else {
      _pending = parsed;
      widget.onCommit(parsed);
    }
    if (releaseFocus) _focus.unfocus();
  }

  /// `#RRGGBB`, or `#RRGGBBAA` when the colour is translucent — showing eight
  /// digits unconditionally makes every opaque colour look like it has a
  /// setting the user did not choose.
  static String _format(Rgba c) {
    final rgb = '${_hex(c.r)}${_hex(c.g)}${_hex(c.b)}';
    return c.a >= 1.0 ? '#$rgb' : '#$rgb${_hex(c.a)}';
  }

  static String _hex(double v) =>
      _byte(v).toRadixString(16).padLeft(2, '0').toUpperCase();

  /// Total: a NaN or infinite channel from a malformed document renders as 0
  /// rather than throwing out of a `build`.
  static int _byte(double v) =>
      v.isFinite ? (v.clamp(0.0, 1.0) * 255).round() : 0;

  static Rgba _quantize(Rgba c) => Rgba(
        _byte(c.r) / 255,
        _byte(c.g) / 255,
        _byte(c.b) / 255,
        _byte(c.a) / 255,
      );

  /// **Total parse, never a throw.** Anything unusable returns null and the
  /// field reverts, rather than writing NaN into a paint the evaluator is
  /// forbidden to rescue (docs/v3/08 §1).
  static Rgba? _parse(String raw, Rgba current) {
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length != 6 && s.length != 8) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) return null;
    double channel(int index) =>
        int.parse(s.substring(index * 2, index * 2 + 2), radix: 16) / 255;
    return Rgba(
      channel(0),
      channel(1),
      channel(2),
      // Six digits keep the alpha in force, quantized so that retyping the
      // displayed text is recognised as "no change" above.
      s.length == 8 ? channel(3) : _byte(current.a) / 255,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _effectiveValue;
    final open = _picker != null;
    return Row(
      children: [
        // The swatch is the picker's button — the affordance every colour UI
        // already trained the user to click — and its own preview.
        CompositedTransformTarget(
          link: _link,
          child: Semantics(
            button: true,
            label: 'Pick colour',
            child: MouseRegion(
              cursor: widget.enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                key: const Key('color-swatch'),
                onTap: widget.enabled ? _togglePicker : null,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: open ? scheme.primary : scheme.outlineVariant,
                      width: open ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    // Chequer under the colour, so a translucent fill reads as
                    // translucent instead of as a slightly pale opaque one.
                    child: CustomPaint(
                      painter: _SwatchPainter(
                        // `Rgba` is straight, non-premultiplied sRGB and so is
                        // `Color.fromARGB` — no conversion, and no place for
                        // one to be forgotten.
                        color: Color.fromARGB(
                          _byte(shown.a),
                          _byte(shown.r),
                          _byte(shown.g),
                          _byte(shown.b),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            // Permissive keystrokes, real validation at commit — an over-strict
            // formatter that rejects a partial code blocks typing one at all.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
              LengthLimitingTextInputFormatter(9),
            ],
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              labelText: widget.label,
              labelStyle: const TextStyle(fontSize: 11),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: scheme.surface,
            ),
            onSubmitted: (_) => _commit(releaseFocus: true),
          ),
        ),
      ],
    );
  }
}

/// Popover geometry. The width is the inspector rail's (260) less its padding,
/// so the card reads as an extension of the panel rather than a floating box;
/// the height is only used to decide whether it opens downward, so an estimate
/// a few pixels out costs nothing.
const double _kPickerWidth = 252;
const double _kPickerHeight = 300;
const double _kGap = 6;

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    paintCheckerboard(canvas, rect, cell: 5);
    canvas.drawRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color;
}
