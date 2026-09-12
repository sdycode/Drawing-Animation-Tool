/// The stored-ZIP writer, checked against the system `unzip` rather than
/// against a reader of our own.
///
/// A hand-rolled archive format is exactly the kind of code that passes its own
/// round-trip and still produces a file no real tool will open — the round-trip
/// shares the bug. So the assertion here is "the operating system's unzip
/// accepts it and yields the bytes we put in", which is the only claim the
/// download button actually needs to be true.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drawing_animation_tool/app/features/export/zip.dart';
import 'package:flutter_test/flutter_test.dart';

/// Skips rather than fails where `unzip` is absent (some CI images), because a
/// missing tool is not a broken writer.
bool get _hasUnzip =>
    Process.runSync('which', ['unzip']).exitCode == 0;

void main() {
  final files = <String, String>{
    'anim_player.dart': "export 'src/render/anim_player.dart' show AnimPlayer;\n",
    'src/core/src/affine.dart': 'class Affine {}\n',
    'README.md': '# anim_player\n\nUnicode: é ü 日本語 — and a tab:\there.\n',
    'empty.txt': '',
  };

  test('the archive is deterministic', () {
    expect(buildZip(files), buildZip(files),
        reason: 'a fixed timestamp is what makes byte assertions possible');
  });

  test('it carries the local-header and end-of-central-directory signatures',
      () {
    final bytes = buildZip(files);
    expect(bytes.sublist(0, 4), <int>[0x50, 0x4b, 0x03, 0x04]);
    expect(bytes.sublist(bytes.length - 22, bytes.length - 18),
        <int>[0x50, 0x4b, 0x05, 0x06]);
  });

  test('system unzip accepts it and round-trips every byte', () {
    if (!_hasUnzip) {
      markTestSkipped('unzip not on PATH');
      return;
    }
    final dir = Directory.systemTemp.createTempSync('zip_test');
    try {
      final archive = File('${dir.path}/bundle.zip')
        ..writeAsBytesSync(buildZip(files));

      final integrity = Process.runSync('unzip', ['-t', archive.path]);
      expect(integrity.exitCode, 0,
          reason: 'unzip -t said:\n${integrity.stdout}${integrity.stderr}');

      final out = Directory('${dir.path}/out')..createSync();
      final extract =
          Process.runSync('unzip', ['-q', '-o', archive.path, '-d', out.path]);
      expect(extract.exitCode, 0, reason: '${extract.stderr}');

      files.forEach((path, contents) {
        final extracted = File('${out.path}/$path');
        expect(extracted.existsSync(), isTrue, reason: '$path was not extracted');
        expect(utf8.decode(extracted.readAsBytesSync()), contents,
            reason: '$path did not survive the round trip');
      });
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('an empty archive is still a legal archive', () {
    final bytes = buildZip(const {});
    expect(bytes.length, 22, reason: 'end-of-central-directory record only');
    expect(bytes.sublist(0, 4), <int>[0x50, 0x4b, 0x05, 0x06]);
  });
}
