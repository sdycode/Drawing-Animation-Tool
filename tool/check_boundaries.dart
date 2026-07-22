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

/// Every directive, with whatever combinator followed it.
final _directiveRe = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]([^;]*);''',
    multiLine: true);

/// `anim_core` names its animation type `Animation` (docs/v3/01 §10) and so
/// does Flutter, and `package:flutter/material.dart` exports its one. Dart only
/// errors when the ambiguous name is actually *referenced*, so a file importing
/// both compiles green until someone writes `Animation` in it — and then fails
/// to compile as a whole file, which reads to whoever trips it as an unrelated
/// breakage rather than as a name clash.
///
/// The rule: a file that imports the `anim_core` barrel alongside Flutter must
/// `hide Animation`, `show` an explicit list, or bind a prefix. Renaming the
/// core type instead would put the code at odds with the authoritative doc, and
/// asking every future file to remember the hide unaided is how the landmine
/// stays live.
const _coreBarrel = 'package:anim_core/anim_core.dart';

bool _leaksAnimation(String combinators) {
  final c = combinators.trim();
  if (c.startsWith('as ')) return false;
  if (RegExp(r'\bhide\b[^;]*\bAnimation\b').hasMatch(c)) return false;
  if (RegExp(r'\bshow\b').hasMatch(c)) {
    return RegExp(r'\bshow\b[^;]*\bAnimation\b').hasMatch(c);
  }
  return true;
}

void main() {
  final violations = <String>[];
  final importRe = _directiveRe;

  final roots = <String>[
    'lib',
    'test',
    'tool',
    'packages/anim_core/lib',
    'packages/anim_core/test',
    'packages/anim_render/lib',
    'packages/anim_render/test',
  ];

  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final path = entity.path.replaceFirst('${Directory.current.path}/', '');
      final source = entity.readAsStringSync();
      final directives = importRe.allMatches(source).toList();
      final usesFlutter = directives.any((m) =>
          m.group(1)!.startsWith('package:flutter/') ||
          m.group(1)!.startsWith('package:flutter_test/'));

      for (final match in directives) {
        if (match.group(1) != _coreBarrel) continue;
        if (!usesFlutter || !_leaksAnimation(match.group(2) ?? '')) continue;
        violations.add('$path\n    import \'$_coreBarrel\'\n'
            "    -> ambiguous-Animation: this file also imports Flutter; add "
            "`hide Animation` (docs/v3/01 §10 names the core type)");
      }
    }
  }

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
