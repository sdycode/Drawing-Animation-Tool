import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';

/// Single data-access seam over Cloud Firestore.
///
/// ALL persistence funnels through here so the rest of the app never builds
/// Firestore paths (or, ideally, imports `cloud_firestore`) directly. The v2
/// namespace is pinned by [DataService.kRootCollection] / [DataService.kDataVersion]
/// (the same constants guarded by the namespace regression test), so legacy
/// top-level `users` data is never touched.
///
/// The [FirebaseFirestore] instance is injectable so the repository can be
/// exercised against an in-memory fake in tests.
///
/// Storage layout (unchanged from legacy, just rooted at the v2 namespace):
/// ```
/// appData/v2/users/{userName}/Project_{n}/Project_{n}  -> Project.toMap()
/// appData/v2/users/{userName}                          -> UserProfile.toMap()
/// ```
class ProjectRepository {
  ProjectRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Root of the isolated v2 namespace: `appData/v2/users`.
  CollectionReference<Map<String, dynamic>> get _users => _firestore
      .collection(DataService.kRootCollection)
      .doc(DataService.kDataVersion)
      .collection('users');

  DocumentReference<Map<String, dynamic>> _userDoc(String userName) =>
      _users.doc(userName);

  CollectionReference<Map<String, dynamic>> _projectCollection(
          String userName, int projectNo) =>
      _userDoc(userName).collection('Project_$projectNo');

  // --------------------------------------------------------------- profile --
  /// Writes (overwrites) the user's profile document.
  Future<void> saveUserProfile(UserProfile profile) =>
      _userDoc(profile.userName).set(profile.toMap());

  /// Live stream of the user's profile document.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUserProfile(
          String userName) =>
      _userDoc(userName).snapshots();

  /// The user's stored project-number list. Defaults to `[0]` (sorted) when the
  /// field is missing or malformed — preserves the legacy `getNewPorjectNo`
  /// behavior exactly.
  Future<List<int>> fetchProjectNos(String userName) async {
    final doc = await _userDoc(userName).get();
    List<int> prNos = [0];
    try {
      prNos = (doc.data()!['projects'] as List<dynamic>)
          .map((e) => int.parse(e.toString()))
          .toList();
    } catch (_) {}
    prNos.sort();
    return prNos;
  }

  // -------------------------------------------------------------- projects --
  /// Writes (overwrites) a single project document at `Project_{n}/Project_{n}`.
  Future<void> saveProject(String userName, int projectNo, Project project) =>
      _projectCollection(userName, projectNo)
          .doc('Project_$projectNo')
          .set(project.toMap());

  /// Loads the project document stored inside `Project_{n}`, or `null` if it is
  /// absent or fails to parse.
  Future<Project?> fetchProject(String userName, int projectNo) async {
    final snap = await _projectCollection(userName, projectNo).get();
    try {
      return Project.fromMap(snap.docs.first.data());
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------- admin --
  /// DEPRECATED whole-collection read: pulls EVERY user document under the v2
  /// namespace from the server. Faithfully carried over from the legacy
  /// username flow; it leaks all users to the client and is slated for removal
  /// in the Phase-0 "switch off Source.server" task. Do not add new callers.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchAllUserDocsFromServer() =>
      _users.get(const GetOptions(source: Source.server));
}
