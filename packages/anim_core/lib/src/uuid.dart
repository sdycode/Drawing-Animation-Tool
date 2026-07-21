/// UUID v4 minting, dependency-free.
///
/// `anim_core` takes no packages (docs/v3/04 §1), and a 20-line generator is a
/// better trade than a dependency in the one package that gets published.
library;

import 'dart:math' as math;

final math.Random _rng = math.Random.secure();

const _hex = '0123456789abcdef';

/// RFC 4122 version 4, variant 1 — `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`.
///
/// Used for `Document.id` and every `NodeId`. Never derived from a name, a
/// counter, or a list position: legacy's `"Project_14"` collided across three
/// of the eight shipped samples, which is what made "open the wrong project"
/// reachable at all.
String uuidV4() {
  final b = StringBuffer();
  for (var i = 0; i < 36; i++) {
    switch (i) {
      case 8:
      case 13:
      case 18:
      case 23:
        b.write('-');
      case 14:
        b.write('4'); // version
      case 19:
        b.write(_hex[8 | _rng.nextInt(4)]); // variant 10xx
      default:
        b.write(_hex[_rng.nextInt(16)]);
    }
  }
  return b.toString();
}
