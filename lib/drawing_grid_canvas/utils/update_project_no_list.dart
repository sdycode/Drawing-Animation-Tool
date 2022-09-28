// ignore_for_file: non_constant_identifier_names

import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/shared/shared.dart';

import '../../service/firebase_service.dart';

Future update_projctno_list(List<int> projectNos) async {
  try {
    DataService().usersInstance.doc("${Shared.getUserName()}").set(UserProfile(
            userName: Shared.getUserName(),
            password: "password",
            projects: projectNos)
        .toMap());
        log("prnadded success");
  } catch (e) {
    log("prnadd error $e");
  }
}
