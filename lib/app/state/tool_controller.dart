/// Tool mode — the third of the three controllers (docs/v3/04 §4).
///
/// **Why the contract lives in `state/` and the tools live in `features/tools/`.**
/// The canvas (a feature) must reach the active tool, and a feature may not
/// import a sibling feature (docs/v3/08 §3). So the *vocabulary* every feature
/// shares — the [ToolMode] contract, the [PointerCtx] a tool is handed, the
/// [ToolId] the toolbar switches on, and the [toolControllerProvider] the canvas
/// watches — lives here in the controller layer, which is not a feature and is
/// therefore reachable from all of them. The canvas never names `SelectTool`: it
/// watches this provider, gets a [ToolMode], and calls through the contract.
///
/// **The dependency points one way, and that is load-bearing.** This file
/// imports nothing from `features/`. An earlier version imported
/// `features/tools/registry.dart` for `resolveTool`, reasoning that the boundary
/// check forbids only *feature → sibling-feature* and `state/` is not a feature.
/// That reading is true of the checker and false of the architecture: it made the
/// real edge `features/canvas → state/ → features/tools/select`, laundered
/// through the controller layer, and it cost the property docs/v3/08 §5 sells as
/// the alternative to a feature-flag registry — deleting `features/tools/` did
/// **not** leave a compiling app, it broke `state/` and through it the canvas.
/// So the concrete tools are injected at composition ([toolResolverProvider])
/// instead, and the arrow now runs `features/tools → state/`, never back.
///
/// **Not a Dart `sealed` class, deliberately.** docs/v3/04 §4 calls it a "sealed
/// class ToolMode", but a Dart `sealed` type requires every variant in the same
/// library, which contradicts the directory law that splits the tools across
/// `select/select_tool.dart`, `pen/pen_tool.dart` and `shape/shape_tool.dart`
/// (docs/v3/08 §3). `sealed`'s only payoff is exhaustive `switch` — and
/// exhaustive `switch` on a tool type in app code is exactly what docs/v3/08 §2
/// bans (dispatch through a map with a `?? ` fallback instead). So the closed set
/// is enforced by the registry, not by the compiler, and this stays an
/// `abstract interface class`.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'command.dart';
import 'editor_controller.dart';

/// The tools the toolbar can switch between (docs/v3/05 §3). Pan and Zoom are
/// **not** here — they are ephemeral viewport gestures the canvas applies through
/// [EditorController.panBy]/[EditorController.zoomAround], and mutate nothing, so
/// they never become a modal tool that could swallow a click meant for Select.
///
/// The three shape tools are three ids, not one `shape` id with a parameter:
/// `R`, `O` and `G` are three separate modal states in docs/v3/05 §5, the
/// toolbar shows three buttons, and a tool that had to be asked "which shape are
/// you?" would put that answer somewhere — a field on the controller, or worse
/// on `EditorState` — where a second feature could read or write it.
enum ToolId {
  select,
  directSelect,
  pen,
  rect,
  ellipse,
  polygon,
}

/// The two keys a tool may answer, both from docs/v3/05 §5.
///
/// Deliberately not `LogicalKeyboardKey`: `state/` would then depend on
/// `package:flutter/services.dart` to express its contract, and every tool
/// would be free to claim any key. Two named intents keep the canvas the only
/// place a physical key is read.
///
/// **`Esc` and `Enter` do the same thing to a pen path — they leave it open.**
/// That is docs/v3/05 §3's Pen row verbatim. §5's shortcut table says `Enter`
/// *closes* the in-progress path; the two documents disagree, and §3 wins here
/// because it is the tool's own behavioural row. Closing is what clicking the
/// first anchor does, and it is the one route worth having: closing by keyboard
/// would have to invent an answer for a two-anchor path, where "closed" means a
/// segment drawn on top of itself.
enum ToolKey { escape, enter }

/// A selection change a tool asks the canvas to perform.
///
/// **Selection is `EditorState`, never a [Command]** (docs/v3/08 §2), so a tool
/// cannot write it — but the tool is the only thing that knows what its gesture
/// hit. Returning the *intent* keeps both halves of that rule: the tool decides,
/// [EditorController] performs, and no tool holds a reference to a controller.
@immutable
final class ToolSelection {
  const ToolSelection._(this.nodes, this.add, this.anchor, this.setsAnchor);

  /// Replace the node selection with [nodes].
  const ToolSelection.replace(Set<ScenePath> nodes)
      : this._(nodes, false, null, false);

  /// Add [nodes] to the current selection (`Shift`+click, docs/v3/05 §3).
  const ToolSelection.add(Set<ScenePath> nodes)
      : this._(nodes, true, null, false);

  /// Replace the anchor selection — Direct select's grab. Null clears it.
  const ToolSelection.anchor(AnchorId? anchor)
      : this._(null, false, anchor, true);

  /// Both at once: grabbing an anchor also selects the node that owns it, so
  /// the inspector and the selection outline follow the handle the user is
  /// working on instead of staying on whatever was selected before.
  const ToolSelection.nodeAndAnchor(Set<ScenePath> nodes, AnchorId? anchor)
      : this._(nodes, false, anchor, true);

  /// Deselect everything (a click on empty space).
  static const ToolSelection clear = ToolSelection.replace(<ScenePath>{});

  /// Null means "leave the node selection exactly as it is" — which is not the
  /// same as an empty set, and the difference is a click on an anchor not
  /// dropping the node selection out from under the inspector.
  final Set<ScenePath>? nodes;
  final bool add;

  final AnchorId? anchor;

  /// Distinguishes "select no anchor" from "do not touch the anchor selection",
  /// for the same reason [nodes] is nullable.
  final bool setsAnchor;
}

/// Everything a tool asks the canvas to do that is **not** a document edit.
///
/// A document edit is a [Command] — one class per edit, returned from the
/// pointer handler. Everything else a gesture legitimately causes (a selection,
/// a refusal the user must see, the pen exiting to Select on close) is
/// ephemeral, belongs to a controller the tool may not reach, and rides here.
///
/// It is **pulled, not pushed**: the canvas calls [ToolMode.takeEffect] after
/// each handler. A pushed callback would put a `void Function(...)` on every
/// tool and make the order of "command applied" versus "selection written"
/// depend on which tool you are looking at.
@immutable
final class ToolEffect {
  const ToolEffect({this.selection, this.message, this.activate});

  final ToolSelection? selection;

  /// A sentence for the user — a **refusal**, not an error. A tool that
  /// declines an edit (an animated transform, an M5-only regeneration) says so;
  /// silence is indistinguishable from a broken gesture.
  final String? message;

  /// Switch the modal tool. The pen uses it to exit to Select on close
  /// (docs/v3/05 §4.1 step 4); nothing else does.
  final ToolId? activate;
}

/// What the canvas should paint for a gesture that has not been committed yet.
///
/// **Every half is ephemeral and none of them is ever saved.** [document] is the
/// document as it *would* be if the drag were released now — produced by the
/// same op the release commits, so the moving shape cannot disagree with what
/// lands (a second "preview-only" geometry path would be a second evaluator,
/// docs/v3/08 §4). [path] is geometry a tool is still building. [markers] are
/// artboard-space points for the overlay layer's `pending` channel — the shape
/// tools' drag preview and direct select's grabbed point.
///
/// An in-progress path is [path] or [markers] and **never** a preview
/// [document]: a half-drawn path in a document — even a speculative one — is a
/// shape in the artboard layer, in the layers panel's paint order, and one
/// missed reset away from being the thing autosave persists. Overlay geometry
/// cannot become any of that.
@immutable
final class ToolPreview {
  const ToolPreview({
    this.document,
    this.path,
    this.liveHandle,
    this.markers = const <Vec2>[],
  });

  static const ToolPreview none = ToolPreview();

  final Document? document;

  /// The path being drawn right now, in **artboard** coordinates, or null.
  ///
  /// Geometry rather than points, and that is the whole reason this field
  /// exists: the pen used to describe its half-drawn path through [markers],
  /// so the user drew a curve and the canvas answered with dots. A `List<Vec2>`
  /// cannot express a cubic. The overlay strokes this instead (`DraftPath` in
  /// `anim_render` carries it the last step, together with the cursor, which
  /// only the canvas knows).
  ///
  /// It is a **copy** handed out per read — the anchors themselves stay a
  /// private field of the tool (docs/v3/08 §2). This is a rendering channel,
  /// not a place to park state.
  final PathData? path;

  /// The anchor in [path] whose tangent handles the gesture is dragging, or
  /// null when no handle is live. Named by id, never by index.
  final AnchorId? liveHandle;

  final List<Vec2> markers;
}

/// Everything a tool may read on a pointer event, and **nothing it may write**
/// (docs/v3/08 §2). A tool observes the world and returns a [Command] (a
/// `Document` edit) or null; it never touches `Document` or `EditorState`
/// directly. That read-only shape is what stops a tool from editing the document
/// inside a gesture handler — the legacy defect where `build()`/`paint()` mutated
/// state (docs/v3/05 §3 rule 2).
final class PointerCtx {
  const PointerCtx({
    required this.docPoint,
    required this.screenPoint,
    required this.fit,
    required this.scene,
    required this.doc,
    required this.editor,
    required this.animation,
    required this.playhead,
    this.shift = false,
    this.alt = false,
  });

  /// Pointer position in **document space** — the canvas has already inverted the
  /// single composed `viewportTransform ∘ artboardFit` matrix (docs/v3/05 §3),
  /// so a tool never re-derives the transform and never invents a second one
  /// (AC-3.1.4).
  final Vec2 docPoint;

  /// The same pointer in canvas-local **screen** pixels.
  final Vec2 screenPoint;

  /// **THE** composed matrix — `viewportTransform ∘ artboardFit`, built once per
  /// build by the canvas and handed to all three painters (AC-3.1.4).
  ///
  /// Handing it to the tool is not a second mapping; it is the *same* one,
  /// passed by value. A tool needs it because a grab radius is a **screen**
  /// distance: 14 px at every zoom, exactly like the handle the user is aiming
  /// at, which the overlay also draws at a constant screen radius. Comparing
  /// document-space distances instead would make handles untargetable when
  /// zoomed out and grabbable from a mile away when zoomed in.
  final Affine fit;

  /// The evaluated scene at the live playhead — for hit-testing against posed
  /// geometry, keyed by `ScenePath`.
  final Scene scene;

  /// The current document, for a tool that needs a node's authored `Transform2`
  /// or `PathData` (the overlay draws *authored* anchors, never `Scene`'s
  /// synthetic ones — docs/v3/04 §5).
  final Document doc;

  /// The current ephemeral state — the existing selection a drag operates on.
  final EditorState editor;

  /// The animation the playhead is a position within, already resolved against
  /// the document's `defaultAnimationId` (`activeAnimationProvider`). Null means
  /// the document has none, which is a rest-pose-only document, not an error.
  final AnimationId? animation;

  /// The live playhead, clamped into `0..1` by the canvas. Pose edits key
  /// against it (`atT:`), so it is the one number that decides whether a drag is
  /// a rest-pose edit or a keyframe-local one.
  final double playhead;

  /// Keyboard modifiers, read once by the canvas and passed **by value**.
  ///
  /// A tool that asked `HardwareKeyboard.instance` itself would be a tool whose
  /// behaviour cannot be driven by a test without synthesising real key events,
  /// and would put `package:flutter/services.dart` in every tool file.
  final bool shift;
  final bool alt;

  /// The screen-pixel radius within which a click counts as *on* a handle, an
  /// anchor, or the pen's first anchor.
  ///
  /// Generous on purpose, and in **screen** pixels rather than document units
  /// so it is the same physical target at every zoom — the overlay draws its
  /// handles at a constant screen radius for the same reason. One constant for
  /// the whole tool layer: a pen whose close radius disagreed with direct
  /// select's grab radius would let the user land in the gap between them.
  static const double grabRadius = 14.0;

  /// The mix the canvas evaluated [scene] with — one definition, so a tool that
  /// needs stages 1–3 (the overlay's authored-anchor frame) cannot sample a
  /// different `t` than the pixels the user is aiming at.
  List<AnimationMix> get mix {
    final id = animation;
    return id == null
        ? const <AnimationMix>[]
        : <AnimationMix>[AnimationMix(id, playhead)];
  }

  /// Screen-pixel distance from the pointer to a **document-space** point,
  /// through [fit]. The one place a grab radius is measured.
  double screenDistanceTo(Vec2 docSpace) {
    final at = fit.apply(docSpace);
    if (!at.x.isFinite || !at.y.isFinite) return double.infinity;
    return (at - screenPoint).length;
  }
}

/// One tool. **In-progress gesture state is a private field of the implementing
/// class — never on `Document`, never on `EditorState`** (docs/v3/08 §2). An
/// unfinished drag that leaked into either would be autosaved or would survive an
/// undo; keeping it private to the tool is what makes a half-finished gesture
/// unrepresentable in the persisted or undoable world.
///
/// Every pointer handler returns a [Command] to mutate the document, or null when
/// the gesture changed nothing the document owns. **Selection is not a [Command]**
/// — it is `EditorState`, applied by the canvas gesture layer through
/// [EditorController]; a tool signals a pure selection by returning null.
abstract interface class ToolMode {
  ToolId get id;

  Command? onPointerDown(PointerCtx ctx);
  Command? onPointerMove(PointerCtx ctx);
  Command? onPointerUp(PointerCtx ctx);

  /// `Esc` / `Enter` while the canvas has focus (docs/v3/05 §5). Every tool
  /// answers it; all but the pen answer null.
  Command? onKey(ToolKey key, PointerCtx ctx);

  /// The selection / message / tool-switch the last handled event asks for, and
  /// **clears it** — an effect is consumed exactly once, by the canvas, on the
  /// event that produced it.
  ToolEffect? takeEffect();

  /// What to paint for the in-flight gesture. [ToolPreview.none] when there is
  /// no gesture, which is the state every tool is in between strokes.
  ToolPreview get preview;

  /// Drop the in-progress gesture and its preview, changing nothing the
  /// document owns.
  ///
  /// Called when the tool is switched away from ([ToolController.activate]) and
  /// when the pointer gesture is cancelled. Without it a half-drawn pen path
  /// would still be sitting in the tool the next time the user picked it up —
  /// state that outlives the interaction it belongs to, which is the same defect
  /// as storing it on `EditorState`, just quieter.
  void cancel();
}

/// Holds the one active tool. Modal: exactly one at a time (docs/v3/05 §3).
///
/// A plain [Notifier] (not `Async`, not a family): the tool is process-local UI
/// state with no IO and no per-project identity — switching tools must not
/// invalidate the document or the editor state, which is the whole point of
/// keeping the three controllers apart (docs/v3/04 §4).
class ToolController extends Notifier<ToolMode> {
  @override
  ToolMode build() => ref.watch(toolResolverProvider)(ToolId.select);

  /// Switch tools (the toolbar / a key binding). Goes through the injected
  /// resolver so an id with no tool of its own resolves to something usable
  /// rather than null.
  ///
  /// **The outgoing tool is cancelled first.** Half a pen path left in the pen
  /// tool while the user drew a rectangle would reappear on the next `P`, and
  /// the click that closed it would mint a node with two unrelated halves. The
  /// gesture belongs to the interaction, not to the session.
  void activate(ToolId id) {
    final next = ref.read(toolResolverProvider)(id);
    if (identical(next, state)) return;
    state.cancel();
    state = next;
  }
}

final toolControllerProvider =
    NotifierProvider<ToolController, ToolMode>(ToolController.new);

/// Maps a [ToolId] to the live tool that implements it.
///
/// **Overridden at composition** — `main.dart` supplies `features/tools`'
/// registry. That override is the whole reason `state/` imports no feature: the
/// implementations plug into this contract, the contract never reaches for them.
///
/// The default below is deliberately **inert, not absent**. A tool that returns
/// no [Command] is a tool that changes nothing, which is exactly right for a
/// build (or a widget test) that has not installed the registry — whereas a null
/// tool or a throwing default would make the canvas's `ref.watch` a crash site,
/// and docs/v3/08 §2 requires provider bodies to be provably total.
///
/// It preserves the requested `id`, so the toolbar highlights the tool the user
/// picked either way and nothing reading `tool.id` has to special-case the
/// un-composed build.
///
/// **At M3 that default really does mean a canvas that ignores clicks.** The
/// canvas no longer implements select / move / draw inline — every pointer
/// event is a `PointerCtx` dispatched through the active [ToolMode] — so a
/// widget test that drives *any* tool must install the same override
/// `main.dart` does (`toolResolverProvider.overrideWithValue(toolRegistry())`).
/// That is the cost of the arrow pointing one way, and it is paid in test
/// harnesses rather than in the architecture.
final toolResolverProvider = Provider<ToolMode Function(ToolId)>(
  (ref) => (id) => _InertTool(id),
);

/// A tool that does nothing, for the un-composed case. Not a seam and not a
/// stub for a future tool — its only job is to keep [toolResolverProvider]
/// total.
final class _InertTool implements ToolMode {
  const _InertTool(this.id);

  @override
  final ToolId id;

  @override
  Command? onPointerDown(PointerCtx ctx) => null;

  @override
  Command? onPointerMove(PointerCtx ctx) => null;

  @override
  Command? onPointerUp(PointerCtx ctx) => null;

  @override
  Command? onKey(ToolKey key, PointerCtx ctx) => null;

  @override
  ToolEffect? takeEffect() => null;

  @override
  ToolPreview get preview => ToolPreview.none;

  @override
  void cancel() {}
}
