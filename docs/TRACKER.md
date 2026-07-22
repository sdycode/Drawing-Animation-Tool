# v3 Tracker

⚪ not started · 🔵 in progress · 🟡 thin/stubbed · 🟢 done · 🔴 broken

**Now:** M2 — F2.1 nested scene graph · F2.2 layers panel · F3.1 `Transform2` authoring · `CommandStack` undo. M1 shipped `anim_core` complete and gated; F12.1 deploy stays parked (web build is CI-verified).

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
| | `anim_core` 260 `dart test` green · zero try/catch · zero bare `as double` (all via `d()`/`i()`) · `boundary_test` enforced | 🟢 |
| **M2** | F2.1 Nested scene graph · F2.2 Layers panel | ⚪ |
| | F3.1 `Transform2` authoring · undo (`CommandStack`) | ⚪ |
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
- **Editor exposes very few operations.** Owner flagged this on first use. Breadth is real, scheduled work — it arrives across M2–M6, not in one step; this is expected at M1, not a defect.
- **No board pan/zoom — genuine roadmap gap, needs a decision.** No milestone in `v3/06` schedules viewport pan/zoom. `viewportTransform` *is* specified (`v3/01 §12` EditorState; `v3/04 §5` says hit-testing inverts it) but the **feature** is unscheduled. This is a gap in the roadmap, not a bug in the code.
- **Owner-requested capabilities, so their landing is visible:** select a whole object and move it → **M2** (F2.1/F3.1 authoring). Play/transport → **M6** (F9.1).

Detail: [v3/03_features.md](v3/03_features.md) · [v3/06_roadmap.md](v3/06_roadmap.md) · isolation rules: [v3/08_feature_isolation.md](v3/08_feature_isolation.md)
