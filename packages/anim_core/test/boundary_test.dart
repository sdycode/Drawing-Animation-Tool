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
}
