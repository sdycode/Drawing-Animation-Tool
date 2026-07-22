# 06 — Roadmap

**What this doc is:** the build order — milestones `M0…M14`, each with a goal, the [03](03_features.md) features it contains, one **observable exit criterion**, a relative size, and its scope-leak risk. It sequences 03's features under 03's dependency graph and 04's package boundaries.
**What it is not:** a schedule. **There are no dates in this document and none may be added** — the owner builds alongside a full-time job, so any date would be fiction. Scope is [00 §3](00_vision_and_scope.md); types are [01](01_domain_model.md); structure is [04](04_architecture.md).

---

## 0. The four sequencing rules

| # | Rule | Reason |
| --- | --- | --- |
| 1 | **Every milestone ends deployed and shippable.** No milestone leaves the app half-migrated, half-wired, or buildable only locally. | The project may pause or stop permanently at any point. Whatever exists when it stops must be a working public URL, not a branch. **This is the single most important constraint in this document.** |
| 2 | **`anim_core` (domain + evaluator) leads its UI.** Model, ops and evaluator land and are `dart test`-green before the panel that drives them. | It is unit-testable with zero Flutter (04 §7) and it is the irreplaceable work. UI is re-writable; a correct bezier/keyframe engine is not. |
| 3 | **M0 is a walking skeleton, not a foundation layer.** The whole vertical slice — draw → key → scrub → save → reload → deployed — exists before any layer is deep. | Bottom-up layering defers integration to the end, which is where the last 40 months died. |
| 4 | **No backend milestone before the ship gate.** | 00 §4: the DB swap is deferrable forever; the editor is not. |

**Sizes are relative only:** **S** = a sitting or two · **M** = several sessions · **L** = the milestone you underestimate. `L` milestones are M4, M5.

---

## v1 — Milestones

### M0 — Walking skeleton (**M**)

**Goal:** one end-to-end vertical slice on a public URL. Every layer exists thin; none is deep.

| Contains | From 03 |
| --- | --- |
| `packages/anim_core` + `packages/anim_render` created, pubspec-enforced boundary (04 §1) | — |
| Explicit artboard, `Document` with `id` / `schemaVersion == 3` / `rev` | F1.1, F1.2 |
| `ProjectStore` interface + `FirestoreProjectStore` + `FakeProjectStore`, `--dart-define=BACKEND=firestore` | **F10.1** |
| **Firebase email/password auth — and nothing else.** Sign-up form, sign-in form, sign-out, session persists across reload. `uid` scopes the `appData/v3/users/{uid}` path; security rules deny cross-uid reads. **No social providers, no anonymous auth, no forgot-password, no email verification** (00 §4). Anonymous is rejected: a new `uid` per browser and per data-clear scatters one person's work across orphaned accounts. | F10.1 |
| One `PathNode` from a crude 3-click tool; one `PathTrack` with 2 keyframes; playhead scrub | thin F4.1, F6.1 |
| `evaluate` present with **all 8 stages as named functions** (stages 4/5/6 no-op; 7/8 pass-through) | thin F9.2 |
| CI (analyze + `dart test`) and web deploy to a public URL | F12.1 partial |

> **Exit criterion:** on the deployed URL, a stranger signs up with an email and password, draws a shape, sets a second keyframe, drags the playhead and sees it interpolate, reloads the browser, and the shape returns — still signed in.

**Build order inside M0 — deploy first, not last.** Commit one is a hello-world Flutter Web build live on the public URL: hosting chosen, base href correct, CanvasKit loading. It is the highest-variance item in M0 (hosting config, `--base-href`, cold start) and the only one that cannot be unit-tested. Doing it last means discovering it at the worst moment; doing it first means every later M0 commit is deployable. Everything else in this table lands on top of a URL that already works.

**Risk — the one that matters here:** building M0 "properly". M0's pen tool may be three clicks and no handles; its timeline may be a slider; its shape may be one hard-coded colour. **Depth in M0 is the failure mode.** Three things must nonetheless be right on day one, because retrofitting them is expensive: the `ProjectStore` `String`-in/`String`-out seam (03 F10.1: cheap at commit one, expensive at commit three hundred), the 8 named evaluator stages (an inlined walk gets re-inlined everywhere before anyone notices), and ID-matched `PathPose` interpolation — M0's two keyframes must tween by `AnchorId`, never by index, or M0 quietly re-creates the legacy defect the whole rewrite exists to fix.

---

### M1 — Domain core & the CI gate (**M**)

**Goal:** `anim_core` is complete and provably correct before UI is built on it. This is rule 2 in its purest form.

| Contains | From 03 |
| --- | --- |
| All 60 types of 01 §2–§10; `Affine` is the **only** matrix | F1.1, F3.1 |
| Decoder split strictly by **required vs optional** (see the boundary below); every numeric read via `double d(Object? v)` | F10.2 |
| `UnknownNode` verbatim re-emit; `rev` round-trip | AC-1.2.4, AC-1.2.3 |
| **Round-trip property test over the 8 authored v3 fixtures** + **golden transform test on 450.2 × 250.4** wired as a red-blocks-deploy CI gate | AC-12.1.4, AC-10.2.5, AC-1.1.2 |

> **The decoder boundary — required throws, everything else degrades.** 00 §7 ("strict decoder, missing required subtree throws with a path") and 08 §2 ("decode degrades, never validates-and-throws") are both in force; they are not in conflict once the line is drawn where it belongs, and it is drawn here and in 08 §2 in the same words.
> **Throws `DocumentException` carrying a JSON path:** a missing or unusable **required root-level structure** — `schemaVersion`, `id`, `artboard`, `root` — and, transitively, every structure *they* require in turn (a node's `type` and `id`, a path node's `path`, an anchor's `id` and `position`, an animation's `id`). There is no document to show without them, and a silently empty canvas reads to the user as data loss. The path is the point: absent a location, "invalid document" is what makes a corrupt file unfixable.
> **Degrades and is preserved, never throws:** unknown node `type` → `UnknownNode` verbatim · unknown `paint.type` → `UnknownPaint` · unknown `easing.kind` → `UnknownEasing` · a malformed or invariant-violating track → kept raw in `TrackSet.unknownKeys` and not evaluated · an orphan pose id → dropped with a warning · unknown keys at every level → re-emitted. This is the forward-compat contract of 02 §8: a field a newer client adds must never make the document unopenable in an older one.

> **Which 8 fixtures — and why this had to be restated.** The gate round-trips **8 authored v3 fixtures checked into `packages/anim_core/test/fixtures/`**, chosen between them to cover the whole type surface (minimal document, nesting, geometry, paint, all five track types, the forward-compat unknowns, trim, and the 450.2 × 250.4 lopsided board). 00 §5 and 04 §7 originally read "all 8 legacy fixtures", which could not be satisfied at M1: `LegacyImporter` is **F11.3, milestone M8**, so at M1 there is nothing to import and the gate as worded could not exist. At **M8 the 8 imported legacy documents join this SAME test** — a ninth through sixteenth case in one file, not a third gate.

> **Exit criterion:** `dart test` in `anim_core` is green with zero Flutter imports resolvable, both CI gate tests pass as their own named workflow steps ahead of `flutter build web`, and a push with a broken round-trip is blocked from deploying.

**Risk:** inventing test tracks. 04 §7 defines the gate as **exactly two** tests. Everything else is developer-local coverage. A third gate is scope creep with a test-shaped alibi. The honest cost of holding that line: fixture *coverage* is asserted by the table at the head of the round-trip test, not mechanically, so adding a type to `anim_core` without extending a fixture fails nothing. Extending a fixture is part of adding a type — a coverage-completeness checker would be the third gate.

---

### M2 — Scene graph, layers, transforms (**M**)

**Goal:** the document becomes a real tree with real transform authoring.

| Contains | From 03 |
| --- | --- |
| Nested `GroupNode`, `NodeOps.createGroup` / `reparent` / `duplicateSubtree`, `clipChildren` | F2.1 |
| Layers panel — reversed tree, drag-reorder as a `children` splice, rename, `visible` AND, `opacity` PRODUCT, `locked` | F2.2 |
| `Transform2` authoring: position / scale / pivot / rotation (unbounded radians) / skewX | F3.1 |
| Riverpod `DocumentController` / `EditorController` / `ToolController` (04 §4); `CommandStack` snapshot undo (04 §6) | — |
| **Viewport pan/zoom** — `Space`/middle-drag pan, `Cmd/Ctrl`+scroll zoom-at-cursor, `Cmd/Ctrl+0/1`. `EditorState.viewportTransform` composed with `artboardFit` in **one** place; **ephemeral only** — no `Document` write, no `rev` bump, no undo entry, never persisted (ADR-018) | 05 §3 |

> **Exit criterion:** a 3-level nested document reorders, reparents and duplicates correctly; a reparented node does not visually move; `Ctrl+Z` reverts a duplicate-subtree as **one** entry. **Every step of that sentence is performed by hand, through the UI** — the document is built, grouped and nested with the shipped affordances, not assembled by a test calling `run(...)`. Panning and zooming the board leaves `rev` and the stored bytes untouched.

**Risk:** `EditorState` bleeding into `Document`. Selection, hover and zoom must never be persisted (AC-2.2.7) — this is the legacy defect that made documents unloadable.

**Second risk, learned here rather than predicted:** *a command with no way to invoke it.* M2's ops were correct and green while `createGroup` and `duplicateSubtree` had **zero call sites outside tests** — no `Cmd/Ctrl+G`, no `Cmd/Ctrl+D`, no button — so the exit criterion above passed in CI and was unreachable by a person. A milestone's tests proving an op works is not evidence the milestone shipped; the exit criterion is written to be run by hands, and it must be *checked* that way.

---

### M3 — Pen tool, paths, paint (**M**)

**Goal:** the drawing surface is real. Cubic-only geometry, solid paint.

| Contains | From 03 |
| --- | --- |
| Pen tool, closed paths, `AnchorKind` handle behaviour, unique `AnchorId`s | F4.1 |
| Shape tools emitting anchors + **inert** `RectRecipe` / `EllipseRecipe` / `PolygonRecipe`; recipe edits route through `PathOps.retopologize` | AC-4.1.4, AC-4.1.5 |
| `PathData`'s const constructor private — `PathOps` is the only route to a topology change | AC-4.3.8 |
| Solid `Fill` + `Stroke` (width, `StrokeCap`, `StrokeJoin`), `FillRule`, fills-then-strokes order | F5.1 |
| Three stacked painters, each in its own `RepaintBoundary` (04 §5) | E13 partial |

> **Exit criterion:** click-click-drag-close produces a filled, stroked closed path with at least one curved segment; a grep finds no polyline branch and no second segment type.

> **⚠ Scope-leak risk — gradients.** 00 §4 names gradient authoring as one of the **two most likely leaks**. `LinearGradientPaint`, `RadialGradientPaint`, `GradientStop` and `StopId` exist in the sealed `PaintSource` type and get **no authoring UI** (AC-5.1.3). It looks like an afternoon. It is a week. The type is sealed precisely so it stays additive later.

---

### M4 — Timeline, keyframes, easing (**L**)

**Goal:** per-node, per-property animation with per-segment easing — the model half of what the legacy tool got wrong.

| Contains | From 03 |
| --- | --- |
| Sparse per-node/per-property tracks; the exhaustive **15**-member `kExpectedTrackType[PropKey]` mapping (`pivot` is excluded — 01 §4) | F6.1 |
| `TrackOps.upsertKeyframe` / `moveKeyframe` (index resolved at command-construction) / `minSeparation` / `pinEndpoints` | F6.2 |
| Edit-at-keyframe selection; pose editing (`PathOps.moveAnchor`, `setTangents`) is **keyframe-local** | F4.2, AC-6.2.6 |
| Per-segment `Easing` — `LinearEasing` model default, `CubicEasing`, `HoldEasing`; presets lower at authoring time | F7.1 |
| Interpolation: ID join over `Map<AnchorId, AnchorPose>`, bool steps, unbounded rotation, hold-first/hold-last | F7.2 |
| `Vec2Keyframe` spatial tangents (null = straight-line fast path), orthogonal to time easing | F7.3 |
| Playhead as `ValueNotifier` on `CustomPainter(repaint:)` — the tick never enters `build()` (04 §4) | E13 partial |

> **Exit criterion:** 00 §5 criterion 2 passes — 3 path keyframes at fractional times with a different easing on each segment — and four nodes with independent key positions all animate while only one is selected (AC-6.1.5).

> **⚠ Scope-leak risk — per-anchor tracks.** The other of 00 §4's two named leaks. Whole-path keyframes only: one `PathTrack` per node, `PathPose` per key. The moment an individual anchor gets its own track, rule 2 (identical `AnchorId` sequence across keyframes) has nothing to enforce and M5 becomes impossible.
>
> Second risk: coincident keys. `Squares.json` holds three keys at exactly `20.34722169240316`. `minSeparation = 1e-4` must be enforced **at mutation**, not patched in the sampler.

---

### M5 — Topology editing ★ (**L**)

**Goal:** the feature the rewrite exists for. Insert an anchor at one keyframe; every keyframe of every path track for that node, across every `Animation`, gains it — and the others render pixel-identically.

| Contains | From 03 |
| --- | --- |
| `PathOps.insertAnchor(after:, u:)` — one minted `AnchorId`, de Casteljau split of *each keyframe's own* cubic at `u` | AC-4.3.1, AC-4.3.2 |
| `PathOps.deleteAnchor` — removed from `PathData` **and** every keyframe pose | AC-4.3.5 |
| `PathOps.retopologize` — arc-length correspondence, once per edit, **never inside the tick** | AC-4.3.7 |
| One command = one undo entry across every touched keyframe | AC-4.3.3 |
| CI invariant test: identical `AnchorId` sequence across every keyframe of every path track | **AC-4.3.6** |

> **Exit criterion:** 00 §5 criterion 3 passes on the deployed URL — return to keyframe 1, insert a mid-path anchor, scrub the full range: no crash, no vanishing shape, no frozen animation, keyframes 2 and 3 pixel-identical to before.

**Risk:** starting downstream work early. 03 names this the critical path's terminus — **nothing downstream of F4.3 should begin before AC-4.3.6 is green in CI.** If topology is wrong, every later milestone is built on a defect that only appears at demo time. Second risk: "pixel-identical" is a claim about *exactness*, not best effort — a nearly-correct split passes visual inspection and fails the golden.

---

### M6 — Trim, transport, full evaluator (**M**)

**Goal:** the pipeline reaches its final shape and the stroke-reveal demo works.

| Contains | From 03 |
| --- | --- |
| `PathTrim` — `trimStart` / `trimEnd` / `trimOffset` as keyable `ScalarTrack`s, arc-length fractions, node-local | F8.1 |
| Arc-length table **memoized per immutable `PathData`** (01 §5 — the only real perf hazard in the model) | AC-8.1.7 |
| Transport: play/pause, `LoopMode.once` / `loop` / `pingPong` via `normalizedTime` **outside** the evaluator, live scrub preview, `durationSeconds` retime | F9.1 |
| Full 8-stage pipeline: `sampleTracks → resolvePose → composeWorldA → solveConstraints → composeWorldB → deform → applyTrim → resolvePaint` | F9.2 |

> **Exit criterion:** 00 §5 criteria 4, 5 and 6 pass — a group rotates while its child spins the opposite way at a different rate; a stroke draws itself on then fades out; a full 0→1 scrub yields no NaN, no empty geometry, no error dialog, shape present at `t = 1.0`.

**Risk:** deleting the no-ops. `solveConstraints`, `composeWorldB` and `deform` are **seams for IK, re-compose and skinning**. Removing them because they "do nothing" is a scope violation, not a cleanup (AC-9.2.2). Second risk: rebuilding the arc-length table per tick — it is invisible at 3 anchors and fatal at 114.

---

### M7 — Autosave hardening & the narrow perf pass (**S/M**)

**Goal:** close the only real data risk in v1, then stop optimizing.

| Contains | From 03 |
| --- | --- |
| Debounced autosave — one write after the edit settles, never one per frame | AC-10.3.1 |
| `enablePersistence()`; offline edits queue and flush | AC-10.3.2 |
| Visible **dirty / saving / saved / error** indicator; a failed write retains the edit in memory, no modal | AC-10.3.3, AC-10.3.4 |
| `rev` increments by exactly 1 per persisted save — **written, not enforced** (v1.1 turns this same field into the concurrency check with no schema break) | AC-10.3.5 |
| `RepaintBoundary` placement verified; no rebuild storm on scrub or anchor drag at the 114 × 10 budget | E13 |

> **Exit criterion:** a 5-second continuous drag produces one Firestore write; the indicator visibly transitions dirty → saving → saved; scrubbing the perf-budget document repaints the canvas without rebuilding the layers panel.

**Risk — stated, not silently omitted:** **memory-leak hunting, allocation-churn reduction and object pooling are out of v1.** 00 §6 fixes the budget at 114 anchors × 10 keyframes × 1 node and states allocation churn is free at that scale. A day spent here buys nothing measurable and costs the editor.

---

### M8 — `anim_core` publish, export, legacy import, samples (**M**)

**Goal:** the document becomes portable and the app becomes demonstrable to a stranger.

| Contains | From 03 |
| --- | --- |
| Versioned `.json` export — **the persistence serializer**, exactly one `toJson` path per type, no export-only path | F11.1 |
| **`anim_core` published to pub.dev** (model + serializer + evaluator, zero Flutter imports); `anim_render` published alongside as the `CustomPainter` binding | F11.2 |
| One-way `LegacyImporter` over the 8 fixtures — camelCase mapping, coincident-key repair, per-keyframe vertex-count repair via `PathOps.retopologize` | F11.3 |
| Sample gallery; opening + editing a sample saves a **new** project under `appData/v3` | F11.4 |

> **Exit criterion:** 00 §5 criteria 8 and 9 pass — an exported `.json` replays at 50 sampled `t` values in a plain Flutter app depending only on `anim_core` + `anim_render`, and all 8 legacy fixtures import and play clean.

**Risk:** treating the old package as a target. `annimation` v0.0.2 is built on the legacy structure — **not a dependency, not a compatibility target, not a migration path.** It reads the legacy format and cannot read a v3 document; that is why v3 ships a new package rather than a version bump. A grep for `annimation` in the v3 codebase must return zero (AC-11.2.3). Second risk: SVG and Lottie export are v2 — not built, **not stubbed**.

---

### M9 — Ship gate verification (**S**)

**Goal:** prove it, on the URL, with someone else's hands.

| Contains | From 03 |
| --- | --- |
| A person who is not the owner runs all 9 of 00 §5 on the public URL, unassisted, and the transcript is recorded | F12.1 |
| Both CI gate tests green on `main`; Flutter Web only, no mobile/desktop target configured | AC-12.1.4, AC-12.1.5 |

> **Exit criterion:** all 9 criteria pass on the deployed URL without assistance. Anything that fails re-opens its owning milestone; it does not get waived.

---

<hr>

> # 🚧 V1 SHIP GATE — HARD BARRIER 🚧
>
> ### Nothing below this line may begin until **all 9 success criteria in [00 §5](00_vision_and_scope.md#5-success-criteria-for-v1) pass on a public URL**, run by someone who is not the owner, without assistance — plus the two CI gate tests green.
>
> **No backend milestone may appear before it, be prototyped before it, or be "started while blocked" before it.** 00 §4 lists the Go + PostgreSQL service as an explicit v1 non-goal; its presence in this document is a *deferred plan*, not scope.
>
> **Why the barrier is absolute:** the editor — bezier engine, stable-`AnchorId` topology, total evaluator — is the irreplaceable work and cannot be bought, borrowed, or resumed cheaply. The persistence swap is pre-paid by the `ProjectStore` seam and remains deferrable forever. If this project stops permanently at M9, a working animation editor is live on the internet. If it stops mid-M11, nothing is.

<hr>

---

## v1.1 — after the gate

**Every v1.1 milestone is additive.** `firestore_project_store.dart` is never deleted, `BACKEND=firestore` never stops building, and `main` stays deployable at every commit (rule 1 does not relax after the gate — it matters *more*, because this is the phase most likely to be abandoned midway).

### M10 — Go service skeleton, deployed (**M**)

**Goal:** an HTTP service exists and is reachable. Flutter Web has no `dart:io`, so a browser cannot speak the Postgres wire protocol — the service is a forced consequence of the platform, not optional scope (04 §3).

| Contains |
| --- |
| `server/` — Go HTTP service: health endpoint, structured logging, config, Dockerfile |
| JWT verification + ownership checks; no document parsing anywhere in Go |
| Deployed to a public host; CI builds it |

> **Exit criterion:** `GET /healthz` returns 200 from the public service URL, and an unauthenticated request to a project route returns 401. The editor is untouched and still live on `BACKEND=firestore`.

**Risk:** re-implementing the evaluator in Go. **The evaluator exists in exactly one place — `anim_core`.** A second implementation is two evaluators that disagree, which is the bug class this rewrite exists to eliminate. The server treats `body jsonb` as opaque except to extract projection columns on write.

---

### M11 — PostgreSQL hybrid schema (**M**)

**Goal:** real relational modelling, not a blob.

| Contains |
| --- |
| Hybrid schema per [02 §9b](02_file_format.md) — `projects` with typed projection columns (`owner_id`, `name`, `rev`, `schema_version`, `updated_at`, soft-delete) + `body jsonb` |
| Migrations checked in and applied by CI; indexes on the projection columns |
| CRUD handlers + `list()` served **from typed columns**, never by scanning JSON |

> **Exit criterion:** `curl` creates, lists, updates and soft-deletes a project against the deployed service; `EXPLAIN` on the list query shows an index scan, not a seq scan.

**Risk:** collapsing into a single `jsonb` blob. Postgres keeps no statistics on JSONB keys, so a blob produces bad plans and teaches nothing — the whole point of this milestone is the projection columns.

---

### M12 — `http_project_store.dart` (**S**)

**Goal:** the seam pays out.

| Contains |
| --- |
| `lib/data/http_project_store.dart` — **added beside** `firestore_project_store.dart`, never replacing it |
| `flutter build web --dart-define=BACKEND=api --dart-define=API_URL=…`; the const switch tree-shakes the unused implementation |
| Both backends exercised by the same `ProjectStore` consumer tests |

> **Exit criterion:** the identical editor build, flipped only by `--dart-define`, saves and reloads a document byte-identically from Postgres — with **zero diffs under `lib/domain/**` and `packages/`**. That diff (or its absence) is the whole argument for the seam.

**Risk:** a forked branch. Same repo, same branch, additive files only. A long-lived rewrite branch rots against `main` and never merges.

---

### M13 — Optimistic concurrency via `rev` (**S**)

**Goal:** detect the two-tab clobber that v1 accepts blindly.

| Contains |
| --- |
| Server rejects a save whose `rev` ≠ stored `rev` with `409 Conflict` |
| Client surfaces the conflict in the existing dirty/saving/saved/error indicator — no new UI surface |

> **Exit criterion:** two browser tabs open the same project; the second save returns 409 and the user is told, instead of silently overwriting. **No schema change was required** — `rev` has been written since M0.

---

### M14 — Version history & restore (**M**)

**Goal:** the capability Firestore never gave, justifying the swap.

| Contains |
| --- |
| `project_versions` — append a row per accepted save, retention policy |
| List versions; restore a version as a new save (`rev` advances forward; history is never rewritten) |

> **Exit criterion:** a document edited five times lists five versions; restoring version 2 yields byte-identical geometry to version 2 and produces `rev = 6`, not `rev = 2`.

**Risk:** unbounded growth. Retention is decided in this milestone, not after the table is large.

---

## Milestone summary

| # | Milestone | Size | 03 features | Ships |
| --- | --- | --- | --- | --- |
| M0 | Walking skeleton | M | F10.1, F1.1, F1.2, thin F4.1/F6.1/F9.2, F12.1 partial | Public URL, draw→key→scrub→save→reload |
| M1 | Domain core & CI gate | M | F1.1, F1.2, F3.1, F10.2 | Both gate tests red-block deploy |
| M2 | Scene graph, layers, transforms | M | F2.1, F2.2, F3.1 | Nested tree, undo |
| M3 | Pen tool, paths, paint | M | F4.1, F5.1 | Real drawing surface |
| M4 | Timeline, keyframes, easing | **L** | F6.1, F6.2, F4.2, F7.1, F7.2, F7.3 | 00 §5 criterion 2 |
| M5 | **Topology editing ★** | **L** | F4.3 | 00 §5 criterion 3 |
| M6 | Trim, transport, full evaluator | M | F8.1, F9.1, F9.2 | 00 §5 criteria 4, 5, 6 |
| M7 | Autosave hardening & perf pass | S/M | F10.3, E13 | 00 §5 criterion 7 |
| M8 | `anim_core`, export, import, samples | M | F11.1–F11.4 | 00 §5 criteria 8, 9 |
| M9 | Ship gate verification | S | F12.1 | **v1** |
| — | 🚧 **HARD BARRIER** 🚧 | — | — | — |
| M10 | Go service skeleton | M | — | Deployed service |
| M11 | PostgreSQL hybrid schema | M | — | Real CRUD over Postgres |
| M12 | `http_project_store.dart` | S | — | `BACKEND=api` |
| M13 | `rev` optimistic concurrency | S | — | 409 on clobber |
| M14 | Version history & restore | M | — | **v1.1** |

**Critical path (03):** `F1.1 → F2.1 → F4.1 → F4.2 → F6.1 → F6.2 → F4.3` — M0 → M2 → M3 → M4 → **M5**. Everything else is scheduled around it.

**If the project stops permanently, the best stopping points are M5 and M9** — M5 because the irreplaceable engineering is then done and demonstrable, M9 because it is v1.

---

## Cross-links

- [00_vision_and_scope.md](00_vision_and_scope.md) — scope, non-goals, the 9 success criteria that define the barrier.
- [01_domain_model.md](01_domain_model.md) — authoritative types, invariants, mutation API, evaluator pipeline.
- [02_file_format.md](02_file_format.md) — wire format, Firestore layout (§9), PostgreSQL layout (§9b) for M11.
- [03_features.md](03_features.md) — the features and acceptance criteria this doc sequences.
- [04_architecture.md](04_architecture.md) — package boundaries, `ProjectStore` seam, state, render pipeline, undo, testing.
- [05_ux_flows.md](05_ux_flows.md) — the flows the milestones make usable.
- [07_decisions.md](07_decisions.md) — the decision records behind these milestones.
