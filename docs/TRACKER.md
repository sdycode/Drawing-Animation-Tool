# v3 Tracker

⚪ not started · 🔵 in progress · 🟡 thin/stubbed · 🟢 done · 🔴 broken

**Now:** M5 ★ — **F4.3 topology editing**. ⏸ **PAUSED at a clean green checkpoint.** M5's **domain half is DONE and machine-proven**: `PathOps.insertAnchor` (exact de Casteljau — reproduces `v3/01 §13.5` to 1e-12, pixel-identical golden ~1e-12), `deleteAnchor`, `retopologize` (arc-length correspondence), the AC-4.3.6 invariant checker, and the three command classes. **M5's UI half is IN PROGRESS** (pen hover→insert, `Del`→delete, tracked recipe→`retopologize`): recipe-regeneration routing is wired; pen-insert / Del gestures are partially wired; ONE M4-era inspector test is `skip:true` (documented, un-skip on resume). Gate is green: anim_core 426 · anim_render 64 · app 209 (+1 skipped). **To resume: say "continue M5" — finish the UI stream, un-skip the test, then the 6-lens M5 audit.** F12.1 deploy stays parked (web build CI-verified).

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
| **M3** | F4.1 Pen tool — click=corner, click-drag=smooth (symmetric tangents), close on first anchor, `Esc`/`Enter` exit open · one cubic segment type, no polyline branch | 🟢 |
| | Shape tools `R`/`O`/`G` — rect/ellipse (4 cubics, κ=0.5523)/polygon-star, inert `ShapeRecipe`; `Shift`/`Alt` modifiers; live **outline** preview | 🟢 |
| | Direct-select `A` — drag anchors & handles, `AnchorKind` baked into stored tangents, `Alt` breaks symmetry; `PathOps.setTangents` | 🟢 |
| | F5.1 Solid fill & stroke **authoring** (inspector) — colour/opacity/rule + width/cap/join/miter; fills-before-strokes; addressed by `PaintId`; gradients rendered-not-authored | 🟢 |
| | Tool rail + `V`/`A`/`P`/`R`/`O`/`G` bindings — tool layer now real (dispatch through `ToolMode`, cancelled on switch/cancel/dispose) | 🟢 |
| | `regenerateRecipe` — replaces an untracked node's path; **refuses** a path-tracked node (correspondence is M5) | 🟢 |
| **M4** | F6.1 Per-node/per-property tracks · F6.2 keyframe ops — `TrackOps.moveKeyframe`/`removeKeyframeAt`/`setEasing`/`pinEndpoints` · `KeyframeOps` Document-level route | 🟢 |
| | **Timeline** — per-node→per-property rows, dots dragged (index frozen at drag start), per-segment easing picker (presets→`CubicEasing`), `,`/`.`/Home/End/`K`/`Shift+K` | 🟢 |
| | F4.2 edit-at-keyframe — direct-select routes on `_hasPathTrack` (untracked→rest pose, AC-4.2.3); inspector keyframe diamonds; **path diamond** (`PathOps.keyPose`) authors the first path key | 🟢 |
| | F7.1 easing · F7.2 interpolation (ID-join, bool-step, unbounded rotation, hold-first/last) · F7.3 spatial motion-path tangents — all verified, most shipped in M0/M1 | 🟢 |
| | Playhead hot path holds under the timeline + diamonds — a scrub rebuilds nothing but leaf value-builders (audited) | 🟢 |
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
- **Live drag feedback** (owner: a drag should show the new shape, not just a moving dot) → **shipped, and extended in M3** to the pen (draws the real curve) and shape tools (draw the real outline, not dots).
- **⚠ NEEDS AN OWNER DECISION — no way to delete a node.** `Del`/`Backspace` is unbound and there is no node-delete op anywhere: you can create nodes (pen/shape/duplicate) but cannot remove any. Same shape as the pan/zoom gap — a real capability owned by no milestone (`deleteAnchor` is legitimately M5; *node* deletion is unscheduled). Small (~an afternoon: `DeleteNodeCommand` + `NodeOps.remove` + a key binding). Recorded, not built, awaiting a call on whether to fold it into M4.

**M4 audited (6 lenses) — 1 blocker + 6 findings, all fixed:**
- ~~**BLOCKER: the first path keyframe was unreachable by hand**~~ — the AC-4.2.3 fix removed auto-seed-on-drag but nothing replaced the route to *start* animating a path (the M2-recurrence: op green, no call site). **Fixed** with `PathOps.keyPose` (the stopwatch — snapshots rest/evaluated pose into a key) + an inspector **Path diamond**. Exit criterion now performed by hand in `test/m4_ui_audit_test.dart`.
- ~~stale path `selectedKeyframe` re-seeded a track~~ → route on `_hasPathTrack` alone; `clearKeyframe()` wired on key removal.
- ~~tracked inspector fields showed the static pose but wrote to the keyframe~~ → fields now WYSIWYG (value sampled at playhead via a leaf builder, hot-path-safe).
- ~~tracked stroke-width bypassed the clamp~~ · ~~timeline `.then` lacked `onError`~~ · ~~undo didn't restore `selectedKeyframe`~~ · ~~stale seam labels~~ → all fixed.
- **Two of six lenses returned NO FINDINGS** (the pure-math layer): coincident keys unrepresentable, continuity to 1.9e-9, whole-path keys only (no per-anchor leak — the M5-critical constraint), 50-sample totality clean.

**Deferred / carried:**
- `CommandStack`'s gesture coalescing (`beginGesture`/`commitGesture`) is correct and tested but **has no call site** — one-entry-per-drag comes from a local preview + a single release command (`v3/04 §6` satisfied). Wire only if a gesture must issue *multiple* commands.
- **Easing UI is 8 presets, not `v3/05 §4.4`'s editable cubic curve / draggable handles / "Custom".** Presets satisfy the exit criterion ("a different easing on each segment"); the custom-curve editor is a shortfall vs §4.4, not built. Note: 3 keys make 2 segments, so "different easing on each segment" = 2 distinct easings, not 3.
- **`kPropMeta` table not built** — `docs/v3/08 §2` wants one core table driving every property-label UI; the timeline hand-rolls an exhaustive `PropKey` switch instead (compiler-safe: a new member fails the build loudly). Worth centralising when the next property-labeling UI lands.

**Known limits recorded in M3, needing a decision later:**
- **A clipping group's window is always the artboard's size/aspect.** `GroupNode` has no extent of its own, so `position`/`scale`/`rotation` move and resize the window *and* its children together. A 100×50 window independent of its content needs a new `GroupNode` rect — a field in `anim_core`, the wire format and the decoder. Not invented; recorded.
- **Hit-testing is not clip-aware.** Geometry clipped away is invisible but still clickable and selectable. Making it consistent means intersecting `selectionBounds` with the clip chain, or the pinned property *"the outline you see is the box the hit-test answers for"* breaks for clipping groups.
- **Recipe regeneration is refused on a path-tracked node** (`PathOps.regenerateRecipe` throws, naming M5). AC-4.1.5 routes it through `retopologize`, which `v3/06` schedules at **M5**; a cheap approximation shipped under the real name is a defect M5 would inherit invisibly. Shape-parameter fields must be disabled, with M5 named, on a node that has path keyframes.

Detail: [v3/03_features.md](v3/03_features.md) · [v3/06_roadmap.md](v3/06_roadmap.md) · isolation rules: [v3/08_feature_isolation.md](v3/08_feature_isolation.md)
