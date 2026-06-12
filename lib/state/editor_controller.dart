import 'package:flutter/foundation.dart';

import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart'
    as g;
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

/// The single in-memory editor-state seam (strangler entry point for the
/// pervasive top-level globals).
///
/// For now it **proxies** the legacy globals in `drawing_grid_canvas_fields.dart`
/// (read-through / write-through), so introducing it changes no behavior: code
/// still reading the globals directly stays in sync. New code should read/write
/// through this controller and call [notify] after mutating shared state, so the
/// globals can be migrated into it field-by-field later.
///
/// The `*OrNull` accessors replace the crash-prone index chain
/// `projectList[currentProjectNo].iconSections[currentIconSectionNo]
/// .frames[currentFrameNo]` with bounds-checked navigation — use these instead
/// of indexing directly, and instead of wrapping the access in empty
/// `try/catch` blocks.
class EditorController extends ChangeNotifier {
  EditorController._();

  /// Shared singleton. Registered in the [MultiProvider] via
  /// `ChangeNotifierProvider(create: (_) => EditorController.instance)`, so the
  /// Provider instance and direct `EditorController.instance` access are one and
  /// the same object.
  static final EditorController instance = EditorController._();

  // ------------------------------------------------- proxied document cursor
  int get currentProjectNo => g.currentProjectNo;
  set currentProjectNo(int value) {
    g.currentProjectNo = value;
    notifyListeners();
  }

  int get currentIconSectionNo => g.currentIconSectionNo;
  set currentIconSectionNo(int value) {
    g.currentIconSectionNo = value;
    notifyListeners();
  }

  int get currentFrameNo => g.currentFrameNo;
  set currentFrameNo(int value) {
    g.currentFrameNo = value;
    notifyListeners();
  }

  List<Project> get projectList => g.projectList;
  set projectList(List<Project> value) {
    g.projectList = value;
    notifyListeners();
  }

  String get currentProjectName => g.currentProjectName;
  set currentProjectName(String value) {
    g.currentProjectName = value;
    notifyListeners();
  }

  // -------------------------------------------- guarded derived accessors
  /// The selected project, or `null` if [currentProjectNo] is out of range.
  Project? get currentProjectOrNull =>
      (g.currentProjectNo >= 0 && g.currentProjectNo < g.projectList.length)
          ? g.projectList[g.currentProjectNo]
          : null;

  /// The selected icon section, or `null` if the project or section index is
  /// out of range.
  IconSection? get currentIconSectionOrNull {
    final project = currentProjectOrNull;
    if (project == null) return null;
    final n = g.currentIconSectionNo;
    return (n >= 0 && n < project.iconSections.length)
        ? project.iconSections[n]
        : null;
  }

  /// The selected frame, or `null` if any index up the chain is out of range.
  Frame? get currentFrameOrNull {
    final section = currentIconSectionOrNull;
    if (section == null) return null;
    final n = g.currentFrameNo;
    return (n >= 0 && n < section.frames.length) ? section.frames[n] : null;
  }

  /// The selected frame's [SingleFrameModel], or `null`.
  SingleFrameModel? get currentSingleFrameModelOrNull =>
      currentFrameOrNull?.singleFrameModel;

  /// Notify listeners after mutating shared state through the legacy globals.
  /// (Bridge until those mutations move behind this controller.)
  void notify() => notifyListeners();
}
