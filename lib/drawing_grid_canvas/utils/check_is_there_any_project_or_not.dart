import 'dart:developer';

import 'package:animated_icon_demo/data/project_repository.dart';
import 'package:animated_icon_demo/shared/shared.dart';

Future<bool> checkIsthereAnyPorjectExist() async {
  final doc = ProjectRepository().watchUserProfile(Shared.getUserName());
  // .get();
  log("old data size ${doc.length} ");
  int count = 0;
  doc.forEach((element) {
    log("old data size $count / ${doc.length} ");
    count++;
  });

  return false;
}
