/// `GroupNode.clipChildren` — AC-2.1.6, in ONE place (docs/v3/04 §5).
///
/// Clipping is hierarchical and `Scene.drawOrder` is flat, so this file is the
/// join between the two. Both painters that can clip read it, for the same
/// reason both read [artboardClipRect]: three hand-rolled clips is the same
/// defect as three hand-rolled fits, one layer down.
library;

import 'dart:ui' as ui;

import 'package:anim_core/anim_core.dart';

import 'path_geometry.dart';

/// The window a clipping group confines its subtree to, in the group's **own
/// local space**.
///
/// ### The ruling, written down because the model cannot express the ideal
///
/// AC-2.1.6 says a child that "overflows its bounds" is clipped, so the group
/// needs *bounds of its own*. v3's `GroupNode` has `children` and
/// `clipChildren` and **no extent field** — no width/height, no rect. That
/// leaves exactly two candidate definitions:
///
///  1. **The union of its descendants' bounds.** Rejected: it is by
///     construction big enough to contain every descendant, so a clipping group
///     defined this way can never clip anything and the feature means nothing.
///     Every bounds-from-content definition has this property, at every depth.
///  2. **A frame the group carries independently of its content**, placed by
///     the group's own transform. The only extent this document model expresses
///     is `Document.artboard`, and the root of the tree *is* a `GroupNode`
///     whose extent is exactly the artboard (docs/v3/01 §3, "Container. Also
///     the artboard root."). So: **a clipping group's bounds are the artboard
///     rect in the group's own local space.**
///
/// That is After Effects' precomp rule — a precomp layer clips to the *comp's*
/// size, transformed by the layer's transform, not to the size of what is
/// inside it — and it is the closest thing to Figma's "clip content" a frame
/// with no width/height of its own can mean. The group's `Transform2` positions
/// and sizes the window: `position` moves it, `scale` resizes it, `rotation`
/// turns it (the window is clipped in local space, so a rotated group has a
/// rotated window, not an inflated upright one).
///
/// **What an author consequently cannot do yet:** give a group a window whose
/// size or aspect differs from the artboard *without also transforming its
/// children*, because the one matrix does both. A 100 × 50 window needs
/// `GroupNode` to carry its own rect — a field in `anim_core`, the file format
/// and the decoder, which is out of this package's reach. Until it exists,
/// authoring a clip window is authoring a group transform.
///
/// An artboard that is non-positive or non-finite yields [ui.Rect.zero]: a
/// frame with no area shows nothing. Failing closed is the honest reading of
/// "clip to this" — and it keeps a NaN out of `Canvas.clipRect`, which would
/// poison the layer rather than the node.
ui.Rect groupClipWindow(Vec2 artboard) {
  if (!artboard.x.isFinite || !artboard.y.isFinite) return ui.Rect.zero;
  if (artboard.x <= 0 || artboard.y <= 0) return ui.Rect.zero;
  return ui.Rect.fromLTWH(0, 0, artboard.x, artboard.y);
}

/// Every node confined by at least one clipping group → the groups that confine
/// it, **outermost first**. Nodes under no clip are absent, so an ordinary
/// document yields an empty map and costs the painters one `isEmpty` check.
///
/// A clipping group is **not** in its own chain: its clip opens at its first
/// child, not at its own slot. In the GEOMETRY layer a group draws nothing from
/// its own slot (groups have null geometry), so opening the clip there or at the
/// first child records the identical `clipRect`s — nothing is drawn between the
/// two points, so no `clipRect` that wraps a child moves. The OVERLAY is where
/// the difference is load-bearing: the group's own slot draws its selection
/// outline, stroked from the full descendant union ([selectionBounds]), and that
/// union routinely OVERFLOWS the group's artboard-sized window. Opening the
/// group's own clip before that draw truncated the outline — and, when the union
/// enclosed the window on every side, erased it entirely — while [hitTestScene]
/// still answered a click for the whole untruncated union. So the group's own
/// draw stays unclipped by its own window, and every descendant still enters it.
///
/// **The root is never a clipping group, whatever it is authored as.** The
/// artboard boundary belongs to [RenderMode] and to AC-1.1.3 alone: the editor
/// does not clip there, and honouring `root.clipChildren` would silently make
/// it, which is exactly the conflation of "the artboard clip" with "a clipping
/// group" that must not happen. The root is not a node the user selects, drags
/// or hit-tests either (see [hitTestScene]); this is the same exclusion.
///
/// Hierarchy comes from [doc] and every coordinate comes from the `Scene` — the
/// split [selectionBounds] and [hitTestScene] already make. Reading topology
/// here is not a second evaluator: nothing is re-derived, and there is no
/// second traversal that could disagree with `composeWorldA` about a position,
/// because this walk produces no positions. Rebuilt per paint and **never
/// cached** (docs/v3/08 §4).
Map<NodeId, List<NodeId>> clipChains(Document doc) {
  final out = <NodeId, List<NodeId>>{};
  _chain(doc.root, const <NodeId>[], out, isRoot: true);
  return out;
}

void _chain(
  Node node,
  List<NodeId> enclosing,
  Map<NodeId, List<NodeId>> out, {
  bool isRoot = false,
}) {
  // The node's OWN entry is the windows it is inside — its enclosing clips, and
  // never its own. A clipping group is confined by its ancestors, not by its own
  // window: its own-slot draw (nothing in the geometry layer; the selection
  // outline in the overlay) must be unclipped by the window it opens for its
  // children, or the outline of a selected clipping group is truncated to — and
  // often erased by — its own artboard-sized frame.
  if (enclosing.isNotEmpty) out[node.id] = enclosing;

  var confining = enclosing;
  if (!isRoot && node is GroupNode && node.clipChildren) {
    confining = List<NodeId>.unmodifiable(<NodeId>[...enclosing, node.id]);
  }
  if (node is GroupNode) {
    for (final child in node.children) {
      _chain(child, confining, out);
    }
  }
}

/// The clips a painter currently has open, as it walks the flat `drawOrder`.
///
/// `Scene.drawOrder` is a faithful pre-order flattening, but a flat list cannot
/// say where a subtree *ends* — `ScenePath` carries no depth and a group's
/// `ResolvedNode` carries no extent. So membership comes from [clipChains]
/// (topology, from the `Document`) and the window's placement comes from the
/// group's evaluated `world` (coordinates, from the `Scene`).
///
/// Every clip is one `save()`, closed with `restoreToCount`. The stack records
/// the save count taken **before** each `save()`, so [floor] can name the depth
/// a failed item must unwind to: everything that item leaked, and nothing its
/// ancestors legitimately opened. An unbalanced save here would leak a clip
/// into the *next* node, which is invisible on the node that caused it.
final class GroupClipStack {
  GroupClipStack._(
    this._chains,
    this._scene,
    this._window,
    this._base,
    this._floor,
  );

  /// Reads the save count [canvas] is at **now** as the floor, so it must be
  /// built after the caller has pushed whatever state wraps the whole layer
  /// (the fit transform, the export-preview artboard clip).
  ///
  /// [base] maps document space to the canvas's *current* space: identity when
  /// the caller has already applied the fit to the canvas (the geometry layer),
  /// the fit itself when it has not (the overlay draws in screen space).
  factory GroupClipStack.forCanvas(
    ui.Canvas canvas,
    Document document,
    Scene scene, {
    Affine base = Affine.identity,
  }) =>
      GroupClipStack._(
        clipChains(document),
        scene,
        groupClipWindow(document.artboard),
        base,
        canvas.getSaveCount(),
      );

  final Map<NodeId, List<NodeId>> _chains;
  final Scene _scene;
  final ui.Rect _window;
  final Affine _base;
  final int _floor;

  final List<NodeId> _open = <NodeId>[];
  final List<int> _depths = <int>[];

  /// The save count an item that threw must be unwound to.
  int get floor => _depths.isEmpty ? _floor : _depths.last + 1;

  /// True when this document has no clipping group at all — the common case,
  /// and then [enter] never touches the canvas.
  bool get isEmpty => _chains.isEmpty;

  /// Makes the canvas's open clips exactly the chain confining [path]: closes
  /// the ones it has left, opens the ones it has entered, leaves the shared
  /// prefix alone. Closing on the way out is what stops a group's clip leaking
  /// onto the sibling painted after it.
  void enter(ui.Canvas canvas, ScenePath path) {
    final chain = _chains[path.nodeId] ?? const <NodeId>[];

    var shared = 0;
    while (shared < _open.length &&
        shared < chain.length &&
        _open[shared] == chain[shared]) {
      shared++;
    }
    while (_open.length > shared) {
      _open.removeLast();
      canvas.restoreToCount(_depths.removeLast());
    }

    for (var k = shared; k < chain.length; k++) {
      final depth = canvas.getSaveCount();
      canvas.save();
      // Recorded only once the clip is actually applied: if `_apply` throws,
      // `floor` still names the depth below this save, so the item's catch
      // unwinds it and the stack stays honest about what is open.
      _apply(canvas, _scene.byPath[ScenePath(chain[k])]?.world);
      _depths.add(depth);
      _open.add(chain[k]);
    }
  }

  /// Closes every open clip. The layer's own `restore` would do it, but the
  /// overlay keeps drawing after the node loop and its pending markers are tool
  /// state, not document content — they are not inside anybody's group.
  void closeAll(ui.Canvas canvas) {
    _open.clear();
    while (_depths.isNotEmpty) {
      canvas.restoreToCount(_depths.removeLast());
    }
  }

  /// Clips to [world]'s window, leaving the canvas in the space it was in.
  ///
  /// The window is rectangular in the group's **local** space, so it is clipped
  /// there and the matrix is then undone — a group with rotation or skew gets
  /// its real slanted window rather than the upright box around it.
  void _apply(ui.Canvas canvas, Affine? world) {
    // A group whose matrix collapsed (an animator keyed scale to 0) has a
    // window of no area, so its subtree shows nothing. Fail CLOSED: the author
    // asked for the content to be confined, and an unplaceable window confines
    // it to nothing. Never `invert()!` (docs/v3/08 §4).
    if (world == null) {
      canvas.clipRect(ui.Rect.zero);
      return;
    }
    final toCanvas = _base.mul(world);
    final back = toCanvas.invert();
    if (back == null || !isPlaceable(toCanvas)) {
      canvas.clipRect(ui.Rect.zero);
      return;
    }
    canvas.transform(affineToMatrix4(toCanvas));
    canvas.clipRect(_window);
    canvas.transform(affineToMatrix4(back));
  }
}
