import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

Object? reencode(Object? j) => jsonDecode(jsonEncode(j));

ScalarTrack scalar(List<(double, double)> keys, {Easing? easing}) =>
    ScalarTrack([
      for (final (t, v) in keys)
        Keyframe<double>(
            t: t, value: v, easing: easing ?? const LinearEasing()),
    ]);

void main() {
  group('the §9 decision table', () {
    // Each row of docs/v3/01 §9, as a table. The sampler is TOTAL: there is no
    // input in this table, or outside it, for which it throws.
    final cases = <(String, ScalarTrack, double, double)>[
      ('single key holds everywhere (below)', scalar([(0.4, 7)]), 0.0, 7),
      ('single key holds everywhere (at)', scalar([(0.4, 7)]), 0.4, 7),
      ('single key holds everywhere (above)', scalar([(0.4, 7)]), 1.0, 7),
      ('t < first HOLDS FIRST', scalar([(0.25, 10), (0.75, 20)]), 0.0, 10),
      ('t == first', scalar([(0.25, 10), (0.75, 20)]), 0.25, 10),
      ('midpoint eases linearly', scalar([(0.25, 10), (0.75, 20)]), 0.5, 15),
      ('t == last', scalar([(0.25, 10), (0.75, 20)]), 0.75, 20),
      ('t > last HOLDS LAST', scalar([(0.25, 10), (0.75, 20)]), 1.0, 20),
      (
        't far past last still HOLDS LAST',
        scalar([(0.25, 10), (0.75, 20)]),
        99.0,
        20
      ),
      ('negative t holds first', scalar([(0.25, 10), (0.75, 20)]), -99.0, 10),
      (
        'the correct span is picked out of three',
        scalar([(0.0, 0), (0.5, 100), (1.0, 0)]),
        0.75,
        50
      ),
    ];

    for (final (name, track, t, expected) in cases) {
      test(name, () => expect(track.sampleAt(t), closeTo(expected, 1e-12)));
    }

    test('HOLD LAST is the fix for "the shape disappears at 100%"', () {
      // Legacy wrapped interpolation in `if (frames.length > preFrameNo + 1)`,
      // so past the last keyframe the body never ran and the section rendered
      // as nothing. Here the last value simply persists.
      final track = scalar([(0.0, 1), (0.6, 0.5)]);
      for (var n = 60; n <= 200; n++) {
        expect(track.sampleAt(n / 100.0), 0.5);
      }
    });

    test('a span at the 1e-9 floor takes the k1 branch, never the divide', () {
      // T2 makes coincident keys unrepresentable, but legacy's Squares.json
      // really does hold three keys at one position — the guard is what makes
      // the divide provably safe instead of merely likely.
      final track = scalar([(0.5, 10), (0.5 + 5e-10, 20), (0.9, 30)]);
      final y = track.sampleAt(0.5 + 2e-10);
      expect(y.isNaN, isFalse);
      expect(y, 20);
    });

    test('easing is applied to the segment leaving k0, not to the track', () {
      final held = ScalarTrack([
        const Keyframe<double>(t: 0, value: 10, easing: HoldEasing()),
        const Keyframe<double>(t: 1, value: 20),
      ]);
      expect(held.sampleAt(0.001), 10);
      expect(held.sampleAt(0.999), 10, reason: 'hold maps u -> 0');
      expect(held.sampleAt(1.0), 20, reason: 'the key itself still lands');

      final eased = scalar([(0.0, 0), (1.0, 100)], easing: CubicEasing.easeIn);
      expect(eased.sampleAt(0.5), lessThan(50),
          reason: 'easeIn is behind linear at the midpoint');
    });

    test('continuity: 1e-6 past a key renders within epsilon of the key', () {
      // Totality alone was never sufficient — a shape that collapses to a
      // point on the first frame is total and completely wrong.
      final track = scalar([(0.0, 5), (0.3, 40), (0.9, -12)]);
      for (final t in <double>[0.0, 0.3, 0.9]) {
        expect(track.sampleAt(t + 1e-6), closeTo(track.sampleAt(t), 1e-3));
        expect(track.sampleAt(t - 1e-6), closeTo(track.sampleAt(t), 1e-3));
      }
    });
  });

  group('per-type interpolation', () {
    test('vec2 without spatial tangents takes the straight-line fast path', () {
      final track = Vec2Track([
        const Vec2Keyframe(t: 0, value: Vec2(0, 0)),
        const Vec2Keyframe(t: 1, value: Vec2(100, 50)),
      ]);
      expect(track.sampleAt(0.5), const Vec2(50, 25));
    });

    test('vec2 spatial tangents curve the motion path off the chord', () {
      // `easing` shapes TIME; these shape SPACE. Orthogonal, and both needed
      // for a ball that arcs and accelerates.
      final track = Vec2Track([
        const Vec2Keyframe(t: 0, value: Vec2(0, 0), outTangent: Vec2(0, -100)),
        const Vec2Keyframe(t: 1, value: Vec2(100, 0), inTangent: Vec2(0, -100)),
      ]);
      final mid = track.sampleAt(0.5);
      expect(mid.x, closeTo(50, 1e-9));
      expect(mid.y, closeTo(-75, 1e-9), reason: 'off the chord, i.e. an arc');
    });

    test('rotation lerps RAW unbounded radians — no shortest-arc collapse', () {
      // -12.5664 means two full reverse turns and must play as two turns.
      final track = scalar([(0.0, 0.0), (1.0, -12.5664)]);
      expect(track.sampleAt(0.5), closeTo(-6.2832, 1e-9));
    });

    test('color lerps per channel', () {
      final track = ColorTrack([
        const Keyframe<Rgba>(t: 0, value: Rgba(0, 0, 0, 0)),
        const Keyframe<Rgba>(t: 1, value: Rgba(1, 1, 1, 1)),
      ]);
      expect(track.sampleAt(0.25), const Rgba(0.25, 0.25, 0.25, 0.25));
    });

    test('bool is always stepped — it holds the FROM key for the whole span',
        () {
      final track = BoolTrack([
        const Keyframe<bool>(t: 0, value: false),
        const Keyframe<bool>(t: 0.5, value: true),
      ]);
      expect(track.sampleAt(0.0), isFalse);
      expect(track.sampleAt(0.4999), isFalse);
      expect(track.sampleAt(0.5), isTrue);
      expect(track.sampleAt(1.0), isTrue);
    });
  });

  group('PathTrack (docs/v3/08 §1)', () {
    final track = PathTrack([
      Keyframe<PathPose>(
        t: 0,
        value: PathPose({
          const AnchorId('a0'):
              const AnchorPose(Vec2(0, 0), Vec2.zero, Vec2.zero),
        }),
      ),
      Keyframe<PathPose>(
        t: 1,
        value: PathPose({
          const AnchorId('a0'):
              const AnchorPose(Vec2(10, 10), Vec2.zero, Vec2.zero),
        }),
      ),
    ]);

    test('sampleDynamic returns null instead of reaching the StateError', () {
      // Without this override a generic byKey loop reaches interpolateKeys'
      // StateError and blanks the ENTIRE canvas on the first path-animated
      // node. The StateError stays reachable-looking and unwrapped on purpose.
      expect(track.sampleDynamic(0.5), isNull);
      expect(track.sampleDynamic(0.0), isNull);

      for (final t in <Track>[
        track,
        scalar([(0.0, 1)])
      ]) {
        expect(() => t.sampleDynamic(0.5), returnsNormally);
      }
    });

    test('interpolateKeys is the wrong door and says so loudly', () {
      expect(() => track.interpolateKeys(track.keys[0], track.keys[1], 0.5),
          throwsA(isA<StateError>()));
    });

    test('the facade fields still work', () {
      expect(track.keyCount, 2);
      expect(track.firstT, 0.0);
      expect(track.lastT, 1.0);
    });
  });

  group('invariants T1/T2/T3', () {
    test('T1: a track cannot be empty', () {
      expect(() => ScalarTrack(const []), throwsArgumentError);
    });

    test('T2: t must be STRICTLY increasing', () {
      expect(() => scalar([(0.5, 1), (0.5, 2)]), throwsArgumentError,
          reason: 'coincident keys are legacy Squares.json divide-by-zero NaN');
      expect(() => scalar([(0.5, 1), (0.2, 2)]), throwsArgumentError);
    });

    test('T3: every t lies in [0,1]', () {
      expect(() => scalar([(-0.1, 1)]), throwsArgumentError);
      expect(() => scalar([(0.0, 1), (1.5, 2)]), throwsArgumentError);
      expect(() => scalar([(double.nan, 1)]), throwsArgumentError);
    });

    test('T6: endpoints are NOT pinned — a track may start and end late', () {
      final late = scalar([(0.3, 1), (0.7, 2)]);
      expect(late.firstT, 0.3);
      expect(late.lastT, 0.7);
    });
  });

  group('TrackSet accessors', () {
    final set = TrackSet({
      const PropertyKey(PropKey.rotation): scalar([(0.0, 0), (1.0, 1)]),
      const PropertyKey(PropKey.fillColor, 'p-body'): ColorTrack([
        const Keyframe<Rgba>(t: 0, value: Rgba.black),
      ]),
    });

    test('a hit returns the typed track', () {
      expect(set.scalar(PropKey.rotation), isA<ScalarTrack>());
      expect(set.color(PropKey.fillColor, 'p-body'), isA<ColorTrack>());
    });

    test('a type mismatch returns null — it never throws and never casts', () {
      // A malformed stored document must not crash the paint loop; the
      // evaluator's fallback for a null track is already defined as the node's
      // pose value.
      expect(set.vec2(PropKey.rotation), isNull);
      expect(set.boolean(PropKey.rotation), isNull);
      expect(set.pathTrack(), isNull);
    });

    test('the wrong subjectId is a miss, not a wrong-fill hit', () {
      expect(set.color(PropKey.fillColor, 'p-stroke'), isNull);
      expect(set.color(PropKey.fillColor), isNull);
    });

    test('kExpectedTrackType covers all 15 properties, and only 15', () {
      // Fifteen, not sixteen: docs/v3/03 AC-6.1.3 and docs/v3/02 §3.9 both
      // list `pivot`, and doc 01 §4 (authoritative) says that row is the bug.
      expect(PropKey.values, hasLength(15));
      expect(kExpectedTrackType.keys.toSet(), PropKey.values.toSet());
      expect(PropKey.values.map((p) => p.name), isNot(contains('pivot')));
    });
  });

  group('PropertyKey', () {
    test('value equality, so it is usable as a map key', () {
      expect(const PropertyKey(PropKey.rotation),
          const PropertyKey(PropKey.rotation));
      expect(const PropertyKey(PropKey.fillColor, 'p-body'),
          const PropertyKey(PropKey.fillColor, 'p-body'));
      expect(const PropertyKey(PropKey.fillColor, 'p-body'),
          isNot(const PropertyKey(PropKey.fillColor, 'p-ink')));
      expect(const PropertyKey(PropKey.fillColor, 'p-body').hashCode,
          const PropertyKey(PropKey.fillColor, 'p-body').hashCode);
    });

    test('the wire form round-trips both shapes', () {
      expect(const PropertyKey(PropKey.rotation).wire, 'rotation');
      expect(const PropertyKey(PropKey.fillColor, 'p-body').wire,
          'fillColor:p-body');
      expect(PropertyKey.tryParse('rotation'),
          const PropertyKey(PropKey.rotation));
      expect(PropertyKey.tryParse('fillColor:p-body'),
          const PropertyKey(PropKey.fillColor, 'p-body'));
    });

    test('an unknown property name parses to null, not to a guess', () {
      expect(PropertyKey.tryParse('pivot'), isNull);
      expect(PropertyKey.tryParse('blurRadius:p-body'), isNull);
    });
  });

  group('wire format (docs/v3/02 §3.10)', () {
    test('every track type survives encode -> JSON text -> decode', () {
      final tracks = <String, Track>{
        'scalar': ScalarTrack([
          const Keyframe<double>(t: 0, value: 0, easing: CubicEasing.easeInOut),
          const Keyframe<double>(t: 0.769, value: 1),
        ]),
        'vec2': Vec2Track([
          const Vec2Keyframe(
              t: 0, value: Vec2(0, 0), outTangent: Vec2(90, -30)),
          const Vec2Keyframe(
              t: 0.6,
              value: Vec2(260, 120),
              inTangent: Vec2(-70, -95),
              outTangent: Vec2(45, -80)),
          const Vec2Keyframe(t: 1, value: Vec2(340, 120)),
        ]),
        'color': ColorTrack([
          const Keyframe<Rgba>(t: 0, value: Rgba(0.9, 0.24, 0.19)),
          const Keyframe<Rgba>(t: 1, value: Rgba(0.16, 0.42, 0.92)),
        ]),
        'bool': BoolTrack([
          const Keyframe<bool>(t: 0, value: true),
          const Keyframe<bool>(t: 0.5, value: false),
        ]),
        'path': PathTrack([
          Keyframe<PathPose>(
            t: 0,
            value: PathPose({
              const AnchorId('b0'):
                  const AnchorPose(Vec2(40, 40), Vec2.zero, Vec2.zero),
              const AnchorId('b1'):
                  const AnchorPose(Vec2(80, 40), Vec2(-14, 6), Vec2(14, -6)),
            }),
          ),
          Keyframe<PathPose>(
            t: 1,
            value: PathPose({
              const AnchorId('b0'):
                  const AnchorPose(Vec2(60, 20), Vec2.zero, Vec2.zero),
              const AnchorId('b1'):
                  const AnchorPose(Vec2(96, 60), Vec2(0, -18), Vec2(0, 18)),
            }),
          ),
        ]),
      };

      for (final entry in tracks.entries) {
        final json = reencode(entry.value.toJson());
        expect((json! as Map<String, Object?>)['type'], entry.key);

        final back = Track.fromJson(json);
        expect(back, isNotNull, reason: entry.key);
        expect(back.runtimeType, entry.value.runtimeType);
        expect(back!.keyCount, entry.value.keyCount);
        // Byte-stable: autosave runs this loop constantly, so any drift here
        // compounds.
        expect(jsonEncode(back.toJson()), jsonEncode(entry.value.toJson()),
            reason: entry.key);
      }
    });

    test('spatial tangents are omitted when absent, not written as zero', () {
      // A written {0,0} tangent is not the same document as no tangent: it
      // takes the cubic branch forever after instead of the lerp fast path.
      final json = const Vec2Keyframe(t: 0, value: Vec2(1, 2)).toJson();
      expect(json.containsKey('inTangent'), isFalse);
      expect(json.containsKey('outTangent'), isFalse);
    });

    test('whole-number doubles that Firestore returns as ints still decode',
        () {
      final back = Track.fromJson(<String, Object?>{
        'type': 'scalar',
        'keys': <Object?>[
          <String, Object?>{'t': 0, 'value': 1},
          <String, Object?>{'t': 1, 'value': 2},
        ],
      });
      expect(back, isA<ScalarTrack>());
      expect((back! as ScalarTrack).sampleAt(0.5), 1.5);
    });

    test('an absent easing decodes as linear, the identity', () {
      final back = Track.fromJson(<String, Object?>{
        'type': 'scalar',
        'keys': <Object?>[
          <String, Object?>{'t': 0.0, 'value': 0.0},
        ],
      });
      expect((back! as ScalarTrack).keys.single.easing, const LinearEasing());
    });
  });

  group('forward compatibility (docs/v3/02 §7)', () {
    test('a track type this build does not know rides through verbatim', () {
      // The stale-tab failure: a newer editor writes a `spring` track, this
      // build autosaves, and the track is silently gone. The user never sees
      // it happen.
      final source = <String, Object?>{
        'rotation': <String, Object?>{
          'type': 'scalar',
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': 0.0},
          ],
        },
        'position': <String, Object?>{
          'type': 'spring',
          'stiffness': 400.0,
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': <String, Object?>{}},
          ],
        },
      };

      final set = TrackSet.fromJson(source);
      expect(set.scalar(PropKey.rotation), isNotNull);
      expect(set.vec2(PropKey.position), isNull, reason: 'never evaluated');
      expect(set.toJson()['position'], source['position']);
    });

    test('an unknown property name is preserved, not evaluated', () {
      final source = <String, Object?>{
        'blurRadius:p-body': <String, Object?>{
          'type': 'scalar',
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': 4.0},
          ],
        },
      };
      final set = TrackSet.fromJson(source);
      expect(set.byKey, isEmpty);
      expect(set.toJson(), source);
    });

    test(
        'T5: a track whose type contradicts the property is preserved, not '
        'coerced', () {
      final source = <String, Object?>{
        'rotation': <String, Object?>{
          'type': 'vec2',
          'keys': <Object?>[
            <String, Object?>{
              't': 0.0,
              'value': <String, Object?>{'x': 1.0, 'y': 2.0},
            },
          ],
        },
      };
      final set = TrackSet.fromJson(source);
      expect(set.scalar(PropKey.rotation), isNull);
      expect(set.vec2(PropKey.rotation), isNull,
          reason:
              'the table says rotation is scalar; the entry is not a track');
      expect(set.toJson(), source);
    });

    test('keys that violate T1/T2/T3 are preserved verbatim, never repaired',
        () {
      // Constructing these would throw ArgumentError out of the middle of a
      // decode, and anim_core has no `try` to contain it. Preserving them is
      // also the honest answer: the data is someone else's, not ours to fix.
      final broken = <String, Object?>{
        'empty': <String, Object?>{'type': 'scalar', 'keys': <Object?>[]},
        'coincident': <String, Object?>{
          'type': 'scalar',
          'keys': <Object?>[
            <String, Object?>{'t': 0.5, 'value': 1.0},
            <String, Object?>{'t': 0.5, 'value': 2.0},
          ],
        },
        'outOfRange': <String, Object?>{
          'type': 'scalar',
          'keys': <Object?>[
            <String, Object?>{'t': 1.5, 'value': 1.0},
          ],
        },
      };

      for (final entry in broken.entries) {
        expect(Track.fromJson(entry.value), isNull, reason: entry.key);
      }

      final set = TrackSet.fromJson(<String, Object?>{
        'rotation': broken['coincident'],
      });
      expect(set.byKey, isEmpty);
      expect(set.toJson()['rotation'], broken['coincident']);
    });

    test('a keyframe VALUE this build cannot read degrades the same way', () {
      // The asymmetry that has to not exist: an unknown track *type* is
      // preserved-verbatim, so a wrong-typed *value* in one keyframe of one
      // track must be too. Blind-casting it instead throws a TypeError that
      // anim_core has no `try` to contain, so it unwinds out of
      // `Document.fromJson` and costs the user every node in the file — one bad
      // number against a hundred good shapes.
      final malformed = <String, Object?>{
        'scalar value': <String, Object?>{
          'type': 'scalar',
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': 'not a number'},
          ],
        },
        'bool value': <String, Object?>{
          'type': 'bool',
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': 1},
          ],
        },
        'color value': <String, Object?>{
          'type': 'color',
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': '#ff0000'},
          ],
        },
        'vec2 value': <String, Object?>{
          'type': 'vec2',
          'keys': <Object?>[
            <String, Object?>{
              't': 0.0,
              'value': <Object?>[1, 2],
            },
          ],
        },
        'vec2 spatial tangent': <String, Object?>{
          'type': 'vec2',
          'keys': <Object?>[
            <String, Object?>{
              't': 0.0,
              'value': <String, Object?>{'x': 1.0, 'y': 2.0},
              'inTangent': 'sideways',
            },
          ],
        },
        'path pose': <String, Object?>{
          'type': 'path',
          'keys': <Object?>[
            <String, Object?>{
              't': 0.0,
              'value': <String, Object?>{
                'anchors': <String, Object?>{'b0': 'over there'},
              },
            },
          ],
        },
        'easing': <String, Object?>{
          'type': 'scalar',
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': 1.0, 'easing': 'easeInOut'},
          ],
        },
      };

      for (final entry in malformed.entries) {
        expect(Track.fromJson(entry.value), isNull, reason: entry.key);
      }

      // And the container does with it exactly what it does with an unknown
      // type: rides it through untouched, so the client that understands it
      // still can.
      final set = TrackSet.fromJson(<String, Object?>{
        'rotation': malformed['scalar value'],
      });
      expect(set.byKey, isEmpty);
      expect(set.toJson()['rotation'], malformed['scalar value']);
    });

    test('an unrecognised easing KIND still decodes — it is not malformed', () {
      // The distinction the degrade must not blur: a v4 spring easing is
      // modelled as UnknownEasing and the track stays live and evaluable.
      final back = Track.fromJson(<String, Object?>{
        'type': 'scalar',
        'keys': <Object?>[
          <String, Object?>{
            't': 0.0,
            'value': 1.0,
            'easing': <String, Object?>{'kind': 'spring', 'stiffness': 400},
          },
        ],
      });
      expect(back, isA<ScalarTrack>());
      expect((back! as ScalarTrack).keys.single.easing, isA<UnknownEasing>());
    });

    test('track-level unknown keys survive — `pins` is the reserved one', () {
      // docs/v3/02 §7 puts preservation at "Document, Node, Animation,
      // TrackSet, Track and Keyframe level", and names `pins` (path track)
      // among the reserved keys. A later build authors endpoint pins, a stale
      // tab running this build opens the document, the user drags one anchor,
      // and autosave writes them away for good.
      final source = <String, Object?>{
        'type': 'path',
        'pins': <Object?>['b0'],
        'keys': <Object?>[
          <String, Object?>{
            't': 0.0,
            'value': <String, Object?>{
              'anchors': <String, Object?>{
                'b0': <String, Object?>{
                  'position': <String, Object?>{'x': 1.0, 'y': 2.0},
                },
              },
            },
            'easing': <String, Object?>{'kind': 'linear'},
          },
        ],
      };

      final track = Track.fromJson(source);
      expect(track, isA<PathTrack>());
      expect(track!.toJson()['pins'], <Object?>['b0']);

      // Through an op, too: a mutation has not been told anything about a key
      // it cannot read, so rebuilding the key list must not drop it.
      final next = TrackOps.upsertKeyframe(
        track as PathTrack,
        Keyframe<PathPose>(t: 1.0, value: PathPose.empty),
      );
      expect(next.toJson()['pins'], <Object?>['b0']);
      expect(next.keyCount, 2);
    });

    test('a typed key can never be shadowed by a preserved one', () {
      // `withUnknown` splats first and the typed map wins, so a stale copy of
      // `keys` riding in unknownKeys cannot resurrect old geometry.
      final track = ScalarTrack(
        [const Keyframe(t: 0.0, value: 1.0)],
        const <String, Object?>{'type': 'spring', 'keys': <Object?>[]},
      );
      final json = track.toJson();
      expect(json['type'], 'scalar');
      expect(json['keys'], hasLength(1));
    });
  });
}
