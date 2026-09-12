/// A minimal, stored-only ZIP writer (docs/v3/03 F11.1's sibling).
///
/// The player ships as a *folder*, and a browser can only be handed one file,
/// so something has to archive it. This is ~100 lines against a new dependency
/// in an app that currently has none for archiving — and the format it emits is
/// the simplest legal one: **stored**, no compression. Dart source compresses
/// well, but the bundle is ~290KB and the alternative is vendoring a DEFLATE
/// implementation to save a download nobody is waiting on.
///
/// Deterministic on purpose: every entry is stamped 1980-01-01, the earliest
/// timestamp the DOS date field can represent. The same bundle therefore
/// produces byte-identical archives, which is what lets a test assert on the
/// bytes instead of on their length.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Archive [files] (path → UTF-8 contents) as an uncompressed `.zip`.
Uint8List buildZip(Map<String, String> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var entries = 0;

  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final data = utf8.encode(entry.value);
    final crc = _crc32(data);
    final offset = out.length;

    // Local file header. Flag bit 11 declares the name is UTF-8, which is what
    // keeps a non-ASCII path from arriving as mojibake on Windows.
    out
      ..add(_u32(0x04034b50))
      ..add(_u16(20)) // version needed
      ..add(_u16(0x0800)) // UTF-8 names
      ..add(_u16(0)) // stored
      ..add(_u16(0)) // time: 00:00:00
      ..add(_u16(0x0021)) // date: 1980-01-01
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(name.length))
      ..add(_u16(0)) // no extra field
      ..add(name)
      ..add(data);

    central
      ..add(_u32(0x02014b50))
      ..add(_u16(20)) // version made by
      ..add(_u16(20)) // version needed
      ..add(_u16(0x0800))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0x0021))
      ..add(_u32(crc))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(name.length))
      ..add(_u16(0)) // extra
      ..add(_u16(0)) // comment
      ..add(_u16(0)) // disk number
      ..add(_u16(0)) // internal attrs
      ..add(_u32(0)) // external attrs
      ..add(_u32(offset))
      ..add(name);
    entries++;
  }

  final centralBytes = central.takeBytes();
  final centralOffset = out.length;
  out
    ..add(centralBytes)
    ..add(_u32(0x06054b50))
    ..add(_u16(0)) // this disk
    ..add(_u16(0)) // disk with central directory
    ..add(_u16(entries))
    ..add(_u16(entries))
    ..add(_u32(centralBytes.length))
    ..add(_u32(centralOffset))
    ..add(_u16(0)); // no archive comment

  return out.takeBytes();
}

Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

/// The reflected CRC-32 ZIP requires, table built once on first use.
final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
    }
    table[i] = c;
  }
  return table;
}

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
