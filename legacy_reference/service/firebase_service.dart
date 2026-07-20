import 'package:cloud_firestore/cloud_firestore.dart';

class DataService {
  final FirebaseFirestore _firebaseFirestore = FirebaseFirestore.instance;

  /// Root collection that namespaces ALL application data.
  static const String kRootCollection = 'appData';

  /// Schema / namespace version. Bump (and add a new doc under
  /// [kRootCollection]) only when introducing a breaking storage layout.
  /// The legacy top-level `users` collection is intentionally NEVER referenced
  /// by v2 code, so existing data is left completely untouched.
  static const String kDataVersion = 'v2';

  /// The single Firestore chokepoint for the whole app. Every read/write
  /// funnels through this field (and chains `.doc(userName)
  /// .collection('Project_$n').doc('Project_$n')` off it), so repointing it
  /// here isolates the entire data tree under `appData/v2/users/...` —
  /// the legacy `users/...` tree is no longer addressed.
  late CollectionReference<Map<String, dynamic>> usersInstance =
      _firebaseFirestore
          .collection(kRootCollection) // appData
          .doc(kDataVersion) // v2
          .collection('users'); // appData/v2/users


  static final DataService _instance = DataService._internal();

  factory DataService() {
    return _instance;
  }

  DataService._internal();
  FirebaseFirestore get fbStore => _firebaseFirestore;
}
