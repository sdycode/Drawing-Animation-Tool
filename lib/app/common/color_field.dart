import 'package:anim_core/anim_core.dart' show Rgba;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A hex colour field that commits on **submit or blur** and **releases focus on
/// commit** — `CommittedNumberField`'s twin for [Rgba] (docs/v3/05 §5).
///
/// Lives in `common/` because the inspector's fill and stroke rows both need it
/// and neither owns it; `common/` may not import a feature (docs/v3/08 §3), so
/// this file imports only Flutter and the one domain value type it edits.
///
/// **Why a hex field and not a picker.** The authoring surface v1 owes F5.1 is
/// "a colour is picked" (AC-5.1.1), and a wheel/saturation-square picker is a
/// week of hit-testing, gesture arithmetic and its own bug class for a control
/// every designer already has a hex code for. A text field is also the only
/// colour control that is *testable* without pixel-probing a gradient.
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
    super.key,
  });

  final Rgba value;

  /// Called once per commit, only when the typed colour actually differs from
  /// the one in force — so an Enter-without-change writes no command and leaves
  /// no empty undo entry.
  final ValueChanged<Rgba> onCommit;

  final String? label;
  final bool enabled;

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

  @override
  void didUpdateWidget(CommittedColorField old) {
    super.didUpdateWidget(old);
    // Adopt an externally changed value — undo/redo, selecting a different node
    // — but only while unfocused, so it never yanks the text out mid-type.
    if (widget.value != old.value) {
      _pending = null; // the document caught up (or moved somewhere else)
      if (!_focus.hasFocus) _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
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
    return Row(
      children: [
        // `Rgba` is straight, non-premultiplied sRGB and so is `Color.fromARGB`
        // — no conversion, and no place for one to be forgotten.
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Color.fromARGB(
              _byte(shown.a),
              _byte(shown.r),
              _byte(shown.g),
              _byte(shown.b),
            ),
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(3),
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
