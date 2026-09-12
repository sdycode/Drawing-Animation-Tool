import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What the editor says out loud — **one toast, one look**.
///
/// Lives in `common/` because every panel reports through it and none owns it
/// (docs/v3/08 §3), so this file imports only Flutter.
///
/// **Why not the default `SnackBar`.** The stock one is a full-bleed black bar
/// with no way to dismiss it but waiting: it looks like it belongs to a
/// different application than the panels above it, and it parks itself over the
/// timeline for four seconds — which is exactly where the keyframe coaching
/// tells the user to look next. This one is themed like the panels, no wider
/// than it needs to be, and **closable**: an ✕ on the right, a swipe in either
/// direction, or the timer, whichever comes first.
///
/// It takes a [ScaffoldMessengerState] rather than a `BuildContext` on purpose.
/// Every caller is a command reporter that captured its messenger **before** an
/// await (a `BuildContext` may not cross an async gap), and handing that object
/// straight through keeps that discipline instead of quietly reintroducing a
/// post-await `context` lookup.
enum ToastKind {
  /// Something could not be done — a refused edit, a failed save. The colour
  /// the user already reads as "stop" elsewhere in the editor.
  alert,

  /// A teaching moment that follows a *successful* action, so it must not look
  /// like a failure.
  tip,
}

/// How tall the chrome at the **bottom** of the window is, so a toast can float
/// clear of it.
///
/// The editor's timeline is pinned to the bottom edge and is **resizable**, so
/// there is no constant that can be baked in here — and a toast parked over the
/// timeline is worse than no toast at all when the message it carries is "move
/// the playhead". `editor_shell.dart` sets this as the panel resizes and clears
/// it on teardown; screens without a timeline leave it at zero and their toasts
/// sit where they always did.
///
/// It is a bare `double` on purpose: nothing rebuilds when it changes (it is
/// read once, at the moment a toast is shown), so a notifier would be ceremony
/// around an assignment. It is chrome geometry written by the one file that
/// composes the panels — not shared *state* that a feature can reach into
/// (docs/v3/08 §4).
double _bottomChrome = 0.0;

/// Total, because it feeds a layout constraint: a NaN here would propagate into
/// the toast's margin and take the frame with it.
void setEditorBottomChrome(double height) =>
    _bottomChrome = height.isFinite ? math.max(0.0, height) : 0.0;

/// Show [message] as the editor's toast.
///
/// [duration] defaults to something proportionate: a refusal is a few words and
/// is gone in four seconds; a tip is a sentence with an instruction in it, so it
/// waits longer and can always be closed early.
void showEditorToast(
  ScaffoldMessengerState messenger,
  String message, {
  ToastKind kind = ToastKind.alert,
  Duration? duration,
}) {
  final context = messenger.context;
  final scheme = Theme.of(context).colorScheme;

  final (Color background, Color foreground, Color accent, IconData icon) =
      switch (kind) {
    ToastKind.alert => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
    ToastKind.tip => (
        scheme.surfaceContainerHigh,
        scheme.onSurface,
        scheme.primary,
        Icons.lightbulb_outline,
      ),
  };

  // Narrow and centred rather than full-bleed: a sentence set across 1400 px is
  // harder to read than the same sentence set across 40 characters, and a bar
  // that spans the window hides more of the editor than it needs to.
  // `maybeSizeOf` because the messenger's context is not guaranteed to sit under
  // a MediaQuery in every host, and a missing one must not cost the message.
  final available = MediaQuery.maybeSizeOf(context)?.width ?? 560.0;
  final width = math.max(280.0, math.min(560.0, available - 32));
  // Centred via symmetric margins rather than `width`, because the two cannot
  // be combined and only `margin` can lift the bar above the timeline.
  final side = math.max(16.0, (available - width) / 2);

  messenger.showSnackBar(SnackBar(
    backgroundColor: background,
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.only(
        left: side, right: side, bottom: _bottomChrome + 12),
    elevation: 6,
    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: kind == ToastKind.tip ? scheme.outlineVariant : background,
      ),
    ),
    // Either way, not just down — a toast in the way should get out of it with
    // whatever flick the user reaches for first.
    dismissDirection: DismissDirection.horizontal,
    duration: duration ??
        (kind == ToastKind.tip
            ? const Duration(seconds: 8)
            : const Duration(seconds: 4)),
    content: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 17, color: accent),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12, height: 1.4, color: foreground),
          ),
        ),
        const SizedBox(width: 6),
        // The ✕ the user asked for, top-right where a dismiss lives everywhere
        // else. `hideCurrentSnackBar` animates this one away and lets anything
        // queued behind it through, rather than clearing the queue.
        Tooltip(
          message: 'Dismiss',
          child: InkWell(
            key: const Key('toast-dismiss'),
            onTap: messenger.hideCurrentSnackBar,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(Icons.close,
                  size: 15, color: foreground.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ],
    ),
  ));
}
