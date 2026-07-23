# 05 — UX Flows

**What this doc is:** the behavioural contract for the editor UI — screens, panels, tools, interaction flows, shortcuts, and status states. Every interaction names the [01](01_domain_model.md) mutation it issues.
**What it is not:** visual design. No colours, spacing, typography, iconography, or component library. No widget code — that is doc 04.

---

## 1. Screen inventory

Three screens. That is the whole app.

| # | Screen | Route | Contents |
| --- | --- | --- | --- |
| 0 | **Auth** | `/signin` | One form, two modes toggled by a link: **sign in** and **sign up**. Fields: email, password. Nothing else. Shown only when no session exists; a live session redirects straight to `/`. |
| 1 | **Project list** | `/` | Auth gate → `ProjectStore.list()` → cards (name, modified, thumbnail-less). Actions: new, open, rename, delete, import legacy `.json`, open bundled sample, **sign out**. |
| 2 | **Editor** | `/p/{projectId}` | Everything else. One `Document`, one artboard. |

**Auth is email + password only** — no social providers, no anonymous auth, no forgot-password, no email verification ([00 §4](00_vision_and_scope.md)). Error states the form must render: invalid email, weak password (Firebase minimum is 6 characters), email already in use, wrong password, user not found, network failure. **A forgotten password is unrecoverable in v1** — that is the accepted cost of cutting the reset flow, and the form should not offer a link that implies otherwise.

**Sign-out confirms.** The icon opens a two-choice alert dialog (*Cancel* / *Sign out*) and only ends the session on explicit confirmation; dismissing it counts as Cancel. It is the one modal in the signed-in chrome — auth *errors* stay inline (AC-10.0.4). The copy names only what is true: the session ends and a login is needed to return. It must not warn about unsaved work until autosave exists to have work in flight (00 §3 item 18).

**Theme is a toggle, not a screen.** One app-bar icon flips light ↔ dark, dark is the default, and the choice is remembered across reloads. Two states only — `ThemeMode.system` is never offered, because "straight light/dark" is the requirement (00 §3 item 19). This is deliberately *not* the beginning of a preferences surface: the moment a second preference wants a home, it goes in the inspector, not in a new screen.

**Decision: no settings screen, no dashboard, no gallery.** Artboard size and `durationSeconds` are edited in the inspector when nothing is selected. A fourth screen is scope that buys nothing testable in [00 §5](00_vision_and_scope.md).

---

## 2. Editor layout

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ CHROME  ‹back   project name          ● Saved 2s ago        [Export .json]    │
├───┬──────────────────┬────────────────────────────────────┬──────────────────┤
│ T │ LAYERS           │  CANVAS  (pan / zoom viewport)      │ INSPECTOR        │
│ O │  ▾ group "gear"  │   ┌──────────────────────────────┐  │  Transform2      │
│ O │     ● path "cog" │   │  ARTBOARD  450.2 × 250.4     │  │  Fill / Stroke   │
│ L │     ● path "pin" │   │                              │  │  PathTrim        │
│ B │  ● path "arc"    │   │      ◇──── selected path ────│  │  Easing (segment)│
│ A │    👁 🔒 ⠿ reorder│   │                              │  │  Anchor kind     │
│ R │                  │   └──────────────────────────────┘  │                  │
├───┴──────────────────┴────────────────────────────────────┴──────────────────┤
│ TRANSPORT  ⏮ ▶ ⏭   loop: once│loop│pingPong    0.42 s / 1.00 s    t = 0.420   │
│ TIMELINE                                                                      │
│  0 ─────────────────────────────┃─────────────────────────────────────── 1    │
│  ▾ cog     path      ◆      ◆        ◆                                        │
│            opacity   ◆                        ◆                               │
│  ▾ arc     trimEnd   ◆           ◆                                            │
│            rotation         ◆  ◆                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Panel contracts

| Panel | Owns | Never owns |
| --- | --- | --- |
| **Canvas** | Rendering the evaluated frame at `EditorState.playhead`; hit-testing; direct manipulation | Any model mutation performed during paint or `build()` |
| **Layers** | Tree, z-order (= child-list order), rename, visibility, lock | Keyframes |
| **Toolbar** | Active tool; modal, one at a time | Selection |
| **Inspector** | Numeric/typed editing of the *selected keyframe's* values, plus non-animatable structure | Timing |
| **Transport** | `playing`, `LoopMode`, seconds ↔ `t` display conversion | Storing time in pixels |
| **Timeline** | Per-node, per-property rows; keyframe dots; segment easing; playhead drag | The document (playhead lives in `EditorState`) |

### Three legacy behaviours carried forward ([00 §7](00_vision_and_scope.md))

| Kept | Contract in v3 |
| --- | --- |
| **Edit-at-keyframe, not record mode** | Clicking a keyframe dot sets `EditorState.selectedKeyframe = (NodeId, PropertyKey, int)`, snaps the playhead to that key's `t`, and routes every subsequent canvas edit to that key via `atT`. There is no arm/record toggle and no accidental keyframe creation. |
| **Live scrub preview** | Interpolated geometry renders *during* the playhead drag, not only on play. The evaluator runs per frame at the dragged `t`. |
| **Per-object independent timelines** | Every node×property is its own row with its own key positions. No global keyframe grid, no column alignment, no "current section" cache — every node evaluates every tick. |

**Timeline row expansion:** a node collapses to a single summary row (union of its keys, read-only) and expands to one row per `PropertyKey`. Editing is only ever possible on an expanded property row.

---

## 3. Tools

Modal. Exactly one active. Tool never changes selection semantics of another tool.

| Tool | Key | Behaviour | Modifiers | Mutates via |
| --- | --- | --- | --- | --- |
| **Select** | `V` | Click node → select; drag → move; marquee → multi-select; handles → scale/rotate about pivot | `Shift` add to selection · `Shift`+drag axis-lock · `Alt`+drag duplicate-and-move (`NodeOps.duplicateSubtree` then move) | `Transform2` write → `TrackOps.upsertKeyframe` on `position` / `scale` / `rotation` if the node has that track, else the node's static transform |
| **Direct select** | `A` | Click anchor or handle → select; drag → move it; `Del` removes the anchor | `Shift` add to selection · `Shift`+drag axis-lock · `Alt`+drag handle **breaks symmetry** (sets `AnchorKind.corner`) · `Alt`+click anchor cycles `AnchorKind` | `PathOps.moveAnchor`, `PathOps.setTangents` (**pose, keyframe-local**) · `PathOps.deleteAnchor` (**topology, document-wide**) |
| **Pen** | `P` | Click → corner anchor; click-drag → smooth anchor with symmetric tangents; click the first anchor → close and exit; `Esc`/`Enter` → leave open and exit. On an existing selected path: hover a segment → `+` cursor, click inserts at parameter `u`; hover an endpoint → continue the path | `Alt` while dragging a new anchor breaks the outgoing tangent · `Shift` constrains the new anchor to 45° from the previous | While drawing: builds one `PathData` and commits a whole `PathNode` on exit. On an existing tracked path: **`PathOps.insertAnchor(d, n, after:, u:)`** |
| **Shape** | `R` rect · `O` ellipse · `G` polygon | Drag on canvas → bounding box; on release the `ShapeRecipe` generates the `PathData`. Editing recipe params in the inspector regenerates | `Shift` constrain square/circle/regular · `Alt` draw from centre | New node: constructs `RectRecipe` / `EllipseRecipe` / `PolygonRecipe`. Regeneration on a node that already has a `path` track goes through **`PathOps.retopologize`** — never a raw path replacement. Any direct-select edit **nulls the recipe** |
| **Pan** | hold `Space`, or middle-drag | Translates `EditorState.viewportTransform` | — | Nothing. Ephemeral only. |
| **Zoom** | `Cmd/Ctrl` + scroll, `Cmd +` / `Cmd -` | Scales `viewportTransform` about the cursor | — | Nothing. Ephemeral only. |

**Two rules the toolbar enforces structurally:**

1. **The pen tool cannot replace a node's `PathData`.** Insert is the only topology op it can reach, and it reaches it only through `PathOps`. This is what makes rule 2 of [00 §8](00_vision_and_scope.md) unbreakable from the UI.
2. **Nothing mutates during `build()` or `paint()`.** Interaction handlers emit a command; the command returns a new `Document`. Legacy edited the document from inside `itemBuilder`.

---

## 4. Core interaction flows

### 4.1 Draw a closed bezier path

| # | User | System |
| --- | --- | --- |
| 1 | `P`, click on artboard | New `PathNode`, 1 anchor, `closed: false`. **Renders nothing** (path invariant P2) — no error |
| 2 | Click-drag elsewhere | 2nd anchor, `AnchorKind.symmetric`, tangents from the drag vector |
| 3 | …repeat | Preview stroke follows the cursor from the last anchor |
| 4 | Click the first anchor | `closed: true`, tool exits to Select, node selected and named `Path N` |

No track exists yet. The node is fully static and legal.

### 4.2 Insert an anchor mid-animation — **the headline flow**

Preconditions: `cog` has a `path` track with keyframes at `t = 0.0 / 0.5 / 1.0`.

| # | User | System |
| --- | --- | --- |
| 1 | Click the keyframe dot at `t = 0.0` | `selectedKeyframe` set; playhead snaps to `0.0`; canvas shows that keyframe exactly |
| 2 | `P`, hover a segment | Segment highlights; the hit gives parameter `u` on that cubic |
| 3 | Click | **One** `PathOps.insertAnchor` command → **one** undo entry |
| 4 | — | Mints **one** `AnchorId`; inserts it into `PathNode.path` at the correct draw position; writes an `AnchorPose` into **every keyframe of every path track for that node, across every `Animation`** — each computed by de Casteljau splitting *that keyframe's own* cubic at the same `u` |
| 5 | Scrub 0→1 | **Keyframes 0.5 and 1.0 are pixel-identical to before the insert.** The split is exact, so the added anchor lies on the existing curve at every key |

**What the user sees:** the new dot appears on the curve at *every* keyframe when they visit it. Nothing moved. This is [00 §5](00_vision_and_scope.md) criterion 3 and the reason the rewrite exists.

**What the UI must never offer:** an "insert on this keyframe only" option. Anchor sets are not per-keyframe state; it is not a representable document.

### 4.3 Set a keyframe

| # | User | System |
| --- | --- | --- |
| 1 | Select node, drag playhead to `t` | Live preview |
| 2 | Edit on canvas or in the inspector | If the property has **no track**: create the track and write a key at `t`. If it **has** a track and `t` sits on an existing key: replace that key's value. If it has a track and `t` is between keys: **insert a new key at `t`** |
| 3 | — | `TrackOps.upsertKeyframe(track, t, value, easing)`. Coincident keys are impossible by construction (`minSeparation = 1e-4`) |
| 4 | Or press `K` on a selected property row | Writes a key at the playhead with the currently evaluated value — a no-visual-change key, used to hold a value before an upcoming change |

**Drag a keyframe dot** → `TrackOps.moveKeyframe(track, index, newT)`. The index is resolved when the drag *starts*, never re-derived from the float during the drag. A drop within `minSeparation` of a neighbour is **rejected and the dot springs back** — no silent merge, no divide-by-zero.

**`TrackOps.pinEndpoints`** is a context-menu affordance on a track row ("pin first key to 0, last to 1"), not an automatic behaviour. Hold-first / hold-last already makes it unnecessary for correctness.

### 4.4 Edit easing on a segment

Easing belongs to the key it **leaves** (outgoing). The UI addresses segments, not key pairs.

| # | User | System |
| --- | --- | --- |
| 1 | Click the span *between* two dots | Selects segment `i` = the left key's index |
| 2 | Inspector shows preset chips + an editable cubic curve | `LinearEasing` · `HoldEasing` · `ease` · `easeIn` · `easeOut` · `easeInOut` · `backIn` · `backOut` · Custom |
| 3 | Pick a preset or drag the curve handles | `TrackOps.setEasing(track, i, e)` |
| 4 | — | Presets persist as their four numbers. A preset dragged into a custom curve is **not a type change** — no mode switch, no data loss |

**Hold is a preset in the same list, not a separate "interpolation type" dropdown.** Constraint surfaced in the UI: `x1`/`x2` clamp to `0..1` (time must stay monotonic); `y1`/`y2` are unclamped so overshoot and anticipation are draggable.

### 4.5 Reorder layers

| # | User | System |
| --- | --- | --- |
| 1 | Drag a row in the Layers tree | Drop indicator shows target parent + index |
| 2 | Drop within the same parent | Reorder child list. **Z-order is child-list order** — no separate z-index |
| 3 | Drop into a different group | `NodeOps.reparent(d, n, newParent, index)` — world-preserving: `newLocal = newParent.world.invert() · oldWorld`, then `Affine.decompose`. **The node does not visually move** |
| 4 | `Cmd/Ctrl+G` on a multi-selection | `NodeOps.createGroup` — pivot is set to the union-AABB centre of the members at group time |

Locked rows reject selection and drag. Hidden rows still reorder.

### 4.6 Scrub

| # | User | System |
| --- | --- | --- |
| 1 | Drag the playhead | Pixels → `t` **inside the timeline widget only**. `EditorState.playhead` is a unitless normalized double |
| 2 | — | One `t` evaluates every node's independent tracks in one pass through the 8-stage pipeline ([01 §11](01_domain_model.md)) |
| 3 | Past the first / last key | Hold-first / hold-last. The shape is **present and correct at `t = 1.0`** — legacy's vanishing shape is gone |
| 4 | Release | Nothing is written. Scrubbing is never a mutation |

Readout shows **seconds** (`t × durationSeconds`); the document stores the fraction. The user never types a normalized number.

### 4.7 Play / loop

| Control | Behaviour |
| --- | --- |
| Play/pause | Ticker drives `elapsedSeconds` → `normalizedTime(animation, elapsed)` → `playhead`. Playback is a read; it writes nothing |
| Loop mode | `LoopMode.once` (clamps and stops at 1) · `loop` (wraps) · `pingPong` (0→1→0) |
| Scrub while playing | Pauses, then scrubs. No fighting the ticker |
| Editing while playing | Blocked. The tool cursor is disabled on the canvas during playback — edit-at-keyframe requires a stationary, selected key |

### 4.8 Trim draw-on reveal

| # | User | System |
| --- | --- | --- |
| 1 | Select a stroked path; expand `trimEnd` in the timeline | Row appears |
| 2 | Playhead `0.0`, set `trimEnd = 0.0` | `end <= start` → **renders nothing**. Empty geometry, never a throw |
| 3 | Playhead `0.6`, set `trimEnd = 1.0` | Stroke draws on between 0.0 and 0.6 |
| 4 | Add `opacity` keys at 0.7 → 1.0 | Fades out after the draw-on. [00 §5](00_vision_and_scope.md) criterion 5 |
| 5 | `trimOffset` | Rotates the reveal start point around a closed path |

**Surfaced in the UI:** trimming a `closed: true` path emits an open path — the fill disappears while the window is partial. Shown as an inspector note on the trim group, so it reads as designed behaviour rather than a bug. Trim is measured in **node-local** space, so scaling the node does not change the revealed fraction.

### 4.9 Save + dirty/saved indicator

| # | Trigger | System |
| --- | --- | --- |
| 1 | Any command returns a new `Document` | State → `dirty`, debounce timer (re)armed |
| 2 | Debounce elapses | `rev++`, `ProjectStore.save(id, jsonEncode(doc.toJson()))` — **String in, String out**. State → `saving` |
| 3 | Ack | State → `saved` |
| 4 | Offline | `enablePersistence()` queues the write locally; the indicator stays `saving` (honest) and flushes on reconnect |

There is no Save button. `Cmd/Ctrl+S` forces an immediate flush of the pending debounce — it exists because users press it reflexively, not because it is required.

### 4.10 Export

| # | User | System |
| --- | --- | --- |
| 1 | `Export .json` | Flush any pending save first, then `jsonEncode(doc.toJson())` → browser download `{name}.json` |
| 2 | — | **The same serializer as persistence.** One contract, never a parallel path |
| 3 | In their own app | Replay via the new **`anim_core`** runtime package. The old pub.dev `annimation` v0.0.2 cannot read a v3 document and is not offered as a fallback |

No export dialog, no options, no format picker. SVG/Lottie are v2.

---

## 5. Keyboard shortcuts

Figma/Illustrator/After Effects convention, so the tool is learnable without documentation.

### Tools & selection

| Key | Action |
| --- | --- |
| `V` | Select |
| `A` | Direct select (anchors/handles) |
| `P` | Pen |
| `R` / `O` / `G` | Rectangle / Ellipse / Polygon |
| `Esc` | Deselect, or exit the in-progress pen path (leaving it open) |
| `Enter` | **Finish** the in-progress pen path, leaving it **open** — same as `Esc`. It does **not** close the path; closing is clicking the first anchor (§3). Only reaches the pen while the canvas has focus — see the transport table below, where `Enter` is play/pause with the canvas unfocused |
| `Cmd/Ctrl+A` | Select all nodes (Select tool) / all anchors of the selected path (Direct select) |
| `Del` / `Backspace` | Delete selected nodes, or `PathOps.deleteAnchor` on selected anchors |

### Edit

| Key | Action |
| --- | --- |
| `Cmd/Ctrl+Z` / `Cmd/Ctrl+Shift+Z` | Undo / redo — **one command = one entry**, including a document-wide `insertAnchor` |
| `Cmd/Ctrl+D` | Duplicate (`NodeOps.duplicateSubtree` — re-mints every `NodeId` and `AnchorId` and deep-copies the tracks) |
| `Cmd/Ctrl+G` / `Cmd/Ctrl+Shift+G` | Group / ungroup |
| `Cmd/Ctrl+]` / `Cmd/Ctrl+[` | Bring forward / send backward (child-list index) |
| `Arrows` / `Shift+Arrows` | Nudge 1 / 10 artboard units |
| `Cmd/Ctrl+S` | Force-flush the pending autosave |

### View

| Key | Action |
| --- | --- |
| `Space` (hold) | Pan |
| `Cmd/Ctrl` + scroll | Zoom at cursor |
| `Cmd/Ctrl +` / `Cmd/Ctrl -` | Zoom in / out |
| `Cmd/Ctrl+0` | Fit artboard |
| `Cmd/Ctrl+1` | Zoom 100 % |

### Timeline & transport

| Key | Action |
| --- | --- |
| `Enter` (canvas unfocused / transport focused) | Play / pause |
| `,` / `.` | Previous / next keyframe on the selected property row |
| `Home` / `End` | Playhead to `t = 0` / `t = 1` |
| `K` | Key the selected property at the playhead with its evaluated value |
| `Shift+K` | Delete the keyframe under the playhead |

**Decision: `Space` is pan, not play.** After Effects uses `Space` for play; Figma and Illustrator use it for pan. This is a drawing tool where the pointer lives on the canvas, so pan wins, and `Enter` takes play/pause. Stated because the conflict is real and picking silently would produce a tool that feels wrong to users of either convention.

**Decision: `Enter` is resolved by focus, and finishing a path never closes it.** `Enter` appears three times in this document — finish the pen path (§3), "close the in-progress pen path" (Edit table), and play/pause (above) — and the middle one was simply wrong. It is now stated once, in §3's terms: **`Esc` and `Enter` both finish the path and leave it open; only clicking the first anchor closes it.** Two keys for one action is deliberate (either reflex works, and neither destroys the shape), whereas a key that silently *closes* a path is destructive and unguessable — the user has to undo to find out what it did. Focus disambiguates the third: with the canvas focused the pen owns `Enter`, otherwise the transport does. Recorded because M3's implementation had to pick, and a contradiction left in the spec is one an implementer "fixes" back later.

### Flutter Web browser conflicts — real ones only

| Combo | Reality | Handling |
| --- | --- | --- |
| `Cmd/Ctrl+S`, `Cmd/Ctrl+P`, `Cmd/Ctrl+O`, `Cmd/Ctrl+D`, `Cmd/Ctrl+F` | Interceptable | Consumed by the editor's focus scope; browser default suppressed |
| `Cmd/Ctrl+W`, `Cmd/Ctrl+T`, `Cmd/Ctrl+N`, `Cmd+Q`, `Ctrl+Shift+T`, `Ctrl+Tab` | **Not interceptable** in Chrome/Safari | Never bound. No editor action may live on them |
| `Cmd/Ctrl+Z` | Interceptable, but hits the browser's *text field* undo when a DOM input has focus | The inspector's numeric fields explicitly release focus on commit |
| Keyboard focus lost to browser chrome | CanvasKit needs a focused `FocusNode`; without it every shortcut silently dies | Clicking anywhere in the editor restores focus. The focus node is re-requested on window focus |
| Browser back / `Cmd+[` | `Cmd+[` is back-navigation in Safari | Bound anyway; suppressed via the focus scope, and the app uses a router so a stray back is recoverable |

---

## 6. Dirty / saved indicator

One chip in the chrome. Five states, one meaning each.

| State | Trigger | User sees | Interaction |
| --- | --- | --- | --- |
| `clean` | Loaded, nothing edited | `Saved` (muted) | — |
| `dirty` | A command mutated the document; debounce running | `Unsaved changes` | `Cmd/Ctrl+S` flushes now |
| `saving` | `ProjectStore.save` in flight, or queued offline | `Saving…` (spinner) | Blocks navigation away with a browser `beforeunload` prompt |
| `saved` | Write acknowledged | `Saved · 2s ago`, decaying to `Saved` | — |
| `conflict` | **v1.1 only** — server rejected the write on `rev` mismatch | `This project changed in another tab` + `Reload` / `Overwrite` | Modal, never auto-resolved |

| Rule | Reason |
| --- | --- |
| The indicator never lies about being saved | The failure mode of an autosave drawing tool is silently losing artwork. It is the only real data risk in v1 |
| Offline shows `Saving…`, not `Saved` | `enablePersistence()` queued it locally; it is not on the server yet |
| `conflict` is **unreachable in v1** | `rev` is written and round-tripped but not enforced. v1 is last-write-wins, single user. The state is built now so v1.1 turns it on without new UI |

---

## 7. Empty, loading, error states

| Surface | State | User sees |
| --- | --- | --- |
| Project list | Loading | Skeleton rows |
| Project list | Empty | `No projects yet` + `New project` + `Open a sample` (the 8 imported legacy fixtures) |
| Project list | Load failed | `Couldn't reach your projects` + `Retry`. Never an empty list masquerading as "you have none" |
| Editor | Loading document | Blocking spinner over the layout. The canvas never paints a partial document |
| Editor | Decode failed (missing required subtree) | Full-screen error with **the JSON path that failed**. Read-only. No "open anyway" — the strict decoder refuses to manufacture plausible-but-wrong data |
| Editor | `schemaVersion` newer than 3 | Opens **read-only** with a banner. Editing would drop the forward keys it is preserving |
| Editor | Empty document | Artboard outline, empty layers panel, pen tool preselected |
| Editor | Node with 0 or 1 anchor | Renders nothing. **No error.** The pen tool produces this on the first click |
| Editor | Save failed (network) | Chip → `Saving…`; after the offline queue also fails, a non-modal toast `Changes are saved on this device only` |
| Editor | **Save conflict (v1.1)** | Modal: `Someone else — probably another tab — saved this project after you opened it.` Two buttons: `Reload theirs` (discards local edits, confirms first) / `Overwrite with mine` (re-saves at the server's `rev`). No merge. Not a CRDT |
| Import | Legacy file rejected | Names the file and the failing field. Import is one-way; the source file is never modified |

**No modal error dialog is ever raised from inside the animation tick.** Validation happens at load and at mutation. Legacy raised dialogs from the frame callback.

---

## 8. Out of scope for v1 UX

Consistent with [00 §4](00_vision_and_scope.md). If it is not above, it is not in v1.

| Not in v1 UX | Note |
| --- | --- |
| Gradient picker / stop editor | `LinearGradientPaint` / `RadialGradientPaint` exist in the type; the UI exposes solid only. **One of the two most likely scope leaks** |
| Per-anchor keyframing UI | Whole-path keys only. **The other likely leak** |
| Multi-artboard, artboard tabs | One artboard per document |
| Text tool, image import | Vector paths only |
| Boolean path ops UI | No demo needs it |
| Bone/rig tools, IK handles | `solveConstraints` / `deform` are no-ops in v1 |
| State-machine graph editor | `animations` is a List; there is no second-animation UI in v1 |
| Component/instance panel | Seam pre-paid via `ScenePath`; no UI |
| Video / GIF / MP4 export UI | JSON export is the contract |
| Presence, comments, cursors | Not a CRDT |
| Absolute-duration keyframe entry (timecode fields) | The timeline displays seconds and writes `t = seconds / durationSeconds` |
| Graph editor (value curves across a whole track) | Per-segment easing only |
| Dash / dash-offset controls | Trim is the correct primitive |
| Multiple fills or strokes per node | Wire format is a list; the UI caps at one |
| Mobile / touch layout | Flutter Web desktop only. One target, one test matrix |

**Also explicitly out: UI memory-leak hunting and allocation optimization.** The perf budget ([00 §6](00_vision_and_scope.md)) is 114 anchors × 10 keyframes; immutability and allocation churn are free at that scale. The narrow perf work that *is* in v1 — `RepaintBoundary` placement, repaint scoping, and no rebuild storms during scrub or drag — belongs to doc 04, not here.

---

## Cross-links

- [00_vision_and_scope.md](00_vision_and_scope.md) — v1 scope contract, non-goals, success criteria.
- [01_domain_model.md](01_domain_model.md) — **authoritative.** Types, invariants, `PathOps` / `TrackOps` / `NodeOps`, `EditorState`, the 8-stage evaluator pipeline.
- [02_file_format.md](02_file_format.md) — wire contract, `rev`, Firestore layout, export.
