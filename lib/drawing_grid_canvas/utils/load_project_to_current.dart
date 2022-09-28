import 'dart:developer';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/utils/get_current_project_instance.dart';

Future loadDataToCurrentProject() async {
  Project? project;
  try {
    project = await getCurrentProjectInstance();
  } catch (e) {
    log("failed to get project");
  }
  if (project != null) {
    projectList[currentProjectNo].iconSections = project.iconSections;
    List<List<Frame>> _newFrameList = [];
    project.iconSections.forEach((e) {
      _newFrameList.add(e.frames);
    });
    // framesList = List<List<Frame>>.from(_newFrameList);
  }
}
