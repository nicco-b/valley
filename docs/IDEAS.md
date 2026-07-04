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

## Later / bigger

- **Seasonal drift:** not four hard seasons — slow bloom-cycles and light
  changes across many game-days (ties to flora lifecycle sim).
- **Wildlife with daily lives:** drink at dawn, shade at noon, herds that
  remember being hunted (needs-AI reuse on creatures).
- **One live music performance in the world somewhere, once a day, findable.**
