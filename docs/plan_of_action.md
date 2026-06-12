# Plan of Action — Execution Tracker

> **What this is:** the *living* execution surface for the v2 modernization. It tracks **where we are / what's next** as concrete, PR-sized tasks. It does **not** restate strategy — for the *why/how* of each item see the roadmap.
>
> **Reference docs (read-only):**
> - [raw_analysis_of_old_app.md](raw_analysis_of_old_app.md) — current-state analysis (what *is*).
> - [additional_suggestions_and_modifications.md](additional_suggestions_and_modifications.md) — the roadmap (what to *change*, phased, with rationale).
>
> **Constraints (always):** Flutter **web only** (ignore android/ios); all data stays isolated under `appData/v2/...` (legacy `users/...` never touched); keep the app **green at every commit** (`flutter analyze` 0 errors · `flutter test` · `flutter build web`).
>
> **Branch:** `version_2` · **Toolchain:** Flutter 3.44 / Dart 3.12 (fvm default).

**Legend:** `[x]` done · `[~]` in progress · `[ ]` not started

---

## Status snapshot

| Phase | State |
|---|---|
| **Phase 0 — Isolate, Gate, Sweep** | **In progress** (foundations landed; perf + structural sweep remain) |
| **Phase 1 — State Seam & Data Layer** | **In progress** — test net + `ProjectRepository` + `EditorController` seam landed; global migration ongoing |
| Phases 2–8 | Not started — see roadmap |

**Health:** `flutter analyze` → 0 errors (135 info/warnings, down from 933) · `flutter test` → **41 passing** · `flutter build web` → ✓ builds.

---

## Changelog

- **2026-06-12** — Firebase data isolation landed (`appData/v2/users/...`); Firebase/SDK deps modernized so the app builds on Dart 3; Phase-0 cleanup pass (dart fix, dead code, password removal); CI + lint baseline + this tracker added.
- **2026-06-12** — Phase 1 started: pure-core characterization test suite ([test/domain/](../test/domain/), 30 tests) locks the serialization / interpolation / geometry contract before the state-layer refactor. Pinned 4 real bugs (see below).
- **2026-06-12** — `ProjectRepository` extracted ([lib/data/project_repository.dart](../lib/data/project_repository.dart)). All ~16 Firestore call sites across 9 files migrated off inline `DataService().usersInstance` paths; app code no longer builds Firestore paths. Injectable `FirebaseFirestore` + 5 round-trip tests ([test/data/project_repository_test.dart](../test/data/project_repository_test.dart)) via `fake_cloud_firestore` verify save/load and that writes land in `appData/v2` (not legacy `users`).
- **2026-06-12** — `EditorController` seam introduced ([lib/state/editor_controller.dart](../lib/state/editor_controller.dart)): a `ChangeNotifier` that proxies the document-cursor globals (read/write-through, zero behavior change) and adds bounds-checked `currentProject/IconSection/Frame/SingleFrameModelOrNull` accessors to replace the crash-prone index chain. Registered in the `MultiProvider`; 6 accessor tests ([test/state/editor_controller_test.dart](../test/state/editor_controller_test.dart)). Strangler entry point — call-site migration is the next, incremental step.

---

## Phase 0 — Isolate, Gate, and Sweep

**Goal:** guarantee data isolation, stand up CI/lint guards, delete dead code. Low risk, high leverage.

### Done
- [x] **Isolate all v2 Firestore data** under `appData/v2/users/{username}/Project_{n}` via the single `DataService.usersInstance` chokepoint + named constants `kRootCollection`/`kDataVersion` — [lib/service/firebase_service.dart](../lib/service/firebase_service.dart). Legacy `users/...` never addressed.
- [x] **Regression guard** locking the namespace — [test/data/namespace_test.dart](../test/data/namespace_test.dart).
- [x] **Firestore rules + config** (legacy-safe, **NOT deployed**) — [firestore.rules](../firestore.rules), [firebase.json](../firebase.json). *Decision: legacy `users` left permissive so deploying won't break the old app; tighten to `request.auth.uid == uid` in Phase 3.*
- [x] **Modernize deps so the app builds on Dart 3** — firebase_core 1.22→3.15.2, cloud_firestore→5.6.12, url_launcher→6.3.2 (migrated removed `launch()`→`launchUrl` in [drawer.dart](../lib/widgets/drawer.dart)), flutter_colorpicker→1.1.0; SDK constraint→`>=3.2.0 <4.0.0`. *(This also satisfies the Phase-2/7 "bump SDK + modernize Firebase" item.)*
- [x] **Remove the `password:"password"` dead/insecure writes + field** — [new_full_user_model.dart](../lib/drawing_grid_canvas/models/new_full_user_model.dart), [username_page.dart](../lib/screens/username_page.dart), [update_project_no_list.dart](../lib/drawing_grid_canvas/utils/update_project_no_list.dart).
- [x] **`dart fix --apply`** — 771 mechanical fixes / 65 files (unused imports, const, braces…); analyzer issues 933 → 144.
- [x] **Delete dead code (partial):** stock `test/widget_test.dart`; dead `import 'dart:html'` in `DrawingComponentTileWidget.dart`; scratch model JSON (`a.json`, `userModel.json`, `projectmodel.json`, `singleframemodel.json`).
- [x] **CI** — analyze (error-gated) · test · build web · non-blocking format check — [.github/workflows/ci.yml](../.github/workflows/ci.yml).
- [x] **Lint baseline** — [analysis_options.yaml](../analysis_options.yaml) (flutter_lints + generated-file excludes).

### Remaining
- [ ] **Switch the project-list query off `Source.server` / drop whole-collection reads** — `username_page.dart` (~:258,:394). *Stops leaking every profile to every client; med risk — changes load flow.*
- [ ] **Adopt strict lint set (very_good_analysis) with a triaged baseline**, then flip CI `--no-fatal-warnings` off. *(M, needs the 144-issue backlog triaged.)*
- [ ] **One-time `dart format .` pass**, then make the CI format step a hard gate.
- [ ] **Bigger dead-code sweep** — vestigial demo/engine surfaces (`lib/Animated/**`, `playpause.dart`, `mypaint.dart`, `HoverPaint`) — verify each is unimported before deleting; update `main.dart` imports.
- [ ] **Perf quick wins** — wrap canvas/preview/timeline thumbnails in `RepaintBoundary`; hoist `Paint()` allocs to `static final`; real `shouldRepaint`; strip `log()`/error dialogs from paint/interpolation hot paths. *Verify visually (run app) since these affect repaint.*
- [ ] **Remove the entire-collection JSON download** path (data-leak). 
- [ ] *(Deferred, deploy-sensitive)* Make base-href build-arg driven (removing hard-coded `/Annimation/` would change the current GitHub Pages deploy — do under the new hosting pipeline in Phase 7).

---

## Phase 1 — State Seam & Data Layer (next major)

**Goal:** introduce one `EditorController` (ChangeNotifier) seam + a `ProjectRepository`, then start draining globals and the index chain. Everything later depends on this. Item list → roadmap [Phase 1](additional_suggestions_and_modifications.md#phase-1--state-seam--data-layer-the-spine).

- [~] Introduce `EditorController` (strangler entry point) — seam landed ([lib/state/editor_controller.dart](../lib/state/editor_controller.dart)): proxies the document-cursor globals + bounds-checked `*OrNull` accessors, registered in the `MultiProvider`, 6 tests. **Remaining:** migrate the ~244 direct-index/global call sites onto it (incremental; needs in-app verification).
- [x] Extract `ProjectRepository` — app code no longer touches Firestore/paths directly ([lib/data/project_repository.dart](../lib/data/project_repository.dart); injectable + `fake_cloud_firestore` round-trip tests)
- [ ] Replace the 244-site index tuple with derived selectors / guarded accessors
- [ ] Add `schemaVersion` to `Project`; fix serialization casing/int-double traps
- [ ] Snapshot-based undo/redo in the store
- [x] Unit tests for geometry / interpolation / serialization — [test/domain/](../test/domain/) (30 tests)

### Known bugs locked by the test net (fix during Phase 1 serialization hardening / Phase 5)
- `Point.fromMap` throws on **integer-valued** coords (int/double drift); `?? 0` defaults are fine only because the literal is double-typed.
- `Frame` (de)serializes under the capital-S key `"SingleFrameModel"`; a lowercase `"singleFrameModel"` is **silently dropped** (data loss).
- A null `controlPointAdjecntPair` is **rehydrated to `{0,1}`** on reload (non-idempotent round-trip).
- `getNthPointFromInitialAngleWithStepAngle` **throws for odd `n`** when no `initAngle` is given (`int = radianToDegree(...)` double). `get_startpoint_for_polygon_withcenter_side_and_no` is dead (always returns `Point.zero`).

## Phases 2–8

Not started. Each is a goal + checklist in the roadmap — pull them here as they begin:
[Phase 2 Cleanup/Typed State](additional_suggestions_and_modifications.md#phase-2--cleanup-typed-state--test-pyramid) ·
[Phase 3 Identity & Security](additional_suggestions_and_modifications.md#phase-3--identity--security) ·
[Phase 4 Rendering](additional_suggestions_and_modifications.md#phase-4--rendering-pipeline--viewport) ·
[Phase 5 Animation Engine](additional_suggestions_and_modifications.md#phase-5--animation-engine--export-contract) ·
[Phase 6 Editor UX](additional_suggestions_and_modifications.md#phase-6--high-value-editor-ux) ·
[Phase 7 Web Platform](additional_suggestions_and_modifications.md#phase-7--web-platform-routing--delivery) ·
[Phase 8 Sharing/Stretch](additional_suggestions_and_modifications.md#phase-8--sharing-responsiveness--stretch)

---

## Verify (run before marking anything done)

```bash
fvm flutter analyze --no-fatal-warnings --no-fatal-infos   # 0 errors
fvm flutter test                                            # all pass
fvm flutter build web                                       # ✓ Built build/web
```
