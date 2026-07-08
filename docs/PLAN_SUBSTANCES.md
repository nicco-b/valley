# PLAN_SUBSTANCES — water, snow, sand, and the falling sky

*2026-07-08, from Nicco: "i'd like to look into water physics a bit
more. i don't want photorealistic but im seeing a lot of really nice
water sim coming out of unity / unreal and id like to see how much we
can roll. i want water to be really really nice. honestly same with
snow / sand / particle physics." Companion to `PLAN_PHYSICS.md` (the
W/S tracks — this plan builds beside them, never re-plans them) and
`PLAN_FABRIC.md` (same laws, same voice). The Watershed learns to
answer back; the Grain learns to wear white.*

## Executive summary

The showpiece water coming out of Unity (HDRP Water, Crest) and Unreal
(Water plugin, Fluid Flux, Niagara Fluids) decomposes into about eight
tricks — and we already own more of them than expected. We have an FFT
stand-in that reads (4 Gerstner bands + storm heralds, W1/W2 LANDED),
a real interactive wave grid (tier 2.5: 512² damped wave equation,
12.5cm texels — the thing Fluid Flux sells), flow-map advection, a
posterized foam language, and a conserved GPU granular field that is
strictly *better* than the RDR2 snow-trail trick AAA uses. The verdict,
measured on this machine (M5 Pro, 2026-07-08):

- **Interactive water** → **extend the shipped wave grid, don't
  replace it.** Only the player disturbs it today; the gap between us
  and "alive" is *sources* (creatures, NPCs, splashes, wakes), which
  are script, not sim. The kernel itself costs **0.054 ms/step at
  512²; 0.114 ms at 1024²** (measured, the shipped `wave_step.glsl`) —
  doubling the window to 128m is a rounding error. Full SWE water
  bodies: **drawer** (buys sloshing the pipe model + wave field
  already split between them).
- **Water looks** → foam needs *memory* (a second field channel that
  deposits, advects, decays — the Sea-of-Thieves trick in gouache),
  plus three cheap flagged fixes: foam distance-fade (the "too white
  at distance" lake read), river-mouth feathering into lake discs,
  and promoting the placeholder underwater veil into a real painting.
- **Buoyancy** → **analytic, never sim-coupled.** A CPU mirror of the
  Gerstner sum costs **7.6 µs per floater per frame** (measured,
  GDScript, 5 probe points); a *blocking* GPU probe readback costs
  **0.17 ms each** (measured) — the analytic surface wins by 20× and
  is deterministic by construction. `buffer_get_data_async` exists in
  4.7 if wave-field coupling is ever wanted; it isn't, yet.
- **Snow** → snow EXISTS (a Climate scalar, a lapse-rate snowline, a
  terrain-shader band, melt feeding Hydrology) but nothing *falls* and
  nothing *holds a footprint*. The mountain-cap tier is buildable
  today; deformation trails are a **parameter table on the sand
  field** (one granular engine, three substances — verified below,
  with one honest caveat); valley-floor winter blankets are GATED on
  a per-cell snow field (small sim) + her seasonal palettes.
- **Sand** → PLAN_PHYSICS S1–S3 stand unchanged. This plan adds only
  the substance unification and non-player stamps.
- **Particles** → 12 ad-hoc `GPUParticles3D` emitters become one
  records-driven weather language (`data/particles/*.json`), all
  reading the one wind; the engine's heightfield collision +
  at-collision sub-emitters cover splash/settle without a single
  engine patch.
- **Fork pricing: zero, on every dimension** — stated per item below.

S1 (everything that moves rings the water) is the cheapest thing that
makes the water feel ALIVE, and it is almost entirely `disturb()`
calls that already have an API.

## Where substances stand (inventory, 2026-07-08)

**Water, four tiers, all landed:**
- Tier 1 Hydrology — hourly basin balance, sim contract, saved,
  soaked. Region tier breathes the Strata rivers/lakes (P2).
- Tier 2 WaterField — 1024² pipe-model depth field, 2m texels,
  scrolling window; rain streams, pools, drains. Presentation-only.
  Probe readback is **blocking `buffer_get_data`**, single-point,
  player-only, hidden by one-frame pipelining (`water_gpu.gd:174`).
- Tier 2.5 WaterWaves — 512² damped wave equation over a **64m window**
  (12.5cm texels), one step/frame, ±0.2m rails (`wave_gpu.gd`,
  `wave_step.glsl`). Sources today: player wading strides, player
  splashdown (the ONLY external `disturb()` caller — `player.gd:392`),
  rain pocks, wind chop with downwind twins. **No creature, NPC,
  wildlife, or boat has ever touched the water.** CPU reference kernel
  + scene tests exist (`wave_reference.gd` — the sand discipline).
- The sea — W1 Gerstner swell (4 components, storm heralds 5200m
  ahead), W2 shoaling/breakers on baked bathymetry (CUSTOM0), lee
  shores calm. `sea_surface()` physics stays **flat + tide**; the wave
  shape lives only in the vertex shader ("Physics never sees this").
- Shader — screen-space refraction, depth-drunk pink, **posterized
  foam (3 steps)** from shoreline/crests/flow/rapids/wading/breakers,
  flow-map advection (UV2, two-phase crossfade), golden-hour palette.
  Foam is *instant* — born and dead in the same frame's math, no
  memory, no ride-along. No camera-distance fade on foam terms.
- Underwater — a placeholder: deep-pink ColorRect veil + 900Hz
  low-pass when the camera dips (`player.gd:239`), flagged for the
  real fog-swap treatment (WATER_REVIEW §3.1). Dive state exists
  (PROVISIONAL). W3 swash/wet strand: not built (PLAN_PHYSICS owns it).

**Snow (the Elements):** one valley-anchored scalar `Climate.snow`
(0..1) accreted when a wet front sits over the valley while
`snow_line() < 60m` (`climate.gd:318`); snowline = `base_temperature()
/ LAPSE` — pure lapse rate, so winter storms drop it below the valley
floor and summer lifts it over the volcano. Rendering is a terrain-
shader whitening band above `snow_line` (settles on flats). Melt =
base + warm term; meltwater soaks the wetness field AND becomes
Hydrology runoff (`SNOW_MELT_M`). **No snowfall particles, no spatial
cover field, no deformation, no ice.** Seasons are the real calendar —
it is July; the valley floor will not see honest snow until real
winter (dev time travel + forced fronts test it any day).

**Sand (the Grain):** 1024² conserved signed-volume field, 2.3cm
texels over 24m, apply/relax/scroll kernels, angle-of-repose
avalanches (wet raises repose via Climate), wind erosion reading the
one wind, CPU reference + conservation unit test. Stamp API:
`stamp/plow/crater` — called by the **player and wildlife hooves
only**; NPCs don't print. One `SandPatch` follows the player
everywhere (not biome-gated); the substance of the ground never
changes what the field does — sand math on snow, mud, and meadow
alike.

**Particles:** every emitter is `GPUParticles3D` +
`ParticleProcessMaterial`, no collision, no attractors, no shader
process materials. The roster (atmosphere.gd unless noted): sand
motes, glow-motes, moths, rain streaks (1400, wind-tilted),
butterflies/pollen/gnats/embers/gulls (biome+time gated), storm dust
(weather_fx.gd), landing sand-puff + sprint scuff (player.gd). Rain
curtains and lightning are meshes, not particles. **No snowfall, no
spray, no splash particles exist.**

**Engine surface (stock 4.7 = the fork's base — verified in the fork
checkout):** `GPUParticlesCollisionHeightField3D` (256–8192 res,
follow-camera mode, WHEN_MOVED/ALWAYS update = a top-down depth
re-render), SDF/box/sphere colliders, vector-field attractors,
**`SUB_EMITTER_AT_COLLISION`** (splash-on-impact chains, built in),
`GPUParticles3D.emit_particle()` (scripted GPU bursts),
`RenderingDevice.buffer_get_data_async` (stall-free readback). No
built-in water/fluid/buoyancy anywhere — everything below is ours to
roll, and all of it fits extension points.

## Measurements (this machine, 2026-07-08)

Probes committed on this branch: `tests/wave_bench.gd/.tscn` (times
the SHIPPED `wave_step.glsl` on a local RenderingDevice) and
`tests/buoy_bench.gd` (CPU Gerstner mirror, headless). Two gotchas the
probes recorded: **no local RenderingDevice exists headless** (dummy
renderer — compute probes need a window), and **stock Metal Forward+
crashes at CLI boot on this box** (the placement_probe finding, again)
— `--rendering-driver vulkan` (MoltenVK) is the workaround and is
what these numbers ran on. MoltenVK IS Metal underneath; treat them as
upper bounds.

**The wave kernel** (`wave_step.glsl`, 240 dispatches, submit+sync
timed, r32f ping-pong — the real texture sizes in play):

| Grid | window @ texel | ms per step |
|---|---|---|
| 512² (shipped) | 64m @ 12.5cm | **0.054** |
| 1024² | 128m @ 12.5cm | **0.114** |
| 2048² | 256m @ 12.5cm | **0.331** |

Read: the interaction grid is **effectively free at any size we'd
want**. One step/frame is the shipped cadence; even 2048² + splat +
publish stays under half a millisecond. The cost of "alive" is not
the kernel — it's having nothing to say to it.

**Blocking readback** (16 bytes, submit+sync+`buffer_get_data`, ×60):
**0.169 ms each**. That is the per-frame price of ONE synchronous
buoyancy probe — and why buoyancy must not be sim-coupled (below).

**CPU analytic buoyancy** (GDScript, 4 Gerstner components, 2
fixed-point inversion iterations, 5 probe points per floater):

| Floaters | µs/frame |
|---|---|
| 1 | 7.6 |
| 8 | 57 |
| 30 | 216 |

Read: an entire harbor of bobbing props costs a fifth of a
millisecond **in script**, deterministically, with zero GPU traffic.
(Same shape as PLAN_FABRIC's verlet finding: the want is CPU-cheap.)

**Not measured, estimated** (flagged again in the honesty section):
particle-collider depth-pass cost, foam-channel marginal cost
(bounded: it rides the same dispatch, rg16f instead of r32f), and
all authoring effort.

## The survey — what the Unity/Unreal showpieces actually are

Each row: the trick → what delivers the FEEL → the photorealism
baggage we skip → our gouache analog.

| Trick (who) | The feel | Baggage we skip | Our analog |
|---|---|---|---|
| FFT ocean spectra (Sea of Thieves, HDRP Water, Crest) | a horizon that never repeats; storm seas with real menace | oceanographic spectra, Jacobian folding, displacement mips | **Have it in spirit**: 4 Gerstner bands + fronts-as-heralds landed (W1/W2). FFT stays fenced unless band regularity ever offends the eye — PLAN_PHYSICS already reserved that exit |
| Interactive ripple/SWE grids (Fluid Flux, Niagara Grid2D, Uncharted ripples) | the water acknowledges YOU — rings, wakes, splash rebounds | full shallow-water momentum, erosion coupling, whitewater particles per cell | **Have the grid** (tier 2.5). Missing: everyone-else sources, wake trains, splash bursts. That's S1, and it's script |
| Foam that remembers (SoT wakes, Crest foam sim) | foam is BORN by events, rides the current, dies slowly — the water has a memory | screen-space foam buffers, mip-chain diffusion | a second channel in the wave field: deposit from crest energy + disturbances + breaker band, advect along flow, decay. Posterized on read — painted curds, not mist |
| Flow maps (Valve → everyone) | rivers visibly GO somewhere; pools laze | — | **Have it** (UV2 per-vertex flow, two-phase crossfade) |
| Buoyancy (UE WaterBody pontoons) | things sit IN the water, lean into swell | physics-solver coupling, wave readbacks | analytic probe points on the CPU Gerstner mirror — 7.6 µs/floater, measured |
| Waterline + underwater (HDRP water line, SoT) | the crossing is an EVENT: meniscus, muffle, a different world below | volumetric absorption, real caustics, Snell refraction | S4: fog-keyframe swap, painted meniscus band, wobble, motes — *night is a different painting; so is under* |
| Shore wetness / swash decals (everyone since Uncharted) | the beach remembers the last wave | screen-space decal stacks | **Planned** — PLAN_PHYSICS W3 owns swash + the wet strand; this plan doesn't touch it |
| Deformable snow (RDR2 heightfield trails, BotW) | the ground remembers YOU — the single loudest "next-gen" feel | render-target displacement with no conservation, tessellation | **We own a better one**: the Grain is a *conserved* GPU heightfield with repose physics. Snow = a parameter table swap on it (S5), not a new system |
| Weather-driven cover (BotW, Horizon) | the world dresses for the season | material blending stacks | shader band exists today; a per-cell snow field (the wet_grid pattern) makes cover LOCAL — gated, S7 |
| Snow sparkle (RDR2, Horizon) | cold air glitter | glint BRDFs, sparkle noise | ★ the terrain's existing sun-glint language, denser above the snowline — glow stays reserved (Art Bible Law 2); if it reads as glitter, it's wrong |
| Windblown transport (Journey sand, BotW gales) | the surface is ALIVE under wind | GPU advection of surface material | PLAN_PHYSICS S2 owns it (ripple phase drift + saltation streamers). Snow inherits the same trick above the snowline |
| Niagara-as-a-system (data-driven emitter graphs) | one weather = one coherent sky; every effect agrees | node-graph VFX authoring | records: `data/particles/*.json` emitters, all reading `Weather.wind/rain/dust` + biome + season — the flora/species pattern applied to the sky |

The through-line: **the showpieces sell interaction and memory, not
resolution.** Rings, wakes, lingering foam, prints in snow — every
one is a small field + sources + a painted read. We have the fields.
We're missing the sources and two channels of memory.

## The verdicts (dimension → options → price → recommendation)

### 1 · Interactive water — extend the grid, never replace it

| Option | Price | Verdict |
|---|---|---|
| **A · Extend tier 2.5** — non-player sources, wakes, splash coupling; window 64→128m if edges show | kernel measured 0.054→0.114 ms/step; sources are `disturb()` calls (API exists, `MAX_OPS=32` cap already guards); wake train = periodic offset splats behind swimmers (interference draws the V for free) | **BUILD (S1)** |
| B · Full SWE water bodies (Fluid-Flux-style momentum grid per body) | a third water sim family + its seams vs tier 2; ~0.3–0.5 ms est.; buys sloshing/persistent currents the pipe model (transport) + wave field (reaction) already divide between them | **Drawer.** Reopen only if a design wants flash floods with momentum (a wave that travels a dry wash) |
| C · Shader-only fakes (screen-space ripple decals) | cheap | already surpassed — we paid for a real grid and it's 0.05 ms |

Sizing the window is a taste call, not a budget one: at 512²/64m a
ring dies 32m out. **Position: ship S1 at 1024²/128m** (+0.06 ms
measured) so a hound crossing the far side of a pond still speaks to
you; keep `WAVE_GRID` a knob and let the probe A/B decide. ★

Creature sources ride what exists: wildlife bodies already stamp sand
(`wildlife_body.gd:109`) — the same hook rings water when wading.
Splashdown generalizes from `player.gd:392` to any body entering.
Rain/chop already speak. Boats: the raft (D3) becomes a source the
day it moves.

**Fork price: zero** (compute + script, the shipped pattern).
**Determinism: presentation** — off headless, cosmetic RNG, nothing
saved (the existing WaterWaves law; S1 adds callers, not state).

### 2 · Water looks — memory, then the three flagged eyesores

Ranked by lift-per-work on the EXISTING stack:

1. **Foam memory (the big one).** Promote the wave field to two
   channels (rg16f): R = height (unchanged), G = foam. Deposit where
   crest energy is high, where disturbances land, and along the W2
   breaker band; decay per step (`FOAM_DECAY` knob); advect by the
   local flow where tier-2 flow speed exists. The shaders read .g as
   a foam *history* term into the same 3-step posterize. Foam born at
   a breaker then RIDES shoreward and dies on the sand — wakes linger
   behind a swimmer. Price: the same dispatches on a two-channel
   texture (estimate: +0.01–0.03 ms at 1024²); one kernel edit + two
   shader edits. The gouache read: painted curds that outlive their
   wave — never mist. ★ decay time is a taste knob (start ~6 s).
2. **Foam distance-fade — the "too white at distance" lake read**
   (Nicco's P2 eye-check note). Cause is mechanical: posterized foam
   terms have no camera-distance treatment, so far shorelines/chop
   alias to a white shimmer. Fix: fade the foam sum over camera
   distance (`smoothstep(150, 300, dist)`) into the calm palette,
   exactly the fabric LOD law (fade into the *leaned* pose — here,
   into painted stillness). A far lake should read as a single quiet
   color field with maybe one painted highlight — that's what gouache
   distance IS. ★
3. **River-into-lake seams** (the P2 hydrology rivers end in drawn
   lines on their lake discs — no mouth blend exists,
   `water_bodies.gd` builds ribbons and discs independently). Fix at
   the ribbon end: feather the last ~2 widths of the ribbon (alpha
   ramp in vertex COLOR, the shader honors it), fade its flow vector
   to zero so advection agrees, and drop the ribbon surface to the
   lake's live level over the overlap (both read the same hydrology
   level, so the seam is geometric, not hydrological). Estimate: one
   `_ribbon()` pass + a shader term.
4. **Waterline meniscus.** When the camera crosses `water_surface()`,
   a 2–3px painted band at the crossing line (screen-space, the
   depth-compare trick) — the crossing becomes an event. Cheap,
   pairs with S4.
5. **Underwater, the real painting (S4).** Promote the placeholder
   veil: WorldEnvironment fog keyframe swap (deep-pink density — a
   new `day_night.gd` key family, underwater joins the palette
   machinery), a gentle full-screen wobble, drifting motes (the
   particle language), the surface read from below (already
   `cull_disabled`) with foam silhouettes. ★ kitchen table: does the
   red sun cast painted light-ribbons down there, or is under a
   *quiet* painting? Glow is reserved; ribbons flirt with it.

**Fork price: zero** (shaders + one kernel + mesh builder edits).
**Determinism: presentation throughout.**

### 3 · Buoyancy — ride the analytic surface; the position

Things must float believably (the raft slot exists in the cards;
props at the shore should bob). Two postures were priced:

| Posture | Price | Verdict |
|---|---|---|
| **Analytic** — CPU mirror of tide + Gerstner sum (+ tanh(kd) shoaling via a Terrain depth read), 3–5 probe points per floater, spring to the surface | **7.6 µs/floater/frame measured**; deterministic by construction; works headless (it's just math) | **BUILD (S3)** |
| Sim-coupled — read the wave field / tier-2 depth under each floater | blocking readback **0.17 ms EACH** (measured); async (`buffer_get_data_async`, verified in 4.7) removes the stall but adds latency + nondeterminism + a GPU dependency for a ±12cm ripple (the field clamps at ±0.2m) | **Drawer.** The ripples are garnish; the swell is the meal, and the swell is analytic |

The honest wrinkle W1 accepted stands: the *player's* swim rides
`water_surface()` (flat + tide) while the sea VISUALLY rolls. S3
builds the CPU mirror anyway (`SeaSwell.surface_at(x, z, t)` — the
shader math replayed, scene-tested against known cases); floaters use
it fully, and the player's swim spring can adopt it later as a
`swim_swell` knob if the mismatch ever reads (in swell heavy enough
to matter, you are mostly looking at the water, not the horizon). ★

**Determinism: two tiers, named now.** Bobbing/lean = presentation
(stateless f(TIME, wind, fronts) — off the digest by construction).
The raft's POSITION once the player can ride it = gameplay = a
record + sim state (moored X, ridden like a platform), exactly the
mirror law. Nothing in S3 ships the riding — a drifting vehicle is a
kitchen-table want with traversal implications (the causeway/boat
question, PLAN_PHYSICS's "boats someday"). ★ S3 delivers moored
bobbing + a `FloatBody` helper; riding waits for the table.

**Fork price: zero** (an autoload helper + math).

### 4 · Snow — the cap is buildable today; the blanket is gated

The reality check first: snow is REAL in the sim (scalar cover,
lapse-rate snowline, melt into Hydrology — the machinery is honest)
and fake on the screen (a shader whitening band; nothing falls,
nothing holds a print). And the calendar is real: **the valley floor
cannot see winter until real winter** — but the volcano's 850m summit
crosses the snowline seasonally, storms drop the snowline hundreds of
meters, and dev time travel (`advance_hours` — the one door) makes
any of it testable today. So the plan splits at the snowline:

**Not gated (the mountain-cap tier — S5/S6 carry it):**
- **Snowfall.** The particle language's first showpiece: when a wet
  front rains at the focus AND the focus altitude is near/above
  `snow_line()`, rain streaks hand off to snow flakes (both read the
  same `rain_at` — one precipitation truth, two paints). Chunky
  posterized flakes, wind-blown by the one wind. ★ flake look:
  painted 4–6px daubs, 3 sizes, no sparkle textures.
- **Deformation trails.** The Grain wears white: above the snowline
  with cover, the SAME field stamps prints with a **higher repose**
  (snow holds near-vertical walls — footprints stay crisp), **no wind
  erosion** (decay rides melt: `SNOW_MELT_BASE + WARM` maps straight
  onto the existing decay term), and an **accumulation source term**
  (falling snow refills the field — the one genuinely new kernel
  term, a per-texel add while snowing, rate = the same number the
  Climate scalar accretes by). Patch albedo blends to the snow white
  above the line (the terrain band's math, reused).
- **Melt already works.** Meltwater → wetness + runoff is landed;
  trails melting out in an afternoon sun falls out of tying decay to
  the melt term. Nothing to build but the wiring.

**Gated (named, with what unblocks each):**
- **Valley winter blankets** — gated on (a) `Climate.snow` becoming a
  per-cell FIELD (the wet_grid pattern: 8×8 over the frame, each cell
  accreting under its own sky at its own altitude — a real but small
  sim change: hour_tick, `climate.snow_grid` mirror, catch-up, digest
  moves once), and (b) **her seasonal palettes** (STATUS placeholder
  ledger: "seasons change daylight/weather only (→ her seasonal
  palettes)"). Winter is a different painting — code must not fake
  what she hasn't painted. ★★ the palette is the gate, not the tech.
- **Deep snow slows movement** — crosses INTO the sim. Priced both
  postures: presentation-only cover can NEVER touch movement (the
  soak would lie); the sim posture needs the snow_grid above plus a
  depth read in the player/agent movers (then wildlife heading for
  shelter in deep-snow cells falls out of the utility AI for free).
  Cheap AFTER the grid exists; illegal before. S7 owns it.
- **Ice** — nothing freezes today (no clamp in the thermal field).
  Frozen ponds are a whole design conversation (traversal! fishing!
  the pond thermometer!), not a substance rung. Drawer, kitchen
  table. ★

**Fork price: zero** (kernel term + shader + particle records).

### 5 · Sand — one field, three paints (the unification)

PLAN_PHYSICS S1 (response tuning), S2 (visible wind life), S3 (mud)
stand exactly as written — this plan does not re-plan them. What it
adds is the claim the snow dimension needs, **verified against the
code**: the Grain generalizes to a substance table.

True (verified): stamps/masks/plow/crater are substance-agnostic;
repose is already climate-modulated (wet bonus — the mechanism IS a
parameter); decay is one term (wind for sand, melt for snow, slow
rebound for mud); the patch shader already blends albedo. The honest
caveats: (a) snow needs the **accumulation source term** (sand
conserves, snow is deposited — one kernel add, small); (b) the field
is **one window with one parameter set** — the patch picks its
substance from ground context at the anchor (above snowline+cover =
snow; wetland+wet = mud; else sand), and a footprint left in sand
does not survive the patch re-anchoring into snow country (it never
survived leaving the window anyway — same law); (c) mud's
no-ejecta/slow-rebound response is a response-curve swap, exactly as
PLAN_PHYSICS S3 already planned. So: **SubstanceField = SandField + a
per-substance constants row** `{repose, flow, decay_src, accum,
albedo, print_depth_scale}` — data, not a second engine. NPCs join
wildlife as stampers when bodies land (one call site).

Dune-face avalanching: already real (the repose flux slides
oversteepened faces). Making it *visible* under gales is sand-S2's
streamers, not new physics.

**Fork price: zero. Determinism: presentation** (transient window,
no save — the standing sand law).

### 6 · Particles — one language for the falling sky

Today's 12 emitters are good instincts wired ad hoc — each hand-built
in `_make_particles()`, gated by its own if-chain. The Niagara lesson
isn't the tech (GPUParticles3D is enough); it's the *system*: *one
vocabulary, per-substance emitters, all driven by the same weather.*

**The shape:** `data/particles/*.json` records (the flora-species
pattern applied to the sky): emitter = {slot, mesh/billboard, counts
per tier, gates (weather kind / biome / season / time / altitude vs
snowline), wind response (tilt/drift/turbulence scale), palette
family, collision class}. One `ParticleKit` builder in the Elements
replaces the hand-rolled `_make_*` bodies; atmosphere.gd becomes a
consumer. New emitters this unlocks, in order of want: **snowfall**
(D4), **surf spray** (posterized puffs along the W2 breaker band and
at waterfall lips — the band's `break_x` mirror math already knows
where), **splash bursts** (`emit_particle()` at every wave-field
`disturb()` above a strength threshold — entry splashes get a visible
crown), **leaf/petal fall** (season + biome, her paintings as
billboards), plus the existing roster re-homed unchanged.

**Collision, budgeted:** ONE `GPUParticlesCollisionHeightField3D`
near the focus (512–1024 res, ~64m, follow-camera) so rain dies ON
the ground (splash sub-emitter via `SUB_EMITTER_AT_COLLISION` — rain
sparks a tiny crown where it lands, snow just stops), instead of
clipping through overhangs. Update mode WHEN_MOVED + follow-camera
(the terrain is static at particle timescales; the sand patch's 10cm
displacements don't earn ALWAYS' per-frame depth re-render).
Estimated, not measured: one small top-down depth pass on re-anchor —
if it reads >0.2 ms in the Toolkit line, resolution drops to 512 or
collision stays rain-only. **No SDF bakes ever** (static, offline,
wrong for a streamed world).

**Budget per tier** (knobs, Toolkit `PARTICLES` line): near ≤ 3000
alive across all emitters (today's rain alone is 1400 — the record
counts make the total *visible* for the first time), one collider,
zero attractors until a want names one (the vector-field attractor is
the drawer for valley-wind-over-a-ridge streamlines someday).

**Fork price: zero** — and stated deliberately: ParticleProcessMaterial
has NO global wind input (engine fact), which tempts an engine patch.
Not taken: the ParticleKit sets per-material gravity/turbulence from
`Weather.wind` each frame (the rain tilt already does this) — an
autoload loop over a dozen materials, not a fork patch.
**Determinism: presentation** — headless-gated, local RNG, no state,
the atmosphere.gd law.

### 7 · The laws, per item (determinism + fork, the full table)

| Item | Tier | Digest | Fork |
|---|---|---|---|
| Wave-grid sources/wakes/splashes (S1) | presentation | never (off headless, no state — existing WaterWaves law) | zero |
| Foam memory channel (S2) | presentation | never | zero |
| Mouth feather / foam fades / meniscus (S2/S4) | presentation | never | zero |
| Buoyancy bobbing (S3) | presentation (stateless f(TIME, sim-owned wind/fronts)) | never | zero |
| Raft position/mooring, if ridden (future) | **SIM** — record + WorldState, hour-tick if it drifts | joins when built (mirror law) | zero |
| Snowfall/spray/splash particles (S6) | presentation | never | zero |
| Snow/mud trails in the substance field (S5) | presentation (transient window — the sand law) | never | zero |
| Per-cell snow cover field (S7) | **SIM** — hour_tick, `climate.snow_grid` mirror, catch-up, load_state | **moves once**, then bit-stable (the wet_grid precedent) | zero |
| Deep snow slows movement (S7) | **SIM** (reads the snow grid; illegal before it exists) | rides the grid's digest | zero |
| Particle collider / ParticleKit | presentation | never | zero |

The one rule that keeps all of this safe: **interaction fields are
player-driven and must never feed a sim read.** The day gameplay
wants to READ a substance (deep snow, a footprint a tracker follows),
that state gets a sim-owned twin on the contract — the field never
becomes load-bearing by accident.

## The gouache look (positions, so the rungs don't drift AAA)

- **Rings are brushstrokes.** Wave-grid displacement is already
  clamped ±0.2m and the foam posterizes to 3 steps — S1's new sources
  inherit the language for free. If dense rain-rings ever read as CG
  interference patterns, posterize the *field read* (quantize wave_h
  into 4–5 bands in the shader — the fabric `flap_posterize`
  precedent; decide at the probe, keep the knob). ★
- **Foam is curds, not mist.** The memory channel must produce
  painted shapes that hold, then vanish — decay in visible steps
  (posterize the foam age too) rather than a smooth fade. ★
- **Distance is stillness.** Far water is a flat color field with the
  sun's one painted glint. The distance-fade isn't a performance LOD;
  it's how gouache paints far water.
- **Snow is paper.** The snow albedo is near the paper white the UI
  already speaks; prints are blue-shadowed dents (the patch shader's
  edge-darkening, cooled). Sparkle, if it ever comes, is the terrain
  sun-glint language above the snowline — never a glitter texture,
  and never emissive (glow is reserved). ★
- **Flakes and spray are daubs.** 3 sizes, painted, tumbling slow.
  Storm snowfall is a different painting (dense, wind-laned), not
  more of the same flake.
- **Splashes are crowns.** 5–9 particles in a ring, one frame of
  white, gone — the children's-book splash, not droplet spray.

## Milestone ladder (each rung fleet-sized, probe + Toolkit hook included)

*"S" here = substances. PLAN_PHYSICS's sand track is cited as
sand-S1..S3 to keep the namespaces apart; its W3–W5 remain that
plan's rungs and interleave freely with these.*

**S1 · Everything that moves rings the water (the ALIVE rung).**
Wildlife/NPC/creature wading + splashdown feed `disturb()` (hook
beside the sand-stamp call sites); swimmer wake trains (periodic
offset splats astern — interference draws the V); entry/exit rings
scaled by mass; window 64→128m at 1024² (0.114 ms measured, knob
kept). Toolkit: WAVES line grows sources/frame + window echo. Probe:
`tests/wave_probe.tscn` — a hound crossing the ford, calm|storm A/B.
✓ A hound crossing the ford rings the water and the rings outlive
its crossing; your wake trails a swim; rain pocks rivers while chop
streaks the lake; soak untouched.

**S2 · The water remembers (foam memory + the flagged eyesores).**
rg16f wave field: foam deposit (crests, disturbances, breaker band),
advection along flow, stepped decay; foam distance-fade into painted
stillness (the "too white at distance" fix); river-mouth feather into
lake discs (alpha + flow + level agreement); lake calm-band check.
✓ Foam born at a breaker rides ashore and dies on the sand in ~6 s; a
lake at 400m is a quiet color field; a hyd river enters its lake with
no drawn line. Soak untouched.

**S3 · Things float.** `SeaSwell.surface_at(x,z,t)` CPU mirror
(scene-tested against the shader math on pinned cases); `FloatBody`
helper (3–5 probes, spring + lean); the raft card floats at its
mooring; shore props (nets, buoys someday) opt in via card field.
✓ The raft bobs and leans with storm swell and sits flat at dawn calm;
30 floaters cost <0.25 ms (bench pinned); soak untouched. Riding
waits for the table ★.

**S4 · Under the surface is a painting.** Fog keyframe swap +
underwater palette family in day_night; waterline meniscus band;
wobble + motes; surface-from-below with foam silhouettes; the
placeholder veil retires. (WATER_REVIEW §3.1 promoted, minus breath —
that ★ stays at the table.)
✓ Diving at golden hour is a scene: pink fog, dark bulb-flora
silhouettes, the surface a moving painting overhead.

**S5 · The field wears three paints (substance unification).**
SubstanceField = the Grain + per-substance constants
{repose, flow, decay source, accumulation, albedo}; ground-context
pick at re-anchor; snow trails above the snowline (accumulation term
while snowing, decay = melt); mud adopts sand-S3's curve; NPC stamps
when bodies land. CPU reference + conservation tests extend per
substance.
✓ Prints above the snowline hold crisp walls and refill under
snowfall; the wetland trail goes glossy and pressed after storms;
conservation tests pass in all three paints. Soak untouched.

**S6 · The sky has substance (the particle language).**
`data/particles/*.json` + ParticleKit builder; existing emitters
re-homed; snowfall (rain→flake handoff at the snowline), surf spray
along the breaker band + waterfall lips, splash crowns via
`emit_particle` on strong disturbs; ONE heightfield collider with
AT_COLLISION rain splashes; Toolkit PARTICLES line (alive counts vs
budget, collider cost).
✓ One JSON adds an emitter; a cold storm snows on the summit while
the strand gets rain — same front, two paints; rain visibly lands.
Soak untouched.

**S7 · Winter arrives (gated — do not start before its gates).**
Per-cell snow grid (wet_grid pattern; digest moves once), cover
rendering by cell + altitude, deep-snow movement (the sim posture),
wildlife sheltering from deep cells. GATES: her seasonal palettes
(★★ kitchen table + ASSETS_NEEDED), the snow-grid design blessed at
the table. Test via dev time travel + forced fronts long before real
December proves it.
✓ A three-day winter storm blankets the valley by cells (windward
flank first — the rain shadow, in white); paths through deep snow
cost visible effort; the soak moves once and pins.

**Order:** S1 → S2 are one arc (the water answers, then remembers) —
the "really really nice water" ask lands there. S3/S4 as mood strikes
(each independent). S5 before S6's snowfall if snow should *hold*
what falls (recommended); S6's non-snow rows anytime. S7 waits for
its gates. Interleaving with PLAN_PHYSICS: W3 (swash) + S2 share the
foam language — do S2 first so swash tongues deposit into the memory
channel; W4 (sediment) pairs beautifully with S5 (one window, sand
AND water moving).

## Do-not-build (the fence)

- **No photorealism, structurally:** no FFT ocean (Gerstner bands
  landed and read; the W1 exit clause stands only if regularity
  offends at the probe), no Jacobian foam, no caustics, no SSR
  upgrades, no subsurface scattering, no normal maps on anything
  (Art Bible Law 1).
- **No SWE momentum bodies, no 3D fluid grids** (Niagara Fluids 3D
  territory). The tier 2 / 2.5 split (transport / reaction) is the
  architecture; a third family needs a design want neither can fake.
- **No sim-coupled buoyancy.** 0.17 ms per blocking probe vs 7.6 µs
  analytic — measured; the drawer note names async readback if a
  future want (a boat riding the wave FIELD in a harbor cinematic)
  ever justifies it.
- **No second deformation system.** Snow trails, mud, sand: one
  field, one conservation test, a constants table. If a substance
  can't express itself in the table, that's a kitchen-table
  conversation, not a fork of the Grain.
- **No per-frame particle SDF bakes; no UPDATE_MODE_ALWAYS collider**
  unless the Toolkit line proves it cheap. No particle attractors
  until a want names one.
- **No snow content before its palettes.** The blanket waits for her
  winter (S7's gate) — the cap tier (S5/S6) is the honest scope until
  then.
- **No second wind, no second precipitation.** Flakes, spray, chop,
  drift — all read `Weather.wind/wind_dir/rain_at`. One sky.
- **No engine patches for any of this.** Every rung is compute +
  shaders + render targets + script — extension-point territory end
  to end (verified against the fork's 4.7 surface).

## What was measured vs estimated (the honesty section)

**Measured, this machine, committed probes:** the shipped wave kernel
at 512²/1024²/2048² (0.054/0.114/0.331 ms per step, MoltenVK — upper
bounds vs native Metal); blocking 16-byte readback (0.169 ms);
CPU Gerstner buoyancy (7.6 µs × 1 / 57 µs × 8 / 216 µs × 30 floaters,
GDScript). Inherited measurements leaned on: PLAN_FABRIC's SoftBody
floor + verlet ceiling (the "wants are CPU-cheap" precedent), the
sand field's established budget (PLAN_PHYSICS Law 3's bar).

**Estimated, honestly:** the foam channel's marginal cost (bounded by
the same-dispatch argument, unverified); the particle collider's
depth-pass cost (engine-code-read, not timed — gate on the Toolkit
line); snowfall emitter cost (bounded by the existing 1400-particle
rain); all authoring/wiring effort per rung. The "too white at
distance" and mouth-seam items are Nicco's eye-check notes taken on
faith — neither is reproduced in a committed probe yet; S2's probe
should capture before/after shots of both.

**Probe hygiene:** `wave_bench` and `buoy_bench` are labeled
THROWAWAY and prove prices, not features. The Metal-CLI-crash and
no-headless-RD findings they recorded are environment facts worth
keeping (they shape every future compute probe).

## Open questions (kitchen table)

- **The raft** ★: moored prop (S3 ships it) vs ridden vehicle — the
  boat conversation PLAN_PHYSICS deferred. Riding is traversal
  design, not substance work; but S3's mirror math is the half that
  makes it cheap later.
- **Winter palettes** ★★: the S7 gate. Does she paint winter as one
  keyframe family or per-biome? (The palette table says biome ×
  time-of-day; winter adds a third axis.)
- **Underwater's palette moment** ★: quiet painting vs the red sun's
  light-ribbons (glow-law tension — same question PLAN_PHYSICS asked
  of swell crests at golden hour).
- **Frozen water** ★: the thermal field can freeze ponds honestly —
  but ice is traversal + fiction (what does the glow-phenomenon do
  under ice?), so it waits for the axioms.
- **Ring posterization** ★: decide at the S1 probe — smooth field vs
  quantized bands (the fabric precedent says ship the knob).
- **Does spray join the pink hour?** Surf spray at golden hour in
  the water_gold language — or is airborne water always paper-white?
