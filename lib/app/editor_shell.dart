import 'package:anim_core/anim_core.dart' hide Animation;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/project_store.dart';
import 'features/canvas/widgets/canvas_view.dart';
import 'features/timeline/widgets/timeline_bar.dart';
import 'state/document_controller.dart';

/// Screen 2 — the editor (docs/v3/05 §2).
///
/// **This file is not a feature, and that is the point.** `canvas` and
/// `timeline` may not import each other (`tool/check_boundaries.dart` rejects
/// it), so the file that composes them has to sit one level up. Deleting the
/// timeline is one import and one folder, and the compiler finds every loose
/// end — the kill switch docs/v3/08 §5 prefers over a feature-flag registry.
///
/// It is also the only place in the editor that touches the whole
/// `AsyncValue<Document>`. Panels read named slices from their own
/// `providers.dart`; the shell reads the async wrapper so it can render
/// loading and error *states* rather than pushing that decision into every
/// panel — and it consumes it with `.when`, never `.requireValue`, because a
/// `.requireValue` on the first frame throws at every `ref.watch` and takes the
/// tree with it (docs/v3/08 §2).
class EditorShell extends ConsumerWidget {
  const EditorShell({required this.projectId, super.key});

  final String projectId;

  /// Fixed height rather than a flex share: the timeline must not grow into the
  /// canvas as keys are added, and — more importantly — every panel gets
  /// explicit constraints from its parent (docs/v3/08 §2, last row). An
  /// unconstrained slot is what makes the fallback `ErrorWidget` throw a
  /// *second* time during layout, and that second throw is the white screen.
  static const double timelineHeight = 84.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentControllerProvider(projectId));
    final doc = async.valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc?.name ?? 'Editor'),
        actions: [
          if (doc != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Center(
                child: Text(
                  'rev ${doc.rev}',
                  key: const Key('editor-rev'),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e is StoreException
                  ? e.failure.message
                  : 'Could not open this project.',
              key: const Key('editor-error'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        data: (document) => Column(
          children: [
            // docs/v3/02 §1 rule 7's user-facing half. `DocumentController._save`
            // is what actually refuses the write — the gate belongs at the one
            // place a write happens, not in a widget — but a refusal the user
            // only discovers by dragging something and reading a snackbar is a
            // trap, so the state is on screen before they touch anything.
            if (document.isReadOnly)
              _ReadOnlyBanner(version: document.schemaVersion),
            Expanded(child: CanvasView(projectId: projectId)),
            SizedBox(
              height: timelineHeight,
              child: TimelineBar(projectId: projectId),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says which build wrote the file, because "read-only" without a reason reads
/// as a bug in this build rather than as a newer document.
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.version});

  final int version;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: scheme.tertiaryContainer,
      child: Text(
        'Read-only — this project was written by a newer editor '
        '(schema $version, this build reads ${Document.currentSchemaVersion}). '
        'Edits will not be saved.',
        key: const Key('editor-readonly'),
        style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer),
      ),
    );
  }
}
