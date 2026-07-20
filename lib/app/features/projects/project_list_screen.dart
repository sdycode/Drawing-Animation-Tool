import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../data/providers.dart';
import 'providers.dart';

/// Screen 1 — the project list (docs/v3/05 §1).
///
/// M0 scope: proves the signed-in path reaches Firestore and back. Cards, new /
/// open / rename / delete, import and samples arrive with F11 at M8.
class ProjectListScreen extends ConsumerWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final projects = ref.watch(projectListProvider);

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
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 18),
            onPressed: () => ref.read(authServiceProvider).signOut(),
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
              const Icon(Icons.cloud_off, size: 28, color: Colors.white38),
              const SizedBox(height: 12),
              Text(
                e is StoreException
                    ? e.failure.message
                    : 'Could not load projects.',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
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
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.brush_outlined, size: 32, color: Colors.white24),
          SizedBox(height: 12),
          Text('No projects yet',
              style: TextStyle(fontSize: 14, color: Colors.white70)),
          SizedBox(height: 4),
          Text('Creating projects arrives with the editor (M2).',
              style: TextStyle(fontSize: 11, color: Colors.white38)),
        ],
      ),
    );
  }
}
