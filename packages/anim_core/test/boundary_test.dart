import 'dart:io';

import 'package:anim_core/anim_core.dart';
import 'package:test/test.dart';

/// The package boundary from docs/v3/04 §1, enforced as a test rather than a
/// convention. `anim_core` is published as the runtime and must stay pure Dart:
/// a single `package:flutter` import here would make it unpublishable and
/// untestable without a Flutter toolchain.
///
/// This runs in `dart test` — no Flutter involved — so a violation fails CI
/// immediately rather than at publish time.
void main() {
  test('schemaVersion is 3', () {
    expect(kSchemaVersion, 3);
  });

  test('no Flutter, dart:ui, or persistence imports anywhere in lib/', () {
    const banned = <String>[
      'package:flutter/',
      'dart:ui',
      'cloud_firestore',
      'firebase_',
      'package:http/',
    ];

    final offenders = <String>[];
    final libDir = Directory('lib');

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final needle in banned) {
        // Only flag real import/export directives — a mention inside a doc
        // comment (like the one above this test) is not a boundary breach.
        final directive = RegExp(
          '^\\s*(import|export)\\s+[\'"][^\'"]*${RegExp.escape(needle)}',
          multiLine: true,
        );
        if (directive.hasMatch(source)) {
          offenders.add('${entity.path} -> $needle');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'anim_core must stay pure Dart (docs/v3/04 §1)');
  });

  // AC-4.3.8, docs/v3/01 §12: "PathData's const constructor is private and
  // PathOps is the only route to a topology change. Enforced structurally,
  // asserted in CI." A source-level check is the right shape for it — the claim
  // is about what code *can* be written, which no runtime assertion can see.
  group('AC-4.3.8 — PathOps is the only route to a topology change', () {
    test('PathData has no public const constructor', () {
      final source = File('lib/src/path.dart').readAsStringSync();

      expect(source.contains('const PathData._('), isTrue,
          reason: 'the private const ctor is the one the factory delegates to');
      expect(source.contains('factory PathData({'), isTrue,
          reason: 'the validating factory is the only public constructor');
      expect(source.contains('const PathData.trusted('), isTrue,
          reason: 'the evaluator-only unchecked ctor (docs/v3/08 §1)');

      // A public `const PathData(...)` would let any caller bypass the P1
      // uniqueness check — legacy's public const ctors enforced nothing, and a
      // duplicate id silently animates one anchor with another's pose.
      final publicConst = RegExp(r'const\s+PathData\s*\(');
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        expect(publicConst.hasMatch(entity.readAsStringSync()), isFalse,
            reason: '${entity.path} constructs PathData const-ly');
      }
    });

    test('PathData is only constructed in the geometry, decode and ops files',
        () {
      // The allowlist IS the enforcement: a new file that builds a PathData is
      // a new route to a topology change, and it has to be argued for here
      // before it can exist.
      const allowed = <String>{
        'lib/src/path.dart', // the factory itself + fromJson
        'lib/src/shape_geometry.dart', // recipe → geometry (AC-4.1.4)
        'lib/src/ops/path_ops.dart', // pose + recipe regeneration
        'lib/src/ops/node_ops.dart', // duplicateSubtree's id remap
      };
      const trusted = <String>{
        'lib/src/path.dart',
        'lib/src/eval/evaluate.dart', // resolvePose, per docs/v3/08 §1
      };

      final builders = <String>{};
      final trustedCallers = <String>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final source = entity.readAsStringSync();
        if (RegExp(r'\bPathData\(').hasMatch(source)) builders.add(path);
        if (source.contains('PathData.trusted(')) trustedCallers.add(path);
      }

      expect(builders, allowed);
      expect(trustedCallers, trusted,
          reason: 'the unchecked ctor is the evaluator\'s alone — everything '
              'else uses the validating factory');
    });

    test('no node-level path replacement outside ops/', () {
      // `PathNode.copyWith(path: …)` IS the topology write. Confining it to
      // `ops/` is what stops a pen tool, a panel or an importer swapping the
      // geometry under a tracked node's keyframes.
      final offenders = <String>[];
      final write = RegExp(r'path:\s*(PathData|_remap|recipe\.toPath)');
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path.startsWith('lib/src/ops/')) continue;
        if (path == 'lib/src/node.dart') continue; // fromJson / copyWith decl
        if (write.hasMatch(entity.readAsStringSync())) offenders.add(path);
      }
      expect(offenders, isEmpty);
    });
  });
}
