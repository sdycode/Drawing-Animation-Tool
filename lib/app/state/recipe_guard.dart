/// The one routing predicate that stands between a shape-parameter edit and the
/// geometry it regenerates — **does this node carry an animated path?**
///
/// **Why it lives here and not in a feature.** Two features issue recipe
/// regeneration — the canvas (the shape tools' re-edit path) and the inspector
/// (its shape-parameter fields) — and a file under `features/X` may not import
/// `features/Y` (docs/v3/08 §3, enforced by `tool/check_boundaries.dart`).
/// Anything two features need moves **down**, never sideways; `state/` is not a
/// feature and both may import it. A copy in each feature is the same defect
/// twice over: the day one copy learns a subtlety the other keeps routing the
/// old way, and the two write the same document two different ways.
///
/// **What it decides — a route, no longer a refusal.** An editable recipe reaches
/// geometry by one of two representable routes, and which one is a property of
/// the *document*, not the recipe:
///
/// - **No path track → `RegenerateRecipeCommand`.** Nothing poses the old ids, so
///   the recipe's fresh anchor set simply replaces them and the recipe rides
///   along as inert metadata (AC-4.1.4). This is every shape just drawn and every
///   shape nobody has animated yet.
/// - **A path track → `RetopologizeCommand`.** Every keyframe poses the *old* ids
///   while `recipe.toPath()` mints *fresh* ones, so a raw replacement would leave
///   the topology and its keyframes disjoint — the single state v3 exists to make
///   unrepresentable (docs/v3/01 §5, §13.1). `PathOps.retopologize` rewrites every
///   keyframe onto the new id set by arc-length correspondence (AC-4.1.5,
///   AC-4.3.7) and clears the now-stale recipe. Once per edit, from a command,
///   never inside the tick.
///
/// **Why this used to be a refusal, and why it is not any more.** Until M5 a
/// tracked node was *refused*: `retopologize` did not exist, so the honest answer
/// was a disabled field naming the missing capability. M5 shipped `retopologize`,
/// so the tracked case now **works** — the predicate that once gated the edit now
/// only chooses its route. The one genuinely impossible case, an `UnknownRecipe`,
/// never arrives here as an editable field: it draws no parameters (the inspector
/// shows a sentence and stops) and its `toPath()` is empty, so retopologising to
/// it would erase the outline. `PathOps.regenerateRecipe` still refuses it,
/// loudly, as the backstop for a mis-routed call (docs/v3/08 §1) — never a path a
/// user reaches.
///
/// So one predicate drives both halves: the inspector enables the shape fields
/// for any recipe it can read and hands the edit here, and here decides the
/// route. The control the user sees and the write behind it can never disagree,
/// because every recipe the panel makes editable has a representable route and
/// this is the fork between them.
library;

import 'package:anim_core/anim_core.dart';

/// True when [node] carries a `path` track in **any** of [document]'s animations
/// — the fork between an in-place recipe regeneration and a retopologise.
///
/// Checks every animation, not just the default one: a track under a second clip
/// poses the same node's anchors and would be orphaned just as thoroughly by a
/// raw replacement.
bool hasPathTrack(Document document, NodeId node) {
  for (final animation in document.animations) {
    if (animation.tracksFor(node).pathTrack() != null) return true;
  }
  return false;
}
