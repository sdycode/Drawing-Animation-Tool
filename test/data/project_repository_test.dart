// Verifies the ProjectRepository data-layer wiring against an in-memory
// Firestore. This is the runtime save/load coverage we otherwise couldn't get
// without a live Firebase project: it proves writes land in the isolated
// `appData/v2` namespace (never legacy `users`) and that save -> load
// round-trips through the domain models.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animated_icon_demo/data/project_repository.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProjectRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ProjectRepository(firestore: firestore);
  });

  Project sampleProject(int n) => Project(
        projectId: 'Project_$n',
        projectName: 'demo_$n',
        width: 400.0,
        height: 400.0,
        iconSections: [
          IconSection(
            iconSectionNo: 0,
            iconSectionName: 'Polyline_0',
            position: const Point(x: 0.0, y: 0.0),
            frames: [
              Frame(
                frameNo: 0,
                singleFrameModel: SingleFrameModel(
                    frameNo: 0,
                    controlPointAdjecntPair: ControlPointAdjecntPair()),
              ),
            ],
          ),
        ],
      );

  test('saveProject writes under appData/v2, never legacy `users`', () async {
    await repo.saveProject('alice', 3, sampleProject(3));

    // Legacy top-level collection must remain untouched.
    expect((await firestore.collection('users').get()).docs, isEmpty);

    // Document lands exactly at appData/v2/users/alice/Project_3/Project_3.
    final doc = await firestore
        .collection(DataService.kRootCollection)
        .doc(DataService.kDataVersion)
        .collection('users')
        .doc('alice')
        .collection('Project_3')
        .doc('Project_3')
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['projectName'], 'demo_3');
  });

  test('saveProject -> fetchProject round-trips through the model', () async {
    await repo.saveProject('bob', 1, sampleProject(1));
    final loaded = await repo.fetchProject('bob', 1);
    expect(loaded, isNotNull);
    expect(loaded!.projectId, 'Project_1');
    expect(loaded.iconSections.first.iconSectionName, 'Polyline_0');
  });

  test('fetchProject returns null when the project is absent', () async {
    expect(await repo.fetchProject('nobody', 9), isNull);
  });

  test('saveUserProfile -> fetchProjectNos round-trips and sorts', () async {
    await repo.saveUserProfile(
        UserProfile(userName: 'carol', projects: [2, 0, 1]));
    expect(await repo.fetchProjectNos('carol'), [0, 1, 2]);
  });

  test('fetchProjectNos defaults to [0] for an unknown user', () async {
    expect(await repo.fetchProjectNos('ghost'), [0]);
  });
}
