# Systems Roadmap — Skyrim-level or better

*Proposed 2026-07-02, after the six-domain deep-sim build. **Status:
PROPOSAL — not canon until blessed.** Extends FOUNDATIONS F1.5/F2/G5/G6;
nothing here contradicts DESIGN or DECISIONS. Read with the composition
principle in hand: every item below grows a seam of a live system. There
are no rewrites in this document.*

## The thesis: where "better" is winnable

Skyrim's depth is two things: **per-encounter richness** (detection,
combat AI, animation graphs) and **content tonnage** (voiced lines,
dungeons, quest count). The second is a hundred people for four years —
we don't chase it, ever (DESIGN Pillar 5: density of meaning, not stuff).

What Skyrim does *not* have — because staged-encounter design forbids it —
is **persistence**. A Skyrim wolf doesn't exist offscreen; cells reset;
nothing ages; nothing is remembered that wasn't scripted. Our whole
architecture (1:1 time, catch-up, tier-3 data agents, WorldState,
selective memory) is built on the opposite bet. So:

> **Match Skyrim** where absence breaks believability: navigation,
> perception, social texture, schedules that read.
> **Beat Skyrim** on the axes staging can't reach: persistence,
> consequence, ecology, time, memory.

## The four foundations (build first; everything below rides on them)

**P1 — AgentSim: one mind, three presentations.** Extract the
needs/utility/activity core duplicated across `npc.gd` and
`wildlife_manager.gd` into one `RefCounted` (`game/sim/agent_sim.gd`):
needs, drives, activity scoring, hour-chunk advance, serialization.
Presentations own nothing but a body: embodied node / coarse node / pure
data. Every agent-shaped thing forever — NPC, hound, predator, villager,
caravan — is an AgentSim + a record. *This is Skyrim's Actor system, minus
the engine baggage.* Gate: before the village (M4), before NPC #3.

**P2 — Navigation, two-level.** Near: runtime-baked navmesh per streamed
cell (`NavigationRegion3D`, stitched), replacing straight-line +
whiskers. Far: a **world waypoint graph** (roads, fords, passes — records
in `data/nav/`) that data-tier agents route on, so offscreen journeys
respect geography and *arrive from the right direction*. Skyrim NPCs
walk real roads; ours must too, at both tiers, or the tier seam shows.
Resolves the FOUNDATIONS open question (navmesh vs steering: both, by
tier). Gate: before NPC #3 and before any predator reaches the hearth.

**P3 — Perception & attention.** A senses layer on AgentSim: sight cone
(distance + light level — night matters, the moon matters), a sound-event
bus (footsteps, weather masking), and an attention state machine
(unaware → alert → engaged/fleeing → resume, with memory of last-seen).
This is Skyrim's detection system, and it's load-bearing for three
canon features at once: wildlife wariness ("indifferent until provoked"
needs *aware*), social approach (NPCs greeting you needs *noticed you*),
and eventually combat + the field-recordist stealth-adjacent sits.
Dread tone note: a heard-but-unseen agent is the session doc's fog-wood
scare — perception is also an *atmosphere* system.

**P4 — World events & seed binding (Radiant Story, done honestly).**
An append-only, capped **event log** (`world.events`: storm days, deaths,
migrations, firsts) written through defined channels, read by rumors,
journal prose, and seeds. On top: **story-seeds v2** — seeds gain
parameter *bindings* resolved at activation by a query over world state
("a {herd} pushed toward {place} by {cause}" → this herd, this place,
this drought), written into the journal entry. Plus the seed **index**
(evaluate only seeds referencing changed keys — the Conditions language
is closed, key extraction is mechanical). This is Skyrim's radiant quest
aliasing pointed at a world that actually simulates its state.

## System by system

**GameClock / seasons / moon — done.** Add only: calendar events as
records (`data/calendar/`: solstices, invented festivals post-axioms) that
set flags seeds can start from.

**Climate** — regionalize the fields. Wetness/temperature become low-res
world fields (per-region records + blending, same painted-mask pattern as
biomes) so weather can differ across the quilt; add **snow state**
(temp < 0 + wetness → snow coverage the terrain shader reads, melting by
temperature — material-states layer from F1.5) and a **wind vector**
(direction, not just strength — dunes, audio panning, seed drift read
it). Interface now, one region while the world is one valley.

**Climate v2 — the spatial atmosphere (added 2026-07-05, the
climate conversation; concretizes "regionalize the fields" now that
the world is an archipelago with traveling fronts and a volcano).**
Hawaii's fact: one mountain interrupting one prevailing wind makes a
dozen climates. Four rules buy it:
- **Rain shadow (orographic lift)** — *SHIPPED 2026-07-05 (phase 1,
  with the first field: wetness regionalized to an 8×8 grid so the
  shadow reaches ground moisture and flora; see STATUS).* Fronts
  already travel along a wind heading; when a front's path crests
  high terrain it drops extra rain windward and arrives dry leeward.
  Windward flanks run lush, leeward runs dry — *derived, not
  painted* — and Hydrology's windward catchments fill for free.
- **Humidity as its own field:** air humidity ≠ ground wetness —
  distance-to-sea downwind, evaporation off warm water, recent rain,
  falling with altitude. The honest substrate under dew fog, dew at
  dawn, star extinction, and the cricket thermometer (all currently
  proxying off wetness), and the diurnal-swing knob below.
- **Maritime moderation + aspect:** damp the diurnal temperature
  swing near the sea and by humidity (deserts freeze at night,
  coasts don't); warm equator-facing slopes by dot(normal, mean sun)
  (IDEAS already wants aspect for snowmelt).
- **Soil fertility from the erosion bake:** the map pipeline's
  hydraulic erosion already computes sediment deposition (alluvial
  fans) — persist it as a third substrate field. Flora density reads
  it now, agriculture later; "why is the farm *here*" gets a true
  answer.
Payoff: **biomes derived from climate equilibrium** (map stage B′) —
run climate to steady state, classify temperature × moisture
(Whittaker), and hand the result to `derive_biomes` as a better seed
for the painted map; sim proposes, author disposes, same as the
stage-C river plan. Slot after stage C. First gameplay readers:
spoilage/drying, geothermal and tidal set pieces (IDEAS 2026-07-05).

**Weather** — from global state machine to **fronts that travel**: a
weather system is a position + heading on the region map; you *see the
storm coming over the west ridge* before it arrives (readability beats
Skyrim's pop-in weather), and different regions live different weather.
Authored-primary stands: affect zones (session doc §4a) clamp/override
locally; storm odds stay season-biased. Real-local-weather bias stays an
optional kitchen-table toggle, never a dictate.

**FloraLife** — from one global vitality to **per-cell living state**
(F1.5 already promises this): species records (`data/flora/*.json`) with
lifecycle stages (sprout → grow → bloom → seed → dry), per-cell
vitality/coverage advanced on the coarse tick from cell moisture,
**harvest depletes / regrowth is honest** (no cell-reset respawns —
beat Skyrim by simply not cheating), scatter density + stage variant
chosen at cell build, her painted stage variants in the same billboard
slots. Blooms become *placed* ecological events seeds can bind (P4).

**Wildlife** — the ecology ladder, one rung at a time (each
player-visible before the next, per F1.5 discipline):
1. Perception + wariness (P3) — they notice you, keep distance, resume.
2. Herd cohesion — spacing/alignment terms in target choice; a herd
   reads as a herd from a ridge away.
3. **Population records** — the herd count becomes state: births
   (seasonal), deaths (age, predation, drought), migration between
   ranges when food/water fails. The census lives in WorldState; the
   event log carries "the west herd didn't come to water this season."
4. Predator-prey — a second species with a predation drive hunting the
   first (the utility AI already proves context drives via storm_boost);
   predator pushed toward the hearth = the canonical sim-authored seed.
5. Species records generalize it all (`data/wildlife/` grows; bodies per
   species when her creatures land).

**NPCs** — presence over systems, but the systems Skyrim has that make
presence legible:
- **Relationship web** — pairwise opinion values (records seed them, events
  move them through guardrailed channels), read by dialogue conditions,
  meeting behavior, and gift/trade pricing. (G6, already named.)
- **NPC-to-NPC conversations** — the rumor exchange made *visible*: when
  two agents share a place, they face each other, idle-talk barks surface
  what actually got traded (the G6 pond meeting, upgraded from silent).
- **Mood** — one derived contentment value from needs, modulating
  dialogue entry lines and posture. Cheap; Skyrim never had it.
- **Locations & ownership** — places as records (home, workplace,
  social spot, capacity, owner) so activities bind to *places* rather
  than coordinates; ownership makes "someone's chair" possible and
  trespass *social* (a norms/reaction thing) — no crime/guard system,
  that's a city game.
- **Guardrails formalized** (F1.5 rule 6): canon-critical flags whitelist
  writers; the sim can never kill the Keeper by accident.

**Rumors** — provenance ("heard from X", already logged) becomes data;
facts **age and blur** (fresh: "a storm broke the west fence post" →
old: "storms were bad that year" — text templates per age bracket);
rumor pool feeds the bark layer and dialogue small-talk. Skyrim has
nothing here. This is our social texture at near-zero content cost.

**Economy** — the pantry-stock foundation grows into flows: NPCs
**consume** as well as produce (activities gain `consumes`; hunger for
goods, not survival homework — the gentle-comfort law); **prices derive
from stock vs. want** (one curve, per-good, per-holder); trading (G4)
reads them; scarcity becomes visible (a drought that empties pantries
raises what bulbs cost and seeds a storyline — climate → flora →
economy → narrative through pure composition). Skyrim's static gold
pools lose to this with one week of work. Factions/money-vs-barter stay
open (DECISIONS) until the village.

**Quests/Journal** — seeds v2 + index (P4); journal entries render as
**diary prose from bindings** (no-compass canon: the journal says "past
the twin palms," never a marker); "Remembered" grows into the player's
own event log — the game's memoir.

**Dialogue** — three additions, all pre-village: **stable line IDs**
(session doc §8 — costs nothing now, preserves the VO decision either
way, enables localization); a **bark layer** (one-liners outside dialogue
mode, driven by mood/rumors/weather — Skyrim's ambient life is mostly
barks; ours come from real state); **topic memory** (NPCs reference the
last conversation — one WorldState key per pair, huge warmth).

**Combat** — canon unchanged (sparse, monumental, M5, feel-probe first).
The systems dividend arrives free: P3 gives threat perception, AgentSim
gives creature combat drives, P4 makes every fight's outcome a world
event. The encounter-as-resolvable-situation schema (session doc §5)
builds on the dialogue engine when M5 comes. Nothing to do now.

**Save/persistence** — the bill for all of the above: **per-cell deltas**
(fill the `"cells": {}` scaffold: object states, flora cell state,
placed/destroyed diffs — Skyrim's cell-change tracking); **threaded,
delta-based autosave** before WorldState grows (the 30s full-JSON
stringify will hitch first); save-size budget with the selective-memory
policy (what the world forgets is design, not GC).

**Observability — the system that makes the rest shippable.** The
Radiant AI lesson, institutionalized:
- **Sim dashboard** (the Toolkit): time controls, climate/flora/moon dials,
  herd census + positions on the live map, rumor table, seed states,
  event log tail. Every system above lands with its panel *in the same
  commit* or it doesn't land.
- **World soak harness**: headless, run N game-days at speed, assert
  invariants (needs bounded, populations within rails, no NaN, seeds
  fire and complete, save size under budget) — `scripts/soak.sh`,
  in CI. Emergence without regression tests is how Radiant AI died;
  this is the single highest-leverage engineering item in this plan.

## Sequencing (dependency order, mapped to the existing plan)

```
Phase A  P1 AgentSim + P2 navigation + P3 perception     (F2 debts, pre-NPC#3)
         + soak harness v1 (rails for everything after)
Phase B  wildlife ladder 1–3 + per-cell flora + snow/wind (G5/G6 texture)
Phase C  relationships + barks + mood + line IDs + topic memory
         → the village (M4) lands on B+C                  (G6)
Phase D  P4 events + seeds v2 + index + diary journal     (the forever-engine)
Phase E  economy flows + trading                          (G4 completes)
    M5 combat unchanged, after; region/biome work (F3) interleaves when
    the world grows; the dashboard grows a panel per phase, not at the end.
```

Each phase is weeks not months, ships player-visible, and none blocks
the asset or canon tracks. Axioms still gate all real writing.

## The extreme tier (survived the 2026-07-02 spec questions; depth-first)

Three advancements beyond the Skyrim bar, all sim-side, all riding the
foundations above — plus the discipline that enables them:

- **Determinism per system** (build with Phase A, alongside the soak
  harness): every sim system draws from its own seeded RNG stream;
  given the same save + wall-clock span, the world replays identically.
  Not a feature — an engineering discipline that buys perfect bug repro,
  a bulletproof soak harness, and the memoir below.
- **The world's memoir** (after P4): the event log + determinism make
  history *replayable* — sit at the shrine and watch a ghost time-lapse
  of the last season: paths wearing in, the drought breaking. Ties into
  the field-recordist mechanic (a recording is an item carrying the
  actual soundscape of the actual day it was made).
- **Succession-scale ecology** (extends the flora/climate ladders):
  multi-month arcs as content — overgrazed ground recovering through
  stages across a real season, heavy wear eroding into actual terrain
  grooves (the wear map writing the sculpt edit layer), the water table
  breathing across years. Year-two valley ≠ year-one valley.
- **Individual animal identity** (extends wildlife rung 3): each tier-3
  record accrues history — the scar from the winter fight, the limp that
  never healed, the one that drinks last. Names earned by behavior,
  never assigned. The cheapest emotional depth in this document.

Parked, recorded in DECISIONS open list: the shared valley (decide
before/with per-cell persistence), OS-level ambient presence (window
only for now). Declined: stroke-space rendering R&D (depth first);
runtime text generation (offline authoring amplifier only — decided).

## What we deliberately do not chase

Animation-graph combat breadth (anti-spiral, session doc §5). Voiced
content volume (canon; IDs preserve the option). Dungeon/quest tonnage
(seeds recombine instead). Crime/guard systems (no cities). Radiant
filler ("kill N wolves" — a seed with no world-state cause is cut).
World-scale fluid/granular solvers (never — DECISIONS).

## Decisions this opens (kitchen table, don't drift)

1. **Life timescale at 1:1** — do NPCs/creatures age on real years, or
   does biological time run faster than solar time? Gates population
   dynamics (wildlife rung 3) and all mortality stakes. The axioms
   conversation should answer it ("does the valley's life run faster
   than its light?").
2. **Night sky** — real star chart + moon disc vs. invented celestial
   canon (mechanical moon already built either way). Gates no-compass
   star navigation.
3. **Real-weather bias** — cozy or gimmick? Cheap either way, taste call.
4. **Money vs. barter** — before trading UI (Phase E), not before.
