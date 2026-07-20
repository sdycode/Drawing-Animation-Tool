// Architecture enforcement, entire budget (docs/v3/08 §3).
//
// Run: dart run tool/check_boundaries.dart
// Exits non-zero on violation. Wired into CI at M0.
//
// Imports are RESOLVED to repo-relative paths before being judged. A regex over
// the raw import string misses `import '../layers/x.dart'` — the most natural
// way to accidentally couple two features — because that string contains no
// "features/" substring at all.
import 'dart:io';

const _pkg = 'package:drawing_animation_tool/';

/// Repo-relative path of the file an import points at, or null if it is a
/// dart:/ third-party package import (those are judged by URI, not by path).
String? _resolveTarget(String fileDir, String uri) {
  if (uri.startsWith(_pkg)) return 'lib/${uri.substring(_pkg.length)}';
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return null;
  // Relative import: normalize against the importing file's directory.
  return File('$fileDir/$uri').uri.normalizePath().path.replaceFirst(
        '${Directory.current.path}/',
        '',
      );
}

/// The feature a lib path belongs to, or null if it is not feature code.
String? _featureOf(String path) =>
    RegExp(r'^lib/app/features/([^/]+)/').firstMatch(path)?.group(1);

void main() {
  final violations = <String>[];
  final importRe =
      RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;

    final path = entity.path.replaceFirst('${Directory.current.path}/', '');
    final dir = File(path).parent.path;
    final feature = _featureOf(path);

    for (final match in importRe.allMatches(entity.readAsStringSync())) {
      final uri = match.group(1)!;
      final target = _resolveTarget(dir, uri);

      void flag(String rule, String why) =>
          violations.add('$path\n    import \'$uri\'\n    -> $rule: $why');

      // 1. Firebase may only be imported by the data layer. The seam is
      //    ProjectStore (String in / String out) — docs/v3/04 §2.
      if ((uri.startsWith('package:cloud_firestore/') ||
              uri.startsWith('package:firebase_')) &&
          !path.startsWith('lib/app/data/')) {
        flag('firestore-outside-data',
            'only lib/app/data may import Firebase; the seam is ProjectStore');
      }

      if (target == null) continue;
      final targetFeature = _featureOf(target);

      // 2. A feature may not reach into a sibling feature. Features talk
      //    through the three controllers and Command objects only.
      if (feature != null &&
          targetFeature != null &&
          targetFeature != feature) {
        flag('feature-to-feature',
            'features talk through controllers and Commands, never directly');
      }

      // 3. common/ is shared leaf widgets. Depending on a feature inverts that.
      if (path.startsWith('lib/app/common/') && targetFeature != null) {
        flag('common-imports-feature',
            'common/ is shared leaf widgets; depending on a feature inverts that');
      }

      // 4. anim_core is the only place shared math lives. An app-level geometry
      //    grab-bag becomes a second evaluator that disagrees with core
      //    (docs/v3/08 §4).
      if (RegExp(r'^lib/app/(utils|helpers|widgets)/').hasMatch(target)) {
        flag('grab-bag',
            'no app-level utils/helpers/widgets bag; shared code moves down into anim_core');
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('boundaries ok');
    return;
  }
  stderr.writeln('Boundary violations (docs/v3/08 §3):\n');
  for (final v in violations) {
    stderr.writeln('  $v\n');
  }
  exit(1);
}
