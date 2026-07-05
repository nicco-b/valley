# Status — read this first when resuming

*As of 2026-07-03 (day three: the deep-sim build-out — 1:1 real time,
real seasons/sun/moon, climate/flora/rumors/wildlife, SIM_ROADMAP Phase
A+B starts, and the GPU granular sand simulation; ~91 commits, all
pushed to github.com/nicco-b/valley). This file is the live state;
update it when things change. The doc map: [DESIGN.md](DESIGN.md) = what the game is ·
[FOUNDATIONS.md](FOUNDATIONS.md) = build plan & backlog · [DEV_GUIDE.md](DEV_GUIDE.md)
= how to work on it · [DECISIONS.md](DECISIONS.md) = settled questions ·
[IDEAS.md](IDEAS.md) = the drawer · [ASSETS_NEEDED.md](ASSETS_NEEDED.md) =
the human-made shopping list · [lore/](lore/) = canon (axioms pending) ·
`/CLAUDE.md` = conventions + gotchas for AI sessions.*

## What exists and works (all tested; run `./scripts/test.sh`)

**World** — streamed 128m cell grid (threaded generation); one height
function feeding near terrain, far-terrain LOD to the horizon, and the map
("if you can see it, you can go there" — the distant mountains are real);
authored valley landform (spawn → pond ~310m → shrine ~620m); god-mode
sculpt layer (EXR); painterly terrain shader (height/slope bands, wind
ripples, sun glints); scattered flora from her 3 paintings + dense
ground-cover stratum (placeholder SVGs); **water bodies as records**
(`data/water/*.json` lakes = basin + surface height; `rivers/*.json`
rivers = node polyline with per-node width + surface; Terrain carves
basin/channel and answers `water_surface()`, ribbon/disc surface meshes
built from records, painterly flow shader scrolls downstream — a new lake
or brook is one JSON file; swimming, navmesh carving, moisture floors,
flora/cover submersion all read the same records; first authored brook
feeds the pond); **whole-watershed hydrology** (DECISIONS 2026-07-04:
tier 1 of 3 — the Hydrology autoload flow-routes the entire valley once
at boot (priority-flood pit filling + D8 on a 256² grid, on a worker
thread) giving every river/lake its real catchment, then runs an hourly
water balance forever: storm runoff scaled by ground saturation,
snowmelt, spring baseflow, river reservoirs, lake evaporation/outflow;
water surfaces ride the live levels via `Terrain.water_surface()` while
cell generation reads the authored base — the pond visibly swells in
storms and drops through droughts, the brook's flow speed tracks real
discharge, fords open and close unscripted; state is per-basin scalars
on the sim contract: hour_tick, WorldState `water.*`, catch-up, soaked
deterministic); **tier 2 — live water dynamics** (WaterField autoload +
WaterGpu: one 1024² GPU depth field at 2m texels over the WHOLE 2048m
watershed, same budget as the sand field; pipe-model flux kernels flow
rain down the real terrain, pool it in hollows, drain it into the ground
(seepage-bounded so flat ground never floods) and into the authored
water bodies as sinks; a WaterSheet patch follows the player and lifts
its vertices onto the live field, discarding where dry; a one-thread
readback probe feeds `current_at()` — the river/field current now pushes
the player downstream, real effort upstream; presentation-only —
disabled headless, never saved, never fingerprinted; tier 3, the
near-window sediment coupling, is the remaining seed); **tier 2.5 —
the wave field** (WaterWaves autoload + WaveGpu: a 512² damped
wave-equation window at 12.5cm texels following the player; wading
strides ring the surface, storm rain pocks it, wind keeps a chop; the
water shader displaces VERTICES by the field — lake discs and river
ribbons are now vertex-dense so the surface actually moves; scrolls
with the focus, presentation-only, off headless); **water that
reads as water** (the shader composites the refracted bed
through the surface — screen-space refraction bent by ripple + wave
normals, light drunk toward the deep pink with depth — plus painted
posterized foam at shorelines, wave crests, fast water, and stirred
wading; still the pool's pink language, Elden Ring's recipe in gouache;
the compute-kernel compile check now runs headless in scene tests so CI
catches GLSL errors); pond
with wading/swimming and
ripple wake; day/night palette cycle; custom sky (swelling red sun, stars);
weather (calm/windy/storm) driving sway, audio, fog, dust, and NPC shelter;
interaction field (80m coarse: desire-path wear, distant trails) +
**granular sand simulation** (GPU compute when available — 1024x1024
field at 2.3cm texels over 24m, apply/relax/scroll kernels, renderer
samples the field directly via Texture2DRD, zero CPU texel work; CPU
threaded reference otherwise — a heightfield sim in a 20m
window: signed sand volume in meters, CONSERVED — footsteps displace
material into ejecta ridges, landings blast craters with thrown rims,
moving feet plow bow waves; cells past the angle of repose avalanche
downhill each tick, so pits slump shut and ridges slide; wet raises
repose, wind erodes; rendered as real geometry by a 9.4cm sand patch;
sand-slide traversal on steep slopes — the Journey move; conservation
unit-tested; visual probe verifies eight framings); ambient
particles (sand motes, dusk moths from her painting, night glow-motes).

**Simulation** — GameClock (**1:1 real time** — a game day is a real day;
wall-clock driven, hour_tick bus, time_scale for Stillness); **real
seasons, real local sun** (season + daylight + sunrise/sunset from the
system date and geolocated latitude/longitude — solar declination +
equation of time, hemisphere-correct; new worlds anchor the clock to
real local time; sun/palette/dusk-audio/creatures follow via
`solar_hours()`; storms season-biased; `time.season` in WorldState for
conditions; dev time travel: T → next sunrise/noon/sunset/midnight,
Shift/Alt+T → +day/+week, always lived via `advance_hours`;
Shift+Alt+T → back to now, re-anchoring the dial to real time); the ambient machine: saves carry a wall-clock timestamp and time away/asleep is
replayed via shared `GameClock.advance_hours()` catch-up (weather rolls,
NPCs live the skipped hours — needs/position/activity persist hourly);
FocusThrottle (unfocused window fps-capped but watchable, minimized
near-idle); needs/utility NPC AI from records; two-tier (bodies dissolve
>170m, coarse sim continues); sim inspector (god mode → right-click NPC).

**Deep sim (built 2026-07-02, the six-domain pass — every sim obeys the
CLAUDE.md sim contract):** Climate substrate (`temperature(x,z)` +
`moisture(x,z)`; rain soaks / warmth dries; wet ground darkens via
`ground_wetness`); FloraLife (valley-wide vitality chasing climate over
days; billboards dry toward straw via `flora_vitality`; writes
`valley.bloom`/`valley.parched` — first sim-authored story-seed, "The
Dry Spell", with journal seed-latching so transient states can open
quests); real moon phase (stars wash out, glow-motes/fireflies thin
under a full moon; `sky.moon_phase`); rumors (NPCs notice valley-scale
events, hold 12 facts oldest-forgotten, mirror them as
`npc.<id>.knows.*` flags for dialogue, and swap news when they share a
place for an hour); wildlife tier-3 (star-hound herd as pure data —
drink at dawn, shade at noon, prowl — embodied only near the focus;
`data/wildlife/*.json`); long memory (NPC pantry stocks from
`produces` activities → `npc.<id>.stock.*`, ready for trading;
permanent desire-path wear layer persisted in the save, fading over
game-months; placed records stamp their day for future weathering).

**RPG** — WorldState (all flags/values, saved); records loader with
validation; interaction layer (E); items + satchel (I); fireflies (catch at
night / F deploys orbiting light swarm / R recalls); dialogue engine
(records in data/dialogue/, conditions/effects, familiarity-aware); quests
(declarative over WorldState, journal on J); use-based skills (Wayfaring/
Stillness—bends time while sitting/Swimming/Foraging); two inhabitants —
the Wanderer (pink scarf) and the Keeper (teal, tends shrine) — who know
each other; first errand quest "Between Two Solitudes".

**Characters** — Blender creature pipeline live (assets/blender/creatures/
README.md is the contract): scripted low-poly build → rig → clip set →
glb export. Two creatures built: the biped fox (**now the player body**,
from her painting) and the star hound (fully animated, currently unplaced).
NPCs (Wanderer, Keeper) still ride the CC0 robot placeholder.

**Shell/tools** — title screen, pause/settings, autosave (**hardened
2026-07-04:** atomic write via tmp+rename, rotating `.bak1`/`.bak2`
refreshed ≤ every 10 min, load falls back live → bak1 → bak2 with a
warning — a torn save costs minutes, never the world); god mode (F1:
fly/sculpt/place/inspect); live map (M, gestures); hot-reload of paintings;
place mode writing cell records; gamepad support (physics interpolation
was tried 2026-07-04 and REVERTED: a streamed world teleports/adds nodes
every frame — cells, scatter, sand patch, water sheet — and each arrival
renders as a white streak without a per-node reset_physics_interpolation
pass; adopt deliberately later with interpolation OFF on procedural
nodes, or accept the 60/120Hz micro-judder); CI on
GitHub (Linux + **macOS-14/Apple Silicon** — the shipping platform;
note test.sh is headless, so Metal compute kernels still only run under
a local windowed session); test
harness (unit + scene + dual smoke). The home valley has hand-composed
places (pond oasis + surrounds) authored via place mode — cells in data/cells/.
**Pending, needs both machines:** Git LFS adoption — `.gitattributes`
patterns are written (in the 2026-07-04 handoff patch) but NOT committed
because git-lfs isn't installed here yet; install on both machines, then
commit the attributes and (optionally, history rewrite — coordinate!)
`git lfs migrate`.

## Placeholder ledger (each has a named replacement path)

Biped fox player (hers, replaced the star hound as the player body
2026-07-02) and the star hound (now placed as the placeholder *wildlife*
body — a herd with daily lives west of the pond → rename/re-skin when
canon names the valley's creatures). The fox now
renders through character_paint.gdshader (gouache wash/grain/edge-dark
in-engine, restoring what the flat glb export loses); apply the same
CharacterPaint pass to the star hound and NPC models when they land ·
synth wind + footsteps
(→ his recordings; night bed is a CC0 field recording, see
assets/audio/SOURCES.md) · SVG tufts/pebbles/cactus (→ her painted PNGs,
same slots) · noise terrain beyond the valley (→ painted region tiles,
FOUNDATIONS F3) · all dialogue text (→ post-axioms rewrite) · seasons
change daylight/weather only (→ her seasonal palettes + flora states when
painted) · location via one-shot IP lookup (→ settings-screen location
picker).

## Next up (in rough priority)

0. **[SIM_ROADMAP.md](SIM_ROADMAP.md) Phase A — in progress** (started
   2026-07-02 on "go"): ✅ A1 determinism (Rng streams) + soak harness
   (30 days headless ×2, fingerprint-matched) · ✅ A2 AgentSim core
   (wildlife ported, fingerprint bit-identical; NPC is the second
   adopter, with the village) · ✅ perception v1 (wildlife wariness:
   light-scaled sight, hearing, alert/flee/resume) · ✅ navmesh-per-cell
   (baked per streamed cell on the worker thread from terrain triangles,
   water carved out; NPCs and wildlife walk waypoints via PathCursor,
   straight-line fallback where no navmesh exists; god mode N toggles
   the overlay) · ⏳ remaining: far waypoint graph (with the first
   authored road — an empty graph is scaffolding), NPC AgentSim port
   (with the village). **Phase B started:** ✅ snow (cover state +
   emergent snowline from the lapse rate, meltwater soaks the ground) ·
   ✅ wind direction (wanders hourly, swings in storms; sand ripples and
   dust follow it) · ✅ herd cohesion (roam draws around the group's
   drifting centroid) · ⏳ per-cell flora + species records next;
   population dynamics gated on the life-timescale axiom.

1. **Asset track (humans)** — see ASSETS_NEEDED.md. Top: her ground-cover
   kit, his Blender rock family, real wind recording.
2. **Canon track (kitchen table)** — the axioms conversation
   (docs/lore/axioms.md is scaffolded); gates all real writing. Pending
   decisions: field-recordist player mechanic (IDEAS ★), no-compass
   Morrowind navigation (must precede quest writing).
3. **Code: G4 remainder** — inventory/item-use UI (eat, examine, gift),
   trading (needs the errand pattern + prices).
4. **Code: G6** — NPC-to-NPC ambient meetings (they cross paths at the pond
   daily and ignore each other — though they now trade rumors there);
   proper navmesh before more NPCs; extract the shared sim core
   (NPC/wildlife utility logic → one RefCounted, three presentations)
   when the village lands.
5. **Code: G5** — region tile pipeline (painted heightmaps) when the world
   wants to grow; biome mask when region #2 exists.
6. **Code: G1 leftovers** — save slots, macOS export build.

## How to resume

`./scripts/run.sh` plays · `./scripts/test.sh` before every commit ·
`godot --path . -e` opens the editor · full keymap + recipes in
DEV_GUIDE.md. For AI sessions: CLAUDE.md carries every hard-won gotcha
(tscn rules, import traps, autoload-vs-`-s` compile order, etc).
