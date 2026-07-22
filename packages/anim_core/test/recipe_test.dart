/// `ShapeRecipe` — inert re-edit metadata (docs/v3/01 §5, docs/v3/02 §3.7).
///
/// These types carry no behaviour, which is exactly why they need tests: "inert"
/// is a property that decays the moment somebody finds it convenient to read one
/// in the evaluator, and nothing in the type system stops that. The last group
/// here is the guard — the evaluated scene must be byte-identical with and
/// without a recipe present.
library;

import 'dart:convert';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

Map<String, Object?> reencode(Document d) =>
    jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>;

/// Everything the renderer would draw, flattened to a comparable string.
///
/// Deliberately exhaustive rather than spot-checked: the claim under test is
/// "the recipe changes nothing", and a digest that omits a field is a digest
/// that cannot falsify it.
String sceneDigest(Scene s) => jsonEncode(<Object?>[
      for (final n in s.drawOrder)
        <String, Object?>{
          'path': n.path.toString(),
          'world': <double>[
            n.world.a,
            n.world.b,
            n.world.c,
            n.world.d,
            n.world.tx,
            n.world.ty,
          ],
          'opacity': n.worldOpacity,
          'visible': n.worldVisible,
          'geometry': n.geometry?.toJson(),
          'fills': n.fills.map((f) => f.toJson()).toList(),
          'strokes': n.strokes.map((f) => f.toJson()).toList(),
        },
    ]);

PathData squarePath() => PathData(
      closed: true,
      anchors: const <Anchor>[
        Anchor(id: AnchorId('a0'), position: Vec2(0, 0)),
        Anchor(id: AnchorId('a1'), position: Vec2(40, 0)),
        Anchor(id: AnchorId('a2'), position: Vec2(40, 40)),
        Anchor(id: AnchorId('a3'), position: Vec2(0, 40)),
      ],
    );

Document documentWith(ShapeRecipe? recipe) {
  final base = Document.create(name: 'Recipes');
  // The root id is pinned rather than left as `Document.create`'s fresh UUID:
  // the digest below compares two separately built documents, and a random id
  // would make them differ for a reason that has nothing to do with recipes.
  return base.copyWith(
    root: GroupNode(id: const NodeId('n-root'), name: 'Root', children: <Node>[
      PathNode(
        id: const NodeId('n-sq'),
        name: 'Square',
        path: squarePath(),
        recipe: recipe,
        transform: const Transform2(
          position: Vec2(12.5, -3.25),
          scale: Vec2(2, 0.5),
          pivot: Vec2(20, 20),
          rotation: 0.75,
        ),
        fills: const <Fill>[
          Fill(id: PaintId('p-body'), paint: SolidPaint(Rgba(0.9, 0.2, 0.2))),
        ],
      ),
    ]),
  );
}

void main() {
  group('round trip', () {
    final recipes = <String, ShapeRecipe>{
      'rect': const RectRecipe(w: 40, h: 25, cornerRadius: 4),
      'rect at defaults': const RectRecipe(w: 40, h: 40),
      'ellipse': const EllipseRecipe(rx: 30, ry: 20),
      'polygon': const PolygonRecipe(sides: 5, radius: 50),
      'star': const PolygonRecipe(
          sides: 5, radius: 50, star: true, innerRatio: 0.38),
    };

    for (final entry in recipes.entries) {
      test('${entry.key} survives encode -> JSON text -> decode', () {
        final doc = documentWith(entry.value);
        final back = Document.fromJson(reencode(doc));
        final node = back.root.children.single as PathNode;

        expect(node.recipe, entry.value);
        // And through a second trip, which is what autosave is.
        expect(
          (Document.fromJson(reencode(back)).root.children.single as PathNode)
              .recipe,
          entry.value,
        );
      });
    }

    test('the wire shape is exactly docs/v3/02 §3.7', () {
      expect(const RectRecipe(w: 40, h: 40).toJson(), <String, Object?>{
        'type': 'rect',
        'w': 40.0,
        'h': 40.0,
        'cornerRadius': 0.0,
      });
      expect(const EllipseRecipe(rx: 30, ry: 20).toJson(), <String, Object?>{
        'type': 'ellipse',
        'rx': 30.0,
        'ry': 20.0,
      });
      expect(
        const PolygonRecipe(sides: 5, radius: 50, star: true, innerRatio: 0.5)
            .toJson(),
        <String, Object?>{
          'type': 'polygon',
          'sides': 5,
          'radius': 50.0,
          'star': true,
          'innerRatio': 0.5,
        },
      );
    });

    test('no recipe writes no key at all', () {
      // Not an explicit null: the no-recipe case is every path the pen tool has
      // ever drawn, and a null in every node is noise in a format people
      // hand-inspect.
      final node = documentWith(null).root.children.single;
      expect(node.toJson().containsKey('recipe'), isFalse);
      expect((node as PathNode).recipe, isNull);
    });

    test('an explicit null recipe decodes as absent, not as unreadable', () {
      final node = Node.fromJson(<String, Object?>{
        'type': 'path',
        'id': 'n-sq',
        'path': <String, Object?>{'anchors': <Object?>[]},
        'recipe': null,
      });
      expect((node as PathNode).recipe, isNull);
      expect(node.toJson().containsKey('recipe'), isFalse);
    });

    test('an int-valued recipe decodes (dart2wasm hygiene)', () {
      // Firestore hands back `40` for a value written as `40.0`. Every numeric
      // read routes through d()/i(); a bare `as double` here would be a runtime
      // TypeError under dart2wasm (docs/v3/00 §6).
      final r = ShapeRecipe.fromJson(
          <String, Object?>{'type': 'rect', 'w': 40, 'h': 25});
      expect(r, const RectRecipe(w: 40, h: 25));

      final p = ShapeRecipe.fromJson(<String, Object?>{
        'type': 'polygon',
        'sides': 5,
        'radius': 50,
      });
      expect(p, const PolygonRecipe(sides: 5, radius: 50));
    });
  });

  group('forward compatibility', () {
    test('a recipe from a build this one is not survives untouched', () {
      // The whole reason these types land at M1 rather than with the shape
      // tools at M3: nothing in v1's UI writes a recipe, but a rectangle
      // authored by a later build must not be flattened into four anonymous
      // anchors by this one's autosave.
      final authored = <String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-future',
        'name': 'Authored elsewhere',
        'artboard': <String, Object?>{'x': 450.2, 'y': 250.4},
        'root': <String, Object?>{
          'type': 'group',
          'id': 'n-root',
          'children': <Object?>[
            <String, Object?>{
              'type': 'path',
              'id': 'n-sq',
              'name': 'Square',
              'path': <String, Object?>{'closed': true, 'anchors': <Object?>[]},
              'recipe': <String, Object?>{
                'type': 'rect',
                'w': 40.0,
                'h': 40.0,
                'cornerRadius': 6.0,
              },
            },
          ],
        },
      };

      final doc = Document.fromJson(authored);
      final node = doc.root.children.single as PathNode;
      expect(node.recipe, const RectRecipe(w: 40, h: 40, cornerRadius: 6));
      expect(node.toJson()['recipe'], authoredRecipe(authored));
    });

    test('an unknown recipe type is preserved verbatim', () {
      final spiral = <String, Object?>{
        'type': 'spiral',
        'turns': 3.5,
        'growth': 1.2,
      };
      final r = ShapeRecipe.fromJson(spiral);
      expect(r, isA<UnknownRecipe>());
      expect(r.toJson(), spiral);
    });

    test('a KNOWN recipe type with unreadable numbers degrades, never throws',
        () {
      // Coercing it to a plausible rectangle would be worse than dropping it:
      // the user would see a shape whose recipe silently disagrees with its
      // anchors, and the first re-edit would rewrite the geometry from the wrong
      // numbers. It is optional metadata with a preserve-verbatim variant, so it
      // sits on the degrading side of the boundary (see DocumentException).
      final broken = <String, Object?>{'type': 'rect', 'w': 'forty', 'h': 40.0};
      final r = ShapeRecipe.fromJson(broken);
      expect(r, isA<UnknownRecipe>());
      expect(r.toJson(), broken);

      for (final bad in <Object?>[
        <String, Object?>{'type': 'rect', 'h': 40.0},
        <String, Object?>{'type': 'ellipse', 'rx': 30.0},
        <String, Object?>{'type': 'polygon', 'sides': 'five', 'radius': 50.0},
        <String, Object?>{
          'type': 'polygon',
          'sides': 5,
          'radius': 50.0,
          'star': 'yes',
        },
        'not an object',
        <Object?>[],
      ]) {
        expect(ShapeRecipe.fromJson(bad), isA<UnknownRecipe>(), reason: '$bad');
      }
    });

    test('an unknown key inside a known recipe rides through', () {
      final source = <String, Object?>{
        'type': 'rect',
        'w': 40.0,
        'h': 40.0,
        'cornerRadius': 0.0,
        'cornerStyle': 'squircle',
      };
      final r = ShapeRecipe.fromJson(source);
      expect(r, isA<RectRecipe>());
      expect(r.toJson(), source);
    });

    test('a broken recipe never costs the document', () {
      final doc = Document.fromJson(<String, Object?>{
        'schemaVersion': 3,
        'id': 'doc-broken-recipe',
        'artboard': <String, Object?>{'x': 10.0, 'y': 10.0},
        'root': <String, Object?>{
          'type': 'group',
          'id': 'n-root',
          'children': <Object?>[
            <String, Object?>{
              'type': 'path',
              'id': 'n-sq',
              'path': <String, Object?>{'anchors': <Object?>[]},
              'recipe': 'a rectangle, honest',
            },
          ],
        },
      });
      expect(doc.root.children, hasLength(1));
      expect(
          (doc.root.children.single as PathNode).recipe, isA<UnknownRecipe>());
    });
  });

  group('authority: a manual anchor edit nulls the recipe (docs/v3/01 §5)', () {
    // Without this rule, re-editing a rectangle silently discards every manual
    // edit made since it was drawn. It is enforced in PathOps, at the only
    // mutation that can create the divergence, rather than trusted to the shape
    // inspector that will read the recipe two milestones from now.

    test('a rest-pose drag nulls it', () {
      final doc = documentWith(const RectRecipe(w: 40, h: 40));
      expect((doc.root.children.single as PathNode).recipe, isNotNull);

      final after = PathOps.moveAnchor(
        doc,
        const NodeId('n-sq'),
        const AnchorId('a2'),
        const Vec2(55, 40),
      );
      expect((after.root.children.single as PathNode).recipe, isNull);
      // The edit itself still happened.
      expect((after.root.children.single as PathNode).path.anchors[2].position,
          const Vec2(55, 40));
    });

    test('a keyframe-local pose edit nulls it too', () {
      // Arguably safe to keep — a pose edit does not change the topology the
      // recipe regenerates — but "arguably safe" is how a wrong-shape bug ships.
      // Being wrong in this direction costs one re-editable rectangle; being
      // wrong in the other costs a keyframe the user authored.
      final doc = documentWith(const EllipseRecipe(rx: 20, ry: 20));
      final after = PathOps.moveAnchor(
        doc,
        const NodeId('n-sq'),
        const AnchorId('a1'),
        const Vec2(90, 10),
        atT: 0.5,
      );
      expect((after.root.children.single as PathNode).recipe, isNull);
      expect(
          after.defaultAnimation!
              .tracksFor(const NodeId('n-sq'))
              .pathTrack()!
              .keyCount,
          2);
    });

    test('the nulling survives a save/load cycle', () {
      final doc = PathOps.moveAnchor(
        documentWith(const RectRecipe(w: 40, h: 40)),
        const NodeId('n-sq'),
        const AnchorId('a0'),
        const Vec2(-5, -5),
      );
      final back = Document.fromJson(reencode(doc));
      expect((back.root.children.single as PathNode).recipe, isNull);
      expect(back.root.children.single.toJson().containsKey('recipe'), isFalse);
    });

    test('copyWith cannot null it by accident, and can on purpose', () {
      // `recipe: null` is indistinguishable from an omitted argument, so
      // clearing needs its own flag — otherwise "unchanged" and "nulled" are
      // the same call and one of them is silently wrong.
      final node = documentWith(const RectRecipe(w: 40, h: 40))
          .root
          .children
          .single as PathNode;

      expect(node.copyWith(name: 'Renamed').recipe, isNotNull);
      expect(node.copyWith(recipe: null).recipe, isNotNull);
      expect(node.copyWith(clearRecipe: true).recipe, isNull);
      expect(node.copyWith(recipe: const EllipseRecipe(rx: 1, ry: 1)).recipe,
          const EllipseRecipe(rx: 1, ry: 1));
    });
  });

  group('inertness: the evaluator never reads a recipe', () {
    // The claim that makes recipes free. If this ever fails, the recipe has
    // become a second source of truth for geometry that already has one, and
    // "draw a square, change it to a star" stops being a retopologize.

    test('the evaluated scene is byte-identical with and without one', () {
      final rest = <AnimationMix>[];
      final withRect =
          evaluate(documentWith(const RectRecipe(w: 40, h: 40)), rest);
      final withStar = evaluate(
          documentWith(const PolygonRecipe(sides: 5, radius: 50, star: true)),
          rest);
      final withUnknown = evaluate(
          documentWith(const UnknownRecipe(<String, Object?>{
            'type': 'spiral',
            'turns': 3.0,
          })),
          rest);
      final without = evaluate(documentWith(null), rest);

      expect(sceneDigest(withRect), sceneDigest(without));
      expect(sceneDigest(withStar), sceneDigest(without));
      expect(sceneDigest(withUnknown), sceneDigest(without));
      // The digest is only meaningful if it is non-trivial.
      expect(sceneDigest(without), contains('geometry'));
      expect(sceneDigest(without).length, greaterThan(200));
    });

    test('identical under animation too, at every sampled t', () {
      // A recipe cannot be animated (it is absent from PropKey), so it cannot
      // change over time — but the assertion that matters is that the SAMPLED
      // output does not either.
      Document animated(ShapeRecipe? recipe) {
        var d = documentWith(recipe);
        d = PathOps.moveAnchor(
            d, const NodeId('n-sq'), const AnchorId('a1'), const Vec2(90, -20),
            atT: 1.0);
        // moveAnchor nulls the recipe by design, so put it back to isolate the
        // question this test is asking.
        return d.copyWith(
          root: d.root.copyWith(children: <Node>[
            (d.root.children.single as PathNode)
                .copyWith(recipe: recipe, clearRecipe: recipe == null),
          ]),
        );
      }

      final a = animated(const RectRecipe(w: 40, h: 40));
      final b = animated(null);
      final id = a.defaultAnimationId!;

      for (var n = 0; n <= 20; n++) {
        final t = n / 20.0;
        expect(
          sceneDigest(evaluate(a, <AnimationMix>[AnimationMix(id, t)])),
          sceneDigest(evaluate(b, <AnimationMix>[
            AnimationMix(b.defaultAnimationId!, t),
          ])),
          reason: 't = $t',
        );
      }
    });

    test('a recipe is not an animatable channel', () {
      // Parametric-shape animation is a written non-goal (docs/v3/01 §7).
      // Promoting a recipe parameter to a property later is additive; doing it
      // now buys a second, disagreeing source of truth for the same anchors.
      expect(PropKey.values.map((p) => p.name), isNot(contains('recipe')));
      expect(kExpectedTrackType.keys, hasLength(PropKey.values.length));
      expect(PropertyKey.tryParse('recipe'), isNull);
    });
  });
}

/// The `recipe` sub-map of a hand-written fixture, for an exact-shape compare.
Map<String, Object?> authoredRecipe(Map<String, Object?> doc) =>
    (((doc['root']! as Map<String, Object?>)['children']! as List<Object?>)
        .single! as Map<String, Object?>)['recipe']! as Map<String, Object?>;
