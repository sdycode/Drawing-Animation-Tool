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

/// Directory names that mean "I could not think where this goes".
///
/// `common/` is deliberately absent: docs/v3/08 §3 sanctions it by name for
/// shared leaf widgets, and rule 3 already stops it depending on a feature.
const _grabBagNames = <String>{
  'utils',
  'util',
  'helpers',
  'helper',
  'widgets',
  'shared',
  'misc',
  'core',
};

/// `features/<name>/widgets/` — the ONE sanctioned use of a banned name.
///
/// docs/v3/08 §3's directory law spells a feature as
/// `canvas/ { widgets/, providers.dart, commands.dart }`, so a feature's own
/// `widgets/` is the law, not a grab-bag: it is scoped to one feature, and rule
/// 2 already stops anything else importing it. `features/canvas/utils/` is NOT
/// exempt — a private grab-bag is still a grab-bag.
final _featureWidgetsRe = RegExp(r'^lib/app/features/[^/]+/widgets(/|$)');

/// The grab-bag directory [path] sits in, or null.
///
/// Matches on any path SEGMENT under `lib/`, not on a fixed prefix. The earlier
/// rule was a literal `^lib/app/(utils|helpers|widgets)/`, which meant
/// `lib/app/util/`, `lib/app/shared/`, `lib/utils/` and `lib/app/canvas/utils/`
/// all sailed through — the antipattern was preventable only under three exact
/// spellings.
String? _grabBagDir(String path) {
  if (!path.startsWith('lib/')) return null;
  if (_featureWidgetsRe.hasMatch(path)) return null;
  for (final segment in path.split('/')) {
    if (_grabBagNames.contains(segment)) return segment;
  }
  return null;
}

/// Grab-bags flagged by EXISTING, not merely by being imported.
///
/// An empty or not-yet-imported `lib/app/utils/` is still the beginning of the
/// shared mutable surface docs/v3/08 §4 names; catching it on creation is the
/// difference between deleting one file and unpicking twenty call sites.
List<String> _grabBagDirectories() {
  final out = <String>[];
  final lib = Directory('lib');
  if (!lib.existsSync()) return out;
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! Directory) continue;
    final path = entity.path.replaceFirst('${Directory.current.path}/', '');
    final name = _grabBagDir(path);
    if (name == null || path.split('/').last != name) continue;
    out.add('$path/\n    -> grab-bag: a "$name" directory is where shared '
        'mutable surface starts; shared code moves DOWN into anim_core, never '
        'sideways (docs/v3/08 §3, §4)');
  }
  return out;
}

/// Feature → sibling-feature edges that run THROUGH a non-feature file.
///
/// Rule 2 compares one importer against one target, so it cannot see
/// `features/canvas → state/x.dart → features/tools/y.dart`. That laundered
/// edge is what docs/v3/08 §5's kill switch actually depends on: if deleting
/// `features/tools/` breaks `state/`, and `state/` is what every panel imports,
/// then "delete the folder and the app still compiles" is false and the
/// compiler-checked alternative to a feature-flag registry does not exist.
///
/// Walks the import graph from each feature file and reports the first path
/// that lands in a different feature, with the intermediary named — a violation
/// nobody can act on is a violation nobody fixes.
List<String> _transitiveFeatureEdges() {
  final edges = <String, List<String>>{};
  final lib = Directory('lib');
  if (!lib.existsSync()) return <String>[];

  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceFirst('${Directory.current.path}/', '');
    final dir = File(path).parent.path;
    final targets = <String>[];
    for (final match in _directiveRe.allMatches(entity.readAsStringSync())) {
      final target = _resolveTarget(dir, match.group(1)!);
      if (target != null && target.startsWith('lib/')) targets.add(target);
    }
    edges[path] = targets;
  }

  final out = <String>[];
  for (final start in edges.keys) {
    final from = _featureOf(start);
    if (from == null) continue;

    // BFS, carrying the path so the report can name the intermediary.
    final seen = <String>{start};
    final queue = <List<String>>[
      for (final t in edges[start] ?? const <String>[]) [start, t],
    ];
    while (queue.isNotEmpty) {
      final trail = queue.removeAt(0);
      final node = trail.last;
      if (!seen.add(node)) continue;

      final at = _featureOf(node);
      if (at == from) continue; // still inside the same feature
      if (at != null) {
        // Direct hops are rule 2's job; only report the laundered ones.
        if (trail.length > 2) {
          out.add('${trail.first}\n    ${trail.join('\n      -> ')}\n'
              '    -> transitive-feature-to-feature: reaches feature "$at" '
              'through a non-feature file. Deleting features/$at/ would break '
              '${trail[trail.length - 2]} and everything importing it — invert '
              'the dependency (docs/v3/08 §3, §5)');
        }
        continue; // do not walk on through another feature
      }
      for (final next in edges[node] ?? const <String>[]) {
        queue.add([...trail, next]);
      }
    }
  }
  return out;
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
      //    (docs/v3/08 §4). Existence is checked separately below — this catches
      //    the import even if the directory itself somehow passes.
      if (_grabBagDir(target) != null) {
        flag('grab-bag',
            'no app-level ${_grabBagDir(target)}/ bag; shared code moves down into anim_core');
      }
    }
  }

  violations
    ..addAll(_grabBagDirectories())
    ..addAll(_transitiveFeatureEdges());

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
