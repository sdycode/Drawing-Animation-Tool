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

    test('animations survive even though they are not modelled yet', () {
      // Tracks arrive at M4. Until then `animations` rides in unknownKeys
      // rather than being dropped, so a document authored by a later build is
      // not destroyed by this one. When Animation is typed, this test changes
      // shape — it does not disappear.
      final animations = <Object?>[
        <String, Object?>{'id': 'anim-main', 'name': 'Main', 'duration': 1.5},
      ];
      final source = <String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-anim',
        'name': 'has animation',
        'artboard': <String, Object?>{'x': 100.0, 'y': 100.0},
        'root': <String, Object?>{'type': 'group', 'id': 'n-root'},
        'animations': animations,
        'defaultAnimationId': 'anim-main',
      };

      final out = Document.fromJson(source).toJson();
      expect(out['animations'], animations);
      expect(out['defaultAnimationId'], 'anim-main');
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
      // `recipe` is a real spec'd field with no Dart type until the shape tools
      // (M3). It rides through unknownKeys on a fully typed PathNode, so a
      // rectangle authored by a later build stays re-editable rather than being
      // flattened into anonymous anchors by this one.
      final recipe = <String, Object?>{
        'type': 'rect',
        'w': 40.0,
        'h': 40.0,
        'cornerRadius': 0.0,
      };
      final node = Node.fromJson(<String, Object?>{
        'type': 'path',
        'id': 'n-rect',
        'name': 'Square',
        'path': <String, Object?>{'closed': true, 'anchors': <Object?>[]},
        'recipe': recipe,
      });

      expect(node, isA<PathNode>());
      expect(node.toJson()['recipe'], recipe);
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

    test('bumpRev advances by exactly one and touches nothing else', () {
      final doc = Document.create(name: 'save me');
      final saved = doc.bumpRev();

      expect(saved.rev, doc.rev + 1);
      expect(saved.id, doc.id);
      expect(saved.root, same(doc.root));
    });
  });
}
