/// Which nodes a click may not reach — the hit-test gate shared by the tools
/// that hit-test (AC-2.2.6).
///
/// **Locked is a hit-test gate, not a render gate** (docs/v3/01 §3), so it is
/// not on `ResolvedNode` and the evaluator never reads it: a locked layer plays
/// back exactly like an unlocked one. It is resolved here, from the document's
/// own tree, at gesture time.
///
/// One copy, because two tools ask the question. Select refuses to select or
/// move a locked node; Direct select refuses to grab its anchors — and a lock
/// that protected the shape but not its handles would be no lock at all.
library;

import 'package:anim_core/anim_core.dart' hide Animation;

/// Every node that is locked, directly or through a locked ancestor.
///
/// Lock inherits **down** the tree: locking a group protects its children, which
/// is the whole reason a user locks a group.
Set<NodeId> lockedNodeIds(Document doc) {
  final out = <NodeId>{};
  void walk(Node node, bool inheritedLock) {
    final locked = inheritedLock || node.locked;
    if (locked) out.add(node.id);
    if (node is GroupNode) {
      for (final child in node.children) {
        walk(child, locked);
      }
    }
  }

  for (final child in doc.root.children) {
    walk(child, false);
  }
  return out;
}
