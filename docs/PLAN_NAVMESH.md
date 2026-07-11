# PLAN_NAVMESH — the walkable world, and where its bake belongs

> "Do we have navmesh on the table?" — Nicco, 2026-07-10.
> We already do. This memo maps what shipped, proves the determinism fence
> holds, and answers — by evidence — the one open question the brief raised:
> should the nav bake move from runtime into a Strata **bless artifact**?
> **Verdict: no, not now.** Keep the runtime per-cell bake. The reasons are
> below, with both bless options priced.

## 1. What already exists (Phase A, `98a9ee2` + `9a8da8b`)

Navmesh is not a table item — it is a shipped feature of the near tier:

- **`game/world/nav.gd` (`Nav` autoload).** Every streamed cell bakes a
  `NavigationMesh` from its terrain triangle soup on the **worker thread**
  (`bake_from_source_geometry_data`; water carved out, steep slopes filtered
  by `agent_max_slope`). Cells register as `NavigationServer3D` regions on the
  world map (`add_cell`), knit at shared borders, and **unregister on teardown**
  (`remove_cell`) — the teardown-reap law. `path()` returns a walkable route or,
  where no navmesh exists (far tier, unstreamed cells), the **straight line** —
  which is exactly the data tier's honest approximation.
- **`game/sim/path_cursor.gd` (`PathCursor`).** One cursor per body; repaths
  when the goal moves or the route goes stale, and hands back the next
  waypoint. Its own docstring states the law: *"Presentation-tier only — data
  agents move as straight math."*
- **Embodiment already drives it.** Both `wildlife_body.gd` and
  `villager_body.gd` walk `_nav.waypoint(delta, global_position, target)` toward
  the mind's target, then `move_and_slide()`. Hard time-catch-ups `seat()` the
  body onto the sim position. This *is* the brief's GAME item (2):
  NavigationAgent-style locomotion toward the sim truth, per-cell region
  streaming, teardown reap.

So of the brief's three work items, **(2) GAME is done.** (1) BAKE and (3)
PROOF are what this memo and branch address.

## 2. The determinism fence already holds

The design constraint — *sim-tier math untouched, the fingerprint must not
move; navmesh serves the embodied presentation tier only* — is already true:

- **The sim tier is straight-line, capped-step, and nav-free.**
  `agent_sim.gd::advance()` moves `pos += to.normalized() * min(speed·dt, |to|)`.
  It has **zero** references to `Nav`, `PathCursor`, `NavigationServer`, or the
  streamer. The fingerprinted positions come from this math and nothing else.
- **The soak is structurally blind to nav.** `tests/soak.gd` never constructs
  the streamer or `Nav` (`grep` is empty), and `world_streamer.gd` itself notes
  *"the soak (headless, no streamer) never sees it."* The six-run soak matrix
  can only fingerprint the sim; navmesh cannot perturb it because it is never on
  that code path.
- **The bake never runs headless in anger.** It rides the streamer's threaded
  finish-budget pipeline, which the soak does not spin up. Nav is a rendering-
  side artifact of a streamed cell.

The split is **sound and already enforced.** Nothing in this work touches sim
math; the branch is presentation-and-tests only.

## 3. The bake mechanism: runtime is the right default

The brief offered two ways to make nav a bless artifact and asked to price
both. There is a third option already in the tree — the runtime bake — and it
wins today:

| Option | Determinism cost | Runtime cost | New surface |
|---|---|---|---|
| **A. Runtime per-cell bake** (shipped) | none — off the fingerprint entirely | Recast per cell on the worker thread, finish-budget throttled | none |
| **B. Godot `NavigationMesh` baked headless at bless** | **high risk** — the gate demands byte-identical double-bake, but Recast's heightfield rasterization + region partitioning is **not guaranteed bit-reproducible** (FP + partition ordering). Likely to *fail* the byte-identity gate. | zero at runtime | a new blessed artifact per cell + manifest row + double-bake gate |
| **C. Heightfield-walkability grid at bless** | deterministic (a pure float threshold on the carved heightfield) | **does not remove the runtime bake** — `NavigationServer` wants polygons, so the game still bakes regions from the grid per streamed cell | a new artifact + carve plumbing, for marginal gain |

The evidence:

- **A is already off the fingerprint** (§2). B and C both *add* a determinism
  surface where none exists today. B's surface is the very one the brief's gate
  polices, and Recast is the worst possible candidate for a byte-identical
  double-bake law. That is the concrete way the "move it to bless" split is
  **unsound for the byte-identity gate** — so, per the brief, this memo is the
  stop-and-write output rather than a forced B/C build.
- **A's cost is already paid down.** The bake is worker-thread work
  (`Nav.bake_navmesh` is `static`, "pure resource work — safe on a worker
  thread"), drained through the same `_finish_budget_ms` queue that lands mesh
  and collision. There is **no measured hitch attributable to nav baking** — the
  `walk_probe.gd` harness exists to catch streaming stutter numerically and nav
  is not implicated. Optimizing an unmeasured cost by adding a determinism gate
  is the wrong trade.
- The one real prize of bless (skip runtime Recast) is only worth claiming once
  a profile blames nav for a frame spike. Until then, **C** — the deterministic
  walkability grid baked from W1's carved heightfield — is the right *first*
  bless step **if** that day comes, because it keeps the byte-identity gate
  honest; B should stay off the table for that gate's sake.

**Call: keep the runtime bake. Revisit C (grid-at-bless) only behind a measured
per-cell bake cost, and price it as a runtime *seed*, not a replacement.**

## 4. What this branch lands

- **`tests/scene_tests.gd::_test_nav`** gains the determinism-law PROOF the
  suite was missing. The pre-existing nav checks route across a flat plane —
  but a flat-plane `map_get_path` is a straight two-point path *indistinguishable
  from the straight-line fallback*, so they never actually proved the walkable
  surface. The new proof bakes a 24×24 m cell with an 8×8 m **placement
  footprint carved out** (the way the streamer carves water/footprints) and
  asserts, straight from the baked polygons:
  - the footprint centre `(12,12)` is **not** walkable — a body cannot cross it;
  - both banks the sim's straight `z=12` line joins **are** walkable;
  - walkable ground exists **north and south** of the hole — a route around
    exists.

  The sim's capped-step line runs dead through the footprint; the embodied body
  cannot follow it and must bow around. Same target, two presentations — the
  whole point of the split, now pinned.

  *(The proof reads the `NavigationMesh` polygons directly rather than querying
  a live `NavigationServer` map: headless Godot does not sync the navigation
  map — `map_get_path` / `map_get_closest_point` return empty in `--headless` —
  so the baked surface itself is the ground truth to assert. This also explains
  why the old flat-plane checks silently passed on the fallback.)*

## 5. Open ends

- **Interiors.** The Threshold's interior pockets are their own little worlds;
  they reuse `PathCursor` but have no baked cell yet. If interiors ever need
  obstacle-aware NPC movement, they need their own small nav bake (or authored
  nav) — tracked, not built here.
- **Rubber-band tolerance.** Bodies currently steer toward the mind's *target*
  and hard-`seat()` to the mind's *position* on catch-up; they do not
  continuously rubber-band to `sim.pos` within a tolerance. That is a looser,
  cheaper coupling than the brief's "diverge-beyond-tolerance-then-catch-up"
  model and is fine today, but it is the knob to reach for if bodies visibly
  lag their minds on long detours.
- **Live-server headless proof.** A true end-to-end `map_get_path`-around-the-
  obstacle assertion needs a windowed (non-headless) instance to sync the nav
  map. The polygon-coverage proof is the headless-safe stand-in; a windowed
  variant could ride the eyes/visual harness later.
