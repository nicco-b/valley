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
consequences; the 1:1 clock (already shipped); the one-timeline save
(below); opportunity-cost progression (★ decision).

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

## The saving system — one world, one timeline

**The insight: the 1:1 clock already decided this.** A reload-to-undo
model is incoherent in Valley — the world lives while the app is
closed; restoring an old save would rewind wall-time and replay it
differently, which the fiction (and the catch-up machinery) can't
honestly mean. Valley is structurally an ironman game; the save system
should embrace what the clock already made true. (Animal Crossing is
the proof this combination reads as life, not punishment — famously,
resetting was *scolded*.)

Proposed design:

1. **Worlds, not slots.** `user://worlds/<world_id>/save.json` — the
   title screen lists worlds (name, day count, last-seen). "New game"
   creates a world; a world is a timeline; there is exactly one save
   per world, always current. This *satisfies* the G1 "save slots"
   leftover in the only form compatible with weight. Deleting a world
   is the only undo, and it's total.
2. **The choice seal.** R2's `seal_choice()` saves immediately on any
   `choice.*` write (debounced a frame for multi-flag effects). Killing
   the app cannot un-choose. Cost honesty: an accidental misclick would
   seal too — so weighty dialogue choices get a *fiction-side* confirm
   beat (a "…are you certain?" line, which is also good writing),
   never an OS-style dialog.
3. **Keep the robustness ladder** (already good): atomic tmp+rename,
   rotating `.bak1/.bak2` — corruption falls back minutes, never
   choices. The baks protect against *bugs*, not *regret*: restore only
   ever offers the newest readable file, no picker.
4. **Versioning + migration registry.** `version` already exists and
   one ad-hoc migration shipped (`civil`). Formalize: a
   `MIGRATIONS: {1: func, 2: func}` chain in save_manager so a
   two-year-old world loads in the 1.0 game. A long-lived single
   timeline makes migrations a core feature, not a chore.
5. **Per-cell state** when the village lands (the `cells: {}` scaffold
   + DESIGN's per-cell persistence law) so the save scales with the
   world, not with time played.
6. ★ DECIDE: **death/failure policy** (pre-M5): what does defeat mean
   in a world that can't reload? Fail-forward candidates: wake at the
   last camp with days LOST (the 1:1 clock makes lost time a real
   price), goods scattered, a rumor of your fall circulating. Death as
   deletion is off the table (too cruel for pillar 1's sit-and-soak
   tone); death as mere teleport is too cheap. The answer is probably
   the journey premise's job (Open Question in DESIGN.md).

## Kitchen-table decisions this plan needs (★)

1. Adopt the Consequence Contract as canon (edit into DESIGN.md).
2. One-world-one-timeline saves: bless or reject (it's a marketing
   sentence AND a design law: "the valley doesn't do take-backs").
3. Progression opportunity-cost model (R3 options a/b/c).
4. Death/failure fiction (with the journey premise).
5. Factions & economy shape — already Open Questions in DESIGN.md;
   R4/R5 give them concrete first forms to react to.
6. The axioms — unchanged, still gate all real WRITING of choices;
   none of R1/R2 code waits on them.

## What starts now (no decisions needed)

R1 standing + rumor propagation → R2 seal + quest schema (code side) →
worlds-not-slots + migration registry (save side). All three are pure
rails: they make every future quest consequential by default, and they
front-run the village so M4 lands on a consequence engine instead of
retrofitting one.
