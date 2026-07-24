/// The three shape tools — `R` rect, `O` ellipse, `G` polygon (AC-4.1.4,
/// docs/v3/05 §3's Shape row).
///
/// Drag on the canvas → a bounding box; on release the [ShapeRecipe] generates
/// the `PathData` and the node stores the recipe as **inert** metadata.
/// `Shift` constrains square / circle / regular, `Alt` draws from the centre.
///
/// ## The geometry is `anim_core`'s, all of it
///
/// This file computes a box and nothing else. `recipe.toPath()` — the extension
/// in `shape_geometry.dart` — turns the parameters into anchors: four real
/// cubics at κ = 0.5523 for an ellipse (never legacy's 114 straight segments),
/// four anchors for a rectangle, `sides` for a polygon, and `PathData.empty` for
/// every degenerate box a drag passes through on its way to a real shape. A
/// second copy of that maths in `app/` would be a second evaluator that
/// disagrees with core (docs/v3/08 §4), and it is precisely where a shape tool
/// grows a per-axis scale.
///
/// ## Why constructing the node needs no op
///
/// A brand-new node has no keyframes to keep consistent, so it is built whole
/// and appended in one [AddNodeCommand] — the same shape the pen uses.
/// `PathOps.regenerateRecipe` is for *re-editing* a recipe parameter later
/// (AC-4.1.5), and it refuses, naming M5, on a node that already has path
/// keyframes. Nothing here can reach that state: the node it commits is one
/// event old.
///
/// ## Inert means inert
///
/// The recipe is never keyed, never appears in a `TrackSet`, and is never read
/// by the evaluator or the renderer (docs/v3/01 §5). It is re-edit metadata, and
/// `PathOps.moveAnchor` / `setTangents` null it the moment an anchor is dragged
/// by hand — a rectangle whose corner was moved is not a rectangle any more, and
/// regenerating one from `w` and `h` would silently discard the drag.
library;

import 'dart:math' as math;

import 'package:anim_core/anim_core.dart' hide Animation;

import '../../../state/command.dart';
import '../../../state/tool_controller.dart';
import '../new_path_node.dart';

/// The default polygon, drawn before any inspector exists to change it.
///
/// Five sides, not three or six: it is unmistakably a polygon on screen (a
/// triangle reads as a stray path, a hexagon as a circle at small sizes), and
/// the count is the first thing the inspector's recipe field will edit.
const int kDefaultPolygonSides = 5;

final class ShapeTool implements ToolMode {
  ShapeTool(this.id)
      : assert(
          id == ToolId.rect || id == ToolId.ellipse || id == ToolId.polygon,
          'ShapeTool implements the three shape ids only',
        );

  /// Which shape this instance draws. One class, three instances, three ids —
  /// see [ToolId] for why the alternative (one `shape` id plus a parameter)
  /// puts that parameter somewhere a second feature can reach it.
  @override
  final ToolId id;

  /// The drag box in **artboard** coordinates, private to the tool
  /// (docs/v3/08 §2): a half-drawn rectangle is not a document, and it must not
  /// be autosaved or rebuild every panel while the pointer moves.
  Vec2? _from;
  Vec2? _to;

  ToolEffect? _effect;

  @override
  ToolEffect? takeEffect() {
    final effect = _effect;
    _effect = null;
    return effect;
  }

  /// The shape the recipe *would* generate, placed where the node would sit —
  /// stroked by the overlay through its in-progress **geometry** channel
  /// ([ToolPreview.path], `DraftPath`), exactly as the pen's half-drawn path is.
  ///
  /// **Geometry, not markers.** This used to feed the `markers` channel, so
  /// dragging out an ellipse showed the user four dots and a polygon N dots —
  /// never the outline they were drawing. That is the same defect the pen was
  /// upgraded away from (dots cannot express a cubic), so a shape now hands over
  /// the real `PathData`: the outline the user is dragging, stroked and unfilled,
  /// closed so it draws its whole rect/ellipse/polygon boundary.
  ///
  /// Produced by the **same** `recipe.toPath()` the release commits — only
  /// translated onto `box.centre`, where the committed node's `Transform2` will
  /// place identical geometry — so the preview cannot drift from the result. A
  /// degenerate box yields `PathData.empty`, so the first frame of every drag
  /// shows nothing rather than throwing (`shape_geometry.dart` is total, by
  /// design, for exactly this caller).
  @override
  ToolPreview get preview {
    final box = _box();
    if (box == null) return ToolPreview.none;
    final geometry = box.recipe.toPath();
    if (geometry.isEmpty) return ToolPreview.none;
    return ToolPreview(
      path: PathData(
        anchors: <Anchor>[
          for (final a in geometry.anchors)
            a.copyWith(position: box.centre + a.position),
        ],
        closed: geometry.closed,
      ),
    );
  }

  @override
  void cancel() {
    _from = null;
    _to = null;
  }

  @override
  Command? onKey(ToolKey key, PointerCtx ctx) => null;

  @override
  Command? onPointerDown(PointerCtx ctx) {
    _from = ctx.docPoint;
    _to = ctx.docPoint;
    _capture(ctx);
    return null;
  }

  @override
  Command? onPointerMove(PointerCtx ctx) {
    if (_from == null) return null;
    _to = ctx.docPoint;
    _capture(ctx);
    return null;
  }

  /// **ONE** [AddNodeCommand] per drag, on release (docs/v3/04 §6). A drag that
  /// never left the press point produces no geometry, so it produces no node and
  /// no undo entry — a stray click with the rectangle tool is not an edit.
  @override
  Command? onPointerUp(PointerCtx ctx) {
    final box = _box();
    cancel();
    if (box == null) return null;

    final path = box.recipe.toPath();
    if (path.isEmpty) return null; // degenerate: nothing to commit

    final node = newPathNode(
      name: '$_name ${ctx.doc.root.children.length + 1}',
      path: path,
      recipe: box.recipe,
      // The recipe centres its geometry on the local origin, so where the shape
      // sits is the node's transform. That is also what makes it rotate about
      // its own middle without a compensating pivot every tool would have to
      // remember to write.
      transform: Transform2(position: box.centre),
    );
    _effect = ToolEffect(
      selection: ToolSelection.replace(<ScenePath>{ScenePath(node.id)}),
    );
    return AddNodeCommand(node);
  }

  String get _name => switch (id) {
        ToolId.ellipse => 'Ellipse',
        ToolId.polygon => 'Polygon',
        _ => 'Rectangle',
      };

  /// The drag box, resolved through the modifiers, or null when no drag is in
  /// flight.
  ///
  /// `Shift` squares the box — which is a square, a circle, or a polygon
  /// inscribed in a square. `Alt` draws from the centre: the press point becomes
  /// the middle rather than a corner, so the box grows both ways.
  ({Vec2 centre, ShapeRecipe recipe})? _box() {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return null;

    var w = (to.x - from.x).abs();
    var h = (to.y - from.y).abs();
    if (_shift) {
      final side = math.min(w, h);
      w = side;
      h = side;
    }
    if (_alt) {
      // From the centre: the pointer describes a half-extent, not an extent.
      w *= 2;
      h *= 2;
    }

    final centre = _alt
        ? from
        : Vec2(
            from.x + (to.x >= from.x ? w : -w) / 2,
            from.y + (to.y >= from.y ? h : -h) / 2,
          );

    return (centre: centre, recipe: _recipe(w, h));
  }

  ShapeRecipe _recipe(double w, double h) => switch (id) {
        ToolId.ellipse => EllipseRecipe(rx: w / 2, ry: h / 2),
        // A polygon is regular by construction, so its one size parameter is a
        // radius: the circle inscribed in the drag box, which is what `Shift`
        // (a square box) makes a circumscribed one.
        ToolId.polygon => PolygonRecipe(
            sides: kDefaultPolygonSides,
            radius: math.min(w, h) / 2,
          ),
        _ => RectRecipe(w: w, h: h),
      };

  /// The modifiers as of the last pointer event.
  ///
  /// Captured on every move rather than read from the keyboard at release: a
  /// user who lets go of `Shift` a frame before the mouse button expects the
  /// square they were looking at, and re-reading the hardware at commit time
  /// would hand them a rectangle instead.
  bool _shift = false;
  bool _alt = false;

  void _capture(PointerCtx ctx) {
    _shift = ctx.shift;
    _alt = ctx.alt;
  }
}
