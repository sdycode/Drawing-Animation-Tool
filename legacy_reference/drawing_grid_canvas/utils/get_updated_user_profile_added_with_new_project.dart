import 'dart:developer';

import 'package:animated_icon_demo/data/project_repository.dart';
import 'package:animated_icon_demo/shared/shared.dart';

Future<List<int>> getNewPorjectNo() async {
  log("username in getNewPorjectNo ${Shared.getUserName()} ");
  return ProjectRepository().fetchProjectNos(Shared.getUserName());
}
