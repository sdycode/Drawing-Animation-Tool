# 07 — Decision Log (ADRs)

**What this doc is:** the numbered record of every load-bearing v3 decision — context, decision, consequences, and what was rejected. The place you look when you have forgotten *why*, or when someone asks in an interview.
**What it is not:** a design doc. It states decisions and their cost; the actual types are in [01_domain_model.md](01_domain_model.md), the wire format in [02_file_format.md](02_file_format.md).

**Every ADR here carries a real cost line.** A decision log listing only upsides is worthless.

| Status | Meaning |
|---|---|
| **Accepted** | In force. Changing it requires a new ADR that supersedes this one. |
| **Superseded** | Replaced. Kept for the reasoning trail, never deleted. |

---

## ADR-001 — Stack: Flutter Web, Dart 3, CanvasKit

**Status:** Accepted

**Context.** The editor is a browser app. The two credible stacks are Flutter Web/CanvasKit and TypeScript on `<canvas>`. A multi-agent review panel split **2-1 in favour of TypeScript**, on two honest arguments:

| TypeScript argument | Weight |
|---|---|
| Ecosystem depth: `paper.js`, `bezier-js`, `fit-curve`, `lottie-web` solve bezier math, curve fitting, and playback off the shelf | Real. Dart has no equivalent; this repo writes that math itself. |
| Denser AI-training coverage → faster AI-assisted iteration on canvas/vector code | Real, and measurable in day-to-day velocity. |

**Decision.** Flutter Web. The panel is **overruled**.

**Reasoning.** The owner's bottleneck is *finishing*, not ecosystem. 40 months have produced zero shipped software (00 §4). A 3–6 week language-and-runtime ramp spends the single scarce resource — evenings alongside a full-time job — on the one thing that is already solved. Dart/Flutter is the owner's strongest skill and the skill the target role hires for; writing the bezier and evaluator math by hand is the portfolio artifact, not an accident.

**Consequences.**
- The bezier engine, curve math, and evaluator are all first-party code. That is the differentiator and it is also weeks of work that TypeScript would have imported.
- CanvasKit ships a ~2 MB wasm payload; first-load time is worse than a TS canvas app. Accepted — this is a tool, not a landing page.
- Flutter Web has no `dart:io` (see **ADR-011**).
- The renderer is `CustomPainter` + `Canvas`, not the widget tree, for the artboard.

**Cost.** No off-the-shelf `fit-curve` / `bezier-js`. Every hit-test, curve split, and trim-path length calculation is hand-written and hand-tested.

**Rejected.** TypeScript + Canvas (ramp cost) · Flutter with an HTML renderer (no path-level fidelity) · Desktop/mobile targets (00 §4 — one target, one test matrix).

---

## ADR-002 — Full rewrite over incremental modernization

**Status:** Accepted

**Context.** The legacy app works and has bundled sample content. Incremental modernization is the default-safe answer. Three judges evaluated; **2 of 3 chose rewrite.**

**Decision.** Full from-scratch rewrite. Legacy `lib/` moves to `legacy_reference/` and is deleted at parity.

**Reasoning.** Every requested v1 feature is model-replacing, not additive:

| Legacy behaviour | Feature it blocks |
|---|---|
| Tweens vertices **by array index** | Insert/delete anchors mid-animation (00 §5 criterion 3) — the reason the rewrite exists |
| Stores **baked absolute pixel** points | Artboard-relative coordinates, one `Affine`, non-square artboards |
| Parallel sorted-percent array beside an unsorted frames list | Per-property independent tracks |
| Editor state (hover, selection, cached AABBs) persisted **in the document** | A stable wire format, a second reader, export |

Refactoring these one at a time means running two incompatible geometry models simultaneously in a single-developer codebase.

**Consequences.**
- The legacy format is reachable only through the one-way importer (02 §8); all 8 `assets/library/*.json` become golden fixtures.
- Legacy Firestore namespaces `users/` and `appData/v2` are never touched or migrated.
- Nothing ships until the rewrite reaches parity. There is no half-state to demo from.

**Cost.** Zero user-visible progress for the first stretch of the project, against a legacy app that already runs.

**Rejected.** Strangler-fig refactor (two geometry models at once, solo) · Fork-and-diverge (see **ADR-010**).

---

## ADR-003 — Stable `AnchorId`s: topology on the node, poses in keyframes

**Status:** Accepted — **the load-bearing decision of v3**

**Context.** Legacy tweened vertex *n* of keyframe A into vertex *n* of keyframe B. Insert an anchor at keyframe 1 and every later keyframe silently re-pairs; the shape tears, freezes, or vanishes. This is the single bug that killed the legacy app.

**Decision.** Topology lives **once**, on `PathNode.path` (`PathData`, which owns the ordered `AnchorId` sequence). Keyframes hold `PathPose` = `Map<AnchorId, AnchorPose>` — **poses only, never topology**. Interpolation is an ID join, not an index walk.

Governed by the three rules (00 §8 / 01 §1):

| # | Rule |
|---|---|
| 1 | **TOPOLOGY** edits are track/document-wide for a node; **POSE** edits are keyframe-local. |
| 2 | `AnchorId` unique within a `PathData`; `NodeId` unique within a `Document`. An anchor-ID *sequence* may never differ between two keyframes of one track. |
| 3 | The evaluator is **total and continuous** — never throws, never NaN, and output at `u = 1e-6` is within epsilon of output at `u = 0`. |

**Consequences.**
- **A mismatched anchor set is not a representable state.** The bug is designed out, not tested out.
- `PathOps.insertAnchor` mints one ID and writes it into *every* keyframe of *every* path track for that node, across every animation. `PathOps.retopologize` is the only other topology mutator.
- Pre-pays the deferred seams for free: bones/skinning (`deform`), components (`ScenePath`), per-anchor tracks — all need stable identity and now have it.
- 00 §5 criterion 3 becomes mechanically testable: insert at keyframe 1, assert keyframes 2 and 3 are pixel-identical.

**Cost.** Every path mutation is a document-wide operation, not a local edit — mutations go through `PathOps`, never through direct field writes. Poses carry an ID key per anchor, so documents are larger than an index-addressed format. At the 00 §6 budget (114 anchors × 10 keyframes) that overhead is irrelevant.

**Rejected.** Index correspondence (the legacy bug) · Per-keyframe topology with a diff/merge reconciler (a CRDT problem for a single-user tool) · Auto-matching anchors by proximity at render time (non-deterministic, and violates rule 3).

---

## ADR-004 — Clean break from the published `annimation` v0.0.2

**Status:** Accepted

**Context.** `annimation` v0.0.2 is on pub.dev and replays legacy documents. The reflex is to ship v3 as a version bump of it.

**Decision.** **Clean break.** `annimation` is **not a dependency, not a compatibility target, and not a migration path.** Nothing in v3 depends on it. The pure-Dart core — model + serializer + evaluator, **zero Flutter imports** — is published as a **new** package, **`anim_core`**, from this repo.

**Reasoning.** `annimation` is built on the legacy structure (index-addressed vertices, baked absolute pixels, no `schemaVersion`). It **cannot read a v3 document** — not "reads it with degraded fidelity", cannot parse it. A version bump would advertise a continuity that does not exist. That is why this is a break rather than a bump.

**Consequences.**
- **No backward constraint on the v3 design.** The model was free to be correct.
- 00 §5 criterion 8 stands as written and names `anim_core`: export a `.json`, replay it in a plain Flutter app. `annimation` is explicitly *not* a fallback.
- Two independently-versioned readers of the same wire format (editor, `anim_core`) — which is exactly why 02 §7's forward-compat rules exist.
- Any doc, comment, or task implying v3 exports are replayed by the published `annimation` package is **stale and must be purged**.

**Cost.** `annimation`'s existing users are not carried forward. Accepted: **67 lifetime downloads**, no known production dependants, no deprecation obligation worth a design compromise.

**Rejected.** `annimation` v1.0.0 with a dual-format reader (drags the legacy geometry model into the new runtime forever) · Keeping v3 unpublished and vendored (kills criterion 8, which is the proof the format is a real contract).

---

## ADR-005 — Firestore for v1; Go + PostgreSQL deferred to v1.1

**Status:** Accepted

**Context.** The owner is a solo developer building this alongside a full-time job. **The project may pause for weeks or stop permanently at any point.** It is also the single portfolio project their interview prep rests on. Backend work is a stated learning goal. Firestore already works and is already known (3–4 years).

**Decision.** Two phases:

| Phase | Persistence | Focus |
|---|---|---|
| **v1** | Firebase Auth + Firestore, namespace `appData/v3` | Ship the editor. Firestore is **not replaced pre-ship**. |
| **v1.1** | Self-written Go + PostgreSQL service in `server/`, same repo | Backend learning. **Strictly after** 00 §5 passes on a public URL. |

**Reasoning.** Front-load the **irreplaceable** work. The vector editor, the bezier engine, and the evaluator exist nowhere else and are the actual differentiator for a Flutter role. A CRUD-over-JSON backend is replaceable, well-trodden, and — behind the seam of **ADR-008** — deferrable *forever* at no design cost. If the project stops after v1, what exists is a shipped editor. If the order were reversed, what exists is a database with nothing to store.

**Consequences.**
- Legacy `users/` and `appData/v2` are never touched or migrated.
- v1 concurrency is last-write-wins; two tabs on one document is undefined behaviour (see **ADR-013**).
- v1 adds **debounced autosave + `enablePersistence()` + a visible dirty/saved indicator** (00 §3.18). Rationale: the failure mode of an autosave drawing tool is silently losing the user's artwork. That is the only real data risk in v1 and the cheapest one to close.
- Doc 06's service plan is a **deferred** plan, not v1 scope.

**Cost.** The backend story is unfinished at ship time, and Firestore alone is a weak interview signal for the owner (3–4 years of it already — no new claim). Accepted deliberately: a shipped editor with a deferred backend beats an unshipped editor with a good one.

**Rejected.** Building the Go service first (deepest work last, highest abandonment risk) · Shipping v1 with no persistence at all (kills criterion 7).

---

## ADR-006 — Rejected: Supabase

**Status:** Accepted (rejection recorded)

**Context.** Supabase is the reflexive "Firebase but Postgres" answer and would appear to satisfy both the v1 and v1.1 goals at once.

**Decision.** **Rejected**, for both phases.

**Reasoning.**

| Objection | Detail |
|---|---|
| **Near-zero standalone hiring signal** | Its value is *borrowed from Postgres*. Interview credit comes from schema design, indexing, and transactions — none of which Supabase teaches by using it. |
| **Undefendable if the schema is one blob** | The realistic Supabase path for this app is a single `jsonb` column, which is precisely the design **ADR-012** rejects. "I used Postgres" collapses on the first follow-up question. |
| **No static hosting** | It would add a *second* vendor when `firebase.json` already deploys the web build and Firebase Auth already works. |

**Cost.** Genuinely gives up the fastest route to a hosted Postgres. Accepted: the goal is a defensible interview story, not a resume keyword.

---

## ADR-007 — Rejected: MongoDB, Appwrite, PocketBase

**Status:** Accepted (rejection recorded)

**Decision.** **Rejected** as the v1.1 target.

**Reasoning.** All three are document stores or document-store-shaped BaaS. Moving from Firestore to any of them is **lateral** given 3–4 years of Firestore: same modelling instincts, same denormalization habits, same absence of joins, constraints, transactions, and query planning. **No new transferable skill.** The entire point of v1.1 is the relational skill gap (**ADR-012**).

**Cost.** Some are operationally simpler to self-host than Postgres. Irrelevant — operational simplicity is not the objective of v1.1.

---

## ADR-008 — `ProjectStore` seam: String in, String out

**Status:** Accepted

**Context.** v1 is Firestore, v1.1 is HTTP + Postgres (**ADR-005**). The swap must cost nothing later, which means it must be paid for **at commit one**.

**Decision.** One interface, from the first commit, `String` at the boundary:

```dart
abstract class ProjectStore {
  Future<List<ProjectSummary>> list();
  Future<String?> load(String id);           // raw jsonEncode output
  Future<void> save(String id, String json);
  Future<void> delete(String id);
}
```

**Why `String` and not `Map<String, dynamic>`.**

| Reason | Detail |
|---|---|
| **Domain isolation** | `cloud_firestore` types (`Timestamp`, `DocumentReference`, `GeoPoint`) must **never** enter the domain layer. A `Map` boundary lets them in silently; a `String` boundary cannot. |
| **Single contract** | The wire format ([02](02_file_format.md)) becomes the *only* thing crossing the seam. The same bytes go to Firestore, to the HTTP service, to file export, and to `anim_core`. |
| **Trivially testable** | An in-memory `ProjectStore` is a `Map<String, String>`. Domain tests need no Firebase, no emulator, no network. |

**Consequences.**
- Encode/decode happens exactly once, on the domain side of the seam.
- Firestore stores the document as a single string field; queryable metadata (name, updatedAt, `rev`) is duplicated as sibling fields for the `list()` summary.
- v1.1 needs no domain-layer change at all.

**Cost.** A `jsonEncode`/`jsonDecode` round trip on every save and load that a `Map` boundary would skip, plus duplicated summary metadata to keep `list()` cheap. At the 00 §6 budget, free.

**Rejected.** `Map` in / `Map` out (leaks vendor types) · A generic `ProjectStore<T>` (generality nobody needs, two implementations forever) · No seam, swap later (the swap then touches every call site, which is how "deferrable forever" stops being true).

---

## ADR-009 — Debounced autosave, `enablePersistence()`, visible dirty/saved indicator

**Status:** Accepted

**Context.** v1's user-visible data risk is not corruption or concurrency — it is a drawing tool that appears saved and is not.

**Decision.** In v1 scope (00 §3.18): debounce writes, enable Firestore offline persistence, and show a dirty/saved state in the chrome at all times.

**Consequences.** Offline persistence means edits survive a network drop and flush on reconnect. The indicator makes save state falsifiable by the user instead of assumed.

**Cost.** Offline persistence makes a stale cached document possible after a cross-tab edit; combined with last-write-wins (**ADR-013**), the loser's work is gone with no warning until v1.1. Documented, accepted, not fixed in v1.

**Rejected.** Save-on-every-edit (write amplification) · Explicit save button (users of drawing tools do not press it).

---

## ADR-010 — Two implementations in one branch, selected at build time

**Status:** Accepted

**Context.** v1.1 introduces a second `ProjectStore`. The obvious structure is a long-lived `v1.1-backend` branch.

**Decision.** **No forked branch.** Same repo, same branch, both implementations present, selected by a compile-time define:

```
lib/data/project_store.dart              // interface
lib/data/firestore_project_store.dart    // v1
lib/data/http_project_store.dart         // v1.1 — added, not replacing
server/                                  // v1.1 — Go service
```

```bash
flutter run --dart-define=BACKEND=firestore   # v1
flutter run --dart-define=BACKEND=api         # v1.1
```

**Reasoning.** A long-lived branch on a project that may pause for weeks (**ADR-005**) rots and never merges. Tree-shaking drops the unselected implementation from the build, so the cost of carrying both is compile-time only.

**Consequences.** `main` always builds a shippable app. v1.1 is additive: nothing is deleted, the Firestore path stays as a fallback and as a comparison point.

**Cost.** Both Firebase and HTTP dependencies stay in `pubspec.yaml` after v1.1, and one factory function must stay honest about which define maps to which implementation.

**Rejected.** A `v1.1-backend` branch (rots) · Runtime backend switching via config (needs both SDKs live in the shipped bundle for no user benefit).

---

## ADR-011 — Flutter Web has no `dart:io` → v1.1 requires an HTTP service

**Status:** Accepted — **forced consequence, not a scope choice**

**Context.** The v1.1 goal is PostgreSQL. Postgres speaks a binary protocol over a TCP socket.

**Decision.** v1.1 ships an HTTP service in `server/`. The Flutter Web client talks to it over `package:http`; it never talks to Postgres.

**Reasoning.** Flutter Web has **no `dart:io`**. A browser cannot open a raw TCP socket at all — `package:postgres` is not merely unavailable, it is unimplementable on this target. The service is therefore *forced by the stack*, not chosen as extra scope.

**Consequences.**
- The Go service is not optional v1.1 polish; it is the *minimum* v1.1.
- It becomes the natural home for auth verification, the `rev` optimistic-concurrency check (**ADR-013**), and the version-history table — none of which a direct DB connection would have given.
- Real HLD work belongs to this service. v1's HLD is deliberately thin: it is single-user CRUD over one document, and inventing architecture for it would be theatre.

**Cost.** An extra network hop, a deploy target, and CORS/auth surface that a hypothetical direct connection would not have had. Not a tradeoff — there is no alternative.

**Rejected.** Nothing. There is no rejected alternative; the platform decides this one.

---

## ADR-012 — Go over a Dart backend; hybrid relational schema over a `jsonb` blob

**Status:** Accepted

**Context.** Two independent v1.1 questions, decided together because they share one motive.

**Decision A — Go, not Serverpod/Shelf.**

**Be honest about the tradeoff:**

| | Dart backend (Serverpod / Shelf) | Go |
|---|---|---|
| Time to working service | **Faster** | Slower |
| Model code sharing | **Shares `anim_core` types directly** | Re-declares the wire structs |
| Language ramp | **Zero** | Real |
| New marketable skill | **None** | Yes |

Dart wins on every engineering axis and is rejected anyway. The **entire purpose** of v1.1 is skill acquisition (**ADR-005**); a Dart backend would deliver a service and teach nothing new. Go is chosen for the same reason Postgres is: it is what the gap is in.

**Decision B — hybrid relational schema, never a single `jsonb` blob.** Identity, ownership, timestamps, `rev`, and summary metadata are **typed columns**; the authored document body stays as one serialized payload (02 §10).

**Reasoning.** Postgres keeps **no statistics on JSONB keys** — `body->>'name'` gets a hardcoded default selectivity guess, so the planner cannot estimate row counts and picks bad plans (seq scan where an index nested loop was right). Typed columns are analyzable; a blob is not. A blob-only schema also teaches nothing about constraints, indexes, or query planning, which is the whole point.

**Consequences.**
- Summary metadata exists in two places (typed column and inside the body) and must be written in one transaction. Since `ProjectStore` is String-in/String-out (**ADR-008**), the *service* — not the client — extracts those columns from the payload.
- Version history (`project_versions`, PK `(project_id, rev)`) becomes cheap and is in v1.1 scope.
- The wire format is untouched by any of this. The service stores it; it does not redefine it.

**Cost (A).** v1.1 takes materially longer than the Dart route, and the wire structs are declared twice — Dart and Go — with a round-trip test on each side as the only thing keeping them honest.
**Cost (B).** Denormalized summary fields can drift from the body if a write path bypasses the transaction. Mitigated by a single write path, not by a constraint.

**Rejected.** Serverpod/Shelf (no new skill) · Node/Express (owner already has JS-adjacent exposure; weaker systems signal than Go) · One `jsonb` column (bad plans, no statistics, nothing learned) · Fully normalizing nodes/anchors/keyframes into tables (shreds an immutable authored document into hundreds of rows to satisfy queries nobody issues).

---

## ADR-013 — Monotonic `rev` on `Document`, added in v1

**Status:** Accepted

**Context.** v1 is single-user, last-write-wins. `rev` is genuinely unused in v1 beyond being incremented and round-tripped.

**Decision.** Add `rev` to `Document` **now**: `int`, optional-with-default `1`, incremented by exactly 1 per **persisted save** (never per edit, never per undo).

**Reasoning.** Retrofitting a required field into documents that already exist in production Firestore is a **migration**. Adding one integer today costs a line in the serializer and a line in the round-trip test. v1.1 turns it into optimistic concurrency and detects the two-tab clobber that 02 §9 currently accepts blindly.

**Consequences.** v1 writes and round-trips `rev` but does **not** enforce it. The v1.1 conditional update (`WHERE id = $1 AND rev = $2`) and the `project_versions` history PK both key off it, with no schema break.

**Cost.** A field that does nothing in the shipped product, which invites "delete the unused field" during cleanup. That is exactly what this ADR exists to prevent.

**Rejected.** Adding `rev` in v1.1 (a migration over live documents) · A `updatedAt` timestamp as the concurrency token (clock skew, and equal-timestamp ties are real at autosave debounce intervals).

---

## ADR-014 — Time is normalized `0..1`; the UI displays seconds

**Status:** Accepted

**Context.** Legacy stored `0..100` percentages — the one unambiguously correct legacy decision (00 §7). The alternative is authoring in absolute milliseconds or frames.

**Decision.** The document stores **normalized fractional `t` in `0..1`**. `durationSeconds` and `fps` live on the `Animation`. The **UI displays seconds**, converting at the widget boundary only.

**Reasoning.** Resolution- and duration-independent: changing an animation's duration retimes it uniformly with zero keyframe edits. Frame numbers for Lottie export are mechanical (`t * durationSeconds * fps`). It also keeps the playhead a unitless double in the domain — killing the legacy bug where it round-tripped through pixels and `BuildContext`.

**Consequences.**
- **No absolute-duration authoring in v1** (00 §4). You cannot type "hold for 200 ms"; you type a fraction, or you set the duration and the fraction follows.
- Segment-local remap stays `(t - t[i]) / (t[i+1] - t[i])` — the correct shape, now with easing applied where legacy had none.
- Strictly-increasing `t` is enforced at mutation (`TrackOps.moveKeyframe`), with a zero-span guard in the sampler. This is where legacy's divide-by-zero NaN came from.

**Cost.** Duration-relative authoring is genuinely awkward for effects that should be absolute — a 150 ms flash is a different fraction at every duration. Accepted for v1; a millisecond-entry field that converts on input is additive later and changes no stored data.

**Rejected.** Absolute milliseconds (retiming becomes an edit of every keyframe) · Frame numbers (couples the document to an fps, which is a rendering concern) · Legacy `0..100` (same model, arbitrary scale, and every consumer divides by 100 anyway).

---

## ADR-015 — Engineering focus: what v1 optimizes and what it does not

**Status:** Accepted

**Context.** "Make it good" is unbounded. This ADR bounds it, so that omissions are *decisions* rather than oversights.

| Area | Treatment |
|---|---|
| Architecture, patterns, structure, **testing** | **In.** Testing is already scoped by 00 §5: the round-trip property test over all 8 fixtures + the golden transform test on the 450.2 × 250.4 artboard. **No extra test tracks are invented.** |
| **UI performance — narrow** | **In.** `RepaintBoundary` around the artboard, repaint scoping, and no rebuild storms during scrub or drag. Those three, nothing more. |
| **Memory-leak hunting, allocation optimization** | **Explicitly out of v1.** 00 §6 sets the budget at 114 anchors × 10 keyframes × 1 node and states that immutability and allocation churn are **free at this scale**. Stated here so the omission is on the record, not silent. |
| **HLD** | **Thin in v1** — single-user CRUD over one document. Real HLD belongs to the v1.1 service (**ADR-011**). |

**Consequences.** Every immutable value type allocates freely on every evaluator tick. That is a deliberate purchase of correctness and testability with memory the app does not need.

**Cost.** If a future feature (bones, instancing, or a document an order of magnitude larger than the legacy maximum) breaks the §6 budget, allocation behaviour becomes a real problem that has never been measured. The trigger for revisiting is a *measured* frame-time regression, not a suspicion.

**Rejected.** Profiling and pooling in v1 (optimizing a budget already met) · Mutable geometry for tick-time allocation savings (re-introduces the aliasing class of bug that made the legacy copy constructor return the same instance).

---

## ADR-016 — The M1 round-trip gate runs over 8 **authored v3** fixtures; the legacy 8 join the same test at M8

**Status:** Accepted

**Context.** 00 §5 and 04 §7 both describe the automated gate as the round-trip property test "over all 8 legacy fixtures" — the `assets/library/*.json` files, which are also 00 §5 criterion 9 and 00 §3 item 15. 06 schedules that gate at **M1**. Those two statements cannot both hold: `LegacyImporter` is **F11.3, milestone M8**. At M1 there is no importer, so there are no legacy documents in v3 form to round-trip, and the gate as worded could not exist for seven milestones — precisely the seven milestones during which the serializer is being written and is most likely to silently drop a field.

**Decision.** The gate round-trips **8 authored v3 fixtures**, real `.json` files checked into `packages/anim_core/test/fixtures/`, chosen between them to cover the whole type surface: minimal document, nesting/clip/z-order, geometry and all anchor kinds, paint including the rendered-but-not-authorable gradients, all five track types, the forward-compat unknowns, trim, and the 450.2 × 250.4 lopsided board. At **M8, the imported legacy documents join that same test** as additional cases. There is no second round-trip gate and no legacy-specific gate.

**Reasoning.** The gate's job is to prove the serializer is a fixed point, and a fixture proves that whatever authored it. Legacy provenance adds *realism*, not *coverage* — and it subtracts coverage in the direction that matters, because the legacy format has no trim, no per-property tracks, no unknown-key forward compat and no gradients, so eight legacy documents would leave most of the v3 type surface unasserted. Authored fixtures are also adversarial by construction: 08_lopsided exists solely to make a y-scaled-by-width error numerically obvious, and no real legacy file was drawn to do that. Keeping the legacy documents in the *same* test at M8 is what stops this from becoming a second gate.

**Consequences.**
- The gate exists from M1 and blocks deploys for the whole build, instead of arriving at M8.
- Fixture *coverage* is asserted by a table at the head of the test, not mechanically. Adding a type to `anim_core` without extending a fixture fails nothing. Extending a fixture is part of adding a type.
- The test carries a presence check, so deleting a fixture or adding a ninth turns it red rather than quietly shrinking the gate.
- 00 §5, 04 §7 and 06 M1 were corrected to say this; 00 §5's nine success criteria are unchanged, and criterion 9 still means the legacy library.

**Cost.** Eight hand-authored JSON files are a maintenance surface that has to be edited by hand every time the format grows, and they are only as adversarial as whoever wrote them. A fixture that was never extended is a gate that quietly stops covering the thing it was named for.

**Rejected.** Moving the gate to M8 (leaves the serializer ungated through the milestones that write it) · A separate legacy round-trip gate at M8 (the third gate 04 §7 forbids) · Generating fixtures from a property-based random document generator (a generator that shares the model's assumptions cannot falsify them, and a failure is not reproducible from a file you can read).

---

## ADR-017 — The decoder is strict at the required root and degrading everywhere below it

**Status:** Accepted

**Context.** Two rules, written in different documents for different reasons, read as a contradiction. 00 §7 and 06 M1 say **strict decoder — a missing required subtree throws with a path**, aimed at legacy's null-coalescing that manufactured plausible-but-wrong data. 08 §2 says **decode degrades, never validates-and-throws**, aimed at the cascade failure where a field one feature adds on Monday makes the document unopenable in another feature on Tuesday. Applied globally, each rule breaks the other's failure mode.

**Decision.** Split by required versus optional, at the document root:

- **Throws `DocumentException` carrying a JSON path:** a missing or unusable **required root-level structure** — `schemaVersion`, `id`, `artboard`, `root` — and, transitively, whatever those in turn require (a node's `type` and `id`, a path node's `path`, an anchor's `id` and `position`, an animation's `id`).
- **Degrades and is preserved, and may never throw:** everything else. Unknown node `type` → `UnknownNode` verbatim · unknown `paint.type` → `UnknownPaint` · unknown `easing.kind` → `UnknownEasing` · a malformed or invariant-violating track → kept raw in `TrackSet.unknownKeys` and not evaluated · an orphan pose id → dropped with a warning · unknown keys at every level → re-emitted on save.

**Reasoning.** The two rules are not general principles in competition; they are answers to two different questions, and the questions are separated exactly by whether a document still exists. Without `root` or `artboard` there is nothing to show, and degrading produces a blank canvas the user reads as *their artwork was deleted* — the loudest possible failure is the honest one, and the path in the exception is what makes it diagnosable. Below the root, every unknown is a *newer* document being opened by an *older* client, which is the normal, expected lifetime of a versioned format; throwing there converts forward compatibility into breakage. `schemaVersion` and `id` are on the strict side not because they are structural but because a document that cannot say what it is or be addressed cannot be saved back without inventing identity.

**Consequences.**
- 06 M1 and 08 §2 now state this boundary in the same words, so neither can be read alone and produce the wrong answer.
- `anim_core` still contains **zero** `try/catch` (08 §1). Throwing is a decode-time act at the IO boundary; the evaluator remains total by construction, and the single catch lives one layer out at `ProjectStore`/decode per 08 §1's table.
- A corrupt-below-the-root document opens **partially and visibly**, with warnings, and re-emits everything it did not understand.

**Cost.** The strict set follows the *required* relation and nothing else, so a document whose `root` is intact but whose children are all unreadable-but-well-formed opens as an almost-empty canvas with warnings, not an error. That is the case where the strict rule would have been more useful and the degrading rule wins anyway — accepted, because widening strictness past "required" starts a slide that ends with the decoder validating the whole tree, which is the thing 08 §2 exists to prevent.

**Rejected.** Strict everywhere (one unknown paint type from a newer client makes the whole document unopenable) · Degrading everywhere including the root (silent empty canvas; indistinguishable from data loss) · A `strict: bool` decode flag (two decoders, one of which is never exercised, and the caller has to know which one it wants before it knows what is in the file).

---

## Cross-links

- [00_vision_and_scope.md](00_vision_and_scope.md) — v1 scope contract, the written non-goals, success criteria.
- [01_domain_model.md](01_domain_model.md) — **authoritative** types, invariants, mutation API, evaluator pipeline.
- [02_file_format.md](02_file_format.md) — wire contract, forward-compat rules, legacy importer, both store layouts.
- **07_decisions.md** — this document. Every ADR above is in force unless marked Superseded.
