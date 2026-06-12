import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';
import 'package:animated_icon_demo/data/project_repository.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';
import 'package:animated_icon_demo/shared/shared.dart';

Future<Project?> getCurrentProjectInstance() async {
  final project = await ProjectRepository()
      .fetchProject(Shared.getUserName(), currentProjectNo);
  if (project != null) return project;
  // Preserve the legacy fallback: on absence/parse-failure return an empty
  // placeholder project (this path never returns null).
  return Project(
    projectId: "Project_$currentProjectNo",
    projectName: "${currentProjectName}_$currentProjectNo",
    iconSections: [],
    width: defaultProjectWidth,
    height: defaultProjectHeight,
  );
}
