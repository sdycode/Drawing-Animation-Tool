/// The transport feature's named slices (docs/v3/08 §2).
///
/// The transport OWNS `playing`, `LoopMode` and the seconds↔`t` display
/// conversion, and it NEVER stores time in pixels (docs/v3/05 §2 panel
/// contract). It reads the document only through the value-equal record slice
/// below — no transport widget watches `documentControllerProvider` directly —
/// so a document mutation that changes neither the loop mode nor the duration
/// rebuilds the bar not at all.
///
/// This file imports the `anim_core` barrel WITHOUT `hide Animation` and imports
/// **no** Flutter, on purpose: it needs the real `Animation` type and the
/// top-level `normalizedTime` to feed the Ticker, and the ambiguous-`Animation`
/// clash only exists in files that also import Flutter (docs/v3/01 §10). Keeping
/// the clock→`t` maths here is what lets the widget stay Flutter-only and never
/// name `Animation` at all.
library;

import 'package:anim_core/anim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/document_controller.dart';
import '../../state/editor_controller.dart';

/// The two PERSISTED time-model fields the transport shows, plus the id it edits
/// them on — a **record**, so `.select` dedups by value with no hand-written
/// `==`/`hashCode` (exactly as the shell's read-only banner slice does).
typedef TransportModel = ({
  AnimationId? animationId,
  LoopMode loop,
  double durationSeconds,
});

/// "No animation" — a legal document with no `defaultAnimationId` renders its
/// rest pose, and the transport shows the neutral defaults against it.
const TransportModel restingTransport =
    (animationId: null, loop: LoopMode.loop, durationSeconds: 1.0);

/// Loop mode + duration of the active animation, as a value-equal slice.
///
/// Never `animations.first` (docs/v3/01 §11): the active id is resolved by
/// `activeAnimationProvider` (the editor override or the document's
/// `defaultAnimationId`), and a stale pointer simply falls back to the resting
/// defaults rather than throwing on an empty list.
final transportModelProvider =
    Provider.autoDispose.family<TransportModel, String>((ref, projectId) {
  final animationId = ref.watch(activeAnimationProvider(projectId));
  if (animationId == null) return restingTransport;
  return ref.watch(documentControllerProvider(projectId).select((async) {
    final doc = async.valueOrNull;
    if (doc == null) return restingTransport;
    for (final a in doc.animations) {
      if (a.id == animationId) {
        return (
          animationId: animationId,
          loop: a.loop,
          durationSeconds: a.durationSeconds,
        );
      }
    }
    return (
      animationId: animationId,
      loop: LoopMode.loop,
      durationSeconds: 1.0,
    );
  }));
});

/// Wall-clock elapsed seconds → normalized `t`, **delegating to `anim_core`'s
/// `normalizedTime`** (AC-9.1.2) — the transport never reimplements
/// clamp/wrap/triangle.
///
/// `normalizedTime` lives OUTSIDE the evaluator (docs/v3/01 §10) precisely so a
/// clock-driven caller like the Ticker can feed it elapsed seconds and get the
/// loop-correct `t` back. The throwaway `Animation` carries only the two fields
/// it reads — duration and loop — because the tick has those on a cached record
/// and must not read the document (or walk its tracks) every frame.
double transportNormalizedTime(TransportModel model, double elapsedSeconds) {
  final animation = Animation(
    id: model.animationId ?? const AnimationId('transport'),
    name: '',
    durationSeconds: model.durationSeconds,
    loop: model.loop,
  );
  return normalizedTime(animation, elapsedSeconds);
}
