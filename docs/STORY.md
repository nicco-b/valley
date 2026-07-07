# Story — memory, quests, arcs, and the ground they stand on

*Proposed 2026-07-06 from the outside-perspective session (Nicco's
directives: "I like Skyrim's quests, I don't want to rely too much on the
sim for that" · "the 12-memory thing seems unnecessary" · "NPCs age
normally; write aging into character arcs" · literal fossils · rainbows).
**Status: PROPOSAL — kitchen-table ★s below.** This extends DESIGN pillar 4,
the Consequence Contract (RPG_WEIGHT), and SIM_ROADMAP P4; it REPLACES
R1's standing scalar and the MAX_RUMORS cap, and it reframes the U1
"sim writes the quests" headline. Nothing here contradicts the sim
contract: everything below is deterministic, catch-up-able, observable.*

## The thesis

Skyrim's memorable quests are its most *authored* ones (Blood on the Ice,
Frostflow Lighthouse); its systemic ones are the forgettable ones.
Emergence produces situations; it has never once produced a twist. A
reveal, a reversal, a person who lies to you — those are written or they
don't exist. So the division of labor, stated as law:

> **The sim is the ground: it DELIVERS the hook, STAGES the scenes,
> REMEMBERS the outcome, and ERODES it into feeling, legend, and stone.
> Authored writing is the meaning. Never ask the ground to mean.**

The lineage and the lesson of each:

| Precedent | What it proved |
|---|---|
| Ultima VII | A simulated town and a scripted plot can coexist — by separation |
| Oblivion / Radiant AI | Emergence gets demoted the day it breaks an authored quest |
| STALKER A-Life | Sim actors fight staged scenes; GSC cut the sim's radius to ship |
| RimWorld | A drama manager can PACE stories; it cannot write them |
| Wildermyth | Authored events + sim-cast actors is the workable synthesis |
| Shadow of Mordor | Systemic characters need an authored grammar underneath |

Valley's position: **authored text · sim delivery · sim staging · sim
aftermath.** Skyrim's quest skeleton (stages + conditions — which
`journal.gd` already reimplements in 60 lines) on a world that actually
remembers.

## The derivation law (name what we already do)

Twice the codebase made the same move and got its two cleanest systems:
skills ("levels are derived, so they save for free and can never desync")
and the journal (no quest state machine; done-ness is a reading). Adopt
as canon:

> **Nothing is stored that can be derived. State is facts; everything
> else — skill levels, quest progress, opinions, legends — is a reading
> of facts.**

R1's `npc.<id>.standing` scalar violates this law (double bookkeeping
against the rumor system; they WILL desync). It is replaced below,
before it is ever built.

## Memory v2 — erosion, rehearsal, sediment, fossil

*Replaces MAX_RUMORS (FIFO forgets by arrival order — the Keeper forgets
you saved her life because twelve weather rumors arrived since) and R1's
propagation/damping code. The cap was a crude answer to a true problem:
perfect permanent recall is the Skyrim guard reciting one line for a
decade. Replace the buffer with a process — and make it the SAME process
the terrain already runs. The world remembers by erosion and deposition
(hydraulic bake, wear→paths→roads); minds get identical physics.
One law, two substrates: the valley and its people remember the same way.*

### The fact record (the atom of the whole social layer)

Facts stop being strings and become records; rumor exchange passes the
record; `learn(fact, from_whom)` appends to a provenance chain.

```jsonc
// minted by event channels (storms, deeds, promises, deaths, firsts)
{
  "id": "brook_bank_slumped.d112",
  "kind": "land_changed",        // valence table lives on the KIND record
  "about": ["brook_bank"],       // subjects: npcs, places, the player
  "by": "storm",                 // agent, if any
  "place": "brook_north",
  "day": 112,
  "magnitude": 0.5               // 0..1 — scales strength AND half-life
}
```

Per-mind entry: `{fact_id, strength 0..1, firsthand, chain[], last_told_day}`.
Kind records (`data/facts/*.json`) carry the valence table: how this
kind reflects on each role (`about`, `by`, witnesses' friends…). Valence
authoring is the honest new cost — linear in kinds, tabular, exactly
what Records eats, and it deletes per-quest reputation scripting.

### The four forces

1. **Learning.** `strength = magnitude × relevance × trust(chain)`.
   Relevance: about me 1.0 · my kin/warm ties 0.8 · my place/livelihood
   0.6 · valley-scale 0.5 · else 0.3. Trust: firsthand 1.0, then decays
   per hop — hop-damping IS chain trust; no separate propagation code.
2. **Erosion.** Strength halves every `half_life(magnitude)` days:
   mundane ~4d · notable ~a season · extraordinary ~a year+. Memory is
   self-limiting the way a slope is. No cap. *(Safety rail only: evict
   lowest-strength past 64 entries — engineering, not design.)*
3. **Rehearsal.** Telling or re-hearing restores strength (diminishing
   bump, both parties). **A story lives exactly as long as people keep
   telling it** — rumor lifetime becomes an emergent, honest quantity;
   we never tune it directly.
4. **Deposition.** At strength < 0.05 the record drops and its valence
   settles into per-relationship **sediment**: she no longer remembers
   *what* you did in the spring; she remembers how she feels about you.

**Opinion is a reading, never a variable:**
`opinion(A→B) = sediment[B] + Σ strength × valence × trust` — read into
the R1 bands (hostile/cold/neutral/warm/trusted) by dialogue, prices
(R4), access (R5). Repairing your name is now literal U2 gameplay:
change what people know — trace the chain, confront the source, mint
fresher facts, or let a story starve (stay away while it's hot). Social
stealth with no crime system.

**Fossilization (the legend tier).** A fact with population-wide
tellings ≥ N and age ≥ M calcifies into `lore.legends`: loses chain and
precision, gains permanence, anyone may reference it. Text ages through
brackets keyed to strength/tier: vivid ("a storm broke the west fence
post on the 3rd") → worn ("storms were bad that year") → mythic ("the
year of storms"). Heavy wear becomes roads; heavy retelling becomes
legend; deep time becomes fossils (below). Same law, three depths.

### What this deletes / fixes

- Deletes: MAX_RUMORS · R1 standing scalar + per-hop damping · a
  separate rumor-aging system (brackets read strength).
- Fixes the quest-regression hazard: steps conditioned on
  `npc.X.knows.Y` can currently UN-complete when the FIFO drops a fact
  (`journal.gd` re-evals `quest_done` live; only notifications latch).
  Quest-relevant facts are exactly the high-magnitude, oft-rehearsed
  ones — and step done-ness gets sealed anyway (latch like
  `quest_started`).
- Migration: existing string rumors become facts of kind `observation`,
  magnitude 0.3, chain `[]`; `npc.<id>.knows.<fact>` flags keep their
  keys so no dialogue breaks.

### Soak invariants (land with the system or it doesn't land)

- No fact older than a season survives with < N tellings.
- Sediment bounded; opinions bounded; no NaN.
- Fingerprint: the rumor table + sediment matrix after 30 soaked days
  is deterministic across runs.
- **Legibility assertion (the Radiant lesson, formalized):** each NPC's
  week, summarized hourly, is ≥ 80% self-similar week-over-week absent
  perturbation — routines must be stable enough to LEARN (U7) or the
  player can't perceive the sim, and imperceptible sim is cut (F1.5).

## Questing — three tiers, explicit boundary

*So we never accidentally lean on the sim for meaning.*

**Errands** (sim-authored, U1 stands — demoted from headline to texture).
Seed-latched from real states: water-hauling in the dry spell, the
closed ford. Deliberately small. They exist so Stories don't have to
make the world feel busy.

**Stories** (the Skyrim tier — fully authored, budgeted like guardians).
★ Budget ~30–60 across the game, each bespoke, ONE reversal each. The
authoring unit that works at kitchen-table scale: **a place + a secret +
a person who cares.** Build the location's history first; the quest
falls out of it. The sim contributes the *edges*, where our engine beats
Bethesda's:

- **Hook = a fact.** The invitation travels on the rumor system: author
  one situation, get multiple diegetic entry points free (hear it at the
  fire, or stumble on the place yourself). No markers — `start_if` takes
  `any:` of the entries.
- **Scenes are staged through needs, not teleports.** A scene request
  injects a high-priority activity ("the Keeper wants to be at the
  shrine at dusk"): actors WALK there through the world, weather delays
  them, you can follow them.
- **Resolution mints facts** that propagate, erode, sediment — the echo
  weeks later ("someone mentions it") is free, and it's the thing
  Skyrim players always wished for.

**Arcs** (the tier nobody else can build — unlocked by aging, below).
A person across seasons. Chapters gated by elapsed real time +
accumulated sediment ("she tells you this only after months of warmth"
is ONE condition), not by prerequisite chains. A player here since
spring gets a winter scene a new player literally cannot access yet.

### Schema additions (quest records)

```jsonc
{
  "id": "...", "title": "...", "tier": "story",
  "hook": "fact_kind_or_id",              // rides the rumor system
  "start_if": { "any": [ ... ] },         // multiple diegetic entries
  "excludes": ["other_quest_or_branch"],  // R2: branches that CLOSE
  "deadline": { "day": 128 },             // R2: 1:1 clock, fail-forward
  "steps": [ { "id", "text", "done_if", "effects": [ ... ] } ],
  "scenes": [ {
      "id": "reveal", "who": "keeper", "where": "shrine",
      "hours": [18, 20], "priority": "high", "hold_days": 3
  } ]
}
```

Scene contract (the historically hard part — the A-Life lesson): a
scene is a REQUEST, not a command. It must assemble within `hold_days`
or the quest fails FORWARD into world truth (she couldn't come; the
rumor of the storm that stopped her travels). Guardrails stand: the sim
never kills a canon actor; scenes never teleport one.

**The scene waits for the player (canon: Nicco, 2026-07-06).** A scene
never resolves off-screen: `hold_days` counts only days the player was
present-and-absent-minded is fine, but the reveal itself requires the
player within earshot. The window (`hours`) is when the actor shows up;
if the player doesn't, the actor goes home and tries again — the hold
clock ticks on ATTEMPTS the player missed, not wall days, so a
morning-only player still gets their dusk scene (the actor keeps
coming back until they meet). Fail-forward remains for the actor's
side only: if the WORLD stops her (storm, injury channel), that's the
forward failure — player absence never is.

### The craft checklist (every Story, no exceptions)

1. Hook arrives diegetically (a fact, a sight, a letter — never UI).
2. The journey tours a place worth seeing (quests are guided tours of
   authored space; the reveal recontextualizes ground already walked).
3. Exactly one reveal.
4. A choice satisfying the Consequence Contract (something closes).
5. An **echo**: a fact minted at resolution that someone will retell.
6. No-marker discipline: every step text embeds geography ("past the
   twin palms, where the bank gave way"). ★ Decide the direction-giving
   vocabulary (landmark names, cardinal style) before quest #3, not #30.

### Exemplar Story — "The Bank Gives Way" (buildable with the two NPCs)

```jsonc
{
  "id": "bank_gives_way", "title": "The Bank Gives Way", "tier": "story",
  "hook": "brook_bank_slumped",   // minted by hydrology after a real storm
  "start_if": { "any": [
      { "flag": "npc.wanderer.told.brook_bank_slumped" },
      { "flag": "player.saw.brook_bank" } ] },
  "steps": [
    { "id": "walk",
      "text": "Walk the brook north of the pond, to where the storm took the bank.",
      "done_if": { "flag": "player.saw.brook_bank" } },
    { "id": "carry",
      "text": "Bring what the water uncovered to the Keeper, at the shrine, toward dusk.",
      "done_if": { "flag": "choice.bank_marker.sealed" } }
  ],
  "scenes": [ { "id": "reveal", "who": "keeper", "where": "shrine",
      "hours": [18, 20], "priority": "high", "hold_days": 3 } ]
}
```

The dig: a carved shell older than the shrine, in the fresh cut. The
reveal (in dialogue, where reveals live): the Keeper recognizes the
carving — the shrine you know is not the first; one stood by the water
before the brook moved. The choice, sealed: return it to the water or
set it at the shrine. `excludes` each other; each mints a fact with
opposite valences for Keeper and Wanderer (a friend AND a
disappointment from one act — both ends of the opinion system in the
first authored quest); "shrine" mutates existing content (a small placed
object, forever). The echo arrives on its own legs weeks later.

## Aging & Arcs (canon: Nicco, 2026-07-06)

**NPCs age normally** — biological time = solar time = the 1:1 clock.
This answers half of SIM_ROADMAP's open question #1 and sets the memory
half-life scale: tuned in real days, generously (a season is the unit of
social memory). Consequences:

- **The season is the arc-visible unit.** Most players live with the
  game weeks-to-months; write arc chapters to land within a season. A
  full lifespan is background truth, not content.
- **Aging is written INTO arcs**, never simulated at canon actors:
  mortality and decline of named people go through whitelisted authored
  channels only (F1.5 rule 6 stands — the sim never kills the Keeper;
  her authored decline across year two may be the most affecting thing
  in the game).
- Deadlines stay RARE and warm (the gentle-comfort law): real-Tuesday
  expiry is weight in a doc and homework in a life; fail-forward always,
  guilt never. ★ Tone-test the first deadline quest early.

## Conditions v2 (the DSL is four lines carrying a skyscraper)

Everything above conditions on things the current language cannot say.
Grow it ONCE, on paper, before quest content multiplies — and keep it
**closed** (no expressions): the seed index depends on mechanical key
extraction.

Additions: `all:` / `any:` / `not:` composition · `lt` / `eq` ·
`since: [flag_or_event, days]` · `season` · `knows: [npc, fact]` ·
`opinion_band: [npc, band]` · `told: [npc, npc, fact]`. Existing four
predicates unchanged.

## Fossils (Nicco: "I want literal fossils")

Fossils are the geological legend tier — the world's version of a story
retold until it turned to stone — and a **third legible era** that
predates people entirely (extends the two-era canon). An invented
ecology's paleontology is a worldbuilding cheat code: segmented ancestors
of the bulb-flora; a creature nobody alive has seen.

Mechanics, nearly free on existing rails: the erosion bake seeds
**fossil beds** (authored placements in strata, a `data/fossils/`
record layer); real hydrology exposes them — after a storm, a bank
slumps and something is showing in the cut (`land_changed` events roll
exposure checks against local beds). Fossil-hunting = walking the washes
after weather: pillar-1 behavior, going out BECAUSE of the world's own
events. One collector NPC turns the layer into an Arc. ★ Canon: what
died here (axioms-adjacent; hold for the paintings).

## Rainbows (Nicco: "and rainbows")

The substrate exists without knowing it: sun position, traveling fronts,
humidity as its own field (Climate v2). Derive, don't script: rainbow =
anti-solar point + rain-in-air + sun below ~42°. It appears HONESTLY —
after storms, low sun, facing away — as a painted arc at the anti-solar
point (billboard language; hers). Sets `sky.rainbow` so dialogue, seeds,
and facts can reference it ("were you out for it?" — a mintable moment).
NPCs get the watch-idle: everyone stops and looks. The cheapest awe in
the plan. ★ Canon options: a **red sun's narrowed, red-shifted arc**
(one of the "light behaves differently here" tells — ownable in her
palette) · **moonbows** on bright full-moon rain nights, rare enough
that seeing one is an event.

## Build order (each phase player-visible; dashboard panel per phase)

```
S1  Conditions v2 + fact/kind records + string-rumor migration   (pure code)
S2  Memory dynamics (erosion/rehearsal/sediment) + derived opinion
    + Toolkit memory panel (rumor table → fact table, sediment matrix)
    + soak invariants incl. the legibility assertion
S3  Quest schema (excludes/deadline/scenes/effects/echo)
    + seal step latching + "The Bank Gives Way" end-to-end
S4  Fossils + rainbows (both ride storms; ship together as one
    "after the weather" moment)
S5  Legends (fossilization) + first Arc chapter        (post-M4 village)
```

## Honesty ledger

- **Valence tables are real authoring** — linear in fact-kinds, but
  someone (Nicco) writes every judgment. Budget it like dialogue.
- **Scenes vs. sim is THE hard engineering** in this doc (every
  precedent above bled here). The request/hold/fail-forward contract is
  the mitigation, not a solution; expect iteration.
- The memory model is *plausible*, not psychological — an NPC won't
  connect two old facts into an inference. Don't chase it; the bar is
  "reads as human at conversation distance."
- Arcs need **calendar-scale playtesting** no one can shortcut. Start
  one arc early on the two NPCs purely to live with it.
- Text volume grows with age brackets — mitigate: brackets per KIND,
  never per fact.
- Fossils/rainbows are cheap only because hydrology/climate are real;
  they are downstream and must not drive those systems' schedules.

## Kitchen-table decisions (★)

1. Adopt the derivation law + the thesis ("never ask the ground to
   mean") into DESIGN.md.
2. Bless Memory v2 as the replacement for MAX_RUMORS and R1's scalar
   (R1's BANDS survive; the scalar dies).
3. Story budget (~30–60?) and the place+secret+person unit.
4. Direction-giving vocabulary (no-marker step text) — before quest #3.
5. Memory half-life constants (now anchored: biological time = solar
   time; tune in real days, season = social memory unit).
6. Fossil canon (what died here) — with the axioms, over the paintings.
7. Rainbow canon: red-shifted arc? moonbows? (art call, hers.)
8. First deadline quest tone-test (gentle-comfort law audit).
