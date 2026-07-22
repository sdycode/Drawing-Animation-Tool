/// The required/optional decode boundary (docs/v3/06 M1, F10.2).
///
/// Two docs appear to disagree — docs/v3/06 M1 wants "missing required subtree
/// throws with a path", docs/v3/08 §2 wants "decode degrades, never
/// validates-and-throws" — and the resolution is that they describe different
/// halves of the same file, split by required vs optional. `DocumentException`
/// carries the written statement of that boundary; this file is the executable
/// one. Both halves are tested together, in one file, on purpose: they are a
/// single decision, and a future reader who finds only one of them will
/// re-derive the other wrongly.
library;

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// A minimal but *complete* valid document. Every required-field test deletes
/// exactly one key from a deep copy of this and asserts the location.
Map<String, Object?> validDocument() => <String, Object?>{
      'schemaVersion': 3,
      'id': 'doc-1',
      'name': 'Fixture',
      'rev': 4,
      'artboard': <String, Object?>{'x': 450.2, 'y': 250.4},
      'background': <Object?>[0.0, 0.0, 0.0, 0.0],
      'defaultAnimationId': 'anim-main',
      'root': <String, Object?>{
        'type': 'group',
        'id': 'n-root',
        'name': 'Root',
        'children': <Object?>[
          <String, Object?>{'type': 'group', 'id': 'n-mid', 'name': 'Mid'},
          <String, Object?>{'type': 'group', 'id': 'n-mid2', 'name': 'Mid 2'},
          <String, Object?>{
            'type': 'path',
            'id': 'n-sq',
            'name': 'Square',
            'path': <String, Object?>{
              'closed': true,
              'anchors': <Object?>[
                for (var k = 0; k < 8; k++)
                  <String, Object?>{
                    'id': 'a$k',
                    'position': <String, Object?>{'x': k * 10.0, 'y': k * 5.0},
                  },
              ],
            },
            'fills': <Object?>[
              <String, Object?>{
                'id': 'p-body',
                'paint': <String, Object?>{
                  'type': 'solid',
                  'color': <Object?>[0.9, 0.2, 0.2, 1.0],
                },
              },
            ],
          },
        ],
      },
      'animations': <Object?>[
        <String, Object?>{'id': 'anim-main', 'name': 'Main'},
      ],
    };

/// Deletes the value at a slash/`[i]` path and returns the mutated document.
Map<String, Object?> without(String path) => _edit(path, remove: true);

/// Replaces the value at a slash/`[i]` path with [replacement].
Map<String, Object?> replacing(String path, Object? replacement) =>
    _edit(path, replacement: replacement);

Map<String, Object?> _edit(String path,
    {bool remove = false, Object? replacement}) {
  final doc = validDocument();
  final steps = _split(path);
  Object? cursor = doc;
  for (var n = 0; n < steps.length - 1; n++) {
    cursor = switch (steps[n]) {
      final int index => (cursor! as List<Object?>)[index],
      final String key => (cursor! as Map<String, Object?>)[key],
      _ => null,
    };
  }
  final last = steps.last;
  if (last is int) {
    final list = cursor! as List<Object?>;
    if (remove) {
      list.removeAt(last);
    } else {
      list[last] = replacement;
    }
  } else {
    final map = cursor! as Map<String, Object?>;
    if (remove) {
      map.remove(last as String);
    } else {
      map[last as String] = replacement;
    }
  }
  return doc;
}

List<Object> _split(String path) => <Object>[
      for (final segment in path.split('/'))
        ...segment.endsWith(']')
            ? <Object>[
                segment.substring(0, segment.indexOf('[')),
                int.parse(segment.substring(
                    segment.indexOf('[') + 1, segment.length - 1)),
              ]
            : <Object>[segment],
    ];

Matcher throwsAt(String path) => throwsA(isA<DocumentException>()
    .having((e) => e.path, 'path', path)
    .having((e) => e.toString(), 'toString', contains(path)));

void main() {
  group('the STRICT half — a required field throws WITH its path', () {
    // docs/v3/01 §11: "an invalid document with no location is what makes a
    // corrupt file unfixable." Before M1 these were bare `j['id']! as String`
    // and `Vec2.fromJson(j['artboard'])` casts, which surfaced as a TypeError
    // or a NoSuchMethodError from somewhere inside a decode — no field name and
    // no location, so neither the user nor a support thread could act on it.

    test('the valid fixture decodes, so every failure below is the edit', () {
      final doc = Document.fromJson(validDocument());
      expect(doc.id, 'doc-1');
      expect(doc.rev, 4);
      expect(doc.artboard, const Vec2(450.2, 250.4));
      expect(doc.root.children, hasLength(3));
    });

    // The four root-level structures a document cannot exist without. Without
    // any one of them there is no document to show, and a silently empty canvas
    // reads to the user as data loss they have already suffered.
    for (final field in <String>['schemaVersion', 'id', 'artboard', 'root']) {
      test('missing root `$field` throws naming $field', () {
        expect(() => Document.fromJson(without(field)), throwsAt(field));
      });

      test('unusable root `$field` throws naming $field', () {
        expect(() => Document.fromJson(replacing(field, <Object?>['wrong'])),
            throwsAt(field));
      });
    }

    test('a missing required field says "missing", a wrong one says "expected"',
        () {
      // The distinction matters to whoever has to repair the file by hand.
      expect(
        () => Document.fromJson(without('id')),
        throwsA(isA<DocumentException>()
            .having((e) => e.message, 'message', contains('missing'))),
      );
      expect(
        () => Document.fromJson(replacing('id', 7)),
        throwsA(isA<DocumentException>()
            .having((e) => e.message, 'message', contains('expected string'))),
      );
    });

    test('a deeply nested malformed anchor names the anchor, not the document',
        () {
      // This is the whole value of the feature. The path has to survive four
      // levels of nesting and two array indices to be worth threading.
      const at = 'root/children[2]/path/anchors[7]';
      expect(() => Document.fromJson(replacing(at, 'not an anchor')),
          throwsAt(at));
      expect(() => Document.fromJson(without('$at/id')), throwsAt('$at/id'));
      expect(() => Document.fromJson(without('$at/position')),
          throwsAt('$at/position'));
      // Down to the offending component of the offending vector.
      expect(() => Document.fromJson(without('$at/position/y')),
          throwsAt('$at/position/y'));
    });

    test('a duplicate AnchorId is located at the second occurrence', () {
      // Invariant P1, re-checked at decode. The validating factory rejects it
      // too, but with an ArgumentError naming only the id — and a duplicate id
      // silently animates one anchor with another's pose, so it has to be
      // findable, not merely fatal.
      expect(
        () => Document.fromJson(
            replacing('root/children[2]/path/anchors[7]/id', 'a3')),
        throwsAt('root/children[2]/path/anchors[7]'),
      );
    });

    test('every other required structure reports a real path', () {
      const node = 'root/children[2]';
      final cases = <String, String>{
        // A node with no discriminator has nothing for UnknownNode to preserve.
        '$node/type': '$node/type',
        '$node/id': '$node/id',
        // A path node with no geometry has nothing to draw and nothing to key.
        '$node/path': '$node/path',
        '$node/fills[0]/id': '$node/fills[0]/id',
        '$node/fills[0]/paint': '$node/fills[0]/paint',
        // A KNOWN paint type with a broken body: unknown types degrade, but a
        // solid whose colour this build claims to understand and cannot must
        // not be quietly repainted black.
        '$node/fills[0]/paint/color': '$node/fills[0]/paint/color',
        // defaultAnimationId joins to it; an invented id would re-save as a
        // different animation on every open.
        'animations[0]/id': 'animations[0]/id',
      };
      for (final entry in cases.entries) {
        expect(
            () => Document.fromJson(without(entry.key)), throwsAt(entry.value),
            reason: entry.key);
      }
    });

    test('a present-but-broken optional container is located too', () {
      // These have always thrown — there is no preserve-verbatim variant for
      // "children is a string". What M1 adds is the address.
      expect(() => Document.fromJson(replacing('root/children', 'nope')),
          throwsAt('root/children'));
      expect(() => Document.fromJson(replacing('animations', 'nope')),
          throwsAt('animations'));
      expect(
          () => Document.fromJson(
              replacing('root/children[2]/fills', <String, Object?>{})),
          throwsAt('root/children[2]/fills'));
      expect(
          () =>
              Document.fromJson(replacing('root/children[0]', <String, Object?>{
                'type': 'group',
                'id': 'n-mid',
                'transform': <String, Object?>{'scale': 'big'},
              })),
          throwsAt('root/children[0]/transform/scale'));
    });

    test('a present-but-wrong-type optional scalar is located, not a TypeError',
        () {
      // The optional bool/String fields used to read through a bare `v as bool`
      // / `v as String` inside opt(), so a PRESENT-but-mistyped value threw
      // Dart's raw _TypeError — no field name, no location, not a
      // DocumentException — while the byte-adjacent optional `opacity` threw a
      // clean located DocumentException via reqDouble. A single mistyped flag on
      // the required root node made the whole document unopenable with an
      // unlocatable error, which is the exact defect this milestone exists to
      // kill. Every optional scalar now fails the same way its numeric siblings
      // already did: with an address (docs/v3/08 §2's present-but-broken
      // carve-out).
      final cases = <String, Object?>{
        'name': 5, // document name
        'root/name': 5,
        'root/visible': 'yes',
        'root/locked': 1,
        'root/clipChildren': 'x',
        'root/children[2]/path/closed': 'no',
        'root/children[2]/fills[0]/visible': 'no',
        'animations[0]/name': 5,
      };
      for (final entry in cases.entries) {
        expect(() => Document.fromJson(replacing(entry.key, entry.value)),
            throwsAt(entry.key),
            reason: entry.key);
      }
      // A stroke's `visible` shares the reqBool path; the fixture has no stroke,
      // so it is supplied here.
      final withStroke = replacing('root/children[2]/strokes', <Object?>[
        <String, Object?>{
          'id': 's-edge',
          'paint': <String, Object?>{
            'type': 'solid',
            'color': <Object?>[0.0, 0.0, 0.0, 1.0],
          },
          'visible': 'no',
        },
      ]);
      expect(() => Document.fromJson(withStroke),
          throwsAt('root/children[2]/strokes[0]/visible'));
    });

    test('the root path is spelled bare, never with a leading slash', () {
      // Cosmetic, and it is the string a user pastes into a bug report.
      expect(
        () => Document.fromJson(without('artboard')),
        throwsA(isA<DocumentException>()
            .having((e) => e.path, 'path', isNot(startsWith('/')))),
      );
    });
  });

  group('the DEGRADING half — none of these may throw', () {
    // docs/v3/08 §2: a field feature A adds on Monday must not make the
    // document unloadable in feature B on Tuesday. Everything here is data this
    // build cannot interpret; all of it survives to the next save.

    /// Every case is `(what is malformed, how the source is broken)`.
    final cases = <String, Map<String, Object?> Function()>{
      'unknown node type -> UnknownNode': () => replacing(
            'root/children[0]',
            <String, Object?>{'type': 'bone', 'id': 'n-bone', 'length': 3.0},
          ),
      'unknown paint.type -> UnknownPaint': () => replacing(
            'root/children[2]/fills[0]/paint',
            <String, Object?>{'type': 'conicGradient', 'turns': 2.0},
          ),
      'unknown easing.kind -> UnknownEasing': () => replacing(
            'animations[0]',
            <String, Object?>{
              'id': 'anim-main',
              'tracks': <String, Object?>{
                'n-sq': <String, Object?>{
                  'rotation': <String, Object?>{
                    'type': 'scalar',
                    'keys': <Object?>[
                      <String, Object?>{
                        't': 0.0,
                        'value': 0.0,
                        'easing': <String, Object?>{
                          'kind': 'spring',
                          'stiffness': 90.0,
                        },
                      },
                      <String, Object?>{'t': 1.0, 'value': 6.28},
                    ],
                  },
                },
              },
            },
          ),
      'unknown recipe.type -> UnknownRecipe': () => replacing(
            'root/children[2]/recipe',
            <String, Object?>{'type': 'spiral', 'turns': 3.0},
          ),
      'malformed track (coincident keys) -> TrackSet.unknownKeys': () =>
          replacing(
            'animations[0]',
            <String, Object?>{
              'id': 'anim-main',
              'tracks': <String, Object?>{
                'n-sq': <String, Object?>{
                  // legacy Squares.json section 3: three keys at exactly the
                  // same t, which is the divide-by-zero NaN T2 exists to reject.
                  'opacity': <String, Object?>{
                    'type': 'scalar',
                    'keys': <Object?>[
                      <String, Object?>{'t': 0.2, 'value': 1.0},
                      <String, Object?>{'t': 0.2, 'value': 0.5},
                      <String, Object?>{'t': 0.2, 'value': 0.0},
                    ],
                  },
                },
              },
            },
          ),
      'malformed track (unreadable value) -> TrackSet.unknownKeys': () =>
          replacing(
            'animations[0]',
            <String, Object?>{
              'id': 'anim-main',
              'tracks': <String, Object?>{
                'n-sq': <String, Object?>{
                  'opacity': <String, Object?>{
                    'type': 'scalar',
                    'keys': <Object?>[
                      <String, Object?>{'t': 0.0, 'value': 'opaque'},
                    ],
                  },
                },
              },
            },
          ),
      'wrong track type for the property -> TrackSet.unknownKeys': () =>
          replacing(
            'animations[0]',
            <String, Object?>{
              'id': 'anim-main',
              'tracks': <String, Object?>{
                'n-sq': <String, Object?>{
                  'rotation': <String, Object?>{
                    'type': 'vec2',
                    'keys': <Object?>[
                      <String, Object?>{
                        't': 0.0,
                        'value': <String, Object?>{'x': 1.0, 'y': 2.0},
                      },
                    ],
                  },
                },
              },
            },
          ),
      'unknown property name -> TrackSet.unknownKeys': () => replacing(
            'animations[0]',
            <String, Object?>{
              'id': 'anim-main',
              'tracks': <String, Object?>{
                'n-sq': <String, Object?>{
                  'blurRadius': <String, Object?>{
                    'type': 'scalar',
                    'keys': <Object?>[
                      <String, Object?>{'t': 0.0, 'value': 3.0},
                    ],
                  },
                },
              },
            },
          ),
      'orphan pose -> dropped with a warning': () => replacing(
            'animations[0]',
            <String, Object?>{
              'id': 'anim-main',
              'tracks': <String, Object?>{
                'n-sq': <String, Object?>{
                  'path': <String, Object?>{
                    'type': 'path',
                    'keys': <Object?>[
                      <String, Object?>{
                        't': 0.0,
                        'value': <String, Object?>{
                          'anchors': <String, Object?>{
                            'a0': <String, Object?>{
                              'position': <String, Object?>{'x': 0.0, 'y': 0.0},
                            },
                            'ghost': <String, Object?>{
                              'position': <String, Object?>{'x': 9.0, 'y': 9.0},
                            },
                          },
                        },
                      },
                    ],
                  },
                },
              },
            },
          ),
      'unknown key at the document level': () =>
          replacing('stateMachines', <Object?>['sm-1']),
      'unknown key at the node level': () =>
          replacing('root/children[2]/skin', <String, Object?>{'bones': 2}),
      'unknown key at the animation level': () =>
          replacing('animations[0]/markers', <Object?>['intro']),
      'unrecognised enum name (loop)': () =>
          replacing('animations[0]/loop', 'boomerang'),
      'unrecognised enum name (AnchorKind)': () =>
          replacing('root/children[2]/path/anchors[3]/kind', 'quadratic'),
      'unrecognised enum name (StrokeJoin)': () => replacing(
            'root/children[2]/fills',
            <Object?>[
              <String, Object?>{
                'id': 'p-body',
                'paint': <String, Object?>{
                  'type': 'solid',
                  'color': <Object?>[0.0, 0.0, 0.0, 1.0],
                },
                'rule': 'wraparound',
              },
            ],
          ),
      'every optional field absent': () => <String, Object?>{
            'schemaVersion': 3,
            'id': 'doc-bare',
            'artboard': <String, Object?>{'x': 1, 'y': 1},
            'root': <String, Object?>{'type': 'group', 'id': 'n-root'},
          },
      'defaultAnimationId pointing at nothing': () =>
          replacing('defaultAnimationId', 'anim-deleted'),
      'defaultAnimationId explicitly null': () =>
          replacing('defaultAnimationId', null),
      'recipe explicitly null': () =>
          replacing('root/children[2]/recipe', null),
      'an int where the format says double': () =>
          replacing('artboard', <String, Object?>{'x': 450, 'y': 250}),
    };

    for (final entry in cases.entries) {
      test('${entry.key} — decodes and survives a re-save', () {
        final source = entry.value();
        final doc = Document.fromJson(source);
        // Decoding is only half of it. The point of degrading rather than
        // throwing is that the data comes back OUT, so a stale tab's autosave
        // does not delete what it could not read.
        expect(() => Document.fromJson(doc.toJson()), returnsNormally);
      });
    }

    test('the preserved data is actually still there after a round trip', () {
      // The table above proves nothing throws. This proves nothing is lost —
      // the failure mode is a decoder that "degrades" by silently dropping.
      var doc =
          Document.fromJson(replacing('stateMachines', <Object?>['sm-1']));
      doc = Document.fromJson(doc.toJson());
      expect(doc.unknownKeys['stateMachines'], <Object?>['sm-1']);

      doc = Document.fromJson(
          replacing('root/children[2]/skin', <String, Object?>{'bones': 2}));
      doc = Document.fromJson(doc.toJson());
      expect(doc.root.children[2].unknownKeys['skin'],
          <String, Object?>{'bones': 2});

      final conic = <String, Object?>{'type': 'conicGradient', 'turns': 2.0};
      doc = Document.fromJson(
          replacing('root/children[2]/fills[0]/paint', conic));
      doc = Document.fromJson(doc.toJson());
      final fill = (doc.root.children[2] as PathNode).fills.single;
      expect(fill.paint, isA<UnknownPaint>());
      expect(fill.paint.toJson(), conic);
    });

    test('an orphan pose is dropped AND announced', () {
      // Dropping is right — an orphan resurrects the moment an id is reused —
      // but silence is not. The one thing worse than dropping data is dropping
      // it invisibly, and anim_core cannot import a logger.
      final seen = <String>[];
      final previous = onDecodeWarning;
      onDecodeWarning = seen.add;
      addTearDown(() => onDecodeWarning = previous);

      final doc = Document.fromJson(replacing(
        'animations[0]',
        <String, Object?>{
          'id': 'anim-main',
          'tracks': <String, Object?>{
            'n-sq': <String, Object?>{
              'path': <String, Object?>{
                'type': 'path',
                'keys': <Object?>[
                  <String, Object?>{
                    't': 0.0,
                    'value': <String, Object?>{
                      'anchors': <String, Object?>{
                        'a0': <String, Object?>{
                          'position': <String, Object?>{'x': 0.0, 'y': 0.0},
                        },
                        'ghost': <String, Object?>{
                          'position': <String, Object?>{'x': 9.0, 'y': 9.0},
                        },
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      ));

      final pose = doc.animations.single
          .tracksFor(const NodeId('n-sq'))
          .pathTrack()!
          .keys
          .single
          .value;
      expect(pose.anchors.keys.map((k) => k.v), <String>['a0']);
      expect(seen, hasLength(1));
      expect(seen.single, contains('orphan'));
      expect(seen.single, contains('n-sq'));
    });
  });

  group('numeric hygiene (docs/v3/00 §6)', () {
    test('int-valued JSON decodes everywhere a double is expected', () {
      // Firestore hands back `1` for a value written as `1.0`. Under dart2js
      // int and double are the same thing so a bare `as double` works; under
      // dart2wasm they are distinct and every one of those casts is a runtime
      // TypeError. Every numeric read routes through d() or i().
      final source = validDocument();
      source['artboard'] = <String, Object?>{'x': 450, 'y': 250};
      source['background'] = <Object?>[0, 0, 0, 1];
      source['rev'] = 4;
      final children = (source['root']! as Map<String, Object?>)['children']!
          as List<Object?>;
      final node = children[2]! as Map<String, Object?>;
      node['opacity'] = 1;
      node['transform'] = <String, Object?>{
        'position': <String, Object?>{'x': 3, 'y': 4},
        'rotation': 0,
        'skewX': 0,
      };
      ((node['path']! as Map<String, Object?>)['anchors']!
          as List<Object?>)[0] = <String, Object?>{
        'id': 'a0',
        'position': <String, Object?>{'x': 0, 'y': 0},
      };

      final doc = Document.fromJson(source);
      expect(doc.artboard, const Vec2(450.0, 250.0));
      expect(doc.background, const Rgba(0, 0, 0, 1));
      expect(doc.root.children[2].opacity, 1.0);
      expect(doc.root.children[2].transform.position, const Vec2(3, 4));
    });

    test('a non-numeric value where a number belongs is located, not coerced',
        () {
      expect(() => Document.fromJson(replacing('artboard/x', '450.2')),
          throwsAt('artboard/x'));
      expect(() => Document.fromJson(replacing('rev', '7')), throwsAt('rev'));
      expect(() => Document.fromJson(replacing('schemaVersion', '3')),
          throwsAt('schemaVersion'));
      expect(
          () => Document.fromJson(replacing('background', <Object?>[0, 0, 0])),
          throwsAt('background'));
      expect(
          () =>
              Document.fromJson(replacing('root/children[2]/opacity', 'half')),
          throwsAt('root/children[2]/opacity'));
    });
  });
}
