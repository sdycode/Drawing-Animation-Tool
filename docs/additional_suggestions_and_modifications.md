# Suggestions & Modifications — Legacy Flutter-Web Animation Tool

> **Subject:** `animated_icon_demo` ("Annimation") — incremental modernization plan for the **Flutter WEB app** on branch `version_2`.
>
> **Companion:** Read alongside [raw_analysis_of_old_app.md](docs/raw_analysis_of_old_app.md) (the current-state analysis). This document is **forward-looking**: what to change, why, how, and in what order.
>
> **Two hard constraints:** (1) **Web only** — android/ios are ignored. (2) **Data isolation** — keep the same Firebase project, but write all new data under a new root namespace (`appData/v2/users/…`) so existing legacy data is never touched.

## Table of Contents

- [Overview](#overview)
- [Guiding Principles](#guiding-principles-for-the-modernization)
- [Firebase Data Isolation (Do This First)](#firebase-data-isolation-do-this-first)
- [Phased Roadmap](#phased-roadmap)
- [Quick Wins](#quick-wins)
- [Prioritization Matrix](#prioritization-matrix)
- [Sequencing, Dependencies & Risks](#sequencing-dependencies--risks)
- [Detailed Recommendations by Dimension](#detailed-recommendations-by-dimension)
  - [1. Architecture & State Management](#1-architecture-state-management)
  - [2. Domain Model, Persistence & Firebase Data Isolation](#2-domain-model-persistence-firebase-data-isolation)
  - [3. Rendering, Canvas & Performance](#3-rendering-canvas-performance)
  - [4. Animation Engine & Export Format](#4-animation-engine-export-format)
  - [5. Authentication, Identity & Security](#5-authentication-identity-security)
  - [6. Editor UX & New Features](#6-editor-ux-new-features)
  - [7. Code Quality, Structure, Tooling & Testing](#7-code-quality-structure-tooling-testing)
  - [8. Web Platform, Hosting & Delivery](#8-web-platform-hosting-delivery)

---

## Overview

This document is the connective tissue of the **Suggestions & Modifications** roadmap for incrementally modernizing the Flutter **web** vector-animation editor on branch `version_2`. Eight dimension specialists (Architecture & State, Domain/Persistence, Rendering, Animation Engine, Auth/Security, Editor UX, Code Quality, Web Platform) each produced a prioritized backlog. This document does **not** re-derive their findings; it **sequences, de-conflicts, and de-risks** them into one executable plan.

### How to use this doc
- **Start with the Firebase Data Isolation plan** (next section). It is a single-line change in `lib/service/firebase_service.dart` that must land **before any other write-path work**, because it is what guarantees the product owner's hard constraint: *new v2 data is written under `appData/v2/users/{username}/Project_{n}/Project_{n}` and the legacy top-level `users` collection is never touched.*
- Then follow the **Phased Roadmap**. Each phase lists the concrete recommendations (by their specialist titles) it contains and the goal it achieves. Phases are ordered so that foundations (data isolation, state seam, repository) precede the features that depend on them.
- Use the **Quick Wins** and **Prioritization Matrix** tables to pull individual items into a sprint. The **Sequencing & Risks** section tells you what blocks what and where the big-bang vs. strangler boundaries are.

### Guiding strategy
This is **incremental modernization on `version_2`, not a rewrite**. Three constraints shape everything:
1. **Web-only.** Every change is scoped to `lib/`, `web/`, `pubspec.yaml`, CI, and Firebase config. We do not touch `android/` or `ios/`.
2. **Data-isolated.** All new persistence lands under the `appData/v2` namespace via the single `DataService().usersInstance` chokepoint. Legacy data stays read-frozen and untouched.
3. **Strangler-pattern.** A single `EditorController`/`EditorStore` seam is introduced first; globals are absorbed module-by-module behind it so the app keeps compiling and running at every commit. We never have a "big rewrite branch" that lives for weeks.

The grounding facts behind this plan were verified against the live code: the chokepoint is exactly `usersInstance = _firebaseFirestore.collection('users')` at `firebase_service.dart:6-7`; **16 live call-sites** funnel through `usersInstance`; **no** `firestore.rules`/`firebase.json` exist in the repo; and whole-collection `Source.server` reads sit at `username_page.dart:258` and `:394`.

## Guiding Principles for the Modernization

1. **Isolate data before you change behavior.** The very first commit repoints the Firestore namespace to `appData/v2`. Doing this first means every subsequent write-path experiment is automatically sandboxed away from production legacy data. Nothing else lands until the chokepoint is moved.

2. **One seam, then strangle.** Introduce exactly one new state object (`EditorController` / `EditorStore`, a `ChangeNotifier`) and one new data object (`ProjectRepository`). Initially they *proxy* the existing globals and `DataService`. New code points at the seam; old code is migrated into it module-by-module. This is the spine all eight dimensions hang off of — it is the prerequisite for undo/redo, autosave, selectors, repaint isolation, and testability.

3. **Keep the app green at every commit.** No multi-week refactor branch. Use compatibility shims (thin global getters delegating to the controller, util functions delegating to the repository) so the 244-site index chain and 16 Firestore call-sites keep compiling while they are drained.

4. **Cheap gates before expensive cleanup.** CI (format + analyze + test) and a strict lint baseline land early so that mechanical cleanup (renames, dead-code deletion, typo fixes) cannot silently regress. Tooling is a force multiplier for every later phase.

5. **Pure core, impure shell.** Push geometry, interpolation, and serialization into a Flutter-free `domain`/`core` layer so they are unit-testable. Keep Firestore, `dart:html`, and Flutter widgets at the edges behind services (`ProjectRepository`, `AuthService`, `WebPlatform`).

6. **Backward-compatible wire format.** The published `annimation` v0.0.2 player and any existing v2 docs constrain serialization. Preserve the load-bearing `"SingleFrameModel"` capital-S key, read both casings on input, stamp `schemaVersion`, and version the export contract so the engine can evolve without breaking replay.

7. **Web is the only platform — own it.** CanvasKit is pinned deliberately (Skia-bound CustomPainter workload), `dart:html` is abstracted behind `WebPlatform`, base-href is build-arg-driven, and routing/PWA/hosting are first-class, not afterthoughts.

8. **Security is sequenced, not skipped.** Rules ship immediately (deny legacy, scope v2). Real `firebase_auth` (anonymous-first) and uid re-keying come as a coherent unit *before* any public-sharing feature, because sharing without identity is a data-leak.

9. **Features compose on the foundation, never on globals.** Undo/redo, multi-select, easing, zoom/pan, and copy/paste are all deferred until the store + viewport transform exist, so each new feature is a small addition to a typed model rather than another ambient mode flag.

## Firebase Data Isolation (Do This First)

This is the **P0, S-effort, low-risk** move that satisfies the hard constraint. Because **every** Firestore read/write in the app funnels through `DataService().usersInstance` (verified: 16 live call-sites, all chaining `.doc(userName).collection('Project_$n').doc('Project_$n')` off this one field), changing where `usersInstance` points isolates the **entire** data tree in one edit. The product owner's legacy top-level `users` collection is never read or written again by v2 code.

### Target scheme
```
appData (collection)
  └─ v2 (doc)
       └─ users (collection)
            └─ {username} (doc)
                 └─ Project_{n} (collection)
                      └─ Project_{n} (doc)   ← project payload
```
Every existing downstream chain (`.doc(userName).collection('Project_$n').doc('Project_$n')`, the `UserProfile` write at the `{username}` doc, etc.) is left **completely untouched** — it simply now hangs off the v2 root.

### The one-line change (before → after)

The current code in `lib/service/firebase_service.dart` (lines 6–7):

```dart
// BEFORE — writes to the legacy top-level `users` collection
import 'package:cloud_firestore/cloud_firestore.dart';

class DataService {
  final FirebaseFirestore _firebaseFirestore = FirebaseFirestore.instance;

  late CollectionReference<Map<String, dynamic>> usersInstance =
      _firebaseFirestore.collection('users');

  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal() {}
  FirebaseFirestore get fbStore => _firebaseFirestore;
}
```

```dart
// AFTER — isolates ALL v2 data under appData/v2/users, with named constants
import 'package:cloud_firestore/cloud_firestore.dart';

class DataService {
  final FirebaseFirestore _firebaseFirestore = FirebaseFirestore.instance;

  /// Root collection that namespaces ALL application data.
  static const String kRootCollection = 'appData';

  /// Schema/namespace version. Bump (and add a new doc under [kRootCollection])
  /// only when introducing a breaking storage layout. Legacy top-level `users`
  /// is intentionally NEVER referenced.
  static const String kDataVersion = 'v2';

  /// The single Firestore chokepoint. Every read/write in the app funnels
  /// through this field, so repointing it here isolates the entire data tree.
  late CollectionReference<Map<String, dynamic>> usersInstance =
      _firebaseFirestore
          .collection(kRootCollection)   // appData
          .doc(kDataVersion)             // v2
          .collection('users');          // appData/v2/users

  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal() {}
  FirebaseFirestore get fbStore => _firebaseFirestore;
}
```

That is the whole behavioral change. The named constants document the path in exactly one place and make a future `v3` cutover a one-character edit.

### Why this is safe
- **Single chokepoint, verified.** All 16 live `usersInstance` references (in `username_page.dart`, and the `utils/*.dart` helpers `update_all_projects`, `update_project_no_list`, `get_current_project_instance`, `create_new_empty_project_with_next_id_name`, `add new methods/add_new_project`, etc.) inherit the new root automatically. No call-site edits are required.
- **Legacy is untouched, not migrated.** We do not copy, move, or delete anything under `users/**`. The old data simply stops being addressed. Existing legacy users of the *old* deployment are unaffected; the new build writes only to `appData/v2`.
- **Additive in Firestore.** Creating `appData/v2/users/...` documents does not modify sibling paths. There is no destructive operation.
- **Reversible.** Reverting the one edit restores legacy behavior instantly (though we will not — v2 is the path forward).

### Pair it with security rules (same PR)
No `firestore.rules` or `firebase.json` exist today, so the database is in default-open test mode. Ship a minimal rules file in the **same** change so the new namespace is not wide open and legacy is frozen:

```
// firestore.rules (sketch — tighten to request.auth.uid == uid once auth lands)
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {

    // Legacy data is read-frozen for the v2 app: deny everything.
    match /users/{document=**} {
      allow read, write: if false;
    }

    // v2 namespace. Pre-auth: gate by shape/path. Post-auth: gate by identity.
    match /appData/v2/users/{username}/{document=**} {
      // Phase 0 (pre-auth): allow during isolated rollout.
      // Phase 3 (post-auth): allow read, write: if request.auth.uid == username;
      allow read, write: if true;
      // Public-read carve-out for shared projects (once isPublic exists):
      // allow read: if resource.data.isPublic == true;
    }

    // Everything else denied.
    match /{document=**} { allow read, write: if false; }
  }
}
```
Reference it from a new `firebase.json`. Tighten the `appData/v2` rule to `request.auth.uid == uid` in Phase 3 when `firebase_auth` + uid re-keying lands.

### Verification steps (do these immediately after the edit)
1. **Static check:** `flutter analyze lib/service/firebase_service.dart` — confirm it compiles and `usersInstance` resolves.
2. **Grep audit:** `grep -rn "collection('users')" lib/` returns **only** the (now-changed) line context — confirm no other code constructs the legacy path directly.
3. **Run the app on web** (`flutter run -d chrome`), create a user, create a project, draw, save.
4. **Firestore console:** confirm a new document appears at `appData/v2/users/{yourName}/Project_1/Project_1` and that **no new** document appears under the top-level `users` collection. Confirm the legacy `users` tree is byte-for-byte unchanged (timestamps, doc count).
5. **Reload path:** refresh, log in with the same name, confirm the project loads back from `appData/v2`.
6. **Rules smoke test:** with the rules deployed, attempt a console-side read of legacy `users/*` from an unauthenticated client and confirm it is denied; confirm `appData/v2/users/...` reads/writes succeed.
7. **Add a regression test** (`test/data/namespace_test.dart`) asserting `DataService.kRootCollection == 'appData'` and `DataService.kDataVersion == 'v2'`, so an accidental revert fails CI.

## Phased Roadmap

Phases are ordered by **dependency and risk**: data isolation and the state/data seam come first (they unblock everything and prevent legacy corruption), then cleanup/tooling, then the rendering/animation engine, then features, then identity/sharing, then web-platform polish. Each phase ends in a shippable, green state.

### Phase 0 — Isolate, Gate, and Sweep (foundation + quick wins)
**Goal:** Guarantee data isolation, stand up CI/lint guards, and delete dead code so the true model is visible. Low risk, high leverage; unblocks safe iteration.
- *Isolate ALL v2 Firestore data under appData/v2/users via the single DataService chokepoint* (the one-line change + named constants)
- *Add Firestore security rules scoped to appData/v2 (currently none exist in repo)*
- *One-line v2 isolation* / *Switch the project-list Firestore query off Source.server* (quick wins, incl. removing whole-collection reads at username_page.dart:258/:394)
- *Add GitHub Actions CI: format + analyze + test + build web*
- *Adopt a strict lint set (very_good_analysis) with a triaged baseline*
- *Delete vestigial demo code and junk model artifacts* (lib/Animated/**, playpause, mypaint, scratch .json)
- *Delete dead/phantom/typo model files and remove their imports*
- *Remove vestigial/demo animation code that confuses the engine surface*
- *Delete dead render code* (mypaint.dart, HoverPaint) and *Strip log() and dead allocations from paint/interpolation hot paths*
- *Remove the password field and the entire-collection download* (kills the data-leak and dead `password:"password"` writes)
- *Wrap the canvas, animation preview, and each timeline thumbnail in RepaintBoundary* and *Pin the CanvasKit renderer* (cheap, large per-frame win)

### Phase 1 — State Seam & Data Layer (the spine)
**Goal:** Introduce the single `EditorController`/`EditorStore` seam and the `ProjectRepository`, then begin draining globals and the 244-site index chain. Everything later depends on this.
- *Introduce a single EditorController (ChangeNotifier) as the seam — strangler entry point*
- *Extract a ProjectRepository / data layer and make the v2 namespace switch one line* / *Introduce a ProjectRepository layer so app code never touches Firestore or builds paths directly*
- *Replace the unvalidated index tuple with derived selectors (kill the 244-site chain)*
- *Purge empty/swallowing catch blocks and replace with guarded access* (typed `currentFrameOrNull` accessors)
- *Add a schemaVersion field to Project (and stamp it on every write)*
- *Fix serialization fragility: casing trap, int/double drift, enum-as-string, and corruption-masking defaults*
- *Introduce an EditorStore with command-pattern undo/redo* (snapshot-based; the unlock for UX features) — coalesced with the EditorController as one store
- *Introduce unit tests for geometry, interpolation, and serialization* (lock the contract early)

### Phase 2 — Cleanup, Typed State & Test Pyramid
**Goal:** Finish absorbing globals into typed sub-stores, collapse the provider/updateUI mess, and pay down structural debt now that the seam exists.
- *Split state into typed sub-stores: DocumentState, SelectionState, ToolState, AnimationState, SessionState*
- *Collapse the 5 empty providers + 88 updateUI() calls into one notify path with Selector-based rebuilds*
- *Rename space-containing directories/files to snake_case (kill %20 imports)*
- *Fix baked-in identifier and file typos*
- *Define and document a target folder structure & naming convention* / *Define the target folder/layer structure (domain / data / state / presentation) and migrate into it*
- *Bump Dart SDK to 3.x and modernize/pin Firebase + other deps*
- *Add dependency injection + a minimal test harness around the new controller/repository*
- *Add widget tests for the editor shell and golden tests for painters*

### Phase 3 — Identity & Security
**Goal:** Add real auth (anonymous-first, frictionless) and re-key data by uid so the namespace is per-identity and rules can be tightened. Must precede any sharing.
- *Add firebase_auth + google_sign_in and bootstrap an auth gate (anonymous-first)*
- *Re-key all v2 data by auth uid under the isolated appData/v2 namespace*
- *Deploy Firestore security rules scoping each user to their own appData/v2 subtree* (tighten the Phase 0 rules to `request.auth.uid == uid`)
- *Add server-enforced username uniqueness via a usernames→uid mapping*
- *Add anonymous→permanent account linking and an account menu with sign-out*
- *Fix latent recursion/correctness bugs on the load path exposed once auth changes*

### Phase 4 — Rendering Pipeline & Viewport
**Goal:** Make painters pure and isolated, split static/dynamic layers, and introduce the single Matrix4 viewport — the prerequisite for zoom/pan, snapping, and crisp hit-testing.
- *Make painters pure: inject immutable data + implement real shouldRepaint*
- *Drive repaints with a Listenable model instead of notifyListeners()+rebuild*
- *Split static (grid/background) from dynamic (shapes/handles) into separate layers*
- *Memoize Paths and Offset lists; stop per-frame reallocation*
- *Introduce a single Matrix4 view transform for zoom/pan and world-space coordinates* / *Add canvas zoom & pan via a viewport transform (Matrix4) and decouple percent math from MediaQuery*
- *Replace linear ±5px AABB hit-testing with zoom-aware, bounding-box-pruned picking*
- *Unify the three duplicate painters into one parameterized renderer*

### Phase 5 — Animation Engine & Export Contract
**Goal:** Collapse to one pure interpolation engine driven by an AnimationController, add easing and an explicit time model, and version the export so the published player stays compatible.
- *Unify on one pure multi-frame interpolation engine; delete the 2-frame path*
- *Stop per-tick error dialogs and log spam inside the hot interpolation loop*
- *Add per-segment easing Curves at the single interpolation chokepoint*
- *Model time explicitly: duration, fps, and loop modes (loop / ping-pong / once)*
- *Decouple playback from editor globals and the timeline pixel position* / *Drive playback with AnimationController/Ticker, not Provider rebuilds*
- *Handle point-correspondence when bracketing frames differ in vertex count*
- *Honor curves during playback (fix dead curvePaths/closedCustomPath in playback painter)*
- *Version the export JSON and publish a documented contract shared with the annimation player* / *Version the JSON export contract and keep it decoupled from the live model*
- *Reduce per-tick allocation and gate CustomPainter.shouldRepaint*

### Phase 6 — High-Value Editor UX
**Goal:** Layer the features users feel — built on the store, viewport, and engine, so they compose instead of multiplying flags.
- *Make timeline keyframes draggable and remove build-time model mutation*
- *Per-keyframe easing curves with editable handles (replace linear-only interpolation)*
- *Copy/paste/duplicate for shapes (IconSections) and keyframes (Frames)*
- *Separate 'select tool' from 'create object', and finish the circle tool*
- *Keyboard shortcuts (Shortcuts/Actions): undo, copy/paste, delete, play, pan, tool switch*
- *Replace brittle hex-string color storage with real color + stroke/fill styling*
- *Add a playback scrubber bar with fps/duration control and onion-skinning*
- *Decompose the 684-line edit pallet monolith and fix its broken bindings*
- *Add web pointer/hover affordances: real hover highlight and correct cursors*

### Phase 7 — Web Platform, Routing & Delivery
**Goal:** Productionize the web shell: build-arg base-href, CI/CD deploy, modern bootstrap, dart:html abstraction, deep-linking, PWA/SEO.
- *Make base-href build-arg driven (remove hard-coded /Annimation/)*
- *Add a real hosting + CI/CD deploy pipeline (Firebase Hosting recommended)*
- *Modernize the bootstrap to flutter_bootstrap.js and bump the SDK to Dart 3*
- *Abstract the 3 direct dart:html imports behind a WebPlatform service*
- *Do the JSON export via the WebPlatform download service (package:web Blob+anchor)*
- *Introduce go_router for real URL routing / deep-linking*
- *Fix the PWA manifest, favicon links, SEO/meta and title mismatches*

### Phase 8 — Sharing, Responsiveness & Stretch
**Goal:** Cross-user/public features (now safe because identity + rules exist), responsive layout, and advanced engine/migration work.
- *Implement the public/private project visibility flag (designed but never built)*
- *Provide a one-time, user-initiated legacy→v2 import (coexistence, never auto-read legacy)*
- *Migrate to a single source-of-truth serialization with json_serializable (and optionally freezed)*
- *Multi-select + group transform with snapping and alignment guides*
- *Richer, reorderable component/layers tree with visibility, rename, and grouping*
- *Responsive layout beyond landscape-only with a portrait/small-screen fallback* / *Responsive layout + orientation handling*
- *Deliberate renderer + load-time/perf decision and PWA offline strategy*
- *Per-property animation tracks*; *Catmull-Rom / bezier smoothing of point PATHS*; *Stretch: interoperable export to Lottie and/or SVG SMIL*; *Evaluate Riverpod migration only AFTER globals are eliminated*; *Upgrade the templates/library*; *Replace ad-hoc debugLog/print with a single logger*

## Quick Wins

All S-effort, high-value items that can be pulled independently. Most are low-risk cleanups; a couple (delete demo code, rules) carry a "med" risk only because they touch entry points — do them under the new CI gate.

| Change | Why | Files |
|---|---|---|
| Repoint `usersInstance` to `appData/v2/users` + named constants | Isolates the entire v2 data tree in one line; legacy `users` never touched | `lib/service/firebase_service.dart` |
| Add `firestore.rules` + `firebase.json` (deny legacy, scope v2) | Closes the default-open database today | `firestore.rules`, `firebase.json` (new) |
| Delete whole-collection `Source.server` reads + dead scanning helpers | Stops leaking every user's profile to every client; cuts web reads | `lib/screens/username_page.dart:258,394` |
| Remove `password:"password"` writes + `password` field | Deletes misleading dead/insecure data | `username_page.dart:331,382`, `update_project_no_list.dart:14`, `new_full_user_model.dart` |
| Add `int schemaVersion = 1` to Project to/fromMap | Lets future migrations branch on version | `lib/drawing_grid_canvas/models/new_full_user_model.dart` |
| Read BOTH `SingleFrameModel`/`singleFrameModel` keys; coerce numbers via `(json['x'] as num?)?.toDouble()` | Stops silent geometry loss on casing/int-double drift | `new_full_user_model.dart` |
| Wrap editing CustomPaint + each timeline thumbnail in `RepaintBoundary` | Board edits stop re-rasterizing the whole timeline | `drawing_plane_widget.dart`, `temp_paint.dart`, `HorizontalTimeLinesOfAllIconsections.dart` |
| Pin CanvasKit renderer | Large per-frame win for Skia-bound CustomPainter app | run/build args or `web/index.html` |
| Delete 13 `log()` calls + showErrorDialog in hot loop | Removes string-format work + per-frame modals from play/scrub | `get_animatedpoints.dart`, controller listeners, `mypaint.dart` |
| Hoist 4 `Paint()` allocs to `static final`; resolve hex color once | Stops per-paint allocation + malformed-color crash | `polyline_paint.dart`, `temp_paint.dart` |
| Real `shouldRepaint` on BorderRectPaint / triangle pointer (compare points/revision) | Cuts per-tick repaints during scrub/play | `border_rect_paint.dart`, `trianlge_drag_pointer.dart` |
| Wrap export output in `{"schemaVersion":1, ...}` + sanitize filename | Non-breaking discriminator for versioned readers | export function, `top_bar.dart` |
| Add `easing:String='linear'` to SingleFrameModel to/fromMap | Zero behavior change; unblocks easing UI, keeps legacy JSON loadable | `new_full_user_model.dart` |
| Replace hardcoded 3000ms with `kDefaultAnimationDurationMs` constant | First step toward a real timeline model | `landscape_layout.dart`, `multi_section_animating_box.dart` |
| Delete `lib/Animated/**`, `playpause.dart`, `mypaint.dart`, scratch `.json` | ~1,700 dead lines; clarifies the true model | `main.dart` imports, `lib/Animated/`, `models/` |
| `dart fix --apply` + delete stale `test/widget_test.dart` | Auto-resolve unused imports/const/final; remove non-compiling template | whole tree, `test/` |
| Delete dead `import 'dart:html'` (zero usages) | Removes a web-lock signal | `DrawingComponentTileWidget.dart:2` |
| Remove literal `<base href="/Annimation/">`; uncomment `$FLUTTER_BASE_HREF` | Makes base-href build-arg driven | `web/index.html:17-18` |
| Fix manifest icon paths, title, description, favicon, `orientation:any` | PWA/SEO correctness | `web/manifest.json`, `web/index.html` |
| Fix height-controller bug (assigns width into height controller) | Real binding bug in the edit pallet | `edit_features_pallete_box.dart` `DrawingBoardSizeWidgetsRow.onTapUp` |
| Single-tap timeline seek; SnackBar on template-load failure + overwrite confirm | Visible UX correctness | `trianlge_drag_pointer.dart`, `librarySamples.dart` |
| Add Sign out ListTile (placeholder) + Undo/Redo buttons (disabled until store) | Wires the UI for Phase 1/3 work | `drawer.dart`, `top_bar.dart` |

## Prioritization Matrix

Top ~20 recommendations across all dimensions, sorted P0 first. Effort: S/M/L/XL. Risk: low/med/high. Items sharing a row are the same work surfaced by multiple specialists.

| Recommendation | Dimension | Priority | Effort | Risk |
|---|---|---|---|---|
| Isolate ALL v2 Firestore data under appData/v2/users via the single DataService chokepoint | Domain/Persistence | P0 | S | low |
| Add Firestore security rules scoped to appData/v2 (none exist) | Domain/Persistence + Auth | P0 | S | med |
| Remove the password field and the entire-collection download | Auth/Security | P0 | S | low |
| Add GitHub Actions CI: format + analyze + test + build web | Code Quality | P0 | S | low |
| Strip log() and dead allocations from paint/interpolation hot paths | Rendering + Animation | P0 | S | low |
| Wrap canvas, preview, and each timeline thumbnail in RepaintBoundary | Rendering | P0 | S | low |
| Pin the CanvasKit renderer for this Skia-bound workload | Rendering + Web | P0 | S | low |
| Make base-href build-arg driven (remove hard-coded /Annimation/) | Web Platform | P0 | S | low |
| Delete vestigial demo code and junk model artifacts | Code Quality | P0 | S | med |
| Introduce a single EditorController/EditorStore (strangler seam + undo/redo) | Architecture + UX | P0 | M | low/med |
| Extract a ProjectRepository / data layer (v2 switch is one line) | Architecture + Domain | P0 | M | low |
| Make painters pure: inject immutable data + real shouldRepaint | Rendering | P0 | M | low |
| Adopt a strict lint set (very_good_analysis) with a triaged baseline | Code Quality | P0 | M | med |
| Purge empty/swallowing catch blocks; replace with guarded access | Code Quality | P0 | M | med |
| Add firebase_auth + google_sign_in; auth gate (anonymous-first) | Auth/Security | P0 | M | med |
| Re-key all v2 data by auth uid under appData/v2 | Auth/Security | P0 | M | med |
| Add a real hosting + CI/CD deploy pipeline | Web Platform | P0 | M | low |
| Modernize the bootstrap to flutter_bootstrap.js and bump SDK to Dart 3 | Web Platform | P0 | M | med |
| Replace the unvalidated index tuple with derived selectors (244-site chain) | Architecture | P0 | L | med |
| Add canvas zoom & pan via a viewport transform (Matrix4) | Rendering + UX | P0 | L | med |
| Make timeline keyframes draggable; remove build-time model mutation | Editor UX | P0 | M | med |
| Unify on one pure multi-frame interpolation engine; delete 2-frame path | Animation Engine | P0 | L | med |
| Version the export JSON + documented contract shared with annimation player | Animation Engine | P0 | M | med |
| Add per-segment easing Curves at the single interpolation chokepoint | Animation Engine | P0 | M | med |

## Sequencing, Dependencies & Risks

### The critical path (what must come before what)
1. **Firebase isolation + rules → everything write-path.** The `usersInstance` repoint (P0, S) is the literal first commit. No new persistence, repository, autosave, or auth work proceeds until v2 data is namespaced and legacy is rules-frozen. This is the cheapest, highest-leverage, lowest-risk change and it satisfies the product owner's hard constraint.
2. **CI + lint baseline → all mechanical cleanup.** Renames, dead-code deletion, and typo fixes are only safe once `format + analyze + test` runs on every PR. Land CI before the file/dir renames (which are the single highest-risk cleanup, see below).
3. **EditorController/EditorStore seam → undo/redo, selectors, repaint isolation, autosave.** This one ChangeNotifier is the universal prerequisite. The architecture, UX, and rendering dimensions all converge on it. Coalesce the architecture team's `EditorController` and the UX team's `EditorStore` into **one** object to avoid two competing seams.
4. **ProjectRepository → auth re-keying, autosave, offline.** Once Firestore access is behind a typed repository, the uid re-keying in Phase 3 becomes "inject a uid" rather than editing call-sites, and autosave/offline become repository concerns.
5. **Selectors / typed sub-stores → Selector-based rebuild isolation.** Granular rebuilds require the state to be sliced first.
6. **Matrix4 viewport → zoom/pan, snapping, crisp hit-testing, sub-pixel placement.** All canvas-precision UX waits on world-space coordinates.
7. **One pure interpolation engine → easing, time model, point-correspondence, onion-skinning, scrubber.** The engine must be unified and AnimationController-driven before timeline UX is layered on; otherwise features are built on the doomed 2-frame path.
8. **Auth + uid re-keying + tightened rules → public/private sharing, deep-link viewer, legacy import.** Sharing without identity is a data leak; it is sequenced strictly after Phase 3.
9. **go_router → shareable `/editor/:projectId` deep links.** Routing precedes the share-link feature in Phase 7/8.

### Big-bang vs. strangler
- **Strangler (default for all state/data work).** The seam proxies globals, util functions delegate to the repository, and the 244-site index chain is drained file-by-file (smallest blast radius first: the 13-ref `currentSingleFrameModel`, the 16-ref `panPointIndex`). Keep thin global getters as compatibility shims so the app compiles at every commit. The 88 `updateUI()` sites migrate incrementally to one `notify()`/Selector path.
- **Engine deletion is a contained big-bang.** Unifying on one interpolation engine deletes Engine B (`multi_section_animating_box.dart`, `set_points_for_2_frames...`, `animate_points_model.dart`, and ~7 globals) wholesale. This is acceptable because the two engines are independent and Engine A already covers the multi-frame case — but it must land as one reviewed PR behind the new unit tests for `getInterPolatedPoint`/`getAnimatedPoints`.
- **Renames are a mechanical big-bang.** The space-containing dir/file renames (`Landscape Widgets` → `landscape_widgets`, killing `%20` imports) touch many imports at once. Do them as a single automated `git mv` + import-rewrite PR, with CI green before and after, so reviewers diff intent not noise.

### Highest-risk items and mitigations
- **Rename space-containing dirs/files (risk: high).** Mitigate: land CI first; do it as one mechanical PR; verify `flutter analyze` + web build before/after; no behavior change in the same PR.
- **Bump Dart SDK 3.x + Firebase core 1.x→3.x (risk: high).** Breaking major bumps; regenerate `firebase_options.dart` with `flutterfire configure` (same project, web only). Pin every dep. Do it in its own PR with the web build job gating. Web-only — never touch `android/ios`.
- **Re-key data by uid (risk: med).** Because access is behind the repository, this is "inject uid" not a sweep — but verify the anonymous→permanent **link** path preserves the uid so `appData/v2/users/{uid}` data survives sign-up. Test the guest→Google upgrade explicitly.
- **244-site selector migration (risk: med).** Drain incrementally with `elementAtOrNull`-guarded accessors; the swallowed-exception clamps are removed only after the typed accessor proves out on the low-ref files.
- **Multi-select + group transform with snapping (risk: high).** Defer to Phase 8; it depends on the store, viewport, and hit-testing all being done, and is the most invasive UX feature.
- **Per-property animation tracks / Lottie export (risk: high, XL).** Explicitly stretch — only after the v2 export contract is versioned and the engine is stable.

### Rollback safety
- The **Firebase isolation** is a one-line revert that instantly restores legacy addressing; because it is purely additive in Firestore, there is no data to clean up.
- **Rules** are deployed separately from code (`firebase deploy --only firestore:rules`) and can be reverted independently.
- Every strangler step keeps the app green, so any phase can stop at a shippable commit. The compatibility shims mean a half-migrated index chain or provider set still runs.
- The **versioned export contract** (with `schemaVersion`/`exportSchemaVersion` and dual-casing reads) guarantees old JSON and the published `annimation` v0.0.2 player keep loading through every engine change — the format only advances when a new player version ships, never silently.

---

## Detailed Recommendations by Dimension

## 1. Architecture & State Management

### The problem in one paragraph
Authoritative state does not live in Provider or the widget tree. It lives in ~41 mutable top-level globals ([drawing_grid_canvas_fields.dart](lib/drawing_grid_canvas/drawing_grid_canvas_fields.dart), [sizes_landscape.dart](lib/Landscape%20Widgets/sizes_landscape.dart), [animation_sheet.dart](lib/Landscape%20Widgets/animation_sheet.dart)), ~10 ambient enum-mode flags ([enums.dart](lib/enums/enums.dart)), three file-scope `late AnimationController`s, and static `TextEditingController`s ([text_controllers.dart](lib/controllers/text_controllers/text_controllers.dart)). The five `ChangeNotifier`s in [main.dart](lib/main.dart) are an empty "repaint now" bus. Measured on the current tree:

| Signal | Count | Meaning |
|---|---|---|
| `.updateUI()` call sites | 88 | manual, ad-hoc, often fired 2–3 at once |
| `Provider.of` | 44 | all `listen:true` rebuild subscriptions, no data |
| `Consumer` / `Selector` | 1 / 0 | zero rebuild granularity |
| stray `setState((){})` | 36 | mixed in with `updateUI` interchangeably |
| `projectList[...]` index-chain | 244 (in 40 files) | the unvalidated cursor tuple |
| `drawing_grid_canvas_fields` imported by | 55 files | the global blast radius |
| `currentProjectNo` / `IconSectionNo` / `FrameNo` refs | 284 / 182 / 106 | how deep the index addressing goes |

The current shape is `projectList[currentProjectNo].iconSections[currentIconSectionNo].frames[currentFrameNo].singleFrameModel.points`, bounds-checked only by per-`build()` clamping in [drawing_grid_canvas.dart](lib/drawing_grid_canvas/drawing_grid_canvas.dart) and empty `try/catch{}`. The eager singletons `currentProject`/`currentIconSection`/`currentFrame` dereference `projectList[currentProjectNo]` *at declaration time* — but are referenced only 2–4× each, so they are cheap to delete.

### Target architecture (incremental, not a rewrite)
A **strangler migration** around one owned controller. The key insight: have `EditorController` *initially proxy the existing globals*, so day-one behavior is identical; then absorb globals module-by-module.

```
presentation/  (screens, Landscape Widgets, painters)  ── watch/read ──►  state/
state/         EditorController (ChangeNotifier)
                 ├─ DocumentState   { List<Project> projects; int projectNo }
                 ├─ SelectionState  { iconSectionNo; frameNo; selectedPointIndex; panPointIndex }
                 ├─ ToolState       { DrawingObjectType; ShapePanORModify; ShowOuterBox; ... }  ◄─ enums.dart instances
                 └─ AnimationState  { buffers; timeLinePointerXPosition; isPlaying }
data/          ProjectRepository ─► DataService().usersInstance (appData/v2/users)
domain/        pure models + interpolation (no Flutter, no Firestore)
```

Safe selection accessor (replaces the 244-site chain and the per-build clamp):
```dart
class EditorController extends ChangeNotifier {
  Project        get project => doc.projects[doc.projectNo];
  IconSection?   get section => project.iconSections.elementAtOrNull(sel.iconSectionNo);
  SingleFrameModel? get frame => section?.frames.elementAtOrNull(sel.frameNo)?.singleFrameModel;
  void mutate(void Function() change){ change(); notifyListeners(); }  // ONE notify path, replaces 88 updateUI()
}
```

### Recommendations

| # | Priority | Effort | Risk | Recommendation |
|---|---|---|---|---|
| 1 | **P0** | M | low | Introduce `EditorController` seam that proxies globals; one `notify()` replaces the 5-way `updateUI()` dance |
| 2 | **P0** | L | med | Replace the 244-site index tuple with derived `elementAtOrNull` selectors; delete eager singletons; clamp on write |
| 3 | **P0** | M | low | Extract `ProjectRepository`; flip `usersInstance` to `appData/v2/users` (one line) |
| 4 | P1 | L | med | Split into `DocumentState`/`SelectionState`/`ToolState`/`AnimationState`/`SessionState` |
| 5 | P1 | L | med | Delete 4 empty providers; convert 88 `updateUI` → `controller.mutate`; add `Selector` at hot leaves |
| 6 | P1 | M | low | Adopt `domain/ data/ state/ presentation/` layout; rename space-containing dirs; delete dead files |
| 7 | P2 | M | low | DI via constructor + Provider; first tests (selection clamp, interpolation, repo round-trip with `fake_cloud_firestore`) |
| 8 | P2 | L | med | **Only after globals are gone**, optionally swap `EditorController` for Riverpod Notifiers |

### Migration order (why this sequence)
1. **Seam first** (P0-1): nothing to migrate *into* exists today; the controller is the prerequisite for everything else and changes no behavior.
2. **v2 isolation + repository** (P0-3): a one-line `usersInstance` change satisfies the hard product constraint; wrapping it in `ProjectRepository` decouples persistence so the in-memory refactor can't break saves. Verify with `grep -rn "collection('users')" lib` → only [firebase_service.dart](lib/service/firebase_service.dart) should match.
3. **Selectors over the index tuple** (P0-2): migrate in waves *by reference count* (panPointIndex 16 → selectedPointIndex 13 → currentFrameNo 106 → currentIconSectionNo 182 → currentProjectNo 284), `flutter analyze` + smoke-test after each file. Because the controller still proxies the same globals, each wave is behavior-preserving.
4. **Concern split** (P1-4) then **flip backing fields** from globals to private controller state — now the globals in [drawing_grid_canvas_fields.dart](lib/drawing_grid_canvas/drawing_grid_canvas_fields.dart)/[enums.dart](lib/enums/enums.dart) can be deleted.
5. **Granular rebuilds** (P1-5): wrap painters/timeline leaves in `Selector<EditorController, T>` so a polygon-side-count change no longer rebuilds the timeline. Move the three global `AnimationController`s (`newanimationController` in [landscape_layout.dart](lib/screens/landscape_layout.dart), `multianimationController`, `animationController`) into their owning `State` with a `TickerProviderStateMixin`, exposing play/pause as controller methods — removing the cross-widget `mounted`/dispose hazard.
6. **Folder moves** (P1-6) once the seam exists so moves don't fight live refactors.
7. **DI + tests** (P2-7), then **Riverpod is optional** (P2-8) — Provider + ChangeNotifier + Selector is enough to ship version-2.

### Rendering-perf payoff
Today every `notifyListeners()` rebuilds whole subtrees (1 `Consumer`, 0 `Selector`) and `shouldRepaint` is always `true` (14 painters). Routing through `controller.mutate()` + leaf `Selector`s shrinks the rebuild surface; switching the project-list query off `Source.server` to cache-then-server cuts redundant Firestore reads. This dimension's state cleanup is also the enabler for **undo/redo** (snapshot `DocumentState` in `mutate`), **autosave** (debounced `repository.saveProject` on change), and **session restore** (persist `SelectionState`) — all impossible while mutations are scattered global writes.

### Quick wins (S, do today)
- Flip `usersInstance` to `appData/v2/users` in [firebase_service.dart](lib/service/firebase_service.dart) (one line; all 19 refs inherit it).
- Delete eager singletons `currentProject`/`currentIconSection`/`currentFrame`/`currentSingleFrameModel` and `reInitSingleModel` (lines 42–118 of [drawing_grid_canvas_fields.dart](lib/drawing_grid_canvas/drawing_grid_canvas_fields.dart)).
- Delete dead/commented blocks (`framesList`, `WhichTextField` map in [enums.dart](lib/enums/enums.dart), `simple_user_model.dart`, `stucture for firestore database.dart`).
- Add a single `EditorController.notify()` and stop firing `editPalletProvider.updateUI(); drawingBoardProvider.updateUI();` pairs in [edit_features_pallete_box.dart](lib/Landscape%20Widgets/edit_features_pallete_box.dart).

## 2. Domain Model, Persistence & Firebase Data Isolation

This dimension owns the entire persisted domain tree (`UserProfile → Project → IconSection → Frame → SingleFrameModel → Point[]`), its hand-written serialization, all Cloud Firestore CRUD, and the one-click JSON export. Two thrusts: **(A) data isolation** (P0, blocking) and **(B) domain-model/serialization hardening**.

### A. Firebase Data Isolation (P0)

#### The single chokepoint
Every Firestore access in the app reaches the database through exactly one field — `usersInstance` in [firebase_service.dart](lib/service/firebase_service.dart). It is referenced in ~11 files (`grep -rln usersInstance lib/`): [update_all_projects.dart](lib/drawing_grid_canvas/utils/update_all_projects.dart), [get_current_project_instance.dart](lib/drawing_grid_canvas/utils/get_current_project_instance.dart), [add_new_project.dart](lib/drawing_grid_canvas/utils/add%20new%20methods/add_new_project.dart), [create_new_empty_project_with_next_id_name.dart](lib/drawing_grid_canvas/utils/create_new_empty_project_with_next_id_name.dart), [updateProject.dart](lib/drawing_grid_canvas/utils/updateProject.dart), [update_project_no_list.dart](lib/drawing_grid_canvas/utils/update_project_no_list.dart), [get_updated_user_profile_added_with_new_project.dart](lib/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart), [check_is_there_any_project_or_not.dart](lib/drawing_grid_canvas/utils/check_is_there_any_project_or_not.dart), [create_single_model.dart](lib/drawing_grid_canvas/utils/create_single_model.dart), and [username_page.dart](lib/screens/username_page.dart). **Because all of them suffix `.doc(userName).collection('Project_$n')` onto this one base, rebasing the base rebases everything.**

#### The one-line change
```dart
class DataService {
  static const String rootCollection = 'appData';
  static const String schemaVersion  = 'v2';

  late final CollectionReference<Map<String, dynamic>> usersInstance =
      _firebaseFirestore
          .collection(rootCollection) // 'appData'
          .doc(schemaVersion)         // 'v2'  (virtual parent doc)
          .collection('users');
}
```
Resulting layout (mirrors legacy, rooted deeper): `appData/v2/users/{username}/Project_{n}/Project_{n}`. The legacy top-level `users` collection is now unreachable from app code — nothing constructs that path anymore.

**Edge cases**
- **Virtual parent doc:** `appData/v2` has no document body (only subcollections), so it won't appear in console listings — expected, nothing reads it. Optionally `set({...}, SetOptions(merge:true))` once at boot if you want it discoverable.
- **Offline cache:** rebasing invalidates any web IndexedDB cache under the old path on first run — harmless re-fetch.
- **Ordering:** this MUST land before any v2 writes, or early data lands at the wrong path.

#### Security rules (P0 — none exist today)
`find` shows **no `firestore.rules` in the repo**; combined with no real auth (`firebase_auth` not imported, password is literal `"password"`), the DB is open. Add rules that defensively freeze legacy `users` and scope v2:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    match /users/{doc=**}          { allow read, write: if false; } // legacy freeze
    match /appData/v2/users/{u} {
      allow read, write: if true;          // TODO: tighten to request.auth post-auth
      match /{p=**} { allow read, write: if true; }
    }
    match /{document=**}           { allow read, write: if false; }
  }
}
```
Wire via `firebase.json` → `firestore.rules`, deploy with `firebase deploy --only firestore:rules`. **Tighten `if true` → `request.auth != null` in lockstep with adding `firebase_auth`** so you don't lock yourself out.

### B. Domain Model & Serialization Hardening

The single source of truth is [new_full_user_model.dart](lib/drawing_grid_canvas/models/new_full_user_model.dart) — all hand-written `fromMap`/`toMap`, no codegen. Concrete defects:

| Defect | Location | Effect |
|---|---|---|
| Casing trap: field `singleFrameModel` serialized as key `"SingleFrameModel"` | `Frame.toMap`/`fromMap` | On mismatch, falls back to **empty** `SingleFrameModel(frameNo:0)` → all geometry lost. The published `annimation` 0.0.2 reads exactly `json["SingleFrameModel"]` (verified in pub-cache) — **export contract is locked to this casing**. |
| int→double drift: `json["x"] ?? 0` into `double x` | `Point.fromMap` | Firestore int/double round-trips with wrong type. |
| Enums as raw strings | `IconSection.drawingObjectType`, `color` | `color` parsed via `Color(int.parse('0x$color'))` throws in `paint()` on malformed input; `DrawingObjectType` (`polyline/triangle/rectangle/polygon/circle`) not persisted as enum names. |
| Corruption-masking defaults | every `fromMap` (`?? "Polyline_0"`, `?? "FFFFC0CB"`, `?? 0.0`) | Bad docs decode to plausible-but-wrong data instead of failing loudly. |
| Aliasing "copy" factories | `SingleFrameModel.fromModel` is literally `return model;` | `withAllPointsButNOtFrameNo` et al. mutate the original. |

Dead/typo files to remove: [converted_songle_frame_model.dart](lib/drawing_grid_canvas/models/converted_songle_frame_model.dart) (100% commented, still imported by [cast_control_points.dart](lib/drawing_grid_canvas/utils/cast_control_points.dart)), [stucture for firestore database.dart](lib/drawing_grid_canvas/models/stucture%20for%20firestore%20database.dart) (doc-comment-only; its unimplemented public-visibility `bool` should become a real `Project.isPublic` field if that feature ships), plus `Single_Icon_Project_Model.dart`, `icon_section_model.dart`, `single_frame_model.dart`, and the stray `*.json` fixtures under `models/`.

#### Repository layer
Today path-building and CRUD are duplicated and buggy across call-sites: [updateProject.dart](lib/drawing_grid_canvas/utils/updateProject.dart) hardcodes `projectNo = 0` (always writes `Project_0`), [get_current_project_instance.dart](lib/drawing_grid_canvas/utils/get_current_project_instance.dart) has dead code after `return`, `loadAllProjectsFromServer` in [username_page.dart](lib/screens/username_page.dart) **recurses with no base case**, project numbering is a non-atomic `last+1`, and [create_new_empty_project_with_next_id_name.dart](lib/drawing_grid_canvas/utils/create_new_empty_project_with_next_id_name.dart) builds 3 sections while [add_new_project.dart](lib/drawing_grid_canvas/utils/add%20new%20methods/add_new_project.dart) builds 1. Wrap all of this in `lib/data/project_repository.dart`:
```dart
class ProjectRepository {
  final _users = DataService().usersInstance;          // the ONLY Firestore touchpoint
  DocumentReference<Map<String,dynamic>> _doc(String u, int n) =>
      _users.doc(u).collection('Project_$n').doc('Project_$n');
  Future<int> createProject(String u, Project Function(int) build) =>
      _users.firestore.runTransaction((tx) async { /* read projects, last+1, write atomically */ });
  Future<List<Project>> loadAllProjects(String u) async { /* iterative, base-case-safe */ }
  Future<void> saveProject(String u, Project p) => _doc(u, _noOf(p)).set(p.toMap());
}
```
This makes the isolation guarantee and the transactional numbering enforceable in one place, and kills the infinite-recursion and `Project_0`-overwrite bugs.

#### Versioned schema + export contract
- Add `int schemaVersion = 1` to `Project` (`'schemaVersion': schemaVersion` in `toMap`, `?? 1` in `fromMap`) so future readers can dispatch by version.
- Migrate to **json_serializable** (optionally **freezed**) with explicit `@JsonKey(name: 'SingleFrameModel')`, `@JsonValue` enums, and `num.toDouble()` coercers — generated code that can't drift. Freezed `copyWith` replaces the aliasing factories.
- Decouple export: [`exportProjectToJson()`](lib/Landscape%20Widgets/top_bar.dart) currently does `jsonEncode(project.toMap())`, so any internal change leaks into the artifact the `annimation` package replays. Introduce a versioned `export_service.dart` emitting only replay-needed fields + `exportSchemaVersion`, sanitize the filename (currently used verbatim), golden-test it against `annimation` 0.0.2, and only change emitted keys when you publish `annimation` 0.0.3.

### Recommended order
1. **P0** Repoint `usersInstance` + add security rules (S, low/med) — isolates everything, prevents legacy corruption.
2. **P1** `ProjectRepository` chokepoint + `schemaVersion` field + targeted serialization fixes (casing tolerance, num coercion, enum-by-name).
3. **P2** json_serializable/freezed migration + versioned export DTO.
4. **P3** Delete dead/typo files, rename misspelled identifiers.

## 3. Rendering, Canvas & Performance

The drawing surface is a `dart:ui` `CustomPaint` stack with no `RepaintBoundary`, no static/dynamic layer split, no view transform, and four near-duplicate painters that all `return true` from `shouldRepaint` and read mutable globals inside `paint()`. The result: any gesture fires `ProvData.notifyListeners()`, rebuilds the subtree, reallocates `List<Offset>`/`Path`/`Paint`, and repaints the board **plus every timeline thumbnail**. This section is the highest-leverage perf work in the codebase.

### 3.1 The core problem: impure painters + a global repaint bus

The live painter [`PointsLinePaint`](lib/Paints/polyline_paint.dart) reaches straight into globals from inside `paint()`:

```dart
// polyline_paint.dart — paint() reads 4 globals + deep model chain
switch (drawingType) { ...                       // global enum
  controlMidPoints.containsKey(i)                 // global map
  controlPointAdjecntPair.preIndex == i           // global pair
  color: Color(int.parse(                         // throws on bad hex, no fallback
    "0x${projectList[currentProjectNo].iconSections[...].color}"))
  if (showPoints) ...                             // global flag
}
@override bool shouldRepaint(old) => true;        // always
```

[`_TempPainter`](lib/widgets/temp_paint.dart) (timeline thumbnails) and [`_AnimatedMyPainter`](lib/widgets/animated_paint.dart) (side preview) are copy-pasted versions of the same `switch`; [`BorderRectPaint`](lib/Paints/border_rect_paint.dart) also returns `true`. The demo [`mypaint.dart`](lib/mypaint.dart) `_Painter1` is dead but still imports `dart:developer` and logs inside `paint()`. There is **zero `RepaintBoundary` in `lib/`** (`grep -rn RepaintBoundary lib/` is empty).

**Fix order (do P0 first):**

1. **Make painters pure.** Move *everything* into final constructor fields — points, `DrawingType`, resolved `Color`, `controlMidPoints`, `selectedEdge`, `showPoints` — via an immutable `ShapeRenderData` with `==`/`hashCode` or a monotonic `int revision`. Implement `shouldRepaint(old) => old.data.revision != data.revision`. Resolve the hex `Color` once in `build` with a try/catch fallback (today a malformed Firestore hex crashes inside `paint()`). Hoist the four `Paint()` to `static final`.
2. **Add `RepaintBoundary`** around the editing `CustomPaint` in [drawing_plane_widget.dart](lib/Landscape%20Widgets/drawing_plane_widget.dart) (~line 225), the [`AnimatedDrawingBoardWidget`](lib/Landscape%20Widgets/animatedDrawingBoardWidget.dart) preview, and each `TempPaint` cell (give it a `ValueKey(frame.frameNo)`). Verify with `debugRepaintRainbowEnabled = true`: only the active board should flash on a vertex drag.
3. **Repaint via `Listenable`, not rebuild.** Pass `repaint:` to the painter and bump a `ValueNotifier<int>` in `onPanUpdate` — `paint()` runs without a `build()`. Stop calling `provData.updateUI()`/`animSheetProvider.updateUI()` on the per-pixel path ([prov.dart](lib/providers/prov.dart) is an empty notify bus).

### 3.2 Layering: static vs dynamic

Today one painter draws the shape while the green board, the selected vertex (`BoxPoint`), the control midpoint, and four corner handles are `Positioned` widgets in the same `Stack` ([drawing_board_widget.dart](lib/Landscape%20Widgets/drawing_board_widget.dart)) — two rendering models for one overlay, all re-laying-out every frame. Split into three `RepaintBoundary`-wrapped `CustomPaint` layers:

| Layer | Painter | `shouldRepaint` keyed on |
|---|---|---|
| Static | `BackgroundGridPainter` (board fill, **grid lines**, snap guides) | size / zoom / grid step only |
| Shapes | `VectorPainter` (closed path + curves) | shape revision |
| Overlay | `OverlayPainter` (selected vertex, control handle, bbox, corner handles, hover) | selection/hover revision |

Note the dir is named `drawing_grid_canvas` but **nothing draws a grid** — add `for (x=0; x<=w; x+=step) canvas.drawLine(...)` in the static layer. Replace the `Positioned` `BoxPoint`/`ControlBoxPoint`/corner-handle widgets ([point_box.dart](lib/widgets/point_box.dart), [control_point_widget.dart](lib/widgets/control_point_widget.dart)) with `canvas.drawCircle` in `OverlayPainter` + one `GestureDetector` for hit-testing.

### 3.3 Memoize paths & kill per-frame allocation

Every build allocates via [`pointsToOffsets`](lib/drawing_grid_canvas/utils/points_to_offsets.dart); each `paint()` builds a fresh `Path` + four `Paint`s; `_TempPainter` also allocates a Map per thumbnail per build via `reverseCastControlPointsToIntOffset`. Cache the built `Path` and offset list on the render-data object, rebuilding only on revision change:

```dart
Path get path => _cachedPath ??= buildShapePath(points, controlMidPoints);
// invalidated only when revision changes
```

Path tessellation is the real cost on CanvasKit, so caching it across a scrub is a large win. Move thumbnail scaling (`e.x * size.width/biggerSize.width`) out of `paint()` into data prep.

### 3.4 Zoom/pan via a single Matrix4 / canvas transform

There is no zoom: precision is locked to 400×400 CSS px, points are stored as raw board pixels, and the only transform is a **dead** `Transform.rotate(angle: finalAngle * 0)` in [drawing_board_widget.dart](lib/Landscape%20Widgets/drawing_board_widget.dart). Add a `CanvasViewport { Offset pan; double zoom; }` and transform the canvas, not the data:

```dart
canvas.save(); canvas.translate(pan.dx, pan.dy); canvas.scale(zoom);
/* draw world-space shapes + grid */ canvas.restore();
// pointer -> world: world = (localPos - pan) / zoom
```

Wrap the board in `InteractiveViewer` (read its `TransformationController` Matrix4 to invert pointer coords) or drive it manually (`Listener.onPointerSignal` for zoom-to-cursor, drag/space for pan). Store points in normalized/world units so shapes become board-size-portable — this also kills the y-axis rescale bug in `reverseCastControlPointsToIntOffset` (uses width factor for y).

### 3.5 Hit-testing

[`getIndexForHoveredPointFromListofAddedPoints`](lib/drawing_grid_canvas/utils/getIndexForHoveredPointFromListofAddedPoints.dart) is a linear scan returning the **first** point inside a fixed **±5px** AABB ([check_this_point_is_inside_given_point_box.dart](lib/drawing_grid_canvas/utils/check_this_point_is_inside_given_point_box.dart)) — no zoom/DPI awareness, no overlap handling. With zoom added, a fixed pixel radius breaks. Replace with:

```dart
final r = HIT_RADIUS_PX / zoom;        // constant in screen space
// prune by inflated cornerBoxPoints AABB first
// return NEAREST by distanceSquared (no sqrt), not first match
```

Centralize the magic `5`/`3`/`-5`/`-4`/`-2` into `lib/constants/canvas_constants.dart`. A spatial bucket grid is overkill at current scale; bbox pruning suffices.

### 3.6 Web renderer: CanvasKit vs HTML

This is a pure Skia `CustomPaint` workload (many `drawLine`/`drawPath`/anti-aliased fills per frame). [index.html](web/index.html) sets **no explicit renderer**, so it falls to the default heuristic. The HTML renderer emulates canvas via DOM/CSS and janks badly on this pattern; **CanvasKit (WASM Skia)** renders natively and holds 60fps.

| | CanvasKit | HTML |
|---|---|---|
| Per-frame path perf | Excellent | Poor (DOM/CSS) |
| First-load size | +~1.5MB WASM | Light |
| Pixel accuracy | Native-identical | Approximate |

For a desktop-class editor the WASM cost is worth it. Pin it: `flutter run/build web --web-renderer canvaskit`, or on newer SDKs via the bootstrap `config: { renderer: 'canvaskit' }`. Self-host the canvaskit assets so it works under the `/Annimation/` base href.

### 3.7 Hot-path hygiene & painter unification

- [`get_animatedpoints.dart`](lib/drawing_grid_canvas/utils/Point%20methods/get_animatedpoints.dart) runs **13 `log()` calls** (several inside the per-point interpolation loop) on every scrub/play tick — delete or `assert(() { log(...); return true; }())`. Length-clamp `getInterPolatedPoint` callers so the `try/catch -> showErrorDialog` wrappers become unnecessary.
- Drive **playback** with an `AnimationController`/`Ticker` (the dead `MyPaint1` already shows the pattern) bound via `repaint:`/`AnimatedBuilder`, instead of mutating `timeLinePointerXPosition` + `updateUI()` per tick. This also enables `CurvedAnimation` easing atop the current constant-velocity lerp.
- **Unify** `PointsLinePaint` / `_TempPainter` / `_AnimatedMyPainter` (and delete `_Painter1`) into one `VectorPainter(ShapeRenderData)` over a shared `buildShapePath` helper — the copies have already drifted (thumbnail closes last→first; board does not).

### 3.8 Web pointer/hover

`MouseRegion.onHover` writes `hoverPoint` but the `setState` is commented out, so hover is invisible and [`HoverPaint`](lib/Paints/hover_paint.dart) is dead; the cursor is hardcoded `SystemMouseCursors.help`. Fold hover into `OverlayPainter` (driven by the repaint notifier, not `setState`) and set context cursors (`precise` over canvas, `grab` over a vertex, `resize*` over corner handles).

### Recommendations summary

| # | Priority | Effort | Risk | Recommendation |
|---|---|---|---|---|
| 1 | P0 | M | low | Pure painters: inject immutable data + real `shouldRepaint` |
| 2 | P0 | S | low | `RepaintBoundary` on board, preview, thumbnails |
| 3 | P0 | S | low | Strip `log()` + dead allocs from paint/interp hot path |
| 4 | P1 | M | med | Repaint via `Listenable` (`repaint:`), not Provider rebuild |
| 5 | P1 | M | low | Split static grid/bg vs dynamic shapes/overlay layers |
| 6 | P1 | M | low | Memoize `Path`/offset lists; stop per-frame realloc |
| 7 | P1 | L | med | Single Matrix4 viewport for zoom/pan + world coords |
| 8 | P1 | S | low | Pin CanvasKit renderer |
| 9 | P2 | M | low | Zoom-aware, bbox-pruned, nearest-vertex hit-testing |
| 10 | P2 | M | med | `AnimationController`/`Ticker` playback (+ easing) |
| 11 | P2 | M | low | Unify the 3 duplicate painters into one |
| 12 | P3 | S | low | Real hover highlight + correct cursors |

## 4. Animation Engine & Export Format

The runtime turns keyframes into motion via a single constant-velocity lerp, [`getInterPolatedPoint`](lib/drawing_grid_canvas/utils/get_interpolated_point.dart) — `x*(1-t)+x'*t`, no easing, no curves-in-time, no `Tween`. That primitive is driven by **two divergent engines**, several mutable globals, and a published companion package that re-implements the same pipeline for replay. This section is the plan to collapse them into one curve-aware, time-modeled, track-based engine with a versioned export contract.

### 4.1 Current shape (what we are replacing)

- **Engine A — timeline/multi-frame (the real one).** `newanimationController` (3000ms, file-scope `late`) in [landscape_layout.dart](lib/screens/landscape_layout.dart) does **not** interpolate; its listener converts `value*100` into a pixel `timeLinePointerXPosition` and `setState`s the whole screen. The morph happens on every rebuild of [animatedDrawingBoardWidget.dart](lib/Landscape%20Widgets/animatedDrawingBoardWidget.dart) -> [`getAnimatedPoints`](lib/drawing_grid_canvas/utils/Point%20methods/get_animatedpoints.dart), which round-trips px -> `0..100` percent (via `framePosPercentListForAllIconSections`) -> local `0..1`, then per-index lerps. A **triple conversion** (`controller.value -> px -> 0..100 -> local`) bound to `MediaQuery` width through `.sw`.
- **Engine B — 2-frame multi-section (the "Run Animation" button).** [`setAnimatingPointsForMultisectionsWith2frames`](lib/drawing_grid_canvas/utils/set_animating_points_for_multisections_with2_frames.dart) snapshots `frames[0]`/`frames[1]` into `frame1Points`/`frame2Points`; `multianimationController` in [multi_section_animating_box.dart](lib/widgets/multi_section_animating_box.dart) lerps between only those two, never loops, and **re-registers `addListener` on every build** (listener accumulation). Its validator `checkNoofFramesAndPointsAreCorrectForMultiSectionAnimation()` is commented out. Defaults to the magic `iconSectionNosIncludedInAnimation = [1]`.
- **Dead curve playback.** `_AnimatedMyPainter` in [animated_paint.dart](lib/widgets/animated_paint.dart) hardcodes `controlMidPoints = {}`, so `curvePaths`/`closedCustomPath` fall through to straight lines; [PointsLinePaint](lib/Paints/polyline_paint.dart) reads the **global** editor `controlMidPoints`, not interpolated ones. All playback painters `shouldRepaint => true`.
- **Per-tick hazards.** `getAnimatedPoints` reallocates every section's points + `pointsToOffsets` each frame and calls `showErrorDialog` **inside the loop** — a point-count mismatch spawns a modal every frame on web.
- **Export.** [`exportProjectToJson`](lib/Landscape%20Widgets/top_bar.dart) writes raw `project.toMap()` with **no version, no duration/fps/loop, no easing**. The published `annimation: ^0.0.2` ([libraryButton.dart](lib/Landscape%20Widgets/TopBar/libraryButton.dart)) is a byte-for-byte copy of this pipeline and the caller hardcodes `animationDuration: 2000ms`.

Notably, the cleaner N-keyframe bracketing already exists in the dead Material fork [my_animated_icons.dart](lib/Animated/my_animated_icons/my_animated_icons.dart) `_interpolate` (`targetIdx = lerpDouble(0, n-1, progress); floor/ceil; t = targetIdx - low`) — port the idea, then delete the fork.

### 4.2 Target architecture

One pure engine in a new `lib/animation/`:

```dart
class AnimationEngine {
  // global t in 0..1 from a single AnimationController.value
  List<Offset> evaluateSection(IconSection s, double t01);          // bracket -> curve -> lerp
  List<List<Offset>> sampleAll(Project p, double t01, Set<int> on); // for the painter
}
```

- Time evaluation consumes `controller.value` **directly** (no px/MediaQuery). The timeline stick becomes a *view* of `value`, not the source of truth.
- Bracket keyframes by `framePosition` (normalized to `0..1` once), compute local `t`, apply `Curve.transform(t)` from the keyframe's `easing`, then per-index lerp — easing applied to the **segment-local** t.
- Point-correspondence handled before lerp (clamp to `min(len)` now; arc-length resample later) so shapes with differing vertex counts can morph.
- Rendered under an `AnimatedBuilder(animation: controller)` scoped to the painter, ending whole-screen `setState`-per-tick.

### 4.3 Data-model changes

| Model | Add | Purpose |
|---|---|---|
| `SingleFrameModel` ([new_full_user_model.dart](lib/drawing_grid_canvas/models/new_full_user_model.dart)) | `String easing = 'linear'` (+ optional cubic `[x1,y1,x2,y2]`) | per-segment outgoing curve |
| `IconSection` | `int? vertexCount`, `SpatialInterp interp` | stable correspondence + Catmull-Rom path mode |
| `Project` | `int durationMs`, `int? fps`, `LoopMode loopMode` | explicit time model, persisted to export |
| (new) `Track<T>` / `Keyframe<T>{t,value,easing}` in `lib/animation/tracks.dart` | position/scale/rotation/color/opacity tracks | per-property animation |

All additions default to today's behavior (`'linear'`, `loopMode: once`, `durationMs: 3000`) and `fromMap` stays tolerant, so legacy v1 JSON and Firestore docs load unchanged. (DB-path isolation to `appData/v2/users` via `DataService().usersInstance` in [firebase_service.dart](lib/service/firebase_service.dart) is independent of these model changes.)

### 4.4 Controller / Ticker wiring

```dart
// ONE controller, owned by AnimSheetProvider, created once in initState
controller.duration = Duration(milliseconds: project.durationMs);
switch (project.loopMode) {
  case LoopMode.once:     controller.forward(from: 0);        break;
  case LoopMode.loop:     controller.repeat();                break;
  case LoopMode.pingPong: controller.repeat(reverse: true);   break;
}
// painting subtree:
AnimatedBuilder(animation: controller, builder: (_, __) =>
  CustomPaint(painter: PointsLinePaint(engine.sampleAll(project, controller.value, on))));
```

Replaces: file-scope `late` controllers, `addListener`-in-`build`, and the px round-trip. `shouldRepaint` compares offsets via `listEquals`.

### 4.5 Export schema + player contract

Wrap the export and version it; update the player in lockstep:

```jsonc
{ "schemaVersion": 2,
  "meta": { "app": "Annimation", "durationMs": 3000, "loopMode": "loop", "fps": 30 },
  "project": { /* IconSection -> frames -> {points, easing, controlMidPoints} or tracks */ } }
```

`Project.fromMap` branches on `schemaVersion` (absent/`1` = today's linear format). Release `annimation ^0.1.0` mirroring `_curveFor` and the unified engine, falling back to linear for v1. Commit `docs/animation_schema_v2.md` as the canonical contract. **Stretch:** a `LottieExporter` (map shape keyframes to Lottie `sh` with bezier easing handles, transform/color/opacity to `tr`/`fl`, `durationMs`/`fps` to `ip`/`op`/`fr`) for replay outside the package.

### 4.6 Recommendations (priority order)

| # | Recommendation | Priority | Effort | Risk |
|---|---|---|---|---|
| 1 | Unify on one multi-frame engine; delete Engine B + its globals | P0 | L | med |
| 2 | Kill per-tick `showErrorDialog`/`log` in the hot loop | P0 | S | low |
| 3 | Per-segment easing `Curve` at the single chokepoint | P0 | M | med |
| 4 | Version + document the export JSON; update `annimation` player | P0 | M | med |
| 5 | Explicit time model: duration/fps + loop/ping-pong | P1 | M | med |
| 6 | Decouple playback from editor globals & pixel position | P1 | L | med |
| 7 | Point-correspondence (clamp now, arc-length resample) | P1 | L | med |
| 8 | Honor curves during playback (fix dead `controlMidPoints`) | P1 | S | low |
| 9 | Per-property tracks (pos/scale/rot/color/opacity) | P2 | XL | high |
| 10 | Cut per-tick allocation; gate `shouldRepaint` | P2 | M | low |
| 11 | Delete vestigial demo trees (port `_interpolate` first) | P3 | S | low |
| 12 | Catmull-Rom spatial path smoothing | P3 | L | med |
| 13 | Stretch: Lottie / SVG SMIL export | P3 | XL | high |

**Sequencing:** land P0s (1–4) as the foundation — they unify the engine, make it safe on web, add easing, and lock the contract — then time/decoupling/correspondence/curves (5–8), then the larger track + interop work (9, 13). Quick wins (escape per-tick dialogs, add `schemaVersion:1`, add `easing:'linear'`, `min(len)` loop bound, real `shouldRepaint`) are non-breaking and can ship immediately ahead of the engine extraction.

## 5. Authentication, Identity & Security

There is **no authentication** in this app. No `firebase_auth` import exists anywhere (only `firebase_core` and `cloud_firestore` are in [pubspec.yaml](pubspec.yaml)); the typed username **is** the Firestore document id; a literal `password: "password"` is written to Firestore; and the Go path downloads the **entire** `users` collection to every client. With no rules file in the repo (the database is almost certainly in default-open test mode), any browser dev-tools user can read or overwrite any account. This section replaces the non-existent identity layer with real `firebase_auth`, re-keys all v2 data by `uid` under the isolated `appData/v2/users/{uid}` namespace, enforces username uniqueness server-side, and deploys security rules.

### 5.1 Every current security hole

| # | Hole | Evidence | Impact |
|---|------|----------|--------|
| 1 | Username is the primary key → full account takeover | `usersInstance.doc(Shared.getUserName())` in 9 sites; `.set()` upsert in [username_page.dart](lib/screens/username_page.dart) (328, 380) | Type any existing name → instantly get that account's projects |
| 2 | No auth at all | no `firebase_auth` / `FirebaseAuth` / `signInAnonymously` anywhere | No `uid`, no token, no identity to enforce on |
| 3 | Fake credential persisted | `password: "password"` in [username_page.dart](lib/screens/username_page.dart) (331, 382), [update_project_no_list.dart](lib/drawing_grid_canvas/utils/update_project_no_list.dart) (14) | Misleading dead field written to DB |
| 4 | Whole-collection leak | `usersInstance.get(Source.server)` in `getProjectsAndShowOnScreen` ([username_page.dart](lib/screens/username_page.dart):256) | Every user's profile downloaded to every client; unbounded read cost |
| 5 | No security rules in repo | no `firestore.rules` / `firebase.json` found | Open database; any web client can read/write any path |
| 6 | No uniqueness enforcement | dead, typo'd `checkIfUserLareadyExist()` never on live path | Two users can claim the same name |
| 7 | Public/private flag designed but unbuilt | "bool for visibility for public" in [stucture for firestore database.dart](lib/drawing_grid_canvas/models/stucture%20for%20firestore%20database.dart) — no field on `Project` | No principled public-read decision possible |
| 8 | Session lives only in localStorage | [shared.dart](lib/shared/shared.dart) `getUserName()` | Lost on clear-site-data / incognito / other browser |
| 9 | Latent recursion + `use_build_context_synchronously` suppressed | `loadAllProjectsFromServer()` self-recurses ([username_page.dart](lib/screens/username_page.dart):317); ignore at line 1 | Stack-overflow risk; Navigator-after-await bugs |

### 5.2 Target identity model

```
FirebaseAuth uid (immutable, server-issued)
  ├─ anonymous  → guest "just a name" UX, real uid
  ├─ email/pw   → real account
  └─ google     → real account
appData/v2/users/{uid}                         -> UserProfile { uid, userName, projects[], createdAt }
appData/v2/users/{uid}/Project_{n}/Project_{n} -> Project { ..., isPublic }
appData/v2/usernames/{lowercased_name}         -> { uid }   // uniqueness mapping
```

The `uid` becomes the key; the display name becomes mutable metadata + a uniqueness reservation. Anonymous→permanent **linking** preserves the uid (and therefore all data) when a guest upgrades.

### 5.3 Recommendations

| Priority | Effort | Risk | Recommendation |
|----------|--------|------|----------------|
| P0 | M | med | Add `firebase_auth` + `google_sign_in`; anonymous-first auth gate replacing `home: UserNamePage()` |
| P0 | M | med | Re-key all data by `uid` under `appData/v2/users/{uid}` at the single funnel point |
| P0 | S | med | Deploy `firestore.rules` scoping each user to their own subtree; freeze legacy `users/**` |
| P0 | S | low | Delete `password` field + the whole-collection `.get(Source.server)` read |
| P1 | M | med | Server-enforced username uniqueness via `usernames/{name}` mapping |
| P1 | M | low | Implement the `isPublic` project flag (default **false**) |
| P1 | M | low | Anonymous→permanent linking + account menu/sign-out in the drawer |
| P2 | S | med | Fix `loadAllProjectsFromServer()` recursion + `mounted` guards |
| P3 | M | med | Opt-in, server-side legacy→v2 import (never auto-read legacy) |

#### P0a — firebase_auth bootstrap (anonymous-first)
Add to [pubspec.yaml](pubspec.yaml): `firebase_auth: ^4.x`, `google_sign_in: ^6.x` — **note** these force `firebase_core` up from `^1.22.0` to `^2.x` and the SDK constraint up from `>=2.17.6 <3.0.0`; budget that upgrade. New `lib/service/auth_service.dart` alongside [firebase_service.dart](lib/service/firebase_service.dart):

```dart
class AuthService {
  final _a = FirebaseAuth.instance;
  Stream<User?> get authState => _a.authStateChanges();
  String get uid => _a.currentUser!.uid;
  Future<User> ensureSignedIn() async =>
      _a.currentUser ?? (await _a.signInAnonymously()).user!;
  Future<UserCredential> signInWithGoogle() {     // web
    final p = GoogleAuthProvider();
    return _a.signInWithPopup(p);
  }
  Future<void> linkEmail(String e, String pw) =>
      _a.currentUser!.linkWithCredential(EmailAuthProvider.credential(email: e, password: pw));
  Future<void> signOut() => _a.signOut();
}
```

In [main.dart](lib/main.dart) replace `home: UserNamePage()` with a `StreamBuilder<User?>(stream: AuthService().authState, ...)` gate.

#### P0b — uid re-key at the single funnel
[firebase_service.dart](lib/service/firebase_service.dart) is the choke point — change one line:

```dart
late CollectionReference<Map<String, dynamic>> usersInstance =
    _firebaseFirestore.collection('appData').doc('v2').collection('users');
```

Then grep-replace `.doc(Shared.getUserName())` → `.doc(AuthService().uid)` across the 9 call sites: [username_page.dart](lib/screens/username_page.dart), [get_updated_user_profile_added_with_new_project.dart](lib/drawing_grid_canvas/utils/get_updated_user_profile_added_with_new_project.dart), [update_project_no_list.dart](lib/drawing_grid_canvas/utils/update_project_no_list.dart), [add_new_project.dart](lib/drawing_grid_canvas/utils/add%20new%20methods/add_new_project.dart), [get_current_project_instance.dart](lib/drawing_grid_canvas/utils/get_current_project_instance.dart), [update_all_projects.dart](lib/drawing_grid_canvas/utils/update_all_projects.dart), [updateProject.dart](lib/drawing_grid_canvas/utils/updateProject.dart), [check_is_there_any_project_or_not.dart](lib/drawing_grid_canvas/utils/check_is_there_any_project_or_not.dart). The `Project_{n}/Project_{n}` subcollection layout is unchanged — only the parent key moves — so per-project code is otherwise untouched. This simultaneously satisfies the **isolation constraint** (legacy top-level `users` is never read/written).

#### P0c — security rules (the only real boundary on a client app)
New `firestore.rules` + `firebase.json`, deployed via `firebase deploy --only firestore:rules`:

```
match /databases/{db}/documents {
  match /users/{u}/{rest=**} { allow read, write: if false; }   // legacy frozen
  match /appData/v2/users/{uid} {
    allow read, write: if request.auth != null && request.auth.uid == uid;
    match /{proj}/{doc} {
      allow write: if request.auth.uid == uid;
      allow read:  if request.auth.uid == uid || resource.data.isPublic == true;
    }
  }
  match /appData/v2/usernames/{name} {
    allow read: if true;
    allow create: if request.auth != null
      && !exists(/databases/$(db)/documents/appData/v2/usernames/$(name))
      && request.resource.data.uid == request.auth.uid;
    allow update, delete: if request.auth != null && resource.data.uid == request.auth.uid;
  }
}
```

`request.auth != null` is satisfied by **anonymous** users too — guests still pass, by design.

#### P1 — uniqueness, public flag, linking
- **Uniqueness**: a `runTransaction` that reads `usernames/{lowercased}`, throws if `.uid != myUid`, else claims it and writes `userName` onto the profile. Replaces the meaningless `length > 4` check duplicated three times in [username_page.dart](lib/screens/username_page.dart).
- **Public flag**: add `bool isPublic` (default **false** — overriding the old "default true" note so existing animations aren't silently exposed) to `Project` in [new_full_user_model.dart](lib/drawing_grid_canvas/models/new_full_user_model.dart); rules already read `resource.data.isPublic`.
- **Linking + drawer**: `linkWithCredential` upgrades a guest in place (uid preserved → all data intact). [drawer.dart](lib/widgets/drawer.dart) currently has **only** social links — add an account block (display name/email, "Save your account" CTA when `currentUser.isAnonymous`, and Sign out).

#### Sequencing
P0a → P0b → P0c are a single coherent landing (auth + uid key + rules ship together, or rules will lock out a still-username-keyed client). P0d (drop `password`/whole-collection read) lands with them. P1 (uniqueness, public flag, linking/drawer) follows. P2 hardening rides along with the P0b rewrite. P3 legacy import is last and strictly opt-in.

## 6. Editor UX & New Features

The editor works, but every interaction is *index-driven in-place mutation of ~41 globals* (`projectList`, `currentProjectNo/IconSectionNo/FrameNo`, `framePosPercentListForAllIconSections`, `timeLinePointerXPosition`) routed through **empty repaint-bus** `ChangeNotifier`s (`ProvData.updateUI()` is just `notifyListeners()`). That architecture *blocks* the highest-value features. So the plan is: **first give mutations a single owner with undo and give the canvas a viewport transform**, then layer features on top so they compose instead of multiplying global flags.

### 6.1 Foundation (P0 — do these first; everything else depends on them)

| # | Recommendation | Priority | Effort | Risk |
|---|----------------|----------|--------|------|
| 1 | `EditorStore` + command-pattern undo/redo | P0 | L | med |
| 2 | Canvas zoom & pan (Matrix4 viewport) + decouple timeline math from `MediaQuery` | P0 | L | med |
| 3 | Draggable timeline keyframes; delete build-time model mutation | P0 | M | med |

**1. EditorStore with undo/redo.** Undo is impossible today because mutations happen everywhere (e.g. [pan_update.dart](lib/drawing_grid_canvas/utils/shape%20functions/pan_update.dart) writes points in-place; [insert_new_frame_at_position.dart](lib/drawing_grid_canvas/utils/insert_new_frame_at_position.dart) hand-edits three caches). Create `lib/editor/editor_store.dart` owning the `Project` + selection cursors, with every mutation wrapped in an `EditorCommand{apply,revert}`. Start snapshot-based using the existing round-trip in [new_full_user_model.dart](lib/drawing_grid_canvas/models/new_full_user_model.dart):

```dart
void beginEdit(String label){ _before = section.toMap(); }
void commit(){ _push(SnapshotCommand(sectionIndex, _before, section.toMap())); notifyListeners(); }
// undo(): section = IconSection.fromMap(cmd.before)
```

Wire gesture handlers to `beginEdit`(onPanStart)/`commit`(onPanEnd). Keep `projectList` as the store's backing field and leave global getters as a shim so existing files compile during migration.

**2. Zoom & pan.** Points are raw px and the percent↔px helpers ([getActualStickserPositionFromPercentValue.dart](lib/drawing_grid_canvas/utils/numeric%20funtions/getActualStickserPositionFromPercentValue.dart), [getPercentValueForStickPosition.dart](lib/drawing_grid_canvas/utils/numeric%20funtions/getPercentValueForStickPosition.dart)) multiply by `MediaQuery.size.width/100` ([extensions.dart](lib/extensions.dart) `.sw`), so resizing reflows every dot and there is no way to zoom in for detail. Add `CanvasViewport{pan,scale}` on the store; apply a `Matrix4` to the painter in [drawing_board_background_box.dart](lib/Landscape%20Widgets/drawing_board_background_box.dart)/[drawing_board_widget.dart](lib/Landscape%20Widgets/drawing_board_widget.dart) and inverse-map pointer events to scene space before hit-testing. Ctrl+scroll = zoom, space+drag = pan, zoom-to-fit button in [top_bar.dart](lib/Landscape%20Widgets/top_bar.dart). Replace the context-bound timeline conversions with a `TimeScale{pxPerPercent}` computed once per layout.

**3. Draggable keyframes + kill build-time mutation.** In [HorizontalTimeLinesOfAllIconsections.dart](lib/Landscape%20Widgets/Anim_sheet_widgets/HorizontalTimeLinesOfAllIconsections.dart) dots are tap-to-select only, and `build()` force-writes `frames.first.framePosition=0`/`frames.last=100` every repaint inside `try/catch → showErrorDialog` (a setState-during-build hazard that silently rewrites persisted data). Replace each dot's `InkWell` with `onHorizontalDragUpdate` writing `framePosition` (clamped between neighbors), via a store command. **Delete the pinning block**; enforce the 0/100 endpoint invariant once at insert/delete time. Make `framePosPercentListForAllIconSections` a *derived* getter to kill the three-way desync flagged in analysis 8.7.

### 6.2 High-value features (P1)

| # | Recommendation | Effort | Risk |
|---|----------------|--------|------|
| 4 | Per-keyframe easing curves (replace linear-only lerp) | M | med |
| 5 | Copy/paste/duplicate of shapes & frames | M | low |
| 6 | Separate tool-select from object-create; **finish circle tool** | M | med |
| 7 | Keyboard shortcuts (Shortcuts/Actions) | M | low |
| 8 | Real color + stroke/fill styling (replace hex-string surgery) | M | med |
| 9 | Multi-select + group transform + snapping/guides | L | high |

**4. Easing.** [get_interpolated_point.dart](lib/drawing_grid_canvas/utils/get_interpolated_point.dart) is pure linear `x*(1-t)+x'*t`. Add `String easing` to `SingleFrameModel` (default `'linear'`, written only when non-default for back-compat with the external `annimation` package). In [get_animatedpoints.dart](lib/drawing_grid_canvas/utils/Point%20methods/get_animatedpoints.dart), transform the local `t` through Flutter `Curves` (easing belongs to the *segment leaving the previous keyframe*; add a `hold` step mode).

**5. Copy/paste/duplicate.** Nothing duplicates today; the tile menu in [DrawingComponentTileWidget.dart](lib/Landscape%20Widgets/DrawingCompoents/DrawingComponentTileWidget.dart) only offers Show/Hide Outer Box + Delete. Add **Duplicate section** (`IconSection.fromMap(toMap())`), **Duplicate frame** (clone `singleFrameModel`), and a store clipboard for Ctrl+C/V across sections. Fix `insertNewFrameAtPosition` to clone via the full map (it currently `List.from(points)` only, losing `cornerBoxPoints`/`boxSize`).

**6. Tool vs. create; circle.** In [drawingObjectbutton.dart](lib/Landscape%20Widgets/TopBar/drawingObjectbutton.dart), picking triangle/rectangle/polygon immediately calls `addNewIconSectionPolygon(3)`/`addNewIconSectionAsRectangle()`/`addNewIconSectionPolygon(5)` — *tool selection and object creation are conflated*, and `DrawingObjectType.circle` is a dead branch (menu entry commented out, switch sets the enum but creates nothing). Make the selector set only the active tool; create on first canvas drag. Implement `addNewIconSectionCircle()` reusing the polygon pipeline ([create_polygon_points_from_corner_points.dart](lib/drawing_grid_canvas/utils/Point%20methods/create_polygon_points_from_corner_points.dart)) as a high-N polygon for morphing, while the painter draws a true `drawOval` for crispness; re-enable the commented circle map entries.

**7. Keyboard shortcuts.** None exist. Wrap [landscape_layout.dart](lib/screens/landscape_layout.dart) in `Shortcuts`+`Actions`+`FocusableActionDetector`: Ctrl+Z/Shift+Z (undo/redo), Ctrl+C/V/D (copy/paste/duplicate), Delete (remove point/section), Space (play/pause `newanimationController`), V/H (modify/pan = `shapePanORModify`), 1–5 (tools), +/− (zoom). Guard against firing while an `EditableText` holds focus.

**8. Styling.** Color is a hex `String` (`"FFFFC0CB"`) parsed via `Color(int.parse("0x$color"))` and written back with `d.toString().replaceAll(')','').split('x')[1]` in [edit_features_pallete_box.dart](lib/Landscape%20Widgets/edit_features_pallete_box.dart) — brittle string surgery, and there is **no stroke width or fill toggle**. Add `int colorValue`, `double strokeWidth`, `bool filled` to `IconSection` (migrate the legacy hex in `fromMap`), set `colorValue = picked.value`, and thread style into [polyline_paint.dart](lib/Paints/polyline_paint.dart)/[border_rect_paint.dart](lib/Paints/border_rect_paint.dart). Gradient is a P2 follow-on.

**9. Multi-select + snapping.** Only one point (`selectedPointIndex`) or section edits at a time. Add marquee selection into `EditorStore.selection`, a group bounding-box (reuse [get_box_corner_points_for_numerousPoints.dart](lib/drawing_grid_canvas/utils/Point%20methods/get_box_corner_points_for_numerousPoints.dart)) supporting translate/scale, and grid-snap + alignment guides (reuse [threshold_extension.dart](lib/extension/extensions%20on%20number/threshold_extension.dart) for snap distance, in scene-space thanks to rec #2). Highest value but riskiest — touches hit-testing.

### 6.3 Polish & reach (P2–P3)

| # | Recommendation | Priority | Effort | Risk |
|---|----------------|----------|--------|------|
| 10 | Playback scrubber: loop/duration/fps, time readout, onion-skin | P2 | M | low |
| 11 | Decompose 684-line edit pallet + fix broken bindings | P2 | M | low |
| 12 | Richer reorderable layers tree (rename/visibility/lock/z-order) | P2 | M | med |
| 13 | Responsive layout beyond landscape-only | P2 | M | med |
| 14 | Library upgrade: surface errors, manifest catalog, insert-as-new, import | P3 | M | low |

**10. Playback.** Fixed 3000ms controller, only Play/Stop in [icon_sections_tree_in_animsheet.dart](lib/Landscape%20Widgets/Anim_sheet_widgets/icon_sections_tree_in_animsheet.dart), one global playhead. Add loop toggle, configurable duration/fps (persisted on `Project`), time readout, pause, click-to-seek on [trianlge_drag_pointer.dart](lib/Landscape%20Widgets/Anim_sheet_widgets/trianlge_drag_pointer.dart), and onion-skin (faint prev/next outlines in the canvas painter).

**11. Edit-pallet decomposition.** [edit_features_pallete_box.dart](lib/Landscape%20Widgets/edit_features_pallete_box.dart) (684 lines) has concrete bugs: unreachable code after `return` in `getEditPalletForSelectedItem`; the H stepper assigns **width** into the height controller (`drawingaBoard_height_posController.text = drawingBoardSize.width...`); typed input only writes board X/Y + angle (W/H/Sides typing is a no-op); static [text_controllers.dart](lib/controllers/text_controllers/text_controllers.dart) singletons never disposed and drift. Split into reusable bound `NumberField`/`ColorField`/`EasingField`/`StrokeField` widgets; this is also where the new style/easing controls land.

**12. Layers tree.** [drawing_components_tree_box.dart](lib/Landscape%20Widgets/drawing_components_tree_box.dart) is a flat list with no rename, visibility, lock, or z-order. Add inline rename, eye/lock toggles (`visible`/`locked` on `IconSection`), and `ReorderableListView` controlling paint order. Track section *identity* (not raw index) in `iconSectionIndexesToIncludeInAnimationList` so reorder doesn't scramble which sections play.

**13. Responsive.** The fixed `Positioned` Stack assumes landscape ("Landscape" is a name, not an enforcement). Wrap in `LayoutBuilder`; on narrow widths collapse the tree/pallet into drawers and dock the timeline, maximizing the canvas. Pairs with removing `MediaQuery` from timeline math (rec #2).

**14. Library.** [librarySamples.dart](lib/Landscape%20Widgets/librarySamples.dart) hardcodes 4 paths, **overwrites** `projectList[currentProjectNo]` on *Go* (data loss), and swallows every error in `catch(e){}` (`showErrorDialog` is a no-op). Insert templates as *new* projects, surface errors via SnackBar, drive the catalog from `assets/library/index.json`, and add JSON import (`file_picker`) to round-trip with `exportProjectToJson`. Keep all writes under the v2 isolation namespace via `DataService().usersInstance` in [firebase_service.dart](lib/service/firebase_service.dart).

### 6.4 Quick wins (S, do today)
- Delete the build-time `framePosition` pinning block + dead `Positioned(left:i*50…)` branch in [HorizontalTimeLinesOfAllIconsections.dart](lib/Landscape%20Widgets/Anim_sheet_widgets/HorizontalTimeLinesOfAllIconsections.dart).
- Fix the H-stepper width/height bug in [edit_features_pallete_box.dart](lib/Landscape%20Widgets/edit_features_pallete_box.dart).
- Make the playhead seek on tap, and `shouldRepaint` compare fields instead of returning `true` ([trianlge_drag_pointer.dart](lib/Landscape%20Widgets/Anim_sheet_widgets/trianlge_drag_pointer.dart)).
- Replace the silent `catch(e){}` + overwrite in the Library *Go* button with a SnackBar + confirm.
- Add disabled Undo/Redo buttons to [top_bar.dart](lib/Landscape%20Widgets/top_bar.dart) now, wired to `EditorStore` when rec #1 lands.

### 6.5 Sequencing
Ship **#1 → #2 → #3** as the foundation, then the P1 cluster in order of dependency (#5/#7 are nearly free once #1 exists; #4/#8 need only the model + store; #9 needs #2). #11 should precede #4/#8 so new controls have a clean home. #6's circle should be validated against the external `annimation` package before exposing it in Export.

## 7. Code Quality, Structure, Tooling & Testing

The codebase is functional but carries the textbook signature of a long-lived solo prototype: spaces and typos baked into file names and public identifiers, ~1,700 lines of dead demo code still imported, 30 mostly-empty `catch (e) {}` blocks masking **251** unguarded `projectList[...]` index-chain dereferences, the *default* lint set with every custom rule commented out, a Dart-2-era SDK pin, and **zero** real tests. The strategy below is ordered so each step lands behind a safety gate: **CI + strict lints first** (cheap, stops regression), **then** mechanical renames/deletes, **then** the typed-access and toolchain changes, **then** the test pyramid.

### 7.1 Priorities at a glance

| # | Recommendation | Priority | Effort | Risk |
|---|----------------|----------|--------|------|
| 1 | GitHub Actions CI (format + analyze + test + build web) | P0 | S | low |
| 2 | Strict lints via `very_good_analysis` + triaged baseline | P0 | M | med |
| 3 | Delete vestigial demo code + junk `.json` artifacts | P0 | S | med |
| 4 | Purge empty/swallowing catches; add guarded accessors | P0 | M | med |
| 5 | Rename space/PascalCase files & dirs to snake_case | P1 | M | high |
| 6 | Fix baked-in identifier/file typos | P1 | M | med |
| 7 | Define target folder structure & naming convention | P1 | M | med |
| 8 | Unit tests: geometry / interpolation / serialization | P1 | L | low |
| 9 | Widget tests (editor) + golden tests (painters) | P2 | L | med |
| 10 | Bump Dart SDK to 3.x; modernize/pin Firebase + deps | P1 | L | high |
| 11 | Single logger; remove `debugLog`/stray prints | P3 | S | low |

### 7.2 Tooling gate first (P0)

There is no `.github/` and [analysis_options.yaml](analysis_options.yaml) only does `include: package:flutter_lints/flutter.yaml` with **all** custom rules commented out. Add CI and strict lints before touching code so every later PR is provably non-regressing.

```yaml
# .github/workflows/ci.yml (sketch)
jobs:
  verify:
    steps:
      - uses: subosito/flutter-action@v2   # channel: stable, version pinned to .metadata
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze            # add --fatal-infos once baseline is clean
      - run: flutter test
  build_web:                            # separate job; may fail during the dep bump
      - run: flutter build web --base-href /
```

For lints: `flutter pub add --dev very_good_analysis`, switch the `include`, then promote the issues this dimension cares about to hard errors:

```yaml
analyzer:
  errors:
    empty_catches: error      # the 30 catch (e) {} blocks
    unused_import: error
    dead_code: error
  exclude:
    - "**/*.g.dart"
    - "lib/Animated/**"       # until deleted in task 3
```

Run `dart fix --apply` once to mechanically clear unused imports / `prefer_const` / `prefer_final`, then triage the remainder rule-by-rule before flipping `--fatal-infos` on in CI.

### 7.3 Delete dead weight (P0)

[main.dart](lib/main.dart) imports an entire Material-`AnimatedIcon` fork only for a splash `AnimatedSwitcher`:

- `lib/Animated/**` — 4 files, incl. an **821-line** `play_pause.g.dart` and a **304-line** `my_animated_icons.dart`
- [playpause.dart](lib/playpause.dart), [play_pause_points.dart](lib/play_pause_points.dart), [mypaint.dart](lib/mypaint.dart) (419 lines, a duplicate `_Painter1` of the live painters)
- scratch fixtures in models/: `a.json`, `projectmodel.json` (empty), `singleframemodel.json`, `userModel.json`

`grep -rl` confirms the only live importers are `main.dart`, `drawing_grid_canvas.dart`, and `drawing_plane_widget.dart`. Excise the imports + the splash use site, salvage the two non-empty `.json` files into `test/fixtures/` for the serialization tests, then delete. Also delete the stale [test/widget_test.dart](test/widget_test.dart) — it asserts a counter UI that does not exist and cannot compile.

### 7.4 Kill the index-chain crashes (P0)

The analysis's #2 risk: **251** `projectList[currentProjectNo].iconSections[...].frames[...]` chains, bounds-checked only opportunistically, with **30** `} catch` blocks (several literally `catch (e) {}`) swallowing the resulting `RangeError`s. Introduce nullable accessors at the existing chokepoint [get_current_project_instance.dart](lib/drawing_grid_canvas/utils/get_current_project_instance.dart):

```dart
Project?     get currentProjectOrNull => projectList.elementAtOrNull(currentProjectNo);
IconSection? get currentSectionOrNull => currentProjectOrNull?.iconSections.elementAtOrNull(currentIconSectionNo);
Frame?       get currentFrameOrNull   => currentSectionOrNull?.frames.elementAtOrNull(currentFrameNo);
```

Convert the long chains to null-aware access through these; keep `try/catch` **only** at true I/O boundaries (Firestore in [firebase_service.dart](lib/service/firebase_service.dart), file export) and there log via the new logger instead of swallowing. This makes `empty_catches: error` enforceable.

### 7.5 Renames: files, dirs, identifiers (P1)

Thirteen directories/files contain spaces, forcing fragile `%20`-encoded imports, plus PascalCase/camelCase filenames and capitalized dirs. Do this as **isolated, behavior-free** PRs after CI exists.

| Current (wrong) | Rename to |
|---|---|
| `lib/Landscape Widgets/` | `lib/landscape_widgets/` |
| `.../utils/add new methods/` | `.../utils/add_new_methods/` |
| `.../utils/Point methods/` | `.../utils/point_methods/` |
| `.../utils/numeric funtions/` | `.../utils/numeric_functions/` |
| `.../models/stucture for firestore database.dart` | delete (notes) or `firestore_schema.dart` |
| [DrawingComponentTileWidget.dart](lib/Landscape%20Widgets/DrawingCompoents/DrawingComponentTileWidget.dart) | `drawing_component_tile_widget.dart` |
| [trianlge_drag_pointer.dart](lib/Landscape%20Widgets/Anim_sheet_widgets/trianlge_drag_pointer.dart) | `triangle_drag_pointer.dart` |
| [curretn_time_vertical_stick.dart](lib/Landscape%20Widgets/Anim_sheet_widgets/curretn_time_vertical_stick.dart) | `current_time_vertical_stick.dart` |
| [converted_songle_frame_model.dart](lib/drawing_grid_canvas/models/converted_songle_frame_model.dart) | `converted_single_frame_model.dart` |

Identifier typos (rename-symbol or `sed` where the analyzer can't): `getNewPorjectNo`→`getNewProjectNo` ([fileButton.dart](lib/Landscape%20Widgets/TopBar/fileButton.dart), [add_new_project.dart](lib/drawing_grid_canvas/utils/add%20new%20methods/add_new_project.dart)), `update_projctno_list`→`updateProjectNoList`, `ControlPointAdjecntPair`→`ControlPointAdjacentPair` (used across 5+ files incl. [new_full_user_model.dart](lib/drawing_grid_canvas/models/new_full_user_model.dart)), `checkIfUserLareadyExist`→`checkIfUserAlreadyExists`. Use `git mv` to preserve history; verify each batch with `flutter analyze` (zero unresolved URIs). Fold the snake_case→`lowerCamelCase` member conversions into the `non_constant_identifier_names` lint pass so files are touched once.

### 7.6 Target structure (P1)

Carve out a Flutter-free `lib/src/core/` for the pure code — this is both the cleaner layering **and** the unit-test target:

```
lib/src/
  core/            # NO flutter imports → unit-testable in isolation
    geometry/      # from utils/Point methods, geometric functions
    interpolation/ # from get_interpolated_point.dart
    serialization/ # toMap/fromMap, the SingleFrameModel key-casing trap
    constants/     # merge Global/constants.dart + 'constants/math constants.dart'
  data/            # firebase_service, repositories
  ui/              # widgets, screens, painters
```

Add `docs/structure.md` + a `CONTRIBUTING.md` rule (snake_case files, `lowerCamelCase` members, no spaces) and a small CI guard that fails on any space/uppercase path under `lib/` so the drift cannot recur. Keep this incremental: relocate the pure modules first; leave the widgets until the state-management refactor (dimension on state) moves them.

### 7.7 Test pyramid from zero (P1–P2)

Start where ROI is highest — the deterministic, side-effect-free functions:

- **Unit (P1)** — `test/core/`: `get_interpolated_point.dart` (lerp endpoints + midpoint), `create_polygon_points_from_corner_points.dart`, `angle_between3_points.dart`, `getCenterPointForBoxCornerPoints.dart`; **serialization round-trips** `fromMap(toMap(x)) == x` plus a **regression test pinning the `singleFrameModel` ↔ `'SingleFrameModel'` key-casing trap** so any future fix is deliberate. Seed from the salvaged `singleframemodel.json` / `userModel.json` fixtures.
- **Contract (P1)** — a golden JSON fixture matching what the published `annimation` replay package expects, asserted in CI so refactors can't silently break export/replay.
- **Widget (P2)** — `editor_smoke_test.dart` pumps `landscape_layout` with a seeded `projectList` fixture and asserts *no exception* (directly catches the index-chain crashes the empty catches hide). Requires the state to be seedable, which usefully pressures the state refactor toward injectability.
- **Golden (P2)** — render `PolylinePaint`/`border_rect_paint`/`hover_paint` at fixed sizes via `matchesGoldenFile`; pin one Flutter version in CI (rendering varies across versions) and store baselines under `test/golden/`. Defer until painters are made pure (constructor-injected inputs, real `shouldRepaint`) per the rendering dimension.

### 7.8 Toolchain & dependency modernization (P1)

`environment.sdk: ">=2.17.6 <3.0.0"` blocks Dart 3 (records/patterns/sealed classes — directly useful for the Shape and state refactors). Resolved versions are years behind: `firebase_core 1.22.0` (current 3.x), `cloud_firestore 3.4.8` (current 5.x), and `provider`/`cloud_firestore` are **unpinned** in [pubspec.yaml](pubspec.yaml) (non-reproducible builds); `file_saver 0.1.1` and the deprecated `url_launcher.launch()` are stale.

Sequence to contain the high risk — one major bump per PR, CI green between each:

1. `sdk: ">=3.3.0 <4.0.0"` + `dart fix` for 2→3 deprecations.
2. `firebase_core ^3.x` / `cloud_firestore ^5.x` — the **only** Firestore touchpoint is `DataService().usersInstance` in [firebase_service.dart](lib/service/firebase_service.dart), so API churn is one file; combine with the version-2 isolation (`appData/v2/users`) here. Regenerate [firebase_options.dart](lib/firebase_options.dart) via `flutterfire configure`.
3. `url_launcher` `launch()` → `launchUrl(Uri.parse(...))`; pin `provider ^6.x`, `shared_preferences`, `file_saver`, and `annimation` explicitly.

All changes are web-only; `android/` and `ios/` are out of scope. Verify `flutter build web` in CI after each step.

### 7.9 Logging (P3)

Replace the bespoke `debugLog` shim ([debugLog.dart](lib/utils/text_field_methods/debugLog.dart)) and any stray `print()` (which `avoid_print` will flag) with a single `package:logging` logger gated on `kReleaseMode`. This gives the now-non-empty catch handlers a real sink — pairing directly with task 7.4.

## 8. Web Platform, Hosting & Delivery

This dimension covers everything between the Dart code and the browser: the boot shell, base-href, renderer, PWA manifest, URL routing, the `dart:html` surface, file download, and the (currently nonexistent) deploy pipeline. The app is a public Flutter **web** editor, so these are first-class concerns — yet today it is hand-deployed to a single GitHub Pages subpath with a hard-coded base href, a pre-Flutter-3 bootstrap, broken PWA icons, no URL routing, and three direct `dart:html` imports riding a deprecated library.

All recommendations are web-only and orthogonal to the Firestore `appData/v2/users/...` isolation (a one-line change in [firebase_service.dart](lib/service/firebase_service.dart) `DataService.usersInstance`).

### Current state (load-bearing facts)

- **Hard-coded base href.** [web/index.html](web/index.html) line 18: `<base href="/Annimation/">`; the standard `$FLUTTER_BASE_HREF` token (line 17) is present but commented out. Pins the build to one Pages subpath.
- **Legacy bootstrap.** [web/index.html](web/index.html) lines 35-56 use `_flutter.loader.loadEntrypoint(...)` + `var serviceWorkerVersion = null` + `flutter.js` (pre-`flutter_bootstrap.js`), matching the Dart-2 SDK pin `>=2.17.6 <3.0.0` in [pubspec.yaml](pubspec.yaml) line 21.
- **Three `dart:html` imports**, of which only two are live:
  - [top_bar.dart](lib/Landscape%20Widgets/top_bar.dart):280 — `html.window.open('https://youtu.be/m_NibA9HXW8', "_blank")`
  - [drawing_components_tree_box.dart](lib/Landscape%20Widgets/drawing_components_tree_box.dart):36 — `html.document.onContextMenu.listen((e) => e.preventDefault())` (right-click suppression for the canvas menu)
  - [DrawingComponentTileWidget.dart](lib/Landscape%20Widgets/DrawingCompoents/DrawingComponentTileWidget.dart):2 — **dead import**, zero `html.` usages.
- **No routing.** Project selection sets the global `currentProjectNo` and calls `Navigator.pushReplacement(MaterialPageRoute(... LandscapeLayoutScreen()))` ([username_page.dart](lib/screens/username_page.dart):155/424, [top_bar.dart](lib/Landscape%20Widgets/top_bar.dart):68, [fileButton.dart](lib/Landscape%20Widgets/TopBar/fileButton.dart):72, [showProjecListInDialog.dart](lib/Landscape%20Widgets/TopBar/showProjecListInDialog.dart):46). The URL never changes; refresh dumps the user back to `/`.
- **Broken/contradictory PWA.** [manifest.json](web/manifest.json) references `icons/Icon-192.png`, `icons/Icon-512.png`, `icons/Icon-maskable-*.png` — but `web/icons/` actually contains `android-chrome-192x192.png`, `android-chrome-512x512.png`, `apple-touch-icon.png` (all manifest icon paths are broken). `name`/`short_name` are still `animated_icon_demo`; description is `A new Flutter project.`; `orientation: "portrait-primary"` contradicts the landscape-only fixed-pixel Stack. [web/index.html](web/index.html) `<title>` is `animated_icon_demo`; favicon/apple-touch point at `logo.png` while `web/favicon.png` is unused.
- **Export.** `exportProjectToJson()` ([top_bar.dart](lib/Landscape%20Widgets/top_bar.dart):299-309) uses `file_saver: ^0.1.1` (very old pin).
- **No hosting/CI.** No `.github/`, no `firebase.json`/`.firebaserc` — deploy is manual.

### Recommendations

| # | Title | Priority | Effort | Risk |
|---|-------|----------|--------|------|
| 1 | Base-href build-arg driven (remove `/Annimation/`) | P0 | S | low |
| 2 | Hosting + CI/CD pipeline (Firebase Hosting / Pages) | P0 | M | low |
| 3 | Modernize bootstrap → `flutter_bootstrap.js` + Dart 3 SDK | P0 | M | med |
| 4 | Abstract `dart:html` behind a `WebPlatform` service | P1 | M | med |
| 5 | `go_router` routing / deep-linking | P1 | L | med |
| 6 | JSON export via `package:web` download service | P1 | S | low |
| 7 | Fix manifest / favicon / SEO / title | P1 | S | low |
| 8 | Responsive + orientation handling | P2 | L | med |
| 9 | Renderer (CanvasKit) + load-time + PWA offline strategy | P2 | M | low |

#### P0 — Base href, hosting, bootstrap (do first, unblock everything else)

**1. Base-href at build time.** Delete line 18 of [web/index.html](web/index.html), uncomment line 17 (`<base href="$FLUTTER_BASE_HREF">`), and let the build inject it:

```bash
# GitHub Pages subpath
flutter build web --release --base-href=/Annimation/
# Firebase Hosting root
flutter build web --release --base-href=/
```

**2. Pipeline.** Prefer **Firebase Hosting** (same project `animate-widget-tool`; serves at root → base-href `/`; SPA rewrites for deep links; preview channels). Add:

```jsonc
// firebase.json
{ "hosting": { "public": "build/web",
    "rewrites": [{ "source": "**", "destination": "/index.html" }] } }
```

`.github/workflows/deploy.yml`: `subosito/flutter-action@v2` (pinned 3.x) → `flutter build web --release --base-href=/ --pwa-strategy=offline-first` → `FirebaseExtended/action-hosting-deploy@v0` (PR previews + live on merge). GitHub Pages fallback: build `--base-href=/Annimation/`, add a `404.html` copy of `index.html` (SPA shim for deep links), push `build/web` to `gh-pages`.

**3. Bootstrap + SDK.** Replace the inline `_flutter.loader.loadEntrypoint(...)` block and `serviceWorkerVersion`/`flutter.js` tags with the modern single entry:

```html
<body><script src="flutter_bootstrap.js" async></script></body>
```

Bump [pubspec.yaml](pubspec.yaml) to `sdk: ">=3.4.0 <4.0.0"`, `firebase_core: ^3.x` + matching `cloud_firestore`, regenerate [firebase_options.dart](lib/firebase_options.dart) via `flutterfire configure` (web only). Diff a fresh `flutter create --platforms web` to pick up the new scaffold while keeping custom meta/manifest links. This is the keystone — go_router, `package:web`, and current Firebase all require Dart 3.

#### P1 — Platform abstraction, routing, export, metadata

**4. `WebPlatform` service.** Create `lib/platform/web_platform.dart` with `openInNewTab`, `suppressBrowserContextMenu`, `downloadBytes`, behind conditional imports:

```dart
import 'web_platform_stub.dart'
    if (dart.library.js_interop) 'web_platform_web.dart';
```

Implement the web side with `package:web/web.dart` + `dart:js_interop` (`web.window.open`, `web.document.onContextMenu.listen`). Replace the call sites; **delete the dead import** at [DrawingComponentTileWidget.dart](lib/Landscape%20Widgets/DrawingCompoents/DrawingComponentTileWidget.dart):2; move the YouTube link in [top_bar.dart](lib/Landscape%20Widgets/top_bar.dart):280 to `url_launcher` (as [drawer.dart](lib/widgets/drawer.dart) already does). Prefer a Flutter-side `Listener`/`onSecondaryTapDown` on the canvas over the global `document` context-menu listener where feasible. Drop the `// ignore_for_file: avoid_web_libraries_in_flutter` once `dart:html` is gone.

**5. `go_router`.** Routes `/` (UserNamePage), `/projects`, `/editor/:projectId`. Convert `MaterialApp` ([main.dart](lib/main.dart):58) to `MaterialApp.router`; replace every `Navigator.pushReplacement(... LandscapeLayoutScreen())` with `context.go('/editor/$projectId')`; set `currentProjectNo` from the route param in the editor route builder (minimally invasive given the globals). Add a `redirect` that bounces protected routes to `/` when no username is in `Shared`. With the SPA rewrite (rec 2), deep links survive hard refresh — finally giving the web app shareable project URLs and working browser back/forward.

**6. Export via `package:web`.** Implement `downloadBytes` (Blob + transient `<a download>` + `URL.createObjectURL`/`revokeObjectURL`) and replace `FileSaver.instance.saveFile(...)` ([top_bar.dart](lib/Landscape%20Widgets/top_bar.dart):304); drop `file_saver`. Use `utf8.encode` instead of `String.codeUnits` (line 301) for non-ASCII project names.

**7. Manifest/SEO.** Fix manifest icon paths to files that exist (or add correctly-named 192/512/maskable icons), set `name`/`short_name` to `Annimation` + a real description; set `<title>Annimation</title>`, real `<meta name=description>`, point favicon at `favicon.png`, add Open Graph/Twitter + `theme-color` meta. Validate with a Lighthouse PWA audit in CI.

#### P2 — Responsive & performance

**8. Responsive/orientation.** Set manifest `orientation` to `any`; add a `LayoutBuilder` min-width gate overlay in [landscape_layout.dart](lib/screens/landscape_layout.dart). Medium term, replace the fixed-pixel Stack geometry ([sizes_landscape.dart](lib/Landscape%20Widgets/sizes_landscape.dart): tree 200 / palette 260 / board 400×400 @ `Offset(50,50)`) with a responsive Flex shell (collapsible panels, flexible canvas), and stop reading stale global `w`/`h` ([global.dart](lib/Global/global.dart), set once at [main.dart](lib/main.dart):75-76) — standardize on the live `MediaQuery` already used by `num.sw/sh` in [extensions.dart](lib/extensions.dart). Overlaps the state-management dimension.

**9. Renderer/perf.** Choose the renderer deliberately for this `CustomPainter`-heavy vector editor — **CanvasKit** for paint fidelity (accept the wasm payload) vs the lighter HTML path — set it via build/bootstrap config, add a `--pwa-strategy`, and put a loading indicator in `<body>` so the CanvasKit download shows progress. Benchmark both with Lighthouse; optionally self-host CanvasKit to drop the gstatic CDN dependency. The stale-`serviceWorkerVersion` problem disappears once rec 3 lands.

### Quick wins (S, do today)

- Delete the dead `import 'dart:html'` at [DrawingComponentTileWidget.dart](lib/Landscape%20Widgets/DrawingCompoents/DrawingComponentTileWidget.dart):2.
- Swap the hard-coded base href for `$FLUTTER_BASE_HREF` + `--base-href` build flag.
- Fix the broken manifest icon paths and rename `animated_icon_demo` → `Annimation` (manifest + `<title>`).
- Real `<meta name=description>`; point favicon at the existing `web/favicon.png`.
- Manifest `orientation: "any"` to end the portrait/landscape contradiction.
- Move the YouTube `window.open` ([top_bar.dart](lib/Landscape%20Widgets/top_bar.dart):280) to `url_launcher` — kills one of the two real `dart:html` uses with no abstraction work.

### Suggested order

1. (P0) Quick-win base-href + manifest/title fixes — minutes, instantly unbreaks non-Pages hosting and PWA install.
2. (P0) Bootstrap + Dart 3 SDK bump + Firebase SDK upgrade — keystone for all package upgrades below.
3. (P0) Firebase Hosting + GitHub Actions pipeline with per-host base-href.
4. (P1) `WebPlatform` abstraction + delete dead import + export via `package:web` (retire `file_saver` and the ignore lint).
5. (P1) `go_router` deep-linking (needs the SPA rewrite from step 3).
6. (P2) Responsive shell, then renderer/perf tuning with Lighthouse in CI.
