# v3 — Features & Acceptance Criteria

**What this doc is:** the v1 build list. Every numbered scope item in [00 §3](00_vision_and_scope.md) expanded into epics → features → **observable, testable** acceptance criteria, with inter-feature dependencies so [06](06_roadmap.md) can sequence them.
**What it is not:** a design doc or a schedule. Types and invariants are [01_domain_model.md](01_domain_model.md) (authoritative); wire format is [02_file_format.md](02_file_format.md). No dates here.

---

## 0. How to read this

| Convention | Meaning |
| --- | --- |
| **Epic `E{n}`** | A coherent slice of 00 §3. Every epic cites the scope items it discharges. |
| **Feature `F{n}.{m}`** | A shippable unit. Carries **Depends on** — the sequencing input for doc 06. |
| **Criterion `AC-{n}.{m}.{k}`** | Given / When / Then. One row = one assertion a stranger can run on the deployed URL, or one test in CI. |
| **Scope** | The 00 §3 item number. Nothing in this doc lacks one, except E13 (a quality bar, not a feature). |

**Rules that bind every criterion below** — from 00 §8 / 01 §1:

1. TOPOLOGY edits are **track-/document-wide** for a node; POSE edits are **keyframe-local**.
2. `AnchorId` unique within a `PathData`; `NodeId` unique within a `Document`. An anchor-ID **sequence** may never differ between two keyframes of one track.
3. The evaluator is **total and continuous** — never throws, never NaN, and output at `u = 1e-6` is within epsilon of output at `u = 0`.

**The one insight this doc keeps testing:** topology lives on `PathNode.path` (`PathData`); keyframes hold `PathPose` = `Map<AnchorId, AnchorPose>`, poses only. **A mismatched anchor set is not a representable state** — so every criterion phrased as "the other keyframes are unchanged" is a claim about *exactness*, not about best effort.

---

## E1 — Artboard & Document
*Scope 1, 19.*

### F1.1 — Explicit artboard
**Depends on:** nothing (first feature).

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-1.1.1 | A new document | Created | `Document` holds an explicit `width`/`height`; the artboard rect is drawn with a visible boundary |
| AC-1.1.2 | Artboard 450.2 × 250.4 | A unit square is placed at document `(0,0)`–`(1,1)` and the golden transform test runs | Screen-space corners match the golden to ≤ 0.01 px. **No per-axis hand-rolled scaling exists** — one `Affine` maps document → screen |
| AC-1.1.3 | A node positioned outside the artboard | Rendered | It draws (off-artboard is legal), is selectable, and is clipped only at the artboard boundary in the export preview |
| AC-1.1.4 | Artboard width or height edited | Applied | Existing node coordinates are **not** rescaled — coordinates are artboard-relative, not artboard-normalized |

### F1.2 — Document identity, `schemaVersion`, `rev`
**Depends on:** F1.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-1.2.1 | Any new `Document` | Created | `id` is a UUID v4; `schemaVersion == 3`; `rev == 0`. No sequential ids anywhere |
| AC-1.2.2 | A document at `rev == n` | A save completes | `rev == n + 1`, monotonic, written by the serializer and read back by the decoder |
| AC-1.2.3 | A document round-tripped `Document.fromJson(doc.toJson())` | Compared | `rev` survives byte-identically. (v1 **writes** `rev`; it does **not** enforce it — 00 §6 concurrency) |
| AC-1.2.4 | JSON containing an unrecognized node `type` | Loaded then saved | It decodes to `UnknownNode`, renders nothing, is unselectable, and re-emits **verbatim** on save |

---

## E2 — Scene Graph & Layers
*Scope 2, 10.*

### F2.1 — Nested scene graph
**Depends on:** F1.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-2.1.1 | An empty document | A shape is drawn | A `PathNode` is appended to the root `GroupNode.children` |
| AC-2.1.2 | Three sibling nodes | Rendered | Paint order is `children` index order — index 0 back-most. There is **no** `zIndex` field to desync |
| AC-2.1.3 | Two nodes selected | `NodeOps.createGroup` | A `GroupNode` wraps them, its pivot is the union-AABB centre, and both nodes render pixel-identically to before |
| AC-2.1.4 | A node inside group A with a non-identity world transform | `NodeOps.reparent` into group B | The node does **not** visually move (`newLocal = newParent.world.invert() · oldWorld`, then `Affine.decompose` back into `Transform2`) |
| AC-2.1.5 | A group is duplicated | `NodeOps.duplicateSubtree` | Every `NodeId` **and** every `AnchorId` in the subtree is re-minted and the matching `TrackSet` entries are deep-copied under the new ids, as ONE undo entry. Animating the copy leaves the original untouched |
| AC-2.1.6 | A `GroupNode` with `clipChildren == true` | A child overflows its bounds | The child is clipped. With `false`, it is not |

### F2.2 — Layers panel
**Depends on:** F2.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-2.2.1 | A 3-level nested document | The layers panel opens | The tree is displayed **reversed** relative to `children` (top of list = front-most) |
| AC-2.2.2 | A layer dragged to a new index | Dropped | The change is a `children` list splice; paint order updates in the same frame; no derived order array exists |
| AC-2.2.3 | A layer renamed | Committed | `Node.name` changes; `NodeId` does not |
| AC-2.2.4 | A group's `visible` toggled off | Rendered | Every descendant is hidden regardless of its own `visible` value or `BoolTrack` (`worldVisible` = AND over ancestors) |
| AC-2.2.5 | A group at `opacity 0.5` containing a child at `opacity 0.5` | Rendered | Effective opacity is 0.25 (`worldOpacity` = PRODUCT over ancestors) |
| AC-2.2.6 | A layer with `locked == true` | Clicked on canvas | It is not hit-tested and not selectable. The **evaluator never reads `locked`** — playback is unaffected |
| AC-2.2.7 | A locked/hidden layer | Reloaded from persistence | `locked` and `visible` survive (authored), while selection, hover, playhead, and zoom do **not** (`EditorState`, ephemeral) |

---

## E3 — Transforms
*Scope 3.*

### F3.1 — `Transform2` authoring
**Depends on:** F2.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-3.1.1 | A selected node | position / scale / pivot / rotation / skewX edited | `Transform2` updates; composition order matches 01 §4 and is asserted by the golden test |
| AC-3.1.2 | Rotation dragged past 360° | Released | The stored value is **unbounded radians** — no wrap to `[0, 2π)`, no shortest-arc normalization |
| AC-3.1.3 | Pivot moved | Node re-rendered | The node rotates about the new pivot; its untransformed geometry is unchanged |
| AC-3.1.4 | Any coordinate mapping in the codebase (document→screen, parent→child, viewport zoom/pan) | Inspected | It goes through the single `Affine` type. A grep for a second matrix or a per-axis scale helper returns nothing |
| AC-3.1.5 | A node whose `scale` is keyed to `(0, 0)` | Evaluated | `Affine.invert()` returns null, the node renders nothing, and the evaluator does **not** throw and produces no NaN |

---

## E4 — Drawing & Path Editing
*Scope 4, 5. **This epic is the reason the rewrite exists.***

### F4.1 — Pen tool & path creation
**Depends on:** F2.1, F3.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-4.1.1 | The pen tool active | Click, click, drag, click-on-first-anchor | A closed `PathData` is created with ≥ 1 curved segment; every `Anchor` has a unique `AnchorId` |
| AC-4.1.2 | Any created path | Inspected | There is exactly **one** segment type (cubic). A straight segment is the degenerate zero-handle case — no polyline branch exists |
| AC-4.1.3 | An anchor dragged with `AnchorKind` set to a smooth kind | Dragged | Handles behave per that kind; setting the corner kind zeroes handles and the segment renders straight |
| AC-4.1.4 | A path created by a shape tool (rect / ellipse / polygon) | Created | It emits anchors and stores the matching `RectRecipe` / `EllipseRecipe` / `PolygonRecipe` as **inert** metadata. The recipe is never keyed and never appears in a `TrackSet` |
| AC-4.1.5 | A recipe parameter edited (e.g. polygon point count) | Applied | The change routes through `PathOps.retopologize`; it never bypasses it |

### F4.2 — Pose editing (keyframe-local)
**Depends on:** F4.1, F6.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-4.2.1 | A 3-keyframe path track, keyframe 2 selected | An anchor is dragged (`PathOps.moveAnchor`) | Only keyframe 2's `PathPose` changes. Keyframes 1 and 3 render pixel-identically |
| AC-4.2.2 | Same, handles dragged | `PathOps.setTangents` | Only that keyframe's `AnchorPose` tangents change; the `AnchorId` **sequence** is untouched |
| AC-4.2.3 | Any pose edit on a node with no track for `PropKey.path` | Applied | It edits the node's `PathData` rest pose. No track is silently created |

### F4.3 — Topology editing (document-wide) — **the load-bearing feature**
**Depends on:** F4.2.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-4.3.1 | A 3-keyframe path animation, scrubbed to keyframe 1 | An existing segment is clicked (`PathOps.insertAnchor(after:, u:)`) | **ONE** `AnchorId` is minted and an `AnchorPose` is written into **every keyframe of every path track for that node, across every `Animation`** — each computed by de Casteljau split of *that keyframe's own* cubic at `u` |
| AC-4.3.2 | Immediately after AC-4.3.1 | Keyframes 2 and 3 are rendered | They are **pixel-identical** to before the insert (the split is exact) |
| AC-4.3.3 | Immediately after AC-4.3.1 | Undo pressed once | The whole insert reverts — **one command, one undo entry**, not one per keyframe |
| AC-4.3.4 | Immediately after AC-4.3.1 | The full 0→1 range is scrubbed | No crash, no vanishing shape, no frozen animation |
| AC-4.3.5 | An anchor deleted (`PathOps.deleteAnchor`) | Applied | The id is removed from `PathData` **and** from every keyframe pose of every path track for that node |
| AC-4.3.6 | Any sequence of N pen edits at arbitrary keyframes | The CI invariant test runs | Every keyframe of every path track for the node holds the **identical `AnchorId` sequence** |
| AC-4.3.7 | A 4-anchor square track | `PathOps.retopologize` to a 10-anchor star topology | Every keyframe pose is rewritten onto the new id set by arc-length correspondence; the track still satisfies AC-4.3.6; the operation runs once per edit and **never inside the tick** |
| AC-4.3.8 | A tracked `PathNode` | Any attempt to assign `PathData` directly | It is unreachable — `PathData`'s const constructor is private and `PathOps` is the only route to a topology change. Enforced structurally, asserted in CI |

---

## E5 — Paint
*Scope 11.*

### F5.1 — Solid fill & solid stroke
**Depends on:** F4.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-5.1.1 | A closed path | A fill colour is picked | One `Fill` with a `SolidPaint` / `Rgba` is applied; `fills` serializes as a length-0-or-1 list |
| AC-5.1.2 | Any path | A stroke is applied | One `Stroke` with width, `StrokeCap`, `StrokeJoin`; `strokes` serializes as a length-0-or-1 list |
| AC-5.1.3 | The paint UI | Inspected | It offers **solid only**. `LinearGradientPaint` / `RadialGradientPaint` / `GradientStop` / `StopId` exist in the sealed `PaintSource` type but have **no authoring UI** (00 §4) |
| AC-5.1.4 | A path with a self-intersecting outline | `FillRule` toggled | The rendered fill changes accordingly |
| AC-5.1.5 | A node with both fill and stroke | Rendered | All fills paint first, strokes after — order asserted in the golden test |
| AC-5.1.6 | A document from a newer client with 2 fills | Loaded, edited, saved | Both fills round-trip; the UI edits only the first. No silent truncation |

---

## E6 — Timeline & Keyframes
*Scope 6.*

### F6.1 — Per-node, per-property tracks
**Depends on:** F3.1, F4.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-6.1.1 | Node A keyed at t = 0.0/0.5/1.0 and node B at t = 0.13/0.77 | Scrubbed | Both animate independently. There is **no** global keyframe grid and no shared key list |
| AC-6.1.2 | One node with `position` keyed and `rotation` unkeyed | Scrubbed | `position` animates; `rotation` holds its `Transform2` pose value |
| AC-6.1.3 | Any property keyed | The track is created | Its runtime type equals `kExpectedTrackType[prop]` — the exhaustive 16-member `PropKey` mapping. A mismatch is rejected at the decoder and returns null (never throws) from the typed accessor |
| AC-6.1.4 | A node absent from `Animation.tracks` | Evaluated | It is fully static. Tracks are per-node **sparse** |
| AC-6.1.5 | 4 nodes each with keys, only node 1 selected | Play pressed | **All four animate.** No cache keyed by selection exists (the legacy defect where unselected sections rendered frozen at keyframe 0) |

### F6.2 — Keyframe manipulation
**Depends on:** F6.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-6.2.1 | A track with keys at 0.2 and 0.5 | A key is dragged (`TrackOps.moveKeyframe`) | It is addressed **by index resolved at command-construction time**, never re-derived from a float mid-drag |
| AC-6.2.2 | Same | A key is dragged onto another within `TrackOps.minSeparation` (`1e-4`) | The move is **rejected** (or ε-nudged) — coincident keys are impossible by construction, so the sampler can never divide by zero |
| AC-6.2.3 | Any track | Inspected at any time | `keys.isNotEmpty`, `t` strictly increasing, every `t ∈ [0,1]`, exactly **one** ordered list. Lookup and value-read come from the same object |
| AC-6.2.4 | A track whose first key is at t = 0.4 | Inspected | It is **not** auto-pinned to 0 (invariant T6). `TrackOps.pinEndpoints` exists as an explicit user affordance only, never as an automatic build-time side effect |
| AC-6.2.5 | The timeline widget | Rendered | `build`/`itemBuilder` performs **pure reads**. No code path mutates the `Document` from inside a build method |
| AC-6.2.6 | A keyframe dot clicked | Selected | That keyframe loads onto the canvas and subsequent pose edits apply **there** (edit-at-keyframe, not record mode). Selection lives in `EditorState`, never in `Document` |
| AC-6.2.7 | A key added at a time where one exists | `TrackOps.upsertKeyframe` | It **replaces**, producing no second key at that `t` |

---

## E7 — Easing & Interpolation
*Scope 7, 8.*

### F7.1 — Per-segment easing
**Depends on:** F6.2.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-7.1.1 | A 3-key track | A different easing is set on each outgoing segment (`TrackOps.setEasing`) | Each segment eases independently; `Easing` governs the segment **leaving** its key |
| AC-7.1.2 | The easing picker | Opened | Named presets are offered and lower to `CubicEasing` parameters at authoring time — no preset symbol survives into evaluation |
| AC-7.1.3 | A programmatically created or imported key | Inspected | Its model default is `LinearEasing` (the identity). The ease-in-out default belongs to the **UI**, never the model |
| AC-7.1.4 | A segment set to `HoldEasing` | Scrubbed across it | The value steps — it holds the left key until the next key, then jumps |

### F7.2 — Interpolation & continuity
**Depends on:** F7.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-7.2.1 | Any two keys `a`, `b` on any track type | `interpolate(a, b, 0.0)` | Renders **pixel-identically** to `a`; and output at `u = 1e-6` is within epsilon of output at `u = 0` (governing rule 3) |
| AC-7.2.2 | A `PathTrack` | Interpolated | Interpolation is an **ID join** over `Map<AnchorId, AnchorPose>` — never an array-index correspondence |
| AC-7.2.3 | A `BoolTrack` on `PropKey.visible` | Interpolated | The value **steps**; booleans are never lerped |
| AC-7.2.4 | `rotation` keyed 0 → 10π | Scrubbed | It spins five times. No shortest-arc normalization |
| AC-7.2.5 | Playhead before the first key or after the last | Evaluated | Hold-first / hold-last clamping applies. The shape is present at `t = 1.0`; nothing vanishes |
| AC-7.2.6 | 50 sampled `t` values on any document | Evaluated | No NaN coordinate, no empty geometry, no throw, no error dialog |

### F7.3 — Spatial tangents on position keys
**Depends on:** F7.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-7.3.1 | Two `Vec2Keyframe`s with `inTangent`/`outTangent` null | Scrubbed | Motion is a straight-line lerp (the unchanged fast path) |
| AC-7.3.2 | A motion-path handle dragged out | Scrubbed | The node follows a curved path; the tangents are stored **relative to `value`** |
| AC-7.3.3 | A curved motion path with `HoldEasing` on the same segment | Scrubbed | Time easing and spatial curvature are **orthogonal** — the hold governs speed, the tangents govern shape |
| AC-7.3.4 | Any curved motion path | Rendered | Node rotation is unaffected. **No auto-orient** (00 §4) |

---

## E8 — Trim / Reveal
*Scope 9.*

### F8.1 — Animatable `PathTrim`
**Depends on:** F4.1, F6.1, F5.1.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-8.1.1 | A stroked path | `trimStart` / `trimEnd` / `trimOffset` edited | `PathTrim` updates; each is a fraction of **total arc length**, 0..1, and each is keyable as a `ScalarTrack` |
| AC-8.1.2 | `trimEnd` keyed 0 → 1 with `opacity` keyed 1 → 0 afterwards | Played | The stroke draws itself on, then fades out |
| AC-8.1.3 | `end <= start` | Evaluated | **Empty geometry.** Never a throw, never a null deref |
| AC-8.1.4 | `start > end` (wrapped window) | Evaluated | **Clamped.** Wrapped windows are a written non-goal |
| AC-8.1.5 | A `closed: true` path with a partial trim window | Evaluated | Output is `closed: false` — a partially revealed shape cannot be filled |
| AC-8.1.6 | `trimOffset` animated on a closed path | Scrubbed | The reveal start walks around the path; it is not locked to anchor 0 |
| AC-8.1.7 | A `PathData` scrubbed 60 times | Profiled | The arc-length table is **memoized per immutable `PathData`** — it is not rebuilt per tick (01 §5: the only real perf hazard in the model) |
| AC-8.1.8 | A trimmed node | Its output anchors inspected | Their ids are **synthetic and non-authoritative** — nothing downstream joins on them |
| AC-8.1.9 | A trimmed node under a non-uniform parent scale | Evaluated | Trim is measured in **node-local space**, so the revealed fraction does not depend on the transform |
| AC-8.1.10 | The trim UI | Inspected | Per-`PathNode` only. No per-subpath trim, no group-level trim, no `Stroke.dash` (00 §4) |

---

## E9 — Transport & Playback
*Scope 12.*

### F9.1 — Transport
**Depends on:** F6.1, F7.2.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-9.1.1 | A document with tracks | Play / pause pressed | Playback starts and stops; `EditorState.playhead` is a **unitless normalized double** at all times |
| AC-9.1.2 | `LoopMode.once` / `loop` / `pingPong` selected | Played past the end | `normalizedTime` yields clamp / wrap / triangle respectively, and it lives **outside** the evaluator |
| AC-9.1.3 | The playhead dragged | Dragging | Interpolation is visible **while dragging**, not only on play (live scrub preview) |
| AC-9.1.4 | The timeline widget | Inspected | Pixels appear only in its paint and hit-test. The playhead never round-trips through pixels or `BuildContext` to reach the domain layer |
| AC-9.1.5 | `durationSeconds` changed from 1.0 to 2.6 | Applied | Everything retimes proportionally and **no keyframe is re-authored** — the document stores fractions; the UI displays seconds and writes `t = seconds / durationSeconds` |
| AC-9.1.6 | `fps` changed | Played | Nothing in the model quantizes to frames; it is a preview/export hint only |

### F9.2 — Evaluator pipeline (8 named stages)
**Depends on:** F6.1, F7.2, F8.1, F5.1. *Blocks E11.*

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-9.2.1 | Any evaluation | `evaluate` runs | Stages execute in this exact order as **named functions, not an inlined walk**: `sampleTracks` → `resolvePose` → `composeWorldA` → `solveConstraints` → `composeWorldB` → `deform` → `applyTrim` → `resolvePaint` |
| AC-9.2.2 | v1 build | The pipeline inspected | `solveConstraints`, `composeWorldB`, and `deform` are **no-ops** and are present as seams (IK, re-compose, skinning). Removing them is a scope violation, not a cleanup |
| AC-9.2.3 | A group rotating one way with a child rotating the opposite way at a different rate | Played | Both rotations are visible and independent (`composeWorldA`: `world = parent.world · local`, pre-order) |
| AC-9.2.4 | A malformed track type in a loaded document | Evaluated | The typed accessor returns null; the paint loop does not crash and shows no modal dialog. Validation happens at **load and at mutation**, never inside the tick |
| AC-9.2.5 | `List<AnimationMix>` with one entry at weight 1.0 (the v1 case) | Evaluated | Output equals the single-animation result. A mix entry whose animation lacks a track for property P contributes the node's **pose** value at that weight — never zero, never a renormalized weight |
| AC-9.2.6 | Any evaluation | Output inspected | It is a `Scene` of `ResolvedNode`s; the `Document` is unmodified (evaluation is a pure read) |

---

## E10 — Persistence & Autosave
*Scope 13, 18, 19.*

### F10.0 — Auth (email/password only)
**Depends on:** nothing. Lands in M0 — `uid` is what scopes every Firestore path, so nothing persistent works without it.

Firebase **email/password sign-up and sign-in, and nothing else**. No social providers, no anonymous auth, no forgot-password, no email verification, no account linking, no MFA (00 §4). Anonymous is rejected outright: it mints a new `uid` per browser and per data-clear, scattering one person's work across orphaned accounts.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-10.0.1 | A new visitor at `/signin` | Submitting a valid email + password in sign-up mode | The account is created and they land on the project list |
| AC-10.0.2 | An existing account | Signing in | The same `uid` is restored and their projects load |
| AC-10.0.3 | A signed-in session | The browser is reloaded | Still signed in — no re-authentication prompt |
| AC-10.0.4 | The sign-in form | Each Firebase error returned | Invalid email, weak password (min 6 chars), email already in use, wrong password, user not found, and network failure each render a distinct inline message — never a modal, never a raw exception string |
| AC-10.0.5 | The auth UI | Inspected | No social buttons, no "forgot password" link. **A forgotten password is unrecoverable in v1** and the UI must not imply otherwise |
| AC-10.0.6 | User A signed in | Requesting user B's project path | Firestore security rules deny it — `uid` scoping is enforced server-side, not only in the client |

### F10.1 — `ProjectStore` seam
**Depends on:** F1.2, F10.0. **Must land in commit one** — retrofitting it means untangling `cloud_firestore` types out of the domain layer.

```dart
abstract class ProjectStore {
  Future<List<ProjectSummary>> list();
  Future<String?> load(String id);           // raw jsonEncode output
  Future<void> save(String id, String json);
  Future<void> delete(String id);
}
```

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-10.1.1 | The domain layer (`lib/domain/**`) | Grepped for `cloud_firestore` | Zero hits. `ProjectStore` is **String in, String out, never `Map`** |
| AC-10.1.2 | The repo | Inspected | `lib/data/project_store.dart` (interface) and `lib/data/firestore_project_store.dart` (v1) exist on the **same branch**. No fork |
| AC-10.1.3 | The app | `flutter run --dart-define=BACKEND=firestore` | The Firestore implementation is selected at build time. `BACKEND=api` and `http_project_store.dart` are **v1.1** — *added* later beside the Firestore one, never replacing it |
| AC-10.1.4 | Firestore writes | Inspected | They target `appData/v3/users/{uid}/projects/{projectId}` only. Legacy `users/` and `appData/v2` are never read and never written |

### F10.2 — Save / load round-trip
**Depends on:** F10.1, F9.2.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-10.2.1 | A signed-in email/password session | A project is saved and the browser reloaded | Geometry comes back **byte-identical**; the session and `uid` persist without re-authenticating |
| AC-10.2.2 | A Firestore payload | Compared to a file export | They are the **same bytes** — `jsonEncode(doc.toJson())`, one serializer, no parallel path |
| AC-10.2.3 | Firestore returning a whole double as an int | Decoded | Every numeric read goes through `double d(Object? v) => (v as num).toDouble();` — no `as double` cast survives a grep (dart2wasm readiness) |
| AC-10.2.4 | A document missing a required subtree | Loaded | The strict decoder **throws with a path**. No null-coalescing manufactures plausible-but-wrong data |
| AC-10.2.5 | All 8 legacy fixtures | The CI property test runs | `Document.fromJson(doc.toJson()) == doc` for every one |

### F10.3 — Autosave hardening
**Depends on:** F10.2. *Scope 18 — the only real data risk in v1.*

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-10.3.1 | Rapid continuous editing (a 5-second drag) | Observed | Writes are **debounced** — one write after the edit settles, not one per frame |
| AC-10.3.2 | The app boots | Inspected | `enablePersistence()` is called; edits made offline queue and flush on reconnect |
| AC-10.3.3 | An unsaved edit exists | Observed | The chrome shows a **dirty** indicator; after the write acknowledges, it shows **saved**. The state is always one of dirty / saving / saved / error |
| AC-10.3.4 | A write fails | Observed | The indicator shows **error** and the edit is retained in memory. No modal dialog, no silent success |
| AC-10.3.5 | An autosave completes | `rev` inspected | It incremented by exactly 1 and round-tripped. In v1 it is **written but not enforced** — two tabs are last-write-wins (00 §6), and v1.1 turns this same field into an optimistic-concurrency check with no schema break |

---

## E11 — Import / Export & Samples
*Scope 14, 15, 16.*

### F11.1 — Versioned JSON export
**Depends on:** F10.2.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-11.1.1 | Any document | Export pressed | A `.json` downloads with a mandatory `schemaVersion`, produced by the **persistence serializer** |
| AC-11.1.2 | The exported file | Loaded back into the editor | It reproduces the document exactly |
| AC-11.1.3 | The repo | Grepped | Exactly one `toJson` path exists per type. No export-only serializer |
| AC-11.1.4 | v1 export targets | Inspected | Native v3 JSON only. **SVG and Lottie export are v2** — not built, not stubbed (02 §10) |

### F11.2 — `anim_core` runtime replay
**Depends on:** F11.1, F9.2.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-11.2.1 | The `anim_core` package | Its imports inspected | Model + serializer + evaluator, **zero Flutter imports** — pure Dart, published from this repo |
| AC-11.2.2 | An exported `.json` | Loaded in a plain Flutter app that depends on `anim_core` | It replays correctly at 50 sampled `t` values |
| AC-11.2.3 | The v3 codebase | Grepped for `annimation` | Zero dependency references. The old pub.dev package v0.0.2 is **not a dependency, not a compatibility target, not a migration path** — it reads the legacy format and cannot read a v3 document, which is why v3 ships a new package rather than a version bump |

### F11.3 — Legacy importer (one-way)
**Depends on:** F9.2, F10.2.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-11.3.1 | Each of the 8 `assets/library/*.json` files | `LegacyImporter.import` | A `Document` with `schemaVersion == 3` is produced. The importer is **one-way** — no v3 → legacy writer exists |
| AC-11.3.2 | Each imported fixture | Evaluated at `k/50` for `k = 0..50` | No NaN coordinate anywhere, no empty geometry, shape present at `t = 1.0` |
| AC-11.3.3 | `Squares.json` (three keys at exactly `20.34722169240316`) | Imported | Coincident keys are separated or rejected at mutation; no divide-by-zero, no NaN |
| AC-11.3.4 | `circlebounce.json` (114 anchors × 10 keyframes) | Imported | Geometry reads from the correct keyframe — one ordered key list, no sorted-percent/unsorted-frames desync |
| AC-11.3.5 | Any legacy path whose per-keyframe vertex counts disagree | Imported | Repair routes through `PathOps.retopologize`; the result satisfies AC-4.3.6 |
| AC-11.3.6 | Legacy `"SingleFrameModel"` and other capital-S keys | Imported | Mapped to camelCase. No capital-S key exists in a v3 document |

### F11.4 — Bundled samples
**Depends on:** F11.3.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-11.4.1 | A first-time user on the deployed URL | The sample gallery opened | All 8 imported legacy projects are listed and play in-app without assistance |
| AC-11.4.2 | A sample opened | Edited and saved | It saves as a **new** project under the user's `appData/v3` namespace; the bundled asset is unmodified |

---

## E12 — Deployment
*Scope 17.*

### F12.1 — Public Flutter Web build
**Depends on:** every epic above (this is the ship gate).

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-12.1.1 | The `main` build | Deployed | A public URL serves the CanvasKit Flutter Web build; a stranger can reach it with no local setup |
| AC-12.1.2 | A stranger on that URL | Signing up with an email and password | The account is created, an empty project list loads, and the session survives a reload. Email/password is the **only** provider (00 §4) |
| AC-12.1.3 | The deployed build | Exercised | All 9 criteria in 00 §5 pass **on that URL, without assistance** |
| AC-12.1.4 | CI | Run on every push | The round-trip property test over all 8 fixtures **and** the golden transform test on the 450.2 × 250.4 artboard both pass. A red gate blocks deploy |
| AC-12.1.5 | Build targets | Inspected | Flutter Web only. No mobile or desktop target is configured (00 §4) |

---

## E13 — Rendering & UI performance *(quality bar, no scope item)*

**In v1, narrowly.** Perf budget is 00 §6: **114 anchors × 10 keyframes × 1 node** — the largest real legacy file.

**Explicitly OUT of v1, stated rather than silently omitted:** memory-leak hunting, allocation-churn reduction, object pooling, and micro-optimizing the immutable value types. 00 §6 says immutability and allocation churn are **free at this scale**. Do not spend a day here; it buys nothing measurable and costs the editor.

**Depends on:** F9.1, F6.2.

| # | Given | When | Then |
| --- | --- | --- | --- |
| AC-13.1 | The canvas and the timeline | Profiled during a scrub | Each is wrapped in a `RepaintBoundary`; scrubbing repaints the canvas without repainting the layers panel or the property inspector |
| AC-13.2 | The playhead dragged across the full range | Profiled | No rebuild storm — the widget subtree rebuilt per frame is scoped to the canvas and the playhead marker, not the whole editor |
| AC-13.3 | An anchor dragged | Profiled | Repaint is scoped to the canvas; the layers panel does not rebuild |
| AC-13.4 | The perf-budget document (114 anchors × 10 keyframes) | Scrubbed end to end | Interaction stays responsive on a mid-range laptop in Chrome. **No allocation-level optimization is required to get there** |
| AC-13.5 | Any per-tick code path | Inspected | The arc-length table (AC-8.1.7) and the `Map<NodeId, Node>` index are built **per document mutation**, never per tick |

---

## Success-criteria coverage

Every criterion in [00 §5](00_vision_and_scope.md#5-success-criteria-for-v1) maps to the epic(s) that satisfy it. A criterion with no owning epic is a scope hole; there are none.

| 00 §5 # | Criterion | Satisfied by | Key ACs |
| --- | --- | --- | --- |
| 1 | Draw a closed bezier shape with ≥ 1 curved segment | **E4** (F4.1), E2, E1 | AC-4.1.1, AC-4.1.2 |
| 2 | 3 path keyframes at fractional times, different easing per segment | **E6**, **E7** | AC-6.1.1, AC-6.2.3, AC-7.1.1 |
| 3 | Insert an anchor at keyframe 1, scrub, keyframes 2–3 pixel-identical | **E4** (F4.3) | AC-4.3.1 … AC-4.3.6 |
| 4 | Group rotation with a child spinning the opposite way at a different rate | **E3**, **E2**, **E9** (F9.2) | AC-9.2.3, AC-2.1.4, AC-3.1.1 |
| 5 | Stroke draws itself on (trim 0→1) then fades out | **E8**, **E5**, **E6** | AC-8.1.2, AC-8.1.1 |
| 6 | Scrub 0→1: no NaN, no empty geometry, no error dialog, shape at `t = 1.0` | **E7** (F7.2), **E9** (F9.2) | AC-7.2.5, AC-7.2.6, AC-9.2.4 |
| 7 | Reload the browser, byte-identical geometry from Firestore | **E10** | AC-10.2.1, AC-10.2.3, AC-10.3.5 |
| 8 | Export a `.json`, replay it in a plain Flutter app via **`anim_core`** | **E11** (F11.1, F11.2) | AC-11.2.1, AC-11.2.2, AC-11.2.3 |
| 9 | Import all 8 legacy fixtures; each plays clean at 50 sampled `t` | **E11** (F11.3), **E9** | AC-11.3.1 … AC-11.3.6 |
| — | *Automated gate:* round-trip property test + golden transform test in CI | **E12**, **E1**, **E10** | AC-12.1.4, AC-1.1.2, AC-10.2.5 |

---

## Dependency graph (sequencing input for doc 06)

```
E1  F1.1 ──► F1.2 ──────────────────────────────► F10.1
     │
     └──► E2 F2.1 ──► F2.2
              │
              ├──► E3 F3.1 ──┐
              │              ├──► E4 F4.1 ──► F4.2 ──► F4.3   ★ ships the rewrite's reason
              └──────────────┘        │
                                      ├──► E5 F5.1
                                      └──► E6 F6.1 ──► F6.2 ──► E7 F7.1 ──► F7.2
                                                                    └──► F7.3
                                      E8 F8.1  ◄── F4.1, F6.1, F5.1
                                      E9 F9.1  ◄── F6.1, F7.2
                                      E9 F9.2  ◄── F6.1, F7.2, F8.1, F5.1
                                      E13      ◄── F9.1, F6.2
F10.1 ──► F10.2 ──► F10.3
F10.2 ──► E11 F11.1 ──► F11.2 (also needs F9.2)
F10.2 + F9.2 ──► F11.3 ──► F11.4
ALL ──► E12 F12.1
```

**Critical path:** `F1.1 → F2.1 → F4.1 → F4.2 → F6.1 → F6.2 → F4.3`. F4.3 is the feature the whole rewrite exists for; nothing downstream of it should be started before AC-4.3.6 passes in CI.

**F10.1 is off the critical path but must land first anyway** — the `ProjectStore` seam is cheap in commit one and expensive at commit three hundred.

---

## Cross-links

- [00_vision_and_scope.md](00_vision_and_scope.md) — the 19 scope items, the non-goals, the 9 success criteria.
- [01_domain_model.md](01_domain_model.md) — authoritative types, invariants, mutation API, evaluator pipeline.
- [02_file_format.md](02_file_format.md) — wire format, Firestore layout, legacy mapping, export targets.
