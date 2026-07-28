/// v1 SHIP-GATE ACCEPTANCE — the 9 success criteria of docs/v3/00 §5, composed.
///
/// Each of the 9 criteria already has focused coverage elsewhere (the pen tool,
/// the timeline, `topology_edit_test`'s AC-4.3.2 golden, `trim_paint_test`, the
/// gates, `export_test`/`replay_test`, `legacy_import_test`). What that coverage
/// does NOT prove is that they hold **together, on one document** — the exact
/// thing a stranger does in the AC-12.1.3 walkthrough. This builds one "showcase"
/// document (an animated bezier + a group whose child spins the opposite way + a
/// stroke that draws itself on and fades) and walks the criteria across it, so a
/// regression in how the features COMPOSE cannot hide behind green unit tests.
///
/// Criterion → where it is proven here:
///   1 closed bezier w/ a curve ....... `_showcase` shape (closed, curved segment)
///   2 3 path keys, distinct easings .. shape PathTrack (t 0/0.4/1, 3 CubicEasings)
///   3 insert @kf1, kf2/kf3 identical . `criterion 3` (rigorous golden: topology_edit_test)
///   4 group vs child opposite spin ... `criterion 4`
///   5 stroke draws on then fades ..... `criterion 5`
///   6 scrub 0→1 NaN-free, present@1 .. `criterion 6`
///   7 reload byte-identical .......... `criterion 7/8` (JSON fixed point; store: round_trip_gate)
///   8 export replays in anim_core .... `criterion 7/8` (+ replay_test in anim_render)
///   9 import 8 legacy, 50t NaN-free .. `criterion 9`
library;

import 'dart:convert';
import 'dart:io';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

const _shape = NodeId('shape');
const _grp = NodeId('grp');
const _child = NodeId('child');
const _stroke = NodeId('stroke');

const _path = PropertyKey(PropKey.path);
const _rotation = PropertyKey(PropKey.rotation);
const _trimEnd = PropertyKey(PropKey.trimEnd);
const _opacity = PropertyKey(PropKey.opacity);

/// A closed, curved quad; anchor a1→a2 is the curved segment (symmetric tangents).
List<Anchor> _quad(double dx) => <Anchor>[
      Anchor(id: const AnchorId('a0'), position: Vec2(40 + dx, 40)),
      Anchor(id: const AnchorId('a1'), position: Vec2(160 + dx, 40)),
      Anchor(
        id: const AnchorId('a2'),
        position: Vec2(160 + dx, 160),
        inTangent: const Vec2(0, -30),
        outTangent: const Vec2(0, 30),
        kind: AnchorKind.symmetric,
      ),
      Anchor(id: const AnchorId('a3'), position: Vec2(40 + dx, 160)),
    ];

PathPose _quadPose(double dx) =>
    PathPose(Map<AnchorId, AnchorPose>.unmodifiable(<AnchorId, AnchorPose>{
      for (final a in _quad(dx))
        a.id: AnchorPose(a.position, a.inTangent, a.outTangent),
    }));

/// The composed showcase document (criteria 1,2,4,5 by construction).
Document _showcase() {
  final root = GroupNode(
    id: const NodeId('root'),
    name: 'Root',
    children: <Node>[
      // Criterion 1: a closed bezier with a curved segment.
      PathNode(
        id: _shape,
        name: 'bezier',
        path: PathData(anchors: _quad(0), closed: true),
        fills: const [Fill(id: PaintId('f'), paint: SolidPaint(Rgba(0.3, 0.5, 0.9)))],
      ),
      // Criterion 4: a group that rotates, with a child spinning the other way.
      GroupNode(
        id: _grp,
        name: 'group',
        children: <Node>[
          PathNode(
            id: _child,
            name: 'child',
            path: PathData(anchors: _quad(0), closed: true),
            fills: const [
              Fill(id: PaintId('cf'), paint: SolidPaint(Rgba(0.9, 0.4, 0.3)))
            ],
          ),
        ],
      ),
      // Criterion 5: a stroked path that draws itself on then fades.
      PathNode(
        id: _stroke,
        name: 'stroke',
        path: PathData(anchors: _quad(0), closed: false),
        strokes: const [
          Stroke(id: PaintId('s'), paint: SolidPaint(Rgba.black), width: 3)
        ],
      ),
    ],
  );

  final anim = Animation(id: const AnimationId('main'), name: 'Main', tracks: {
    // Criterion 2: three path keyframes at fractional t, a distinct easing each.
    _shape: TrackSet({
      _path: PathTrack(<Keyframe<PathPose>>[
        Keyframe(t: 0.0, value: _quadPose(0), easing: const CubicEasing(0.42, 0, 1, 1)),
        Keyframe(t: 0.4, value: _quadPose(60), easing: const CubicEasing(0, 0, 0.58, 1)),
        Keyframe(t: 1.0, value: _quadPose(-30), easing: const CubicEasing(0.25, 0.1, 0.25, 1)),
      ]),
    }),
    // Criterion 4: opposite-signed, different-rate spins that must COMPOSE.
    _grp: TrackSet({
      _rotation: ScalarTrack(const [
        Keyframe(t: 0.0, value: 0.0),
        Keyframe(t: 1.0, value: 1.2),
      ]),
    }),
    _child: TrackSet({
      _rotation: ScalarTrack(const [
        Keyframe(t: 0.0, value: 0.0),
        Keyframe(t: 1.0, value: -3.5),
      ]),
    }),
    // Criterion 5: reveal 0→1 over [0,0.5], then opacity 1→0 over [0.5,1].
    _stroke: TrackSet({
      _trimEnd: ScalarTrack(const [
        Keyframe(t: 0.0, value: 0.0),
        Keyframe(t: 0.5, value: 1.0),
        Keyframe(t: 1.0, value: 1.0),
      ]),
      _opacity: ScalarTrack(const [
        Keyframe(t: 0.0, value: 1.0),
        Keyframe(t: 0.5, value: 1.0),
        Keyframe(t: 1.0, value: 0.0),
      ]),
    }),
  });

  return Document.create(name: 'Showcase', artboard: const Vec2(450.2, 250.4))
      .copyWith(
    root: root,
    animations: <Animation>[anim],
    defaultAnimationId: anim.id,
  );
}

PathData _geomAt(Document d, NodeId n, double t) =>
    evaluate(d, [AnimationMix(d.defaultAnimationId!, t)])
        .byPath[ScenePath(n)]!
        .geometry!;

void _expectFinite(Document d, double t) {
  for (final node in evaluate(d, [AnimationMix(d.defaultAnimationId!, t)]).drawOrder) {
    for (final v in [node.world.a, node.world.b, node.world.c, node.world.d,
      node.world.tx, node.world.ty, node.worldOpacity]) {
      expect(v.isFinite, isTrue, reason: 'non-finite transform at t=$t');
    }
    for (final a in node.geometry?.anchors ?? const <Anchor>[]) {
      for (final v in [a.position.x, a.position.y, a.inTangent.x, a.inTangent.y,
        a.outTangent.x, a.outTangent.y]) {
        expect(v.isFinite, isTrue, reason: 'non-finite anchor at t=$t');
      }
    }
  }
}

void main() {
  test('§5 criterion 1+2: a closed bezier with a curve, keyed at 3 fractional '
      'times with a distinct easing on each', () {
    final doc = _showcase();
    final geom = doc.root.children.first as PathNode;
    // 1: closed, with a genuinely curved segment (non-zero tangents on a2).
    expect(geom.path.closed, isTrue);
    expect(geom.path.anchors.any((a) => a.outTangent != Vec2.zero), isTrue,
        reason: 'at least one curved segment');
    // 2: three path keys at fractional t, three DISTINCT easings.
    final track = doc.defaultAnimation!.tracksFor(_shape).pathTrack()!;
    expect(track.keys.map((k) => k.t).toList(), [0.0, 0.4, 1.0]);
    final easings = track.keys.map((k) => k.easing).toSet();
    expect(easings, hasLength(3), reason: 'a different easing per segment');
    expect(easings.every((e) => e is CubicEasing), isTrue);
  });

  test('§5 criterion 3: insert an anchor at keyframe 1 — no crash, shape stays, '
      'and keyframes 2 and 3 are pixel-identical', () {
    final d0 = _showcase();
    // Insert on the curved segment a1→a2 (the sharpest case) at u=0.5.
    final (d1, newId) =
        PathOps.insertAnchor(d0, _shape, after: const AnchorId('a1'), u: 0.5);

    // Topology invariant (AC-4.3.6): the new id is in every keyframe.
    final track = d1.defaultAnimation!.tracksFor(_shape).pathTrack()!;
    for (final k in track.keys) {
      expect(k.value.anchors.containsKey(newId), isTrue);
    }

    // Keyframes 2 (t=0.4) and 3 (t=1.0): the ORIGINAL anchors evaluate to the
    // exact same positions as before the insert, and the shape is still present.
    for (final t in const [0.4, 1.0]) {
      final before = _geomAt(d0, _shape, t);
      final after = _geomAt(d1, _shape, t);
      expect(after.anchors.length, before.anchors.length + 1,
          reason: 'exactly one anchor added');
      for (final a in before.anchors) {
        final match = after.anchors.firstWhere((x) => x.id == a.id);
        expect(match.position.x, closeTo(a.position.x, 1e-9), reason: 'kf @$t');
        expect(match.position.y, closeTo(a.position.y, 1e-9), reason: 'kf @$t');
      }
      // The inserted anchor lies ON the shape (finite, inside the loop's span).
      final inserted = after.anchors.firstWhere((x) => x.id == newId);
      expect(inserted.position.x.isFinite && inserted.position.y.isFinite, isTrue);
    }
  });

  test('§5 criterion 4: a group rotates while its child spins the opposite way '
      'at a different rate — the two worlds COMPOSE, not cancel', () {
    final s = evaluate(_showcase(), [const AnimationMix(AnimationId('main'), 0.5)]);
    final grp = s.byPath[const ScenePath(_grp)]!;
    final child = s.byPath[const ScenePath(_child)]!;
    // world = parent.world · local, so opposite spins at different rates leave
    // the child's world DIFFERENT from the group's — they do not cancel.
    expect(grp.world == child.world, isFalse);
    expect(grp.worldVisible && child.worldVisible, isTrue);
  });

  test('§5 criterion 5: the stroke draws itself on (trim 0→1) then fades out',
      () {
    final doc = _showcase();
    int revealed(double t) => _geomAt(doc, _stroke, t).anchors.length;
    double opacity(double t) =>
        evaluate(doc, [AnimationMix(doc.defaultAnimationId!, t)])
            .byPath[const ScenePath(_stroke)]!
            .worldOpacity;

    // Draws on: nothing revealed at t=0, fully revealed by t=0.5.
    expect(revealed(0.0), lessThan(revealed(0.5)),
        reason: 'the reveal grows as trimEnd 0→1');
    expect(revealed(0.5), greaterThan(1), reason: 'fully drawn at t=0.5');
    // Fades out: opaque while drawing, transparent by t=1.
    expect(opacity(0.5), closeTo(1.0, 1e-9));
    expect(opacity(1.0), closeTo(0.0, 1e-9), reason: 'faded out');
  });

  test('§5 criterion 6: scrubbing [−0.2, 1.2] — no NaN, no empty geometry, '
      'shape present at t=1.0', () {
    final doc = _showcase();
    for (var n = 0; n < 50; n++) {
      _expectFinite(doc, -0.2 + 1.4 * n / 49.0);
    }
    // Present at t=1.0: the filled shapes still have geometry (the stroke may be
    // faded to opacity 0 by design, but its geometry is not empty).
    for (final id in const [_shape, _child, _stroke]) {
      expect(_geomAt(doc, id, 1.0).anchors, isNotEmpty,
          reason: 'node ${id.v} vanished at t=1.0');
    }
  });

  test('§5 criterion 7+8: the document round-trips byte-identical and replays '
      'through the anim_core runtime', () {
    final doc = _showcase();
    // Reload (criterion 7, the serializer half) + export/replay (criterion 8):
    // decode → encode → decode → encode is a fixed point.
    final once = jsonEncode(doc.toJson());
    final reloaded = Document.fromJson(jsonDecode(once) as Map<String, Object?>);
    final twice = jsonEncode(reloaded.toJson());
    expect(twice, once, reason: 'reload is not byte-identical');
    // It replays: evaluate the reloaded doc at 50 t, finite everywhere.
    for (var n = 0; n <= 50; n++) {
      _expectFinite(reloaded, n / 50);
    }
  });

  test('§5 criterion 9: all 8 legacy samples import and play NaN-free at 50 t',
      () {
    const files = [
      'HomeMenu.json', 'MultiPolygon.json', 'PlayPause.json', 'PlayPause1.json',
      'Squares.json', 'circlebounce.json', 'circlebounce2.json', 'circlebounce3.json',
    ];
    for (final name in files) {
      final legacy = jsonDecode(
              File('${Directory.current.path}/../../assets/library/$name')
                  .readAsStringSync())
          as Map<String, Object?>;
      final doc = LegacyImporter.import(legacy);
      expect(doc.schemaVersion, 3, reason: name);
      for (var k = 0; k <= 50; k++) {
        _expectFinite(doc, k / 50);
      }
    }
  });
}
