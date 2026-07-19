# v3 — Vision & Scope

**What this doc is:** the commitment contract for v3. It fixes what v1 contains, what it does not, and what "done" means. It is the document you re-read when you are tempted to build something extra.
**What it is not:** a design doc. No types, no schema, no algorithms — those live in [01_domain_model.md](01_domain_model.md) and [02_file_format.md](02_file_format.md).

---

## 1. What the app is

A browser-based vector animation editor for **animated icons and micro-interactions**. You draw bezier shapes on an artboard, set keyframes on their properties, scrub a timeline, and export a JSON file that any Flutter app can replay via **`anim_core`** — a **new** pure-Dart runtime package (model + serializer + evaluator, zero Flutter imports) published from this repo.

> **Clean break.** The old pub.dev package `annimation` v0.0.2 is built on the legacy structure. It is **not a dependency, not a compatibility target, not a migration path** — it reads the legacy format and cannot read a v3 document. That is why v3 ships a new package rather than a version bump.

**Who it is for:** Flutter developers who need an animated icon and do not want After Effects + Lottie in their toolchain. Secondary: the owner, who needs to ship something.

**What it is not:** not a general illustration tool, not a motion-graphics suite, not a game rig editor.

---

## 2. The core loop

```
draw  →  keyframe  →  scrub  →  save  →  export
```

| Step | User action | System |
| --- | --- | --- |
| **draw** | Pen tool or shape tool on the artboard | Creates a `PathNode` with stable-ID anchors |
| **keyframe** | Scrub to a time, edit the shape/transform on canvas | Writes a keyframe at the playhead on that property's track |
| **scrub** | Drag the playhead | One normalized `t` evaluates every node's independent tracks in one pass |
| **save** | Automatic | `jsonEncode(doc.toJson())` → Firestore `appData/v3` |
| **export** | Export button | The **same** serializer writes a `.json` file. One contract, never a parallel path. |

**Edit-at-keyframe, not record mode.** Selecting a keyframe dot loads that keyframe onto the canvas and edits apply there. This is the legacy UX and it was right.

---

## 3. v1 scope contract — what IS in

Numbered so you can point at an item and say "that one, nothing else."

1. **Artboard** — explicit width/height; all coordinates artboard-relative. Off-artboard is legal but explicit.
2. **Scene graph** — `GroupNode` / `PathNode`, arbitrary nesting. Z-order **is** child-list order.
3. **Transforms** — position, scale, pivot, rotation (unbounded radians), skewX. One `Affine` type for every coordinate mapping in the codebase.
4. **Cubic bezier paths** — every anchor has a stable string ID; corner anchors are the degenerate zero-handle case. One segment type.
5. **Pen / node editing** — insert, delete, move anchors and handles, at any keyframe, mid-animation. **This is the reason the rewrite exists.**
6. **Property tracks** — per-node, per-property, independent keyframe positions. No global keyframe grid.
7. **Easing** — per-segment, cubic-bezier parameters with named presets. Hold/step is an easing.
8. **Spatial tangents on position keys** — curved motion paths. Nullable; null means straight line.
9. **Trim paths** — `trimStart` / `trimEnd` / `trimOffset` on a `PathNode`, animatable. Draw-on reveal is the single most-used effect in this product category.
10. **Layers panel** — reorder, rename, show/hide, lock.
11. **Solid fill + solid stroke**, one each per node, persisted as length-0-or-1 lists.
12. **Transport** — play, pause, loop, ping-pong, scrub.
13. **Persistence** — Firestore `appData/v3`. Legacy `users/` and `appData/v2` untouched.
14. **Export** — versioned JSON, `schemaVersion` mandatory, same serializer as persistence.
15. **Legacy importer** — one-way, all 8 `assets/library/*.json` as golden fixtures.
16. **Bundled samples** — the imported legacy projects, playable in-app.
17. **Deployed URL** — Flutter Web build, publicly reachable.
18. **Autosave hardening** — `enablePersistence()`, debounced autosave, and a visible dirty/saved indicator in the chrome. *Justification (per §4): the failure mode of an autosave drawing tool is silently losing the user's artwork; this is the only real data risk in v1 and the cheapest one to close.*
19. **Monotonic `rev` counter on `Document`** — incremented on every save, written and read by the serializer. *Justification (per §4): one integer field, added now because adding it later is a schema break; v1.1 turns it into optimistic concurrency and detects the two-tab clobber that §6 currently accepts blindly.*

---

## 4. NON-GOALS — what is NOT in v1

> **This list is a commitment device.** 40 months have produced zero shipped software. The identified failure mode is not lack of skill — it is scope. Every item below is individually defensible and collectively fatal.
>
> **Adding anything to v1 requires editing this file, in a commit, with a one-line justification.** Deciding it "in your head while coding" does not count. If it is not numbered in §3, it is not in v1.

| Not in v1 | Why deferred |
| --- | --- |
| **Bones / IK / skinning** | Weeks of work. Seam is pre-paid (stable AnchorIds, no-op `deform` stage). |
| **State machine (Rive-style)** | Seam is pre-paid (`animations` is a List; evaluator takes a weighted mix list). |
| **Components / instancing** | Seam is pre-paid (`ScenePath` identity, structured override keys). |
| **Boolean path ops** | Computational geometry. No demo needs it. |
| **Video / GIF / MP4 export** | JSON export is the contract. Rasterizing is a separate product. |
| **Real-time collaboration** | Firestore is last-write-wins storage, not a CRDT. |
| **Mobile / desktop targets** | Flutter Web only. One target, one test matrix. |
| **Gradients** | Type is sealed so it is additive. UI exposes solid only. |
| **Multiple fills/strokes per node** | Wire format is already a list; UI caps at one. |
| **Per-anchor property tracks** | Whole-path keyframes only. |
| **Cycle / continue extrapolation** | Hold-first / hold-last only. |
| **Masks & mattes** | Beyond `clipChildren`, nothing. |
| **Multiple artboards** | One per document. |
| **Text & image nodes** | Vector paths only. |
| **Parametric shape animation** | `ShapeRecipe` is inert metadata; it regenerates the path, it is never keyed. |
| **Auto-orient along motion path** | Hand-key rotation instead. |
| **Wrapped trim windows, per-subpath trim, group-level trim** | `trimStart > trimEnd` clamps. Per-`PathNode` only. |
| **Absolute-duration authoring** | Time is normalized 0..1. The UI *displays* seconds; the document stores fractions. |
| **Expressions, audio, plugins** | No. |
| **Swapping the database / building the Go + PostgreSQL service** | **Post-v1 (v1.1), strictly after §5 passes on a public URL.** Seam is pre-paid (`ProjectStore`, String in/out). Its appearance in doc 06 is a *deferred* plan, not v1 scope. |

**The two most likely leaks are gradient authoring and per-anchor tracks.** Both look like an afternoon. Both are a week.

---

## 5. Success criteria for v1

v1 is **done** when a person who is not the owner can do all of this, on a deployed public URL, without assistance:

| # | Testable criterion |
| --- | --- |
| 1 | Draw a closed bezier shape with the pen tool, including at least one curved segment |
| 2 | Set 3 keyframes on its path geometry at fractional times, with a different easing on each segment |
| 3 | **Return to keyframe 1 and insert a new anchor mid-path**, then scrub — no crash, no vanishing shape, no frozen animation, and keyframes 2 and 3 are pixel-identical to before the insert |
| 4 | Animate a group's rotation while a child inside it spins the opposite way at a different rate |
| 5 | Animate a stroke drawing itself on (trim 0→1) then fading out |
| 6 | Scrub the full 0→1 range: no NaN, no empty geometry, no error dialog, shape is present at `t=1.0` |
| 7 | Reload the browser and get byte-identical geometry back from Firestore |
| 8 | Export a `.json` and replay it correctly in a plain Flutter app via the new **`anim_core`** runtime package. The legacy `annimation` v0.0.2 is not a fallback — it cannot read a v3 document. |
| 9 | Import all 8 legacy `assets/library/*.json` files; each plays without NaN or empty geometry at 50 sampled `t` values |

**Automated gate:** the round-trip property test over all 8 fixtures, plus the golden transform test on a deliberately non-square artboard (450.2 × 250.4 — the aspect ratio that exposed the legacy y-rescale bug), pass in CI.

**Not success criteria:** feature count, code elegance, matching After Effects.

---

## 6. Constraints

| Constraint | Decision | Reason |
| --- | --- | --- |
| **Stack** | Flutter Web, Dart 3, CanvasKit | Owner's strongest skill. Zero ramp cost. Not negotiable. |
| **Wasm-readiness** | Every numeric JSON read goes through `double d(Object? v) => (v as num).toDouble();` | dart2js hides int/double; dart2wasm does not. |
| **Backend — v1** | Firebase Auth + Firestore, namespace `appData/v3`. **Not replaced before ship.** | Already works, already known. The irreplaceable work is the editor; the backend swap is deferrable forever, the editor is not. Legacy `users/` and `appData/v2` are never touched or migrated. |
| **Backend — v1.1** | Self-written Go + PostgreSQL service in `server/`, same repo. Strictly after §5 passes on a public URL. | Flutter Web has no `dart:io` — a browser cannot open a TCP socket to Postgres, so an HTTP service is a forced consequence, not optional scope. Schema is hybrid relational, never a single `jsonb` blob. |
| **Persistence seam** | `abstract class ProjectStore` — **String in, String out, never `Map`**, from commit one. Implementation selected at build time: `--dart-define=BACKEND=firestore` (v1) / `--dart-define=BACKEND=api` (v1.1). | Keeps `cloud_firestore` types out of the domain layer. No forked branch: `http_project_store.dart` is *added* beside `firestore_project_store.dart`, not swapped in. |
| **Concurrency** | v1: last-write-wins, single user. `rev` (§3.19) is written but not enforced. | Not a CRDT. Two tabs editing one doc is undefined behaviour in v1; v1.1 makes `rev` an optimistic-concurrency check and rejects the clobber. |
| **Team** | Solo, AI-assisted | Scope discipline beats completeness. Every choice justified against "does this ship in ~3 months". |
| **Repo** | Same repo, new branch. Legacy `lib/` → `legacy_reference/`, deleted at parity. | No big-bang rewrite in a fork nobody merges. |
| **Perf budget** | 114 anchors × 10 keyframes × 1 node (largest real legacy file) | Tiny. Immutability and allocation churn are free at this scale. |

---

## 7. Kept from legacy / discarded

### Kept — these were right

| Kept | Note |
| --- | --- |
| **Per-object independent timelines** | Each node owns its own keyframe positions. Generalized to per-property. |
| **Normalized time** (`0..100` → `0..1`) | Resolution- and duration-independent. The one unambiguously correct legacy decision. |
| **One global playhead driving N independent tracks in one tick** | Correct multi-track model. |
| **Segment-local `t` remap** `(t - t[i]) / (t[i+1] - t[i])` | Exactly the right shape for a keyframe evaluator — and exactly where easing was missing. |
| **Edit-at-keyframe UX** | Click a dot, edit on canvas. |
| **Live scrub preview** | Interpolation visible while dragging, not only on play. |
| **Per-object visibility gating** | Now a proper layer flag. |
| **Export = the persistence serializer** | One contract. Never a parallel code path. |
| **Explicit artboard, separate from viewport** | Now with genuinely artboard-relative coordinates. |
| **Bundled library samples** | Cheap, high-value. Now also the importer's golden fixtures. |
| **Loop / ping-pong transport** | From the external player, unified into one transport. |

### Discarded — these were the bugs

| Discarded | Replaced by |
| --- | --- |
| **Array-index vertex correspondence** | Stable string `AnchorId`; interpolation is an ID join. *The load-bearing fix.* |
| **Parallel sorted-percent array beside an unsorted frames list** | One ordered keys list. Lookup and value-read from the same object. |
| **Coincident keyframes → divide-by-zero → NaN** | Strictly-increasing `t` enforced at mutation; zero-span guard in the sampler. |
| **Shape disappears past the last keyframe** | Explicit hold-first / hold-last clamping. Evaluator is total: never throws, never NaN. |
| **Playhead round-tripping through pixels and `BuildContext`** | Unitless normalized double in the domain layer. Pixels only in the timeline widget. |
| **Editor state persisted in the document** (hover point, selection, screen offsets, cached AABBs, dead `boxSize`) | Document holds authored data only. Selection, hover, playhead, zoom are ephemeral. |
| **Absolute unclamped board pixels** | Artboard-relative coordinates; one `Affine` for document→screen. |
| **Hand-rolled per-axis scaling** (the y-scaled-by-width bug) | One `Affine` type, golden-tested on a non-square artboard. |
| **Copy constructor returning the same instance** | Fully immutable value types. |
| **Null-coalescing that manufactures plausible-but-wrong data** | Strict decoder. Missing required subtree throws with a path. |
| **Modal error dialogs inside the animation tick** | Validate at load and at mutation. The tick has no UI concerns. |
| **`Map<String, dynamic>` hand-written serializers with silently dropped fields** | Code-generated serialization + round-trip test over all 8 fixtures. |
| **No schema version; sequential colliding IDs (`Project_14` ×3)** | Mandatory `schemaVersion`; UUIDs. |
| **Capital-`S` `"SingleFrameModel"` key** | camelCase everywhere. |
| **Global ambient `DrawingType` enum driving rendering** | Polymorphic dispatch on node type. |

---

## 8. The governing rules

Three sentences that keep the whole model coherent. Violating any of them is how the legacy app died.

1. **TOPOLOGY edits are TRACK-WIDE; POSITION edits are KEYFRAME-LOCAL.** Inserting an anchor mints one ID and inserts it into every keyframe of every path track for that node, across every animation.
2. **An anchor-ID *sequence* may never differ between two keyframes of one track.** Not just the set — the sequence.
3. **The evaluator is total and continuous.** It never throws and never returns NaN, *and* `interpolate(a, b, 0.0)` renders pixel-identically to `a`. Totality alone was never sufficient.

---

**Next:** [01_domain_model.md](01_domain_model.md) · [02_file_format.md](02_file_format.md)
