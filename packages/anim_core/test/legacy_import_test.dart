/// F11.3 — the one-way legacy importer, behavioural acceptance (docs/v3/02 §8).
///
/// The round-trip identity of the 8 imported documents is a CI gate case in
/// `round_trip_gate_test.dart`. This file is the developer-local behavioural
/// acceptance: every sample imports to a clean v3 document that evaluates
/// NaN-free and never empty across [0,1] (AC-11.3.2), and the three legacy bugs
/// docs/v3/02 §8 names are pinned shut — coincident keyframes (AC-11.3.3), the
/// sorted-percent / unsorted-frames desync (AC-11.3.4), and the capital-S key
/// leak (AC-11.3.6) — plus the vertex-count repair backstop (AC-11.3.5).
library;

import 'dart:convert';
import 'dart:io';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The 8 legacy fixtures live at the repo root, two levels up from the package.
File legacyFixture(String name) =>
    File('${Directory.current.path}/../../assets/library/$name');

const legacyFiles = <String>[
  'HomeMenu.json',
  'MultiPolygon.json',
  'PlayPause.json',
  'PlayPause1.json',
  'Squares.json',
  'circlebounce.json',
  'circlebounce2.json',
  'circlebounce3.json',
];

Document importFixture(String name) => LegacyImporter.import(
    jsonDecode(legacyFixture(name).readAsStringSync()) as Map<String, Object?>);

/// Every finite coordinate in the scene at [t].
void expectFiniteScene(Document doc, double t) {
  final scene = evaluate(doc, [AnimationMix(doc.defaultAnimationId!, t)]);
  for (final node in scene.drawOrder) {
    for (final v in <double>[
      node.world.a,
      node.world.b,
      node.world.c,
      node.world.d,
      node.world.tx,
      node.world.ty,
      node.worldOpacity,
    ]) {
      expect(v.isFinite, isTrue, reason: 'non-finite transform at t=$t');
    }
    for (final a in node.geometry?.anchors ?? const <Anchor>[]) {
      for (final v in <double>[
        a.position.x,
        a.position.y,
        a.inTangent.x,
        a.inTangent.y,
        a.outTangent.x,
        a.outTangent.y,
      ]) {
        expect(v.isFinite, isTrue, reason: 'non-finite anchor at t=$t');
      }
    }
  }
}

/// Every PathTrack key across a document (for the strictly-increasing check).
Iterable<List<double>> pathTrackTimes(Document doc) sync* {
  for (final anim in doc.animations) {
    for (final set in anim.tracks.values) {
      for (final track in set.byKey.values) {
        if (track is PathTrack) yield track.keys.map((k) => k.t).toList();
      }
    }
  }
}

/// Recursively collect every JSON object key.
void collectKeys(Object? json, Set<String> into) {
  if (json is Map<String, Object?>) {
    for (final e in json.entries) {
      into.add(e.key);
      collectKeys(e.value, into);
    }
  } else if (json is List) {
    for (final v in json) {
      collectKeys(v, into);
    }
  }
}

void main() {
  group('every legacy fixture imports to a clean, evaluable v3 document', () {
    for (final name in legacyFiles) {
      test('$name — schemaVersion 3, NaN-free and non-empty over [0,1] '
          '(AC-11.3.1/11.3.2)', () {
        final doc = importFixture(name);
        expect(doc.schemaVersion, 3, reason: 'AC-11.3.1');
        expect(doc.id, isNotEmpty);
        expect(doc.defaultAnimationId, isNotNull);
        // At least one drawable node (all 8 fixtures have geometry).
        expect(doc.root.children, isNotEmpty, reason: 'the sample has shapes');

        // 50 sample points across the whole range — no NaN anywhere.
        for (var k = 0; k <= 50; k++) {
          expectFiniteScene(doc, k / 50);
        }

        // Nothing vanishes at t=1.0 — the legacy "shape disappears at 100%" bug.
        // Every imported PATH node (the importer adds only PathNodes under the
        // root group; groups legitimately have no geometry) must be present.
        final end = evaluate(doc, [AnimationMix(doc.defaultAnimationId!, 1.0)]);
        for (final child in doc.root.children) {
          final resolved = end.byPath[ScenePath(child.id)];
          expect(resolved, isNotNull, reason: 'node ${child.id.v} not resolved');
          final geom = resolved!.geometry;
          expect(geom, isNotNull, reason: 'a path node lost geometry at t=1.0');
          expect(geom!.anchors.length, greaterThanOrEqualTo(2),
              reason: 'AC-11.3.2: no empty geometry at t=1.0');
        }
      });
    }
  });

  test('AC-11.3.3/11.3.4: every imported PathTrack has strictly increasing t — '
      'coincident keys separated, frames sorted by position', () {
    // Squares.json has 20.347… three times; circlebounce.json stores 100 first
    // in the array and 100 twice. Both must yield a strictly-monotonic key list.
    for (final name in legacyFiles) {
      for (final times in pathTrackTimes(importFixture(name))) {
        for (var i = 1; i < times.length; i++) {
          expect(times[i], greaterThan(times[i - 1]),
              reason: '$name has a coincident or out-of-order key: $times');
        }
        for (final t in times) {
          expect(t, inInclusiveRange(0.0, 1.0));
        }
      }
    }
  });

  test('AC-11.3.4: circlebounce reads geometry from the right keyframe — the '
      'array-order/frameNo desync does not survive import', () {
    // The array stores framePosition 100 at index 0; a naive importer trusting
    // array order would put the last pose at t=0. After a sort-by-position the
    // FIRST key must be the lowest framePosition (near 0), not 1.0.
    final doc = importFixture('circlebounce.json');
    final times = pathTrackTimes(doc).first;
    expect(times.first, lessThan(0.5),
        reason: 'the earliest keyframe is near t=0, not the array head at 1.0');
    expect(times.last, closeTo(1.0, 1e-9));
  });

  test('AC-11.3.6: no capital-S / legacy key survives into the v3 document', () {
    for (final name in legacyFiles) {
      final keys = <String>{};
      collectKeys(importFixture(name).toJson(), keys);
      // v3 keys are all camelCase (lowercase first letter); legacy leaks
      // "SingleFrameModel", "iconSections", etc.
      final capitals = keys.where((k) => RegExp(r'^[A-Z]').hasMatch(k)).toList();
      expect(capitals, isEmpty, reason: '$name leaked capital-S keys: $capitals');
      for (final legacy in const [
        'SingleFrameModel',
        'iconSections',
        'framePosition',
        'controlMidPoints',
        'cornerBoxPoints',
      ]) {
        expect(keys.contains(legacy), isFalse,
            reason: '$name leaked the legacy key "$legacy"');
      }
    }
  });

  test('AC-11.3.5: a legacy path whose per-keyframe vertex counts disagree is '
      'repaired to one topology (retopologize backstop)', () {
    // The 8-file corpus never trips this (counts are constant), so a synthetic
    // section: frame 0 has 3 points, frame 1 has 5. The importer must resample
    // to one AnchorId set shared by every keyframe (AC-4.3.6), NaN-free.
    final legacy = <String, Object?>{
      'projectName': 'Mismatch',
      'width': 200,
      'height': 200,
      'iconSections': [
        {
          'iconSectionName': 'grow',
          'color': 'ff112233',
          'drawingObjectType': 'polygon',
          'frames': [
            {
              'frameNo': 0,
              'SingleFrameModel': {
                'framePosition': 0,
                'controlMidPoints': {},
                'points': [
                  {'x': 0, 'y': 0},
                  {'x': 100, 'y': 0},
                  {'x': 50, 'y': 100},
                ],
              },
            },
            {
              'frameNo': 1,
              'SingleFrameModel': {
                'framePosition': 100,
                'controlMidPoints': {},
                'points': [
                  {'x': 10, 'y': 10},
                  {'x': 90, 'y': 10},
                  {'x': 95, 'y': 90},
                  {'x': 50, 'y': 120},
                  {'x': 5, 'y': 90},
                ],
              },
            },
          ],
        },
      ],
    };

    final doc = LegacyImporter.import(legacy);
    final times = pathTrackTimes(doc).toList();
    expect(times, hasLength(1), reason: 'one animated node');

    // Every keyframe of the node shares the same AnchorId set (AC-4.3.6).
    final track = doc.animations.first.tracks.values.first.byKey.values
        .whereType<PathTrack>()
        .first;
    final idSets = track.keys
        .map((k) => k.value.anchors.keys.map((a) => a.v).toSet())
        .toList();
    for (final ids in idSets) {
      expect(ids, idSets.first,
          reason: 'keyframes disagree on the AnchorId set after repair');
    }
    // And it evaluates NaN-free.
    for (var k = 0; k <= 20; k++) {
      expectFiniteScene(doc, k / 20);
    }
  });

  test('a non-base frame with too few points is dropped, never a crash '
      '(AC-11.3.5 totality)', () {
    // Frame 0 is valid (3 points → the base topology); a later frame has an
    // EMPTY points array. It must be dropped, not resampled into a divide-by-zero
    // (`points[i % 0]`), and the node must still import and evaluate NaN-free.
    List<Map<String, Object?>> frame(double pos, List<List<num>> pts) => [
          {
            'frameNo': pos.toInt(),
            'SingleFrameModel': {
              'framePosition': pos,
              'controlMidPoints': <String, Object?>{},
              'points': [
                for (final p in pts) {'x': p[0], 'y': p[1]},
              ],
            },
          },
        ];

    for (final degenerate in <List<List<num>>>[
      <List<num>>[], // 0 points
      <List<num>>[
        [50, 50]
      ], // 1 point
    ]) {
      final legacy = <String, Object?>{
        'projectName': 'Degenerate',
        'width': 200,
        'height': 200,
        'iconSections': [
          {
            'iconSectionName': 'g',
            'color': 'ff112233',
            'drawingObjectType': 'polygon',
            'frames': [
              ...frame(0, [
                [0, 0],
                [100, 0],
                [50, 100]
              ]),
              ...frame(100, degenerate),
            ],
          },
        ],
      };

      final doc = LegacyImporter.import(legacy); // must not throw
      expect(doc.root.children, hasLength(1),
          reason: 'the section is still a node (frame 0 is valid)');
      for (var k = 0; k <= 20; k++) {
        expectFiniteScene(doc, k / 20);
      }
      // Every surviving PathTrack key is a full-count pose, strictly increasing.
      for (final times in pathTrackTimes(doc)) {
        for (var i = 1; i < times.length; i++) {
          expect(times[i], greaterThan(times[i - 1]));
        }
      }
    }
  });

  test('the importer is a pure read — legacy detection recognises the format',
      () {
    expect(LegacyImporter.isLegacy(jsonDecode(
        legacyFixture('PlayPause.json').readAsStringSync()) as Map<String, Object?>),
        isTrue);
    expect(LegacyImporter.isLegacy(<String, Object?>{'schemaVersion': 3}),
        isFalse);
    expect(LegacyImporter.isLegacy(<String, Object?>{}), isFalse);
  });
}
