import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A numeric text field that commits on **submit or blur** and **releases focus
/// on commit** (docs/v3/08 §3's "buttons, number fields"; docs/v3/05 §5).
///
/// Lives in `common/` because both the inspector's transform rows and (later)
/// the paint/trim rows need it and neither owns it — `common/` may not import a
/// feature (docs/v3/08 §3), so this file imports only Flutter.
///
/// **Why release focus on commit.** `Cmd/Ctrl+Z` is interceptable, but while a
/// DOM `<input>` holds focus it hits the *browser's text-field undo*, not the
/// editor's (docs/v3/05 §5, §"Flutter Web browser conflicts"). A number field
/// that keeps focus after the user presses Enter turns the very next undo into a
/// character delete. So committing here always unfocuses; the editor's undo is
/// then the only undo the keystroke can reach.
///
/// **Why commit-on-blur as well as on-submit.** A user who types a value and
/// then clicks the canvas expects the value to take. Committing only on Enter
/// silently discards that edit — the field would show the new number while the
/// document still held the old one, the drift that makes an inspector feel
/// broken.
///
/// **Total parse, never a throw.** A non-numeric entry is *rejected* — the field
/// reverts to the last committed value — rather than writing NaN into a
/// `Transform2`, which would hand the evaluator a NaN it is forbidden to rescue
/// (docs/v3/08 §1). The parse is locale-tolerant: a comma decimal separator
/// (`1,5`) and grouping are accepted, because the app runs in the browser's
/// locale and a German keyboard types `,` for the decimal point.
class CommittedNumberField extends StatefulWidget {
  const CommittedNumberField({
    required this.value,
    required this.onCommit,
    this.label,
    this.enabled = true,
    this.decimals = 3,
    super.key,
  });

  /// The current value, in the field's own display unit (the inspector passes
  /// *degrees* for rotation and converts to radians in [onCommit]).
  final double value;

  /// Called once per commit with the parsed value — only when it actually
  /// differs from [value], so an Enter-without-change writes no command and
  /// leaves no empty undo entry.
  final ValueChanged<double> onCommit;

  final String? label;
  final bool enabled;

  /// Display precision. Trailing zeros are trimmed, so `1.0` shows as `1` and a
  /// keyed rotation of exactly 45° shows as `45`, not `45.000`.
  final int decimals;

  @override
  State<CommittedNumberField> createState() => _CommittedNumberFieldState();
}

class _CommittedNumberFieldState extends State<CommittedNumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  late final FocusNode _focus = FocusNode(debugLabel: 'number-field');

  @override
  void initState() {
    super.initState();
    // Blur is a commit: losing focus (a click on the canvas, a tab away) settles
    // whatever was typed, exactly as pressing Enter would.
    _focus.addListener(_onFocusChange);
  }

  /// The value this field has already handed to [CommittedNumberField.onCommit]
  /// but which the document has not echoed back yet.
  ///
  /// Without it the Enter path commits **twice**: `onSubmitted` commits and then
  /// calls `unfocus()`, which fires the blur listener while the command is still
  /// in flight — so `widget.value` is still the *old* number, the blur sees a
  /// difference, and issues the same edit again. That is two commands and two
  /// undo entries for one keystroke, and undo would then appear to do nothing on
  /// the first press. Comparing against [_effectiveValue] closes that window.
  double? _pending;

  double get _effectiveValue => _pending ?? widget.value;

  @override
  void didUpdateWidget(CommittedNumberField old) {
    super.didUpdateWidget(old);
    // Adopt an externally changed value — undo/redo, a gizmo drag, selecting a
    // different node — but only while unfocused, so it never yanks the text out
    // from under someone mid-type.
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

  /// Parse, and either commit the new value or revert to the last good one.
  ///
  /// [releaseFocus] is true only on the Enter path — a blur commit has already
  /// lost focus, and calling `unfocus()` again from inside a focus-change
  /// callback would re-enter the listener.
  void _commit({required bool releaseFocus}) {
    final parsed = _parse(_controller.text);
    if (parsed == null) {
      // Unusable: snap the text back to the canonical rendering of the value
      // that is actually in force. This is the "rejects non-numbers gracefully"
      // behaviour — no throw, no NaN into a `Transform2`, no red field.
      _controller.text = _format(_effectiveValue);
    } else if (parsed != _effectiveValue) {
      // Changed: one commit, one command, one undo entry.
      _pending = parsed;
      widget.onCommit(parsed);
    }
    if (releaseFocus) _focus.unfocus();
  }

  String _format(double v) {
    if (!v.isFinite) return '0';
    var s = v.toStringAsFixed(widget.decimals);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    // `-0` reads as a bug to a human; there is one zero.
    return s == '-0' ? '0' : s;
  }

  /// Locale-tolerant, total. Returns null on anything unparseable.
  static double? _parse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    // Accept a comma decimal separator when there is no dot (`1,5` -> `1.5`);
    // strip commas used as grouping when a dot is present (`1,000.5`).
    if (s.contains(',') && !s.contains('.')) {
      s = s.replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
    return double.tryParse(s);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      textAlign: TextAlign.right,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      // Keep the raw keystrokes permissive (a leading `-`, a lone `.` mid-type),
      // and do the real validation at commit — an over-strict formatter that
      // rejects `-` blocks typing a negative number at all.
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
      ],
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        labelStyle: const TextStyle(fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: scheme.surface,
      ),
      onSubmitted: (_) => _commit(releaseFocus: true),
    );
  }
}
