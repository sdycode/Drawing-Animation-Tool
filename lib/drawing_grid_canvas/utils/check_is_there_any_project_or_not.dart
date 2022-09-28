import 'dart:developer';

import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<bool> checkIsthereAnyPorjectExist() async {
  Stream<DocumentSnapshot<Map<String, dynamic>>> doc =
      (await DataService().usersInstance.doc(Shared.getUserName()).snapshots());
  // .get();
  log("old data size ${doc.length} ");
  int count = 0;
  doc.forEach((element) {
    log("old data size $count / ${doc.length} ");
    count++;
  });

  return false;
}
