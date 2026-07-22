/// The painters' fault sink (docs/v3/08 §1).
///
/// `anim_core` contains no `try`/`catch` at all — totality there is a proof
/// obligation, not a runtime rescue. Containment starts exactly one layer out,
/// here, because a painter is the first place a failure is already a
/// user-visible event and there is a slot to draw a fallback into.
///
/// The rule this file exists to enforce: **a `catch` that only returns is the
/// quiet cousin of legacy's modal-per-frame.** Legacy shipped a broken tweener
/// for months behind swallowed `RangeError`s. So every catch in this package
/// reports here *and* asserts, and the assert is wired so that silence is only
/// possible when somebody has explicitly volunteered to watch.
library;

import 'package:anim_core/anim_core.dart' show ScenePath;

/// One item that failed to draw. Never a whole frame — see [RenderFaults].
final class RenderFault {
  const RenderFault({
    required this.stage,
    required this.error,
    required this.stack,
    this.path,
  });

  /// Where in the paint the failure happened, e.g. `'drawNode'`. Free text on
  /// purpose: it is a debugging breadcrumb, not a switchable enum, and giving
  /// it a closed type would make adding a painter a two-file change.
  final String stage;

  /// The scene node being drawn, when there was one. Null for a failure that
  /// is not attributable to a single item.
  final ScenePath? path;

  final Object error;
  final StackTrace stack;

  @override
  String toString() =>
      'RenderFault($stage${path == null ? '' : ' at $path'}): $error';
}

/// The static sink the painters report to.
///
/// Static, and deliberately not injected through the painter constructors: a
/// per-painter callback would have to be threaded through `paintScene`, which
/// is the pure testable function the golden tests call, and adding a required
/// reporting parameter there is how the pure function stops being pure.
abstract final class RenderFaults {
  RenderFaults._();

  /// Installed by the app shell (to surface a badge) and by tests (to observe).
  /// Null in production until the shell is wired up.
  static void Function(RenderFault fault)? sink;

  /// Returns **true** when a sink consumed the fault.
  ///
  /// That return value is the whole design. Call sites read:
  ///
  /// ```dart
  /// final watched = RenderFaults.report(fault);
  /// assert(watched, '$fault');
  /// ```
  ///
  /// so a debug build with nobody listening screams — which is what
  /// `assert(false, ...)` in docs/v3/08 §1 is asking for — while a test or a
  /// shell that has installed a sink has *declared* it is watching and gets
  /// the contained behaviour instead. Without this handshake the assert makes
  /// the containment itself untestable: the AssertionError escapes the catch
  /// and one bad node takes the frame down again, which is the exact failure
  /// the per-item catch exists to prevent.
  static bool report(RenderFault fault) {
    final s = sink;
    if (s == null) return false;
    s(fault);
    return true;
  }
}
