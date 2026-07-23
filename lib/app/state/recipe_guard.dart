/// The one pre-check that stands between a shape-parameter edit and
/// `PathOps.regenerateRecipe`, and the sentence it produces.
///
/// **Why it lives here and not in a feature.** Two features issue recipe
/// regeneration — the canvas (the shape tools' re-edit path) and the inspector
/// (its shape-parameter fields) — and a file under `features/X` may not import
/// `features/Y` (docs/v3/08 §3, enforced by `tool/check_boundaries.dart`).
/// Anything two features need moves **down**, never sideways; `state/` is not a
/// feature and both may import it. A copy in each feature is the same defect
/// twice over: the day one copy learns about a second refusal the other keeps
/// silently letting it through, and the two user-facing sentences drift into
/// contradicting each other about the same document.
///
/// **Why a pre-check at all, rather than catching the op's throw.** A document
/// carrying path keyframes is a perfectly legal document (docs/v3/08 §1), so the
/// answer owed to the user is a sentence they can act on. Letting
/// `PathOps.regenerateRecipe` throw would trip the command gate's
/// `assert(false, …)` and turn a legal document into a debug-mode crash. The op
/// still throws — that is its contract, and it is what stops a future call site
/// from bypassing this check — but nothing reaches it in that state.
library;

import 'package:anim_core/anim_core.dart';

/// The message shown when a shape's parameters cannot be re-applied because the
/// node's path is animated (AC-4.1.5, docs/v3/06 M5).
///
/// `PathOps.regenerateRecipe` mints **fresh** `AnchorId`s, and every existing
/// keyframe poses the old ones — so a raw replacement would leave the node's
/// topology and its keyframes disjoint, the single state v3 exists to make
/// unrepresentable. The correct answer is arc-length correspondence
/// (`PathOps.retopologize`), and a cheap approximation shipped under its name
/// would silently delete keyframes the user authored.
///
/// It names the missing capability in **plain language** rather than by
/// milestone code: the stranger docs/v3/00 §5 sends through the ship gate has
/// never read the roadmap, and "M5" beside a disabled control tells them nothing
/// about whether the tool is broken or unfinished.
const String kAnimatedPathRecipeMessage =
    'This shape’s path is animated, so its size and corner settings cannot be '
    'regenerated yet — that needs anchor correspondence across every keyframe.';

/// Null when [node]'s [ShapeRecipe] may be regenerated; the user-facing refusal
/// otherwise.
///
/// Checks **every** animation, not just the default one: a track under a second
/// clip poses the same node's anchors and would be orphaned just as thoroughly.
///
/// Callers use the same return value twice — as the gate in front of the command
/// and as the reason a field renders disabled — so the control the user sees and
/// the write they cannot make can never disagree.
String? recipeRegenerationRefusal(Document document, NodeId node) {
  for (final animation in document.animations) {
    if (animation.tracksFor(node).pathTrack() != null) {
      return kAnimatedPathRecipeMessage;
    }
  }
  return null;
}
