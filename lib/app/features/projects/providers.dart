import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/project_store.dart';
import '../../data/providers.dart';

/// The project list for the signed-in user.
///
/// `Async` because it awaits IO — docs/v3/08 §2 requires anything with an
/// `await` to be an `Async*` provider consumed with `.when`, so a throwing load
/// renders an error state instead of rethrowing at every `ref.watch` and
/// killing the tree.
final projectListProvider = FutureProvider<List<ProjectSummary>>((ref) async {
  return ref.watch(projectStoreProvider).list();
});
