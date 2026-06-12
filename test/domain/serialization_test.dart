// Characterization tests that LOCK the domain serialization contract before
// the Phase-1 state/data-layer refactor. They assert the *current* behavior
// (including a couple of known fragilities, clearly labelled) so any
// behavioral change during the refactor is caught.
//
// Models have no value `==`, so round-trips are verified via deep map equality:
//   fromMap(toMap()).toMap() == toMap()
import 'package:flutter_test/flutter_test.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/pair_model.dart';

void main() {
  group('Point', () {
    test('toMap shape + round-trip (doubles)', () {
      const p = Point(x: 1.5, y: -2.5);
      expect(p.toMap(), {'x': 1.5, 'y': -2.5});
      expect(Point.fromMap(p.toMap()).toMap(), equals(p.toMap()));
    });

    test('KNOWN FRAGILITY: integer-valued JSON throws (int/double drift)', () {
      // toMap always writes doubles, but external/legacy JSON with int coords
      // crashes fromMap. Flagged for the Phase-1 serialization hardening.
      expect(() => Point.fromMap({'x': 5, 'y': 10}), throwsA(isA<TypeError>()));
    });

    test('missing coords default to 0.0 (the ?? 0 literal is double in context)',
        () {
      // Subtle: `json["x"] ?? 0` defaults fine (the 0 literal is double here),
      // but a *stored* integer value still throws — see the test above.
      final p = Point.fromMap({});
      expect(p.x, 0.0);
      expect(p.y, 0.0);
    });
  });

  group('BoxSize', () {
    test('defaults + round-trip', () {
      const b = BoxSize();
      expect(b.toMap(), {'width': 200, 'height': 100});
      expect(BoxSize.fromMap(b.toMap()).toMap(), equals(b.toMap()));
    });
  });

  group('Pair / ControlPointAdjecntPair', () {
    test('Pair round-trips', () {
      final p = Pair(2, 7);
      expect(p.toMap(), {'preIndex': 2, 'nextIndex': 7});
      expect(Pair.fromMap(p.toMap()).toMap(), equals(p.toMap()));
    });

    test('ControlPointAdjecntPair defaults to 0/1 and round-trips', () {
      final c = ControlPointAdjecntPair();
      expect(c.toMap(), {'preIndex': 0, 'nextIndex': 1});
      expect(
          ControlPointAdjecntPair.fromMap(c.toMap()).toMap(), equals(c.toMap()));
    });
  });

  group('SingleFrameModel', () {
    SingleFrameModel populated() => SingleFrameModel(
          frameNo: 3,
          framePosition: 0.5,
          boxSize: const BoxSize(width: 120, height: 80),
          hoverPoint: const Point(x: 1.0, y: 2.0),
          controlPointAdjecntPair: ControlPointAdjecntPair(
              preIndex: 1, nextIndex: 2),
          controlMidPoints: const {'a': Point(x: 3.0, y: 4.0)},
          points: const [Point(x: 5.0, y: 6.0), Point(x: 7.0, y: 8.0)],
          cornerBoxPoints: const [
            Point(x: 0.0, y: 0.0),
            Point(x: 10.0, y: 0.0),
            Point(x: 10.0, y: 10.0),
            Point(x: 0.0, y: 10.0),
          ],
        );

    test('fully-populated frame round-trips', () {
      final m = populated();
      expect(SingleFrameModel.fromMap(m.toMap()).toMap(), equals(m.toMap()));
    });

    test('KNOWN QUIRK: null controlPointAdjecntPair rehydrates to default 0/1',
        () {
      // Default constructor leaves controlPointAdjecntPair null -> serialized
      // as null -> fromMap substitutes ControlPointAdjecntPair() (0/1).
      final m = SingleFrameModel(frameNo: 0);
      expect(m.controlPointAdjecntPair, isNull);
      expect(m.toMap()['controlPointAdjecntPair'], isNull);
      final reloaded = SingleFrameModel.fromMap(m.toMap());
      expect(reloaded.toMap()['controlPointAdjecntPair'],
          equals({'preIndex': 0, 'nextIndex': 1}));
    });
  });

  group('Frame', () {
    test('serializes under the capital-S "SingleFrameModel" key', () {
      final f = Frame(frameNo: 1, singleFrameModel: SingleFrameModel(frameNo: 1));
      final map = f.toMap();
      expect(map.containsKey('SingleFrameModel'), isTrue);
      expect(map.containsKey('singleFrameModel'), isFalse);
    });

    test('KNOWN TRAP: lowercase "singleFrameModel" key is silently dropped', () {
      // The casing mismatch means data stored under the wrong key is lost and
      // replaced by an empty default frame. Flagged for Phase-1 hardening.
      final loaded = Frame.fromMap({
        'frameNo': 1,
        'singleFrameModel': {
          'frameNo': 1,
          'points': [
            {'x': 9.0, 'y': 9.0}
          ],
        },
      });
      expect(loaded.singleFrameModel.points, isEmpty);
    });
  });

  group('IconSection', () {
    test('defaults (color / drawingObjectType) + round-trip', () {
      final s = IconSection(
        iconSectionNo: 0,
        iconSectionName: 'Polyline_0',
        frames: [
          Frame(
              frameNo: 0,
              singleFrameModel: SingleFrameModel(
                  frameNo: 0,
                  controlPointAdjecntPair: ControlPointAdjecntPair())),
        ],
        position: const Point(x: 0.0, y: 0.0),
      );
      expect(s.color, 'FFFFC0CB');
      expect(s.drawingObjectType, 'polyline');
      expect(IconSection.fromMap(s.toMap()).toMap(), equals(s.toMap()));
    });
  });

  group('Project', () {
    Project sample() => Project(
          projectId: 'Project_0',
          projectName: 'demo_0',
          width: 400.0,
          height: 400.0,
          iconSections: [
            IconSection(
              iconSectionNo: 0,
              iconSectionName: 'Polyline_0',
              frames: [
                Frame(
                    frameNo: 0,
                    singleFrameModel: SingleFrameModel(
                        frameNo: 0,
                        controlPointAdjecntPair: ControlPointAdjecntPair()))
              ],
              position: const Point(x: 0.0, y: 0.0),
            )
          ],
        );

    test('round-trips', () {
      final p = sample();
      expect(Project.fromMap(p.toMap()).toMap(), equals(p.toMap()));
    });

    test('missing width/height fall back to defaults (400)', () {
      final map = sample().toMap()
        ..remove('width')
        ..remove('height');
      final p = Project.fromMap(map);
      expect(p.width, 400.0); // defaultProjectWidth
      expect(p.height, 400.0); // defaultProjectHeight
    });
  });

  group('UserProfile', () {
    test('no longer carries a password field', () {
      final u = UserProfile(userName: 'shubham', projects: [0, 1]);
      expect(u.toMap().containsKey('password'), isFalse);
      expect(u.toMap(), {
        'userName': 'shubham',
        'projects': [0, 1],
      });
    });

    test('round-trips and tolerates missing projects (-> [])', () {
      final u = UserProfile(userName: 'x', projects: const []);
      expect(UserProfile.fromMap({'userName': 'x'}).toMap(), equals(u.toMap()));
    });
  });
}
