/// Fill and stroke mutations (docs/v3/01 §6, §12; F5.1).
///
/// The authoring API behind M3's paint inspector. Every method is
/// `Document → Document`, pure, and throws [ArgumentError] on an unknown node or
/// a node that is not a [PathNode] — ops throw loudly and the command layer
/// catches (docs/v3/08 §1).
///
/// ## Fills paint before strokes, always
///
/// `PathNode.fills` paint in list order, then `PathNode.strokes` paint in list
/// order (docs/v3/01 §6). That ordering is the **renderer's**, expressed by the
/// two fields being two fields. There is no `zIndex`, no `order`, and no op here
/// that reorders paint across the two lists, because there is nothing to
/// reorder: a stored ordering number beside an authoritative list is the derived
/// -state desync docs/v3/08 §4 forbids, and it is what legacy shipped beside
/// `children`.
///
/// ## No gradient authoring — this is the M3 scope-leak line
///
/// docs/v3/06 M3 names gradient authoring as one of the two most likely scope
/// leaks, and AC-5.1.3 is explicit: [LinearGradientPaint], [RadialGradientPaint]
/// and [GradientStop] exist in the sealed [PaintSource] type and are **rendered**
/// in v1, but nothing authors them. So there is no `setFillGradient`, no stop
/// list mutator, and no `PaintSource` parameter anywhere in this file — every
/// colour op takes an [Rgba] and produces a [SolidPaint]. Adding a variant to a
/// sealed type stays additive precisely because no authoring surface has to be
/// widened first.
///
/// The corollary is the one refusal in this file that will look surprising:
/// [PaintOps.setFillColor] and [PaintOps.setStrokeColor] **throw** when the
/// paint they would overwrite is not a [SolidPaint]. A colour picker silently
/// flattening an authored gradient — from a newer client, or from the import
/// path — into one flat colour is a destructive edit dressed up as a colour
/// change, and v1 has no UI that could put the gradient back.
///
/// ## No wholesale `setFills(List<Fill>)`
///
/// For the same structural reason `PathData`'s const constructor is private
/// (AC-4.3.8): a raw list write is a hole in the invariants. `PaintId` is a
/// track's `subjectId` (docs/v3/01 §7), so two fills sharing an id means two
/// paints driven by one `ColorTrack` with no way to tell them apart, and a list
/// write is the only way to reach that state. Ids are minted here, one per
/// [addFill] / [addStroke], from [uuidV4] — never from a list position, which is
/// the same rule [AnchorId] follows and for the same reason.
///
/// Removal takes the paint's tracks with it, across every animation: a
/// `fillColor:p-body` track whose fill no longer exists is dead weight that
/// nothing evaluates, nothing can address, and every future save carries.
library;

import '../animation.dart';
import '../document.dart';
import '../node.dart';
import '../paint.dart';
import '../primitives.dart';
import '../track.dart';
import '../uuid.dart';

abstract final class PaintOps {
  /// Append a solid [Fill] and return the document with the fill's fresh
  /// [PaintId] (AC-5.1.1).
  ///
  /// The id is returned rather than looked up afterwards because the caller
  /// needs it to address every subsequent edit — and because "the last fill in
  /// the list" is exactly the positional addressing docs/v3/01 §6 refuses.
  ///
  /// v1's UI exposes at most one fill, but `fills` is a list from day one and
  /// this op **appends**: a document from a newer client with two fills keeps
  /// both (AC-5.1.6), and widening the UI later is additive rather than a schema
  /// break.
  static (Document, PaintId) addFill(
    Document d,
    NodeId n, {
    Rgba color = Rgba.black,
    FillRule rule = FillRule.nonZero,
    double opacity = 1.0,
    bool visible = true,
  }) {
    _pathNode(d, n);
    final fill = Fill(
      id: PaintId(uuidV4()),
      paint: SolidPaint(color),
      rule: rule,
      opacity: _unit(opacity, 'opacity'),
      visible: visible,
    );
    return (
      d.copyWith(
        root: _replacePath(
            d.root, n, (p) => p.copyWith(fills: <Fill>[...p.fills, fill])),
      ),
      fill.id
    );
  }

  /// Remove the fill [id], and with it every track addressed to it.
  ///
  /// Throws [ArgumentError] when the node holds no such fill — a delete against
  /// a paint that is already gone is a UI that lost track of its own selection,
  /// and swallowing it hides the desync until something else reads the stale id.
  static Document removeFill(Document d, NodeId n, PaintId id) {
    final node = _pathNode(d, n);
    if (!node.fills.any((f) => f.id == id)) {
      throw ArgumentError.value(id.v, 'id', 'no such fill on node "${n.v}"');
    }
    return _dropTracks(
      d.copyWith(
        root: _replacePath(
            d.root,
            n,
            (p) => p.copyWith(fills: <Fill>[
                  for (final f in p.fills)
                    if (f.id != id) f
                ])),
      ),
      n,
      id,
    );
  }

  /// Replace fill [id]'s colour (AC-5.1.1).
  ///
  /// Throws when the fill's current paint is not a [SolidPaint] — see this
  /// library's doc comment: v1 has no gradient authoring, so overwriting one
  /// here would be a one-way destruction of geometry-adjacent authoring this
  /// build cannot recreate.
  static Document setFillColor(Document d, NodeId n, PaintId id, Rgba color) =>
      _mapFill(
          d,
          n,
          id,
          (f) => Fill(
                id: f.id,
                paint: SolidPaint(color),
                rule: f.rule,
                opacity: f.opacity,
                visible: f.visible,
              ),
          requireSolid: true);

  /// Toggle fill [id]'s winding rule (AC-5.1.4).
  static Document setFillRule(
          Document d, NodeId n, PaintId id, FillRule rule) =>
      _mapFill(
          d,
          n,
          id,
          (f) => Fill(
                id: f.id,
                paint: f.paint,
                rule: rule,
                opacity: f.opacity,
                visible: f.visible,
              ));

  /// Set fill [id]'s authored opacity, clamped to `0..1`.
  ///
  /// Clamped **at the mutation**, matching `NodeOps.setOpacity`: a track may
  /// legitimately overshoot through an easing curve and is clamped at read, but
  /// an authored `1.7` is a bad write and belongs rejected where it is made.
  static Document setFillOpacity(
          Document d, NodeId n, PaintId id, double opacity) =>
      _mapFill(
          d,
          n,
          id,
          (f) => Fill(
                id: f.id,
                paint: f.paint,
                rule: f.rule,
                opacity: _unit(opacity, 'opacity'),
                visible: f.visible,
              ));

  /// Show or hide fill [id] without discarding it.
  ///
  /// A hidden fill is not a removed fill: it keeps its [PaintId], so its tracks
  /// survive the toggle and come back with it. This is the affordance that stops
  /// a user deleting a fill to preview the shape without it.
  static Document setFillVisible(
          Document d, NodeId n, PaintId id, bool visible) =>
      _mapFill(
          d,
          n,
          id,
          (f) => Fill(
                id: f.id,
                paint: f.paint,
                rule: f.rule,
                opacity: f.opacity,
                visible: visible,
              ));

  /// Append a solid [Stroke] and return the document with its fresh [PaintId]
  /// (AC-5.1.2).
  ///
  /// Strokes paint after **all** fills regardless of when they were added — the
  /// order is structural, not authored.
  static (Document, PaintId) addStroke(
    Document d,
    NodeId n, {
    Rgba color = Rgba.black,
    double width = 1.0,
    StrokeCap cap = StrokeCap.butt,
    StrokeJoin join = StrokeJoin.miter,
    double miterLimit = 4.0,
    double opacity = 1.0,
    bool visible = true,
  }) {
    _pathNode(d, n);
    final stroke = Stroke(
      id: PaintId(uuidV4()),
      paint: SolidPaint(color),
      width: _nonNegative(width, 'width'),
      cap: cap,
      join: join,
      miterLimit: _atLeastOne(miterLimit, 'miterLimit'),
      opacity: _unit(opacity, 'opacity'),
      visible: visible,
    );
    return (
      d.copyWith(
        root: _replacePath(d.root, n,
            (p) => p.copyWith(strokes: <Stroke>[...p.strokes, stroke])),
      ),
      stroke.id
    );
  }

  /// Remove the stroke [id], and with it every track addressed to it.
  static Document removeStroke(Document d, NodeId n, PaintId id) {
    final node = _pathNode(d, n);
    if (!node.strokes.any((s) => s.id == id)) {
      throw ArgumentError.value(id.v, 'id', 'no such stroke on node "${n.v}"');
    }
    return _dropTracks(
      d.copyWith(
        root: _replacePath(
            d.root,
            n,
            (p) => p.copyWith(strokes: <Stroke>[
                  for (final s in p.strokes)
                    if (s.id != id) s
                ])),
      ),
      n,
      id,
    );
  }

  /// Replace stroke [id]'s colour. Refuses a non-[SolidPaint] for the reason
  /// [setFillColor] does.
  static Document setStrokeColor(
          Document d, NodeId n, PaintId id, Rgba color) =>
      _mapStroke(d, n, id, (s) => _stroke(s, paint: SolidPaint(color)),
          requireSolid: true);

  /// Set stroke [id]'s width in node-local units.
  ///
  /// Zero is legal and means a hairline the renderer draws at its thinnest;
  /// negative is not a thin stroke, it is a caller bug, and it reaches the
  /// rasteriser as an inverted outline.
  static Document setStrokeWidth(
          Document d, NodeId n, PaintId id, double width) =>
      _mapStroke(
          d, n, id, (s) => _stroke(s, width: _nonNegative(width, 'width')));

  /// Set stroke [id]'s end cap.
  static Document setStrokeCap(
          Document d, NodeId n, PaintId id, StrokeCap cap) =>
      _mapStroke(d, n, id, (s) => _stroke(s, cap: cap));

  /// Set stroke [id]'s corner join.
  static Document setStrokeJoin(
          Document d, NodeId n, PaintId id, StrokeJoin join) =>
      _mapStroke(d, n, id, (s) => _stroke(s, join: join));

  /// Set stroke [id]'s miter limit — the ratio at which a [StrokeJoin.miter]
  /// spike is cut back to a bevel.
  ///
  /// It is a ratio of miter length to stroke width, so values below `1` describe
  /// a miter shorter than the stroke is wide: geometrically meaningless, and the
  /// rasteriser's own answer to it varies by backend.
  static Document setStrokeMiterLimit(
          Document d, NodeId n, PaintId id, double miterLimit) =>
      _mapStroke(d, n, id,
          (s) => _stroke(s, miterLimit: _atLeastOne(miterLimit, 'miterLimit')));

  /// Set stroke [id]'s authored opacity, clamped to `0..1`.
  static Document setStrokeOpacity(
          Document d, NodeId n, PaintId id, double opacity) =>
      _mapStroke(
          d, n, id, (s) => _stroke(s, opacity: _unit(opacity, 'opacity')));

  /// Show or hide stroke [id] without discarding it or its tracks.
  static Document setStrokeVisible(
          Document d, NodeId n, PaintId id, bool visible) =>
      _mapStroke(d, n, id, (s) => _stroke(s, visible: visible));
}

/// [Stroke] has no `copyWith`, and adding one to the model type would put an
/// editing affordance on a value the evaluator reads — this keeps it in the ops
/// layer where mutation belongs.
Stroke _stroke(
  Stroke s, {
  PaintSource? paint,
  double? width,
  StrokeCap? cap,
  StrokeJoin? join,
  double? miterLimit,
  double? opacity,
  bool? visible,
}) =>
    Stroke(
      id: s.id,
      paint: paint ?? s.paint,
      width: width ?? s.width,
      cap: cap ?? s.cap,
      join: join ?? s.join,
      miterLimit: miterLimit ?? s.miterLimit,
      opacity: opacity ?? s.opacity,
      visible: visible ?? s.visible,
    );

/// [n] as a [PathNode], or a loud refusal. Paint hangs off path nodes only: a
/// group has no outline to fill, and inventing one there would put geometry on
/// the container type.
PathNode _pathNode(Document d, NodeId n) {
  final found = d.nodeIndex[n];
  if (found is! PathNode) {
    throw ArgumentError.value(
        n.v, 'node', found == null ? 'no such node' : 'is not a path node');
  }
  return found;
}

Document _mapFill(
  Document d,
  NodeId n,
  PaintId id,
  Fill Function(Fill) edit, {
  bool requireSolid = false,
}) {
  final node = _pathNode(d, n);
  final index = node.fills.indexWhere((f) => f.id == id);
  if (index < 0) {
    throw ArgumentError.value(id.v, 'id', 'no such fill on node "${n.v}"');
  }
  if (requireSolid) _solidOnly(node.fills[index].paint, 'fill', id);
  return d.copyWith(
    root: _replacePath(
        d.root,
        n,
        (p) => p.copyWith(fills: <Fill>[
              for (final f in p.fills)
                if (f.id == id) edit(f) else f
            ])),
  );
}

Document _mapStroke(
  Document d,
  NodeId n,
  PaintId id,
  Stroke Function(Stroke) edit, {
  bool requireSolid = false,
}) {
  final node = _pathNode(d, n);
  final index = node.strokes.indexWhere((s) => s.id == id);
  if (index < 0) {
    throw ArgumentError.value(id.v, 'id', 'no such stroke on node "${n.v}"');
  }
  if (requireSolid) _solidOnly(node.strokes[index].paint, 'stroke', id);
  return d.copyWith(
    root: _replacePath(
        d.root,
        n,
        (p) => p.copyWith(strokes: <Stroke>[
              for (final s in p.strokes)
                if (s.id == id) edit(s) else s
            ])),
  );
}

/// The gradient guard (AC-5.1.3). See this library's doc comment.
void _solidOnly(PaintSource paint, String what, PaintId id) {
  if (paint is SolidPaint) return;
  throw ArgumentError.value(
      id.v,
      'id',
      'the $what carries a ${paint.runtimeType}; v1 authors solid paint only '
          '(AC-5.1.3), and overwriting it with a colour would destroy authoring '
          'this build cannot recreate');
}

/// Drop every [PropertyKey] whose `subjectId` is the removed paint, in every
/// animation. Orphan tracks are unreachable — nothing evaluates them and no UI
/// can address them — so keeping them only grows the saved document.
Document _dropTracks(Document d, NodeId n, PaintId id) {
  final animations = <Animation>[];
  var changed = false;
  for (final animation in d.animations) {
    final tracks = animation.tracksFor(n);
    final kept = <PropertyKey, Track>{
      for (final e in tracks.byKey.entries)
        if (e.key.subjectId != id.v) e.key: e.value,
    };
    if (kept.length == tracks.byKey.length) {
      animations.add(animation);
      continue;
    }
    changed = true;
    animations.add(animation.copyWith(
      tracks: Map.unmodifiable(<NodeId, TrackSet>{
        ...animation.tracks,
        n: TrackSet(Map.unmodifiable(kept), unknownKeys: tracks.unknownKeys),
      }),
    ));
  }
  return changed ? d.copyWith(animations: animations) : d;
}

/// Rebuilds the tree with one [PathNode] replaced.
///
/// Typed on [PathNode] rather than [Node] so there is no `as` on the way in and
/// no way to swap a node for one of a different kind by accident. The twin of
/// `path_ops.dart`'s helper; both stay private because a shared public
/// tree-splicer is the grab-bag docs/v3/08 §4 forbids.
GroupNode _replacePath(
        GroupNode root, NodeId id, PathNode Function(PathNode) edit) =>
    root.copyWith(children: <Node>[
      for (final child in root.children)
        switch (child) {
          final PathNode p when p.id == id => edit(p),
          final GroupNode g => _replacePath(g, id, edit),
          _ => child,
        },
    ]);

double _unit(double v, String name) {
  if (v.isNaN) throw ArgumentError.value(v, name, 'must be a number');
  return v.clamp(0.0, 1.0);
}

double _nonNegative(double v, String name) {
  if (v.isNaN || v < 0.0 || v.isInfinite) {
    throw ArgumentError.value(v, name, 'must be finite and >= 0');
  }
  return v;
}

double _atLeastOne(double v, String name) {
  if (v.isNaN || v < 1.0 || v.isInfinite) {
    throw ArgumentError.value(v, name, 'must be finite and >= 1');
  }
  return v;
}
