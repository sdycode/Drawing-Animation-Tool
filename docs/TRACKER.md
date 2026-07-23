# v3 Tracker

⚪ not started · 🔵 in progress · 🟡 thin/stubbed · 🟢 done · 🔴 broken

**Now:** M3 — F4.1 pen tool (`AnchorKind`, closed paths, curved segments) · shape tools + inert recipes · F5.1 solid fill & stroke authoring. M2 shipped the tree, the panels, undo and pan/zoom; F12.1 deploy stays parked (web build is CI-verified).

| M | Feature | S |
|---|---|---|
| **M0** | Repo skeleton, `anim_core` + `anim_render` packages | 🟢 |
| | Boundary check + CI (format·analyze·test·boundaries·build) | 🟢 |
| | F12.1 Public web build on a URL | 🟡 builds; deploy parked |
| | F10.0 Auth — email/password only | 🟢 |
| | F10.1 `ProjectStore` seam + Firestore/Memory impls | 🟢 |
| | Light/dark theme (dark default) · sign-out confirm | 🟢 |
| | F1.1 Artboard · F1.2 `Document` id/`schemaVersion`/`rev` | 🟢 |
| | `Affine`/`Transform2` + decompose · forward-compat passthrough | 🟢 |
| | New/delete project — real `Document` saved and decoded back | 🟢 |
| | F4.1 Path creation *(thin: 3 clicks)* · `PathData`/`Anchor` | 🟢 |
| | F5.1 Solid fill & stroke *(model + renderer; no paint UI)* | 🟡 |
| | `artboardFit` + background/artboard/overlay painters — editor draws | 🟢 |
| | F6.1 Tracks *(thin: one `PathTrack`, 2 keys, ID-matched `PathPose`)* | 🟢 |
| | F9.2 8 named stages *(4/5/6 no-op · 7/8 pass-through)* · typed `Document.animations`/`defaultAnimationId` | 🟢 |
| | F4.2 Pose edit *(thin: anchor drag at playhead auto-seeds `t=0`)* · `PathOps.moveAnchor` · `TrackOps.upsertKeyframe` | 🟡 |
| | Playhead scrub with live preview — `ValueNotifier` hot path, never serialized | 🟢 |
| | App restructured to `v3/08` §3 — `state/` · `features/canvas` · `features/timeline` · `editor_shell` | 🟢 |
| **M1** | Full 01 §2–§10 type surface — nodes/paint/tracks(×5)/easing/recipes/`PathTrim`; `Affine` the only matrix | 🟢 |
| | F10.2 decoder split by required vs optional — required (`schemaVersion`/`id`/`artboard`/`root` + transitive) throws `DocumentException` w/ path; all else degrades | 🟢 |
| | `Unknown`Node/Paint/Easing/Recipe verbatim re-emit · malformed tracks raw in `TrackSet.unknownKeys` · `rev` round-trip | 🟢 |
| | CI gate 1/2 round-trip ×8 authored v3 fixtures · gate 2/2 golden 450.2×250.4 — own named steps, red-blocks `build web` | 🟢 |
| | `anim_core` 297 `dart test` green · zero try/catch · zero bare `as double` (all via `d()`/`i()`) · `boundary_test` enforced | 🟢 |
| **M2** | F2.1 Nested scene graph — `NodeOps` create/reparent/duplicate + `setVisible`/`setLocked`/`setOpacity`/`reorderChild` | 🟢 |
| | F2.2 Layers panel — reversed tree, drag-reorder splice, drop-into-group, rename, eye/lock, `visible` AND · `opacity` PRODUCT | 🟢 |
| | F3.1 `Transform2` + opacity authoring (inspector) · canvas select & move · groups selectable/draggable | 🟢 |
| | `CommandStack` snapshot undo — depth 100, one command = one entry, gesture coalescing, undo **persists**, `rev` monotonic | 🟢 |
| | Three controllers complete — `ToolController` contract in `state/`, tools injected at composition | 🟢 |
| | **Viewport pan/zoom** (ADR-018) — one composed `Affine`, zoom-at-cursor, ephemeral-only | 🟢 |
| | `clipChildren` — data + decode only at M2; **clipping shipped in M3** (AC-2.1.6) | 🟢 |
| | Reparent of a *transform-animated* node refused (exact per-keyframe rewrite is M4) | 🟡 M4 |
| **M3** | F4.1 Pen tool, `AnchorKind`, closed paths | ⚪ |
| | F5.1 Solid fill & stroke | ⚪ |
| **M4** | F6.1 Per-node/per-property tracks · F6.2 Keyframe ops | ⚪ |
| | F4.2 Pose editing · F7.1 Easing · F7.2 Interpolation · F7.3 Spatial tangents | ⚪ |
| **M5** ★ | **F4.3 Topology editing** — insert/delete anchor mid-animation | ⚪ |
| **M6** | F8.1 `PathTrim` · F9.1 Transport · F9.2 Full evaluator | ⚪ |
| **M7** | F10.3 Autosave + dirty/saved indicator · E13 perf pass | ⚪ |
| **M8** | F11.1 Export · F11.2 `anim_core` replay · F11.3 Importer · F11.4 Samples | ⚪ |
| **M9** | Ship gate — all 9 of `v3/00` §5 on the URL | ⚪ |
| 🚧 | **V1 SHIP GATE — nothing below starts before this** | |
| M10-14 | Go service · Postgres · `BACKEND=api` · `rev` concurrency · history | ⚪ |

★ = the load-bearing feature. Best stopping points if this pauses: **M5** (irreplaceable work done) or **M9** (v1).

**Owner notes** — direct product feedback, carried between milestones. Not scheduled scope; recorded so it is not lost.
- **Editor exposes very few operations.** Owner flagged this on first use. Breadth is real, scheduled work arriving across M2–M6. M2 answered most of it — select · move · group · duplicate · reorder · nest · rename · hide/lock · opacity · undo/redo · pan/zoom. Still to come: drawing depth (M3), keyframe editing (M4), play/transport (M6).
- ~~**No board pan/zoom — roadmap gap**~~ **RESOLVED in M2.** It was specified (`v3/01 §12`, `v3/04 §5`) but scheduled by no milestone. Owner approved folding it in; now built, recorded as **ADR-018**, and added to `v3/06` M2's contents and exit criterion.
- **Owner-requested capabilities, so their landing is visible:** select a whole object and move it → **shipped, M2**. Play/transport → **M6** (F9.1).
- **Live drag feedback** (owner: a drag should show the new shape, not just a moving dot) → **shipped**; the preview re-applies the *same* op the release commits, so what you see cannot disagree with what lands.

**Carried into M3** — found by M2's audit:
- ~~`clipChildren` renders nothing~~ **FIXED in M3.** A clipping group's window is the **artboard rect in the group's own local space** (the AE precomp rule) — union-of-descendants is self-defeating, since it contains everything by construction. Hierarchy comes from one `clipChains(Document)` walk (topology only, no coordinates, so it is not a second evaluator); a stack diffs chains along the flat `drawOrder` so nested clips compose and none leaks to a sibling.
- ~~The tool layer is a **seam, not a feature**~~ — being wired in M3 along with the pen and shape tools.
- `CommandStack`'s gesture coalescing (`beginGesture`/`commitGesture`) is correct and tested but **has no call site** — the canvas gets one-entry-per-drag from a local preview plus a single command on release, which also satisfies `v3/04 §6`. Wire it only if a gesture needs to issue *multiple* commands; putting in-progress state into `Document` would violate `v3/08 §2`.

**Known limits recorded in M3, needing a decision later:**
- **A clipping group's window is always the artboard's size/aspect.** `GroupNode` has no extent of its own, so `position`/`scale`/`rotation` move and resize the window *and* its children together. A 100×50 window independent of its content needs a new `GroupNode` rect — a field in `anim_core`, the wire format and the decoder. Not invented; recorded.
- **Hit-testing is not clip-aware.** Geometry clipped away is invisible but still clickable and selectable. Making it consistent means intersecting `selectionBounds` with the clip chain, or the pinned property *"the outline you see is the box the hit-test answers for"* breaks for clipping groups.
- **Recipe regeneration is refused on a path-tracked node** (`PathOps.regenerateRecipe` throws, naming M5). AC-4.1.5 routes it through `retopologize`, which `v3/06` schedules at **M5**; a cheap approximation shipped under the real name is a defect M5 would inherit invisibly. Shape-parameter fields must be disabled, with M5 named, on a node that has path keyframes.

Detail: [v3/03_features.md](v3/03_features.md) · [v3/06_roadmap.md](v3/06_roadmap.md) · isolation rules: [v3/08_feature_isolation.md](v3/08_feature_isolation.md)
