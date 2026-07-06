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

**Shell/tools** — title screen, pause/settings (**UI pass 2026-07-04:**
`canvas_items` stretch so text/DPI scale with any window; one shared
`UITheme` (game/ui/ui_theme.gd) — gouache paper/ink/water-pink palette,
painterly StyleBoxFlat panels/buttons/sliders as labeled placeholders for
her painted 9-slices, fat pink focus rings; title/pause/journal wear it;
menus gamepad-navigable — focus grabbed on open, D-pad walks, Start/Esc
via ui_cancel; verified by tests/ui_probe.gd screenshots), autosave (**hardened
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

**Archipelago v3 — the Big Island (2026-07-05, Nicco's map-scale
call: "2-3x bigger, Hawaii, detailed coastlines, satellite chain, SF-
bay interior").** Usable land 15→49 km² (Big Island 42 km², one
landmass): an 850m Throat-of-the-World-class volcano (v3 called it
"Mauna"; v4's plain-names pass retired explicit Hawaii naming — real
names wait on the naming-language canon item)
(new `volcano` region kind — concave flanks + radial ridge/ravine
drainage; winter snowline crosses it, so the seasonal snowcap falls
out of the lapse-rate sim), the home valley untouched at its foot;
connecting lobes with **fractal coast noise** (new coast_amp/
coast_freq on all landforms — coves and headlands, not circles);
**the Bay** (new subtractive `bay` kind + `over_bays` flag) — an
SF-style enclosed interior sea east of the valley with Alcatraz-
Rock/Angel-Isle/Yerba islets, an eastern peninsula arm, and a gate
strait; the tiered city on the bay's SW shore; a trailing 7-island
chain ESE (pali volcano-mini, 7-tier terrace hill, barren isle,
stairstep ridge, smoke isle, skerries, the painted atoll). All
kernel-mirrored (parity <7e-5m), soak fingerprint UNCHANGED
(2183523517 — the watershed never saw a moved sample). Map zoom to
13km. Superseded entry below kept for the record.

**Archipelago feel-prototype v2 (2026-07-04, the Loom; v1 desert bowl
redone same day on Nicco's call: literal water, bounded world, smaller
city)** — the ~12km world shape as a disposable draft to fly and walk:
a **world sea** (`data/water/sea.json`, surface −2m; not a lake — no
basin, no hydrology reservoir) fills everything below it outside the
home guard; the ground beyond the valley sinks to a seabed (−35m) and
the procedural ranges fade out with it, so the horizon is water — the
sea IS the world's bound. Authored islands are **region records**
(`data/regions/*.json`, mesa/ridge/dome; every record carries the
`layer` field the F3 schema will need). The home valley is island #1:
`Terrain.home_guard()` (rect from the watershed record + 150–550m
noise-wobbled coast ramp) keeps every sample the Hydrology grid sees
bit-identical — soak fingerprint unchanged through the whole rework.
Islands: the metropolis mesa (210m, 5 tiers, rounded-riser terraces),
gate-dome islets, the stairstep ridge, the 7-tier terrace hill, a big
low barren isle; low **causeway ridges** link them until boats are a
thing. Sea renders as a wave-window patch following the focus + a
coarse horizon disc (water_bodies.gd). Hot path is packed
(region sampling ~+15% over valley baseline). NOT the final map.
Toolkit: `Terrain.regions_summary()`; `tests/region_map.gd` (headless
hillshade + landmark check); `tests/region_bench.gd` (throughput +
steepest-grade); `tests/region_probe.tscn` (Movie Maker screenshots,
minimized). Far-terrain rebuilds moved to a dedicated thread (was
starving behind cell builds on the shared pool). Open feel questions:
fog vs landmark (calm fog eats 91% contrast at 3km), causeway vs boat
traversal, coast silhouette still square-ish.

**RESOLVED (2026-07-05) — the descent crash: fixed by the native
terrain kernel.** The GDExtension port (below) removed all GDScript
from worker threads; `tests/fall_probe.tscn` went from 5/5 crashes to
5/5 clean with ZERO "Bad address index" errors — the long-filed
threaded-sampler script errors were the same disease and died with
it. The final abort site (once everything else was native, the crash
handler could finally print it) was sand_patch's re-anchor build; the
underlying engine bug (GDScript VM corruption under concurrent
worker-thread execution) remains worth an upstream report, but the
game no longer exercises it.

**The native kernel (native/, the Loom, 2026-07-05):** TerrainKernel,
a GDExtension port of `height()` / `water_surface_base()` + block and
whole-mesh builders (`build_cell`, `build_far`) — cell meshes, far
LOD, sand patch/base, water-field base, and the hydrology grid all
sample in C++ now; GDScript keeps the single-sample main-thread API
and is the fallback where the library isn't built. macOS-only .dylib
loaded at runtime by Terrain._ready via a custom-suffix
`native/bin/valleykernel.gdext` (deliberately not `.gdextension`, so
Linux CI never sees it and falls back clean). Rebuild: clone
godot-cpp into native/, dump the engine API (commands in
native/CMakeLists.txt header), `cmake -B native/build -S native &&
cmake --build native/build -j`. Determinism contract:
bit-parity with the engine's own GDScript math is impossible (the
official binary's fma codegen), so the kernel is bit-stable with
ITSELF, every worker consumer reads the kernel, divergence vs
GDScript is gated <1e-4m by `tests/kernel_parity.gd`, and the soak
fingerprint changed ONCE at adoption (still bit-identical across
runs). If the double-precision engine build ever lands, recompile
with `precision=double` (CLAUDE.md GDExtension policy).

**Superseded — descent crash (2026-07-04 night; kept for the record).** Falling/moving
fast (~25m/s+) into unstreamed terrain SIGSEGVs on a WorkerThread
(EXC_BAD_ACCESS near-null; sometimes SIGABRT). Deterministic repro:
`tests/fall_probe.tscn` (headless, ~40s; env knobs FALL_KEEP strips
the scene, FALL_NO_PHYSICS disables the player). **Pre-existing, not
archipelago content**: the same probe crashes commit 1eea47e, and a
matching crash report exists from 01:16 the same day. Ruled OUT by
bisection (each tested with the repro): navmesh baking, trimesh shape
creation, cell unload/queue_free, the far-terrain dedicated thread,
region/guard/sea terrain code, in-flight build caps, serializing all
worker height() sampling behind a mutex, player physics, call-stack
tracking setting. Standalone hammers (pool-only, main+pool, mesh
builds — `tests/thread_crash_probe.gd`) do NOT reproduce; it needs
the real streamer + autoload composition. The long-filed "Bad address
index" threaded-sampler script errors accompany it but serializing
sampling doesn't stop the crash, so they may be a co-symptom, not the
cause. Candidate real fixes, in order: (1) **GDExtension port of the
bulk height samplers** (already the named hot-loop candidate — moves
all worker-thread work out of the GDScript VM), (2) try a newer Godot
4.7.x patch when available, (3) upstream bug report with fall_probe.
Meanwhile: descend big landforms at walking pace, or give streaming a
head start; the valley itself has never triggered it in normal play.

**The air, phase A (2026-07-05, the Elements)** — dew fog as a
stateless function of the sim: `Weather.fog_amount()` condenses from
Climate's real wetness/temperature on calm nights, peaks pre-sunrise,
burns off with the real sun (fog SEASONS fall out for free; storms
carry their own murk). Presentation: thin distance haze (landmark law
survives fog weather) + HEIGHT fog that floods sea/strand/valley
floor while mesa tops float clear + a wind-drifted FogVolume noise
bank you wade through (pools BELOW you on a summit). Toolkit:
`Weather.summary()`, `fog_override` knob; probe `FOG=1
REGION_SHOT=rim|summit`. **Phase B (same day): weather as FRONTS** —
systems are bands with positions spawning windward of the 13km world
circle, traveling at 2.2–4m/s along the wind they were born with,
expiring leeward; local weather = youngest band over the point (800m
soft leading edge), calm between bands. `.state/.wind/.storminess`
are now AT-THE-FOCUS values (all consumers unchanged); spatial sims
read `state_at()`: Climate wets the valley and Hydrology rains into
the watershed only when a band is over THEM. Sim contract type (b):
hour_tick + "weather" Rng stream + `weather.fronts` in WorldState +
catch-up; soak fingerprint moved once (3242764635), bit-stable.
Toolkit: `force_kind()` (Y key + all probes/tests use it — writing
`.state` no longer reaches spatial consumers), `summary()` lists all
fronts. **Phase C (same day): seven kinds, continuous properties,
storm bodies.** A kind is a bundle of numbers (wind/rain/cloud/dust/
menace), not a switch: calm, overcast, drizzle, windy, gale (dry
sand-blasting — summer's violence), squall (narrow, 5.5m/s, vicious),
storm; wet kinds favor winter. Consumers read the numbers:
`rain_at()` wets Climate/Hydrology continuously (drizzle = slow soak),
dust hazes and thickens motes, cloud dims without menace; legacy
names kept so saves/probes migrate free. Presentation: posterized
rain CURTAINS hang under rainy fronts within 9km (the approaching
storm has a body); double-pulse LIGHTNING near heavy rain
(presentation-only randomness; thunder audio = placeholder for his
recordings). Soak moved once (3180831281), bit-stable. Kitchen-table
items: volumetric-fog gouache look; rain-curtain texture is a painted
slot. **Climate v2 phase 1 (2026-07-05): the rain shadow and the
wetness field.** Where the wet air CAME FROM matters now: the rain
term probes terrain upwind along each front's own travel direction —
a barrier that tops a point starts stealing its rain (deep lee of the
950m Range: ~18% of base), ground rising just downwind reads as the
windward slope and rains harder (orographic lift with a direction,
not just altitude). And Climate's one global wetness became a FIELD:
an 8×8 grid of 2048m cells over the world frame, each cell wetting
under the rain actually falling on IT and drying by its own
temperature — so the lee of the Range dries into desert while the
windward flank stays lush, and `FloraLife.vitality_at` /
`moisture(x,z)` inherit the split for free (windward green, leeward
straw — the Hawaii fact, derived). `Climate.wetness` is now a
property: read = the home-valley cell (Hydrology runoff, fog, the
soak line keep their meaning), assign = flood-fill (the old global
semantic — every test and dev knob works unchanged); old saves
migrate by flooding the field with their scalar. Fog dew now reads
wetness at the focus. Sim contract intact (hour_tick, catch-up,
`climate.wet_grid` mirror, no randomness); soak moved once
(1071113081, the grid digest + shadowed valley rain), bit-stable,
30 days ~1s. **Phase 2 (same day): the thermal field.**
`temperature(x,z)` knows where it is beyond altitude: the sea damps
the diurnal swing within ~1.8km (coasts never bake or freeze like
the interior — and the home valley itself reads mildly maritime,
because it IS 1.4km from the east shore), and slopes facing the
sun's CURRENT bearing run warmer (this sky's sun rises +Z, passes
overhead, sets −Z — no permanent warm side exists, so aspect is
time-of-day: east flanks thaw first, west flanks hold evening heat;
pure `aspect_term`, unit-tested). Rain-shadow clearance raised
(120m/500m): a valley does NOT sit in the shadow of its own rim —
only a big sustained wall wrings the air dry (found honestly: the
tightened constants broke the brook-swell test through the west
rim). Per-cell static terrain facts (swing/gradient/height) cached
once, cleared on Terrain.edited — the hourly field tick costs no
terrain probes on dry hours, soak back to ~0.75s. Fingerprint moved
once (1333567381), bit-stable. Fun fact the soak taught: in summer
the maritime damping doesn't change 30-day drying at all — the
swing is symmetric and drying is linear in temperature, so warmer
nights buy back exactly what milder afternoons lose; the asymmetry
arrives with winter's freezing clamp. **Phase 3 (same day):
humidity.** AIR moisture, distinct from ground wetness, STATELESS
(type (a) — nothing saved, nothing to catch up):
`Climate.humidity(x,z)` = base + open water upwind (four probes ride
the LIVE wind — the sea breath) + ground wetness under the column +
a wet front overhead (raining air is saturated air), thinning with
altitude to 0.45× on the peaks. Three consumers wired same-commit:
fog's dew term now condenses from humidity (coasts fog harder than
the interior, summits float clear — sea fog for free);
**dew at dawn** (IDEAS ★): in the pre-dawn window, still saturated
air skips drying and lays a 0.03 film on the wetness field — the
ground darkens before sunrise and dries off by mid-morning; and
**star extinction** (`air_humidity` global, sky shader): humid
nights wash the stars, so the clearest sky of the year is a cold
dry winter night — the field recordist's almanac before the
mechanic exists. Fingerprint UNCHANGED (1333567381) and that is
honest: dew is a dawn film that burns off within two hours, so the
9am end-state never sees it (the scene test proves it fires).
Still open in Climate v2: soil from the erosion bake,
biome-from-climate (SIM_ROADMAP).

**The map pipeline, stage A (2026-07-05, the Toolkit): paint →
bake → world.** `data/world/elevation_guide.exr` (1024px, 16m/px,
EXR meters — paint it in any image editor) + `guide.json` (bake
settings) → `tests/bake_world.gd` runs the kernel's `bake_terrain`:
bilinear upsample + fractal relief + thermal talus + **hydraulic
droplet erosion** (400k droplets on 2048² in ~0.4s — coherent
dendritic drainage, alluvial fans, sediment; the believability
engine) → written as an F3 painted-tile record covering the world.
Baked EXR + record are LOCAL CACHE (gitignored; regenerate with one
command — missing bake just means procedural records show through).
The guide is the source of truth; `tests/derive_guide.gd` seeded it
from the v4 archipelago, so the current world IS the first painting.
The running game hot-reloads the tile when a bake lands: repaint →
rebake (sub-second) → the world reshapes under you. Stage B queued:
painted BIOME map + `biome_at(x,z)` substrate (shader palettes,
per-biome flora species/density, Climate/Weather biome response,
sand physicality) — the palette is a kitchen-table item. Stage C:
river proposal from the erosion flow map (Hydrology-compatible
records), beach rules. Same-day Toolkit pass: god-mode WORLD PANEL
(O — every system's summary live), sculpt flatten (Ctrl) + stroke
undo (Z), map right-click teleport, summary() coverage completed
(Climate/Hydrology/Sand/WaterField/Flora/Wear/Nav).

**Map pipeline stage B — the biome substrate (2026-07-05).** A
painted biome map (`data/world/biome_map.png`, committed painted
source; palette in `biomes.json`) is matched to an R8 index image and
fed to rendering + flora. `tests/derive_biomes.gd` seeds a believable
starting map from terrain rules (height/slope/water-proximity: grey
bare peaks → volcanic rock → green mid-slopes → sandy strand → sea).
`Terrain.biome_at/biome_density`; a global index texture + Nx1 palette
texture drive the shader (ground tinted toward the biome albedo — a
tint, not a replace); flora scatter scales by biome density (deserts
bare, oases teeming). 8 PLACEHOLDER biomes (rename at the kitchen
table). Pure presentation + flora — soak untouched (2183523517).
Hot-reloads. Stage C (rivers proposed from the erosion flow map)
queued.

**Map pipeline stage C — rivers from the erosion flow (2026-07-05).**
The bake's droplets already found the drainage; `bake_terrain` now
returns `{height, flow}` (flow = droplet passage per cell), and
`tests/propose_rivers.gd` traces the major channels down the carved
valleys to the sea (headwaters first, tributaries merge) into river
records (`data/water/rivers/gen_*.json`, gitignored cache). They carve
+ render like any river but are **no_sim** (Hydrology skips them via
`Terrain.sim_rivers()` — its domain is the home watershed until
per-region watersheds land, and registering them would move the soak
on a presentation knob). Verified soak 2183523517, parity holds. The
map draws all rivers. Re-run with a different FLOW_PCTILE for more/
fewer. **The paint→bake→world pipeline is complete**: elevation guide
+ biome map in → eroded terrain + biomes + drainage out.
**Proposal quality rebuilt (2026-07-05, same day, from playtest
screenshots — the first pass wrote 40 near-duplicate rectangular
gullies whose ribbons floated over dips):** now ≤10 major rivers — a
wide claim mask coalesces parallel gullies, tributaries junction into
trunks, and only channels reaching the sea or a trunk survive;
flow-guided descent (max-flow lower neighbor, not steepest) keeps
traces in the valley floors; Chaikin ×3 + uniform 45m resample kills
the grid corners; node surfaces are bilinear from the BAKED
heightfield (never Terrain.height) with a monotone downstream clamp,
so ribbons lie in the carved channels. Verified visually by the new
`tests/river_probe.tscn` (RIVER_SHOT=close|flank|wide, Movie Maker +
minimized, region_probe's recipe); soak 4124434361 bit-stable
(unchanged — the current fingerprint since the flora-depletion entry;
gen rivers stay no_sim). **The drape (same day, "it's not actually
flowing over the terrain"):** river ribbons no longer trust the
node-lerped surface — every 1.8m cross-section takes min(record
waterline, carved centerline ground + depth), then a backward
max-scan from the mouth (monotone downstream; dips become flat pools
behind their lips, never bridges). Row-to-row grade goes into
COLOR.r; the water shader's new `rapids_boost` (rivers only) foams
the steep runs — cascades read as falls. The tracer resamples
adaptively (45m gentle → 16m steep) so the CARVE follows the step
scale too. Presentation-only: Terrain/kernel untouched, soak
unchanged. Real live flow out there (per-region WaterField windows)
stays future work.
**Live flow everywhere (2026-07-05, the Elements/Watershed): the
tier-2 field is now a SCROLLING WINDOW.** The 1024² 2m-texel dynamics
field no longer sits on the home watershed — it follows the focus
(player or god cam) anywhere in the archipelago, the sand-field
recipe: re-anchor past 384m drift, depth scrolled by texel offset
(new water_copy kernel), terrain base rebaked off-thread through the
native kernel; entering texels start dry and rain refills them. Storm
runoff now streams down any island's real slopes, pools in its
hollows, and drains into ALL water bodies (generated rivers and the
sea were already in water_base_block's sink answer). Generated
rivers' currents push at a fixed healthy-flow fraction (no Hydrology
discharge to read — per-region routing is still the future item).
Presentation-only: off headless, soak untouched. Verified live at the
volcano: river_probe RIVER_WX=storm (+RIVER_WALK=1 exercises the
mid-run re-anchor/scroll path).
**Flow maps + the water's hours (2026-07-05, Nicco's realism call +
"pink only at golden hours").** Rivers carry a PER-VERTEX flow map
(UV2 = downstream direction × local pace baked from the drape —
rapids race, pools laze, bends curve) scaled by `flow_scale`, the
live hourly discharge; the shader advects ripples/foam along it with
two half-offset cross-faded phases (the flow-map trick — one shared
clock would shear the pattern into streaks). And the pink is now the
LOW SUN'S GIFT: day_night publishes `water_gold`/`water_night` (bell
around solar sunrise/sunset; night from sun elevation) and both water
shaders blend teal day / slate night / the signature pink at golden
hour — day water also absorbs harder so shallow runs still read as
water. river_probe grows RIVER_HOUR=gold + a pond vantage.
**Fill-channels experiment (2026-07-05, debug key K, default OFF).**
The tier-2 field can now SPRING the rivers instead of sinking them: a
new source texture (water_depth.glsl binding 5) injects
discharge-scaled water along each rasterized channel while those
texels drop out of the sink mask (sea + lakes stay sinks), so the
pipe model fills the carved beds with real flowing water. Toggle K
rebakes the base + hides the ribbons for a clean A/B. FINDING: with
fill ON the sim water lies in the bed NEARLY IDENTICAL to the draped
ribbon — the drape already put the ribbon where the water pools — so
it's not a visible win for CALM rivers and it adds 2m-texel edge
blockiness; the payoff is dynamics (storm swelling, pools, rerouting)
and it's confined to the 2048m window / 96m sheet near the focus.
Kept as a toggle, ribbon ships. Presentation-only: off headless, soak
untouched (1333567381).
**Region hydrology (2026-07-05): the generated rivers BREATHE.**
Hydrology grows a region tier: every no_sim river is a linear
reservoir on the same hourly balance, rained on through
`Weather.rain_at` at its own midpoint (fronts + the v2 rain shadow
make flanks differ for real) and fed by the catchment the erosion
bake measured (`catchment_m2` in the record — peak droplet passage ×
area-per-droplet; the tracer writes it now). Discharge feeds
flow_norm → ribbon flow speed, surface level, and current_at push,
exactly like the brook. State in `region_storage` — SEPARATE from
river_storage because the soak fingerprint digests that dict and gen
records are a regenerable cache; verified: fingerprint identical
with and without gen_*.json present. Saved via WorldState water.*,
hour_tick catch-up, load_state — full sim contract. Soak note: the
expected fingerprint is 1333567381 since the Climate v2 rain-shadow
commits (their message records the move; STATUS's flora-era
4124434361 was stale). **Dev time travel fixed + granular:** the T
lag was water_bodies rebuilding every draped ribbon on each hourly
levels_changed (~80ms, found by the new `tests/clock_probe.tscn`
per-consumer timer); levels now TRANSLATE the built mesh (1h chunk:
80ms → 1ms). New Ctrl+T = +1 hour, Ctrl+Shift+T = +15 min.
**Ribbon seam pass (same day, the Skyrim lessons — bed and surface
authored to agree, disagreements hidden):** tangents smoothed ±2 rows
(bend notches), edges tucked 0.4m past the waterline into the carved
bank (edge cracks), and POOL LIPS (flat water arriving at a >1.1m
cliff) emit a vertical fall face instead of one stretched quad —
lip detection requires the flat above, because splitting every steep
row shingled the cascades (tried, reverted same hour).

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
   the overlay) · ✅ far waypoint graph (roads as records in data/roads/;
   graph derived — consecutive nodes edge, coincident nodes junction;
   A* route(); Nav.path()'s far tier now follows the road instead of
   one blind line; first authored road runs spawn → pond → shrine, a
   disposable fixture for the 12km map) · ✅ NPC AgentSim port
   (2026-07-05: the NPC mind — needs/utility/advance — moved into the
   shared AgentSim core wildlife already runs; the node keeps physics,
   animation, dialogue, rumors, and the pantry flush; `needs` is a
   shared reference to sim.needs so the soak and inspector read
   unchanged; AgentSim grew a per-agent drain_scale [NPCs 6.0,
   wildlife 5.0]. Soak fingerprint BIT-IDENTICAL through the port —
   1333567381 before and after, the A2 wildlife standard held).
   **Phase A COMPLETE — caravan embodiment and the village unblocked.**
   · ✅ caravan embodiment (same day: near the focus a body walks the
   route — seated on stateless locate() every frame at fractional
   hours so it GLIDES, faces its travel, wears the road in, stamps
   sand prints, and nods in passing [E — Greet, `caravan.<id>.met`];
   dissolves past 170m; the robot placeholder body, her caravan-walker
   painting's slot; `tests/caravan_probe.tscn` frames it mid-leg;
   soak untouched — presentation seated on a pure function).
   **Phase B started:** ✅ snow (cover state +
   emergent snowline from the lapse rate, meltwater soaks the ground) ·
   ✅ wind direction (wanders hourly, swings in storms; sand ripples and
   dust follow it) · ✅ herd cohesion (roam draws around the group's
   drifting centroid) · ✅ per-cell flora + species records (2026-07-05,
   the Elements: `data/flora/*.json` — a new plant is one JSON file
   carrying per-stage art slots [all placeholder paths today, her stage
   paintings drop into the same slots], biome composition weights, a
   moisture need, and optional forage `yields`; scatter and ground
   cover are now species-driven — biome picks WHO grows, dune cells
   finally scatter the cactus, stage art chosen at cell build from
   season + vitality; `FloraLife.vitality_at(x,z)` is STATELESS spatial
   vitality — global vitality shifted by local Climate, so pond banks
   stay green through a drought and density breathes with the land, no
   per-cell tick, no save growth; HONEST HARVEST: ForageSpot gather
   spots [E — Gather, feeds the Foraging skill, first source: bloom
   tufts → dried blooms] wound a SPARSE per-cell depletion state on
   the sim contract [hour_tick regrow scaled by local vitality,
   WorldState `flora.cells`, catch-up, load_state] — cells thin while
   wounded, heal over ~2 days, and healed cells are FORGOTTEN so the
   save only remembers open wounds — no cell-reset respawns, ever;
   soak fingerprint moved once [4124434361, the depletion digest
   joining it], bit-stable) ·
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
