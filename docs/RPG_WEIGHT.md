# RPG Weight — decisions that hold (DRAFT for the kitchen table)

*Proposed 2026-07-06 from Nicco's directive: "I desire real RPG
mechanics. I want players' decisions to hold weight — unlike Skyrim,
where it leans action-adventure." This is a PROPOSAL: the ★ decisions
below belong to the kitchen table; the build phases are ready to start
once their gating decisions land. DESIGN.md pillar 4 ("Decisions mutate
the world") and the Consequence scope law are the canon this extends.*

## The thesis (positioning)

At kitchen-table scale you cannot out-content Larian or out-simulate
nothing — but nobody else is building a *sim-first* consequence RPG in
a painted world. Skyrim fakes consequence with scripted flags because
its world is static; Valley's world already **remembers by simulation**
(WorldState, rumors, stocks, depletion, wear, 1:1 time). The niche that
makes "one of the best RPGs ever" reachable for two people:

> **A small world that genuinely remembers — where consequences are
> carried by the simulation, delivered by people, and never undoable.**

The lineage being joined: Ultima VII (the simulated town), Gothic
(factions that close), Morrowind (knowledge as progression), Disco
Elysium (text as the reactive surface), Animal Crossing (1:1 time that
makes the world real) — density of meaning over density of stuff,
exactly DESIGN.md pillar 5.

## Why Skyrim drifts, in one sentence each

- Nothing **closes**: you can lead every guild — choices are unlocks,
  never locks.
- Consequences are **scripted**, so they're expensive, so they're rare.
- The world **waits** for you: nothing proceeds without the player.
- Reload **erases** anything: the save system is an undo button.
- Skills **converge**: everyone eventually masters everything.

Valley's counters, respectively: the consequence contract; sim-carried
consequences; the 1:1 clock (already shipped); consequences worth
keeping (weight from content, not save friction — v2 below);
opportunity-cost progression (★ decision).

## The Consequence Contract (proposed law, sibling to the sim contract)

Every meaningful player choice MUST:

1. **Write WorldState** — a namespaced flag/value (`choice.*`), the
   moment it is made.
2. **Be irreversible** unless the fiction itself provides the undoing
   (an apology quest is content; a reload is not).
3. **Echo at least once, later and elsewhere** — through a system, not
   a script: a rumor that travels, a stock/price that shifts, standing
   that moves, an access that opens or closes, a schedule that changes.
4. **Close something** whenever it opens something. Not every choice —
   but a quest where no option costs anything is flagged in review the
   way a sim without catch-up is.
5. **Mutate existing content, never spawn parallel branches** (the
   existing scope law — impact scales linearly, not combinatorially).

A choice that can't satisfy the contract isn't a choice; it's a flavor
button, and gets written as flavor.

## The systems plan (build order, on existing rails)

**R1 — Standing (reputation).** Per-NPC `standing` value in WorldState
(`npc.<id>.standing`, −100..100), moved by choice effects, **propagated
by the existing rumor system**: when NPCs swap news, opinions travel
with facts, dampened per hop — the Keeper thinks less of you because
the Wanderer *told her*, at the speed real gossip walks. Dialogue
conditions read standing bands (hostile/cold/neutral/warm/trusted).
Faction standing later derives from member-NPC webs (M4). *Pure code,
~2 days, no gating decision. The multiplier for everything after.*

**R2 — The choice seal + quest schema.** `WorldState.seal_choice(id,
value)`: writes the flag AND triggers an immediate save (see below) —
the choice is committed to disk before the dialogue box closes. Quest
records gain `excludes:` (mutually exclusive quest/branch ids) and
`deadline:` (GameClock day — the 1:1 clock makes real deadlines
POSSIBLE and precious; an errand that expires next real Tuesday is
weight no fantasy timer matches). Fail-forward: an expired quest
resolves into world truth (the caravan left without you; the rumor of
your absence travels), never a fail screen. *Code ~2-3 days; needs no
axioms, but real quests using it do.*

**R3 — Progression with a spine.** Use-based stays (canon). ★ DECIDE:
the opportunity-cost model. Options: (a) practice budget — advancing
one skill slows others (soft Morrowind); (b) hard caps chosen at
milestones; (c) scarcity — advanced technique needs teachers/tools
found in the world (fits "tools from the world" canon, my lean:
combines with (a)). *Blocked on the ★ only; small code.*

**R4 — Economy that notices (trading, G4).** Prices derive from NPC
stocks (already accumulating) and scarcity; player buying/selling/
gifting moves both stock and standing. No global market — each person's
prices are theirs. *Builds directly on R1 + pantry stocks.*

**R5 — Factions (with the village, M4).** Groups as webs of NPCs with
shared standing modifiers and **exclusive allegiance thresholds**
(Gothic's lesson: past a line, choosing is joining, and the others
notice). Design the village records with faction fields from day one —
retrofitting exclusivity is brutal. *Blocked on axioms + village.*

## The saving system — worlds, forks, and the seal (v2)

*(v1 claimed reloading was "incoherent" with the 1:1 clock. Nicco
called it, and he's right: the clock is time-of-day + elapsed-duration
replay, and reloading an older save already works — catch-up replays
the elapsed real time from that snapshot's wall timestamp, dial synced
to local time. Better still, the Rng streams live in WorldState, so
the replay is DETERMINISTIC: reloading Sunday's save on Wednesday
gives the identical Wednesday every time. Ironman is a design CHOICE
here, not an architectural fact — and that separation is good news:
weight must come from the Consequence Contract, not save friction.
BG3 is the proof: fully scummable, still the most reactive RPG in
years, because consequences are interesting enough to keep.)*

1. **Worlds.** `user://worlds/<world_id>/` — separate timelines, listed
   on the title screen (name, day count, last-seen). Satisfies the G1
   "save slots" leftover at the structural level.
2. **Named manual saves within a world.** Reloading rewinds to that
   fork and honestly re-lives to now via the existing catch-up. One
   accepted wrinkle: shared-with-reality time replays (the storm from
   actual-Tuesday happens again, identically) — the same strangeness
   every save game has, just slightly more visible here.
3. **The choice seal** (`WorldState.seal_choice`) — its real job was
   never anti-reload: it writes the choice AND saves immediately, so a
   crash or rage-quit mid-consequence cannot dodge a decision. Weighty
   dialogue gets a fiction-side confirm beat ("…are you certain?"),
   never an OS dialog.
4. **Ironman as an opt-in world flag** ("one journal"): a single
   rolling save, manual saves disabled — the Animal Crossing contract
   for players who want it. Nearly free to offer; a good marketing
   sentence for those who opt in, never imposed.
5. **Keep the robustness ladder** (atomic tmp+rename, rotating baks —
   bug armor, offered as newest-readable only).
6. **Versioning + migration registry.** `MIGRATIONS: {1: func, ...}`
   chain in save_manager so a two-year-old world loads in the 1.0
   game. Long-lived timelines make migrations a core feature.
7. ★ DECIDE: **death/failure policy** (pre-M5): fail-forward candidates
   — wake at the last camp with real days lost, goods scattered, a
   rumor of your fall circulating. Probably the journey premise's job.

## What the sim-forward setup unlocks (second pass, 2026-07-06)

*Each entry names the RAILS it rides (verified in code this week) and
the honest GAP. Tiered by cost. The through-line: other RPGs fake
these with scripts; here they'd be true statements about sim state.*

### Nearly free (rails exist; wiring + content)

**U1 — The sim writes the quest board.** "The Dry Spell" already
proved the pattern: a sim state latches a journal seed. Generalize:
`valley.parched` → a water-hauling errand; storm-days + river level
max → the ford closes, a repair need appears; the REAL winter snowline
crossing the volcano → the pass shuts seasonally and caravans reroute.
This is Radiant done honestly — Bethesda generates fetch quests from
templates; we latch quests onto things that actually happened.
RAILS: WorldState values all exist; seed-latching shipped. GAP: quest
content + a review pass per seed (scope law applies).

**U2 — Gossip with provenance.** Rumors already travel person-to-person
with a teller. Store the provenance chain and standing (R1) inherits
it: "who told you that?" becomes playable — trace a rumor to its
source, repair your name by confronting the origin. Social gameplay
no mainstream RPG has, from ~20 lines on the existing exchange.
RAILS: learn(fact, from_whom) exists. GAP: persist the teller;
dialogue conditions on provenance.

**U3 — The almanac is content.** Real seasons, real sunrise, real moon.
Appointments at actual dawn; a festival on the ACTUAL solstice;
winter-only regions (the snowline is already emergent); the cricket-
thermometer (IDEAS ★) as a learnable skill. GAP: none — content only.

**U4 — Ecology-driven economy.** Forage depletion, regrowth, vitality,
and NPC `produces` stocks already exist. Hook production rates to
local vitality and prices to actual stock: a drought RAISES the price
of dried blooms because gathering genuinely slowed. The player who
reads weather can play the market — knowledge as literal profit.
RAILS: stocks + vitality_at + depletion. GAP: produces×vitality hook
(small) + R4 pricing.

### Medium builds

**U5 — Witnessing.** Perception v1 exists (wildlife: light-scaled
sight, hearing; moon phase already thins night light). Extend to NPCs:
deeds seed rumors ONLY from actual witnesses — darkness and weather
genuinely conceal; a new-moon heist is mechanically real stealth.
Thief-grade systems emerging from the existing light model + rumors.
GAP: NPC perception port + a deed→witness→rumor bridge; crime/
ownership design (★ eventually).

**U6 — The world testifies (tracking).** Wear paths record where
people actually walk (saved, fading over months); sand holds real
prints (conserved, longer in damp); depletion wounds show harvesting.
A tracker skill that reads REAL traces — "someone gathered here
recently, prints head north" as a true statement, not a spawned decal.
GAP: query APIs over existing fields + content.

**U7 — Routine as puzzle.** Needs-driven schedules are emergent but
OBSERVABLE and stable — "catch the Keeper alone" is a genuine
deduction from watching her days, not a quest marker. GAP: none
technically; quest-design discipline.

**U8 — The away-chronicle.** Catch-up already replays every missed
hour deterministically. Tap notable events during replay into a
digest: "While you were away: Tuesday's storm flooded the brook; the
Keeper asked after you; the bloom came in." The save's 1:1 wall-clock
life becomes NARRATED — Animal Crossing's warmth with Dwarf Fortress'
chronicle. GAP: an event-tap taxonomy in advance_hours consumers
(medium; needs care to stay cheap).

### Horizon-defining

**U9 — The year as structure.** Real seasons + hydrology + snowline =
an annual rhythm: summer expeditions when the pass opens, autumn
gathering gluts, winter scarcity. The game becomes a COMPANION over
months of real life — which is pillar 1 (sit-and-soak) at
calendar scale. Design implication: content paced as weeks-long arcs
+ a daily-check-in loop, not a 40-hour burn.

**U10 — Lived history.** Placed records already stamp their day; wear
persists and fades. Let heavy wear PROMOTE into road records (the
Traces feeding the Ways): paths, then roads, then settlement logic —
"two legible historical eras" (DESIGN) where the newest era is the
player's own. GAP: wear→road promotion pass (real build, the fields
exist).

**U11 — Everyone's Tuesday storm.** Weather is an Rng stream. Seed it
from the REAL DATE instead of the world and every player on Earth
lives the same fronts on the same days — communal weather, shared
almanacs, "were you out in Thursday's gale?" — community events with
ZERO netcode. ★ design choice (per-world weather vs. shared sky);
trivially cheap either way.

### What it does NOT unlock (honesty ledger)

Text is still hand-written — rumors are facts, not prose; the
reactivity SURFACE is writing, gated on axioms. NPC witnessing, crime,
and ownership are real builds, not wiring. Every unlock inherits the
sim contract's discipline (deterministic, catch-up-able, observable) —
that's the tax that keeps the fingerprint honest. And the scope law
stands guard over all of it: consequences mutate existing content,
never spawn parallel branches.

## Tone directives (Nicco, 2026-07-06)

Whimsical and magical-feeling: exploring and gathering in a wondrous
land, making friends AND enemies, helping the locals, quests with a
little complexity. Mappings: friends/enemies = BOTH ends of R1's
standing (warm bands get gifts/errands/being-asked-after; cold bands
get refused trade, counter-rumors, shut doors — U2 in reverse);
helping locals = U1's sim-authored quest board; complexity = R2's
schema under the scope law; whimsy = art/writing direction plus a
systems rule: consequences stay warm-hearted (Ghibli, not grimdark).
Note: "magical" is the FEELING — the canon ban on the word "magic"
(the glow has rules) is assumed to stand; confirm at the table.

## Kitchen-table decisions this plan needs (★)

1. Adopt the Consequence Contract as canon (edit into DESIGN.md).
2. Save policy: default = worlds + manual saves (Nicco's call,
   2026-07-06); ironman "one journal" as opt-in world flag — bless.
3. Progression opportunity-cost model (R3 options a/b/c).
4. Death/failure fiction (with the journey premise).
5. Factions & economy shape — already Open Questions in DESIGN.md;
   R4/R5 give them concrete first forms to react to.
6. The axioms — unchanged, still gate all real WRITING of choices;
   none of R1/R2 code waits on them.
7. ★★ VOICE: Nicco wants "a lot of voiced dialog" (2026-07-06) —
   this REVERSES DESIGN.md canon ("text-only, no voice acting — by
   design; reactivity over performance"), and the reactivity reasoning
   is load-bearing for this whole plan (recorded VO is the most
   reactivity-hostile asset class there is). Proposed third path: an
   INVENTED SPOKEN LANGUAGE (animalese/Simlish-style syllable banks,
   per-character voice + emotion) — audibly voiced, whimsy-native,
   costless per text variant, deepens the naming-language canon item,
   recordable by one person. Decide: full VO / partial VO (barks +
   key lines) / invented language / text-only stands.

## What starts now (no decisions needed)

R1 standing + rumor propagation → R2 seal + quest schema (code side) →
worlds-not-slots + migration registry (save side). All three are pure
rails: they make every future quest consequential by default, and they
front-run the village so M4 lands on a consequence engine instead of
retrofitting one.
