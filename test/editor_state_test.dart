import 'dart:convert';

import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:drawing_animation_tool/app/state/editor_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ephemeral state, tested in isolation from any document or widget.
///
/// The whole reason `EditorState` is a separate notifier is that **none of it may
/// ever reach the document** (AC-2.2.7 — the legacy defect where a file saved
/// mid-selection referenced deleted ids and then refused to open). These tests
/// pin the three properties that keeps: nothing here serializes, selection is
/// resolved-not-repaired, and the viewport is a single cursor-anchored `Affine`.
void main() {
  EditorController controller(ProviderContainer c) =>
      c.read(editorControllerProvider.notifier);

  test(
      'viewport, node selection and the keyframe never touch the document JSON',
      () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = controller(c);

    // Author a document, then move every scrap of ephemeral state onto the
    // editor: a selection, a panned+zoomed viewport, an edit-at-keyframe.
    final doc = Document.create(name: 'Sketch');
    editor
      ..selectNode(const ScenePath(NodeId('p1')))
      ..addToSelection(const ScenePath(NodeId('p2')))
      ..panBy(const Vec2(37, -12))
      ..zoomAround(const Vec2(100, 80), 1.5)
      ..restoreKeyframe(
          (const NodeId('p1'), const PropertyKey(PropKey.rotation), 2));

    final state = c.read(editorControllerProvider);
    expect(state.selectedNodes, hasLength(2), reason: 'the editor holds it');
    expect(state.viewportTransform, isNot(Affine.identity));
    expect(state.selectedKeyframe, isNotNull);

    // The document is a wholly separate object; its serialization must contain
    // none of the ephemeral field names. A substring search is deliberately
    // blunt — if any of these ever leaks into a document key, this catches it.
    final json = jsonEncode(doc.toJson());
    expect(json, isNot(contains('viewportTransform')));
    expect(json, isNot(contains('selectedNodes')));
    expect(json, isNot(contains('selectedKeyframe')));
    expect(json, isNot(contains('selectedAnchors')));
    // Round-tripping the document back proves the same from the other side:
    // nothing ephemeral was needed to reconstruct it.
    final reloaded =
        Document.fromJson(jsonDecode(json) as Map<String, Object?>);
    expect(reloaded.name, 'Sketch');
  });

  test('selection survives a delete as a dangling id — resolved, not repaired',
      () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = controller(c);

    // Select a node, then imagine the document deleted it. The controller stores
    // ids without checking they resolve (docs/v3/08 §2): scrubbing the id out
    // "to be safe" is exactly what would make undo unable to restore the
    // selection it took away, and it is what grows `NodeOps` a dependency on
    // editor types. The dangling path stays; read sites filter it.
    const gone = ScenePath(NodeId('deleted'));
    editor.selectNode(gone);
    expect(c.read(editorControllerProvider).selectedNodes, {gone},
        reason: 'the id is legal even though nothing resolves it');

    // A further selection change does not "clean up" the dangling one either.
    const alsoGone = ScenePath(NodeId('deleted-2'));
    editor.addToSelection(alsoGone);
    expect(c.read(editorControllerProvider).selectedNodes, {gone, alsoGone});
  });

  test('zoomAround keeps ONE Affine and holds the cursor point fixed', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = controller(c);

    const focus = Vec2(213.4, 88.6); // the point under the cursor
    editor.zoomAround(focus, 2.5);
    final vt = c.read(editorControllerProvider).viewportTransform;

    // The defining property of zoom-about-cursor: the point under the cursor does
    // not move. One matrix does it — there is no second matrix and no per-axis
    // scale anywhere (AC-3.1.4); the composed `Affine` applied to the focus
    // returns the focus.
    final held = vt.apply(focus);
    expect(held.x, closeTo(focus.x, 1e-9));
    expect(held.y, closeTo(focus.y, 1e-9));

    // A point off the cursor genuinely scales away from it — this is a zoom, not
    // a no-op. Both axes scale by the same factor (a per-axis fit would not).
    const other = Vec2(313.4, 188.6); // focus + (100, 100)
    final moved = vt.apply(other);
    expect(moved.x - focus.x, closeTo(100 * 2.5, 1e-9));
    expect(moved.y - focus.y, closeTo(100 * 2.5, 1e-9));

    // Stacking a second zoom about a new cursor point still holds whatever was
    // under that cursor — the transform accumulates (one `Affine`), it never
    // resets. The invariant is on the fitted point beneath the cursor, not on
    // the screen coordinate: the fitted point under `focus2` before the zoom is
    // `vt⁻¹(focus2)`, and after the zoom it must still land back on `focus2`.
    const focus2 = Vec2(50, 400);
    final underCursor = vt.invert()!.apply(focus2);
    editor.zoomAround(focus2, 0.5);
    final vt2 = c.read(editorControllerProvider).viewportTransform;
    final held2 = vt2.apply(underCursor);
    expect(held2.x, closeTo(focus2.x, 1e-9));
    expect(held2.y, closeTo(focus2.y, 1e-9));
  });

  test('Cmd/Ctrl+1 zooms to 100% ABOUT THE CURSOR, on top of the live camera',
      () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = controller(c);

    // The 00 §5 gate geometry: a 450.2 × 250.4 artboard letterboxed into an
    // 800 × 620 canvas fits at this scale.
    const fitScale = 1.7769880053309641;
    const focus = Vec2(400, 310); // the canvas centre, under the cursor

    // Put the camera somewhere first. `zoom100` used to *replace* the viewport
    // with a fresh matrix, which threw that pan away — the net scale came out
    // right and the focus came out wrong, drifting the point under the cursor
    // by (-56.3, -28.1) px. Zoom-about-cursor means the point under the cursor
    // does not move; there is nothing else it means.
    editor.panBy(const Vec2(100, 50));
    final before = c.read(editorControllerProvider).viewportTransform;
    final underCursor = before.invert()!.apply(focus);

    editor.zoom100(fitScale, focus);
    final after = c.read(editorControllerProvider).viewportTransform;

    // One document unit is one screen pixel: the composed scale is exactly 1.
    expect(after.a * fitScale, closeTo(1.0, 1e-12));
    expect(after.d * fitScale, closeTo(1.0, 1e-12));
    expect(after.a, closeTo(after.d, 1e-12), reason: 'uniform, one Affine');

    // ...and what was under the cursor is still under the cursor.
    final held = after.apply(underCursor);
    expect(held.x, closeTo(focus.x, 1e-9));
    expect(held.y, closeTo(focus.y, 1e-9));

    // Idempotent: pressing it again is a no-op zoom about the same point, not a
    // second cancellation of the fit.
    editor.zoom100(fitScale, focus);
    final again = c.read(editorControllerProvider).viewportTransform;
    expect(again.a, closeTo(after.a, 1e-12));
    expect(again.tx, closeTo(after.tx, 1e-9));
    expect(again.ty, closeTo(after.ty, 1e-9));
  });

  test('Cmd/Ctrl+0 after Cmd/Ctrl+1 returns to the plain fit', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = controller(c);

    editor
      ..panBy(const Vec2(-40, 90))
      ..zoomAround(const Vec2(120, 90), 1.4)
      ..zoom100(1.7769880053309641, const Vec2(400, 310));
    expect(c.read(editorControllerProvider).viewportTransform,
        isNot(Affine.identity));

    // `fitArtboard` is the only method that throws the camera away — identity
    // viewport IS the fit, because the canvas composes it over `artboardFit`.
    editor.fitArtboard();
    expect(c.read(editorControllerProvider).viewportTransform, Affine.identity);
  });

  test('undo restoring no keyframe LEAVES the one you are editing at', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = controller(c);

    const editingAt = (NodeId('p1'), PropertyKey(PropKey.rotation), 2);
    editor.restoreKeyframe(editingAt);

    // No call site passes `keyframe:` to `run()` yet (that is M4), so every
    // `Restore` carries null today — and this method used to read that null as
    // "clear it" and drop the user out of edit-at-keyframe on every undo.
    // docs/v3/04 §6 wants undo to return you to where you were editing; when
    // the snapshot cannot say where, leaving you put is the answer.
    editor.restoreKeyframe(null);
    expect(c.read(editorControllerProvider).selectedKeyframe, editingAt);

    // Clearing is still possible — it just has to say so.
    editor.clearKeyframe();
    expect(c.read(editorControllerProvider).selectedKeyframe, isNull);
  });

  test('ephemeral state does not leak from one open project to the next',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    // Project one: select, pan, scrub, edit at a keyframe.
    final sub = c.listen(editorControllerProvider, (_, __) {});
    controller(c)
      ..bindProject('project-one')
      ..selectNode(const ScenePath(NodeId('only-in-project-one')))
      ..panBy(const Vec2(120, -40))
      ..commitPlayhead(0.42)
      ..restoreKeyframe(
          (const NodeId('p1'), const PropertyKey(PropKey.position), 0));
    expect(c.read(editorControllerProvider).selectedNodes, hasLength(1));

    // Closing the editor drops every watcher — the panels are the only ones.
    // The provider is autoDispose, so the camera, the playhead and the
    // selection go with them instead of being inherited by the next project.
    sub.close();
    await Future<void>.delayed(Duration.zero);

    final fresh = c.read(editorControllerProvider);
    expect(fresh.selectedNodes, isEmpty, reason: 'no phantom selection');
    expect(fresh.viewportTransform, Affine.identity, reason: 'no camera');
    expect(fresh.playhead, 0.0, reason: 'no playhead');
    expect(fresh.selectedKeyframe, isNull);
  });

  test('bindProject resets the ephemeral state when the project changes', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = controller(c);

    editor
      ..bindProject('project-one')
      ..selectNode(const ScenePath(NodeId('only-in-project-one')))
      ..panBy(const Vec2(120, -40))
      ..commitPlayhead(0.42);

    // Re-binding the same project is a no-op — a rebuild must not wipe the
    // user's selection.
    editor.bindProject('project-one');
    expect(c.read(editorControllerProvider).selectedNodes, hasLength(1));
    expect(c.read(editorControllerProvider).playhead, 0.42);

    // A different project starts clean, even if the editor never unmounted.
    editor.bindProject('project-two');
    final fresh = c.read(editorControllerProvider);
    expect(fresh.selectedNodes, isEmpty);
    expect(fresh.viewportTransform, Affine.identity);
    expect(fresh.playhead, 0.0);
  });

  test(
      'fitArtboard resets pan/zoom to identity; panBy translates in screen '
      'space', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final editor = controller(c);

    editor.panBy(const Vec2(40, 25));
    final panned = c.read(editorControllerProvider).viewportTransform;
    // A pure translate maps the origin to the delta.
    final o = panned.apply(Vec2.zero);
    expect(o.x, closeTo(40, 1e-9));
    expect(o.y, closeTo(25, 1e-9));

    // Cmd/Ctrl+0: identity viewport *is* the fit, because the canvas composes it
    // over `artboardFit` (docs/v3/05 §3).
    editor.fitArtboard();
    expect(c.read(editorControllerProvider).viewportTransform, Affine.identity);
  });
}
