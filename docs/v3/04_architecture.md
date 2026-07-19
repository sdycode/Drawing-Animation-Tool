# 04 — Architecture

**What this doc is:** the structural contract — package boundaries and dependency direction, the persistence seam, state management, the render pipeline, undo/redo, and testing seams. How the types in [01](01_domain_model.md) become a running Flutter Web app.
**What it is not:** the domain model (01 is authoritative — if this doc disagrees with 01, 01 wins), the wire format ([02](02_file_format.md)), or the build plan. No product scope is decided here; §3/§4 of [00](00_vision_and_scope.md) already fixed it.

---

## 1. Package boundaries

**One rule: arrows point inward. The domain core imports nothing.**

```
app (repo root)  ──▶  packages/anim_render  ──▶  packages/anim_core  ──▶  (dart:core, dart:math)
      │                                                  ▲
      └──────────────────────────────────────────────────┘
```

```
Drawing-Animation-Tool/
  pubspec.yaml                       # the editor app — Flutter Web
  lib/
    app/                             # shell, panels, canvas widgets, tools
    state/                           # controllers (§4)
    data/                            # ProjectStore + implementations (§2)
  packages/
    anim_core/                       # PURE DART. Published to pub.dev.
      lib/src/model/                 # 01 §2–§10 types
      lib/src/serial/                # toJson / fromJson (02) — generated
      lib/src/eval/                  # the 8 named stages (01 §11)
      lib/src/ops/                   # PathOps / TrackOps / NodeOps (01 §12)
      lib/src/import/                # one-way legacy importer
    anim_render/                     # FLUTTER. Scene → Canvas. Published alongside.
  server/                            # v1.1 Go service (§3). Empty in v1.
  legacy_reference/                  # read-only; deleted at parity
```

| Package | May import | May NOT import |
|---|---|---|
| `anim_core` | `dart:core`, `dart:math`, `dart:convert` | **`package:flutter` — anything. `dart:ui`. `cloud_firestore`. `dart:io`.** |
| `anim_render` | `anim_core`, `package:flutter` | `cloud_firestore`, `lib/` of the app |
| app `lib/` | both packages, Firebase, Riverpod | — |

**The boundary is enforced by pubspec, not by review.** `anim_core/pubspec.yaml` has no `flutter` dependency, so an accidental `import 'package:flutter/material.dart'` in core fails to resolve at analysis time. A lint rule can be forgotten; a missing dependency cannot.

### The `annimation` question is settled: clean break

The published pub.dev package **`annimation` v0.0.2 is built on the legacy structure. It is not a dependency, not a compatibility target, and not a migration path.** It reads the legacy format and *cannot* read a v3 document — which is why v3 ships a **new** package rather than a version bump.

**Nothing constrains this design backward.** No shim layer, no legacy adapter, no v0.0.2 field names anywhere in `anim_core`. The only legacy code in the repo is `legacy_reference/` (read-only, deleted at parity) and the one-way importer in `anim_core/lib/src/import/`, which reads legacy *JSON files* — not the legacy package.

`anim_core` is the contract named by 00 §5 criterion 8: model + serializer + evaluator, zero Flutter imports. **`anim_render` is published alongside it** as the thin Flutter binding (a `CustomPainter` over `Scene`), because criterion 8's "plain Flutter app" needs pixels, not just a `Scene`. Core stays the contract; render stays optional.

---

## 2. Persistence seam

`ProjectStore` exists **from commit one**, before Firestore is wired at all.

```dart
abstract class ProjectStore {
  Future<List<ProjectSummary>> list();
  Future<String?> load(String id);           // raw jsonEncode output
  Future<void> save(String id, String json);
  Future<void> delete(String id);
}
```

**`String` in, `String` out — never `Map`.** A `Map<String, dynamic>` signature is how `cloud_firestore`'s `Timestamp`, `DocumentReference` and integer-normalized doubles leak into the domain layer. A `String` cannot carry a vendor type.

| File | Phase | Role |
|---|---|---|
| `lib/data/project_store.dart` | v1 | the interface + `ProjectSummary` |
| `lib/data/firestore_project_store.dart` | v1 | `appData/v3/...` (02 §9), `enablePersistence()`, debounced autosave |
| `lib/data/http_project_store.dart` | v1.1 | **added beside**, never replacing |
| `lib/data/fake_project_store.dart` | v1 | in-memory; the store seam for tests (§7) |

### Selection is build-time, in one branch

```bash
flutter run   --dart-define=BACKEND=firestore   # v1
flutter build web --dart-define=BACKEND=api     # v1.1
```

```dart
const _backend = String.fromEnvironment('BACKEND', defaultValue: 'firestore');

ProjectStore createProjectStore() => switch (_backend) {
  'api' => HttpProjectStore(baseUrl: const String.fromEnvironment('API_URL')),
  _     => FirestoreProjectStore(),
};
```

`String.fromEnvironment` is **const**, so the switch folds at compile time and the unused implementation is tree-shaken out of the web bundle. A runtime feature flag would ship both Firebase and the HTTP client to every user.

### Injection

One override at the root; everything downstream reads the interface and has never heard of Firestore.

```dart
final projectStoreProvider = Provider<ProjectStore>((_) => throw UnimplementedError());

runApp(ProviderScope(
  overrides: [projectStoreProvider.overrideWithValue(createProjectStore())],
  child: const EditorApp(),
));
```

Tests override the same provider with `FakeProjectStore` — no Firebase emulator, no network, no `setUpAll`.

### No forked branch

Same repo, same branch. `http_project_store.dart` is a **new file added next to** the Firestore one; `server/` is a new directory. Nothing is deleted, nothing is swapped. A long-lived rewrite branch rots against `main` and never merges — that is repo policy (00 §6), and it is exactly why the seam is `String`-shaped: the swap is additive by construction.

---

## 3. Where the Go service sits

**`server/` — same repo, empty until v1.1.** Strictly after 00 §5 passes on a public URL.

**Flutter Web has no `dart:io`.** A browser cannot open a TCP socket, so it cannot speak the Postgres wire protocol. An HTTP service in front of the database is a **forced consequence of the platform, not optional scope** — this is the reason v1.1 is a service and not a driver swap.

| Responsibility | Owner |
|---|---|
| Auth (issue/verify JWT), ownership checks | `server/` |
| CRUD over `projects`, soft delete | `server/` |
| `rev` optimistic concurrency — reject a save whose `rev` ≠ stored `rev` | `server/` |
| `list()` projections from typed columns (02 §9b) | `server/` |
| Parsing document geometry, evaluating, rendering, validating tracks | **Never `server/`.** |

The server treats `body jsonb` as opaque except for extracting the projection columns on write. **The evaluator exists in exactly one place — `anim_core`.** A second implementation in Go is two evaluators that disagree, which is the class of bug this rewrite exists to eliminate.

---

## 4. State management

### The legacy failure, stated precisely

~50 top-level globals, plus `ChangeNotifier` subclasses with **no state at all** used purely as a repaint bus, poked from **93 `updateUI()` call sites**. Consequences: every notify repainted everything; no widget declared what it depended on; the playhead round-tripped through pixels and `BuildContext`; and `build()` mutated the document. The problem was never "the wrong package" — it was **untyped, unscoped, undirected state**.

### Choice: **Riverpod**, three separate state objects, one derived graph

| State | Type | Lives in | Undoable | Persisted |
|---|---|---|---|---|
| **Document** | `Document` (immutable, 01 §11) | `DocumentController extends Notifier<Document>` | **Yes** | Yes |
| **Ephemeral editor** | `EditorState` (01 §12) — selection, hover, `selectedKeyframe`, `viewportTransform`, `activeAnimation` | `EditorController extends Notifier<EditorState>` | No | **Never** |
| **Tool mode** | `sealed class ToolMode` — `SelectTool`, `PenTool`, `ShapeTool(ShapeRecipe)`, plus in-progress gesture state | `ToolController extends Notifier<ToolMode>` | No | Never |

Three separate notifiers, not one god-object: **dragging a selection marquee must not invalidate anything that reads the document.** That separation is the entire fix for the repaint bus.

**Why Riverpod, not `provider` (legacy) or hand-rolled notifiers:**

| Property | Why it matters here |
|---|---|
| Reads need no `BuildContext` | The playhead is a unitless double in the domain layer. Legacy's `BuildContext` round-trip is structurally impossible. |
| `select()` — subscribe to a *slice* | The layers panel watches node names/order only; moving an anchor does not rebuild it. The direct antidote to 93 blind `updateUI()` calls. |
| Derived providers are memoized and auto-invalidated | `sceneProvider` recomputes when — and only when — the document or playhead changes. No manual cache invalidation. |
| Controllers are testable with zero widgets | Undo, autosave debounce and every mutation are `dart test`-able (§7). |
| `overrideWithValue` at `ProviderScope` | The single injection point in §2. |

**Derived state is a provider, never a field.** The `Map<NodeId, Node>` index, AABBs and the sampled `Scene` are all derived (01 §11) and all live in providers. Nothing derived is ever stored on `Document`.

### The playhead is the one hot path, and it bypasses the widget tree

At 60 fps, rebuilding widgets on every playhead tick is a rebuild storm by definition. So:

```dart
/// Identity is stable for the app's lifetime; only its VALUE changes.
final playheadProvider = Provider<ValueNotifier<double>>((_) => ValueNotifier(0.0));
```

- The transport `Ticker` and the scrub drag write `playhead.value`. **No provider is invalidated, no widget rebuilds.**
- The canvas painter takes that notifier as `CustomPainter(repaint: playhead)` — the tick reaches `paint()` without touching `build()`.
- On **scrub end** (or when a keyframe dot is clicked for edit-at-keyframe), the value is committed into `EditorState.playhead` once, so selection logic reads a settled, typed value.

`EditorState.playhead` remains the authoritative field per 01 §12; the `ValueNotifier` is the transport channel between commits.

---

## 5. Render pipeline

```
Document ──┐
           ├─▶ evaluate(doc, [AnimationMix(anim, t, weight: 1.0)]) ─▶ Scene ─▶ ArtboardPainter ─▶ Canvas
playhead ──┘        (anim_core, pure)                                        (anim_render)
```

### Layers — three stacked painters, each in its own `RepaintBoundary`

| # | Layer | Repaints when | Reads |
|---|---|---|---|
| 1 | Artboard background + rulers | artboard size / zoom changes | `Document.artboard`, `viewportTransform` |
| 2 | **Scene geometry** | document mutates **or** playhead moves | `Scene` |
| 3 | Editor overlay — anchors, handles, gizmo, marquee, hover | selection / hover / drag changes | `EditorState`, `ToolMode`, `Scene` |

**Hover and marquee live in layer 3 only, so moving the mouse never repaints geometry.** In legacy, it repainted the entire app.

### What actually re-runs

| Trigger | Evaluator stages | Widgets rebuilt | Layers repainted |
|---|---|---|---|
| **Scrub / play** | 1 `sampleTracks` → 2 `resolvePose` → 3 `composeWorldA` → 7 `applyTrim` → 8 `resolvePaint` (4/5/6 are v1 no-ops) | **none** | 2, 3 |
| **Anchor drag (live)** | same, at the current playhead | none (drag state is in `ToolMode`, painted by layer 3) | 3 |
| **Commit a mutation** (`PathOps` / `TrackOps` / `NodeOps`) | full pass on the new `Document` | layers panel, timeline, inspector — via `select()`, only their slice | 2, 3 |
| **Selection / hover** | none — `Scene` is untouched | none | 3 |

### Painter rules

```dart
@override
bool shouldRepaint(ArtboardPainter old) => !identical(old.scene, scene);
```

Identity, never deep equality — `Scene` is immutable, so a new object *is* the change signal. Deep-comparing 114 anchors every frame to avoid a paint that costs less than the comparison is backwards.

- **One `Affine`, one transform.** `viewportTransform` is applied once via `canvas.transform(affine.toFloat64List())`. Hit-testing inverts *that same matrix*. Legacy's hand-rolled per-axis scaling is the y-scaled-by-width bug, and it is golden-tested here on the 450.2 × 250.4 artboard (00 §5).
- **`PathData` → `ui.Path` is rebuilt per frame, not cached.** At the 00 §6 budget (114 anchors × 10 keyframes) this is free, and a cache keyed on mutable geometry is a stale-render bug waiting to happen. Revisit only if a profile says so.
- **Trim output is drawn, never joined.** After stage 7 the `AnchorId`s in `ResolvedNode.geometry` are synthetic and non-authoritative (01 §11). The painter draws them; the overlay layer draws *authored* anchors from `Document`, never from `Scene`.
- **Singular world matrix → draw nothing.** Never throw. The evaluator is total (00 §8 rule 3); the renderer must not reintroduce a crash the evaluator was built to prevent.

### Explicitly out of scope for v1

**Memory-leak hunting and allocation optimization are not v1 work.** 00 §6 fixes the perf budget at 114 anchors × 10 keyframes × 1 node and states that immutability and allocation churn are free at that scale. Object pooling, `Path` caching, and shader warm-up are deliberately omitted, not overlooked. The UI-performance work that *is* in scope is exactly the narrow list above: `RepaintBoundary` placement, repaint scoping, and no rebuild storms during scrub or drag.

---

## 6. Undo / redo

Every mutation in 01 §12 is already a pure `Document → Document` function. Undo rides that directly.

```dart
abstract interface class Command {
  String get label;                       // shown in the UI ("Insert anchor")
  Document apply(Document before);
}

final class InsertAnchorCommand implements Command {
  final NodeId node; final AnchorId after; final double u;
  @override String get label => 'Insert anchor';
  @override Document apply(Document d) =>
      PathOps.insertAnchor(d, node, after: after, u: u).$1;
}
```

**Undo is a bounded snapshot stack of immutable `Document`s, not inverse commands.**

| Decision | Reason |
|---|---|
| Snapshots, not inverses | `Document` is immutable, so a snapshot is a pointer and unchanged subtrees are shared. Hand-written inverse operations are where undo bugs live — and `PathOps.retopologize` has no clean inverse at all. |
| Depth 100 | Worst realistic document is ~150 KB (02 §9); the stack costs far less because structure is shared. |
| One command = one entry | `PathOps.insertAnchor` touches every keyframe of every path track across every animation, and undoes as **one** entry (01 §12). |
| Gestures coalesce | `begin()` on drag start, `commit(label)` on drag end. A 200-event anchor drag is one entry, not 200. |
| Ephemeral state is **not** undoable | Selection, hover, zoom and tool mode never push entries. Undo restores the `EditorState.selectedKeyframe` captured with the snapshot (so undo returns you to where you were editing) but never restores `viewportTransform` — nothing is more disorienting than undo moving the camera. |
| Every mutation routes through `CommandStack.run` | `DocumentController` has no public setter. If a call site can assign `state = newDoc` directly, some call site eventually will, and that edit is unrecoverable. |

`rev` is **not** touched by undo — it increments only on a persisted save (01 §11).

---

## 7. Testing seams

The point of §1's dependency direction: **the entire irreplaceable part of this app is testable with `dart test` and no Flutter at all.**

| Under test | Harness | Notes |
|---|---|---|
| Model types, invariants, `Affine` algebra | `dart test` (`anim_core`) | no Flutter binding |
| Serializer round-trip | `dart test` | **the 00 §5 automated gate**, over all 8 legacy fixtures |
| `evaluate` — totality, continuity, the 8 stages | `dart test` | 00 §5 criteria 6 & 9 as assertions |
| `PathOps` / `TrackOps` / `NodeOps` invariants | `dart test` | incl. 01 §12's "identical `AnchorId` sequence across every keyframe" |
| Legacy importer | `dart test` | 8 fixtures × 50 sampled `t` |
| `CommandStack`, autosave debounce, `EditorController` | `flutter test` (unit, no widgets) | controllers hold no `BuildContext` |
| `ProjectStore` consumers | `flutter test` + `FakeProjectStore` | no emulator, no network |
| Scene → Canvas transform | **golden** | **the 00 §5 automated gate**: 450.2 × 250.4 artboard |
| Edit-at-keyframe wiring, dirty/saved indicator | `flutter test` (widget) | the two flows where a wiring bug is invisible to unit tests |

**No test tracks beyond these.** 00 §5 defines the CI gate as exactly two things — the round-trip property test over the 8 fixtures, and the golden transform test on the non-square artboard. Everything else in this table is developer-local coverage, not a release gate. Inventing a third gate is scope creep with a test-shaped alibi.

---

## 8. HLD note

**v1's high-level design is deliberately thin, and that is the correct answer.** A single-user Flutter Web SPA doing authenticated CRUD against a managed document store has no meaningful topology: one client, one store, no services to coordinate, no queues, no cache tier, no fan-out. Drawing a boxes-and-arrows diagram for it would be decoration.

The architecture that carries weight in v1 is what this doc actually specifies: package boundaries and dependency direction (§1), the persistence seam (§2), state ownership (§4), and the render pipeline (§5).

**Real HLD arrives with v1.1** — the Go service in `server/`: request lifecycle, auth boundary, the hybrid relational schema (02 §9b), `rev`-based optimistic concurrency, indexes and retention. That is where topology decisions start to exist. It is planned in [06](06_backend_v1_1.md) and it is post-ship, per 00 §4.

---

## Cross-links

- [00_vision_and_scope.md](00_vision_and_scope.md) — v1 scope, non-goals, success criteria, constraints.
- [01_domain_model.md](01_domain_model.md) — **authoritative** types, invariants, mutation API, evaluator pipeline.
- [02_file_format.md](02_file_format.md) — wire format, Firestore layout (§9), v1.1 PostgreSQL layout (§9b).
