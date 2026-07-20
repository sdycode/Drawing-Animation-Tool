# v3 Tracker

⚪ not started · 🔵 in progress · 🟡 thin/stubbed · 🟢 done · 🔴 broken

**Now:** M0 · step 3 — `Document` model + artboard

| M | Feature | S |
|---|---|---|
| **M0** | Repo skeleton, `anim_core` + `anim_render` packages | 🟢 |
| | Boundary check + CI (format·analyze·test·boundaries·build) | 🟢 |
| | F12.1 Public web build on a URL | 🟡 builds; deploy parked |
| | F10.0 Auth — email/password only | 🟡 **needs console toggle** ↓ |
| | F10.1 `ProjectStore` seam + Firestore/Memory impls | 🟢 |
| | F1.1 Artboard · F1.2 `Document` id/`schemaVersion`/`rev` | ⚪ |
| | F4.1 Path creation *(thin: 3 clicks)* | ⚪ |
| | F6.1 Tracks *(thin: 2 keys)* · F9.2 8 named stages *(6 no-op)* | ⚪ |
| **M1** | F10.2 Save/load round-trip · strict decoder | ⚪ |
| | CI gate: round-trip ×8 fixtures + golden 450.2×250.4 | ⚪ |
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

**Blocked on you:** Firebase console → Authentication → Sign-in method → enable **Email/Password**. Until then sign-up returns `operation-not-allowed`.

Detail: [v3/03_features.md](v3/03_features.md) · [v3/06_roadmap.md](v3/06_roadmap.md) · isolation rules: [v3/08_feature_isolation.md](v3/08_feature_isolation.md)
