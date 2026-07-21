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
Future<String?> _askProjectName(BuildContext context) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const _NewProjectDialog(),
  );
  return (name == null || name.isEmpty) ? null : name;
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
      body: projects.when(
        loading: () => const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        // A store failure must not take the screen down — the user is signed
        // in and can still retry (docs/v3/08 §2, last row).
        error: (e, _) => Center(
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
        data: (list) => list.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final p = list[i];
                  return ListTile(
                    leading: const Icon(Icons.movie_outlined, size: 20),
                    title: Text(p.name),
                    subtitle: Text('rev ${p.rev}',
                        style: const TextStyle(fontSize: 11)),
                    onTap: () => onOpen(p.id),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () =>
                          ref.read(projectActionsProvider).delete(p.id),
                    ),
                  );
                },
              ),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.brush_outlined, size: 32, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text('No projects yet',
              style: TextStyle(fontSize: 14, color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text('Create one — the editor to draw in it arrives at M2.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
