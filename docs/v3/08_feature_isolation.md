# 08 — Feature Isolation

**What this doc is:** the mechanical rules that keep one broken feature from taking the editor down — patterns you apply *while writing* each feature, at zero up-front cost.
**What it is not:** a plugin system, a feature-flag registry, or a new layer. Nothing here is built before it is used; every rule is a habit, a directory, or a three-line CI check.

**The one sentence:** isolation comes from what a feature can *reach*, not what it promises. If no widget can watch the whole `Document`, no op can touch `EditorState`, and no draw loop is guarded per frame instead of per item, most cross-feature breakage is unrepresentable.

---

## 1. Where guards belong — get this one right

The evaluator is **total by construction** (01 §1 rule 3). Totality is a *proof obligation*, not a runtime behaviour, so `anim_core` contains **zero** `try/catch`. A catch inside `sampleAt` / `resolvePose` / `composeWorldA` / `applyTrim` / `resolvePaint` converts a wrong-pixels bug into an invisibly frozen shape — it makes the totality and continuity invariants unfalsifiable and blinds the golden tests. That is exactly how legacy shipped a broken tweener behind swallowed `RangeError`s.

Containment belongs one layer out, at the **widget, painter, command, and IO boundaries** — where a failure is already a user-visible event and there is a slot to draw a fallback into.

| Layer | Guard? | Why |
|---|---|---|
| `anim_core` eval / ops | **Never.** Ops keep throwing `ArgumentError` on invariant violation | Loud failure is the product; the throw is what the command gate catches |
| `anim_render` painters | **Per item**, never per frame | One bad node vanishes; the other 113 render |
| `CommandStack.run` | One catch, one site | Bad mutation returns the previous `Document` untouched |
| Panels / widgets | `ErrorWidget.builder` + bounded slots | A dead timeline leaves the canvas usable |
| decode / `ProjectStore` | One exception type, one catch each | Corrupt file opens partially; save failure is a status enum |

Three fixes make the eval path throw-free, done once at M1: `PathTrack` overrides `sampleDynamic => null` (else a generic `byKey` loop reaches `interpolateKeys`' `StateError` and blanks the whole canvas); `resolvePose` uses an unchecked `PathData.trusted(...)` ctor, never the validating factory; `Affine.invert()` returning null is an early `return`, never `invert()!`.

Every catch that does exist reports to a visible fault sink **and** `assert(false, ...)` — loud in debug, contained in release. A `catch` that only returns is the quiet cousin of legacy's modal-per-frame.

---

## 2. Mechanical rules

| Rule | Failure it prevents |
|---|---|
| One feature = one directory + one provider file + one commands file + (optional) one tool file | "Disable this feature" is commenting out one line in the shell, not a refactor |
| Panels read **named slices only**; `ref.watch(_docProvider)` with no `.select` is banned outside `sceneProvider`, and the provider symbol is file-private | Legacy's 93 `updateUI()` call sites, reimplemented in Riverpod: an anchor commit rebuilding layers + inspector + timeline |
| `CommandStack.run` is the only place `Document` is replaced; `DocumentController` exposes no setter. Undo is pushed **after** `apply` returns | A half-applied `insertAnchor` plus a pushed undo entry desyncs the stack unrecoverably |
| `DocInvariants.ok(after)` runs on commit only (~25 lines, M1, +1 line per milestone). Its core check: every path keyframe's pose ids == the node's anchor topology | Pen tool, importer, `retopologize` and `duplicateSubtree` silently breaking each other's keyframes |
| Painters loop `try { _drawNode } catch { faults.report; assert(false) }` **inside** the loop | One broken gradient / degenerate trim / singular matrix erasing the artboard |
| Three painters stay three: background, `ArtboardPainter`, `OverlayPainter` — separate `CustomPaint`, separate `RepaintBoundary`. Never merged, whatever a profile says | The overlay is the least-tested code and dereferences paths undo just deleted; merged, that null takes the artboard with it |
| Selection is **resolved, never repaired**: dangling ids are legal, filtered at every read site (`whereType`, bounds-checked indices) | `NodeOps` growing a dependency on `EditorState` — inverting 04 §1 for every future op |
| Exhaustive `switch` is allowed **only** in `anim_core/lib/src/` and `anim_render/`. In `lib/app/`, dispatch through a map with a `?? SizedBox.shrink()` fallback | Adding `BoneNode` in v2 breaking 5 core files (correct) instead of 12 panels (not) |
| `PropKey` is never switched in UI code — one `kPropMeta` table in core drives inspector rows, timeline lanes and the keyframe button | Adding `trimOffset` = three features to touch and one to forget |
| Tools see only `PointerCtx {docPoint, scene, doc, editor}` and return `Command?`. In-progress drag state is a private field of the `Tool` (or its `ToolMode` variant) — never in `Document`, never in `EditorState` | An unfinished pen stroke being autosaved; a select tool that only works if the pen tool is loaded |
| `Provider` bodies must be provably total. Anything with `await`, `jsonDecode`, or Firestore is `Async*` and consumed with `.when` — never `.requireValue` | A throwing plain provider rethrows at every `ref.watch` and kills the whole tree |
| **Decode is split by required vs optional, and the line is at the document root.** A missing or unusable **required root-level structure** — `schemaVersion`, `id`, `artboard`, `root`, and transitively whatever they require in turn — throws `DocumentException` carrying a JSON path. **Everything else degrades and is preserved, and none of it may throw:** `as num?` casts, `?? default`, `unknownKeys` on every type, unknown node `type` → `UnknownNode` verbatim, unknown `paint.type` → `UnknownPaint`, unknown `easing.kind` → `UnknownEasing`, malformed or invariant-violating track → kept raw in `TrackSet.unknownKeys` and not evaluated, orphan pose → dropped + warning | Below the root: a field feature A adds on Monday making the document unloadable in feature B on Tuesday. At the root: a document with no `root` node opening as a blank canvas, which the user reads as their artwork having been deleted. The two failures pull in opposite directions, so one rule cannot serve both — hence the split. Stated in these same words in 06 M1 |
| Every panel gets constraints from its parent (`SizedBox(width: 260, …)`, `Expanded(…)`), and `main()` sets `ErrorWidget.builder = (d) => FeatureFallback(...)` accepting any constraints | Default `ErrorWidget` unconstrained inside a `Row` throws again during layout — the literal white screen |
| Persistence is a `SaveStatus` enum. The debounce timer is the only caller of `save`; no gesture handler ever `await`s the store; a failed save never clears the doc and never bumps `rev`; `_flush` refuses a doc failing `DocInvariants` | A Firestore hiccup freezing drawing — the least important feature blocking the most important one — or a permanently unopenable saved file |

---

## 3. Directory law

```
packages/anim_core/lib/src/{geom,eval,ops,serial}/   # shared math lives here or nowhere
packages/anim_render/lib/src/{artboard_painter,overlay_painter}.dart
app/lib/
  data/                    # ONLY place that imports cloud_firestore
  state/                   # document_controller, editor_controller, tool_controller
  common/                  # buttons, number fields — may NOT import features/
  app_shell.dart           # the one file that composes panels
  features/
    canvas/    { widgets/, providers.dart, commands.dart }   # only reader of sceneProvider
    layers/    { widgets/, providers.dart, commands.dart }
    inspector/ { … }
    timeline/  { … }
    transport/ { … }
    projects/  { … }
    tools/     { registry.dart, select/select_tool.dart, pen/pen_tool.dart, shape/shape_tool.dart }
```

Rules: a file under `features/X` may not import `features/Y` — enforced by `tool/check_boundaries.dart`, ~15 lines, added at **M0**, run in CI. That script is the entire "architecture enforcement" budget. Anything two features need moves **down** into `anim_core`, never sideways. Features talk only through the three controllers and `Command` objects.

---

## 4. Antipatterns — what would cause cascade failure here

| Antipattern | Blast radius |
|---|---|
| `try/catch` or a NaN clamp inside the evaluator | Silent frozen/collapsed shape; golden tests go blind; days bisecting the wrong package |
| Leaving `PathTrack.interpolateKeys`' `StateError` reachable | First path-animated node blanks the **entire** canvas — make it unreachable, don't wrap it |
| Merging the artboard and overlay painters | An overlay bug erases the document you need to see in order to recover it |
| `ref.watch(documentProvider)` / `ref.watch(editorProvider)` whole-object in a panel | One throwing panel red-screens the editor; hover updates rebuild everything |
| Bare `!` / `as` in `anim_render` and `features/canvas` — the recurring five: `invert()!`, `scene.byPath[p]!`, `doc.animations.first`, `trackSet.scalar(..)!`, `k0 as Vec2Keyframe` | Frame-ending null deref in the one code path with no test gate |
| An `app/widgets/` or `utils/` grab-bag, or geometry helpers written in `app/` | A shared mutable surface every feature imports; a second evaluator that disagrees with core |
| A feature caching `Scene` or a `PathData → ui.Path` map | Stale-render bug that looks exactly like an evaluator bug |
| Storing anything derived on `Document` (id index, cached AABBs, a zIndex beside `children`) | Desyncs precisely when two features mutate in one command — legacy's worst latent defect |
| Fanning the document across Firestore fields so "the timeline only writes tracks" | A partial write leaves poses referencing dead anchors — no client invariant can catch it |
| Routing the playhead through a provider instead of the `ValueNotifier` (04 §4) | Coupling through the frame budget: one slow panel makes scrubbing unusable app-wide |
| A generic `Command` with a `Map` payload, or `BatchCommand` | Unattributable invariant failures; `insertAnchor`'s backfill undoes as two entries |
| Ops clearing `EditorState.selectedNodes` "to be safe" | `anim_core` grows editor types; every future op inherits selection semantics |

---

## 5. Feature flags — verdict

**Premature. Do not build one before M4, and probably not at all in v1.** A runtime flag registry ships every code path in the web bundle, adds an `if` to every call site, and is the framework-first trap that produced 40 months of nothing (00 §4).

The property actually worth paying for is **deletability**, and §2–§3 already buy it: one feature = one folder + one map entry + one line in `app_shell.dart`. Deleting `pen_tool.dart` and its `kTools` line leaves a compiling app. That is a better kill switch than a flag, because it is checked by the compiler.

The one flag that has earned its place is the existing `const String.fromEnvironment('BACKEND')` store selection (04 §2) — it is compile-time and tree-shakes.

---

## Cross-links

- [01_domain_model.md](01_domain_model.md) — totality & continuity invariants (§1), the 8 stages (§11), `Document→Document` mutation (§12)
- [02_file_format.md](02_file_format.md) — `unknownKeys`, degrade paths, one doc / one JSON / one `rev` (§9)
- [04_architecture.md](04_architecture.md) — package boundaries (§1), store seam (§2), three controllers (§4), three painters (§5), undo (§6)
- [06_roadmap.md](06_roadmap.md) — M0 boundary script, M1 `DocInvariants` + eval fixes, M5 topology invariant
- [07_decisions.md](07_decisions.md) — ADRs this doc operationalises
