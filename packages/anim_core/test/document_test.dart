import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

Map<String, Object?> reencode(Document d) =>
    jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>;

void main() {
  group('Document.create', () {
    test('mints a UUID id and an explicit artboard', () {
      final doc = Document.create(name: 'Untitled');

      expect(doc.schemaVersion, Document.currentSchemaVersion);
      expect(doc.schemaVersion, kSchemaVersion);
      // Legacy's "Project_14" collided across three of the eight samples.
      expect(doc.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(doc.id, isNot(Document.create(name: 'Untitled').id));
      // Explicit, never inferred from whatever the canvas happened to measure.
      expect(doc.artboard, const Vec2(450.2, 250.4));
      expect(doc.rev, 0, reason: 'a document reaches rev 1 on its first save');
      expect(doc.root.children, isEmpty);
    });

    test('mints exactly ONE animation and points defaultAnimationId at it', () {
      // The v1 document invariant (docs/v3/01 §11), established at creation —
      // the only place it can be established without rewriting user data.
      final doc = Document.create(name: 'Untitled');

      expect(doc.animations, hasLength(1));
      expect(doc.defaultAnimationId, doc.animations.single.id);
      expect(doc.defaultAnimation, same(doc.animations.single));
      expect(doc.animations.single.tracks, isEmpty);
      expect(doc.animations.single.id.v, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(doc.animations.single.id,
          isNot(Document.create(name: 'x').animations.single.id));
    });

    test('two uuids in a row differ in the random field, not just the clock',
        () {
      final ids = List.generate(64, (_) => uuidV4()).toSet();
      expect(ids, hasLength(64));
      expect(ids.every((s) => s[14] == '4'), isTrue, reason: 'version nibble');
      expect(ids.every((s) => '89ab'.contains(s[19])), isTrue,
          reason: 'variant nibble');
    });
  });

  group('round trip', () {
    test('a nested tree survives encode -> JSON text -> decode', () {
      final leaf = GroupNode(
        id: const NodeId('n-leaf'),
        name: 'Leaf',
        transform: const Transform2(
          position: Vec2(12.5, -3.25),
          scale: Vec2(2, 0.5),
          pivot: Vec2(225.1, 125.2),
          rotation: -0.4,
          skewX: 0.25,
        ),
        opacity: 0.5,
        visible: false,
        locked: true,
      );
      final doc = Document(
        id: 'doc-1',
        name: 'Signature Reveal',
        artboard: const Vec2(450.2, 250.4),
        background: const Rgba(0.1, 0.2, 0.3, 0.4),
        rev: 7,
        root: GroupNode(
          id: const NodeId('n-root'),
          name: 'Root',
          clipChildren: true,
          children: [leaf],
        ),
      );

      final back = Document.fromJson(reencode(doc));

      expect(back.id, doc.id);
      expect(back.name, doc.name);
      expect(back.artboard, doc.artboard);
      expect(back.background, doc.background);
      expect(back.rev, 7);
      expect(back.root.clipChildren, isTrue);

      final backLeaf = back.root.children.single as GroupNode;
      expect(backLeaf.id, leaf.id);
      expect(backLeaf.transform, leaf.transform);
      expect(backLeaf.opacity, 0.5);
      expect(backLeaf.visible, isFalse);
      expect(backLeaf.locked, isTrue,
          reason: 'locked persists; hover does not');

      // Byte-stable: a second pass must not drift. Autosave runs this loop
      // constantly, so any normalisation here compounds.
      expect(jsonEncode(back.toJson()), jsonEncode(doc.toJson()));
    });

    test('whole-number doubles that Firestore returns as ints still decode',
        () {
      // Firestore stores 1.0 and hands back 1. Under dart2js int and double are
      // the same type so a direct cast works today; under dart2wasm it is a
      // TypeError. Every numeric read goes through d() for exactly this.
      final decoded = Document.fromJson(<String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-int',
        'name': 'ints',
        'artboard': <String, Object?>{'x': 400, 'y': 400},
        'background': <Object?>[0, 0, 0, 1],
        'root': <String, Object?>{'type': 'group', 'id': 'n-root'},
      });

      expect(decoded.artboard, const Vec2(400, 400));
      expect(decoded.background, const Rgba(0, 0, 0, 1));
      expect(decoded.root.name, '', reason: 'absent name defaults to empty');
    });

    test('a document written before `rev` existed decodes as generation 1', () {
      final decoded = Document.fromJson(<String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-norev',
        'name': 'no rev',
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{'type': 'group', 'id': 'n-root'},
      });
      expect(decoded.rev, 1);
    });
  });

  group('forward compatibility (docs/v3/02 §7)', () {
    // The failure this prevents is not a wrong render — it is a stale browser
    // tab autosaving a newer document back to Firestore with fields silently
    // deleted. The user never sees it happen.
    test('unknown document keys are re-emitted verbatim', () {
      final source = <String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-fwd',
        'name': 'from a newer editor',
        'rev': 2,
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{'type': 'group', 'id': 'n-root'},
        'stateMachines': <Object?>[
          <String, Object?>{'id': 'sm-1', 'states': <Object?>[]},
        ],
        'components': <String, Object?>{'c-1': 'reserved'},
      };

      final out = Document.fromJson(source).toJson();
      expect(out['stateMachines'], source['stateMachines']);
      expect(out['components'], source['components']);
    });

    test('animations are typed now, and round-trip through their own decoder',
        () {
      // This test used to assert that `animations` rode through unknownKeys
      // untyped. It changed shape rather than disappearing: the guarantee is
      // still "a document authored by another build is not destroyed by this
      // one", but the fields are modelled, so the proof is a typed round-trip
      // plus a preserved unknown key inside the animation.
      final source = <String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-anim',
        'name': 'has animation',
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{
          'type': 'group',
          'id': 'n-root',
          'children': <Object?>[
            <String, Object?>{
              'type': 'path',
              'id': 'n-sq',
              'name': 'Square',
              'path': <String, Object?>{
                'closed': true,
                'anchors': <Object?>[
                  <String, Object?>{
                    'id': 'b0',
                    'position': <String, Object?>{'x': 40.0, 'y': 40.0},
                  },
                ],
              },
            },
          ],
        },
        'animations': <Object?>[
          <String, Object?>{
            'id': 'anim-main',
            'name': 'Main',
            'durationSeconds': 2.6,
            'fps': 60,
            'loop': 'once',
            'markers': <Object?>[],
            'tracks': <String, Object?>{
              'n-sq': <String, Object?>{
                'rotation': <String, Object?>{
                  'type': 'scalar',
                  'keys': <Object?>[
                    <String, Object?>{'t': 0.0, 'value': 0.0},
                    <String, Object?>{'t': 1.0, 'value': 12.5664},
                  ],
                },
              },
            },
          },
        ],
        'defaultAnimationId': 'anim-main',
      };

      final doc = Document.fromJson(source);
      final anim = doc.animations.single;

      expect(anim.id, const AnimationId('anim-main'));
      expect(anim.durationSeconds, 2.6);
      expect(anim.loop, LoopMode.once);
      expect(
          anim
              .tracksFor(const NodeId('n-sq'))
              .scalar(PropKey.rotation)
              ?.sampleAt(0.5),
          closeTo(6.2832, 1e-9));
      expect(anim.unknownKeys['markers'], isEmpty);

      // Resolved by id, never `animations.first`.
      expect(doc.defaultAnimation?.id, const AnimationId('anim-main'));
      expect(reencode(doc)['defaultAnimationId'], 'anim-main');
      expect(jsonEncode(Document.fromJson(reencode(doc)).toJson()),
          jsonEncode(doc.toJson()));
    });

    test('a defaultAnimationId pointing nowhere resolves to null, not a crash',
        () {
      final doc = Document.fromJson(<String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-stale',
        'name': 'stale pointer',
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{'type': 'group', 'id': 'n-root'},
        'defaultAnimationId': 'anim-deleted',
      });

      // Twenty call sites doing `animations.first` is twenty crashes on an
      // empty list (docs/v3/01 §11).
      expect(doc.animations, isEmpty);
      expect(doc.defaultAnimationId, const AnimationId('anim-deleted'));
      expect(doc.defaultAnimation, isNull);
    });

    test('decoding a document with no animations does not synthesize one', () {
      // Document.create mints one; decode must not, or the next autosave
      // rewrites the user's file to satisfy an invariant it never asked for.
      final doc = Document.fromJson(<String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-none',
        'name': 'static',
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{'type': 'group', 'id': 'n-root'},
      });

      expect(doc.animations, isEmpty);
      expect(doc.defaultAnimationId, isNull);
      expect(doc.toJson().containsKey('defaultAnimationId'), isFalse);
    });

    test('an unknown node type round-trips byte-for-byte', () {
      final bone = <String, Object?>{
        'type': 'bone',
        'id': 'n-bone',
        'name': 'Spine',
        'length': 42.0,
        'children': <Object?>[],
      };
      final source = <String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-bone',
        'name': 'v4 doc',
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{
          'type': 'group',
          'id': 'n-root',
          'children': <Object?>[bone],
        },
      };

      final doc = Document.fromJson(source);
      final node = doc.root.children.single;
      expect(node, isA<UnknownNode>());
      expect((node as UnknownNode).rawType, 'bone');

      // Verbatim, not re-encoded through the common fields: routing it through
      // the typed encoder would invent an explicit "opacity": 1.0 that the
      // source never had.
      expect(node.toJson(), bone);
    });

    test('an unclaimed node key survives on a typed node', () {
      // `recipe` became a claimed, typed field at M1 (see recipe_test.dart);
      // `skin` stands in for the next one — a field a v4 client adds to a node
      // this build fully understands. It must ride through `unknownKeys` on a
      // typed PathNode rather than being dropped, or a stale tab's autosave
      // deletes it for good.
      final skin = <String, Object?>{
        'bones': <Object?>['b0', 'b1'],
        'weights': <Object?>[0.5, 0.5],
      };
      final node = Node.fromJson(<String, Object?>{
        'type': 'path',
        'id': 'n-rect',
        'name': 'Square',
        'path': <String, Object?>{'closed': true, 'anchors': <Object?>[]},
        'skin': skin,
      });

      expect(node, isA<PathNode>());
      expect(node.toJson()['skin'], skin);
    });

    test('an UnknownNode is re-emitted byte for byte (AC-1.2.4)', () {
      // Not "an equivalent node" — the SAME map. Re-encoding through the typed
      // fields would normalise an absent `opacity` into an explicit 1.0 and an
      // absent `transform` into a full identity object, which is the silent
      // rewrite UnknownNode exists to prevent. A v2 document opened by a v1
      // client and autosaved must come back out unchanged.
      final bone = <String, Object?>{
        'type': 'bone',
        'id': 'n-bone',
        'name': 'Upper arm',
        'length': 42.5,
        'constraint': <String, Object?>{'kind': 'ik', 'target': 'n-hand'},
        'children': <Object?>[
          <String, Object?>{'type': 'bone', 'id': 'n-bone-2', 'length': 20.0},
        ],
      };
      final source = <String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-bones',
        'name': 'Rigged',
        'artboard': <String, Object?>{'x': 450.2, 'y': 250.4},
        'root': <String, Object?>{
          'type': 'group',
          'id': 'n-root',
          'children': <Object?>[bone],
        },
      };

      final once = Document.fromJson(source);
      final unknown = once.root.children.single;
      expect(unknown, isA<UnknownNode>());
      expect(unknown.toJson(), bone);

      // And it survives a second full trip, which is what an autosave loop is.
      final twice = Document.fromJson(reencode(once));
      expect(twice.root.children.single.toJson(), bone);
      // Its nested children are raw JSON, never decoded into Node objects —
      // this build has no idea what a bone's children mean.
      expect((twice.root.children.single as UnknownNode).raw['children'],
          bone['children']);
    });

    test('rev round-trips exactly, and only bumpRev advances it (AC-1.2.3)',
        () {
      // rev is the one persisted field the evaluator never reads. It must
      // survive a save/load cycle untouched, because v1.1 turns it into
      // optimistic concurrency and a rev that drifts by one on every open would
      // reject every save.
      var doc = Document.create(name: 'Rev').copyWith(rev: 41);
      expect(Document.fromJson(reencode(doc)).rev, 41);

      // An edit does not touch it; only a persisted save does.
      doc = doc.copyWith(name: 'Rev renamed');
      expect(doc.rev, 41);
      expect(doc.bumpRev().rev, 42);

      // Ten trips, no drift.
      for (var n = 0; n < 10; n++) {
        doc = Document.fromJson(reencode(doc));
      }
      expect(doc.rev, 41);
    });

    test('an unrecognised node type is still preserved', () {
      final path = <String, Object?>{
        'type': 'lathe',
        'id': 'n-sig',
        'name': 'Signature',
        'path': <String, Object?>{'closed': false, 'anchors': <Object?>[]},
      };
      final node = Node.fromJson(path);
      expect(node, isA<UnknownNode>());
      expect(node.toJson(), path);
    });

    test('a newer schemaVersion opens read-only', () {
      final doc = Document.fromJson(<String, Object?>{
        'schemaVersion': 4,
        'id': 'doc-v4',
        'name': 'from the future',
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{'type': 'group', 'id': 'n-root'},
      });
      // Key preservation protects syntax, not semantics: this client cannot
      // know a v4 `skin` must stay consistent with anchors it lets you delete.
      expect(doc.isReadOnly, isTrue);
      expect(Document.create(name: 'x').isReadOnly, isFalse);
    });

    test('one unreadable keyframe value does not cost the whole document', () {
      // The blast radius is the point. A `"value": "not a number"` on one
      // scalar track used to throw a TypeError out of the middle of the decode
      // — anim_core has no `try` to contain it — so the editor reported the
      // file as corrupt and no geometry was recoverable. Degrading that one
      // track to preserved-verbatim is the behaviour the surrounding code
      // already implements for an unknown track *type*.
      final source = <String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-sq',
        'name': 'square',
        'rev': 4,
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{
          'type': 'group',
          'id': 'n-root',
          'children': <Object?>[
            <String, Object?>{
              'type': 'path',
              'id': 'p1',
              'name': 'Square',
              'path': <String, Object?>{
                'closed': true,
                'anchors': <Object?>[
                  <String, Object?>{
                    'id': 'b0',
                    'position': <String, Object?>{'x': 0.0, 'y': 0.0},
                  },
                  <String, Object?>{
                    'id': 'b1',
                    'position': <String, Object?>{'x': 10.0, 'y': 0.0},
                  },
                  <String, Object?>{
                    'id': 'b2',
                    'position': <String, Object?>{'x': 10.0, 'y': 10.0},
                  },
                ],
              },
            },
          ],
        },
        'animations': <Object?>[
          <String, Object?>{
            'id': 'a1',
            'name': 'Main',
            'tracks': <String, Object?>{
              'p1': <String, Object?>{
                'rotation': <String, Object?>{
                  'type': 'scalar',
                  'keys': <Object?>[
                    <String, Object?>{'t': 0.0, 'value': 'not a number'},
                  ],
                },
              },
            },
          },
        ],
      };

      final doc = Document.fromJson(source);
      final node = doc.root.children.single as PathNode;
      expect(node.path.anchors, hasLength(3));
      expect(
          doc.animations.single
              .tracksFor(const NodeId('p1'))
              .scalar(PropKey.rotation),
          isNull,
          reason: 'preserved, never evaluated');

      // And the unreadable track rides back out verbatim: the bad data belongs
      // to whoever wrote it, and this build is the one that has to not lose it.
      final animations = doc.toJson()['animations']! as List<Object?>;
      final tracks = (animations.single as Map<String, Object?>)['tracks']!
          as Map<String, Object?>;
      expect(tracks['p1'], <String, Object?>{
        'rotation': <String, Object?>{
          'type': 'scalar',
          'keys': <Object?>[
            <String, Object?>{'t': 0.0, 'value': 'not a number'},
          ],
        },
      });
    });
  });

  group('invariants', () {
    test('a duplicate NodeId is rejected at decode, not at animation time', () {
      // Governing rule 2 (docs/v3/01 §1): every track lookup joins on this id.
      // A duplicate does not fail loudly later — it animates the wrong node.
      expect(
        () => Document.fromJson(<String, Object?>{
          'schemaVersion': 3,
          'id': 'doc-dup',
          'name': 'dup',
          'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
          'root': <String, Object?>{
            'type': 'group',
            'id': 'n-root',
            'children': <Object?>[
              <String, Object?>{'type': 'group', 'id': 'n-a', 'name': 'A'},
              <String, Object?>{'type': 'group', 'id': 'n-a', 'name': 'B'},
            ],
          },
        }),
        throwsA(isA<DocumentException>()),
      );
    });

    test('walk() yields paint order, index 0 back-most', () {
      final doc = Document(
        id: 'd',
        name: 'z-order',
        artboard: const Vec2(100, 100),
        root: GroupNode(
          id: const NodeId('n-root'),
          name: 'Root',
          children: const [
            GroupNode(id: NodeId('n-back'), name: 'Back'),
            GroupNode(id: NodeId('n-front'), name: 'Front'),
          ],
        ),
      );

      expect(doc.walk().map((n) => n.id.v).toList(),
          ['n-root', 'n-back', 'n-front']);
      expect(doc.nodeIndex.keys.map((k) => k.v).toSet(),
          {'n-root', 'n-back', 'n-front'});
    });

    group('P6: orphan poses are dropped at decode', () {
      Map<String, Object?> docWith(List<String> topology, List<String> posed) =>
          <String, Object?>{
            'schemaVersion': 3,
            'id': 'doc-orphan',
            'name': 'stale poses',
            'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
            'root': <String, Object?>{
              'type': 'group',
              'id': 'n-root',
              'children': <Object?>[
                <String, Object?>{
                  'type': 'path',
                  'id': 'n-sq',
                  'name': 'Square',
                  'path': <String, Object?>{
                    'closed': true,
                    'anchors': <Object?>[
                      for (final id in topology)
                        <String, Object?>{
                          'id': id,
                          'position': <String, Object?>{'x': 1.0, 'y': 2.0},
                        },
                    ],
                  },
                },
              ],
            },
            'animations': <Object?>[
              <String, Object?>{
                'id': 'anim-main',
                'name': 'Main',
                'tracks': <String, Object?>{
                  'n-sq': <String, Object?>{
                    'path': <String, Object?>{
                      'type': 'path',
                      'keys': <Object?>[
                        <String, Object?>{
                          't': 0.0,
                          'value': <String, Object?>{
                            'anchors': <String, Object?>{
                              for (final id in posed)
                                id: <String, Object?>{
                                  'position': <String, Object?>{
                                    'x': 3.0,
                                    'y': 4.0,
                                  },
                                },
                            },
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
            'defaultAnimationId': 'anim-main',
          };

      Set<String> posedIds(Document d) => (d.animations.single
              .tracksFor(const NodeId('n-sq'))
              .pathTrack()!
              .keys
              .single
              .value
              .anchors
              .keys)
          .map((k) => k.v)
          .toSet();

      final warnings = <String>[];
      setUp(() {
        warnings.clear();
        onDecodeWarning = warnings.add;
      });
      tearDown(() => onDecodeWarning = (_) {});

      test('a pose for an id not in the topology is dropped, with a warning',
          () {
        // Orphan poses are the only way stale data survives the id join. They
        // are never read at render time (the evaluator iterates topology), but
        // they resurrect the moment an id is reused or a track is
        // retopologized — and they keep the commit invariant permanently red.
        final doc =
            Document.fromJson(docWith(['b0', 'b1'], ['b0', 'b1', 'b2']));

        expect(posedIds(doc), {'b0', 'b1'});
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('orphan pose'));
        expect(warnings.single, contains('n-sq'));
      });

      test('dropping is not throwing: the document still opens', () {
        final doc = Document.fromJson(docWith(['b0'], ['zz']));

        expect(posedIds(doc), isEmpty,
            reason: 'an all-orphan key is legal — resolvePose falls back to '
                'the node rest pose for every anchor');
        expect(doc.animations, hasLength(1));
      });

      test('a clean document is untouched and warns about nothing', () {
        final doc = Document.fromJson(docWith(['b0', 'b1'], ['b0', 'b1']));

        expect(posedIds(doc), {'b0', 'b1'});
        expect(warnings, isEmpty);
        // The repair pass must not perturb what it did not repair: a second
        // decode of the encoded form is byte-identical.
        expect(jsonEncode(Document.fromJson(reencode(doc)).toJson()),
            jsonEncode(doc.toJson()));
      });

      test('a path track on a node that is not a PathNode loses every pose',
          () {
        final source = docWith(['b0'], ['b0']);
        final root = source['root']! as Map<String, Object?>;
        root['children'] = <Object?>[
          <String, Object?>{'type': 'group', 'id': 'n-sq', 'name': 'Group'},
        ];

        final doc = Document.fromJson(source);
        expect(posedIds(doc), isEmpty);
        expect(warnings, hasLength(1));
      });
    });

    test('bumpRev advances by exactly one and touches nothing else', () {
      final doc = Document.create(name: 'save me');
      final saved = doc.bumpRev();

      expect(saved.rev, doc.rev + 1);
      expect(saved.id, doc.id);
      expect(saved.root, same(doc.root));
    });
  });
}
