/// Numeric hygiene and forward-compatibility helpers (docs/v3/02 §6, §7).
///
/// Every number entering the domain goes through [d] or [i]. Not a style rule:
/// JSON, and Firestore in particular, hand back `1` for a value written as
/// `1.0`. Under dart2js `int` and `double` are the same thing so `j['x'] as
/// double` works today; under dart2wasm they are distinct and every one of
/// those casts becomes a runtime `TypeError`. v3 targets CanvasKit and may move
/// to Wasm, so the coercion is written once, here.
library;

/// The **only** way a number becomes a `double` in this package.
double d(Object? v) => (v as num).toDouble();

/// Per-field, never blanket — `fps` is the one deliberate `int` in the format.
int i(Object? v) => (v as num).toInt();

/// Reads a key that may be absent, applying [parse] only when it is present.
T opt<T>(Map<String, Object?> j, String key, T Function(Object? v) parse,
        T fallback) =>
    j.containsKey(key) ? parse(j[key]) : fallback;

/// Everything in [j] that [known] does not claim.
///
/// This is the whole of rule 6 (docs/v3/02 §7): a v3 client opening a document
/// written by a newer editor must re-emit the fields it does not understand,
/// because Firestore autosave from a stale tab would otherwise be silent data
/// loss rather than a degraded view.
Map<String, Object?> unknownKeysOf(Map<String, Object?> j, Set<String> known) {
  final rest = <String, Object?>{};
  for (final entry in j.entries) {
    if (!known.contains(entry.key)) rest[entry.key] = entry.value;
  }
  return Map.unmodifiable(rest);
}

/// Splats preserved keys back out.
///
/// Known keys are written *after* this, so a stale unknown copy of a field the
/// decoder later learned to model can never shadow the typed value.
Map<String, Object?> withUnknown(
  Map<String, Object?> unknown,
  Map<String, Object?> known,
) =>
    <String, Object?>{...unknown, ...known};
