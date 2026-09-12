import 'dart:async';

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
/// **Why a stepper as well as a keyboard.** Typing is exact but blind: to find
/// the rotation that *looks* right you have to type, look, retype. A pair of
/// ▲▼ buttons that nudge by a known increment — and repeat while held — turns
/// that into one gesture with the canvas updating under it, which is how every
/// design tool with a numeric inspector behaves. [step] is opt-in per field
/// because the right increment is the caller's knowledge: 1° of rotation and
/// 0.01 of a scale factor are both "one nudge".
class CommittedNumberField extends StatefulWidget {
  const CommittedNumberField({
    required this.value,
    required this.onCommit,
    this.label,
    this.enabled = true,
    this.decimals = 3,
    this.step,
    this.min,
    this.max,
    this.onStepStart,
    this.onStepEnd,
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

  /// One nudge, in the field's display unit. **Null means no steppers** — the
  /// field renders exactly as it always did, so a caller with no sensible
  /// increment is not forced to invent one.
  ///
  /// `Shift` multiplies it by 10 and `Alt`/`Option` divides it by 10 — the
  /// Figma/Illustrator convention — so one increment covers three orders of
  /// magnitude without a second control.
  final double? step;

  /// Bounds for the **stepper only**. Typing stays total (a typed value commits
  /// and the op clamps it, docs/v3/08 §1), but a ▼ held at 0 % must sit still
  /// rather than emit a stream of commands the op would only clamp back.
  final double? min;
  final double? max;

  /// Called once when a press on a stepper begins, and once when it ends.
  ///
  /// The seam that lets a caller collapse a whole press-and-hold into **one**
  /// undo entry and one save (`DocumentController.beginGesture` /
  /// `commitGesture`) — the same coalescing a canvas drag gets. Optional:
  /// without them every nudge is its own entry, which is correct, just noisier
  /// to undo. A callback rather than a command because `common/` may not import
  /// a feature (docs/v3/08 §3).
  final VoidCallback? onStepStart;
  final VoidCallback? onStepEnd;

  @override
  State<CommittedNumberField> createState() => _CommittedNumberFieldState();
}

class _CommittedNumberFieldState extends State<CommittedNumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  /// `onKeyEvent` gives the focused field ↑/↓ stepping. It hangs off the node
  /// rather than an enclosing `Focus` so it sees the key before the editor's
  /// shortcut scope does, and it returns `ignored` for everything else —
  /// including the `Cmd/Ctrl+Z` that must keep bubbling to the shell.
  late final FocusNode _focus =
      FocusNode(debugLabel: 'number-field', onKeyEvent: _onKey);

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

  // --- Stepping (▲▼ and ↑↓) -------------------------------------------------

  /// True while a press is being coalesced by the caller. A *value*, not a
  /// latch that can disagree with anything: [_beginSpan] and [_endSpan] are its
  /// only writers and both are idempotent, so a second button pressed while the
  /// first is held cannot open a second span.
  bool _spanOpen = false;

  void _beginSpan() {
    if (_spanOpen) return;
    _spanOpen = true;
    widget.onStepStart?.call();
  }

  void _endSpan() {
    if (!_spanOpen) return;
    _spanOpen = false;
    widget.onStepEnd?.call();
  }

  /// Nudge by [direction] × [step] × the modifier scale, [boost] times over.
  ///
  /// **It steps from what is on screen, not from the last committed value.**
  /// Someone who types `40` and then presses ▲ means 41; snapping back to the
  /// committed 12 because the typed text was never submitted is the same drift
  /// commit-on-blur exists to prevent.
  ///
  /// The result is re-rendered at [CommittedNumberField.decimals] before it is
  /// committed, so repeated steps cannot accumulate binary dust — `0.1 + 0.2`
  /// has to land on `0.3`, not on `0.30000000000000004`, or the field starts
  /// showing a number nobody typed.
  void _stepBy(int direction, {int boost = 1}) {
    final step = widget.step;
    if (step == null || !widget.enabled) return;

    final base = _parse(_controller.text) ?? _effectiveValue;
    if (!base.isFinite) return;
    final delta = step * _modifierScale() * boost * direction;
    var next = double.parse((base + delta).toStringAsFixed(widget.decimals));
    final min = widget.min;
    final max = widget.max;
    if (min != null && next < min) next = min;
    if (max != null && next > max) next = max;

    if (next == _effectiveValue) {
      // Already there (a bound, or an unchanged value): keep the text honest
      // and emit nothing, so a held ▼ at 0 % is silent rather than a stream of
      // no-op commands.
      _controller.text = _format(next);
      return;
    }
    _pending = next;
    _controller.text = _format(next);
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    widget.onCommit(next);
  }

  /// `Shift` ×10, `Alt`/`Option` ÷10. Read from [HardwareKeyboard] at the moment
  /// of the step, so a modifier pressed *during* a hold takes effect on the very
  /// next repeat.
  static double _modifierScale() {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) return 10.0;
    if (keys.isAltPressed) return 0.1;
    return 1.0;
  }

  /// ↑/↓ while the field has focus. Each press is its own commit: a held *key*
  /// has no press/release pair to coalesce against, and the OS repeat rate is
  /// slow enough to leave the undo stack usable.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.step == null || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _stepBy(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _stepBy(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
    final steppers = widget.step == null ? null : _steppers(scheme);
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
        // The steppers sit INSIDE the field's own box, so a 260-px inspector
        // rail loses no column to them and an X/Y pair still fits side by side.
        // The right padding shrinks to meet them.
        contentPadding: EdgeInsets.only(
            left: 8, right: steppers == null ? 8 : 2, top: 8, bottom: 8),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: scheme.surface,
        suffixIcon: steppers,
        // Without this the decoration reserves Material's 48×48 icon slot and
        // the field grows to twice its height.
        suffixIconConstraints:
            const BoxConstraints(minWidth: 22, minHeight: 30, maxHeight: 34),
      ),
      onSubmitted: (_) => _commit(releaseFocus: true),
    );
  }

  Widget _steppers(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StepperButton(
            icon: Icons.keyboard_arrow_up,
            tooltip: 'Increase (Shift ×10, Alt ÷10)',
            semanticLabel: 'Increase',
            enabled: widget.enabled,
            onStep: (boost) => _stepBy(1, boost: boost),
            onPressStart: _beginSpan,
            onPressEnd: _endSpan,
            scheme: scheme,
          ),
          _StepperButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: 'Decrease (Shift ×10, Alt ÷10)',
            semanticLabel: 'Decrease',
            enabled: widget.enabled,
            onStep: (boost) => _stepBy(-1, boost: boost),
            onPressStart: _beginSpan,
            onPressEnd: _endSpan,
            scheme: scheme,
          ),
        ],
      ),
    );
  }
}

/// One arrow: a nudge on press, then auto-repeat while it is held.
///
/// **`Listener`, not `GestureDetector`, for the press.** A hold has to start
/// repeating *before* the pointer comes up, and a tap recognizer only reports a
/// press once the gesture arena has resolved. The nested empty
/// `GestureDetector` is the other half: it claims the tap so the `TextField`
/// underneath does not take focus while the user is only nudging — focus in a
/// DOM input is what hands the next `Cmd/Ctrl+Z` to the *browser's* undo
/// (docs/v3/05 §5).
///
/// **The span is closed by the pointer, never by `dispose`.** Calling back into
/// a provider from `dispose` is how a "ref used after disposal" crash gets
/// written; release is the only close, and `DocumentController` already commits
/// a span whose gesture never came back (its staleness guard), so an abandoned
/// one cannot wedge the stack.
class _StepperButton extends StatefulWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.enabled,
    required this.onStep,
    required this.onPressStart,
    required this.onPressEnd,
    required this.scheme,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final bool enabled;

  /// Called with the acceleration factor for this repeat (1, then 4 once the
  /// hold is clearly deliberate).
  final void Function(int boost) onStep;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final ColorScheme scheme;

  /// The pause before a press becomes a repeat — long enough that an ordinary
  /// click is never read as a hold.
  static const Duration pressDelay = Duration(milliseconds: 350);

  /// ~14 nudges a second while held.
  static const Duration repeatInterval = Duration(milliseconds: 70);

  /// After ~1.5 s of holding, one repeat is worth four nudges. Without it a
  /// 0.01 increment needs a forty-second hold to cross one unit and the user
  /// reaches for the keyboard instead — which is the affordance this button
  /// exists to replace.
  static const int accelerateAfter = 20;

  @override
  State<_StepperButton> createState() => _StepperButtonState();
}

class _StepperButtonState extends State<_StepperButton> {
  Timer? _delay;
  Timer? _repeat;
  bool _down = false;
  bool _hovered = false;
  int _repeats = 0;

  @override
  void dispose() {
    _delay?.cancel();
    _repeat?.cancel();
    super.dispose();
  }

  void _press() {
    if (!widget.enabled) return;
    setState(() => _down = true);
    _repeats = 0;
    widget.onPressStart();
    widget.onStep(1);
    _delay = Timer(_StepperButton.pressDelay, () {
      _repeat = Timer.periodic(_StepperButton.repeatInterval, (_) {
        _repeats++;
        widget.onStep(_repeats >= _StepperButton.accelerateAfter ? 4 : 1);
      });
    });
  }

  void _release() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
    if (!_down) return;
    setState(() => _down = false);
    widget.onPressEnd();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final Color colour;
    if (!widget.enabled) {
      colour = scheme.onSurfaceVariant.withValues(alpha: 0.38);
    } else if (_down) {
      colour = scheme.primary;
    } else if (_hovered) {
      colour = scheme.onSurface;
    } else {
      colour = scheme.onSurfaceVariant;
    }

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Listener(
            onPointerDown: (_) => _press(),
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // claims the tap; see the class doc
              child: Container(
                width: 18,
                height: 14,
                alignment: Alignment.center,
                color: _down && widget.enabled
                    ? scheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                child: Icon(widget.icon, size: 14, color: colour),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
