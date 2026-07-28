/// One-way importer: the 8 legacy sample projects → v3 [Document] (docs/v3/02 §8).
///
/// **One-way, for the bundled samples only.** There is no v3 → legacy writer and
/// no general migration path: the legacy format has no version field, cannot
/// express a node added mid-animation (point counts are constant within every
/// section of every sample), and the shipped files are already corrupt
/// (scrambled frame order, duplicate positions, colliding project ids). This
/// reads those 8 files into clean v3 documents that become golden fixtures; it
/// is not a supported format.
///
/// It produces a [Document] and constructs [PathData] directly — the same kind
/// of "external data → geometry" route as `PathData.fromJson`, and it is on the
/// `boundary_test` allowlist for exactly that reason. Per-keyframe vertex-count
/// repair (a path the corpus never exercises, but AC-11.3.5 requires to exist)
/// routes through the shared arc-length machinery, the same correspondence
/// `PathOps.retopologize` uses.
library;

import '../animation.dart';
import '../document.dart';
import '../easing.dart';
import '../geom/arc_length.dart';
import '../node.dart';
import '../paint.dart';
import '../path.dart';
import '../primitives.dart';
import '../track.dart';
import '../uuid.dart';

final class LegacyImporter {
  const LegacyImporter._();

  /// The smallest gap that keeps two keyframes distinct in `t` after a duplicate
  /// `framePosition` is nudged apart (AC-11.3.3). Large enough to survive a JSON
  /// round-trip, small enough to be a visually instantaneous transition.
  static const double _epsilon = 1e-6;

  /// Legacy detection (docs/v3/02 §8): a `schemaVersion` is absent and the
  /// capital-S `iconSections` / `SingleFrameModel` shape is present.
  static bool isLegacy(Map<String, Object?> json) =>
      json['schemaVersion'] == null &&
      (json.containsKey('iconSections') || json.containsKey('SingleFrameModel'));

  /// Import [legacy] (a decoded legacy JSON map) into a v3 [Document] with a
  /// fresh id (legacy ids collide) and `schemaVersion == 3`.
  static Document import(Map<String, Object?> legacy) {
    final artboard =
        Vec2(_d(legacy['width'], 400), _d(legacy['height'], 400));
    final name = (legacy['projectName'] as String?)?.trim();
    var doc = Document.create(
      name: name == null || name.isEmpty ? 'Imported' : name,
      artboard: artboard,
    );

    final sections = (legacy['iconSections'] as List?) ?? const <Object?>[];
    final nodes = <Node>[];
    final tracksByNode = <NodeId, PathTrack>{};

    for (var s = 0; s < sections.length; s++) {
      final section = sections[s] as Map<String, Object?>;
      final frames = _sortedFrames(section['frames']);
      // A section with no usable geometry contributes no node (invariant P2: a
      // path needs at least two anchors).
      if (frames.isEmpty || frames.first.points.length < 2) continue;

      final nodeId = NodeId(uuidV4());
      final sectionName =
          (section['iconSectionName'] as String?) ?? 'Section $s';
      final fill = Fill(
        id: PaintId(uuidV4()),
        paint: SolidPaint(_parseArgb(section['color'])),
      );

      // The base topology is frame 0. Ids are minted by index — safe because
      // point counts are constant within every legacy section (docs/v3/02 §8);
      // the mismatch branch below is the defensive repair for anything else.
      final baseCount = frames.first.points.length;
      final anchorIds = <AnchorId>[
        for (var i = 0; i < baseCount; i++) AnchorId('n${s}a$i'),
      ];
      final node = PathNode(
        id: nodeId,
        name: sectionName,
        // Filled legacy shapes: closed so they fill and never render empty
        // (AC-11.3.2). `controlMidPoints` is `{}` in every legacy frame, so every
        // anchor is a corner with zero tangents.
        path: PathData(
          anchors: <Anchor>[
            for (var i = 0; i < baseCount; i++)
              Anchor(id: anchorIds[i], position: frames.first.points[i]),
          ],
          closed: true,
        ),
        fills: <Fill>[fill],
      );
      nodes.add(node);

      // A single-frame section is static: its rest pose (frame 0) is the whole
      // geometry, so it needs no track. Two or more frames animate.
      if (frames.length < 2) continue;

      final keys = <Keyframe<PathPose>>[];
      for (final f in frames) {
        // A frame with fewer than two points has no polyline to pose onto the
        // base topology — drop it rather than fabricate garbage (a 0-point frame
        // would also have no arc to resample). Corrupt legacy data, not the
        // corpus; totality is preserved (AC-11.3.5).
        if (f.points.length < 2) continue;
        keys.add(Keyframe<PathPose>(
          t: f.t,
          // AC-11.3.5: a frame whose vertex count disagrees with the base is
          // resampled to the base topology by arc length — the same
          // correspondence `PathOps.retopologize` uses — so every keyframe
          // shares the base AnchorId set (AC-4.3.6). The corpus never trips this;
          // it is the required defensive route.
          value: _poseOf(
            f.points.length == baseCount
                ? f.points
                : _resample(f.points, baseCount),
            anchorIds,
          ),
          easing: const LinearEasing(),
        ));
      }
      // If dropping degenerate frames left fewer than two keys, the node is
      // static (its rest pose, frame 0) rather than a one-key track.
      if (keys.length >= 2) tracksByNode[nodeId] = PathTrack(keys);
    }

    doc = doc.copyWith(root: doc.root.copyWith(children: nodes));

    if (tracksByNode.isNotEmpty) {
      final anim = doc.defaultAnimation!;
      doc = doc.copyWith(
        animations: <Animation>[
          anim.copyWith(
            tracks: Map<NodeId, TrackSet>.unmodifiable(<NodeId, TrackSet>{
              for (final e in tracksByNode.entries)
                e.key: TrackSet(<PropertyKey, Track>{
                  const PropertyKey(PropKey.path): e.value,
                }),
            }),
          ),
        ],
        defaultAnimationId: anim.id,
      );
    }

    return doc;
  }

  static PathPose _poseOf(List<Vec2> points, List<AnchorId> ids) =>
      PathPose(Map<AnchorId, AnchorPose>.unmodifiable(<AnchorId, AnchorPose>{
        for (var i = 0; i < ids.length; i++)
          ids[i]: AnchorPose(points[i], Vec2.zero, Vec2.zero),
      }));

  /// Every frame of a section as `(t, points)`, **sorted by `framePosition`**
  /// (never array order or `frameNo`, AC-11.3.4), with duplicate positions nudged
  /// apart into a strictly-increasing `t` sequence (AC-11.3.3). A key that cannot
  /// be separated below 1.0 (a run pinned at the very end) is dropped rather than
  /// left coincident.
  static List<_Frame> _sortedFrames(Object? raw) {
    final frames = <_Frame>[];
    for (final entry in (raw as List?) ?? const <Object?>[]) {
      final model = (entry as Map<String, Object?>)['SingleFrameModel']
          as Map<String, Object?>?;
      if (model == null) continue;
      final pts = (model['points'] as List?) ?? const <Object?>[];
      final points = <Vec2>[
        for (final p in pts)
          Vec2(_d((p as Map<String, Object?>)['x'], 0),
              _d(p['y'], 0)),
      ];
      frames.add(_Frame(
        (_d(model['framePosition'], 0) / 100.0).clamp(0.0, 1.0),
        points,
      ));
    }
    frames.sort((a, b) => a.t.compareTo(b.t));

    final out = <_Frame>[];
    var prev = double.negativeInfinity;
    for (final f in frames) {
      var t = f.t <= prev ? prev + _epsilon : f.t;
      if (t > 1.0) t = 1.0;
      if (t <= prev) continue; // pinned at 1.0 with no room — drop the duplicate
      out.add(_Frame(t, f.points));
      prev = t;
    }
    return out;
  }

  /// Resample [points] (a polyline) to [count] points evenly by arc length —
  /// the correspondence `retopologize` uses, applied at import for the
  /// AC-11.3.5 vertex-count-repair backstop.
  static List<Vec2> _resample(List<Vec2> points, int count) {
    // Degenerate input has no arc to walk. Callers already screen frames with
    // fewer than two points, but the fallback must never divide by zero
    // (`i % 0`) — repeat the sole point, or the origin for an empty list.
    if (points.length < 2 || count < 2) {
      final fill = points.isEmpty ? Vec2.zero : points.first;
      return <Vec2>[for (var i = 0; i < count; i++) fill];
    }
    final table = ArcTable.build(
      PathData(
        anchors: <Anchor>[
          for (var i = 0; i < points.length; i++)
            Anchor(id: AnchorId('r$i'), position: points[i]),
        ],
        closed: true,
      ),
    );
    final total = table.total;
    return <Vec2>[
      for (var i = 0; i < count; i++)
        total <= 0.0 ? points.first : table.pointAtFraction(i / count),
    ];
  }

  /// ARGB hex string (mixed case, e.g. `"fff50c10"` or `"FFFFC0CB"`) → [Rgba],
  /// parsed case-insensitively (AC — docs/v3/02 §8). Falls back to opaque mid-grey
  /// on a missing or malformed value so a shape never imports invisible.
  static Rgba _parseArgb(Object? raw) {
    final hex = raw is String ? raw.trim() : '';
    if (hex.length != 8) return const Rgba(0.5, 0.5, 0.5);
    final v = int.tryParse(hex, radix: 16);
    if (v == null) return const Rgba(0.5, 0.5, 0.5);
    final a = (v >> 24) & 0xff;
    final r = (v >> 16) & 0xff;
    final g = (v >> 8) & 0xff;
    final b = v & 0xff;
    return Rgba(r / 255.0, g / 255.0, b / 255.0, a / 255.0);
  }

  /// A legacy numeric field (int in 7 files, double in `circlebounce`) → double,
  /// with a fallback for a missing value.
  static double _d(Object? v, double fallback) =>
      v is num ? v.toDouble() : fallback;
}

class _Frame {
  _Frame(this.t, this.points);
  final double t;
  final List<Vec2> points;
}
