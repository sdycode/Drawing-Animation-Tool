import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<List<int>> getNewPorjectNo() async {
  log("username in getNewPorjectNo ${Shared.getUserName()} ");
  DocumentSnapshot<Map<String, dynamic>> doc =
      await DataService().usersInstance.doc("${Shared.getUserName()}").get();
  List<int> prNos = [0];
  try {
    prNos = (doc.data()!["projects"] as List<dynamic>).toList().map((e) {
      return int.parse(e.toString());
    }).toList();
  } catch (e) {}

// log("docpre   ${prNos}//${doc.data()!["projects"].runtimeType}");
  // doc.data()!["projects"];
  prNos.sort();
  return prNos;
}
