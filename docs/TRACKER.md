# v3 Tracker

⚪ not started · 🔵 in progress · 🟡 thin/stubbed · 🟢 done · 🔴 broken

**Now:** ✅ **M8 COMPLETE — export, the legacy importer, and the sample gallery. All 9 of `v3/00` §5's feature criteria are met.** A document exports to versioned `.json` through the one persistence serializer and round-trips exactly (#8); the pure-Dart `anim_core` runtime replays an exported file at 50 sampled `t` from a plain consumer. All 8 legacy samples import to clean v3 documents — sorted-by-position, coincident keys ε-separated, capital-S keys mapped, fresh UUIDs — and join CI Gate 1 as round-trip cases 9–16 (#9); the sample gallery opens any of them as a new project, the bundled asset untouched. Audited by **6 lenses — 5 returned NO FINDINGS** (fidelity, export/round-trip, gallery, purity/replay, isolation); AC-4.3.6 verified on every import; the one real finding — a `_resample` divide-by-zero on a malformed 0-point frame — was fixed with a regression test, plus a widened `_openSample` catch. Gate: anim_core 474 · anim_render 67 · app 247 · 0 skipped · analyze clean · boundaries ok · web build ✓. **The entire v1 feature set (E1–E13) is built, audited, and green.** **Next: M9** — the ship gate: verify all 9 criteria on the deployed URL with a stranger's hands (F12.1 deploy — the one remaining piece is the public URL + email/password sign-up, web build already CI-verified).

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
| | `regenerateRecipe` — replaces an untracked node's path; a path-tracked node was refused at M3, **now routes through `retopologize` (M5)** | 🟢 |
| **M4** | F6.1 Per-node/per-property tracks · F6.2 keyframe ops — `TrackOps.moveKeyframe`/`removeKeyframeAt`/`setEasing`/`pinEndpoints` · `KeyframeOps` Document-level route | 🟢 |
| | **Timeline** — per-node→per-property rows, dots dragged (index frozen at drag start), per-segment easing picker (presets→`CubicEasing`), `,`/`.`/Home/End/`K`/`Shift+K` | 🟢 |
| | F4.2 edit-at-keyframe — direct-select routes on `_hasPathTrack` (untracked→rest pose, AC-4.2.3); inspector keyframe diamonds; **path diamond** (`PathOps.keyPose`) authors the first path key | 🟢 |
| | F7.1 easing · F7.2 interpolation (ID-join, bool-step, unbounded rotation, hold-first/last) · F7.3 spatial motion-path tangents — all verified, most shipped in M0/M1 | 🟢 |
| | Playhead hot path holds under the timeline + diamonds — a scrub rebuilds nothing but leaf value-builders (audited) | 🟢 |
| **M5** ★ | **F4.3 Topology editing** — `PathOps.insertAnchor` (exact de Casteljau, `§13.5` to 1e-12, pixel-identical golden that bites) · `deleteAnchor` · `retopologize` (arc-length correspondence) | 🟢 |
| | Pen hover→`+`→insert (nearest-point `u`-solve) · `Del`/`Backspace`→delete anchor · tracked recipe edit→`retopologize` (square→star rewrites every keyframe) | 🟢 |
| | AC-4.3.6 CI invariant — identical `AnchorId` sequence across every keyframe, a property sweep (8 seeds × 30 random ops × 2 animations) that blocks the build | 🟢 |
| | Audited by 6 lenses — 3 NO-FINDINGS (both math + isolation); degenerate-recipe erasure fixed, `u`-solve self-crossing branch fixed | 🟢 |
| **M6** | **F8.1 `PathTrim`** — real `applyTrim` (stage 7): arc-length window `[start,end]+offset`, revealed tip on the authored cubic to 6.7e-14, `ArcTable` memoized per immutable `PathData` (AC-8.1.7), node-local (AC-8.1.9); partial reveal→`closed:false`, **full-width+offset stays closed** · trim inspector (static↔keyframe routing, WYSIWYG-at-playhead, per-`PathNode`) | 🟢 |
| | **F9.1 Transport** — play/pause/loop/duration/skip; Ticker writes only `playheadProvider.value` → playback rebuilds no panel (Δ0, audited); `normalizedTime` outside the evaluator; `playing` ephemeral, loop/duration persist | 🟢 |
| | **F9.2 Full evaluator** — animated `resolvePaint` (fill/stroke colour · opacity · width by `PaintId`, gradients untouched); all 8 stages compose in order, the 3 no-op seams still `=> frame` | 🟢 |
| | Audited by 6 lenses — **transport + isolation NO-FINDINGS**, applyTrim geometry machine-precision; fixed: full-width+offset closed-loop stayed open (LOW); clamp-to-noop phantom undo/save killed (a no-op edit no longer bumps `rev` — matters for M7 autosave) | 🟢 |
| **M7** | **F10.3 Autosave** — debounced write (one write after edits settle, AC-10.3.1; coalesces a burst); `SaveState` machine + chrome **dirty/saving/saved/error** indicator (leaf, Δ0 repaint); **failed write RETAINS the edit** + error indicator, no modal, recovers on next write (AC-10.3.4); `rev` +1 per persisted save via `_persistedRev` (AC-10.3.5); `AppLifecycleListener` + `onDispose` teardown flush; Firestore `persistenceEnabled` offline queue (AC-10.3.2) | 🟢 |
| | **E13 perf pass** — 114-anchor × 10-keyframe budget fixture; scrub + live-drag both Δ0 rebuilds on canvas/layers/inspector (AC-13.2/13.3/13.4); timeline `RepaintBoundary` (AC-13.1); per-mutation-not-per-tick pinned (AC-13.5) | 🟢 |
| | Audited by 6 lenses — **3 NO-FINDINGS** (rev monotonicity, lifecycle/timer, indicator/ephemeral); fixed: teardown drag-leak + unhandled-error escape in `_disposeFlush`, `_flush` on-Object assert, vacuous AC-13.1 assertion, stale docstring | 🟢 |
| **M8** | **F11.1 Export** — `[Export .json]` downloads `jsonEncode(doc.toJson())` (the ONE serializer, AC-11.1.3), via a conditional-import web helper (VM stub / `package:web` impl); round-trips exactly (AC-11.1.2) · **F11.2** — `anim_core` stays Flutter-free incl. the importer (AC-11.2.1); external replay at 50 t through the public API from `anim_render` (AC-11.2.2); `annimation`-free (AC-11.2.3) | 🟢 |
| | **F11.3 Legacy importer** — `LegacyImporter` (in `ops/`) turns all 8 samples into clean v3 docs: sorted-by-`framePosition` (AC-11.3.4), ε-nudged coincident keys (AC-11.3.3), case-insensitive ARGB, capital-S keys mapped away (AC-11.3.6), arc-length vertex-count repair backstop (AC-11.3.5), fresh UUIDs; the 8 imported docs join CI Gate 1 as round-trip cases 9–16 (no third gate) | 🟢 |
| | **F11.4 Sample gallery** — 8 samples listed to a first-timer; opening one imports → **new project** under the user's namespace (fresh UUID, bundled asset unmodified, AC-11.4.2) and plays in-app | 🟢 |
| | Audited by 6 lenses — **5 NO-FINDINGS** (fidelity, export/round-trip, gallery, purity/replay, isolation); AC-4.3.6 verified on all 8 imports; fixed: a `_resample` divide-by-zero on a malformed 0-point frame (MEDIUM), and widened `_openSample`'s catch | 🟢 |
| **M9** | Ship gate — all 9 of `v3/00` §5 on the URL | 🟡 |
| | **Pre-flight verified 🟢** — email/password sign-up/sign-in wired, only provider (AC-12.1.2); Firestore rules uid-scope `appData/v3/users/{uid}` server-side (AC-10.0.6); web-only (`android/` gitignored, AC-12.1.5); `firebase.json` hosting ready (`build/web`, SPA rewrites, cache headers); **both release gates green and block `Build web`** (AC-12.1.4). Remaining = operational (owner): `firebase deploy` (hosting + `--only firestore:rules`), enable Email/Password in the Firebase console, then verify all 9 §5 criteria on the URL with a stranger (AC-12.1.1/12.1.3). | 🟡 |
| 🚧 | **V1 SHIP GATE — nothing below starts before this** | |
| M10-14 | Go service · Postgres · `BACKEND=api` · `rev` concurrency · history | ⚪ |

★ = the load-bearing feature. Best stopping points if this pauses: **M5** (irreplaceable work done) or **M9** (v1).

**Owner notes** — direct product feedback, carried between milestones. Not scheduled scope; recorded so it is not lost.
- **Editor exposes very few operations.** Owner flagged this on first use. Breadth is real, scheduled work arriving across M2–M6 — **now all shipped:** select · move · group · duplicate · reorder · nest · rename · hide/lock · opacity · undo/redo · pan/zoom (M2), drawing depth (M3), keyframe editing (M4), topology editing (M5), trim + play/transport (M6).
- ~~**No board pan/zoom — roadmap gap**~~ **RESOLVED in M2.** It was specified (`v3/01 §12`, `v3/04 §5`) but scheduled by no milestone. Owner approved folding it in; now built, recorded as **ADR-018**, and added to `v3/06` M2's contents and exit criterion.
- **Owner-requested capabilities, so their landing is visible:** select a whole object and move it → **shipped, M2**. Play/transport → **shipped, M6** (F9.1 — play/pause/loop/duration/skip, Enter toggles).
- **Live drag feedback** (owner: a drag should show the new shape, not just a moving dot) → **shipped, and extended in M3** to the pen (draws the real curve) and shape tools (draw the real outline, not dots).
- **Three usability gaps closed on owner feedback (post-M8), all audited and tested:**
  - ~~**"I did not understand how to add an animation keyframe."**~~ The ◇ stopwatch is an After Effects convention and nothing on screen said so — the discoverability half of `v3/00` §5's ship gate, in the place it cost the most. **Shipped:** `features/guide/` — an eight-chapter **how-to guide** (layout · draw · reshape · **your first keyframe** · timeline · colour & draw-on · play/save/export · shortcuts) with a diamond-state legend, opened by the app-bar `?`, by `F1`, and **once** on a first visit. It is a leaf feature: no provider, no command, no document — so it cannot desync from the editor or break a panel, at the cost of the prose being a copy of the bindings rather than a projection of them.
  - ~~**Timeline stuck at 84 px — only two rows visible.**~~ **Shipped:** a drag handle on its top edge, `84 … 420 px`, double-click to reset, remembered per browser. The ceiling is derived from `EditorShell.workspaceFloor`, not guessed: the tool rail is a `Column` of six fixed 52-px buttons with nowhere to scroll, so it — not the canvas — is what a too-tall timeline breaks first, and it breaks with a layout assertion.
  - ~~**Inspector values were keyboard-only.**~~ **Shipped:** ▲▼ steppers on every numeric row (`Shift` ×10, `Alt` ÷10, `↑`/`↓` on the focused field, press-and-hold to repeat with acceleration). Each field's increment is set at its call site in its own display unit; `min`/`max` stop the stepper where the op's clamp already is.
  - **Follow-up on the same feedback — "adding a keyframe is still not clear, and neither is setting a different value at another frame":** the guide alone did not close it, so the product says it now. The inspector carries a **live strip** under the layer name — `Not animated. Click a ◇ to key that property at the playhead.` before, `● Editing at 0.50 s / Move the playhead, then change a value — it becomes a keyframe at that time.` after — the diamonds grew **tooltips** naming all three of their actions (including that a filled one *deletes*), and the first key on any property earns **one sentence of coaching** at the only moment it is actionable. The guide's keyframe chapter gained a diagram of what two keys on one row *are*, and a worked example with real numbers.
  - **The playhead was a 1-px line with no affordance.** It now has a **grab handle carrying the current time**, and the ruler grew from 18 px to a 32-px scale with second labels and ticks — so "which moment am I on" is answered where the pointer already is, and the drag target is nearly twice as tall. The timeline's default height rose to 120 px to keep three rows visible under the taller ruler.
  - ~~**A drag on an animated layer was REFUSED**~~ — "this layer's transform is animated — move it by keyframing it, not by dragging" — while the *same value* stayed editable by typing in the inspector, which keys at the playhead. Owner hit it immediately, and they were right: dragging is the gesture everyone reaches for first. **Fixed**: the Select tool now forks on the one predicate the inspector already uses — position tracked → one `KeyframeAtCommand` at the playhead (the key under it is edited, or a new one is inserted where there was none), position untracked → the static pose exactly as before. The drag starts from the **sampled** position so the shape does not jump to the rest pose, and the live preview applies the same op the release commits. A second bug fell out with it: the old guard refused the drag when *any* of position/scale/rotation/skew was tracked, but the evaluator composes per channel — a rotation-animated node's static position edit is perfectly visible, and that move was being refused for nothing. Three canvas tests pin the new routing.
  - **The editor's messages were stock `SnackBar`s** — full-bleed black bars that read as another application's UI, parked over the timeline with no way out but waiting. There is now one themed toast (`common/editor_toast.dart`): panel colours, an icon, capped at 560 px and centred, **dismissible by an ✕ or a swipe either way**, and in the accent (not the error) colours when it follows a *successful* action. It floats above the timeline's live height — the shell publishes that footprint, because a tip saying "move the playhead" that covers the playhead is worse than no tip. Every reporter in the editor routes through it; a test pins that the ruler still takes a drag with a toast on screen.
  - Persistence for the two before rides on one new seam, `common/ui_prefs.dart` + `data/prefs_ui_prefs.dart`, injected in `main.dart` exactly as `ThemeStore` is. Its in-memory default reports the guide as **already seen**, so no widget test is handed a modal it did not ask for.
- **⚠ NEEDS AN OWNER DECISION — no way to delete a node.** `Del`/`Backspace` is unbound and there is no node-delete op anywhere: you can create nodes (pen/shape/duplicate) but cannot remove any. Same shape as the pan/zoom gap — a real capability owned by no milestone (`deleteAnchor` is legitimately M5; *node* deletion is unscheduled). Small (~an afternoon: `DeleteNodeCommand` + `NodeOps.remove` + a key binding). Recorded, not built, awaiting a call on whether to fold it into M4.

**M4 audited (6 lenses) — 1 blocker + 6 findings, all fixed:**
- ~~**BLOCKER: the first path keyframe was unreachable by hand**~~ — the AC-4.2.3 fix removed auto-seed-on-drag but nothing replaced the route to *start* animating a path (the M2-recurrence: op green, no call site). **Fixed** with `PathOps.keyPose` (the stopwatch — snapshots rest/evaluated pose into a key) + an inspector **Path diamond**. Exit criterion now performed by hand in `test/m4_ui_audit_test.dart`.
- ~~stale path `selectedKeyframe` re-seeded a track~~ → route on `_hasPathTrack` alone; `clearKeyframe()` wired on key removal.
- ~~tracked inspector fields showed the static pose but wrote to the keyframe~~ → fields now WYSIWYG (value sampled at playhead via a leaf builder, hot-path-safe).
- ~~tracked stroke-width bypassed the clamp~~ · ~~timeline `.then` lacked `onError`~~ · ~~undo didn't restore `selectedKeyframe`~~ · ~~stale seam labels~~ → all fixed.
- **Two of six lenses returned NO FINDINGS** (the pure-math layer): coincident keys unrepresentable, continuity to 1.9e-9, whole-path keys only (no per-anchor leak — the M5-critical constraint), 50-sample totality clean.

**Deferred / carried:**
- ~~`CommandStack`'s gesture coalescing (`beginGesture`/`commitGesture`) is correct and tested but **has no call site**~~ **Now wired**, by the case that note predicted: the inspector's press-and-hold steppers are a gesture that *does* issue multiple commands (one per ~70 ms repeat), so a hold opens a span through `InspectorCommands.beginStep`/`endStep` and undoes as one entry and one save. Canvas drags still coalesce the other way — local preview, one release command — and neither route changed.
- **Easing UI is 8 presets, not `v3/05 §4.4`'s editable cubic curve / draggable handles / "Custom".** Presets satisfy the exit criterion ("a different easing on each segment"); the custom-curve editor is a shortfall vs §4.4, not built. Note: 3 keys make 2 segments, so "different easing on each segment" = 2 distinct easings, not 3.
- **`kPropMeta` table not built** — `docs/v3/08 §2` wants one core table driving every property-label UI; the timeline hand-rolls an exhaustive `PropKey` switch instead (compiler-safe: a new member fails the build loudly). Worth centralising when the next property-labeling UI lands.

**Known limits recorded in M3, needing a decision later:**
- **A clipping group's window is always the artboard's size/aspect.** `GroupNode` has no extent of its own, so `position`/`scale`/`rotation` move and resize the window *and* its children together. A 100×50 window independent of its content needs a new `GroupNode` rect — a field in `anim_core`, the wire format and the decoder. Not invented; recorded.
- **Hit-testing is not clip-aware.** Geometry clipped away is invisible but still clickable and selectable. Making it consistent means intersecting `selectionBounds` with the clip chain, or the pinned property *"the outline you see is the box the hit-test answers for"* breaks for clipping groups.
- **Recipe regeneration is refused on a path-tracked node** (`PathOps.regenerateRecipe` throws, naming M5). AC-4.1.5 routes it through `retopologize`, which `v3/06` schedules at **M5**; a cheap approximation shipped under the real name is a defect M5 would inherit invisibly. Shape-parameter fields must be disabled, with M5 named, on a node that has path keyframes.

Detail: [v3/03_features.md](v3/03_features.md) · [v3/06_roadmap.md](v3/06_roadmap.md) · isolation rules: [v3/08_feature_isolation.md](v3/08_feature_isolation.md)
