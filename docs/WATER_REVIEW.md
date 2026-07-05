# Water engine review — findings & build plan

*Deep-dive review, 2026-07-04. Scope: the water stack (all tiers), swimming,
sand/snow physics, and the C++/GDExtension question. Companion to
[DECISIONS.md](DECISIONS.md) (the water canon, 2026-07-04 entries) and
[SIM_ROADMAP.md](SIM_ROADMAP.md). Point-in-time document: file references
were true at ~129 commits; trust the code over this doc where they diverge.*

**TL;DR** — the three-tier architecture is the correct shape for a
persistent 1:1-time world and needs no rework. What's missing is exactly
what DECISIONS already names: **tier 2.5 (waves/inertia)** — the surface
cannot react to bodies — and an **underwater swim state**, which doesn't
exist at all (swimming today is a surface spring). C++ is not the move
for any of this: the heavy per-texel physics already runs in GPU compute.

---

## 1. How the water engine works (as built)

### Records are the foundation

- A lake is one JSON (`data/water/pond.json`: center, radius, surface,
  basin radius/depth, outlet). A river is a node polyline with per-node
  width and surface (`data/water/rivers/brook.json`). The watershed domain
  is itself a record (`data/water/watersheds/home.json`).
- `game/world/terrain.gd` carves basins and banked channels into the
  global height function and answers `water_surface(x,z)` (authored +
  live hydrology offset) and `water_surface_base()` (authored only, so
  streamed cells stay deterministic). River queries prune to O(1) via
  bbox + coarse segment grid; the hot probe never allocates.
- Swimming, navmesh carving, moisture floors, flora submersion, and the
  surface meshes (`game/world/water_bodies.gd`: lake discs, river
  ribbons) all read the same records. **One JSON = a working brook.**
  Every later tier must preserve this property.

### Tier 1 — canonical hydrology (`game/world/hydrology.gd`)

- Boot: flow-routes the watershed on a worker thread — priority-flood
  pit filling (Barnes et al.) + D8 steepest descent on a 256² grid →
  per-basin catchment areas. Measured 481ms in the current test run.
- Forever after: an hourly water balance. Storm rain × runoff coefficient
  scaled by ground saturation (`Climate.wetness`), snowmelt, spring
  baseflow, rivers as linear reservoirs (discharge = k·storage), lakes
  integrating inflow − evaporation − outflow, with outlet chaining
  between bodies. Levels move the world via `Terrain.lake_levels` /
  `river_levels`; surfaces rebuild on `levels_changed`.
- On the sim contract: deterministic, hour-tick advanced, saved as
  `water.*` WorldState scalars, replays closed stretches, fingerprinted
  by the soak harness. **This tier is done; nothing below changes it.**

### Tier 2 — live dynamics field (`water_field.gd` + `water_gpu.gd`)

- One 1024² r32f depth field at 2m texels over the whole 2048m watershed
  (same budget as the sand field). Two kernels per substep, two substeps
  per frame:
  - `game/shaders/compute/water_flux.glsl` — outflow to each lower
    neighboring surface (terrain base + depth), scaled by FLOW=0.22
    (stable < 0.25), with a mass limiter (≤ 0.8 × depth) that keeps the
    scheme non-negative and mass-exact. Domain edges read as a 5m drop,
    so storm water exits instead of piling at the rim.
  - `game/shaders/compute/water_depth.glsl` — integrate fluxes, + visual
    rain (~100× physical, documented honesty trade), − soak (parched
    ground drinks faster), − seepage ∝ depth (bounds the film so flat
    ground never floods), hard drain at authored-water sinks. Writes the
    display texture (R depth, G flow speed).
- `game/world/water_sheet.gd`: a 96m / 129² vertex patch follows the
  player, snapped to the 2m texel grid; the vertex shader lifts it onto
  the live field, fragments discard where dry.
- One-thread probe kernel → 4 floats read back at ~6.7Hz feed
  `current_at()`; the river current pushes the player downstream (grip
  factor when wading), verified end-to-end by `tests/current_probe.gd`.
- Presentation-only per the contract: never saved, never fingerprinted,
  off headless. GPU-resident throughout (Texture2DRD, zero CPU texel
  work) — the same pattern as sand, and the right one.

### Presentation (`game/shaders/water.gdshader`, `water_sheet.gdshader`)

Depth-fade transparency, fresnel, drifting sine-sheet ripples, painted
shoreline, wading-trace wake. Explicitly "paint, not physics" — the
ripples are procedural and do not react to anything.

---

## 2. The physics gap

The flux kernel recomputes outflow from the surface gradient every
substep — **no flux memory between frames**. Tier 2 is therefore the
*diffusive* variant of the virtual-pipes model: water always flows
downhill and settles, never overshoots. Ideal for transport (rivulets,
pooling, draining; unconditionally damped and stable), but it means:

- no wave propagation, no rings when something enters the water,
- no wakes or bow waves from moving bodies,
- no sloshing, no wind chop, no reactive surface at all.

Combined with the sine ripples, the water surface is 100% non-reactive.
That is the entire distance between what exists and "high-quality water
physics" — and DECISIONS 2026-07-04 already commits to the fix
(**tier 2.5, the wave field**) and caps the ceiling correctly at
heightfield 2.5D. Note the ceiling caps the *simulation*, not traversal:
a swimmable water column under a heightfield surface is fully in-bounds.

---

## 3. Build plan

### Step 1 — underwater swimming (headline want; no new simulation)

Current state (`game/player/player.gd`): `swimming` is a depth check
(> 1.1m and near the surface) and a spring that overwrites `velocity.y`
to hold the origin 0.8m below the surface. The `elif` chain skips
gravity and jump while swimming; **no input can take you down**. The
pond holds ~3m of water column at center (basin depth 3.2) — room to
dive; the brook (1.1m) stays wading-only, which is right.

Build list:

1. **Dive controller.** Split `swimming` into surface / submerged
   states. Submerged: camera-relative 3D movement (pitch steers), gentle
   buoyant upward drift, jump rises/breaches, a dive input submerges.
   There is no crouch action yet — needs a keybinding decision (gamepad
   included). Exit to wading when depth < threshold or feet find floor.
   Keep the state machine ready for enclosed water volumes (underworld
   skylights/passages, IDEAS), not just open ponds. Swimming skill
   should scale underwater speed; XP already accrues.
2. **Underwater presentation — zero exists today.** Detect camera-below-
   `water_surface()` at the *camera* position, then: swap fog on the
   `WorldEnvironment` (deep-pink density; `day_night.gd` owns it), a
   full-screen tint/wobble post shader, an AudioServer low-pass bus
   effect. The water shader is `cull_disabled` so the surface already
   renders from below; a fake Snell-window brightening is later polish.
3. **Breath — kitchen-table design call, not code.** Proposal on the
   table: no drowning; a soft "surfacing instinct" (auto-drift up after
   ~30s) or nothing at all. Matches the game's gentleness.
4. **Something to see down there.** 3m of pond justifies the mechanic,
   not much more. The real payoff arrives with the underworld: sunken
   features, skylight pools, underwater passages.

### Step 2 — tier 2.5, the wave field (the committed decision)

The "high-quality water physics" core. One more GPU system in the
existing family, built on the sand-field pattern:

- **Field:** ~512² height+velocity (rg32f ping-pong) at ~0.25m texels →
  ~128m scrolling window around the focus, re-anchored like sand.
- **Kernel:** damped wave equation (stability c·dt/dx < 1/√2). Sources:
  submerged capsules inject displacement ∝ speed (bow waves, wakes,
  entry splashes), rain speckle in storms, wind-stress chop biased along
  `Weather.wind_dir`, tier-2 flow speed seeding turbulence in rivers.
- **Consumers:** vertex displacement + gradient normals in both water
  shaders (replace the sines near the focus, keep them far); foam where
  gradient energy is high; shore-lap audio from wave energy at banks;
  splash particles on entry/exit.
- **Buoyancy:** float props/bodies by sampling surface + wave height at
  probe points. Godot 4.7 has `RenderingDevice.buffer_get_data_async` —
  batch a probe *set* (player + floaters + NPCs) with no sync stall,
  instead of today's single blocking probe.
- **Contract:** presentation-only, off headless, never saved — identical
  to tiers 2/3. **Copy the sand discipline:** a pure CPU reference
  kernel, scene-tested (energy decays, waves propagate at c, mass/energy
  bounded), as the spec the GPU implements.

### Step 3 — snow as a deform material (not a snow sim)

Snow today is one scalar (`Climate.snow`) + the emergent snowline drawn
by the terrain shader — a climate state, not physics. Highest value per
effort: **make the existing granular deform field material-aware.**
Above the snowline with cover, the same footprint masks stamp deeper
prints with higher repose (snow holds steeper than sand), decay tied to
melt instead of wind, snow albedo blended in the patch shader. Mud after
storms (`ground_wetness` high) is the natural third material. One
granular engine, three materials; most machinery already exists.
Wind-*transport* of snow (drifts, saltation) is a later kernel term.

### Step 4 — later, when demanded

- **Tier 3** near-window sediment coupling (the remaining seed).
- **C++ bulk height sampler** — see §5; gate on profiling / world growth.

---

## 4. Small findings (fix opportunistically)

- `WaterField.current_at()` river fallback pushes along one whole-river
  direction (`r.flow` = first→last node). Fine on the straight brook;
  on any curved river it shoves swimmers into the bank at bends. Fix:
  per-segment tangents (precompute in `_index_river`, cold-path lookup —
  don't touch the no-allocation hot probe). *(Chip spawned 2026-07-04.)*
- `WaterField.depth_at()` ignores its position argument and returns the
  player probe — a trap for the first NPC/wildlife caller.
- `water_gpu.gd` creates/frees uniform sets every dispatch; cacheable
  per ping-pong parity if frame time ever matters. Minor.
- `water_surface()` / `moisture()` loop all bodies per query — fine at
  today's record count; give lakes the rivers' bbox+grid treatment when
  the world grows toward 12km.

---

## 5. The C++ / GDExtension verdict

**Not yet, and not for water.**

- The expensive per-texel physics (sand 1024², water 1024², waves 512²)
  is **already GLSL compute**. A GDExtension would not touch those
  frames. The architecture already made the right call.
- The wave field, dive controller, and underwater rendering are GPU
  kernels + small GDScript drivers. Nothing in the goals is CPU-bound.
- What *is* slow is bulk `Terrain.height()` sampling from GDScript:
  hydrology routing (481ms measured), the water base bake (~1M calls),
  sand re-anchor bakes, cell mesh + navmesh builds. All run on worker
  threads — they cost *latency*, not frame rate, and today the latency
  is acceptable.
- A GDExtension costs real team overhead: SCons toolchain, per-platform
  binaries (macOS arm64 + Linux CI), and the `precision=double` landmine
  already documented in CLAUDE.md.

**Trigger:** when the world grows toward the 12km plan and streaming/
bake throughput becomes the pressure point, port **one thing** — a
native bulk `height_block()` sampler behind the same interface. Every
bake funnels through that function; one focused port speeds them all
10–50×. This names the designated first target for the existing
CLAUDE.md policy (GDScript until profiled); the policy itself stands.

---

## 6. General project pulse (2026-07-04)

Tests green (unit + scene + dual smoke). ~8k lines of disciplined
GDScript, 129 commits, every sim on the hour-tick contract, determinism
soak harness, placeholder ledger with named replacement paths. Sand is
the strongest physics system (conserved, repose-avalanched, and — the
part worth copying — GPU kernels spec'd by a unit-tested CPU reference).
The water tiers are the same discipline applied at watershed scale. The
gaps are the two named above, both already anticipated by the canon.
