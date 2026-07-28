/// GATE 1 OF 2 — the round-trip property test (docs/v3/00 §5, docs/v3/04 §7).
///
/// docs/v3/00 §5 defines the CI gate as exactly two things: this file, and
/// `transform_gate_test.dart`. Everything else in `anim_core/test` is
/// developer-local coverage. **Do not add a third gate** — docs/v3/04 §7 says
/// it in as many words ("No test tracks beyond these"), because a third gate is
/// scope creep wearing a test's clothes: it grows the release bar without
/// growing the guarantee, and the two that exist are the two that map onto the
/// defects that killed the legacy build.
///
/// **What it asserts.** For each of the eight fixtures in `test/fixtures/`:
/// decode → encode → decode → encode is a fixed point, in *both* senses.
///
///  1. The second encode is **byte-identical** to the first. This is the
///     assertion that carries the weight. Structural equality alone cannot see
///     a dropped unknown key (the decoded models compare equal because neither
///     one has the key), a normalised default (`"opacity"` absent on the way in
///     and `1.0` on the way out — equal models, changed file), or an int/double
///     drift (`3` vs `3.0` — same `double` in Dart, different bytes on the
///     wire). All three are silent data loss under Firestore autosave.
///  2. The second decode is **structurally equal** to the first, checked by a
///     digest walked over the *model API* rather than over `toJson`. Byte
///     identity alone cannot see an encoder and a decoder that are wrong in
///     matching directions — a field written under the wrong key and read back
///     from the wrong key round-trips perfectly and is still a broken format.
///
/// Plus: `rev` survives exactly (it is save metadata, so nothing in the
/// evaluator would ever notice it drifting), and no fixture emits a decode
/// warning — the eight are authored to be *clean* documents, and a warning here
/// means the decoder started degrading something it used to accept.
///
/// **The fixtures are v3, not legacy.** docs/v3/00 §5 and docs/v3/04 §7 both say
/// "8 legacy fixtures" and docs/v3/06 schedules this gate at M1, but
/// `LegacyImporter` is F11.3 and lands at M8 — at M1 there is nothing to
/// import. The eight below are hand-authored v3 documents, checked in as real
/// `.json` files (never Dart literals: a literal is built by the same Dart that
/// is under test, so it cannot catch an encoder that emits an int where the
/// format says double). At M8 the imported legacy documents join *this* test
/// rather than adding a third gate.
///
/// **What breaks if this goes red.** The serializer stopped being a bijection.
/// Concretely: a user's document, opened in this build and autosaved back to
/// Firestore, is no longer the document they saved — 00 §5 criterion 7
/// ("reload and get byte-identical geometry back") is false, criterion 8 (an
/// exported `.json` replays in the standalone `anim_core` runtime) is false,
/// and the loss is invisible until someone diffs a render. Do not quarantine
/// this test. Do not "update the expectation". Find what stopped round-tripping.
library;

import 'dart:convert';
import 'dart:io';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The whole type surface, split across eight documents.
///
/// Each entry says what that fixture is *for*; the split is by type-surface
/// coverage, not by feature, so adding a ninth is a signal that a type has no
/// home rather than a licence to grow the list.
const fixtures = <String, String>{
  '01_minimal.json': 'smallest legal document — root group, no children',
  '02_nested.json': 'three levels of groups, clipChildren, transforms, z-order',
  '03_geometry.json': 'open/closed, curves, all AnchorKinds, 1- and 0-anchor',
  '04_paint.json':
      'solids, every cap/join/fill rule, linear + radial gradients',
  '05_tracks.json': 'all five track types, sparse, unbounded spin, all easings',
  '06_forward.json': 'unknown node/paint/easing/property/keys — forward compat',
  '07_trim.json': 'PathTrim plus trimStart/trimEnd/trimOffset tracks',
  '08_lopsided.json': '450.2 × 250.4 geometry that exposes a y/width rescale',
};

File fixtureFile(String name) =>
    File('${Directory.current.path}/test/fixtures/$name');

/// The 8 legacy sample files (docs/v3/02 §8) — the importer's input, at the repo
/// root. They are NOT `test/fixtures/` v3 documents (the "no ninth" guard above
/// is scoped to that directory); the 8 documents they IMPORT to join this gate
/// as cases 9–16 in-code, per docs/v3/04 §7 (no third gate).
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

File legacyFile(String name) =>
    File('${Directory.current.path}/../../assets/library/$name');

void main() {
  late List<String> warnings;
  late DecodeWarning previousHandler;

  setUp(() {
    warnings = <String>[];
    previousHandler = onDecodeWarning;
    onDecodeWarning = warnings.add;
  });

  tearDown(() => onDecodeWarning = previousHandler);

  test('all eight fixtures are present and no ninth has appeared', () {
    final onDisk = Directory('${Directory.current.path}/test/fixtures')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .toList()
      ..sort();

    // Eight, named, and matching the table above. A fixture deleted from disk
    // would otherwise silently shrink the gate to seven and stay green.
    expect(onDisk, fixtures.keys.toList()..sort());
  });

  fixtures.forEach((name, covers) {
    group('$name — $covers', () {
      test('decode → encode → decode → encode is a fixed point', () {
        final bytes = fixtureFile(name).readAsStringSync();
        final authored = jsonDecode(bytes) as Map<String, Object?>;

        final first = Document.fromJson(authored);
        final encodedOnce = jsonEncode(first.toJson());

        final second =
            Document.fromJson(jsonDecode(encodedOnce) as Map<String, Object?>);
        final encodedTwice = jsonEncode(second.toJson());

        // (1) Byte identity. The file on disk is *not* the comparand — it is
        // hand-formatted and may legally omit defaults. The fixed point is the
        // encoder's own output, and the first encode is where it is reached.
        expect(encodedTwice, encodedOnce,
            reason: 'the second encode drifted from the first — something is '
                'being dropped, normalised or retyped on the way through');

        // (2) Structural identity, walked over the model API rather than over
        // toJson, so a matched encoder/decoder mistake cannot hide behind (1).
        expect(digest(second), digest(first));

        // rev is the one persisted field the evaluator never reads, so nothing
        // downstream would notice it drifting. v1.1 turns it into optimistic
        // concurrency; a rev that does not survive a save is a clobber.
        final authoredRev = authored.containsKey('rev')
            ? (authored['rev']! as num).toInt()
            : 1; // absent means written before `rev` existed — generation 1.
        expect(first.rev, authoredRev);
        expect(second.rev, authoredRev);

        // The eight are clean documents. A warning means the decoder began
        // degrading something these fixtures used to state legally — most
        // likely an orphan pose introduced by an edit to a fixture.
        expect(warnings, isEmpty,
            reason: 'decoding a gate fixture must not degrade anything');
      });
    });
  });

  // Cases 9–16: the imported legacy documents round-trip too (docs/v3/02 §8).
  // An importer output is a v3 Document like any other; if it does not survive
  // decode → encode → decode, the sample it produced cannot be saved and
  // reopened, which is the same defect this gate exists to catch.
  for (final name in legacyFiles) {
    test('$name imports to a document that round-trips to a fixed point', () {
      final legacy = jsonDecode(legacyFile(name).readAsStringSync())
          as Map<String, Object?>;
      final imported = LegacyImporter.import(legacy);
      expect(imported.schemaVersion, 3);

      final encodedOnce = jsonEncode(imported.toJson());
      final decoded =
          Document.fromJson(jsonDecode(encodedOnce) as Map<String, Object?>);
      final encodedTwice = jsonEncode(decoded.toJson());

      expect(encodedTwice, encodedOnce,
          reason: 'the imported document does not survive a save/reload');
      expect(digest(decoded), digest(imported));
      expect(warnings, isEmpty,
          reason: 'importing must not produce a document the decoder degrades');
    });
  }
}

// ---------------------------------------------------------------------------
// Structural digest.
//
// Deliberately does not touch `toJson`: this half of the property exists to
// catch an encoder and a decoder that are wrong in matching directions, and
// re-encoding to compare would consult exactly the code under suspicion.
// Map-valued structure is emitted in sorted key order, so this half is
// insensitive to ordering (which is (1)'s job) and sensitive only to content.
// ---------------------------------------------------------------------------

String digest(Document d) {
  final b = StringBuffer()
    ..writeln('schemaVersion=${d.schemaVersion}')
    ..writeln('id=${d.id}')
    ..writeln('name=${d.name}')
    ..writeln('artboard=${_vec(d.artboard)}')
    ..writeln('background=${_rgba(d.background)}')
    ..writeln('rev=${d.rev}')
    ..writeln('defaultAnimationId=${d.defaultAnimationId?.v}')
    ..writeln('unknown=${_raw(d.unknownKeys)}');
  _node(b, d.root, 0);
  for (final a in d.animations) {
    _animation(b, a);
  }
  return b.toString();
}

void _node(StringBuffer b, Node n, int depth) {
  final pad = '  ' * depth;
  b
    ..writeln('${pad}node ${n.id.v} "${n.name}"')
    ..writeln('$pad  transform=${_transform(n.transform)}')
    ..writeln('$pad  opacity=${n.opacity} visible=${n.visible} '
        'locked=${n.locked}')
    ..writeln('$pad  unknown=${_raw(n.unknownKeys)}');
  switch (n) {
    case GroupNode(:final children, :final clipChildren):
      b.writeln('$pad  group clip=$clipChildren children=${children.length}');
      for (final c in children) {
        _node(b, c, depth + 1);
      }
    case PathNode(:final path, :final fills, :final strokes, :final recipe):
      b
        ..writeln('$pad  path closed=${path.closed} '
            'segments=${path.segmentCount}')
        ..writeln('$pad  trim=${n.trim}')
        ..writeln('$pad  recipe=${_recipe(recipe)}');
      for (final a in path.anchors) {
        b.writeln('$pad    anchor ${a.id.v} ${_vec(a.position)} '
            'in=${_vec(a.inTangent)} out=${_vec(a.outTangent)} ${a.kind.name}');
      }
      for (final f in fills) {
        b.writeln('$pad    fill ${f.id.v} ${f.rule.name} op=${f.opacity} '
            'vis=${f.visible} ${_paint(f.paint)}');
      }
      for (final s in strokes) {
        b.writeln('$pad    stroke ${s.id.v} w=${s.width} ${s.cap.name} '
            '${s.join.name} miter=${s.miterLimit} op=${s.opacity} '
            'vis=${s.visible} ${_paint(s.paint)}');
      }
    case UnknownNode(:final rawType, :final raw):
      // The passthrough map is the whole value of this type, so the digest
      // states it in full — an UnknownNode that quietly lost a subtree would
      // otherwise look identical to one that kept it.
      b.writeln('$pad  unknownNode type=$rawType raw=${_raw(raw)}');
  }
}

void _animation(StringBuffer b, Animation a) {
  b
    ..writeln('animation ${a.id.v} "${a.name}"')
    ..writeln(
        '  duration=${a.durationSeconds} fps=${a.fps} loop=${a.loop.name}')
    ..writeln('  unknown=${_raw(a.unknownKeys)}');
  final nodes = a.tracks.keys.map((k) => k.v).toList()..sort();
  for (final nodeId in nodes) {
    final set = a.tracks[NodeId(nodeId)]!;
    b.writeln('  tracks for $nodeId unknown=${_raw(set.unknownKeys)}');
    final wires = set.byKey.keys.map((k) => k.wire).toList()..sort();
    for (final wire in wires) {
      final key = set.byKey.keys.firstWhere((k) => k.wire == wire);
      b.writeln('    $wire ${_track(set.byKey[key]!)}');
    }
  }
}

String _track(Track t) {
  final b = StringBuffer();
  switch (t) {
    case ScalarTrack(:final keys, :final unknownKeys):
      b.write('scalar unknown=${_raw(unknownKeys)}');
      for (final k in keys) {
        b.write(' [t=${k.t} v=${k.value} ${_easing(k.easing)}]');
      }
    case Vec2Track(:final keys, :final unknownKeys):
      b.write('vec2 unknown=${_raw(unknownKeys)}');
      for (final k in keys) {
        final into = k is Vec2Keyframe ? k.inTangent : null;
        final out = k is Vec2Keyframe ? k.outTangent : null;
        b.write(' [t=${k.t} v=${_vec(k.value)} '
            'in=${into == null ? '-' : _vec(into)} '
            'out=${out == null ? '-' : _vec(out)} ${_easing(k.easing)}]');
      }
    case ColorTrack(:final keys, :final unknownKeys):
      b.write('color unknown=${_raw(unknownKeys)}');
      for (final k in keys) {
        b.write(' [t=${k.t} v=${_rgba(k.value)} ${_easing(k.easing)}]');
      }
    case BoolTrack(:final keys, :final unknownKeys):
      b.write('bool unknown=${_raw(unknownKeys)}');
      for (final k in keys) {
        b.write(' [t=${k.t} v=${k.value} ${_easing(k.easing)}]');
      }
    case PathTrack(:final keys, :final unknownKeys):
      b.write('path unknown=${_raw(unknownKeys)}');
      for (final k in keys) {
        final ids = k.value.anchors.keys.map((a) => a.v).toList()..sort();
        b.write(' [t=${k.t} ${_easing(k.easing)}');
        for (final id in ids) {
          final pose = k.value.anchors[AnchorId(id)]!;
          b.write(' $id=${_vec(pose.position)}/${_vec(pose.inTangent)}'
              '/${_vec(pose.outTangent)}');
        }
        b.write(']');
      }
  }
  return b.toString();
}

String _paint(PaintSource p) => switch (p) {
      SolidPaint(:final color) => 'solid ${_rgba(color)}',
      LinearGradientPaint(:final start, :final end, :final stops) =>
        'linear ${_vec(start)}→${_vec(end)} ${stops.map(_stop).join(',')}',
      RadialGradientPaint(:final center, :final radius, :final stops) =>
        'radial ${_vec(center)} r=$radius ${stops.map(_stop).join(',')}',
      UnknownPaint(:final raw) => 'unknownPaint ${_raw(raw)}',
    };

String _stop(GradientStop s) => '${s.id.v}@${s.offset}=${_rgba(s.color)}';

String _recipe(ShapeRecipe? r) => switch (r) {
      null => 'none',
      RectRecipe(:final w, :final h, :final cornerRadius, :final unknownKeys) =>
        'rect $w×$h r=$cornerRadius unknown=${_raw(unknownKeys)}',
      EllipseRecipe(:final rx, :final ry, :final unknownKeys) =>
        'ellipse $rx/$ry unknown=${_raw(unknownKeys)}',
      PolygonRecipe(
        :final sides,
        :final radius,
        :final star,
        :final innerRatio,
        :final unknownKeys
      ) =>
        'polygon $sides r=$radius star=$star inner=$innerRatio '
            'unknown=${_raw(unknownKeys)}',
      UnknownRecipe(:final raw) => 'unknownRecipe ${_raw(raw)}',
    };

String _easing(Easing e) => switch (e) {
      LinearEasing() => 'linear',
      HoldEasing() => 'hold',
      CubicEasing(:final x1, :final y1, :final x2, :final y2) =>
        'cubic($x1,$y1,$x2,$y2)',
      UnknownEasing(:final raw) => 'unknownEasing ${_raw(raw)}',
    };

String _transform(Transform2 t) =>
    'pos=${_vec(t.position)} scale=${_vec(t.scale)} pivot=${_vec(t.pivot)} '
    'rot=${t.rotation} skewX=${t.skewX}';

String _vec(Vec2 v) => '(${v.x},${v.y})';

String _rgba(Rgba c) => '[${c.r},${c.g},${c.b},${c.a}]';

/// Passthrough maps are opaque by definition, so the digest states them
/// verbatim in sorted-key order. `jsonEncode` here is a printer for data the
/// decoder never interpreted — it is not the encoder under test.
String _raw(Map<String, Object?> m) {
  if (m.isEmpty) return '{}';
  final keys = m.keys.toList()..sort();
  return jsonEncode(<String, Object?>{for (final k in keys) k: m[k]});
}
