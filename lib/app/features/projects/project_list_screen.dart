import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/theme.dart';
import '../../data/project_store.dart';
import '../../data/providers.dart';
import 'providers.dart';

/// Sign-out is destructive enough to confirm: it ends the session and the next
/// screen is a login form. Two plain choices, no third option (docs/v3/05 §1).
///
/// Deliberately says nothing about unsaved work — at M0 there is no editor and
/// nothing to lose, and the dialog must not claim otherwise.
Future<bool> _confirmSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('sign-out-dialog'),
      title: const Text('Sign out?'),
      content:
          const Text('You will need to sign in again to open your projects.'),
      actions: [
        TextButton(
          key: const Key('sign-out-cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('sign-out-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  // Dismissing by tapping outside returns null, which is a "no".
  return confirmed ?? false;
}

/// Asks for a name, because rename does not exist yet and a list of
/// indistinguishable "Untitled" rows cannot demonstrate that save and reload
/// actually worked.
/// Delete a project — **only** after an explicit confirmation (F11.1).
///
/// **This is the one destructive action in the app with nothing behind it.**
/// Every other delete — a layer, an anchor, a keyframe — is a `Command` on the
/// undo stack, so a mis-click costs one `Cmd/Ctrl+Z`. This one reaches straight
/// past the stack to `ProjectStore.delete`, which unlinks the bytes: there is no
/// command, no snapshot, no trash to restore from, and on Firestore no local
/// copy either. One stray click on an 18 px icon, sitting on the same row as
/// "open this project", destroyed a project permanently and silently. The
/// dialog is the whole safety mechanism, which is why it names the project
/// rather than asking "are you sure?" — the question worth answering is *which
/// one*, and a generic prompt is one people learn to dismiss without reading.
///
/// **Cancel holds the focus**, not Delete, so a stray `Enter` on an autofocused
/// destructive button cannot do the thing the dialog exists to prevent.
/// Dismissing the barrier or pressing `Esc` returns null, which is the same
/// answer as Cancel.
///
/// The `StoreException` catch is not incidental. The call this replaced dropped
/// its future entirely — a delete that failed (offline, permissions, a
/// concurrent delete) surfaced as an unhandled async error while the row simply
/// stayed put, telling the user nothing. `create` two blocks below always
/// handled it; this now does too, through a messenger captured *before* the
/// dialog's async gap rather than a `BuildContext` used across it.
Future<void> _deleteProject(
    BuildContext context, WidgetRef ref, ProjectSummary project) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteProjectDialog(name: project.name),
  );
  if (confirmed != true) return;
  try {
    await ref.read(projectActionsProvider).delete(project.id);
  } on StoreException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.failure.message)));
  }
}

/// The confirmation itself. Pops `true` only from the Delete button; every
/// other exit — Cancel, `Esc`, a tap on the barrier — pops null.
class _DeleteProjectDialog extends StatelessWidget {
  const _DeleteProjectDialog({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const Key('delete-project-dialog'),
      icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
      title: Text(
        // An empty name would render as `Delete ""?`, so fall back to the same
        // word the list itself shows for an unnamed project.
        'Delete "${name.trim().isEmpty ? 'Untitled' : name.trim()}"?',
      ),
      content: const Text(
        'This deletes the project and every frame in it, for good. '
        'It cannot be undone.',
        style: TextStyle(fontSize: 13),
      ),
      actions: [
        TextButton(
          key: const Key('delete-project-cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('delete-project-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

Future<String?> _askProjectName(BuildContext context) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const _NewProjectDialog(),
  );
  return (name == null || name.isEmpty) ? null : name;
}

/// Opens a bundled [sample] (F11.4, AC-11.4.2): load its asset, import it to a
/// fresh v3 `Document`, save THAT as a new project under the signed-in user's
/// namespace, then open the new project.
///
/// `onOpen` routes to the **new** project's id — never the sample — so the
/// editor plays and edits a copy, and the bundled asset (read once by
/// [loadSample], written never) stays the golden fixture it ships as. A save
/// failure — or a bad asset read / decode — surfaces inline exactly like
/// [_NewProjectDialog]'s create path, rather than crashing the list or escaping
/// as an unhandled async error (docs/v3/08 §1).
Future<void> _openSample(
  BuildContext context,
  WidgetRef ref,
  BundledSample sample,
  void Function(String projectId) onOpen,
) async {
  try {
    final doc = await loadSample(sample);
    final id = await ref.read(projectActionsProvider).createFrom(doc);
    onOpen(id);
  } on StoreException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.failure.message)));
  } on Object {
    // The 8 bundled samples are known-good and the importer is total, so this is
    // a defensive net (a missing asset, a decode failure) — not an expected path.
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that sample.')));
  }
}

/// Stateful purely to own the controller's lifetime.
///
/// Disposing it in a `.then()` on `showDialog` looks equivalent and is not: the
/// dialog keeps rebuilding through its exit animation, so the `TextField`
/// reaches for a controller that has already been disposed and throws mid-pop.
class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _controller = TextEditingController(text: 'Untitled');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('new-project-dialog'),
      title: const Text('New project'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('new-project-confirm'),
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Screen 1 — the project list (docs/v3/05 §1).
///
/// M0 scope: proves the signed-in path reaches Firestore and back — a real
/// `Document` is created, encoded, stored, listed, and decoded again. Cards,
/// open, rename, import and samples arrive with F11 at M8.
class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({required this.onOpen, super.key});

  /// Where "open this project" goes.
  ///
  /// A callback rather than a `Navigator.push` to `EditorScreen`, because a
  /// feature importing a sibling feature is exactly what `check_boundaries`
  /// rejects (docs/v3/08 §3). Composition lives in `app_shell.dart`, so
  /// deleting the editor stays one line there plus one folder.
  final void Function(String projectId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final projects = ref.watch(projectListProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Center(
                child: Text(
                  user.email,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ),
          const ThemeToggleButton(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 18),
            onPressed: () async {
              if (!await _confirmSignOut(context)) return;
              // `ref` outlives this widget's element, so the guard is about the
              // await, not about ref itself — but read it only once we know the
              // user confirmed.
              await ref.read(authServiceProvider).signOut();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Samples first, then the user's own projects. The gallery is always on
      // screen — even for the first-time user whose project list is empty — so
      // AC-11.4.1's "listed and play in-app without assistance" holds before
      // anything is created.
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _SamplesSection(onOpen: onOpen)),
          const SliverToBoxAdapter(child: _SectionHeader('Your projects')),
          ...projects.when(
            loading: () => const [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            ],
            // A store failure must not take the screen down — the user is signed
            // in, the samples still work, and the list can be retried
            // (docs/v3/08 §2, last row).
            error: (e, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off, size: 28, color: muted),
                        const SizedBox(height: 12),
                        Text(
                          e is StoreException
                              ? e.failure.message
                              : 'Could not load projects.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => ref.invalidate(projectListProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            data: (list) => list.isEmpty
                ? const [SliverToBoxAdapter(child: _EmptyState())]
                : [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final p = list[i];
                          return ListTile(
                            leading: const Icon(Icons.movie_outlined, size: 20),
                            title: Text(p.name),
                            subtitle: Text('rev ${p.rev}',
                                style: const TextStyle(fontSize: 11)),
                            onTap: () => onOpen(p.id),
                            trailing: IconButton(
                              key: Key('delete-project-${p.id}'),
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _deleteProject(context, ref, p),
                            ),
                          );
                        },
                        childCount: list.length,
                      ),
                    ),
                  ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-project'),
        onPressed: () async {
          final name = await _askProjectName(context);
          if (name == null) return;
          try {
            await ref.read(projectActionsProvider).create(name: name);
          } on StoreException catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.failure.message)));
          }
        },
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New project'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_outlined, size: 32, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Text('No projects yet',
                style: TextStyle(fontSize: 14, color: scheme.onSurface)),
            const SizedBox(height: 4),
            // The samples above are the zero-assistance on-ramp (AC-11.4.1):
            // open one to play and edit it as a project of your own.
            Text('Open a sample above, or create a project of your own.',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// A small all-caps rail label above a list section.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The bundled-sample gallery (F11.4, AC-11.4.1).
///
/// A horizontal strip of every bundled fixture. The strip is a [Row] rather than
/// a lazy horizontal list on purpose: all 8 cards are built even when the last
/// ones are scrolled off the right edge, so the gallery genuinely *lists* all 8
/// (and a test can assert as much) instead of only the ones in view.
class _SamplesSection extends StatelessWidget {
  const _SamplesSection({required this.onOpen});

  final void Function(String projectId) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Samples'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Open one to play it — it saves as a new project you can edit.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
        SizedBox(
          height: 132,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final sample in bundledSamples)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _SampleCard(
                      key: Key('sample-${sample.asset}'),
                      sample: sample,
                      onOpen: onOpen,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One tappable card in the sample gallery. Opening it imports the fixture and
/// hands the new project's id to [onOpen] (see [_openSample]).
class _SampleCard extends ConsumerWidget {
  const _SampleCard({
    required this.sample,
    required this.onOpen,
    super.key,
  });

  final BundledSample sample;
  final void Function(String projectId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 148,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openSample(context, ref, sample, onOpen),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.play_circle_outline, size: 30, color: scheme.primary),
                const Spacer(),
                Text(
                  sample.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
