# 02 — File Format (schemaVersion 3)

**What this doc is:** the on-the-wire contract. The exact JSON produced by `Document.toJson()` and consumed by `Document.fromJson()` — the *same* serializer used for Firestore persistence (v1), for the PostgreSQL service (v1.1), for file export, and for the **new pure-Dart core runtime package `anim_core`** (model + serializer + evaluator, zero Flutter imports). Key-by-key schema, forward-compat rules, coordinate space, numeric rules, the legacy importer policy, and both store layouts.

> **Clean break from `annimation`.** The published pub.dev package `annimation` v0.0.2 is built on the legacy structure. It is **not** a dependency, **not** a compatibility target, and **not** a migration path — it reads the legacy format and *cannot* read a v3 document. That is why v3 ships a new package rather than a version bump. Nothing in this doc is constrained by it.

**What it is not:** the domain model (see [01_domain_model.md](01_domain_model.md) for the Dart types, invariants, and the evaluator), the product scope (see [00_vision_and_scope.md](00_vision_and_scope.md)), or the renderer. If this doc and doc 01 disagree, doc 01 wins and this doc is the bug.

---

## 1. Hard rules (read these, skip nothing else)

| # | Rule | Reason |
|---|---|---|
| 1 | `schemaVersion` is **mandatory** on the root, integer, currently `3`. | Legacy has no version field at all; the external player parses this as a public contract. |
| 2 | **Absent `schemaVersion` == legacy**. Route to the one-way importer, never to the v3 decoder. | Legacy docs are structurally distinguishable but only by luck; the version check is the only reliable gate. |
| 3 | All keys are **camelCase**. No exceptions. | Legacy's single capital-S `"SingleFrameModel"` key silently default-constructed empty geometry on any casing mismatch. |
| 4 | Every numeric value decodes through `(v as num).toDouble()`. | Firestore and legacy JSON both mix `int` and `double` for the same field. Works under dart2js, **crashes under dart2wasm**. |
| 5 | Missing **required** subtree → throw with a JSON path. Missing **optional** field → declared default. `null` means absent and is never manufactured into a plausible value. | Legacy's `?? defaultValue` chains turned malformed documents into plausible-but-wrong ones. |
| 6 | Unknown keys are **preserved and re-emitted verbatim**, never dropped, never thrown on. | A stale tab must not silently delete a newer document's data on autosave. |
| 7 | If `schemaVersion` > `Document.currentSchemaVersion`, the document opens **read-only**; every save path is disabled. | Rule 6 covers unknown keys; this covers unknown *semantics* (e.g. a v4 `skin` field a v3 client would strip). |
| 8 | Derived data is **never persisted**. | Legacy stored bounding boxes and stale caches. |
| 9 | Geometry is in **absolute artboard-relative document units** (doubles, y-down, origin = artboard top-left). Time is **normalized 0..1**. | See §5. |
| 10 | Serialization is **code-generated** (freezed + json_serializable). No hand-written `toMap`. | Legacy silently dropped `panPointIndex` because a hand-written map forgot it. |

---

## 2. Complete example document

A real v3 document: one group containing a stroked signature path that draws itself on then fades, and a filled square that spins. Every field shown is exactly what the encoder emits.

```json
{
  "schemaVersion": 3,
  "id": "0f6b2c1e-8e2a-4f38-9d1b-1a7c5e9f2b40",
  "name": "Signature Reveal",
  "rev": 7,
  "artboard": { "x": 450.2, "y": 250.4 },
  "background": [0.0, 0.0, 0.0, 0.0],
  "defaultAnimationId": "anim-main",

  "root": {
    "type": "group",
    "id": "n-root",
    "name": "Root",
    "transform": {
      "position": { "x": 0.0, "y": 0.0 },
      "scale": { "x": 1.0, "y": 1.0 },
      "pivot": { "x": 0.0, "y": 0.0 },
      "rotation": 0.0,
      "skewX": 0.0
    },
    "opacity": 1.0,
    "visible": true,
    "locked": false,
    "clipChildren": false,
    "children": [
      {
        "type": "path",
        "id": "n-sig",
        "name": "Signature",
        "transform": {
          "position": { "x": 0.0, "y": 0.0 },
          "scale": { "x": 1.0, "y": 1.0 },
          "pivot": { "x": 220.0, "y": 130.0 },
          "rotation": 0.0,
          "skewX": 0.0
        },
        "opacity": 1.0,
        "visible": true,
        "locked": false,
        "path": {
          "closed": false,
          "anchors": [
            { "id": "a0", "position": { "x": 20.0,  "y": 200.0 },
              "inTangent":  { "x": 0.0,   "y": 0.0 },
              "outTangent": { "x": 60.0,  "y": -120.0 }, "kind": "corner" },
            { "id": "a1", "position": { "x": 200.0, "y": 90.0 },
              "inTangent":  { "x": -60.0, "y": 40.0 },
              "outTangent": { "x": 60.0,  "y": -40.0 }, "kind": "smooth" },
            { "id": "a2", "position": { "x": 420.0, "y": 60.0 },
              "inTangent":  { "x": -80.0, "y": 30.0 },
              "outTangent": { "x": 0.0,   "y": 0.0 }, "kind": "corner" }
          ]
        },
        "fills": [],
        "strokes": [
          { "id": "p-ink", "paint": { "type": "solid", "color": [0.05, 0.05, 0.08, 1.0] },
            "width": 6.0, "cap": "round", "join": "round", "miterLimit": 4.0,
            "opacity": 1.0, "visible": true }
        ],
        "trim": { "start": 0.0, "end": 1.0, "offset": 0.0 }
      },
      {
        "type": "path",
        "id": "n-sq",
        "name": "Square",
        "transform": {
          "position": { "x": 0.0, "y": 0.0 },
          "scale": { "x": 1.0, "y": 1.0 },
          "pivot": { "x": 60.0, "y": 60.0 },
          "rotation": 0.0,
          "skewX": 0.0
        },
        "opacity": 1.0,
        "visible": true,
        "locked": false,
        "path": {
          "closed": true,
          "anchors": [
            { "id": "b0", "position": { "x": 40.0,  "y": 40.0 },
              "inTangent": { "x": 0.0, "y": 0.0 }, "outTangent": { "x": 0.0, "y": 0.0 }, "kind": "corner" },
            { "id": "b1", "position": { "x": 80.0,  "y": 40.0 },
              "inTangent": { "x": 0.0, "y": 0.0 }, "outTangent": { "x": 0.0, "y": 0.0 }, "kind": "corner" },
            { "id": "b2", "position": { "x": 80.0,  "y": 80.0 },
              "inTangent": { "x": 0.0, "y": 0.0 }, "outTangent": { "x": 0.0, "y": 0.0 }, "kind": "corner" },
            { "id": "b3", "position": { "x": 40.0,  "y": 80.0 },
              "inTangent": { "x": 0.0, "y": 0.0 }, "outTangent": { "x": 0.0, "y": 0.0 }, "kind": "corner" }
          ]
        },
        "fills": [
          { "id": "p-body", "paint": { "type": "solid", "color": [0.90, 0.24, 0.19, 1.0] },
            "rule": "nonZero", "opacity": 1.0, "visible": true }
        ],
        "strokes": [],
        "recipe": { "type": "rect", "w": 40.0, "h": 40.0, "cornerRadius": 0.0 },
        "trim": { "start": 0.0, "end": 1.0, "offset": 0.0 }
      }
    ]
  },

  "animations": [
    {
      "id": "anim-main",
      "name": "Main",
      "durationSeconds": 2.6,
      "fps": 60,
      "loop": "once",
      "tracks": {
        "n-sig": {
          "trimEnd": {
            "type": "scalar",
            "keys": [
              { "t": 0.0,   "value": 0.0, "easing": { "kind": "cubic", "p": [0.42, 0.0, 0.58, 1.0] } },
              { "t": 0.769, "value": 1.0, "easing": { "kind": "linear" } }
            ]
          },
          "opacity": {
            "type": "scalar",
            "keys": [
              { "t": 0.769, "value": 1.0, "easing": { "kind": "linear" } },
              { "t": 1.0,   "value": 0.0, "easing": { "kind": "linear" } }
            ]
          }
        },
        "n-sq": {
          "rotation": {
            "type": "scalar",
            "keys": [
              { "t": 0.0, "value": 0.0,     "easing": { "kind": "linear" } },
              { "t": 1.0, "value": 12.5664, "easing": { "kind": "linear" } }
            ]
          },
          "position": {
            "type": "vec2",
            "keys": [
              { "t": 0.0, "value": { "x": 0.0, "y": 0.0 },
                "outTangent": { "x": 90.0, "y": -30.0 },
                "easing": { "kind": "cubic", "p": [0.42, 0.0, 1.0, 1.0] } },
              { "t": 0.6, "value": { "x": 260.0, "y": 120.0 },
                "inTangent":  { "x": -70.0, "y": -95.0 },
                "outTangent": { "x": 45.0,  "y": -80.0 },
                "easing": { "kind": "cubic", "p": [0.0, 0.0, 0.58, 1.0] } },
              { "t": 1.0, "value": { "x": 340.0, "y": 120.0 },
                "inTangent": { "x": -25.0, "y": -4.0 },
                "easing": { "kind": "linear" } }
            ]
          },
          "fillColor:p-body": {
            "type": "color",
            "keys": [
              { "t": 0.0, "value": [0.90, 0.24, 0.19, 1.0], "easing": { "kind": "linear" } },
              { "t": 0.5, "value": [0.16, 0.42, 0.92, 1.0], "easing": { "kind": "linear" } },
              { "t": 1.0, "value": [0.90, 0.24, 0.19, 1.0], "easing": { "kind": "linear" } }
            ]
          },
          "path": {
            "type": "path",
            "keys": [
              { "t": 0.0, "easing": { "kind": "linear" }, "value": { "anchors": {
                  "b0": { "position": { "x": 40.0, "y": 40.0 }, "inTangent": { "x": 0.0, "y": 0.0 }, "outTangent": { "x": 0.0, "y": 0.0 } },
                  "b1": { "position": { "x": 80.0, "y": 40.0 }, "inTangent": { "x": 0.0, "y": 0.0 }, "outTangent": { "x": 0.0, "y": 0.0 } },
                  "b2": { "position": { "x": 80.0, "y": 80.0 }, "inTangent": { "x": 0.0, "y": 0.0 }, "outTangent": { "x": 0.0, "y": 0.0 } },
                  "b3": { "position": { "x": 40.0, "y": 80.0 }, "inTangent": { "x": 0.0, "y": 0.0 }, "outTangent": { "x": 0.0, "y": 0.0 } } } } },
              { "t": 1.0, "easing": { "kind": "linear" }, "value": { "anchors": {
                  "b0": { "position": { "x": 60.0, "y": 20.0 }, "inTangent": { "x": -14.0, "y": 6.0 }, "outTangent": { "x": 14.0, "y": -6.0 } },
                  "b1": { "position": { "x": 96.0, "y": 60.0 }, "inTangent": { "x": 0.0, "y": -18.0 }, "outTangent": { "x": 0.0, "y": 18.0 } },
                  "b2": { "position": { "x": 60.0, "y": 96.0 }, "inTangent": { "x": 14.0, "y": -6.0 }, "outTangent": { "x": -14.0, "y": 6.0 } },
                  "b3": { "position": { "x": 24.0, "y": 60.0 }, "inTangent": { "x": 0.0, "y": 18.0 }, "outTangent": { "x": 0.0, "y": -18.0 } } } } }
            ]
          }
        }
      }
    }
  ]
}
```

---

## 3. Key-by-key schema

### 3.1 Root — `Document`

| Key | Type | Req | Default | Notes |
|---|---|---|---|---|
| `schemaVersion` | int | **yes** | — | `3`. Absent ⇒ legacy. |
| `id` | string | **yes** | — | UUID v4. Never `"Project_14"` (three legacy samples collide on that id). |
| `name` | string | **yes** | — | Display name. Not an identity. |
| `rev` | int | no | `1` | **Monotonic save counter.** Optional-with-default per §7, so a doc written before it existed decodes. Starts at `1`, incremented by exactly 1 per *persisted* save (never per edit, never per undo). v1 writes and round-trips it; v1.1 turns it into optimistic concurrency (§9b). |
| `artboard` | `Vec2` | **yes** | — | Document size in units. `{x,y}`, both doubles. |
| `background` | `Rgba` | no | `[0,0,0,0]` | `[r,g,b,a]` doubles 0..1. |
| `root` | `Node` | **yes** | — | Always a `group`. Z-order = `children` order, index 0 = back-most. |
| `animations` | `Animation[]` | no | `[]` | **v1 writes exactly one.** Plural from day one (state-machine seam). |
| `defaultAnimationId` | string\|null | no | `null` | Must reference an entry in `animations`. Never `animations.first`. |
| `components` | object | — | *omitted in v1* | Reserved (instancing). v1 never writes it; rule 6 preserves it. |
| `stateMachines` | array | — | *omitted in v1* | Reserved. Same treatment. |

### 3.2 `Node` (sealed, discriminated by `type`)

`type` is an **open string**: `"group"` \| `"path"`. Unknown values decode to an `UnknownNode` that keeps the raw map, renders nothing, is unselectable, and is re-emitted verbatim on save.

Common to all nodes:

| Key | Type | Req | Default |
|---|---|---|---|
| `type` | string | **yes** | — |
| `id` | string | **yes** | — (UUID; unique within a Document) |
| `name` | string | no | `""` |
| `transform` | `Transform2` | no | identity |
| `opacity` | double | no | `1.0` |
| `visible` | bool | no | `true` |
| `locked` | bool | no | `false` |

`"group"` adds: `children` (`Node[]`, default `[]`), `clipChildren` (bool, default `false`).

`"path"` adds:

| Key | Type | Req | Default | Notes |
|---|---|---|---|---|
| `path` | `PathData` | **yes** | — | **Authoritative topology + rest pose.** |
| `fills` | `Fill[]` | no | `[]` | v1 UI exposes 0 or 1; array from day one so multi-paint is additive. |
| `strokes` | `Stroke[]` | no | `[]` | Same. |
| `recipe` | `ShapeRecipe`\|null | no | `null` | Inert re-edit metadata; never animated. |
| `trim` | `PathTrim` | no | `{0,1,0}` | Draw-on / reveal. Omitted when full. |

### 3.3 `Transform2`

```json
{ "position": {"x":0.0,"y":0.0}, "scale": {"x":1.0,"y":1.0},
  "pivot": {"x":0.0,"y":0.0}, "rotation": 0.0, "skewX": 0.0 }
```

- `rotation` and `skewX` are **radians**, **unbounded**, lerped raw. `4π` means two turns. No wrapping, no shortest-arc — ever.
- Composition: `local = T(position)·T(pivot)·R·SkewX·S·T(-pivot)`; `world = parent.world · local`.
- `pivot` is authored once at creation (AABB centre) and is **not** keyframed in v1 — it appears twice with opposite sign, so animating it while `scale != 1` translates the node.

### 3.4 `PathData` / `Anchor`

```json
{ "closed": true,
  "anchors": [
    { "id": "b0", "position": {"x":40.0,"y":40.0},
      "inTangent": {"x":0.0,"y":0.0}, "outTangent": {"x":0.0,"y":0.0},
      "kind": "corner" } ] }
```

| Rule | Statement |
|---|---|
| Identity | `id` is stable and opaque, minted once, never reused, never derived from list position. **This is the whole point of v3.** |
| Uniqueness | `AnchorId` is unique within one `PathData`. Enforced by a validating factory and re-checked at decode. |
| Order | `anchors` order is **draw order**, and it is load-bearing for insert operations — the anchor *sequence* (not just the set) is the topology. |
| Tangents | Relative to `position` (Lottie `i`/`o` convention), so they move with the anchor. Both zero ⇒ straight line. One segment type in the renderer. |
| `kind` | `corner` \| `smooth` \| `symmetric`. **Authoring hint only** — the renderer and evaluator never read it. |
| Degenerate | 0 or 1 anchor renders nothing. Never throws. The pen tool produces exactly this on the first click. |
| Segment `k` | `cubicTo(a[k].pos + a[k].out, a[k+1].pos + a[k+1].in, a[k+1].pos)`; if `closed`, one extra segment last→first. |
| `closed` | Lives **only here**, on the node. It is not per-keyframe and cannot vary over time. |

### 3.5 Paint

```json
"fills":   [{ "id":"p-body","paint":{"type":"solid","color":[0.9,0.24,0.19,1.0]},
              "rule":"nonZero","opacity":1.0,"visible":true }],
"strokes": [{ "id":"p-ink","paint":{"type":"solid","color":[0.05,0.05,0.08,1.0]},
              "width":6.0,"cap":"round","join":"round","miterLimit":4.0,
              "opacity":1.0,"visible":true }]
```

- Colors are `[r,g,b,a]` **doubles 0..1**, straight (non-premultiplied) sRGB. Not hex strings (legacy mixed `'ffeee2dd'` and `'FFFFC0CB'`), not packed ints.
- `paint.type` is an open string; `"solid"` is the only v1 value. `"linearGradient"` / `"radialGradient"` are reserved — unknown values preserve-and-skip-render.
- Every `Fill`/`Stroke` carries a stable `id` (`PaintId`) so a track can address *which* paint. Retrofitting this after documents exist is a schema break; it is free now.
- Enums persist by `.name`: `cap` ∈ `butt|round|square`, `join` ∈ `miter|round|bevel`, `rule` ∈ `nonZero|evenOdd`.

### 3.6 `PathTrim`

```json
"trim": { "start": 0.0, "end": 1.0, "offset": 0.0 }
```

All three are fractions of **total arc length**, 0..1. `end <= start` renders nothing. A partial window on a `closed: true` path renders as open. v1 does not support wrapped windows (`start > end`) — clamped. Omitted from JSON when equal to the default.

### 3.7 `ShapeRecipe`

```json
"recipe": { "type": "rect",    "w": 40.0, "h": 40.0, "cornerRadius": 0.0 }
"recipe": { "type": "ellipse", "rx": 30.0, "ry": 20.0 }
"recipe": { "type": "polygon", "sides": 5, "radius": 50.0, "star": true, "innerRatio": 0.5 }
```

Inert metadata for re-editing a generated shape. **Never animated.** Authority rule: the recipe regenerates `path`; any manual anchor edit nulls the recipe. Regenerating a recipe on a node that has a `path` track routes through `PathOps.retopologize` (doc 01), never a raw path replacement.

### 3.8 `Animation`

| Key | Type | Req | Default | Notes |
|---|---|---|---|---|
| `id` | string | **yes** | — | UUID. |
| `name` | string | no | `""` | |
| `durationSeconds` | double | no | `1.0` | Playback hint only. Changing it retimes everything and re-authors nothing. |
| `fps` | int | no | `60` | Preview/export hint. **Nothing is quantized to frames.** |
| `loop` | string | no | `"loop"` | `once` \| `loop` \| `pingPong`. |
| `tracks` | `{ NodeId: TrackSet }` | no | `{}` | Sparse. A node absent here is fully static. |

**Per-object independent timelines are preserved**: each node owns its own keys at its own positions. There is no global keyframe grid, no shared frame table, and no derived parallel position array anywhere in the format. Legacy's `framePosPercentListForAllIconSections` has no successor.

### 3.9 `TrackSet` and property keys

A `TrackSet` is a flat object keyed by the **wire form of `PropertyKey(prop, subjectId)`**:

```
"rotation"            // subjectId == null
"fillColor:p-body"    // subjectId == "p-body"
```

`prop` is persisted **by name**. v1 property names:

| Name | Track type | Applies to |
|---|---|---|
| `position`, `scale`, `pivot` | `vec2` | any node |
| `rotation`, `skewX`, `opacity` | `scalar` | any node |
| `visible` | `bool` | any node |
| `path` | `path` | path node |
| `fillColor`, `strokeColor` | `color` | path node (`subjectId` = PaintId) |
| `fillOpacity`, `strokeOpacity`, `strokeWidth` | `scalar` | path node (`subjectId` = PaintId) |
| `trimStart`, `trimEnd`, `trimOffset` | `scalar` | path node |

One **const table maps property name → expected track type**, used by both the decoder and the mutation API. It is the only cast site in the codebase; the evaluator reaches tracks through typed accessors that return `null` on mismatch and fall back to the node's pose value. A malformed Firestore document must never crash the paint loop.

**Unknown property names are preserved, not evaluated, and re-emitted on save.** Same for unknown `easing.kind` and unknown `paint.type`.

### 3.10 Tracks and keyframes

```json
"rotation":  { "type": "scalar", "keys": [ { "t": 0.0, "value": 0.0, "easing": {...} } ] }
"position":  { "type": "vec2",   "keys": [ { "t": 0.0, "value": {"x":0.0,"y":0.0},
                                             "inTangent": {...}, "outTangent": {...},
                                             "easing": {...} } ] }
"fillColor:p-body": { "type": "color", "keys": [ { "t": 0.0, "value": [r,g,b,a], "easing": {...} } ] }
"visible":   { "type": "bool",   "keys": [ { "t": 0.0, "value": true, "easing": {...} } ] }
"path":      { "type": "path",   "keys": [ { "t": 0.0, "value": { "anchors": { "<anchorId>": {...} } },
                                             "easing": {...} } ] }
```

| Rule | Statement |
|---|---|
| `t` | **Normalized 0..1**, strictly increasing, clamped to `[0,1]`. The only ordering key. There is no `frameNo`. |
| Coincident keys | Impossible: rejected or ε-nudged (`1e-4`) at insert. Legacy's divide-by-zero NaN (Squares.json had three keys at the same position) cannot form. |
| Endpoints | First key is **not** pinned to 0 and last is **not** pinned to 1. Hold-first / hold-last clamping in the sampler makes pinning unnecessary; a track may legitimately start at `t=0.3`. |
| Ordering | One list. Lookup and value-read come from the same object. No parallel sorted array exists in the format or the code. |
| `easing` | Governs the segment **leaving** this key. Default `{"kind":"linear"}` — the identity of the operation. `easeInOut` is a *UI* default for newly authored keys, never a model default. |
| Vec2 spatial tangents | `inTangent`/`outTangent` on a `vec2` key are **spatial** (relative to `value`), giving curved motion paths. Omitted ⇒ straight-line lerp (the fast path). Distinct from `easing`, which shapes *time*. |
| Path keys | Store `Map<AnchorId, AnchorPose>` — **not** an anchor list. Topology lives on the node; keyframes vary only poses. An anchor missing from a pose resolves to the node's rest anchor. Anchor counts differing between keyframes is not a representable state. |

### 3.11 `Easing`

```json
{ "kind": "linear" }
{ "kind": "hold" }
{ "kind": "cubic", "p": [0.42, 0.0, 0.58, 1.0] }
```

Two shapes only. Named presets (`easeOut`, `backOut`, …) are UI labels over the four numbers and are **not** persisted as names — the wire format never has to know the preset vocabulary. `x1`/`x2` clamped to 0..1 (monotonic time); `y` unclamped (overshoot). `hold` maps `u → 0` (stepped) and falls out of the same code path.

---

## 4. Persisted vs derived

**Persisted — authored data only.**

`schemaVersion`, `rev`, ids, names, artboard size, background, node tree + z-order (child list order), transforms, anchor positions and tangents, `closed`, `kind`, fills/strokes, `trim`, `recipe`, animations, tracks, keyframe `t`/`value`/`easing`/spatial tangents, `defaultAnimationId`, `locked`, `visible`, `opacity`.

**Derived — recomputed every time, NEVER in the document.**

| Thing | Legacy did what | v3 |
|---|---|---|
| Bounding boxes | Persisted `cornerBoxPoints` (4 pts, always the AABB) — a cache that could go stale. | Recomputed from anchors on demand. |
| Mouse cursor | Persisted `hoverPoint: {0,0}` in ~60 frames. | Ephemeral `EditorState`. |
| Selected segment | Persisted `controlPointAdjecntPair`, and `null` decoded into a real `{preIndex:0,nextIndex:1}` — "no selection" was indistinguishable from "segment 0-1 selected". | Ephemeral. |
| Panel/board geometry | Persisted `boxSize: {200,100}` (never overridden) and `position` on Project *and* IconSection, written from the drawing board's **screen** offset and never read back. | Nothing. Viewport chrome never touches the document. |
| Playhead | Stored as `timeLinePointerXPosition` in **logical pixels**, converted via `BuildContext` screen width. | Unitless normalized double in `EditorState`. Pixels exist only inside the timeline widget's paint/hit-test. |
| Zoom / pan | n/a | One `Affine` in `EditorState`, applied at paint time. |
| Sorted keyframe position list | Derived `framePosPercentListForAllIconSections`, sorted, desynced from the unsorted `frames` array — read geometry from the wrong keyframe. | Does not exist. |
| Arc-length tables | n/a | Memoized per immutable `PathData` at runtime. |
| `ScenePath` / resolved scene | n/a | `Scene`, `ResolvedNode`, world matrices, posed geometry — all ephemeral, rebuilt per tick. |

**Rule:** if you can compute it from persisted data, do not write it. If you wrote it and it disagrees with the computation, you have a bug you cannot detect.

---

## 5. Coordinate space and time

**Decision: geometry is stored in absolute artboard-relative document units (doubles, y-down, origin = artboard top-left). Time is stored normalized 0..1.**

| Aspect | Decision | One-line reason |
|---|---|---|
| Geometry units | Artboard-relative absolute units, not 0..1 normalized | Normalizing geometry makes every anchor's stored value depend on artboard size, so resizing the artboard silently rewrites the whole document; absolute units + one transform keeps edits local. |
| Origin | Artboard top-left, y-down | Matches CanvasKit, SVG and Lottie; zero conversion at the render and export boundary. |
| Off-artboard coords | **Legal and explicit** | Legacy samples already contain them (Squares.json spans x −142.4…977.6 on a 400×400 canvas); clamping would destroy documents on import. |
| Screen mapping | One `Affine`, applied at paint time, **never persisted** | Legacy hand-rolled per-axis scaling and scaled **y by the width ratio** (`cast_control_points.dart`), which drifts on any non-square artboard. There is exactly one affine type in the codebase, and a golden test pins it against a deliberately non-square **450.2 × 250.4** artboard — the exact aspect ratio that exposed the bug. |
| Time | Normalized 0..1 | The one legacy decision that was unambiguously right (`framePosition` 0..100). A document plays at any duration and any resolution; the evaluator needs no `BuildContext`, no screen width, no fps. |
| Consequence to own | Absolute-duration authoring is **out of scope** | "Draw on over exactly 2s" is stored as `t = 2.0 / durationSeconds = 0.769`. The timeline UI **must** display seconds alongside `t` and author keys as `seconds / durationSeconds`, or the owner will hand-compute the magic number and get it wrong. |

---

## 6. Numeric hygiene

Every numeric read goes through one helper. No exceptions, no direct casts.

```dart
/// The ONLY way a number enters the domain model.
double d(Object? v) => (v as num).toDouble();

int i(Object? v) => (v as num).toInt();

// Generated decoders call it per field, deliberately:
Vec2 _vec2(Map<String, Object?> j) => Vec2(d(j['x']), d(j['y']));
Rgba _rgba(List<Object?> j) => Rgba(d(j[0]), d(j[1]), d(j[2]), d(j[3]));
```

| Trap | Detail |
|---|---|
| JSON int/double mixing | Legacy files contain `{"x": 192, "y": 57}` next to `{"x": 4.800018310546875}`, `framePosition` as int `0` and double `15.90277353922526`, `width` as int `400` and double `450.1999969482422`. Every numeric field in the format is int-or-double. |
| Firestore | Firestore stores whole doubles as integers on round-trip. `1.0` written → `1` read. Identical hazard, in the primary persistence path. |
| dart2js hides it | `int` and `double` are unified in JS, so `json['x'] as double` on an int **works today**. |
| dart2wasm exposes it | They are distinct types. Every one of those reads becomes a runtime `TypeError`. v3 targets CanvasKit and may move to Wasm. |
| Encoder side | Always emit doubles: `0.0`, not `0`. Firestore may still normalize them; rule 4 makes that harmless. |
| No NaN/Infinity | Not representable in JSON. The decoder rejects them; the evaluator's zero-span and clamping guards ensure they cannot be produced. |
| `fps` | The one deliberate `int`. Coercion is per-field, never blanket. |

---

## 7. Forward compatibility

| Rule | Enforcement |
|---|---|
| **Unknown keys are preserved and re-emitted verbatim.** | Every model class carries `Map<String, Object?> unknownKeys`, populated by the decoder, splatted back on encode. Applies at Document, Node, Animation, TrackSet, Track and Keyframe level. |
| **Unknown node `type`** | Decodes to `UnknownNode { rawType, raw }`. Renders nothing, unselectable, round-trips exactly. |
| **Unknown property name / easing kind / paint type** | Preserved, not evaluated, re-emitted. Never dropped, never thrown on. |
| **Newer document ⇒ read-only.** | `schemaVersion > currentSchemaVersion` opens the document read-only and disables every save path. Key preservation cannot protect *semantics* — a v3 client cannot know that a v4 `skin` field must stay consistent with the anchors it just let the user delete. |
| **New fields are always optional with a default.** | A field that would be required is a new `schemaVersion`, not a new field. |
| **A key is never repurposed.** | Meaning is fixed at first ship. Need different semantics ⇒ new key name. Old key stays readable forever or the format bumps. |
| **`schemaVersion` bumps only on a breaking change.** | Additive fields, additive node types, additive property names, additive enum values: all stay at 3. |

Why this matters more than usual here: Firestore is the backing store (stale browser tabs), and the new core runtime package `anim_core` is a **second, independently-versioned reader** of these documents — an app can ship an `anim_core` older than the editor that wrote the file. A silent field drop on autosave is data loss, not a degrade.

**Reserved keys — v1 never writes them, and rule 6 protects them:** `components`, `stateMachines` (Document); `skin`, `ik` (nodes); `pins` (path track); `linearGradient` / `radialGradient` (paint type); `bone` / `instance` (node type). Declaring them here is what makes bones, the state machine, and instancing additive later. See [01_domain_model.md](01_domain_model.md) §Deferred seams.

---

## 8. Legacy migration

**Decision: a one-way importer for the 8 bundled sample projects only. No back-compat, no round-trip, no export to legacy.**

Why not full back-compat:

- The legacy format has **no version field**, so it cannot be safely evolved.
- Only **two** of `SingleFrameModel`'s 8 keys are load-bearing (`points`, `framePosition`); the rest are dead constants, screen offsets, editor selection, or a recomputable AABB.
- It **structurally cannot express** a node added mid-animation (point counts are provably constant within every section of every sample), which is the single defect the rewrite exists to fix.
- Shipped samples are **already corrupt** (scrambled frame order, duplicate positions, colliding project ids). Preserving fidelity to them is preserving bugs.
- Legacy `users/` and `appData/v2` are **never touched**, so no user data is at risk. The importer is for the 8 asset fixtures — which become golden test files, not a supported migration path.

Detection: `schemaVersion` absent ⇒ legacy. Corroborate on presence of `iconSections` or the capital-S `"SingleFrameModel"` key.

### Mapping

| Legacy | v3 |
|---|---|
| `Project` | `Document` — **new UUID** (`circlebounce`, `circlebounce2`, `circlebounce3` all claim `"Project_14"`). |
| `width` / `height` | `artboard` via `d(v)` (int in 7 files, double in `circlebounce`). |
| `IconSection` | one `PathNode` under `root`, in section order. |
| `color` (ARGB hex string, mixed case) | one `SolidFill`, parsed case-insensitively → `[r,g,b,a]` doubles. |
| `drawingObjectType` | `recipe` where inferable, else dropped. Rendering never dispatches on it. |
| `points[]` | anchors; **ids minted by index at import** — safe *only* because point counts are provably constant within every section of every sample. |
| `controlMidPoints` | `{}` in all ~60 frames across all 8 files ⇒ every anchor imports as `kind: corner`, zero tangents. The legacy corpus imposes zero constraints on the bezier design. |
| `framePosition` (0..100) | keyframe `t = framePosition / 100`. |
| frame ordering | **Sorted by `framePosition`.** Never trust array order, never trust `frameNo` (it is a meaningless insertion tag; `circlebounce` section 1 stores `(0,100)` first). |
| duplicate positions | ε-nudged apart (`Squares.json` section 3 has `20.34722169240316` **three times**; section 4 has a duplicate too). |
| easing | `{"kind":"linear"}` on every key, so imported files play **bit-identically** to legacy. |
| `hoverPoint`, `boxSize`, `cornerBoxPoints`, `controlPointAdjecntPair`, both `position` fields | **Dropped.** Editor/viewport state and derived caches. |
| `frameNo`, `panPointIndex` | Dropped. |

### Importer acceptance tests

```dart
// Golden fixtures: all 8 files in assets/library/.
for (final f in legacyFixtures) {
  final doc = LegacyImporter.import(jsonDecode(await load(f)));
  expect(doc.schemaVersion, 3);
  for (var k = 0; k <= 50; k++) {                 // 50 sample points
    final scene = evaluate(doc, [AnimationMix(doc.defaultAnimationId!, k / 50)]);
    expectNoNaN(scene);                            // no NaN coordinate anywhere
    expectNoEmptyGeometry(scene);                  // nothing vanishes at t=1.0
  }
  expect(Document.fromJson(doc.toJson()), doc);    // round-trip identity
}
```

Three legacy bugs these tests pin shut: the shape disappearing at 100% (no `preFrameNo+1` ⇒ empty points), the NaN from coincident keyframes, and the sorted-list/unsorted-frames index desync.

---

## 9. Firestore layout

```
appData/
  v3/
    users/
      {uid}/
        projects/
          {projectId}          <- one document == one v3 Document, jsonEncode-shaped
```

| Rule | Detail |
|---|---|
| **Namespace** | `appData/v3/...` only. Legacy `users/` and `appData/v2` are **never read and never written** by v3 code. |
| **Document id** | `{projectId}` == `Document.id` == UUID v4. Sequential ids (legacy did sorted-last + 1, non-atomic) are banned. |
| **Same serializer** | The Firestore payload *is* `doc.toJson()` — the exact bytes as file export. One contract, one code path. Legacy already got this right (`jsonEncode(project.toMap())`); keep the discipline. |
| **Numeric coercion** | Mandatory on read (§6). Firestore integer-normalizes whole doubles. |
| **Size** | 1 MiB per Firestore document. Largest realistic workload (`circlebounce`: 114 anchors × 10 keyframes) is ~150 KB with full-UUID anchor ids. Mitigation if ever needed: anchor ids are only required unique *within a `PathData`*, so short opaque ids (`"a0".."a113"`) are legal. Not optimized in v1. |
| **Concurrency** | Last-write-wins. Not solved in v1. Mitigated by: writing the whole document atomically, and by rule 7 (a newer-schema document is read-only). `rev` (§3.1) is **written and round-tripped in v1 but not enforced** — it exists so v1.1 can enforce it (§9b) without a schema break. |
| **Autosave** | Debounced write through `ProjectStore.save`, plus `enablePersistence()` (offline queue) and a visible dirty/saved indicator. Losing artwork is the only real data risk in v1. |
| **Export** | `jsonEncode(doc.toJson())` → `.json` download. Thin serializer over the domain model, never a parallel code path. |

---

## 9b. v1.1 PostgreSQL layout

**Post-ship only.** v1 ships on Firestore (§9); no store migration happens before the 00 §5 success criteria pass on a public URL. v1.1 adds a self-written Go + PostgreSQL service under `server/` in this repo — **added, never replacing**. Both stores live behind the same seam:

```dart
abstract class ProjectStore {
  Future<List<ProjectSummary>> list();
  Future<String?> load(String id);           // raw jsonEncode output
  Future<void> save(String id, String json);
  Future<void> delete(String id);
}
```

`String` in, `String` out — never `Map` — so `cloud_firestore` types never reach the domain layer. Selected at build time, no forked branch:

```bash
flutter run --dart-define=BACKEND=firestore   # v1  → lib/data/firestore_project_store.dart
flutter run --dart-define=BACKEND=api         # v1.1 → lib/data/http_project_store.dart
```

> **The wire format is unchanged by the storage swap.** The identical `doc.toJson()` bytes go to Firestore, to Postgres, and to file export. Nothing in §1–8 moves. That is the entire point of the `ProjectStore` seam — the store is a delivery detail, the format is the contract.

**Flutter Web has no `dart:io`**, so a browser cannot open a TCP socket to Postgres. v1.1 therefore *requires* an HTTP service in front of the database. Forced consequence, not optional scope.

### Schema

Hybrid relational: typed columns for everything filtered, sorted or listed; `body jsonb` for the document itself.

```sql
CREATE TABLE projects (
  id                uuid PRIMARY KEY,
  owner_id          uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name              text        NOT NULL,
  schema_version    integer     NOT NULL,
  rev               bigint      NOT NULL DEFAULT 1,
  artboard_w        double precision NOT NULL,
  artboard_h        double precision NOT NULL,
  duration_seconds  double precision NOT NULL,
  fps               integer     NOT NULL,
  body              jsonb       NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  CONSTRAINT projects_rev_positive     CHECK (rev >= 1),
  CONSTRAINT projects_schema_supported CHECK (schema_version >= 3)
);
```

**Why not one `jsonb` blob column.** Postgres keeps **no statistics on JSONB keys** — `body->>'name'` and `body->>'schemaVersion'` get a hardcoded default selectivity guess, so the planner cannot estimate row counts and picks bad plans (seq scan where an index nested loop was right). Typed columns are analyzable; the blob is not.

```sql
CREATE TABLE project_versions (
  project_id  uuid        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  rev         bigint      NOT NULL,
  body        jsonb       NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  pinned      boolean     NOT NULL DEFAULT false,
  PRIMARY KEY (project_id, rev)
);
```

Backs "restore a previous autosave": every successful save appends the *previous* `body` here in the same transaction. The compound PK `(project_id, rev)` is both the identity and the history scan order; `ON DELETE CASCADE` means deleting a project cannot leave orphan history.

### Indexes

| Index | Reason |
|---|---|
| `projects_pkey (id)` | `ProjectStore.load` / `save` / `delete` are all single-row by id. |
| `CREATE INDEX projects_owner_updated ON projects (owner_id, updated_at DESC) WHERE deleted_at IS NULL;` | The one hot query: `ProjectStore.list()` = a user's live projects, newest first. Partial, so soft-deleted rows never enter the index. |
| `CREATE UNIQUE INDEX projects_owner_name ON projects (owner_id, lower(name)) WHERE deleted_at IS NULL;` | Names are unique per user, case-insensitively, without a trigger. |
| `project_versions_pkey (project_id, rev)` | History list and "restore rev N" are both prefix lookups on the PK. No second index needed. |
| `CREATE INDEX project_versions_pinned ON project_versions (project_id, created_at DESC) WHERE pinned;` | Partial index over the few pinned snapshots — retention must never delete them, and the check has to be cheap. |

### Retention

| Rule | Detail |
|---|---|
| Keep | The newest **50** unpinned revisions per project, plus **all** pinned ones, plus everything younger than **7 days**. |
| Job | A nightly `DELETE FROM project_versions` job (pg_cron), batched by `project_id`. |
| Why | Autosave is debounced but still frequent; unbounded history turns a 150 KB document into gigabytes of `jsonb` in weeks. |

### `rev` as optimistic concurrency

The client sends the `rev` it loaded. The server makes the update conditional on it:

```sql
UPDATE projects
   SET body             = $3::jsonb,
       rev              = rev + 1,
       name             = $4,
       schema_version   = $5,
       artboard_w       = $6,
       artboard_h       = $7,
       duration_seconds = $8,
       fps              = $9,
       updated_at       = now()
 WHERE id = $1 AND rev = $2 AND deleted_at IS NULL
RETURNING rev;
```

| Rowcount | Meaning | Server | Client |
|---|---|---|---|
| `1` | The row was still at the expected `rev`. | `200` + the new `rev`; the caller adopts it. | Mark saved. |
| `0` | Another tab (or another device) saved in between — or the project was deleted. | `409 Conflict` + the current server `rev`. | **Surface the conflict to the user and never clobber.** Keep the in-memory document, stop autosave, offer *reload theirs* / *save as a copy*. An automatic retry with the fresh `rev` is exactly the two-tab overwrite §9 accepts blindly, and is banned. |

This is the concrete upgrade over §9's last-write-wins. It costs one integer on the wire, which is why `rev` ships in v1 unenforced.

### How `doc.toJson()` maps on

| Column | Source | Rule |
|---|---|---|
| `body` | `jsonEncode(doc.toJson())` | **The identical bytes.** Unknown-key preservation (§7) survives because nothing is destructured on the way in or out. `ProjectStore.load` returns `body` verbatim. |
| `id`, `name`, `rev`, `schema_version` | `body.id`, `body.name`, `body.rev`, `body.schemaVersion` | Denormalized projection. |
| `artboard_w`, `artboard_h` | `body.artboard.x` / `.y` | Denormalized projection. |
| `duration_seconds`, `fps` | `body.animations[0].durationSeconds` / `.fps` | Denormalized projection. v1 writes exactly one animation (§3.1). |
| `owner_id`, `created_at`, `updated_at`, `deleted_at` | server-side | Never in `body`. Ownership and timestamps are store metadata, not document data — putting them in the wire format would leak the store into file export. |

**`body` is authoritative.** The typed columns are a denormalized projection written **in the same transaction** as `body`, purely so the planner has statistics. Any disagreement is a server bug: reads of the document always come from `body`, never reassembled from columns, and a repair job can rebuild every typed column from `body` alone.

---

## 10. Export targets

**SVG and Lottie export are v2.** Not built, not stubbed. The v1 export is the native v3 JSON above.

Decisions already made in v1 *specifically* to keep that door open at near-zero cost:

| Decision | Why it pre-pays export |
|---|---|
| Anchor tangents stored **relative to the anchor** | Literally Lottie's `i`/`o` convention. Zero conversion. |
| Colors as `[r,g,b,a]` **doubles 0..1** | Lottie's native color format. |
| Easing as **cubic bezier params**, presets lowered to numbers | Lottie only speaks cubic `o`/`i` pairs; presets would need lowering at export time otherwise. |
| `Transform2` = position / pivot / scale / rotation / skewX | Maps field-for-field onto Lottie's `ks` block (`p`/`a`/`s`/`r`/`sk`). Composition order documented and golden-tested so export cannot discover it is wrong. |
| Group children map to shape groups; **z-order is list order** | No z-index desync to reconcile at export. |
| One cubic segment type (lines are the degenerate cubic) | SVG path emission is one code path, no polyline/curve branching. |
| Vec2 **spatial** tangents separate from time easing | Lottie separates motion path from speed graph the same way; baking a polyline would have been lossy and irreversible. |
| Normalized `t` + `durationSeconds` + `fps` on the Animation | Frame numbers are `t * durationSeconds * fps` — mechanical. |

The only real export work left is: normalized `t` → frame numbers, flipping paint order, and mapping `trim` onto Lottie's trim-paths shape.

---

## Cross-links

- [00_vision_and_scope.md](00_vision_and_scope.md) — what v1 is, and the written non-goals.
- [01_domain_model.md](01_domain_model.md) — Dart types, invariants, mutation API, evaluator pipeline.
- **02_file_format.md** — this document.
