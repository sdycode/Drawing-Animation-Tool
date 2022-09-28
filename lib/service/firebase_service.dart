import 'package:cloud_firestore/cloud_firestore.dart';

class DataService {
  final FirebaseFirestore _firebaseFirestore = FirebaseFirestore.instance;

  late CollectionReference<Map<String, dynamic>> usersInstance =
      _firebaseFirestore.collection('users');


  static final DataService _instance = DataService._internal();

  factory DataService() {
    return _instance;
  }

  DataService._internal() {}
  FirebaseFirestore get fbStore => _firebaseFirestore;
}
