import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' show Rgba;
import 'package:flutter/material.dart';

/// The HSV picking surface behind every colour swatch — saturation/value square,
/// hue rail, alpha rail and a preset row (F5.1, AC-5.1.1).
///
/// Lives in `common/` beside [CommittedColorField], which is its only host: the
/// inspector's fill and stroke rows both need it and neither owns it, and
/// `common/` may not import a feature (docs/v3/08 §3). So this file imports
/// Flutter and the one domain value type it edits, and nothing else.
///
/// **Why HSV state of its own, rather than deriving it from [value] each
/// build.** Hue and saturation are *unrecoverable* from an RGB triple at the
/// edges: black is `(0,0,0)` whatever hue produced it, and so is every fully
/// desaturated grey. A surface that re-derived HSV from the committed colour
/// would snap the hue cursor back to red the moment a drag reached the bottom
/// of the square — the classic picker bug. The HSV here is therefore the
/// authority while the user is on it, and re-syncs from [value] only when the
/// document moves underneath (undo, a different node, a hex paste).
///
/// **Straight (non-premultiplied) sRGB, 0..1** — [Rgba]'s contract
/// (docs/v3/01 §2), and the alpha rail edits `a` in place, so picking a colour
/// never silently re-opaques one the user deliberately made translucent.
class ColorPickerSurface extends StatefulWidget {
  const ColorPickerSurface({
    required this.value,
    required this.onChanged,
    this.onPickStart,
    this.onPickEnd,
    this.width = 228,
    super.key,
  });

  final Rgba value;

  /// Fired **live** during a drag, once per pointer event that actually moves
  /// the quantized colour — the canvas updating under the thumb is the whole
  /// reason to have a picker rather than a hex box.
  final ValueChanged<Rgba> onChanged;

  /// Bracket one drag (or one preset tap) so its stream of [onChanged] calls
  /// collapses into a single undo entry and a single save — the same coalescing
  /// span the number field's steppers open (docs/v3/04 §6). Without it a
  /// two-second drag across the square is ~120 presses of `Cmd+Z` to reverse.
  final VoidCallback? onPickStart;
  final VoidCallback? onPickEnd;

  final double width;

  @override
  State<ColorPickerSurface> createState() => _ColorPickerSurfaceState();
}

class _ColorPickerSurfaceState extends State<ColorPickerSurface> {
  static const double _squareHeight = 150;
  static const double _railHeight = 16;

  late _Hsva _hsva = _Hsva.fromRgba(widget.value);

  @override
  void didUpdateWidget(ColorPickerSurface old) {
    super.didUpdateWidget(old);
    // Adopt an external change, but only a *real* one: `_hsva.toRgba()` is what
    // this surface last emitted, so comparing against it (at 8-bit precision,
    // the precision the whole colour UI shows) means a drag never fights the
    // document's echo of its own edit and the cursor never jitters.
    if (!_sameColor(widget.value, _hsva.toRgba())) {
      _hsva = _Hsva.fromRgba(widget.value);
    }
  }

  static bool _sameColor(Rgba x, Rgba y) =>
      _byte(x.r) == _byte(y.r) &&
      _byte(x.g) == _byte(y.g) &&
      _byte(x.b) == _byte(y.b) &&
      _byte(x.a) == _byte(y.a);

  /// Total: a NaN or infinite channel from a malformed document reads as 0
  /// rather than throwing out of a `build` or a painter.
  static int _byte(double v) =>
      v.isFinite ? (v.clamp(0.0, 1.0) * 255).round() : 0;

  void _emit(_Hsva next) {
    final before = _hsva.toRgba();
    setState(() => _hsva = next);
    final after = next.toRgba();
    // Only when the committed colour actually moves: a pointer wobble inside one
    // 1/255 cell would otherwise write a command per frame that changes nothing.
    if (!_sameColor(before, after)) widget.onChanged(after);
  }

  /// A preset is a whole gesture in one tap — open the span, write, close it —
  /// so it lands as exactly one undo entry, like a drag does.
  void _pickPreset(Color preset) {
    widget.onPickStart?.call();
    _emit(_Hsva.fromRgba(
      Rgba(preset.r, preset.g, preset.b, _hsva.a), // alpha survives a preset
    ));
    widget.onPickEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = widget.width;
    final rgba = _hsva.toRgba();
    final color = _toColor(rgba);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DragSurface(
          key: const Key('color-picker-sv'),
          onStart: widget.onPickStart,
          onEnd: widget.onPickEnd,
          onPoint: (local, size) => _emit(_hsva.copyWith(
            s: (local.dx / size.width).clamp(0.0, 1.0),
            v: 1 - (local.dy / size.height).clamp(0.0, 1.0),
          )),
          child: CustomPaint(
            size: Size(w, _squareHeight),
            painter: _SvSquarePainter(
              hue: _hsva.h,
              s: _hsva.s,
              v: _hsva.v,
              outline: scheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _DragSurface(
          key: const Key('color-picker-hue'),
          onStart: widget.onPickStart,
          onEnd: widget.onPickEnd,
          onPoint: (local, size) => _emit(_hsva.copyWith(
            h: (local.dx / size.width).clamp(0.0, 1.0) * 360,
          )),
          child: CustomPaint(
            size: Size(w, _railHeight),
            painter: _HueRailPainter(
              hue: _hsva.h,
              outline: scheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _DragSurface(
          key: const Key('color-picker-alpha'),
          onStart: widget.onPickStart,
          onEnd: widget.onPickEnd,
          onPoint: (local, size) => _emit(_hsva.copyWith(
            a: (local.dx / size.width).clamp(0.0, 1.0),
          )),
          child: CustomPaint(
            size: Size(w, _railHeight),
            painter: _AlphaRailPainter(
              color: color,
              alpha: _hsva.a,
              outline: scheme.outlineVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: w,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, preset) in _presets.indexed)
                _PresetSwatch(
                  key: Key('color-preset-$i'),
                  color: preset,
                  selected: _sameColor(
                      Rgba(preset.r, preset.g, preset.b, rgba.a), rgba),
                  onTap: () => _pickPreset(preset),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Greys first, then one row of hues — a starting point, not a palette the
/// document knows about.
const List<Color> _presets = [
  Color(0xFF000000),
  Color(0xFF444444),
  Color(0xFF888888),
  Color(0xFFCCCCCC),
  Color(0xFFFFFFFF),
  Color(0xFF8D6E63),
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF00ACC1),
  Color(0xFF1E88E5),
  Color(0xFF5E35B1),
  Color(0xFFD81B60),
];

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// Pointer plumbing for the three rails, in one place.
///
/// **A raw [Listener], not a [GestureDetector].** The square and the rails want
/// "wherever the finger is, right now, from the instant it lands" — there is no
/// tap-versus-drag question to arbitrate, and routing them through the gesture
/// arena would cost a drag its first frames while a competing recognizer (the
/// panel's scrollable, the overlay's dismiss tap) decided to lose.
class _DragSurface extends StatefulWidget {
  const _DragSurface({
    required this.onPoint,
    required this.child,
    this.onStart,
    this.onEnd,
    super.key,
  });

  final void Function(Offset local, Size size) onPoint;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;
  final Widget child;

  @override
  State<_DragSurface> createState() => _DragSurfaceState();
}

class _DragSurfaceState extends State<_DragSurface> {
  int? _pointer;

  void _report(Offset local) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onPoint(local, box.size);
  }

  @override
  void dispose() {
    // A surface torn down mid-drag (the popover closing under the finger, the
    // node being deselected) must still close the coalescing span, or the
    // command stack keeps coalescing for the rest of the session.
    if (_pointer != null) widget.onEnd?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return; // ignore a second finger
          _pointer = e.pointer;
          widget.onStart?.call();
          _report(e.localPosition);
        },
        onPointerMove: (e) {
          if (e.pointer != _pointer) return;
          _report(e.localPosition);
        },
        onPointerUp: (e) => _release(e.pointer),
        onPointerCancel: (e) => _release(e.pointer),
        child: widget.child,
      );

  void _release(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    widget.onEnd?.call();
  }
}

// --- Painters ---------------------------------------------------------------

class _SvSquarePainter extends CustomPainter {
  const _SvSquarePainter({
    required this.hue,
    required this.s,
    required this.v,
    required this.outline,
  });

  final double hue;
  final double s;
  final double v;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(rrect);
    // White → the pure hue across, then transparent → black down. Two gradients
    // is the whole of an HSV square; there is no third.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, _toColor(_Hsva(hue, 1, 1, 1).toRgba())],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
    canvas.restore();
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = outline);
    _cursor(canvas, Offset(s * size.width, (1 - v) * size.height));
  }

  /// A white ring inside a black one, so the cursor stays visible over both the
  /// white corner and the black edge without a luminance test.
  static void _cursor(Canvas canvas, Offset at) {
    canvas.drawCircle(
        at,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
    canvas.drawCircle(
        at,
        7.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_SvSquarePainter old) =>
      old.hue != hue || old.s != s || old.v != v || old.outline != outline;
}

class _HueRailPainter extends CustomPainter {
  const _HueRailPainter({required this.hue, required this.outline});

  final double hue;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            for (var i = 0; i <= 6; i++)
              _toColor(_Hsva(i * 60.0, 1, 1, 1).toRgba()),
          ],
        ).createShader(rect),
    );
    canvas.restore();
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = outline);
    _thumb(canvas, size, (hue % 360) / 360);
  }

  @override
  bool shouldRepaint(_HueRailPainter old) =>
      old.hue != hue || old.outline != outline;
}

class _AlphaRailPainter extends CustomPainter {
  const _AlphaRailPainter({
    required this.color,
    required this.alpha,
    required this.outline,
  });

  final Color color;
  final double alpha;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(rrect);
    paintCheckerboard(canvas, rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 1)],
        ).createShader(rect),
    );
    canvas.restore();
    canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = outline);
    _thumb(canvas, size, alpha.clamp(0.0, 1.0));
  }

  @override
  bool shouldRepaint(_AlphaRailPainter old) =>
      old.color != color || old.alpha != alpha || old.outline != outline;
}

/// The shared rail thumb: a white capsule with a dark hairline, inset so it
/// cannot leave the rail at either end.
void _thumb(Canvas canvas, Size size, double t) {
  final r = size.height / 2;
  final x = r + t * (size.width - size.height);
  final rrect = RRect.fromRectAndRadius(
    Rect.fromCenter(
        center: Offset(x, r),
        width: size.height * 0.6,
        height: size.height + 4),
    Radius.circular(size.height * 0.3),
  );
  canvas.drawRRect(rrect, Paint()..color = Colors.white);
  canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black45);
}

/// The grey chequer behind anything translucent — without it a 0 %-alpha swatch
/// is indistinguishable from a white one, which is how a user "loses" a shape.
void paintCheckerboard(Canvas canvas, Rect rect, {double cell = 5}) {
  canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
  final dark = Paint()..color = const Color(0xFFCFCFCF);
  final cols = (rect.width / cell).ceil();
  final rows = (rect.height / cell).ceil();
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      if ((x + y).isEven) continue;
      canvas.drawRect(
        Rect.fromLTWH(rect.left + x * cell, rect.top + y * cell, cell, cell)
            .intersect(rect),
        dark,
      );
    }
  }
}

/// [Rgba] → a Flutter [Color]. Both are straight, non-premultiplied sRGB, so
/// there is no conversion and no place for one to be forgotten — only the
/// totality guard against a non-finite channel.
Color _toColor(Rgba c) => Color.fromARGB(
      _ColorPickerSurfaceState._byte(c.a),
      _ColorPickerSurfaceState._byte(c.r),
      _ColorPickerSurfaceState._byte(c.g),
      _ColorPickerSurfaceState._byte(c.b),
    );

/// Hue (0..360), saturation, value, alpha (each 0..1).
///
/// **Written out rather than using `HSVColor`.** Flutter's version round-trips
/// through an 8-bit `Color`, which loses the hue of a dark or desaturated
/// colour on every conversion — precisely the state this type exists to hold on
/// to between drag frames.
@immutable
class _Hsva {
  const _Hsva(this.h, this.s, this.v, this.a);

  final double h;
  final double s;
  final double v;
  final double a;

  _Hsva copyWith({double? h, double? s, double? v, double? a}) =>
      _Hsva(h ?? this.h, s ?? this.s, v ?? this.v, a ?? this.a);

  factory _Hsva.fromRgba(Rgba c) {
    double ch(double x) => x.isFinite ? x.clamp(0.0, 1.0) : 0.0;
    final r = ch(c.r), g = ch(c.g), b = ch(c.b);
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final d = max - min;
    double h;
    if (d == 0) {
      h = 0; // a grey has no hue to recover; red is the conventional stand-in
    } else if (max == r) {
      h = 60 * (((g - b) / d) % 6);
    } else if (max == g) {
      h = 60 * ((b - r) / d + 2);
    } else {
      h = 60 * ((r - g) / d + 4);
    }
    return _Hsva((h + 360) % 360, max == 0 ? 0 : d / max, max, ch(c.a));
  }

  Rgba toRgba() {
    final c = v * s;
    final hp = (h % 360) / 60;
    final x = c * (1 - ((hp % 2) - 1).abs());
    final m = v - c;
    final (double r, double g, double b) = switch (hp.floor()) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    return Rgba(r + m, g + m, b + m, a);
  }
}
