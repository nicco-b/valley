# PLAN_FABRIC — cloth in the wind (fabric physics)

*2026-07-08, from Nicco: "i want my characters and other things in the
game to have fabric physics if we don't have it already. clothing,
fabrics, and whatever else." Companion to `PLAN_PHYSICS.md` (same
laws, same voice). The Elements wear the clothes; the Loom hangs the
banners.*

## Executive summary

We have no fabric anything today — but we have every ingredient: one
wind truth already published to all shaders, a proven wind-displacement
vertex pattern (the ocean IS this), skeletons with danglable bones on
every creature, and an engine (4.7) that ships native spring bones with
an `external_force` input. The verdict, measured on this machine:

- **World fabric** (banners, awnings, tents, sails, nets, drying
  lines) → **shader vertex animation** (option 2). Zero sim cost,
  deterministic by construction, the exact W1/flora pattern.
- **Character clothing** (cloaks, hoods, straps, tails, ears) →
  **spring bones** (option 3), via the engine's `SpringBoneSimulator3D`
  fed `Weather.wind` as `external_force`; our GDScript verlet ceiling
  measures 6.9 µs per dressed character — thirty dressed characters
  cost 0.19 ms even in script, and native is cheaper.
- **SoftBody3D** (option 1) works under Jolt in 4.7 (measured, to our
  surprise) but carries a ~1.2 ms/frame floor the moment one exists,
  has no wind API, and buys nothing the first two don't. **Drawer.**
- **GPU cloth kernel / fork work** (option 4) → **priced out.** The
  measured want is <0.2 ms on CPU; fork law says extension points
  first, and we never reach them.

F1 (wind-driven banners on existing textile/camp slots, one shader) is
the cheapest visible win and needs nothing that doesn't already exist.

## Where fabric stands (inventory, 2026-07-08)

**The wind truth (one, already):** `Weather` (autoload, the Elements)
owns `wind` (0..1, eased per-frame from the front kind over the focus,
biome- and ridge-scaled) and `wind_dir` (Vector2, wanders hourly, sim
contract, saved). Every frame it publishes BOTH as global shader
parameters: `wind_strength`, `wind_dir` (`weather.gd` `_process`).
Consumers today: `flora_sway.gdshader` (billboard sway),
`terrain.gdshader` (sand ripple direction), `atmosphere.gd` (cloud
drift, rain slant), `water_waves.gd` (wind chop), `sea_swell.gd`
(Gerstner swell direction + front heralds), `climate.gd` (humidity
advection), `sand_field` wind erosion, `player.gd` (wind push).
**Fabric adds consumers, never a second wind.**

**Who would wear cloth:**
- Player rides `biped_fox.glb` — 19 joints, including `ear.L/ear.R`
  (danglable today).
- `star_hound.glb` — 23 joints including a five-bone tail chain
  (`tail.1..4`, `tail_star`): a free F2 demo rig.
- Two NPCs (Wanderer, Keeper) still ride the CC0 `robot.glb`
  placeholder (43 joints). The eight villagers exist only as asset
  cards (`assets/models/chars/*.card.json`) — **no humanoid bodies
  exist yet to dress.**
- 15+ wildlife slots are cards, statuses placeholder.

**World fabric candidates (the Kit):** `props/textile` (5 placeholder
variants — flat painted sheets from `gen_meshes.py`, no pole, nothing
that hangs), `props/camp/tent`, `props/nautical/{net,raft}`,
`signage`. The village architecture kit (awnings, stalls) is a ★★★
ASSETS_NEEDED item, unbuilt. So F1 also wants one new placeholder
shape (a hung banner/flag) — today's textiles lie flat on the ground.

**Engine surface (stock 4.7-stable = the fork's base, Tier 1):**
`SoftBody3D` simulates under Jolt (verified — the old "Jolt has no
soft bodies" lore is stale in 4.7). `SkeletonModifier3D`,
`SpringBoneSimulator3D` (with `external_force` + per-joint gravity),
`PhysicalBoneSimulator3D` all present.

## Measurements (headless, this machine, 2026-07-08)

Probes committed on this branch: `tests/fabric_softbody_probe.tscn`
(FABRIC_N/FABRIC_RES env) and `tests/fabric_verlet_bench.gd`.

**SoftBody3D under Jolt** (pinned 1.0×1.6 m cloth panels, precision 5,
avg physics ms/frame over 300 frames after 60 warmup;
`Performance.TIME_PHYSICS_PROCESS`):

| Config | physics ms/frame |
|---|---|
| 0 bodies (baseline) | 0.064 |
| 1 body, 16×16 (~256 verts) | 1.227 |
| 4 bodies, 16×16 | 1.270 |
| 8 bodies, 16×16 | 1.405 |
| 1 body, 24×24 (~576 verts) | 1.443 |
| 116 bodies, 16×16 (accidental big run) | 8.2 |

Read: **a ~1.15 ms/frame fixed cost the moment any soft body exists**,
then a cheap ~15–35 µs marginal per body (Jolt threads them). Stable
(drapes, settles, no explosion at rest). Determinism: bounds
fingerprint bit-identical across two runs (`FP -0.499999762
1.069605231 …` twice) — fixed-tick physics is repeatable on one
machine, but nothing guarantees it across thread counts/platforms, and
it's frame-locked to the physics tick, not to sim hours: presentation
tier regardless. Caveat: headless = dummy renderer, so the per-frame
mesh re-upload cost isn't in these numbers; live cost is higher, never
lower. And SoftBody3D has **no wind input** — coupling it to Weather
means faking wind with moving pins or an Area3D gravity tilt. Wrong
tool for a windy game.

**GDScript verlet chains** (option 3 ceiling; 6 chains × 5 points per
"dressed character", 2 constraint iterations, wind + gravity, plus
Skeleton3D pose-write cost):

| Config | µs/frame |
|---|---|
| 1 dressed character | 6.9 |
| 10 characters | 65 |
| 30 characters | 194 |
| 60 bone pose writes | 2.1 |

Read: secondary motion is **free at any plausible population**, even
in script. `SpringBoneSimulator3D` does the same math in C++ inside
the skeleton update with collision spheres/capsules included — use it
first; the bench is our fallback ceiling if we ever need custom
behavior it can't express.

**Shader vertex animation:** not benched because the ocean already
runs 4 Gerstner components over two sea discs and the flora field
sways every card in view — the pattern's cost is established and
absorbed. Marginal cost of a banner: one more material in view.

## The verdicts (fabric class → option)

| Fabric class | Option | Why |
|---|---|---|
| World fabric: flags, banners, awnings, tent walls, sails, nets, drying lines | **2 · shader vertex animation** | Zero sim cost, reads the global wind uniforms directly, deterministic by construction (stateless in TIME + wind, exactly W1), works at any instance count, dies gracefully with distance |
| Character clothing: cloak, hood, straps, sashes — and tails/ears now | **3 · spring bones** (`SpringBoneSimulator3D`, GDScript verlet as fallback) | 6.9 µs/char ceiling measured; native modifier with `external_force` = wind plug-in; collision capsules included; authorable in the existing Blender rig convention (FOUNDATIONS F4) |
| Hero moments: a monumental shrine veil, a market canopy set-piece | **Start with 2** (authored mesh + tuned shader); SoftBody3D stays in the drawer for a scene-local, N≤4, cinematic-only case that earns its 1.2 ms | Measured floor buys nothing at our art scale; no wind API; gouache wants chunky painted folds, not simulated wrinkles |
| Everything at once, city-scale | **4 · GPU kernel — NOT BUILT** | Want is <0.2 ms on CPU; fork law: "anything achievable as a module, GDExtension, shader, or autoload stays OUT of the patch set" — we don't even reach GDExtension |

## Wind coupling (one truth, all consumers)

The law: **fabric never invents wind.** The banner, the dust, the
swell, and the hound's tail must agree or the world stops being one
place.

- **Shader tier:** read the existing `global uniform float
  wind_strength; global uniform vec2 wind_dir;` — no new plumbing, the
  uniforms are already published every frame. Gustiness is synthesized
  statelessly in the shader (two sine octaves phase-offset by world
  position, amplitude scaled by `wind_strength`) — the same trick
  `flora_sway` uses, so flags and flora gust in the same weather. If a
  shared gust *pulse* is ever wanted (a squall front visibly slamming
  a whole street of banners at once), Weather publishes one more
  scalar (`wind_gust`, eased from front lead) and every fabric shader
  reads it — still one truth.
- **Bone tier:** a thin `FabricSpring` wrapper sets each
  `SpringBoneSimulator3D.external_force = Vector3(Weather.wind_dir.x,
  0, Weather.wind_dir.y) * Weather.wind * k` per frame (plus the same
  positional gust hash, CPU-side). Character velocity feeds in for
  free — spring bones live in skeleton space and lag the body
  naturally.
- **Direction convention:** `wind_dir` is FROM→TO on xz (weather.gd
  doc); fabric streams TOWARD `+wind_dir`, same as cloud drift and
  sand ripples.

## Determinism stance (fabric = presentation, off the digest)

Exactly the PLAN_PHYSICS Law 1 / water-tier precedent (`WaterField`,
`WaterWaves`, `SeaSwell`: "presentation-only — off headless, never
saved, never fingerprinted"), and the map arc's rendering-only weather
exemption (STATUS 2026-07-08) as the exemption style to copy. How,
concretely:

- **No state:** fabric writes no WorldState keys, holds nothing across
  saves, never ticks on `hour_tick`. It is a per-frame function of
  (TIME, `Weather.wind`, `wind_dir`, character pose). The soak
  fingerprints WorldState + wildlife after `advance_hours` — fabric
  has, by construction, nothing to fingerprint.
- **Headless gate:** the house pattern — `if DisplayServer.get_name()
  == "headless": return` (sea_swell.gd line 48). Shader displacement
  never runs headless (dummy renderer); `FabricSpring` gates its
  `_process` the same way so soak/test runs never touch spring state.
- **Randomness:** none from the `Rng` streams. Phase offsets are
  position hashes (deterministic), gusts are sines of TIME —
  cosmetic-local like `water_waves`' local RNG rule.
- **Physics isolation:** spring bones don't touch the physics server;
  if a hero SoftBody3D ever ships it is scene-local to a cinematic and
  spawns only under a rendered window — never in headless runs, never
  colliding with sim-relevant bodies.

## The gouache look (position, from the art bible)

Cloth must read as *painted cloth in a children's-book wind*, not
simulated fabric. Taking a position now so F1 doesn't drift AAA:

- **Chunky folds, low poly ON PURPOSE.** A banner is 6–12 quads; the
  fold is a brushstroke, not a wrinkle field. (Law 5: boxy/wobbly is
  on-style; precision is not a goal.) This is also why SoftBody at
  16×16+ verts is aesthetically wrong here, not just expensive.
- **Matte paint, same ramps.** Fabric materials join the
  `character_paint` family: flat base color from the biome palette,
  value-noise wash, paper grain, gouache edge-darkening, `ROUGHNESS
  1.0`, no normal maps ever (Law 1). Banner colors come from the
  palette table (bloom pink, starburst gold, flora teal).
- **Low-frequency motion.** Two sine octaves max, like flora_sway —
  broad flag-waves, no high-frequency flutter. If the sway reads too
  smooth/CG at F1, posterize it: quantize the displacement phase into
  3–4 steps (the posterized-foam trick applied to motion) — decide by
  eye at the F1 A/B probe, keep the knob.
- **Storm is a different painting, not a louder one.** Calm = barely
  breathing; gale = hard streaming with the silhouette leaned full
  over (amplitude curve eases fast at the top, like the palette
  keyframes swap rather than dim).

## LOD / distance (fabric dies gracefully)

- **Shader fabric:** amplitude fades over camera distance in the
  vertex stage (`1.0 - smoothstep(120, 200, dist)`) into the
  wind-*leaned* rest pose, not the neutral pose — a distant banner
  still points with the wind (it's information: you can read the wind
  across the valley), it just stops animating. Beyond that, props
  unload with their cells (the Loom already owns this).
- **Spring bones:** active only while the body renders and within
  ~60 m; beyond, the modifier lerps its influence to 0 (the
  `SkeletonModifier3D.influence` knob exists for exactly this) and the
  chain snaps to the authored pose. The Understory already dissolves
  bodies >170 m — chains never outlive bodies. Budget knob in the
  Toolkit: max simultaneous chain-sets, nearest-first.
- **Hero cloth (if ever):** paused outside its cell, full stop.

## Milestone ladder (each rung agent-sized, probe + Toolkit hook included)

**F1 · The banners feel the wind (shader tier — the cheapest visible
win).** One `fabric_wind.gdshader`: vertex displacement with a pin
mask (from UV.y or COLOR — painted pin weights, so one shader serves
flags, awnings, tent walls), 2-octave sway, lean + amplitude from
`wind_strength`, direction from `wind_dir`, per-instance phase from
world position; fragment = the character_paint gouache treatment.
Asset cards grow an optional `"wind"` field (`"fabric"`); the Kit
applies the material override on placement for flagged slots. New
placeholder in `gen_meshes.py`: `props/textile/banner` (pole + hung
pennant, pin weights baked in vertex color) — today's textiles lie
flat; something must visibly hang. Toolkit: `FABRIC` line (flagged
materials in view, wind echo). Probe: `tests/fabric_probe.tscn`
A/B calm|gale shots (SEA_WX pattern).
✓ A gale whips the camp banners hard over while calm barely stirs
them, and their lean agrees with the dust, the swell, and the rain
slant. Soak bit-identical (shader + material override only).

**F2 · The tail and the ears (bone tier proves itself on what
exists).** `FabricSpring` (`SkeletonModifier3D` wrapper around
`SpringBoneSimulator3D`): auto-adopts configured chains, feeds
`external_force` from Weather per frame, headless-gated, influence
fades by distance. Wire the star hound's `tail.1..tail_star` and the
fox's `ear.L/R`. Toolkit: chain count + µs budget line.
✓ The hound's tail streams in a gale and lags a sprint turn; ears
flick back at a run. Soak untouched (no state, headless-gated).

**F3 · Cloaks (blocked on bodies — do not start before villager or
player models land).** Extend the FOUNDATIONS F4 Blender rig
convention: bones named `cloth.*` (cloak spine ×2, hood, straps) are
auto-adopted by FabricSpring with per-prefix presets; two collision
capsules (torso/legs) per rig. The Wanderer/Keeper robots do NOT get
retrofitted — the robot is a placeholder; dressing it is polishing
debt.
✓ First real dressed character walks into a gale and the cloak
streams, settles at calm, never clips the legs at a walk.

**F4 · The village flutters (content pass, no new code).** When the
village kit lands (★★★ shopping list): awnings, stall canopies,
drying lines, door curtains, boat sails (the raft slot; W-track's
"boats someday" note) — all F1's shader via card `"wind"` field, colors
from the palette table. This rung is authoring + placement only.
✓ A street of stalls reads as one weather: every awning agrees.

**F5 · Hero cloth (drawer — needs a story want).** A monumental
shrine veil or cinematic canopy. First try an authored mesh + tuned
F1 shader (chunky painted folds usually win at our art scale); only
if the moment truly needs draping contact, a scene-local SoftBody3D
(N≤4, ~1.3 ms measured, cinematic-gated, wind faked via pin puppet).
Re-measure on the fork build of the day before committing.

## Fork pricing

**Zero.** No rung touches the engine. Option 4 (GPU cloth
kernel-as-module) is explicitly priced out: the fork law admits
modules only for what extension points can't do, and the measured
CPU cost of everything we actually want is under 0.2 ms — three
orders of magnitude of headroom before a kernel conversation starts
(reopen if a future want exceeds ~30 simultaneous soft bodies or
~500 spring chains, which is not this game).

## Do-not-build

- **No full character cloth sim before characters exist.** The
  villagers are cards. F3 waits for bodies; nothing gets built "ready
  for them" beyond the rig naming convention (one paragraph in
  FOUNDATIONS).
- **No SoftBody3D in the streamed world.** The 1.2 ms floor buys
  nothing options 2+3 don't, it can't hear the wind, and fine
  simulated wrinkles are off-style (Art Bible Law 5).
- **No second wind.** No per-fabric breeze fields, no fabric-local
  weather. One truth: `Weather.wind` / `wind_dir` (+ at most one
  shared `wind_gust` scalar, published by Weather).
- **No fabric state.** Nothing in WorldState, saves, or the soak
  digest, ever. If a design ever wants persistent cloth (a banner
  that tears in a named storm), that's a *record* (prop variant
  swap), not a sim.
- **No engine patches for fabric.** Shader + modifier + autoload
  covers the whole ladder.

## Open questions (kitchen table)

- Do banners get palette *moments* — bloom-pink pennants at golden
  hour joining the water_gold language, or is cloth quiet on purpose?
- Should the wind-leaned distant rest pose feed the map view too (the
  chart showing which way the valley blows)? Cheap, charming, maybe
  noisy.
- Sails: when boats happen (W-track note), sail = F1 shader + a boost
  from boat speed — does the boat *read* the sail (sail as gameplay
  wind gauge), or is it dressing?
