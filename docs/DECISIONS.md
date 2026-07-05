# Decisions Log

*Settled questions and why — so future-us doesn't relitigate them.
All decided 2026-07-01 (first design day) unless noted.*

- **Godot 4, not Unity/Unreal/custom.** Mac-native, open source (MIT) = the
  real "max control"; our differentiating systems live in game code either
  way; custom engine = years of commodity plumbing. Unreal's big-world tech
  serves realistic art we don't use.
- **Hybrid art: painted billboards + flat-shaded meshes; characters are 3D.**
  Her paintings enter the game directly (billboards for flora/props/distant);
  terrain/buildings are low-poly flat-shaded meshes; characters (player,
  NPCs, creatures) are 3D for combat + immersion (Sable-like). Hero flora
  graduates to Blender models over time; billboards stay for density/distance
  (Elden Ring does grass this way).
- **Unified palette law.** One color script per biome/time-of-day; characters
  shade with the world's ramps; nothing gets realistic lighting. Only the
  glow-phenomenon/shrines/celestial emit light — glow is reserved language.
- **Third-person camera.** Settled by lock-on combat + billboard readability
  + seeing your character inhabit the world.
- **Combat: full system, souls-inspired, sparse.** Deliberate/stamina/lock-on;
  Shadow-of-the-Colossus structure (~one monumental guardian per biome).
  Built last (M5) — the world comes first.
- **RPG depth via systemic reactivity, not branching.** Consequences mutate
  existing content (state flags, schedules, prices), never spawn parallel
  content. Text-only dialogue, no VO — reactivity over performance.
- **Progression: use-based skills + tools as exploration keys.** No XP levels.
- **World: finite but undecided size — a growing quilt.** Authored heightmap
  tiles (rect canvases, irregular contents) + a fully irregular painted biome
  mask; auto frontier rim at unauthored edges; start small, grow outward.
  Generative = subordinate detail only. ~12km diameter before float work.
- **Setting: novel genre, not fantasy/sci-fi.** Derived from her paintings via
  2–3 world-axioms (pending). "Magic" is a banned word; the glow is a named
  natural phenomenon (name pending). Tools from world materials.
- **Simulation is a pillar.** Needs-driven NPCs (utility AI), weather,
  eventually flora lifecycle/ecology — with the Radiant AI discipline:
  inspector for everything, coarse far-tier, guardrails on canon state,
  one system at a time, player-visible or cut.
- **"Real physics" = the two-layer illusion.** Coarse state globally +
  interaction-field response near the player (trails, ripples, bent grass).
  World-scale volumetric fluid/granular solvers: never.
- **Maps: functional map rendered live from the world** (Skyrim-style camera);
  her illustrated map traced from it later.
- **Tools live in the game, dev-gated** (god mode pattern); content is
  records; place mode writes JSON, not scenes.
- **If you can see it, you can go there.** No fake vista geometry, ever.
  Distant terrain renders from the same height function the streamer
  builds walkable cells from (far-LOD mesh); a visible mountain is a real
  destination. Scales with the quilt: authored tiles feed both near and far.
- **Sitting changes nothing.** No depth-of-field, no filters, no cinematic
  dressing on the sit — the point of sitting is seeing the world exactly as
  it is. (Camera pull-out and HUD fade stay; they remove, not add.)
- **Repo: private GitHub (nicco-b/valley), plain git for binaries until ~1GB.**
- **Time is 1:1 with the real world — always** *(2026-07-02, the ambient
  machine; see [SESSION_2026-07-02_ambient_feel_and_combat.md](SESSION_2026-07-02_ambient_feel_and_combat.md))*.
  A game day lasts a real day: playing, unfocused, or closed. The save
  carries a wall-clock timestamp; time away (and laptop sleep) is replayed
  through the shared `GameClock.advance_hours()` catch-up in hour chunks,
  always at 1:1 — the valley is a place that keeps its own time, not a tape
  you pause. Stillness (`time_scale`) stays the diegetic fast-forward.
  Rate-1:1, *not* local-clock-synced: the world keeps its own calendar and
  the red-sun fiction; matching the player's actual wall clock + real sun
  position remains an optional future mode (IDEAS "celestial clockwork").
- **Simulation depth is wanted beyond the directly visible** *(2026-07-02)*.
  Amends the "player-visible or cut" clause of the simulation pillar: the
  golden category is **"unseen now, seen later"** — deep offscreen/away
  simulation whose *consequences* the player meets on return is the point
  of the ambient machine. Cut only computation with zero eventual
  consequence. Observability discipline (inspector for everything) is
  unchanged and matters more, not less.
- **Real seasons, the real calendar, the real local sun** *(2026-07-02)*.
  The valley shares the player's calendar *and sky*: season (`GameClock.
  season`, mirrored to WorldState `time.season` for quests/dialogue/seeds),
  daylight length, and sunrise/sunset times derive from the real system
  date and the player's real location (solar declination + equation of
  time; latitude/longitude one-shot IP-geolocated into Settings, timezone-
  guessed fallback, settings-picker later). Hemisphere falls out of
  latitude. New worlds anchor the clock to real local time, so the
  valley's sunset is your sunset — only Stillness bends the clock away
  from your watch (and the valley ignores DST, so alignment steps an hour
  twice a year; accepted). Sun arc, sky palette, dusk audio, and night
  creatures all read `GameClock.solar_hours()` — hour-of-day warped so
  sunrise/noon/sunset land on canonical 6/12/18 — so everything sun-shaped
  inherits the real sky from one seam. Weather storm odds are season-
  biased. Seasonal *palette/flora* changes await her seasonal paintings.
  Dev time travel (T / Shift+T / Alt+T → next anchor / +day / +week,
  debug builds) always goes *through* `advance_hours` — the world lives
  skipped time; there is no travelling back. Shift+Alt+T returns to now:
  a dial-only re-anchor to real local time (days lived stay lived).
- **Unfocused = watchable, throttled** *(2026-07-02)*. The unfocused window
  stays alive and glanceable (fps-capped, nothing dissolves, tiers stay
  distance-based); only a minimized window throttles near-idle. Good-citizen
  behavior for leave-it-running, without sabotaging the glance.

- **AI in the pipeline: offline amplifier only** *(2026-07-02)*. LLMs may
  help the humans author — drafting conditional dialogue variants, seed
  permutations, schema-shaped content for human editing — but nothing
  generated ships unreviewed and **nothing generates at runtime**. Runtime
  systems may only select and parameterize authored content. This is
  authored-primary (Principle #4) applied to text.
- **The ambient sim is the foundation, not a feature** *(2026-07-03,
  stated at the close of the physics session)*. In Nicco's words: the
  game is "a beautiful ambient sim underlying any gameplay loops or
  mechanics… all of these tiny details add up to make something
  amazing." This is Pillar 1 sharpened into a build priority: material
  and atmospheric truth (granular sand, climate, wind, light, sound)
  is invested in FIRST, deliberately, and gameplay loops are built on
  top of it — never the reverse. When triaging work, a detail that
  deepens the world's material reality outranks a mechanic that merely
  adds content. The brainstormed detail backlog lives in IDEAS.md
  ("The ambient material").
- **Depth before visual R&D** *(2026-07-02)*. Stroke-space/whole-frame
  painterly rendering research declined for now; the risk budget goes to
  simulation depth (SIM_ROADMAP). The per-surface painterly stack stands.
- **Water is simulated across the whole watershed** *(2026-07-04)*.
  Overturns the 2026-07-03 IDEAS line "never simulate the whole map" —
  written as 2011-console caution, not a law of our hardware. The wall is
  area × resolution, not compute-per-year: near-window fidelity (2.3cm)
  over the whole valley is ~10,000× out of budget forever, but resolution
  is a choice per tier. So water runs in **three tiers, all real**:
  (1) **canonical hydrology** — whole watershed, coarse grid catchments +
  hourly water balance, CPU, deterministic; this tier is what saves,
  catches up through `advance_hours`, and fingerprints. (2) **dynamics**
  — whole watershed on one ~1024² GPU field at ~2m texels (same budget as
  the sand field): live rivulets, pooling, flash flows, velocity
  everywhere. (3) **near window** — the sand pattern at 2.3cm: wakes,
  splashes, sediment coupling. GPU tiers are live presentation seeded
  from tier 1 and are never authoritative (GPU float order isn't
  bit-stable; a wave sim can't replay three closed weeks — the hourly
  tier can). "All out" means all-out simulation depth — conservation,
  routing, coupling, everywhere, always — not all-out texel count.
- **Water's ceiling is the heightfield (2.5D), forever** *(2026-07-04)*.
  Full volumetric fluid (FLIP / grid Navier-Stokes) is offline VFX: cost
  scales with volume³, can't persist, can't catch up through
  `advance_hours`, and no open world ships it. What makes water *read*
  as water is surface displacement, not volume — so the missing piece is
  **tier 2.5, the wave field**: a small (~512²) wave-equation grid
  around the focus, disturbed by bodies, rain, wind, and tier-2 flow,
  displacing the water meshes' vertices; Gerstner swell on large bodies;
  buoyancy, wakes, splash particles. Presentation-only under the
  existing contract (never saved, never fingerprinted, off headless).
  The three authored/simulated tiers (hourly balance / watershed
  dynamics / near window) stand unchanged beneath it. This closes the
  "are we doing real fluid sim?" question: we already are, in the only
  class of fluid sim a persistent world can honestly run.
- **World scale: ~15–25km, density over size — a vertical archipelago**
  *(2026-07-04; extends the quilt posture. An earlier 80–100km draft
  from the same session is superseded — density won the argument)*.
  The binding constraint is authoring hours, not coordinates or
  compute; the shape that spends them correctly: **dense handcrafted
  oases separated by deliberate emptiness, built VERTICALLY**.
  SF-inspired steep terrain is the density mechanism — reveal-per-
  minute via crests, stairs, and terraces rather than kilometers;
  tiered hill cities whose districts are visible palette/kit terraces;
  stairways and funicular/cable-lift as diegetic transit; fog as a
  traveling front pouring over ridges (pairs with the glow-is-reserved
  lighting law); ONE deliberate barren region carried by the ambient
  sim (dunes, weather, wayfinding, sparse encounters — cheap per km²);
  the existing sand-slide traversal makes steep slopes fun, not walls.
  Corollaries now load-bearing, decide before growth: traversal speed
  (mount / sand-sailing / caravan-riding as diegetic fast travel) and
  the no-compass navigation system — at this scale wayfinding is a
  core mechanic (real sun, stars, wind-oriented dunes, landmark
  silhouettes; the systems already exist to support it). The far-
  terrain quadtree over painted region heightmaps is the gating
  engineering project before the world grows past the valley.
- **Cities: hundreds of persistent individuals, tiered individuality**
  *(2026-07-04)*. Skyrim's ~70-NPC ceiling was 2011 memory and draw
  calls, not AI. Our AgentSim hourly tick makes thousands of simulated
  agents nearly free; the true budgets are skinned rendering
  (~100–150 embodied characters near the player in our flat-shaded
  style; far crowd falls to MultiMesh imposters), animation variety,
  and authoring. Target: **300–500 persistent named individuals per
  major city** — every one with a home, job, schedule, and offscreen
  continuity — structured as 10–15 *deep* NPCs per district (dialogue,
  quests, opinions, hand-written) atop a population instantiated from
  template records and hand-touched (sanctioned by the offline-
  amplifier decision). Beats Skyrim on the axis staging can't reach:
  everyone is somebody, all the time.
- **The budget law: simulation is cheap, embodiment is the budget**
  *(2026-07-04)*. On target hardware (M-series, unified memory) CPU
  simulation depth and big GPU fields are the abundant resources;
  skinned meshes, animation, and texel-dense rendering are the scarce
  ones. So: spend sim depth freely, everywhere, always (it's also our
  differentiator); spend embodiment only where the player is. Every
  system inherits the water/sand shape — canonical coarse everywhere,
  vivid near the focus. When triaging, a proposal that adds simulation
  costs almost nothing and should be judged on player-perceivability
  (F1.5); a proposal that adds embodied density is a real spend and
  must name its budget.
- **Next sim spine: the water economy + caravans** *(2026-07-04)*.
  The physical world is simulated; the multiplier layer is *human*
  dependence on it. Settlements exist at water (springs/wells/cisterns
  fed by Hydrology's real balance — "why this spot" answered by the
  sim); **caravans** are tier-3 data agents on the waypoint graph
  physically carrying goods and rumors between settlements at walking
  speed. Scarcity, prices, and news propagate through space; a drought
  in one basin is felt two oases away before anyone arrives to say so.
  Rides on: waypoint graph (SIM_ROADMAP P2), NPC stocks (long memory,
  built), rumors (built), Hydrology (built). Outranks further ecology
  rungs in build order.
- **The clock stays pure 1:1 — morning exists only in the morning**
  *(2026-07-04, Nicco, settling the planning session's open question)*.
  No compression, no player-directed time travel. If you want to see
  dawn in the valley, you are awake at dawn in your world; most players
  will never see most painted palettes, and that scarcity is the point —
  light you had to be present for is light that means something. This
  is the ambient-sim thesis applied to time itself: the game keeps the
  world's hours, not the player's convenience. `advance_hours` keeps
  its one meaning (catch-up replay of a world that ran without you).
  Corollaries: dev time travel stays dev-only; seasonal/palette content
  is long-tail by design (a February player and a July player play
  different valleys); one standing tension to revisit deliberately —
  the Stillness skill already bends time while sitting (time_scale),
  the single sanctioned diegetic exception; decide at the kitchen table
  whether it survives contact with this entry or becomes pure presence
  (unchanged clock, changed attention).
- **Gameplay loops: posture, not decision — decide after the caravan
  and navigation layers exist** *(2026-07-04)*. The sim-first bet earns
  deciding late. Candidates on the table, to be playtested against the
  live world rather than argued in the abstract: **the connective-
  tissue loop** (traveler/guide/courier between isolated places, in a
  world where information is simulated and distance is respected — the
  novel one; no big game has done it honestly because none simulates
  information or respects distance), knowledge-as-progression
  (wayfinding, star lore, water lore; the map you draw is the character
  sheet), the field-recordist mechanic (IDEAS ★, still leaning yes),
  stewardship (tending wells/shrines/plantings the sim persists), and
  sparse guardian encounters as punctuation. Combat stays deliberate
  and rare regardless. Checkpoint: when caravans walk and no-compass
  navigation works, play for a week and let the loop that pulls win.

## Open (deliberately undecided)

- World-axioms, the glow's name, the Wanderer's identity, journey premise
- **Per-cell persistence schema** (2026-07-04 proposal on the table:
  cells as sparse overlays — save only diffs from the authored+simulated
  baseline, with sim-owned decay: footprints in hours, a felled tree in
  seasons, a burned house repaired by an AgentSim job rather than
  remembered forever. To settle: what does the world remember forever,
  and who repairs the rest? Gates dense settlements; decide before the
  village.)
- ~~The 1:1 clock's consequence~~ — settled same day: pure 1:1, see
  the decision above. Only the Stillness-exception question remains.
- Field-recordist player character (signature-mechanic candidate — leaning yes)
- No-compass/no-markers Morrowind navigation (decide before quest content)
- Fast travel: diegetic-or-none (decide with world size)
- NPC navigation approach: navmesh-per-cell vs steering (before NPC #2)
- Factions, economy model
- **The shared valley** — one persistent world both of you inhabit
  (live/async co-presence) vs. solo worlds with shared traces vs. strictly
  solo. Parked 2026-07-02 with eyes open: deciding *yes* after per-cell
  persistence lands costs rework, so revisit before/with that work (SIM_
  ROADMAP save phase).
- **OS-level ambient presence** (menu-bar status, event notifications,
  wallpaper mode) — "maybe, but just the window for now" (2026-07-02).
