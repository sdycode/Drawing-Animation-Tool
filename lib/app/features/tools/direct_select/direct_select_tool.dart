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
/// ## Pose, and keyframe-local — the three-way routing rule (AC-4.2.3)
///
/// Both ops are **pose** edits (docs/v3/01 §12): they change where an anchor
/// sits or where its handles point, never which anchors exist. The `AnchorId`
/// **sequence** is untouched by construction; neither op can change it. What
/// varies is the `atT` each edit carries, decided per gesture by [_poseTargetT]
/// off **one predicate — does the node carry a `path` track?** ([_hasPathTrack]):
///
/// - The node has **no `path` track** in the active animation → the edit is a
///   **rest-pose** edit (`atT: null`). No track is created (AC-4.2.3), so cycling
///   `AnchorKind` on a static shape — a non-animatable hint — can never seed an
///   animation.
/// - The node **has a `path` track** → the edit is **keyframe-local** at the
///   playhead (`atT: playhead`) — edit-at-keyframe (AC-4.2.1/2, AC-6.2.6): only
///   the keyframe at the playhead changes, every other keyframe stays
///   byte-identical. When a key is selected `EditorController.selectKeyframe` has
///   already snapped the playhead to its `t`, so `atT: playhead` lands on it.
///
/// **The routing is the track alone, never `selectedKeyframe`.** That selection
/// is a highlight, and a highlight nothing clears is what re-seeded a track after
/// one was deleted while its key stayed selected (AC-4.2.3's 2nd route) — see
/// [_hasPathTrack].
///
/// This replaced the M0/M2 auto-seed: `ctx.playhead` is never null (0.0 at
/// rest), so passing it on every edit silently seeded a one-key path track on
/// the first drag of any static shape. A *first* path keyframe is now created
/// deliberately — the inspector's **path diamond** (`KeyPathCommand`, the
/// geometry stopwatch) — never as a side effect of dragging an anchor.
///
/// `AnchorKind` is the exception to "pose only", and deliberately so: it is not
/// animatable (docs/v3/01 §7), so `setTangents` writes it onto the node's
/// `PathData` document-wide in **both** `atT` branches while the handle
/// correction it implies stays keyframe-local. Writing the kind does not, by
/// itself, seed a track — the rest-pose branch touches no `TrackSet`. The
/// renderer never reads `kind`; the invariants it names are baked into the
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

  /// `Esc` mid-drag **abandons the anchor/handle drag** (docs/v3/05 §5).
  ///
  /// It drops the in-flight [_Grab] so the release commits nothing —
  /// `onPointerUp` sees a null grab and returns null. Without it, `Esc` cleared
  /// the selection (the canvas fallback) but the pending `onPointerUp` still
  /// keyed a `MoveAnchorCommand` / `SetTangentsCommand` on release. Returning
  /// null with no effect lets the canvas also clear the selection.
  @override
  Command? onKey(ToolKey key, PointerCtx ctx) {
    if (key == ToolKey.escape && _grab != null) cancel();
    return null;
  }

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
        // affordance — while `smooth`/`symmetric` re-aim the existing pair. The
        // kind rides onto the node's PathData document-wide in either `atT`
        // branch; routing to the rest pose on a static shape is what keeps a
        // kind cycle from seeding a track (AC-4.2.3).
        kind: _nextKind[grab.kind] ?? AnchorKind.corner,
        atT: _poseTargetT(ctx, grab.node),
      );
    }

    if (grab.part == _Part.anchor) {
      return MoveAnchorCommand(
        grab.node,
        grab.anchor,
        grab.localPoint,
        atT: _poseTargetT(ctx, grab.node),
      );
    }
    return _tangentCommand(grab, ctx);
  }

  /// The `atT` a pose edit on [node] carries — the routing rule this tool's
  /// headline task fixes (AC-4.2.3; see the library doc).
  ///
  /// Keyframe-local at the playhead when the node already carries a `path` track
  /// in the active animation; otherwise the node's rest pose (`atT: null`), which
  /// touches no `TrackSet`.
  double? _poseTargetT(PointerCtx ctx, NodeId node) =>
      _hasPathTrack(ctx, node) ? ctx.playhead : null;

  /// **The one routing predicate**, a pure read: does [node] carry a `path`
  /// track in the animation the playhead addresses? `ctx.animation` is the
  /// active animation (`activeAnimationProvider`), which in v1 is the
  /// `defaultAnimationId` the pose op writes its keyframe into — so this asks
  /// exactly "would a keyframe-local edit here land on an existing track, or
  /// invent one?".
  ///
  /// **`selectedKeyframe` is deliberately NOT consulted.** It is a highlight, not
  /// the routing authority (AC-4.2.3): trusting it re-created a track after one
  /// was deleted (timeline `Shift+K`, the path diamond's remove) while its key
  /// stayed selected — a plain drag on the now-static node routed `atT: playhead`
  /// and silently seeded a track. When a track *does* exist and its key is
  /// selected, `selectKeyframe` has already snapped the playhead onto that key,
  /// so `atT: playhead` still lands on it with no extra check.
  bool _hasPathTrack(PointerCtx ctx, NodeId node) {
    final id = ctx.animation;
    if (id == null) return false;
    for (final animation in ctx.doc.animations) {
      if (animation.id == id) {
        return animation.tracksFor(node).pathTrack() != null;
      }
    }
    return false;
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
      atT: _poseTargetT(ctx, grab.node),
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
          atT: _poseTargetT(ctx, grab.node),
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
