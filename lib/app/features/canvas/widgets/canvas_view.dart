import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:anim_render/anim_render.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_controller.dart';
import '../commands.dart';
import '../providers.dart';

/// The canvas panel: three stacked painters and two gestures.
///
/// **M0 scope, and deliberately crude.** The pen is three clicks with no
/// handles and no snapping; the only other gesture is dragging an anchor. Depth
/// here is the stated failure mode for this milestone (docs/v3/06) — what has
/// to be right on day one is that anchors get stable ids, that screen→artboard
/// is the *inverse of the painter's own* matrix, and that a drag at the
/// playhead writes a keyframe rather than the rest pose.
class CanvasView extends ConsumerStatefulWidget {
  const CanvasView({required this.projectId, super.key});

  final String projectId;

  /// Incremented once per `build`, for the test that proves scrubbing the
  /// playhead rebuilds **nothing**.
  ///
  /// That test is the whole justification for `playheadProvider` being a
  /// `ValueNotifier` rather than provider state (docs/v3/04 §4), and it cannot
  /// be written from the outside: a rebuild that produces identical pixels is
  /// invisible to every widget-finder assertion, which is exactly how a rebuild
  /// storm survives a green test suite.
  @visibleForTesting
  static int debugBuildCount = 0;

  @override
  ConsumerState<CanvasView> createState() => _CanvasViewState();
}

/// An anchor drag in flight.
///
/// Private to the tool, exactly as docs/v3/08 §2 requires: never in `Document`
/// (a document holding half a gesture cannot be reloaded, and autosave would
/// persist it) and never in `EditorState` (every panel watching editor state
/// would then rebuild 60 times a second while the pointer moves).
@immutable
class _AnchorDrag {
  const _AnchorDrag({
    required this.node,
    required this.anchor,
    required this.base,
    required this.screenToArtboard,
    required this.worldToLocal,
    required this.position,
  });

  final NodeId node;
  final AnchorId anchor;

  /// The document the gesture started from, captured once.
  ///
  /// The live preview re-applies the move to *this* document on every pointer
  /// event rather than to the current one, for the same reason
  /// [screenToArtboard] is captured once: a gesture must be a function of what
  /// the user grabbed, not of whatever arrived underneath it mid-drag. It also
  /// makes the preview idempotent — re-applying to the previous preview would
  /// compound 200 pointer moves into 200 stacked edits.
  final Document base;

  /// Captured once, at drag start, from the *same* [artboardFit] the painters
  /// used. Recomputing it per pointer event would be a second mapping, and two
  /// mappings is how a drag lands where the pointer is not.
  final Affine screenToArtboard;

  /// The node's world matrix, inverted. `PathOps.moveAnchor` writes a **local**
  /// position, so the artboard-space pointer has to come back through the
  /// node's own transform. At M0 every node is an untransformed child of the
  /// root and this is the identity — which is precisely why it must be written
  /// now, while it is provably correct and free, rather than discovered at M2
  /// as a mysterious offset.
  final Affine worldToLocal;

  /// Live pointer position in **artboard** space.
  final Vec2 position;

  _AnchorDrag at(Vec2 next) => _AnchorDrag(
        node: node,
        anchor: anchor,
        base: base,
        screenToArtboard: screenToArtboard,
        worldToLocal: worldToLocal,
        position: next,
      );
}

class _CanvasViewState extends ConsumerState<CanvasView> {
  /// Artboard-space clicks collected so far. Ephemeral by construction.
  final List<Vec2> _pending = [];

  _AnchorDrag? _drag;

  /// The document as it *would* be if the in-flight drag were released now.
  ///
  /// Ephemeral and speculative: it is painted, never saved, never handed to a
  /// provider, and thrown away on release — so it is drag state, and drag state
  /// is a private field of the tool (docs/v3/08 §2). What makes it honest is
  /// that it is produced by the *same* `PathOps.moveAnchor` the release will
  /// commit, so the preview cannot drift from the result. A second
  /// "preview-only" geometry path would be a second evaluator, which is the bug
  /// class this rewrite exists to remove (docs/v3/08 §4).
  Document? _preview;

  static const int _clicksPerShape = 3;

  /// Screen-space grab radius. Generous on purpose: the overlay's handles are
  /// 3.5 px, and a hit target the size of the thing you can see is a hit target
  /// nobody can hit.
  static const double _grabRadius = 14.0;

  /// The playhead, normalised into the range every op and mix requires.
  ///
  /// One definition, used by the hit-test, the preview and the commit, so the
  /// three cannot disagree about which keyframe the gesture belongs to.
  double _playheadT() {
    final t = ref.read(playheadProvider).value;
    return t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
  }

  List<AnimationMix> _mix(AnimationId? animation) {
    final anim = animation;
    if (anim == null) return const <AnimationMix>[];
    return <AnimationMix>[AnimationMix(anim, _playheadT())];
  }

  /// Speculatively applies [drag] so the canvas can draw the result live.
  ///
  /// The catch is at the **widget boundary**, which is where docs/v3/08 §1 puts
  /// containment — never inside `anim_core`. `PathOps.moveAnchor` throws
  /// `ArgumentError` when the node or anchor has gone (a delete landing mid-drag
  /// at M2, say); losing the preview for that frame is the right cost, and the
  /// `assert` keeps it loud in debug rather than a silently frozen shape.
  Document? _previewOf(_AnchorDrag drag) {
    try {
      return PathOps.moveAnchor(
        drag.base,
        drag.node,
        drag.anchor,
        drag.worldToLocal.apply(drag.position),
        atT: _playheadT(),
      );
    } on ArgumentError catch (e) {
      assert(false, 'anchor drag preview rejected by an op: $e');
      return null;
    }
  }

  void _report(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// The pen commits on tap **up**, never on tap down.
  ///
  /// `BaseTapGestureRecognizer` calls `onTapDown` from `didExceedDeadline()`
  /// after `kPressTimeout` (100 ms) whether or not the tap goes on to lose the
  /// arena to the pan — so wiring the pen to tap-down means every anchor drag
  /// where the user presses and hesitates for a tenth of a second *also*
  /// deposits a pen point, and three unhurried drags commit a phantom triangle
  /// whose vertices are the three grab points. `onTapUp` fires only when the
  /// tap recognizer wins, which is exactly the "this gesture was not a drag"
  /// answer the pen needs, and it is the answer the arena already computes.
  ///
  /// The repo's own drag tests cannot see the difference — `tester.drag`
  /// synthesizes down/move/up with no elapsed time, so the deadline never
  /// fires. `timeline_test.dart`'s slow-drag test pumps real time for that
  /// reason.
  Future<void> _onTapUp(TapUpDetails details, Document doc, Size size) async {
    // Screen → artboard through the *inverse of the same* Affine the painter
    // used. Anything else and the shape lands where the click was not — that is
    // legacy's y-scaled-by-width bug, and it is golden-tested on the
    // 450.2 × 250.4 artboard.
    final inverse = artboardFit(doc.artboard, size).invert();
    if (inverse == null) return; // degenerate artboard: nothing to draw into
    final p = inverse.apply(_vec(details.localPosition));

    setState(() => _pending.add(p));
    if (_pending.length < _clicksPerShape) return;

    final points = List<Vec2>.from(_pending);
    setState(_pending.clear);
    _report(await CanvasCommands(ref, widget.projectId).addPath(points));
  }

  void _onPanStart(
    DragStartDetails details,
    Document doc,
    Size size,
    AnimationId? animation,
  ) {
    final fit = artboardFit(doc.artboard, size);
    final inverse = fit.invert();
    if (inverse == null) return; // early return, never `invert()!`

    // Stages 1–3 only, matching [OverlayPainter] exactly. The handles the user
    // is aiming at are drawn from this frame, so the hit-test has to be drawn
    // from it too — a hit-test derived from the rest pose would miss every
    // handle the moment the playhead leaves a keyframe.
    final frame =
        composeWorldA(resolvePose(sampleTracks(doc, _mix(animation))));

    _AnchorDrag? best;
    var bestDistance = _grabRadius;

    for (final node in frame.nodes) {
      final geometry = node.geometry;
      if (geometry == null) continue; // a group has no anchors to offer
      final worldToLocal = node.world.invert();
      if (worldToLocal == null) continue;

      final toScreen = fit.mul(node.world);
      for (final anchor in geometry.anchors) {
        final at = toScreen.apply(anchor.position);
        if (!at.x.isFinite || !at.y.isFinite) continue;
        final distance = (Offset(at.x, at.y) - details.localPosition).distance;
        if (distance >= bestDistance) continue;
        bestDistance = distance;
        best = _AnchorDrag(
          node: node.path.nodeId,
          anchor: anchor.id,
          base: doc,
          screenToArtboard: inverse,
          worldToLocal: worldToLocal,
          position: inverse.apply(_vec(details.localPosition)),
        );
      }
    }

    if (best == null) return; // a drag on empty canvas does nothing at M0
    final started = best;
    setState(() {
      _drag = started;
      _preview = _previewOf(started);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;
    final moved =
        drag.at(drag.screenToArtboard.apply(_vec(details.localPosition)));
    setState(() {
      _drag = moved;
      _preview = _previewOf(moved);
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    final drag = _drag;
    if (drag == null) return;
    // Both cleared together: the preview exists only to stand in for a document
    // that has not been written yet, so it must not outlive the write by even
    // one frame or the canvas shows a stale ghost of the edit it just committed.
    setState(() {
      _drag = null;
      _preview = null;
    });

    // ONE command, on release. `atT` is the live playhead, so the drag writes
    // into the keyframe at the time the user is looking at (F4.2 + F6.1, thin).
    _report(await CanvasCommands(ref, widget.projectId).moveAnchorAt(
      drag.node,
      drag.anchor,
      drag.worldToLocal.apply(drag.position),
      atT: _playheadT(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    CanvasView.debugBuildCount++;

    // Named slices only (docs/v3/08 §2). None of these change while the
    // playhead moves, which is why a scrub rebuilds nothing here.
    final doc = ref.watch(canvasDocumentProvider(widget.projectId));
    final board = ref.watch(canvasBackgroundProvider(widget.projectId));
    final nodes = ref.watch(canvasNodeCountProvider(widget.projectId));
    final animation = ref.watch(activeAnimationProvider(widget.projectId));
    final playhead = ref.watch(playheadProvider);

    if (doc == null || board == null) return const SizedBox.expand();
    final scheme = Theme.of(context).colorScheme;

    final drag = _drag;

    // WHAT THE PAINTERS SEE. During a drag this is the speculative document, so
    // the whole shape follows the anchor live instead of a lone dot sliding
    // across a stale outline. It is the committed document at every other
    // moment, and it is never the thing that gets saved.
    final painted = _preview ?? doc;

    // The preview mints its own `Animation` when the document had none, so the
    // mix has to name *that* one. Passing the committed document's id would
    // point the evaluator at an animation the painted document does not
    // contain, and the canvas would quietly fall back to the rest pose — the
    // failure would look exactly like "the drag preview does not work".
    final paintedAnimation =
        _preview == null ? animation : _preview?.defaultAnimationId;

    final markers = <Vec2>[
      ..._pending,
      // The grabbed anchor keeps a marker on top of the moved geometry: it says
      // *which* anchor the gesture owns, which the geometry alone cannot.
      if (drag != null) drag.position,
    ];

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                key: const Key('canvas'),
                behavior: HitTestBehavior.opaque,
                // The grab is decided by what was under the pointer when it
                // went DOWN, not by where it had drifted to once the drag was
                // recognised. The default (`DragStartBehavior.start`) reports
                // the position after the ~20 px touch slop has been consumed,
                // which for direct manipulation means the user grabs whatever
                // is 20 px along their gesture — a handle they never aimed at,
                // or nothing at all.
                dragStartBehavior: DragStartBehavior.down,
                onTapUp: (d) => _onTapUp(d, doc, size),
                onPanStart: (d) => _onPanStart(d, doc, size, animation),
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                // Three painters, and they stay three (docs/v3/08 §2). Each in
                // its own RepaintBoundary so a playhead tick repaints layers 2
                // and 3 without touching layer 1, and so an overlay fault
                // cannot take the artboard — the thing the user needs in order
                // to see what went wrong — down with it.
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: BackgroundPainter(
                          artboard: board.$1,
                          background: board.$2,
                          edge: scheme.outlineVariant,
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: ArtboardPainter(
                          document: painted,
                          playhead: playhead,
                          animation: paintedAnimation,
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: OverlayPainter(
                          document: painted,
                          playhead: playhead,
                          animation: paintedAnimation,
                          anchor: scheme.surface,
                          anchorBorder: scheme.primary,
                          pendingColor: scheme.tertiary,
                          pending: markers,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        _ToolHint(remaining: _clicksPerShape - _pending.length, nodes: nodes),
      ],
    );
  }

  static Vec2 _vec(Offset o) => Vec2(o.dx, o.dy);
}

class _ToolHint extends StatelessWidget {
  const _ToolHint({required this.remaining, required this.nodes});

  final int remaining;
  final int nodes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: scheme.surfaceContainerHighest,
      child: Text(
        'Click $remaining more time${remaining == 1 ? '' : 's'} to add a '
        'triangle, or drag an anchor to pose it at the playhead · '
        '$nodes shape${nodes == 1 ? '' : 's'} in this document',
        key: const Key('tool-hint'),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
