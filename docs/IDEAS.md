# Ideas Backlog — maximum immersion

*Brainstormed 2026-07-01. Not commitments — a drawer to pull from. Each entry:
the idea, the reference, rough effort, and what it rides on. Signature-candidate
ideas marked ★.*

## Sound (our unfair advantage)

- ★ **The player is a field recordist.** An in-world recorder as a core verb:
  capture soundscapes (dawn at the pond, wind in an arch, a bloom's hum) into
  a journal — quest structure, lore delivery (recordings of vanished things),
  and a mechanical reason to sit still in beautiful places. Effort: medium.
  Rides on: interaction layer, audio design. Nobody has done this properly.
- **Audio-visual wind coupling:** one wind value drives sway shader amplitude
  AND wind-bed volume. Effort: tiny. Rides on: weather system.
- **Reverb zones from real impulse responses** (record real canyons!),
  occlusion, distance low-pass. Effort: small-medium (Godot audio buses).
- **Diegetic music only:** no soundtrack; humming NPCs, wind-chimes at
  shrines, rare earned music moments (Death Stranding). Effort: content-side.
- **Footstep material system:** per-surface sounds (sand/stone/water/plants),
  ties into material states (wet/dry). Effort: small.

## A world that remembers (simulation pillar extensions)

- ★ **Worn paths emerge:** long-memory interaction field — repeated walking
  (player + NPCs) slowly wears visible trails. Desire paths across the valley.
  Effort: medium. Rides on: interaction field.
- **Weather memory:** puddles that dry over hours, damp sand, snow lingering
  in shade. Effort: small once material states exist.
- **Celestial clockwork:** moons + red sun on slow cycles; rare conjunctions/
  eclipses NPCs stop to watch. Ties to axioms + calendar. Effort: small-medium.
- **Campfire remains, placed-object permanence** (already have records) —
  the player's own traces persist.

## People — presence over systems

- **Familiarity greetings:** stranger → regular → friend from an encounter
  counter in WorldState. Effort: tiny. Payoff: huge warmth.
- ★ **Fires are social gravity:** NPCs converge on fires at night; the sit
  verb works *beside them* (RDR2 camp feel). Sitting becomes social.
  Effort: small on top of needs-AI.
- **Contextual idles:** shading eyes at low sun, hugging self in cold,
  watching things that fly over. Effort: animation content, incremental.

## Interface — immersion by removal

- ★ **No compass, no quest markers** (the Morrowind option): navigation by
  landmarks, the map, and spoken directions in dialogue ("past the twin
  palms, left at the pink pool"). Geography knowledge = progression. Effort:
  negative code, high writing discipline. Decide before quest content exists.
- **Diegetic fast travel or none:** if it exists, it's a creature/caravan at
  fixed points (silt-strider answer), never menu teleport. Decide with world
  size.
- **HUD approaches zero:** everything fades when unused (sit already does
  this — generalize).
- **Photo mode early:** the screenshot tool doubles as her composition/
  reference tool and free marketing in her style.

## Body

- **Character shows the world:** dust after wind, wet after wading, fire
  glow. Material states applied to the character. Effort: small per state
  once the systems exist.
- **Gentle comfort loop, NOT survival:** cold nights make fires feel good
  (warmth shimmer, contented idle); no hunger bars, no death timers. RDR2
  camp-feel, not homework. Effort: small, mostly feel work.
- **Traversal character:** slope scrambling, sand-slides on dunes (Journey),
  tools opening terrain (already planned as exploration keys).

## The ambient material (2026-07-03 — details that add up; most compose
## with systems that now exist: granular sand, Climate, wind vector,
## real moon/seasons, wildlife)

- ★ **Wind saltation:** the granular field slowly TRANSPORTS sand
  downwind (one advection term in the relax kernel) — ripples migrate,
  prints fill from the windward side first, drifts bank against rocks
  and flora. The desert breathes. Effort: small (kernel addition).
- ★ **Dew at dawn:** when pre-dawn temperature crosses the dew point,
  wetness pulses briefly — dawn ground reads darker and takes crisper
  prints, drying off by mid-morning. Pure composition: Climate already
  owns both numbers. Effort: tiny.
- ★ **Gust fronts:** wind arrives as a visible traveling band — a line
  that crosses the valley swaying flora, lifting dust, hissing in the
  wind bed as it passes over you. One moving position + existing
  consumers. Effort: small-medium.
- **The Keeper sweeps:** her tend activity emits a gentle smoothing op
  into the sand field — she literally erases footprints around the
  shrine. Her job, visible in the ground, wordless. Effort: tiny.
- **Booming dune:** a long sand-slide triggers the real "singing sand"
  phenomenon — a low resonant hum while the flow runs (dry sand only).
  Effort: small (audio + slide state).
- **Footsteps sound like the ground:** step audio reads the local sand
  field — soft crunch in fresh ejecta, firmer on compacted path, damp
  slap on wet shore. Effort: small (sample field at foot).
- **Dust devils:** rare small whirlwinds on hot dry afternoons
  (temperature + wetness gated), wandering columns of motes that leave
  faint erratic scribbles in the sand field. Effort: medium.
- **Air quality:** dust load (recent wind) softens and reddens the sun
  disc; the washed air after a storm reads crisp — fog density and sun
  color follow wind/wetness history. Effort: small.
- **Season in the sand:** winter frost crusts the field (repose way up,
  shallow crisp prints); summer loosens it (repose down, softer prints,
  more kicked dust). Two constants already parameterized. Effort: tiny.
- **Moon shadows:** on bright full-moon nights, a faint second
  directional light casts soft moon shadows; star reflections on the
  pond on calm nights. Effort: small.
- **Hound habits in the sand:** digging at rest spots (crater op,
  shallow), shaking off after rain, pawing before lying down — their
  presence recorded in the ground like everyone else's. Effort: small.
- **Buried and uncovered:** the wind slowly buries small placed objects
  (they read the local field and sink visually); walking near them
  kicks them free. Old campfire stones half-swallowed by a week of
  wind. Effort: medium.

### Batch two (2026-07-03, same session — the sim as author)

- ★ **Seed drift:** when FloraLife crosses its seeding stage on a windy
  day, visible fluff streams downwind for an afternoon — and next
  season's scatter density shifts subtly downwind of parents. The WIND
  authors the landscape over seasons. Effort: medium (needs per-cell
  flora). Rides on: wind vector, FloraLife, scatter.
- ★ **The pond breathes:** water level follows a weeks-scale wetness
  integral — shorelines advance and recede, wet banks record deep
  prints, and a long drought exposes ground (and things) normally
  under water. Exploration gated by the sim itself: drought secrets.
  Effort: small-medium. Rides on: Climate, water shader, granular sand.
- ★ **Petrichor beat:** the first rain after a long dry spell is an
  EVENT — dust puffs off the ground as the first drops land, the audio
  holds a beat before the wind bed shifts. One dry-duration counter.
  Effort: small. Rides on: Climate, particles, audio.
- ★ **Insect chorus thermometer (Dolbear's law):** the cricket-analog
  chorus rate literally tracks Climate.temperature, as real crickets
  do — the valley's temperature is audible. A field recordist's
  instrument before the mechanic even exists. Effort: small.
- ★ **Tracks as information (the gameplay bridge):** species-shaped
  prints + wind-aging already write a readable record into the ground —
  who passed, which way, roughly when. Later, a tracking skill and
  quests READ what the sim already writes. Build nothing now; protect
  the property: every creature that moves must leave its true mark.
- **Virgin crust:** sand untouched for days develops a delicate wind
  crust — the first step through it reads and sounds different from
  ground broken yesterday. Untouched places FEEL untouched. Effort:
  small (age term in the field). Rides on: granular sim.
- **Mud:** trampled + soaked ground churns (wear × wetness) — deep
  slow tracks, splash steps; dries into a cracked crust that flakes
  back to sand over days. NPCs route around the worst of it (utility
  cost from moisture), so paths genuinely change after storms.
  Effort: medium. Rides on: wear, Climate, navmesh costs.
- **Distant lightning, delayed thunder:** night storm cells flash on
  the horizon; thunder arrives seconds later by real distance (speed
  of sound). Two lines of physics, enormous presence. Effort: small.
- **Puddles:** concave spots (curvature is computable per cell offline)
  hold water after storms, shrinking over hours, reflecting the sky.
  Effort: medium. Rides on: Climate, water shader.
- **Cold clear nights have more stars:** atmospheric extinction from
  humidity/temperature — the star field breathes with Climate; the
  clearest sky of the year is a cold dry winter night. Effort: tiny.
- **Frost sparkle mornings:** below-freezing clear dawns intensify the
  ground glints until the sun warms them off. Effort: tiny.
- **Snow behaves in the granular sim:** powder lowers the repose angle
  (deeper prints, softer slumps); melt clears south-facing slopes
  first (aspect from the normal). Effort: small. Rides on: snow state,
  granular sim.
- **Moths to your lantern:** deployed fireflies attract the dusk moths
  — two existing systems, one attraction rule, instant life. Effort:
  tiny.
- **Wind timbre from the land:** the wind bed's character shifts with
  local flora density (rustle among growth, open hiss on bare flats) —
  audio that knows where you're standing. Effort: small.
- **The 4am hush:** the quietest hour mixes down to almost nothing —
  your own steps become the loudest thing — so the dawn chorus, when
  it arrives, lands like an event. Effort: small (mix state by hour).
- **Long-absence homecoming:** return after weeks of real time and the
  world says so — your worn paths healed, a new flora generation, an
  inhabitant remarks on the gap. Catch-up already computes all of it;
  this is surfacing, not simulating. Effort: small. Rides on: rumors.
- **The world's breath:** one shared 1/f (pink-noise) conductor gently
  modulating gust timing, chorus density, and mote drift so ambient
  rhythms never feel metronomic — the difference between a loop and a
  place. Effort: small, subtle, everywhere.

## Gameplay inherited from the sim (2026-07-03 — the loop design thesis)

*The principle: don't write content, write READERS. The sim produces
situations; gameplay is the player's relationship to situations. Every
mechanic is a new way to read or enter the sim's causal chains — never
a parallel system with its own fiction. ("The Dry Spell" already works
this way; these generalize it.)*

- ★ **Struggle is visible, help is derived:** a drought strains an
  NPC's needs → their day visibly changes shape (more trips, longer
  routes, wearier). A "help opportunity" is a QUERY (unmet need +
  player has means), not a quest record; the journal shows an
  observation, not an errand. Help, and their day relaxes. Rides on:
  needs AI, stocks, mood (roadmap C).
- ★ **Knowledge skills — perception as progression:** the sim computes
  truth the player can't read yet; each skill is literacy, not power.
  Tracking (prints/age/species), Weatherlore (the transition matrix
  hints: "rain by dusk"), Fieldcraft (vitality points to water).
  Horizontal canon, made concrete. Rides on: everything, free answers.
- ★ **Gardening the valley — the player as climate actor:** carry
  water to parched ground → local moisture → vitality → bloom → moths
  and fireflies gather → the place is beautiful BECAUSE you tended it.
  Stewardship loop, zero new systems once per-cell flora lands; the
  world-shaping progression axis, mechanically true.
- **Information as economy:** rumors distribute true sim facts
  unevenly → leads → investigation by reading the world (tracks, flora,
  weather history). The sim manufactures mysteries because it
  manufactures causes. Trading inherits drama the same way: prices
  move because of a sky the player watched darken.
- **The year is the campaign:** festivals/rituals (post-axioms) are
  RESPONSES to sim state, never dates — the bloom festival fires when
  the sim blooms; a drought year barely has one, and that's the
  memorable year. Rides on: seasons, seeds, calendar records.
- **Guard-rails:** pacing by scarcity (cap active seeds per domain — a
  drought is weather, not a quest dispenser); never mechanize against
  the sim (no fast travel past the weather, no reward loops on ambient
  acts — Stillness has it right: time spent IS the currency).

## Terrain & water (2026-07-03 — the landscape conversation)

*Skyrim's lesson, verified: heightmap carries landforms; a MODULAR
CLIFF KIT carries verticality (heightfields can't overhang — every
Skyrim mountain is ~30 reused slab meshes under one material); then
boulders → rocks → clutter, each scale breaking the one above.
Believability is geological logic (drainage, continuous ridgelines,
consistent strata tilt) + composition (landmarks that pull), not tech.
And Skyrim's water is flat planes + flow maps + waterfall meshes — no
fluid sim, nobody ever noticed. Our two-layer canon is the shipped
answer.*

- ★ **The cliff kit is terrain, not decoration:** his Blender rock
  family (already top of ASSETS_NEEDED) grows into a cliff/plateau kit
  — slab-scale pieces for rims, overhangs, sheer faces, the slide
  walls. Flat-shading hides kit seams for free (Skyrim needed careful
  texturing; matte palette doesn't). Silhouette is king in a painted
  world, and kit rock is silhouette.
- ★ **Water bodies as records (unhardcode the pond):** data/water/
  lakes = basin + surface height; Terrain.water_surface() reads
  records; swimming, navmesh carving, moisture floors, submerged
  culling all come free (they already read that one function).
- ★ **Rivers as splines** — *first increment shipped 2026-07-04:* node
  polyline (position, width, surface height) in `data/water/rivers/*.json`
  → ribbon mesh + painterly flow shader (scrolls downstream), channel
  carved into the terrain, `water_surface()` answers within the ribbon so
  swimming / navmesh-carve / moisture / flora-submersion all come free;
  the first brook feeds the pond. *Still open:* stepped stretches joined
  by waterfall meshes (each a positional audio emitter — the spline holds
  one continuous surface today, so a big drop would vanish into a hill);
  per-vertex flow so curved rivers carry current around bends (one flow
  vector per river now); river current as a real force on swimmers
  (below). Rivers already carve the navmesh (submerged cells drop from the
  bake) → they partition the world → fords and bridges matter → the far
  waypoint graph earns its keep.
- ★★ **Seasonal fords — the sim opens the map:** river flow and lake
  levels follow the Climate wetness integral + snowmelt; late-summer
  drought drops a crossing and a region opens; autumn rains close it
  behind you. Exploration-ring gating authored by the sim, zero
  scripting — the loop-thesis and the landscape meeting in one
  mechanic.
- **River current as traversal:** swimming in flow pushes you
  downstream — free rides, real danger above falls, upstream effort.
- **Hydrology proposes, the author disposes:** the F3 erosion/
  hydrology bake suggests river courses from real drainage on painted
  tiles; she/he blesses or bends the spline; the record ships. Where
  water flows answers "why is the settlement here."
- **Geological believability checklist (for tile painting):** every
  valley drains somewhere; ridgelines continue; strata tilt agrees
  across a face; one landmark visible from every region edge.

### Skyrim's structure, not Skyrim's budget (the principle, 2026-07-03)

*Take their patterns — kits, authored backbones, layered dressing, flat
far water — because they're honest about what matters. But their
budgets were 2011 console budgets; the two-layer-illusion boundary
moves outward with hardware, and the granular sand sim already proved
the near layer can be a REAL local simulation now. Water gets the same
treatment:*

- ★★ **Whole-watershed water dynamics** — *tier 2 shipped 2026-07-04:*
  GPU depth+flux field (WaterField/WaterGpu) over the WHOLE 2048m
  watershed at 2m texels (not just the near clipmap — the "never
  simulate the whole map" line fell, see DECISIONS). Pipe-model kernels
  flow storm rain down the real terrain, pool it in hollows, drain it by
  seepage (flat ground stays a sub-visible film) and into the authored
  pond/rivers as sinks; a WaterSheet patch near the player renders the
  live field; the flux field IS the velocity, read back to push the
  player as real current. *Still open:* eddies behind rocks (needs
  obstacle cells in the base bake); flash-flood spectacle wants the
  landform gradient (below) so gullies exist to run; balance is tuned
  for calm pooling, not yet drama. Rides on: sand_gpu architecture,
  water records — both shipped.
- ★★ **The two sims couple — sediment:** flowing water transports sand
  on the shared clipmap (pipe-model erosion): banks undercut live,
  wading stirs murky plumes that drift downstream, rain erodes prints,
  the busy ford deepens over a season. Two coupled 1024² fields ≈
  <2ms GPU on M-series — the headroom exists precisely for this.
- **Audio follows flow:** waterfall loudness tracks actual flow rate —
  a drought year sounds quiet before it looks dry; foam appears where
  the velocity field is turbulent, not where an artist painted it.

## The underworld (2026-07-04 — the "huge cave, not Skyrim corridors" conversation)

- ★★ **Layered heightfields, not voxels, not interiors:** the vast
  cavern with high ceilings and its own micro-biome is heightfield-
  SHAPED — a floor function plus a lid function (Elden Ring's
  Siofra/Nokron are exactly this: a landscape with a ceiling). So the
  underworld is a second terrain LAYER: its own floor/ceiling
  heightfields, edit layer (the sculpt brush already sculpts caverns),
  water records, flora records, navmesh, streamed cells — the entire
  built sim stack reused one level down. Voxel/SDF terrain is
  rejected: it invalidates every system keyed on height(x,z)
  (hydrology routing, sand base, navmesh, scatter, map, determinism)
  to buy arbitrary overhangs nobody asked for. Kit carries the
  verticality down there too — stalactites, columns, cave mouths: the
  cliff-kit lesson upside down. Ceiling constrained ≤ surface − 
  thickness so it can never poke out of a hill.
  **Implement WITH the F3 region-tile work** — bake `layer` into the
  region record schema from day one (the cheap-now-painful-later
  shape), not before.
- **The micro-biome is a per-layer Climate:** constant temperature (no
  sun, no lapse), moisture from the aquifer. Tier-1 Hydrology's lake
  seepage/outflow term currently vanishes into nothing — route it DOWN:
  underworld lakes are fed by the surface's real seepage, and cave-drip
  weather is surface wetness read with a days-long lag (a spring storm
  becomes cavern rain a week later). The glow-reserved lighting law
  stops constraining and becomes the ecosystem down there; darkness +
  fog replace far-terrain and sky — the cheapest vista in the game.
- **Entrances are authored set pieces** (cave mouths in cliff kit,
  sinkholes in the barren, a ravine that becomes a throat), both layers
  streamed briefly around the mouth. Sinkholes scattered in the barren
  make the desert worth crossing without spending an oasis — the void
  becomes the roof of content. Underground area is free density: it
  spends no surface kilometers, so ~10–12km of interesting surface can
  sit inside a larger barren and still play "bigger" than 25km flat.

## Later / bigger

- **Seasonal drift:** not four hard seasons — slow bloom-cycles and light
  changes across many game-days (ties to flora lifecycle sim).
- **Wildlife with daily lives:** drink at dawn, shade at noon, herds that
  remember being hunted (needs-AI reuse on creatures).
- **One live music performance in the world somewhere, once a day, findable.**
