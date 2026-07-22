/// The decode boundary: located failures, decode-time warnings, and the
/// **required** readers (docs/v3/01 §11, docs/v3/02 §1 rules 5–6, docs/v3/08 §2).
///
/// Everything a decoder needs in order to fail *with an address* lives here, and
/// nowhere else. There is no `try` in this file and none anywhere in
/// `anim_core`: a located throw is a decision, not a rescue.
library;

import 'json.dart';
import 'primitives.dart';

/// Where decode-time repairs announce themselves.
///
/// A repair is not an exception — an orphan pose is stale user data, not a bug
/// in this build — but it must not be silent either, because the one thing
/// worse than dropping data is dropping it invisibly. `anim_core` cannot import
/// a logger and must not `print`, so the app wires this to its fault sink at
/// startup and tests read it directly. The default is a no-op, which keeps the
/// published runtime quiet.
typedef DecodeWarning = void Function(String message);

/// Assignable seam for [DecodeWarning]. Set once, at the IO boundary.
DecodeWarning onDecodeWarning = _ignoreWarning;

void _ignoreWarning(String _) {}

/// Thrown when a **required** structure is missing or unusable.
///
/// ---
/// ## The required/optional boundary — written once, here
///
/// Two docs appear to disagree about the decoder and do not. docs/v3/06 M1 asks
/// for a "strict decoder — missing required subtree throws with a path";
/// docs/v3/08 §2 says "decode degrades, never validates-and-throws". They are
/// talking about different halves of the same file, and the split is by
/// **required vs optional**, not by depth or by type:
///
/// **STRICT — throws a [DocumentException] carrying [path].** The four
/// root-level structures a document cannot exist without — `schemaVersion`,
/// `id`, `artboard`, `root` — plus every structure *they* require in turn: a
/// node's `type` and `id`, a path node's `path`, an anchor's `id` and
/// `position`, a paint's `id` and `paint`, an animation's `id`. There is no
/// document to show without them, and a silently empty canvas reads to the user
/// as data loss they have already suffered rather than a file they can still
/// recover. Absent a location, "invalid document" is what makes a corrupt file
/// unfixable (docs/v3/01 §11) — so every one of these reads its value through a
/// `req*` helper below and reports a real JSON path such as
/// `root/children[2]/path/anchors[7]/position`.
///
/// **DEGRADING — never throws, and never loses data.** Everything else:
///
/// | Malformation | Behaviour |
/// |---|---|
/// | unknown node `type` | `UnknownNode`, re-emitted verbatim |
/// | unknown `paint.type` | `UnknownPaint`, re-emitted verbatim |
/// | unknown `easing.kind`, or a `cubic` whose `p` is not four numbers | `UnknownEasing`, evaluated as linear |
/// | unknown `recipe.type`, or a known one with unreadable numbers | `UnknownRecipe`, never read by anything |
/// | unknown property name, unknown track type, wrong track type for the property, or keys violating T1/T2/T3 | preserved raw in `TrackSet.unknownKeys`, never evaluated |
/// | a pose for an `AnchorId` absent from the node's topology | dropped, with an [onDecodeWarning] |
/// | any unrecognised key at any level | preserved in that type's `unknownKeys` and re-emitted |
/// | any absent optional field | its declared default |
///
/// The asymmetry is deliberate and it is the whole feature. A field that
/// feature A adds on Monday must not make the document unloadable in feature B
/// on Tuesday — that is what the degrading half buys. But a file whose `root`
/// is gone is not a degraded document, it is *no* document, and pretending
/// otherwise hands the user a blank artboard that their next autosave makes
/// permanent.
///
/// One consequence worth stating so nobody re-derives it wrongly: a value that
/// is **present but structurally broken** in a place with no preserve-verbatim
/// variant (an `artboard` that is a string, a `tracks` field that is a list)
/// throws too. It has always thrown; what changes at M1 is that it now says
/// where.
class DocumentException implements Exception {
  const DocumentException(this.message, {this.path});

  final String message;

  /// Slash-separated JSON path from the document root, `[i]` for array indices.
  /// Null only for a failure with no meaningful location.
  final String? path;

  @override
  String toString() =>
      'DocumentException(${path == null ? '' : '$path: '}$message)';
}

/// `parent/key`, with the document root spelled as the empty string so a
/// top-level failure reads `id` rather than `/id`.
String jsonChild(String parent, String key) =>
    parent.isEmpty ? key : '$parent/$key';

/// `parent[index]`.
String jsonIndex(String parent, int index) => '$parent[$index]';

Never _fail(String expected, Object? actual, String path) =>
    throw DocumentException(
      actual == null
          ? 'required $expected is missing'
          : 'expected $expected, got ${actual.runtimeType}',
      path: path.isEmpty ? null : path,
    );

/// A required JSON object at [path].
Map<String, Object?> reqObject(Object? v, String path) =>
    v is Map<String, Object?> ? v : _fail('object', v, path);

/// A required JSON array at [path].
List<Object?> reqArray(Object? v, String path) =>
    v is List<Object?> ? v : _fail('array', v, path);

/// A required string at [path]. An empty string is a legal value; only absence
/// and a wrong type fail.
String reqString(Object? v, String path) =>
    v is String ? v : _fail('string', v, path);

/// A required boolean at [path].
///
/// The optional bool fields (`visible`, `locked`, `clipChildren`, a path's
/// `closed`) read through this inside [opt], for the same reason the optional
/// numerics read through [reqDouble]: a bare `v as bool` inside the parse
/// callback throws Dart's raw `_TypeError` — no field name, no location, not a
/// [DocumentException] — the moment the key is *present but the wrong JSON
/// type*. That is exactly the unlocatable "invalid document" this milestone set
/// out to kill (docs/v3/01 §11); a single mistyped flag on the required root
/// node (`"visible": "yes"`) made the whole document unopenable with an error
/// that named nothing. Absent, the field still takes its default via [opt];
/// present-but-broken now fails *with an address*, in step with every sibling
/// scalar (docs/v3/08 §2's present-but-structurally-broken carve-out).
bool reqBool(Object? v, String path) =>
    v is bool ? v : _fail('boolean', v, path);

/// A required number at [path], coerced through [d].
///
/// The `is num` test is what makes the coercion legal rather than hopeful:
/// under dart2wasm `int` and `double` are distinct types and a bare
/// `as double` is a runtime `TypeError` (docs/v3/00 §6), so every numeric read
/// in this package goes through [d] or [i] and every *required* one comes
/// through here first.
double reqDouble(Object? v, String path) =>
    v is num ? d(v) : _fail('number', v, path);

/// A required integer at [path], coerced through [i].
int reqInt(Object? v, String path) =>
    v is num ? i(v) : _fail('number', v, path);

/// A required `{"x":…,"y":…}` at [path], reporting the offending component.
Vec2 reqVec2(Object? v, String path) {
  final m = reqObject(v, path);
  return Vec2(
    reqDouble(m['x'], jsonChild(path, 'x')),
    reqDouble(m['y'], jsonChild(path, 'y')),
  );
}

/// A required `[r,g,b,a]` at [path], reporting the offending component.
Rgba reqRgba(Object? v, String path) {
  final l = reqArray(v, path);
  if (l.length != 4) {
    throw DocumentException('expected 4 colour components, got ${l.length}',
        path: path.isEmpty ? null : path);
  }
  return Rgba(
    reqDouble(l[0], jsonIndex(path, 0)),
    reqDouble(l[1], jsonIndex(path, 1)),
    reqDouble(l[2], jsonIndex(path, 2)),
    reqDouble(l[3], jsonIndex(path, 3)),
  );
}
