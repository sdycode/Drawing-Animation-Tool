/// The Direct select tool (`A`) — anchors and handles (docs/v3/05 §3, F4.2).
///
/// | Gesture | Result |
/// | --- | --- |
/// | click an anchor or a handle | select it |
/// | drag an anchor | `PathOps.moveAnchor` at the playhead |
/// | drag a handle | `PathOps.setTangents` at the playhead |
/// | `Alt` + drag a handle | **breaks symmetry** — sets [AnchorKind.corner] |
/// | `Alt` + click an anchor | cycles `AnchorKind` |
///
/// It takes over the anchor drag M0 wrote inline in the canvas, which was the
/// only pose edit the app had and belonged to no tool at all.
///
/// ## Pose, and keyframe-local
///
/// Both ops are **pose** edits (docs/v3/01 §12): they change where an anchor
/// sits or where its handles point, never which anchors exist. Passing
/// `atT: playhead` is what makes them keyframe-local — the op writes that one
/// keyframe's `AnchorPose` and leaves every other keyframe byte-identical
/// (AC-4.2.1, AC-4.2.2). The `AnchorId` **sequence** is untouched by
/// construction; neither op can change it.
///
/// `AnchorKind` is the exception, and deliberately so: it is not animatable
/// (docs/v3/01 §7), so `setTangents` writes it onto the node's `PathData`
/// document-wide while the handle correction it implies stays keyframe-local.
/// The renderer never reads `kind` — the invariants it names are baked into the
/// stored tangents at the moment they are set.
///
/// ## What is not here, and which milestone owns it
///
/// - **`Del` removes an anchor** — that is `PathOps.deleteAnchor`, a *topology*
///   op that must remove the id from `PathData` **and** from every keyframe
///   pose of every path track. It is **M5**, it does not exist, and there is no
///   partial version worth shipping: an anchor dropped from the topology but
///   left in the poses is the disjoint-id-set state v3 exists to make
///   unrepresentable.
/// - **Edit-at-keyframe** — a drag keys at the *playhead*, not at
///   `EditorState.selectedKeyframe`, and a drag on an untracked node at `t = 0`
///   seeds a track rather than editing the rest pose (AC-4.2.3). Both are
///   **M4**'s: it owns `selectedKeyframe` and the timeline that sets it. This is
///   the M0/M2 behaviour carried forward unchanged, not a new decision.
/// - **Marquee / `Cmd+A` over anchors** — multi-anchor selection has no editing
///   operation to be the subject of until M5.
library;

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/foundation.dart' show immutable;

import '../../../state/command.dart';
import '../../../state/tool_controller.dart';
import '../locked_nodes.dart';

/// Which part of an anchor the pointer grabbed.
enum _Part { anchor, inHandle, outHandle }

/// One anchor or handle drag in flight — **private to the tool**
/// (docs/v3/08 §2). A pose mid-drag lives here and nowhere the document or the
/// editor state can see it, so a half-finished drag is never autosaved and never
/// survives an undo.
@immutable
final class _Grab {
  const _Grab({
    required this.part,
    required this.node,
    required this.anchor,
    required this.kind,
    required this.base,
    required this.worldToLocal,
    required this.anchorLocal,
    required this.to,
    required this.moved,
  });

  final _Part part;
  final NodeId node;
  final AnchorId anchor;

  /// The anchor's stored [AnchorKind] when the drag began — the input to the
  /// `Alt`+click cycle.
  final AnchorKind kind;

  /// The document the gesture started from, captured once, so the preview is a
  /// function of what the user grabbed rather than of whatever arrives
  /// underneath the pointer mid-drag.
  final Document base;

  /// The node's **posed** world matrix, inverted. Both ops write node-local
  /// values, so the artboard-space pointer has to come back through the node's
  /// own transform.
  final Affine worldToLocal;

  /// The grabbed anchor's posed position in node-local space. A handle drag is
  /// measured from it, because tangents are stored **relative to the anchor**
  /// (the Lottie `i`/`o` convention).
  final Vec2 anchorLocal;

  /// Live pointer position in **document** space.
  final Vec2 to;

  /// True once the pointer has actually moved. It is what tells an `Alt`+click
  /// (cycle the kind) from an `Alt`+drag (break symmetry).
  final bool moved;

  _Grab at(Vec2 next) => _Grab(
        part: part,
        node: node,
        anchor: anchor,
        kind: kind,
        base: base,
        worldToLocal: worldToLocal,
        anchorLocal: anchorLocal,
        to: next,
        moved: moved || next != to,
      );

  /// The pointer in the node's local space — where `moveAnchor` wants its
  /// target and where a tangent is measured from.
  Vec2 get localPoint => worldToLocal.apply(to);
}

final class DirectSelectTool implements ToolMode {
  DirectSelectTool();

  @override
  ToolId get id => ToolId.directSelect;

  _Grab? _grab;
  ToolEffect? _effect;
  Document? _preview;

  /// The kind an `Alt`+click steps to. A **map with a fallback**, not an
  /// exhaustive `switch`: exhaustive switches are `anim_core`'s and
  /// `anim_render`'s only (docs/v3/08 §2), so a fourth `AnchorKind` added in v2
  /// changes core and leaves this compiling.
  static const Map<AnchorKind, AnchorKind> _nextKind = <AnchorKind, AnchorKind>{
    AnchorKind.corner: AnchorKind.smooth,
    AnchorKind.smooth: AnchorKind.symmetric,
    AnchorKind.symmetric: AnchorKind.corner,
  };

  @override
  ToolEffect? takeEffect() {
    final effect = _effect;
    _effect = null;
    return effect;
  }

  /// The speculative document, plus a marker on the grabbed point.
  ///
  /// The marker says *which* anchor or handle the gesture owns, which the moved
  /// geometry alone cannot: the overlay draws every anchor of every path node
  /// while this tool is active, and they all move when one does.
  @override
  ToolPreview get preview {
    final grab = _grab;
    if (grab == null) return ToolPreview.none;
    return ToolPreview(document: _preview, markers: <Vec2>[grab.to]);
  }

  @override
  void cancel() {
    _grab = null;
    _preview = null;
  }

  @override
  Command? onKey(ToolKey key, PointerCtx ctx) => null;

  @override
  Command? onPointerDown(PointerCtx ctx) {
    _grab = null;
    _preview = null;

    final grab = _findGrab(ctx);
    if (grab == null) {
      // Empty space: drop both selections. A drag from here mutates nothing.
      _effect = const ToolEffect(
          selection: ToolSelection.nodeAndAnchor(<ScenePath>{}, null));
      return null;
    }

    _grab = grab;
    _effect = ToolEffect(
      selection: ToolSelection.nodeAndAnchor(
        <ScenePath>{ScenePath(grab.node)},
        grab.anchor,
      ),
    );
    return null;
  }

  @override
  Command? onPointerMove(PointerCtx ctx) {
    final grab = _grab;
    if (grab == null) return null;
    final moved = grab.at(ctx.docPoint);
    _grab = moved;
    _preview = _previewOf(moved, ctx);
    return null; // one command per gesture, on release
  }

  /// **ONE** command per drag, on release (docs/v3/04 §6). A 200-event drag is
  /// one undo entry and one save because the live pose never left [_Grab].
  @override
  Command? onPointerUp(PointerCtx ctx) {
    final grab = _grab;
    _grab = null;
    _preview = null;
    if (grab == null) return null;

    if (!grab.moved) {
      // A click that never moved. `Alt` cycles the anchor's kind (docs/v3/05
      // §3); a plain click has already done its whole job — it selected.
      if (!ctx.alt || grab.part != _Part.anchor) return null;
      return SetTangentsCommand(
        grab.node,
        grab.anchor,
        // A bare kind with no handles: `corner` zeroes both — the straighten
        // affordance — while `smooth`/`symmetric` re-aim the existing pair.
        kind: _nextKind[grab.kind] ?? AnchorKind.corner,
        atT: ctx.playhead,
      );
    }

    if (grab.part == _Part.anchor) {
      return MoveAnchorCommand(
        grab.node,
        grab.anchor,
        grab.localPoint,
        atT: ctx.playhead,
      );
    }
    return _tangentCommand(grab, ctx);
  }

  /// The handle drag, as a command.
  ///
  /// `Alt` **breaks symmetry** by passing `kind: corner` *together with* the
  /// dragged handle: `PathOps.setTangents` stores a corner's handles verbatim
  /// and only zeroes them when the kind arrives on its own, so this authors an
  /// asymmetric corner rather than deleting the handle in the same breath. With
  /// no `Alt` the kind is left null — unchanged — and the op keeps whatever
  /// collinearity the anchor already claims.
  SetTangentsCommand _tangentCommand(_Grab grab, PointerCtx ctx) {
    final tangent = grab.localPoint - grab.anchorLocal;
    return SetTangentsCommand(
      grab.node,
      grab.anchor,
      inT: grab.part == _Part.inHandle ? tangent : null,
      outT: grab.part == _Part.outHandle ? tangent : null,
      kind: ctx.alt ? AnchorKind.corner : null,
      atT: ctx.playhead,
    );
  }

  /// Speculatively applies the drag with the **same ops the release commits**,
  /// so the moving geometry cannot disagree with what lands. The catch is at the
  /// tool boundary (docs/v3/08 §1): losing the preview for one frame if a delete
  /// landed mid-drag is the right cost, and the `assert` keeps it loud in debug.
  Document? _previewOf(_Grab grab, PointerCtx ctx) {
    try {
      if (grab.part == _Part.anchor) {
        return PathOps.moveAnchor(
          grab.base,
          grab.node,
          grab.anchor,
          grab.localPoint,
          atT: ctx.playhead,
        );
      }
      final cmd = _tangentCommand(grab, ctx);
      return cmd.apply(grab.base);
    } on ArgumentError catch (e) {
      assert(false, 'anchor drag preview rejected by an op: $e');
      return null;
    }
  }

  /// The nearest anchor or handle within [PointerCtx.grabRadius] **screen**
  /// pixels, or null.
  ///
  /// It searches stages **1–3** — `composeWorldA(resolvePose(sampleTracks(…)))`
  /// — which is exactly what `OverlayPainter` draws, so the hit-test and the
  /// dots the user is aiming at are the same frame. That is also why the ids are
  /// safe to write back: stage 7's trim produces **synthetic** `AnchorId`s
  /// (docs/v3/01 §11) and a grab that joined on one would pose an anchor no
  /// keyframe has. Stage 3 is strictly pre-trim.
  _Grab? _findGrab(PointerCtx ctx) {
    final frame = composeWorldA(resolvePose(sampleTracks(ctx.doc, ctx.mix)));
    final locked = lockedNodeIds(ctx.doc);

    _Grab? best;
    var bestDistance = PointerCtx.grabRadius;

    for (final node in frame.nodes) {
      final geometry = node.geometry;
      if (geometry == null) continue; // a group has no anchors to offer
      if (locked.contains(node.path.nodeId)) continue; // AC-2.2.6
      final worldToLocal = node.world.invert();
      if (worldToLocal == null) continue; // collapsed: never `invert()!`

      final authored = ctx.doc.nodeIndex[node.path.nodeId];
      if (authored is! PathNode) continue;
      // `kind` is topology, so it is read from the AUTHORED node, not from the
      // posed frame: a pose carries positions and tangents only.
      final kinds = <AnchorId, AnchorKind>{
        for (final a in authored.path.anchors) a.id: a.kind,
      };

      for (final anchor in geometry.anchors) {
        void consider(_Part part, Vec2 local) {
          final distance = ctx.screenDistanceTo(node.world.apply(local));
          if (distance >= bestDistance) return;
          bestDistance = distance;
          best = _Grab(
            part: part,
            node: node.path.nodeId,
            anchor: anchor.id,
            kind: kinds[anchor.id] ?? AnchorKind.corner,
            base: ctx.doc,
            worldToLocal: worldToLocal,
            anchorLocal: anchor.position,
            to: ctx.docPoint,
            moved: false,
          );
        }

        // The anchor first, and handles only when they are **strictly** closer:
        // a zero-length handle sits exactly on its anchor, and offering it as a
        // separate target would make the anchor ungrabbable on every straight
        // segment.
        consider(_Part.anchor, anchor.position);
        if (anchor.inTangent != Vec2.zero) {
          consider(_Part.inHandle, anchor.position + anchor.inTangent);
        }
        if (anchor.outTangent != Vec2.zero) {
          consider(_Part.outHandle, anchor.position + anchor.outTangent);
        }
      }
    }
    return best;
  }
}
