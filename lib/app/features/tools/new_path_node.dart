/// The one place a *new* [PathNode] is built — the pen tool and the three shape
/// tools mint the same kind of node.
///
/// **Why a function and not two copies.** The pen and the shape tools both
/// finish a gesture by constructing a whole node and appending it in one
/// [AddNodeCommand], so a document never contains half a gesture. The paint they
/// give it is identical, and two copies of "a blue fill and a dark 2 px stroke"
/// is two places for the M3 exit criterion's *filled, stroked* half to quietly
/// stop being true in one tool and not the other.
///
/// **This is not a paint feature and must not become one.** docs/v3/06 M3 names
/// gradient authoring as one of the two most likely scope leaks: the sealed
/// `PaintSource` type already has `LinearGradientPaint` and `RadialGradientPaint`
/// and they get **no authoring UI** in v1 (AC-5.1.3). What lives here is the
/// starting paint of a brand-new shape, nothing more. Editing it belongs to the
/// inspector, and the seam for that is exactly this function: when the inspector
/// owns fill and stroke, a new node still starts somewhere, and this is where.
library;

import 'package:anim_core/anim_core.dart' hide Animation;

/// A brand-new path node: [path] as its topology, [recipe] as inert re-edit
/// metadata (null for anything the pen drew), one solid fill and one solid
/// stroke.
///
/// Every id is minted with [uuidV4] — the node's, and both paint subject ids.
/// **Never a constant like `PaintId('p-body')`**: `PaintId` is the subject id a
/// `fillColor` track binds to (docs/v3/01 §5), so two nodes sharing one is the
/// same class of defect as two anchors sharing an `AnchorId`, and it only
/// becomes visible at M4 when a track finally has something to join against.
///
/// [transform] carries where the shape sits. Shape recipes generate geometry
/// **centred on the local origin** (`shape_geometry.dart`), so the shape tools
/// pass the drag box's centre here and get a node that rotates about its own
/// middle; the pen builds artboard-space anchors and leaves it identity.
PathNode newPathNode({
  required String name,
  required PathData path,
  ShapeRecipe? recipe,
  Transform2 transform = Transform2.identity,
}) =>
    PathNode(
      id: NodeId(uuidV4()),
      name: name,
      transform: transform,
      path: path,
      recipe: recipe,
      fills: <Fill>[
        Fill(
          id: PaintId(uuidV4()),
          paint: const SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0)),
        ),
      ],
      strokes: <Stroke>[
        Stroke(
          id: PaintId(uuidV4()),
          paint: const SolidPaint(Rgba(0.05, 0.05, 0.08, 1.0)),
          width: 2.0,
          join: StrokeJoin.round,
        ),
      ],
    );
