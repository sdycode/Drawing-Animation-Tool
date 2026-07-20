// ignore_for_file: non_constant_identifier_names

import 'dart:developer';

import 'package:animated_icon_demo/data/project_repository.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/shared/shared.dart';

Future update_projctno_list(List<int> projectNos) async {
  try {
    await ProjectRepository().saveUserProfile(
        UserProfile(userName: Shared.getUserName(), projects: projectNos));
    log("prnadded success");
  } catch (e) {
    log("prnadd error $e");
  }
}
