import 'package:anim_core/anim_core.dart';
import 'package:anim_render/anim_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import 'document_controller.dart';

/// Screen 2 — the editor (docs/v3/05 §2).
///
/// **M0 scope, and deliberately crude.** The pen tool is three clicks with no
/// handles, no snapping and no selection; the timeline does not exist yet.
/// Depth here is the stated failure mode for this milestone — what has to be
/// right on day one is that anchors get stable ids and that the document
/// round-trips, not that the drawing experience is good.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({required this.projectId, super.key});

  final String projectId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  /// Artboard-space clicks collected so far. Ephemeral by construction: it
  /// lives in the widget, never in the `Document`.
  final List<Vec2> _pending = [];

  static const _clicksPerShape = 3;

  Future<void> _onTapDown(
      TapDownDetails details, Document doc, Size size) async {
    // Screen → artboard through the *inverse of the same* Affine the painter
    // used. Anything else and the shape lands where the click was not.
    final inverse = artboardFit(doc.artboard, size).invert();
    if (inverse == null) return; // degenerate artboard: nothing to draw into
    final p = inverse.apply(
      Vec2(details.localPosition.dx, details.localPosition.dy),
    );

    setState(() => _pending.add(p));
    if (_pending.length < _clicksPerShape) return;

    final points = List<Vec2>.from(_pending);
    _pending.clear();
    await _commit(points);
  }

  Future<void> _commit(List<Vec2> points) async {
    final node = PathNode(
      id: NodeId(uuidV4()),
      name: 'Path',
      // One fresh AnchorId per point. Minted here, once, and never derived from
      // the loop index — an index-derived id is the legacy defect wearing a
      // different hat.
      path: PathData(
        anchors: [
          for (final p in points) Anchor(id: AnchorId(uuidV4()), position: p),
        ],
        closed: true,
      ),
      fills: const [
        // One hard-coded colour at M0. A paint UI is M3.
        Fill(
          id: PaintId('p-body'),
          paint: SolidPaint(Rgba(0.35, 0.55, 0.95, 1.0)),
        ),
      ],
      strokes: const [
        Stroke(
          id: PaintId('p-ink'),
          paint: SolidPaint(Rgba(0.05, 0.05, 0.08, 1.0)),
          width: 2.0,
          join: StrokeJoin.round,
        ),
      ],
    );

    try {
      await ref
          .read(documentControllerProvider(widget.projectId).notifier)
          .addNode(node);
    } on StoreException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(documentControllerProvider(widget.projectId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.name ?? 'Editor'),
        actions: [
          if (async.valueOrNull != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Center(
                child: Text(
                  'rev ${async.requireValue.rev}',
                  key: const Key('editor-rev'),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e is StoreException
                  ? e.failure.message
                  : 'Could not open this project.',
              key: const Key('editor-error'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        data: (doc) => Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    key: const Key('canvas'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _onTapDown(d, doc, size),
                    child: CustomPaint(
                      size: size,
                      painter: _CanvasPainter(
                        document: doc,
                        pending: _pending,
                        chrome: scheme.outlineVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
            _ToolHint(
              remaining: _clicksPerShape - _pending.length,
              nodes: doc.root.children.length,
            ),
          ],
        ),
      ),
    );
  }
}

/// The document, plus the in-progress click markers.
///
/// Pending points are drawn *over* the document rather than inserted into it:
/// an unfinished shape is ephemeral editor state, and a document that contains
/// half a gesture is a document that cannot be reloaded.
class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.document,
    required this.pending,
    required this.chrome,
  });

  final Document document;
  final List<Vec2> pending;
  final Color chrome;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = artboardFit(document.artboard, size);

    // The artboard's own edge, so an empty document is still visibly a canvas
    // of a definite size rather than a void.
    final board = Rect.fromPoints(
      _offset(fit.apply(Vec2.zero)),
      _offset(fit.apply(document.artboard)),
    );
    canvas.drawRect(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = chrome,
    );

    DocumentPainter(document: document).paint(canvas, size);

    for (final p in pending) {
      canvas.drawCircle(
        _offset(fit.apply(p)),
        4,
        Paint()..color = const Color(0xFFFFAB40),
      );
    }
  }

  static Offset _offset(Vec2 v) => Offset(v.x, v.y);

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      !identical(old.document, document) ||
      old.pending.length != pending.length ||
      old.chrome != chrome;
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
        'triangle · $nodes shape${nodes == 1 ? '' : 's'} in this document',
        key: const Key('tool-hint'),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
