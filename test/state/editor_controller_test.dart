// Tests the EditorController's guarded accessors — the bounds-checked
// replacement for the crash-prone `projectList[currentProjectNo]
// .iconSections[...].frames[...]` index chain. They are pure functions of the
// legacy globals, which the test sets up directly.
import 'package:flutter_test/flutter_test.dart';

import 'package:animated_icon_demo/state/editor_controller.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas_fields.dart'
    as g;
import 'package:animated_icon_demo/drawing_grid_canvas/models/new_full_user_model.dart';

Project _projectWith(int sections, int framesPerSection) => Project(
      projectId: 'Project_0',
      projectName: 'p',
      width: 400.0,
      height: 400.0,
      iconSections: List.generate(
        sections,
        (s) => IconSection(
          iconSectionNo: s,
          iconSectionName: 'S$s',
          position: const Point(x: 0.0, y: 0.0),
          frames: List.generate(
            framesPerSection,
            (f) => Frame(frameNo: f, singleFrameModel: SingleFrameModel(frameNo: f)),
          ),
        ),
      ),
    );

void main() {
  final editor = EditorController.instance;

  setUp(() {
    g.projectList = [];
    g.currentProjectNo = 0;
    g.currentIconSectionNo = 0;
    g.currentFrameNo = 0;
  });

  test('all accessors return null when projectList is empty', () {
    expect(editor.currentProjectOrNull, isNull);
    expect(editor.currentIconSectionOrNull, isNull);
    expect(editor.currentFrameOrNull, isNull);
    expect(editor.currentSingleFrameModelOrNull, isNull);
  });

  test('accessors resolve project/section/frame when all indices are in range',
      () {
    g.projectList = [_projectWith(2, 3)];
    g.currentProjectNo = 0;
    g.currentIconSectionNo = 1;
    g.currentFrameNo = 2;
    expect(editor.currentProjectOrNull?.projectId, 'Project_0');
    expect(editor.currentIconSectionOrNull?.iconSectionNo, 1);
    expect(editor.currentFrameOrNull?.frameNo, 2);
    expect(editor.currentSingleFrameModelOrNull?.frameNo, 2);
  });

  test('out-of-range frame index returns null instead of throwing', () {
    g.projectList = [_projectWith(1, 1)];
    g.currentIconSectionNo = 0;
    g.currentFrameNo = 5;
    expect(editor.currentIconSectionOrNull, isNotNull);
    expect(editor.currentFrameOrNull, isNull);
    expect(editor.currentSingleFrameModelOrNull, isNull);
  });

  test('out-of-range section index returns null (and short-circuits frame)', () {
    g.projectList = [_projectWith(1, 1)];
    g.currentIconSectionNo = 9;
    expect(editor.currentProjectOrNull, isNotNull);
    expect(editor.currentIconSectionOrNull, isNull);
    expect(editor.currentFrameOrNull, isNull);
  });

  test('negative project index returns null', () {
    g.projectList = [_projectWith(1, 1)];
    g.currentProjectNo = -1;
    expect(editor.currentProjectOrNull, isNull);
  });

  test('setter writes through to the global and notifies once', () {
    var notifications = 0;
    void listener() => notifications++;
    editor.addListener(listener);
    editor.currentProjectNo = 7;
    expect(g.currentProjectNo, 7); // proxied through to the legacy global
    expect(notifications, 1);
    editor.removeListener(listener);
  });
}
