# Quests — the design (stages, threads, roles, hooks, and the honest clock)

*Proposed 2026-07-08 from the quest-design session. Nicco's brief,
verbatim: "i'd like to take this opportunity to design a delightful
quest system. now that we know we will build them in strata, we have
the opportunity to design something excellent. i'd like to leave the
door open for custom code in quests so future games might feel unique.
but that will be on top of our new quest design. perhaps the current
design we have for quests is sufficient but let's take a closer look.
i want questing to be robust. this may bleed into other design
decisions we make about this game engine."*

***Status: PROPOSAL — kitchen-table ★s in §15.** This document AMENDS
[STORY.md](STORY.md); it does not replace it. What it keeps, changes,
and supersedes is stated precisely in §1. It is also the valley-side
answer to Strata's PLAN_CREATION_LIBRARY §4/§4b (rungs 3, 5, L10): the
record shapes here are what the visual quest window will render, and
§12 feeds that build. Everything below obeys the sim contract (1:1
time, catch-up, determinism), the derivation law, the scope law
(mutate, never branch content), and the fork law (zero engine patches
— verified in §11).*

---

## 0 · Executive summary

**Two co-equal pillars, stated first because the whole design hangs
between them** (Nicco, mid-session: "i'd love to do that novel stuff
but also i still want to be able to build solid story lines that
progress"):

> **Pillar A — the authored spine.** Hand-built storylines with acts,
> deliberate pacing, gated progression, setpiece moments, and
> ordering *guarantees* — the designer fully controls the path, the
> classic CK/BioWare strength. The record shapes must express this
> natively, not as a degenerate case of the emergent machinery.
>
> **Pillar B — the sim-native texture.** Hooks that ride real weather,
> roles filled from live minds, errands the world writes, echoes that
> erode — the layer no other engine can run.
>
> **How they coexist:** authored arcs may USE sim conditions and
> roles for texture and delivery, but **the spine never gates its
> only path on an unguaranteed sim outcome** (§3, the spine-gating
> rule). Sim facts open side doors, add color, and deliver hooks; the
> designer's ordering guarantees are structural and lintable. One
> schema serves both pillars — a main-quest chapter and a radiant
> errand are the same record kind at different settings.

The audit's verdict on STORY.md: **the philosophy is right and stays;
the schema is one size too small.** The thesis (authored text · sim
delivery · sim staging · sim aftermath), the three tiers, the scene
contract, the craft checklist, Memory v2 — all of it stands. But the
flat `steps` array cannot say "this quest has two endings," cannot
say "act two follows act one" across quests, conflates journal prose
with completion logic, names its cast by hardcoded id, has no door
for code, cannot change the world's furniture when a stage lands, and
re-derives done-ness live (the un-complete hazard STORY.md itself
flags). Six moves fix it, each stolen from a precedent that earned it
and re-grounded in what our sim can do that theirs couldn't:

1. **The monotone quest** (our own derivation law, taken seriously).
   No quest state machine and no mutable "current stage" variable:
   a quest is a small DAG of **stages**, and quest state is an
   append-only set of latches — `(stage, day)` facts sealed into
   WorldState the moment a stage's conditions pass. Nothing ever
   un-happens; failure and expiry are just terminal stages; the
   journal is a **memoir written once**, never edited. This keeps
   Skyrim-stage expressiveness while staying a *reading plus a seal*,
   not a machine.
2. **Threads — the authored spine made structural** (the
   BioWare/Witcher lesson, and Pillar A's machinery). Quests chain
   into **threads** by gating on each other's latches (`after_quest`
   sugar); stages may be marked `required` (the linter proves every
   path to every ending passes through them — "this can never be
   skipped" as a *checked invariant*, not a hope); the **no-wedge
   law** guarantees a storyline can't be driven unfinishable; and
   **world flips** (CK's enable-parents) let a stage visibly rebuild
   the bridge, light the shrine, raise the camp — progression the
   player *walks through*, as pure data over placement groups.
3. **Roles** (Creation Kit aliases, the best idea in quest tooling).
   Quests reference named roles — `$keeper`, `$teller`, `$pack` — that
   the engine fills from the live world by data-declared query rules.
   Fills are deterministic and latched. This is the reuse door, the
   radiant-errand door, and the sim-native door in one shape.
4. **One condition vocabulary over WorldState only.** Sims speak by
   mirroring scalars into WorldState (they already do: `weather.state`,
   `water.<id>.flow`, `climate.wetness`, `valley.parched`); conditions
   read keys and nothing else. The language stays **closed** (no
   expressions), so key extraction is mechanical, evaluation is
   event-driven off `WorldState.changed` through an index, catch-up
   is correct by construction, and Strata can render condition rows
   from a published schema without ever evaluating one.
5. **The hooks door, first-class** (the Papyrus-fragment pattern).
   A quest record may name a GDScript hooks script in the game repo;
   the Story manager calls typed lifecycle entry points (`on_stage`,
   `on_fill`, `on_expire`, custom predicates with declared watch
   keys), and hooks declare typed **properties the record binds**
   (CK's property binding: data points, code stays reusable). Hooks
   touch the world only through WorldState/Story APIs — so they stay
   headless-testable and soak-honest — and they are how a future game
   ships unique quest *feel* on this machinery without forking it.
6. **Robustness as machinery, not intention:** a headless quest
   harness (tests as data: script world mutations, assert latch
   sequences, one full-arc playthrough per ending of every shipped
   storyline), a quest linter in `test.sh`, the `journal.*` namespace
   added to the soak fingerprint (a playerless soak must latch only
   sim-born errands, identically, every run), and an id-stability law
   for shipped stages so saves survive quest-record updates.

The new autoload is **`Story`** (the Campfire system): loads quest
records, owns the condition index, latches stages, fills roles,
requests scenes, calls hooks, writes the memoir. One manager, all
data-driven, zero engine forks.

---

## 1 · Relationship to STORY.md — precisely

**STORY.md keeps (unchanged, still canon-track):** the thesis and the
division-of-labor law ("never ask the ground to mean") · the
derivation law · Memory v2 whole (facts, erosion, rehearsal, sediment,
fossilization) · the three tiers and their budgets · hook-is-a-fact ·
scenes staged through needs, the request/hold/fail-forward contract,
and "the scene waits for the player" (canon) · the craft checklist ·
aging & arcs · deadlines rare-and-warm · fossils · rainbows · the
S1–S5 build order (S3 now points at this document's shapes) · all
eight of its kitchen-table ★s.

**This document supersedes two sections of STORY.md:**

- *"Schema additions (quest records)"* — the flat `steps` array and
  its exemplar are replaced by §3's stage shape ("The Bank Gives Way"
  is re-authored there, same story, richer skeleton).
- *"Conditions v2 (the DSL is four lines carrying a skyscraper)"* —
  absorbed and completed by §5 (its additions all survive; the
  evaluation model, the mirror law, and the schema-publication story
  are new).

**This document adds what STORY.md never covered:** the authored
spine made structural — threads, required stages, the no-wedge law,
world flips (§3), roles (§4), the keyword/tag axis (§4–5), the
custom-code contract with property binding (§6), the evaluation model
and seed index made concrete (§5), journal UX and discovery (§8),
dialogue record shapes (§9), persistence/versioning/testability/soak
stance including authored-arc invariants (§10), the engine-bleed
ledger (§11), and the Strata feedback section (§12).

**On the tier audit, one honest finding:** STORY.md's tiers separate
*who authors* (sim/human) and *at what scale* (errand/story/arc), but
they give the authored tier no **spine** — nothing orders Stories
into a progressing line, nothing marks a beat unskippable, nothing
guarantees finishability, and nothing makes progression visible in
the world's furniture. §3 adds exactly that, without adding a tier:
threads are relationships *between* quest records, not a new kind.

**Ground truth note (2026-07-08):** the journal, quests, dialogue,
NPCs, and rumors described in STORY.md as existing were retired in
commit `1390574` ("de-valley"). What survives in the tree is
`Conditions` (four predicates), `WorldState` (+ its `changed` signal),
the sim substrate, and the soak harness. The retired code —
`journal.gd`, the custom dialogue engine, four quest records — is
recoverable from `1390574^` and is treated here as *reference
implementation v1*, not as installed base. We are designing on a
green field with a proven sketch in the drawer. That is exactly the
right moment to get the shapes right.

---

## 2 · The survey — stolen with pride

For each precedent: what made it delightful, and what valley's sim
lets us do that they couldn't.

| Precedent | What we steal | What our sim adds that they lacked |
|---|---|---|
| **Creation Kit / Skyrim** | Stages as numbered checkpoints with journal text; objectives as separate display lines; **aliases** (roles filled at runtime — the machinery behind radiant quests); condition *rows* everywhere; tiny named script fragments per stage with **typed properties the editor binds** (code points at nothing; data does the pointing); **enable parents** (a stage flips a group of placed objects — the burned house becomes the rebuilt house, as data); **keywords** (conditions test tags, never identities — "is Animal," not "is hound #7"); the Story Manager listening for world events | CK aliases query a static world (nearest dungeon, random NPC). Our roles query a *live* one: "an NPC who currently knows the hook fact," "the herd that survived the storm," "the shrine the player visits most." CK's story manager listens to a handful of engine events; ours listens to `WorldState.changed` — every mirrored sim truth is an event source for free. And our enable-parents flips are *saved sim-consistent state*, so a rebuilt bridge persists, catches up, and fingerprints like everything else |
| **The Witcher 3** | The authored multi-act storyline as the game's backbone — the Bloody Baron: acts with gates, mid-quest reversals, endings that pay off choices made hours earlier; quest DESIGN as a pacing craft (every act ends on a turn) | CDPR's world-state deltas are hand-scripted per branch. Ours are latches + minted facts read by one memory system — the Baron's ending doesn't need bespoke plumbing, it needs one `mint` and the world does the remembering. And their clock is fake: our act gates can be *seasons* |
| **Classic BioWare / ME2's suicide mission** | The campaign spine: hub-and-spoke acts, companion arcs feeding a finale; ME2's ending is a **reading of everything you latched** — loyalty, upgrades, assignments — resolved in one setpiece | This is our monotone model vindicated at scale: a finale whose `advance_when`/branches read the accumulated latch-set is *exactly* how our quests already work. No new machinery — a valley finale that weighs a year of sealed choices is just a stage with rich conditions |
| **Majora's Mask** | Deadline pressure creates care; the Bombers' Notebook (schedules as *content* — knowing where someone will be at 6pm is progress); the world runs whether you engage or not | Majora fakes its clock in a 3-day loop and resets. Our clock is real and **never resets**: a deadline spends real days, a missed scene really happened without you, and fail-forward mutates a world you must go on living in. Deadlines therefore stay RARE and warm (STORY law) — the mechanism is cheap, the weight is enormous |
| **Outer Wilds** | Knowledge IS progress — the only save file is what the player learned; the ship log as a map of understanding, not a todo list | Their knowledge graph is authored and static. Ours is *distributed through simulated minds*: facts travel on rumors, erode, and can be traced to sources (U2). "Find out what she knows" is a real query over a real memory system, and the journal-as-memoir (§8) is our ship log |
| **Disco Elysium** | Checks against internal state, not world state; the journal has a *voice*; failure is content, not a wall | Our internal state is the world's opinion of you — derived, never stored (Memory v2 sediment). A "check" is `opinion_band`/`knows` over honest data. And failure-as-content is structural here: expiry latches a terminal stage with journal prose, never a fail screen |
| **Breath of the Wild** | Environmental discovery — quests announced by the world's own shape (a strange rock, smoke on a ridge), no exclamation marks; the shrine sensor as *warmth*, not GPS | BotW's environment is static; its discoveries are placed once. Our hooks ride **events the sim mints**: a storm exposes the fossil bed, a dry river opens the crossing quest. The world doesn't just hold secrets — it *turns them over* in season (§8) |
| **STALKER A-Life** | The offscreen world is real; scripted scenes negotiate with the sim rather than overriding it — and where GSC lost that fight, they cut the sim | We inherit their scar tissue as law: scenes are REQUESTS with hold windows and fail-forward (STORY.md canon); the sim never kills canon actors; and the legibility soak assertion keeps routines learnable. The A-Life lesson is why the scene contract is the most engineered part of this design |
| **RimWorld (storyteller)** | Sim-driven event *pacing* — drama has a budget and a rhythm; the storyteller selects, never writes | Our storyteller equivalent is deliberately humble: seed caps per domain (IDEAS guard-rail: "a drought is weather, not a quest dispenser") and errand cooldowns (§3). We pace by scarcity, not by drama curves — the ambient thesis over the roguelike one |
| **Wildermyth** (already in STORY.md's lineage) | Authored events + sim-cast actors is the workable synthesis | Roles (§4) are exactly this: the text is written, the cast is queried |

The one-line synthesis: **CK gives us the skeleton (stages, roles,
condition rows, fragments, flips, keywords), the Witcher and BioWare
give us the spine's craft, Majora gives us the clock's meaning, Outer
Wilds gives us the journal's soul, and the sim gives every one of
them a live world to stand on.**

---

## 3 · The record shapes v2 (dimension 1)

### The position: the monotone quest

The derivation law says quest progress is a reading of facts. The
un-complete hazard says pure readings are dishonest (a fact erodes,
a step un-checks). STORY.md's answer — latch step done-ness — is
right, and we adopt it as the *whole* model:

> **Quest state is an append-only set of latches.** A stage is
> *reached* when its conditions pass while a parent stage is reached;
> the moment it's reached, `Story` seals `journal.<quest>.<stage>`
> with the day. Latches are never cleared, re-evaluated, or edited.
> There is no "current stage" variable — the frontier is derived
> (reached stages with no reached child). Failure, expiry, and every
> ending are terminal stages like any other. Nothing un-happens.

Why this is the right shape and not just a patch:

- **It IS the derivation law**, honestly applied: a latched
  observation *cannot* be re-derived after the underlying fact erodes
  (Memory v2 guarantees facts erode), so it is exactly the state the
  law permits storing.
- **Branching without a machine.** Two endings = two terminal stages
  whose `advance_when` differ. `excludes` between quests survives for
  cross-quest closure; within a quest, sibling terminal stages are
  naturally exclusive if their conditions are (the linter checks the
  common case: sibling terminals gated on the same sealed choice).
- **Determinism and catch-up come free.** Latching is driven by
  `WorldState.changed` (§5), which fires identically during live play
  and `advance_hours` replay. A quest can progress while you're away
  exactly where the world can move without you — and scenes still
  wait for the player (STORY canon).
- **The save story is nothing.** Latches are WorldState keys; they
  ride `snapshot()`/`restore()` untouched.

### The quest record

Design goal: **the empty-schema tax is zero.** "Fetch the pot" is
`id + title + tier + stages`, where each stage is journal text plus
one objective. Everything else — roles, scenes, hooks, deadline,
excludes — is optional and pay-as-you-go. The same shape scales to
"The Bank Gives Way" without changing kind.

```jsonc
// data/quests/bank_gives_way.json — the exemplar, re-authored in v2
{
  "format": 2,
  "id": "bank_gives_way",
  "title": "The Bank Gives Way",
  "tier": "story",                       // errand | story | arc
  "hook": "brook_bank_slumped",          // fact kind/id — rides the rumor system (unchanged)
  "start_if": { "any": [
      { "knows": ["player", "brook_bank_slumped"] },
      { "flag": "player.saw.brook_bank" } ] },
  "expire": { "window_days": 40, "to": "washed_away" },   // fail-forward target (§7)

  "roles": {                             // §4 — the cast, queried from the live world
    "keeper": { "kind": "npc", "is": "keeper" }           // pinned: authored cast is a role too
  },

  "stages": [
    { "id": "heard", "start": true,
      "journal": "Word at the fire: the storm took the brook bank, north of the pond. Something is showing in the cut.",
      "objectives": [
        { "id": "walk",
          "text": "Walk the brook north of the pond, to where the storm took the bank.",
          "done_if": { "flag": "player.saw.brook_bank" } } ] },

    { "id": "found", "advance_when": { "flag": "player.saw.brook_bank" },
      "journal": "In the fresh cut, older than the shrine: a carved shell. The Keeper would know it.",
      "objectives": [
        { "id": "carry",
          "text": "Bring what the water uncovered to the Keeper, at the shrine, toward dusk.",
          "done_if": { "flag": "scene.bank_reveal.played" } } ],
      "scenes": ["reveal"] },

    { "id": "returned", "terminal": true,
      "advance_when": { "flag": "choice.bank_marker.water" },
      "journal": "I gave the shell back to the water, where the first shrine stood. The Keeper watched me do it and said nothing for a long time.",
      "mint": { "kind": "marker_returned", "about": ["keeper", "player"], "magnitude": 0.6 } },

    { "id": "kept", "terminal": true,
      "advance_when": { "flag": "choice.bank_marker.shrine" },
      "journal": "The shell sits at the shrine now — the new one, the only one most people ever knew.",
      "mint": { "kind": "marker_kept", "about": ["keeper", "player"], "magnitude": 0.6 } },

    { "id": "washed_away", "terminal": true,
      "journal": "The rains came back before I did. The cut slumped shut over whatever it was. The brook keeps its own counsel now." }
  ],

  "scenes": [
    { "id": "reveal", "who": "$keeper", "where": "shrine",
      "hours": [18, 20], "priority": "high", "hold_days": 3,
      "dialogue": "bank_reveal" }        // §9 — the reveal lives in dialogue, where reveals live
  ],

  "hooks": "hooks/bank_gives_way.gd"     // §6 — optional; this quest may not even need it
}
```

And the floor of the schema, for contrast — a sim-latched errand
(U1's "The Dry Spell," rebuilt):

```jsonc
// data/quests/dry_spell.json — the smallest real quest
{
  "format": 2, "id": "dry_spell", "title": "The Dry Spell", "tier": "errand",
  "start_if": { "flag": "valley.parched" },
  "repeatable": { "cooldown_days": 30 },   // errands re-arm; stories never do (§7)
  "stages": [
    { "id": "open", "start": true,
      "journal": "The valley is parched. The pools are rings of cracked clay.",
      "objectives": [ { "id": "wait", "text": "The valley waits for the weather to turn.",
          "done_if": { "not_flag": "valley.parched" } } ] },
    { "id": "rains", "terminal": true, "advance_when": { "not_flag": "valley.parched" },
      "journal": "It rained. The pools remembered how to be pools." } ]
}
```

### Field semantics (the load-bearing ones)

- **`stages`** — a DAG, declared implicitly: a stage's parents are
  every earlier stage that isn't terminal, unless it names
  `"after": ["stage_id", ...]` explicitly (linear quests never write
  `after`; branchy ones do). `start: true` marks the root(s); a root
  is reached the moment `start_if` latches. **Reached is forever.**
- **`advance_when`** — the stage's reach condition (evaluated only
  while a parent is reached and the stage is not). A stage with
  objectives *and* no `advance_when` advances when all its
  non-optional objectives latch (the common case; "The Bank" spells
  them out only because its children branch on the sealed choice).
- **`objectives`** — display lines with their own `done_if`, each
  latched independently (`journal.<q>.<stage>.<obj>`). `optional:
  true` and `count: n` (progress against a numeric key) supported.
  In a no-marker game **objective text is the guidance**, so it
  carries geography (craft checklist rule 6 — unchanged).
- **`journal`** — memoir prose, written ONCE when the stage latches,
  with role bindings resolved at that moment (§8). Not re-rendered,
  not conditional. If a stage needs different prose per path, it is
  two stages.
- **`mint`** — the echo made declarative: a fact record minted when
  the stage latches (rides Memory v2's channels). The craft
  checklist's rule 5 becomes a lintable field: *every Story's
  terminal stages must mint.*
- **`required: true`** on a stage — an authored-spine invariant: the
  linter proves every path from root to every terminal passes through
  this stage (§10). The designer's "this beat can never be skipped,"
  checked at commit time, not discovered in a bug report.
- **`effects`** — the small closed effect set on stages (same shape
  dialogue uses, §9): `set` / `inc` / `give` / `take` / `mint` /
  `latch` (seal a choice key) / `world` (flip placement groups —
  below). Anything beyond these is a hook.
- **`repeatable`** — errand-tier only (linter-enforced). Each cycle's
  latches key as `journal.<id>.<cycle_day>.<stage>`; the journal
  shows the freshest cycle, old cycles fade into "Remembered."

Journal-voice note: `journal.<id>.started` from the retired
implementation survives conceptually as the root stage's latch — one
mechanism, not two.

### Threads — the authored spine (Pillar A's machinery)

A **thread** is an ordered storyline of quests. It needs almost no
new machinery — quests already gate on each other's latches — but it
needs *first-class shape* so the desk, the linter, and the journal
all see the line the designer drew:

```jsonc
// data/threads/keepers_year.json — an authored, progressing storyline
{
  "format": 2, "id": "keepers_year", "title": "The Keeper's Year",
  "spine": true,                       // this thread's guarantees are lint-enforced (below)
  "chapters": [
    { "quest": "bank_gives_way" },
    { "quest": "the_first_shrine",  "after": "bank_gives_way:*",         // any ending — chapters
      "gate":  { "since": ["journal.bank_gives_way", 14] } },            //   PACE, they don't rush
    { "quest": "what_the_water_keeps", "after": "the_first_shrine:told",  // a SPECIFIC ending —
      "gate":  { "season": "winter" } }                                   //   branches carry forward
  ]
}
```

- **`after: "quest:stage"`** compiles to `start_if` clauses on
  journal latches — sugar, not a second mechanism (`*` = any terminal
  of that quest; a named stage = that path specifically, which is how
  a chapter honors an earlier ending). The chapter's own `start_if`
  still applies on top — hooks stay diegetic even on the spine.
- **`gate`** is the pacing knob: deliberate quiet between chapters
  (`since`), seasonal setpieces (`season: winter` — the gate no other
  engine can write honestly, because our winter is real), sediment
  thresholds for Arcs (STORY.md's "months of warmth," unchanged).
  Gates *wait*; they never fail.
- **The journal renders a thread as one continuing story** — its
  chapters' memoir entries interleave under one heading. This is what
  "solid story lines that progress" *looks like* to the player: a
  long entry that keeps growing across seasons.
- **The spine-gating rule (how the pillars coexist, made precise):**
  on a `spine: true` thread, every quest's path-to-terminal may gate
  only on **player-reachable facts** (player actions, dialogue seals,
  scenes, elapsed time, items) or **recurrent sim states** (seasons,
  weather kinds, tides — states the sim guarantees return). One-shot
  sim events (a specific slump, a specific death) may *open* spine
  content or decorate it, but never stand as the only door on its
  path. The linter enforces the checkable part (a declared
  recurrent-key list; everything else on a spine path must be
  player-writable), review covers the rest. Off-spine content gates
  on anything — that's Pillar B's whole point.
- **Ordering guarantees are structural:** chapters cannot latch out
  of order (their roots gate on prior latches), `required` stages
  cannot be bypassed (linted), and latches never un-happen — so an
  authored storyline's progression is exactly as save-safe as the
  save itself.

### World flips (CK's enable parents) — progression you can walk on

The mechanism that makes a storyline VISIBLE: placed records gain an
optional **`group`** field (stable placement ids exist — the Strata
records-desk ask; groups name *sets* of them), and a stage effect
flips groups:

```jsonc
// on a placement row in data/cells/x_y.json:
{ "id": "pl_8f2c", "kit": "village/bridge_broken", "group": "brook_bridge.broken", ... }

// on a stage:
"effects": [ { "world": { "disable": ["brook_bridge.broken"],
                          "enable":  ["brook_bridge.rebuilt"] } } ]
```

- Group state lives at `world.group.<id>` in WorldState — saved,
  restored, caught-up, and (unlike CK's) **fingerprintable**. The
  streamer/CellRecords consults it when instancing placements; a
  flip while the cell is streamed swaps live (with whatever modest
  dust/sound the moment deserves — presentation, not state).
- Flips are **mutable world truth, not latches** (a later stage may
  flip a group back — the camp struck, the flood barrier removed) —
  but on spine threads the linter warns when a flip is contested by
  two quests (one group, one owner: the guardrail against two
  storylines fighting over the same bridge).
- Groups may also start disabled *authored-dark* (`"enabled": false`
  on the placement): the camp that doesn't exist until chapter two —
  CK's exact trick, and the cheap half of "setpiece staging."
- The scope law holds: flips **mutate existing content** (a group is
  authored both ways by human hands, placed in the Toolkit); this is
  not spawning parallel branches, it's the sanctioned mutation the
  Consequence Contract always promised (`RPG_WEIGHT`: "what's
  built/broken/tended").

---

## 4 · Roles (dimension 2) — CK's aliases, sim-native

A **role** is a named slot the engine fills from the live world when
the quest needs it. Roles are how one authored quest meets many
worlds — the reuse door for future games, the radiant door for
errands, and (new to us) the *sim* door: our queries run over live
simulation state, not spawn tables.

### The record shape (filling rules as data)

```jsonc
"roles": {
  "hauler": {
    "kind": "npc",                          // npc | wildlife | place | item
    "require": [                            // hard filters — condition vocabulary, $self-scoped
      { "eq": ["npc.$self.home_region", "$player_region"] } ],
    "prefer": [                             // ordered tie-breakers, first discriminating wins
      { "knows": ["$self", "$hook"] },
      { "opinion_band": ["$self", "warm"] } ],
    "fill": "on_start",                     // on_start (default) | on_stage:<id>
    "fallback": "hold"                      // hold (wait for a candidate) | abandon (quest never offers)
  },
  "keeper": { "kind": "npc", "is": "keeper" }   // pinned — authored cast declares itself the same way
}
```

- **Filling is a deterministic query.** Candidates = all records of
  `kind` passing `require`; ranked by `prefer` in order; ties broken
  by id sort. No RNG in the fill path — same world, same fill, every
  run (the soak can hold us to it).
- **Fills are latched**, like everything else:
  `journal.<q>.role.hauler = "wanderer"`, sealed with the day. A role
  never re-rolls; if the world later invalidates a binding (the NPC
  dies through an authored channel), that is *story*, and the quest
  handles it as a stage or expires — never a silent recast. (CK's
  worst bugs were aliases re-filling under a live quest; we make it
  structurally impossible.)
- **`$role` substitution** works everywhere strings meet the system:
  condition keys (`npc.$hauler.met`), scene `who`, dialogue speakers
  and lines, journal prose (resolved at latch time, so the memoir
  names the person who was actually there).
- **`kind: place`** queries place records (§11 — the L9 dependency)
  by tags/nearness: "a shaded pool within the player's region."
  `kind: wildlife` queries herds ("a hound pack whose count fell this
  season" — the pack that survived the storm). These are the queries
  no other engine could ask, because nothing persists a live world
  the way ours does.
- **The keyword law (CK's keywords, adopted as an axis):** every
  record kind — cards, places, NPCs, items, fact kinds, quests —
  carries the same optional **`tags: []`** array, one spelling, one
  meaning, everywhere (Strata's card `tags` already exist; this
  extends the axis game-wide). Role queries test tags, never
  identities: `{"tagged": ["$self", "shrine"]}`, `{"tagged":
  ["$self", "elder"]}` — which is what lets ONE authored quest meet
  many worlds, and what makes filling rules *readable* ("any placed
  thing tagged shrine within the region"). Identity (`is:`) remains
  for pinned authored cast; everything radiant goes through tags.
- **Built-in bindings**, always present: `$player`, `$hook` (the fact
  that started the quest — errands love this: the *specific* storm,
  the *specific* slump), `$player_region`.
- **The honest cost:** the query vocabulary is small on purpose
  (require/prefer over the condition language + `near`/`is`/`tags`).
  If a fill needs cleverness the data can't say, `on_fill` (§6) gets
  the candidate list and may choose — code, in the game repo, named
  from the record. The machinery stays data; the wit stays authored.

★ **How radiant may errands get?** Roles make "carry water to
$hauler" a template that could fire for anyone. The IDEAS guard-rail
(cap active seeds per domain) and the tier budget already fence this;
the taste call — how *often* the valley is allowed to ask something
of you, and whether role-filled errand text ever risks feeling
mail-merged — is Nicco's, at the table, with the first three errands
playing. (Radiant is a *door* in this design, not a commitment.)

---

## 5 · Conditions over sim truth (dimension 3)

### The mirror law (the one rule that makes everything else cheap)

> **Conditions read WorldState keys and nothing else. A sim truth a
> quest may test MUST be mirrored into WorldState by its owning
> system.** No condition evaluator ever calls `Hydrology.flow_norm()`
> — Hydrology mirrors `water.<id>.flow` (it already does), and the
> condition reads the key.

This is already the codebase's instinct (GameClock mirrors `time.day`
/ `time.season`; Weather mirrors `weather.state`; Climate mirrors
`climate.wetness`; FloraLife mints `valley.parched`) — promoted to
law. What it buys, all at once: one evaluator with no autoload
coupling · mechanical key extraction (the index below) · catch-up
correctness (mirrors update through `hour_tick`, so conditions see
replayed time in order) · headless testability (the harness fakes
sims by writing keys) · and the Strata schema story (key namespaces
are enumerable). **A quest that opens when the river runs dry** is
now one line — `{ "lte": ["water.brook.flow", 0.1] }` — and it costs
Hydrology nothing it doesn't already pay.

### The vocabulary — closed, complete, published

Composition: `all: [...]` · `any: [...]` · `not: {...}` (a bare
dictionary of predicates still ANDs, so v1 records read unchanged).

| predicate | reads (for the index) | notes |
|---|---|---|
| `flag` / `not_flag` | the key | v1, unchanged |
| `eq` / `gte` / `lte` `[key, v]` | the key | v1's `gte` + STORY's `lt`/`eq`, symmetrized |
| `item` `[id, n]` | `player.inventory` | v1, unchanged (Items mirrors its counts) |
| `item_tag` `[tag, n]` | `player.inventory` | the keyword law in the pack: "any 2 things tagged food" — identity-free, like every radiant gate |
| `season` `"summer"` or `[...]` | `time.season` | sugar over `eq` |
| `time_between` `[18, 20]` | `time.hour` | solar hours; GameClock adds an hourly int mirror so evaluation is hourly, not per-frame |
| `since` `[key_or_stage, days]` | the key + `time.day` | days since a latch; latches store their day (§3), so this is a read, not a timer |
| `knows` `[who, fact]` | `npc.<who>.knows.<fact>` | Memory v2 (S1); `player` allowed as who |
| `told` `[a, b, fact]` | provenance keys | reserved until S1 lands (U2) |
| `opinion_band` `[npc, band]` | sediment/fact keys | reserved until S2; a *derived* reading, per Memory v2 |
| `weather` `"storm"` or `[...]` | `weather.state` | sugar over `eq` |
| `custom` `["name", ...args]` | **declared**: `watch: [keys]` required beside it | the escape hatch — a named hook predicate (§6); the linter refuses a `custom` without `watch` |

That is the whole language, forever. Sim vocabulary grows by *adding
mirrors* (e.g. Weather should mirror `weather.storminess`; wildlife
should mirror `wildlife.<species>.count` when population records land)
— never by adding evaluator branches beyond this table. **No
expressions, no arithmetic, no string ops.** The moment a quest needs
more, that's either a missing mirror (a sim change) or wit (a hook).

Two classifications ride the vocabulary, both data:

- **Tags are record data, not world state** — conditions never test
  them directly; role queries and `item_tag` do, and a bound role
  *is* the tag test's result, latched. (Keeps the evaluator pure over
  keys; keeps keywords where they belong, on records.)
- **The recurrent-key list** (`data/story/recurrent.json`): the keys
  whose states the sim guarantees return — `time.season`,
  `time.hour`, `weather.state`, `climate.snow`… Owned by the game,
  read by the spine lint (§3): a spine path may gate on these or on
  player-writable keys, nothing else. One small file is the whole
  enforcement surface of "authored storylines never strand on the
  sim."

### Evaluation: event-driven through the index, never polled

`Story` builds, at load: `key → [ (quest, stage/objective/role) ]`
by walking every condition mechanically (closed language = total
extraction; `custom` contributes its `watch` list; `$role` keys index
after fill, on the latch of the binding). Then:

- `WorldState.changed(key)` → re-evaluate only the entries under that
  key → latch what passes. This is SIM_ROADMAP P4's seed index, built
  once for all three tiers.
- Time conditions ride the same path: `time.hour` changes hourly,
  `time.day` daily — deadlines and windows re-evaluate exactly when
  time moves, including through `advance_hours` catch-up (each
  chunk's mirrors fire `changed` in order; a quest that should have
  latched on day 3 of your week away latches during replay, stamped
  day 3's latch-day... stamped with the replayed `time.day`, which is
  correct — the memoir is honest about *when*).
- Latch-once semantics make re-entrancy trivial: an already-latched
  entry is dropped from the index.
- Cost honesty: 60 stories × ~5 stages × small conditions ≈ hundreds
  of index entries; a `changed` touch re-evaluates a handful of
  dictionaries. This is nothing, and it stays nothing at city scale
  because the index only grows with *authored content*, not world
  size.

---

## 6 · The hooks door (dimension 4) — first-class, load-bearing

Nicco's ask, made contract. The pattern is CK's Papyrus fragments —
tiny named code attached to quest lifecycle points — but with the
discipline our determinism laws demand.

### The shape

A quest record may name one hooks script, living in the **game repo**
(never in Strata, never in data): `"hooks": "hooks/bank_gives_way.gd"`
resolved under `game/story/hooks/`, or the bound form (below). The
script extends the engine's base:

```gdscript
class_name QuestHooks
## The Campfire — base class for per-quest script fragments. Every
## entry point is optional. Hooks receive a QuestRun handle (q) and
## touch the world ONLY through it and WorldState — never scene nodes
## directly (the guardrail that keeps quests headless-testable).

func on_start(q: QuestRun) -> void: pass          # after roles fill, before the root stage latches
func on_fill(q: QuestRun, role: String, candidates: Array[String]) -> String:
    return ""                                     # return an id to override the data-ranked fill; "" defers
func on_stage(q: QuestRun, stage: String) -> void: pass       # the CK fragment — a stage just latched
func on_objective(q: QuestRun, stage: String, obj: String) -> void: pass
func on_expire(q: QuestRun) -> void: pass         # deadline passed; runs before the expire stage latches
func on_resolve(q: QuestRun, outcome: String) -> void: pass   # a terminal stage latched
func condition(q: QuestRun, name: String, args: Array) -> bool:
    return false                                  # answers {"custom": [name, ...]} rows
func custom_keys(name: String) -> Array[String]:
    return []                                     # index keys for a custom predicate (records may also declare watch:)
func properties() -> Dictionary:
    return {}                                     # typed needs the RECORD must bind (CK property binding)
```

### Property binding — data does the pointing (CK's best fragment trick)

A hook never hardcodes a target. It *declares* typed needs; the quest
record *binds* them; `Story` injects before any entry point runs:

```gdscript
# hooks/flood_gate.gd — reusable: knows HOW, never WHAT
func properties() -> Dictionary:
    return { "gate_group": TYPE_STRING,       # a placement group to flip
             "river": TYPE_STRING,            # which river's flow to watch
             "threshold": TYPE_FLOAT }
```

```jsonc
// any quest that wants a flood gate:
"hooks": { "script": "hooks/flood_gate.gd",
           "bind": { "gate_group": "ford.closed", "river": "brook", "threshold": 0.8 } }
```

Bound values arrive as `q.prop("river")`. The linter refuses a record
whose `bind` doesn't satisfy `properties()` (missing, extra, or
mistyped), so the wiring is checked at commit, not discovered at
runtime. The payoff is CK's exactly: **one fragment, many quests** —
flood-gate logic written once, pointed at three fords by three
records — and future games reuse valley's hook library by rebinding
rather than rewriting. (Strata renders `bind` as typed fields from
the schema verb — a group picker, a number stepper — still never
touching the code. §12.)

### What `QuestRun` gives a hook (the whole surface)

`q.id` · `q.prop(name)` (the record-bound properties, above) ·
`q.role(name) -> String` (the latched binding) ·
`q.reached(stage) -> bool` / `q.reached_day(stage) -> int` ·
`q.latch(stage)` (advance by fiat — the imperative door for what
conditions can't say) · `q.seal(choice_key, value)` (the R2 choice
seal: write + immediate save) · `q.mint(kind, data)` (fact channels)
· `q.request_scene(id)` · `q.set(key, v)` / `q.get(key, d)`
(WorldState, unrestricted read, write logged under guardrails) ·
`q.give(item, n)` / `q.take(item, n)` · `q.roll(tag) -> float`
(**the only sanctioned randomness**: seeded from `world.seed + quest
id + tag + time.day`, so a hook's dice are replay-stable) ·
`q.actor(role) -> Node3D?` (the embodied body **or null** — data-tier
agents have no node; presentation flourishes must null-check; this is
the two-tier law crossing the hook boundary).

### The laws that keep the door safe

1. **Hooks are pure over (WorldState, Items, q).** No scene-tree
   spelunking, no engine singletons beyond the sanctioned reads, no
   `randf()` (use `q.roll`), no wall clock (use `time.*` keys). The
   review checklist enforces it; the harness (§10) makes violations
   *visible* — a hook that needs a body crashes headless, which is
   the point.
2. **Hooks run identically in live play, catch-up, harness, and
   soak.** They're called from latch processing, which is
   `changed`-driven, which is deterministic. A hook that breaks the
   soak fingerprint is a bug, full stop.
3. **Strata shows hook names, never edits code** (PLAN_CREATION_
   LIBRARY §4b fence — unchanged). The record names the entry point;
   the game owns the text.
4. **The hook is the LAST resort in authoring order:** mirror → 
   condition → effect → hook. The linter counts hooks per quest in
   its report — a quest that's mostly hooks is a design smell we want
   visible at review.

### Why this door makes future games unique without forks

The Story manager, the condition language, roles, scenes, the memoir
— all generic, all engine (module) code. What a *game* ships:
its record content, its **mirrors** (what truths its sims publish),
its **fact kinds**, and its **hooks**. A future game whose quests
feel nothing like valley's — harder, stranger, chattier — is the same
machinery with different vocabulary and different fragments. The
system is the grammar; hooks are the accent.

---

## 7 · Time, deadlines, failure (dimension 5)

The 1:1 clock is the most valuable and most dangerous thing we own
(Majora's lesson: deadlines create care; homework's lesson: deadlines
create guilt). The stance, extending STORY.md's "rare and warm":

- **Mechanism:** `expire: { window_days: N | day: D | season_end:
  true, to: "<terminal stage>" }`. When the boundary passes
  (`time.day` index entry), `on_expire` runs, then the target stage
  latches with its own journal prose. **There is no failed state,
  only a different ending** — the record shape physically cannot
  express "FAILED" because expiry is just a stage.
- **Journal honesty:** expiry prose is world-truth, warm, and
  specific ("The rains came back before I did"), written like every
  other memoir entry. ★ The first deadline quest gets Nicco's
  tone-test before a second is authored (STORY ★8, restated — now
  testable in the harness before it's testable in the heart).
- **Windows, not walls, wherever possible:** prefer `open_if` on a
  stage (season/hours gates that *wait*) over `expire` (gates that
  *close*). A winter-only stage isn't a deadline; it's a season. The
  journal may say so ("nothing to do until the snow").
- **Missing a quest entirely is sanctioned and silent.** A hook fact
  erodes unheard, a slumped bank re-heals through the sim, and the
  quest never offers. No residue, no regret UI. Most players never
  see most quests — that is the February/July law applied to story,
  and it's what makes the ones you *do* catch feel found rather than
  served.
- **Expiry composes with threads as fail-forward at storyline
  scale:** an expiry terminal is still a terminal, so a chapter that
  expired still *finishes* — and the next chapter's `after:
  "quest:*"` (or a branch keyed to the expiry stage specifically)
  carries the storyline on through the miss. The Witcher writes this
  by hand per branch; here it's the graph's default. On spine
  threads, prefer gates (which wait) over expiry (which closes) —
  and when a spine chapter does expire, the no-wedge law requires
  the thread to continue through it.
- **Retry stance:** Stories never re-arm (the world moved on; if
  return is deserved, a *different* quest opens later conditioned on
  the expiry stage's latch or minted fact — the amends pattern, and
  it's `since:` + one record, no machinery). Errands re-arm via
  `repeatable.cooldown_days`. Arcs neither expire nor repeat; their
  chapters gate on elapsed time and sediment (STORY.md, unchanged).
- **Scenes already wait for the player** (STORY canon, attempt-count
  hold clock) — deadlines and scene holds compose: the hold clock is
  attempts, the expiry clock is days, and the actor's forward-failure
  (the storm that stopped her) remains the only way the world takes a
  scene from you.

---

## 8 · The player's experience (dimension 6) — ★ heavy

### The journal is a memoir

One screen (J), two truths:

- **Threads** (active quests): the latched prose so far, in order,
  each entry stamped with its day and season ("Day 112, autumn"),
  followed by the current objectives — text only, geography embedded,
  no distances, no arrows, no pins. The memoir *reads downward like a
  diary* because it is one: entries were written at latch time with
  the real bindings and never touched again.
- **Remembered** (resolved threads, all endings equal — kept, 
  returned, and washed-away sit in the same list): the finished
  entries. Over a long game this section becomes the player's
  autobiography — SIM_ROADMAP's "the journal grows into a memoir,"
  now structural rather than aspirational.

★ **Journal voice** — first-person past tense is proposed throughout
(the exemplars above are auditions). This is a writing-desk decision
of Nicco's, made once, before quest #2: the memoir voice IS the
player-character's voice, which brushes against the open "Wanderer's
identity" canon question.

### Discovery — how quests announce themselves without a single "!"

Every `start_if` source is diegetic, and the schema already knows
them all:

| channel | condition shape | who builds it |
|---|---|---|
| **Overheard** | `knows: ["player", fact]` | Memory v2 (S1) — barks/dialogue teach facts |
| **Seen** | `flag: player.saw.<place>` | sight/enter triggers on place records (§11) |
| **Found** | `item:` or a pickup effect | Items — already works |
| **Weather-revealed** | sim mirrors (`water.*.flow`, `land_changed` facts) | the sim — already speaks |
| **Given** | letters/objects with effects | Items + dialogue effects |

When a root stage latches, the HUD gives one quiet line (the existing
`notify` pattern — "journal — <first words of the entry>") and the
journal gains its entry. ★ **Loudness**: whether stage-latch
notifications appear at all mid-quest, or only the journal accretes
silently and the player checks it like a diary, is a taste call —
propose: root latch and terminal latch notify; middle stages are
silent (the diary fills; the toast doesn't nag).

### Guidance without GPS-brain

Three layers, no compass (the Morrowind ★ in IDEAS is hereby forced:
this design *requires* deciding it, and assumes **no markers**):

1. **Objective text carries the route** (craft rule 6) — "past the
   twin palms, where the bank gave way." ★ The direction-giving
   vocabulary (landmark canon, cardinal style) must be settled before
   quest #3 (STORY ★4, restated with a deadline the Q-ladder
   enforces: it gates Q7).
2. **People are the fast-travel of information:** asking an NPC about
   an active thread is authored dialogue conditioned on quest latches
   (`{"flag": "journal.bank_gives_way.heard"}`) — re-telling
   directions, adding local color. A pattern, not machinery: costs
   one dialogue node per quest per knowing-NPC.
3. **The world cooperates because the quests are OF it:** hooks are
   real places the sim actually changed, so following the world
   (walk the washes after the storm) IS following the quest.

---

## 9 · Dialogue and scenes (dimension 7)

### Does valley want branching dialogue? (★)

Proposal: **yes, shallow — the retired engine's shape was right.**
Nodes with speaker/text/effects/choices, choices with conditions,
returning to trunk quickly; the CHOICE writes state (a seal, a fact),
the TREE stays shallow (the scope law applied to conversation:
consequences mutate the world, not the transcript). No VO keeps every
line cheap to write and re-write. ★ Nicco blesses the
shallow-branch stance (it constrains his writing desk more than any
code).

The record shape (v1's, restored and extended — this is what Strata's
branch view edits):

```jsonc
// data/dialogue/bank_reveal.json
{
  "id": "bank_reveal",
  "start": [ { "if": { "flag": "journal.bank_gives_way.found" }, "node": "reveal" } ],
  "nodes": {
    "reveal": {
      "speaker": "$keeper",
      "text": "…where did you find this. No — I know where. Show me your hands.",
      "choices": [
        { "text": "Give it to her.",            "next": "weighs" },
        { "text": "Hold it a moment longer.",   "next": "weighs" } ] },
    "weighs": {
      "speaker": "$keeper",
      "text": "The shrine you know is not the first. One stood by the water, before the brook moved.",
      "choices": [
        { "text": "It should go back to the water.",
          "effects": [ { "seal": ["choice.bank_marker", "water"] } ], "next": "end_water" },
        { "text": "It belongs at the shrine, with her.",
          "effects": [ { "seal": ["choice.bank_marker", "shrine"] } ], "next": "end_shrine" } ] }
  }
}
```

Extensions over v1: `$role` in speakers and text · effects grow
`seal` (R2's choice seal: write + immediate save), `mint`, `give`/
`take`, and `hook` (call a named fragment) beside v1's `set`/`inc` ·
conditions are the §5 language (one vocabulary everywhere — dialogue
`if`, quest `advance_when`, role `require` are the same rows, which
is also why Strata only needs ONE condition-row editor).

### Scenes — the contract gets its machinery

STORY.md's contract stands whole (request not command · hold_days
count attempts · waits for the player · fail-forward on world
interference only · never teleport, never kill canon). What the
engine must add (the bleed, priced in §11):

- **`AgentSim.push_activity(activity, source)`** — scene staging
  injects a high-priority, hour-gated activity ("be at the shrine,
  18–20") into the agent's set; utility scoring does the rest (the
  actor *walks*, weather delays her, you can follow her — for free,
  because it's the same locomotion as her life). An arrival signal
  (or a mirrored `npc.<id>.at` key — prefer the mirror; scenes then
  ride the same index as everything else) tells `Story` the actor
  is placed.
- **The assembler** (in `Story`): when a scene's stage is the
  frontier, each day within `hours`, push the activity; if actor
  arrives AND `$player` is within earshot → run the scene (start
  `dialogue`, set `scene.<id>.played`); if the player never showed,
  count an attempt; attempts exceeded → this was never the player's
  failure, keep trying (canon) — only WORLD interference (the actor
  physically couldn't come: storm gate, authored injury channel)
  burns hold days toward fail-forward.
- **Initiation ★:** when both are present, does the actor approach
  and address you (a scene *takes* you, warm but seizing) or beckon
  and wait for the interact prompt (you *choose* the scene)? Propose
  beckon-and-wait as default with `"initiate": true` for the rare
  scene that should walk up to you — but this is tone, table, Nicco.
- **v1 fence:** one actor + the player. Multi-actor choreography
  (two NPCs staged into one clearing) is a later rung and probably a
  later game; the assembler's shape doesn't preclude it, and we don't
  build it now.

---

## 10 · Robustness (dimension 8) — the ask made real

### Persistence

All quest state = WorldState keys under `journal.*` (stage/objective
latches with days, role bindings, cycle keys) and `choice.*` (seals).
Saved and restored verbatim by the existing snapshot — **zero new
save code**. `Story` joins `world_state_reader`: `load_state()`
rebuilds the index and derived frontier from latches (boot-before-
restore is already solved by that group's contract).

### Versioning quest records against live saves

- **The id law** (the slot-identity law, arrived at the quest desk):
  `quest.id`, `stage.id`, `objective.id`, `role` names are immutable
  once shipped — renaming is a new thing. Latches reference ids;
  saves survive any update that respects the law.
- **Additive is free:** new stages, objectives, quests — old saves
  simply haven't latched them.
- **Removal is tolerated, never destructive:** latches for stages a
  newer record no longer declares are *kept verbatim* (the memoir
  doesn't tear out pages) and logged once at load. The journal
  renders unknown latches from their stored prose — which works
  because prose is stored IN the latch (the memoir design pays for
  itself here: the save carries its own text history).
- `format: 2` on every record; a future format bump gets a migration
  entry in the same registry save-v2 proposes (RPG_WEIGHT), not ad-hoc
  code.

### The harness — headless quests, tests as data

`tests/quests/*.json`, run by `tests/quest_harness.gd` inside
`./scripts/test.sh`:

```jsonc
// tests/quests/bank_gives_way.test.json
{ "quest": "bank_gives_way",
  "world": { "world.seed": 123456789, "npc.keeper.home_region": "valley" },
  "script": [
    { "set":  { "npc.player.knows.brook_bank_slumped": true } },
    { "expect_reached": "heard" },
    { "set":  { "player.saw.brook_bank": true } },
    { "expect_reached": "found" },
    { "advance_hours": 72 },
    { "expect_scene_requested": "reveal" },
    { "set":  { "scene.bank_reveal.played": true, "choice.bank_marker": "water" } },
    { "expect_reached": "returned" },
    { "expect_minted": "marker_returned" },
    { "expect_not_reached": ["kept", "washed_away"] } ] }
```

The harness boots the minimal world (the soak's pattern: fixed seed,
autoloads, no player body), drives WorldState + `advance_hours`,
asserts latch order, scene requests, mints, and role fills. **Every
shipped quest ships its test** (the guardians-budget discipline
applied to story: ~30–60 quests = ~30–60 test records, each minutes
to write because they're data). Hooks run inside the harness — which
is the enforcement mechanism for the §6 purity laws. A
`quest_test <id>` link verb exposes the same run to Strata's desk
(the game remains the only interpreter).

### The linter — schema truths `Records.validate` can't see

In `test.sh`, over `data/quests/` + `data/dialogue/` +
`data/threads/`: stage graph rooted/acyclic/reachable · every
non-terminal stage has a way forward (≥1 child edge or an `expire`) ·
**`required` stages lie on every root→terminal path** (the skip-proof)
· terminals have journal prose · Stories' terminals `mint` (craft
rule 5, enforced) · every condition parses against the closed table ·
every `custom` has `watch` · hook `bind` satisfies the script's
`properties()` · `$role` references declared roles · `scenes.where` /
`dialogue` / `hooks` / thread `after` targets exist · **spine paths
gate only on player-writable or recurrent keys** (§3/§5) · world-flip
groups have one owning quest per direction (contested-flip warning) ·
`repeatable` only on errands · sibling terminals' conditions disjoint
on the same sealed key (best-effort).

### Authored-arc invariants — the no-wedge law

Pillar A's specific promise: **a player cannot drive a storyline into
an unfinishable state.** Stated as an invariant: *from every
reachable latch-set, at least one terminal stage of every started
spine quest remains reachable.* Enforced in three layers, because no
single layer can carry it:

1. **Structure (linter):** no dead-end stages; windowed content
   carries `expire`; required-stage paths proven; spine gates
   restricted to player-writable + recurrent keys — so time and
   weather can never permanently close a spine door, only delay it.
2. **Semantics (design rules, review-enforced):** quest-critical
   items are undroppable or re-obtainable (the classic wedge — sold
   the MacGuffin — is ruled out by fiat); canon actors are already
   sim-unkillable (F1.5 rule 6); a sealed choice must lead *into* a
   branch, never off the graph.
3. **Playthroughs (harness):** every shipped Story and every thread
   ships **one full-arc test per ending** — headless, driving the
   real machinery root-to-terminal — plus adversarial scripts where
   they earn their keep (do the acts out of order, expire the
   deadline mid-scene, hand over the item early). A storyline's
   finishability is a *regression test*, rerun on every commit
   forever. This is what "solid story lines that progress" costs and
   what it buys: the confidence to author act three knowing act one
   cannot silently break beneath it.

### The soak stance (the position, taken)

**Add the entire `journal.*` and `choice.*` namespaces to the soak
fingerprint.** Rationale: the soak is playerless, so (a) Stories and
Arcs must latch *nothing* — any latch in soak is a leak of
player-gated logic into sim-driven paths, caught immediately; (b)
sim-born errands (dry spell) MAY latch, and must latch *identically*
across both runs — errand determinism asserted for free, forever.
Quest state stays out of the hand-picked *sim* digest keys (it isn't
sim state), but as a fingerprinted namespace it rides the same
apparatus. The snapshot-size budget already covers its save weight.

---

## 11 · The engine-bleed ledger (dimension 9)

Every capability this design needs that doesn't exist today, priced
under the house laws. **Fork patches required: zero** — every row is
an autoload, a module change to an existing script, records, or UI.
(Verified against the tree: nothing below touches engine source;
the deepest reach is `agent_sim.gd`, our own class.)

| # | capability | what it is | size | law posture |
|---|---|---|---|---|
| B1 | **`Story` autoload** | the manager: record loading, condition index, latching, memoir writes, role fills, scene assembler, hook dispatch | M–L (built up the Q ladder, never all at once) | new autoload in the Campfire; Toolkit panel + `summary()` from day one (F1.5) |
| B2 | **Conditions v2** | composition + new predicates + mechanical key extraction (`keys_of(condition)`) | S | extends `game/state/conditions.gd`; stays closed |
| B3 | **Event channels / fact minting** | STORY.md S1: `data/facts/` kinds, mint API, the `world.events` log (P4) | M | prerequisite for hooks-as-facts + `knows:`; owned by Memory v2's ladder, not this doc — quests consume it |
| B4 | **`AgentSim.push_activity`** + arrival mirror (`npc.<id>.at`) | scene staging's injection door | S | module change to `agent_sim.gd`; wildlife unaffected (empty pushed set) |
| B5 | **NPCs on AgentSim** | the retired NPC layer rebuilt (body + dialogue trigger + needs record) | M | already the M4 track; quests *depend on*, don't own it |
| B6 | **Dialogue engine restored + extended** | v1 engine from `1390574^` + `$role`, `seal`/`mint`/`hook` effects, v2 conditions | M | autoload; records-native (Strata branch view reads the same files) |
| B7 | **Place records** | `data/places/`: named markers/volumes over the cell grid | S | already promised to Strata (L9); roles/scenes/`saw` all consume it |
| B8 | **Sight/enter triggers** | place-record volumes that set `player.saw.<id>` / `player.entered.<id>` | S | rides B7; the cheap half of P3 perception (the full attention model is NOT needed for quests) |
| B9 | **Mirror additions** | `time.hour` (GameClock), `weather.storminess`, `wildlife.<sp>.count` (when populations land) | XS each | the mirror law's ongoing tax — one line per truth |
| B10 | **Journal UI (memoir screen)** | threads + Remembered, prose-first | M | HUD/UI; no marker plumbing to build because there are no markers |
| B11 | **Quest harness + linter** | §10, in `test.sh` | S–M | tests-as-data; the robustness spine — build SECOND (Q2), not last |
| B12 | **Link verbs** | `records schema` (rung 3) · `validate <kind>` (rung 2) · `quest_test <id>` · a dev `state set <key> <value>` verb for desk-driven trial | S | strata_link additions, debug-only; `state set` is dev-gated like `time`/`weather` |
| B13 | **Soak additions** | `journal.*`/`choice.*` in the fingerprint | XS | one function edit in `tests/soak.gd` |
| B14 | **World groups (enable parents)** | placement rows gain `group` + `enabled`; CellRecords/streamer consult `world.group.<id>` when instancing; the `world` stage effect | S–M | module changes to `cell_records.gd`/streamer; rides the stable-placement-ids quick win already promised to Strata |
| B15 | **The tags axis** | `tags: []` accepted on every record kind (places, NPCs, items, fact kinds, quests — cards already have it); `Items.count_tag()` | XS–S | one optional field per validate table; no central registry (tags live on records, the no-database law) |

Not needed (called out because the survey tempts them): a general
event *bus* beyond `WorldState.changed` + the P4 event log (the
changed signal already IS the bus for everything mirrored) · P3's
full perception stack · navmesh beyond what M4 already requires ·
any save-system change.

**Adjacent, noted, not designed here** (CK ideas that belong to other
docs but that quests will eventually target): **AI packages** —
schedules/activities as standalone records rather than inline arrays
(wildlife's `activities` already have the shape; a `data/activities/`
promotion is an Understory decision), and **idle/furniture markers**
— interaction points as placeable cards (lean-here, work-here,
sit-here), which scenes would then target by tag ("meet the elder
*where she works* at dusk" = a marker query, not a coordinate). Both
make quest staging richer and neither is on the Q ladder.

---

## 12 · The Strata window, informed back (dimension 10)

What these shapes mean for PLAN_CREATION_LIBRARY's L10 visual quest
window (Strata builds ON this; nothing here obligates Strata to build
it all at once):

- **The stage-flow view renders the DAG of §3**: nodes = stages
  (title, journal prose preview, terminal badge, `mint` badge,
  `required` badge, world-flip badge); edges = `after`/implicit
  order, labeled with `advance_when` summaries; roots and terminals
  visually distinct. Because quests are monotone, the view is a true
  DAG — no cycles, no state-machine spaghetti to lay out, ever.
  Expiry renders as a dashed edge from the whole quest frame to its
  `to` stage.
- **The thread view is the zoom-out** (Pillar A at the desk): chapters
  as a lane of quest cards joined by `after` edges with their pacing
  `gate`s on the joints — the storyline's act structure, visible and
  editable as data. Spine threads show the lint verdict (skip-proof,
  no-wedge, recurrent-gates) as lights on the frame.
- **World flips get a group picker** (enable-parents UI): the `world`
  effect edits as two tag-style fields listing placement groups (the
  game's `records schema` reply enumerates groups from placement
  data); clicking through opens the placements. Hook `bind` fields
  render as typed editors from `properties()` via the same schema
  reply — a group picker, a record picker, a stepper — code untouched.
- **Condition rows are the §5 table, verbatim.** The `records schema`
  verb reports: the predicate list (name, arity, arg types), known
  key *namespaces* (`time.*`, `weather.*`, `water.<id>.*`,
  `journal.*`, …) for autocomplete, enum values (seasons, weather
  kinds, opinion bands), and which predicates are reserved-not-yet-
  live (`told`, `opinion_band`) so the desk can gray them. Rows get
  the validate light from the game's `validate` verb — Strata never
  evaluates, exactly as fenced.
- **Roles get a small form** (kind / is / require / prefer / fill /
  fallback) — require/prefer reuse the same condition-row editor.
  One editor, three homes (conditions, dialogue `if`s, role rules) —
  that reuse is a gift of the one-vocabulary law.
- **Scenes are cards** cross-linking `where` → place record and
  `dialogue` → the branch view (the §4b click-through, now with real
  targets).
- **The dialogue branch view edits §9's shape** — nodes/choices/
  effects; `$role` chips resolve against the quest's declared roles.
- **Hooks appear as names with lifecycle badges** (`on_stage:
  found`), read-only, jump-to-file as a nicety on the game checkout.
  The window shows *that* wit exists, never the wit itself.
- **The test button:** `quest_test <id>` runs the game's own harness
  over the link and streams the latch trace back — the desk gets
  play-adjacent feedback with zero Strata-side interpretation. This
  is the L10 acceptance row made mechanical ("'The Bank Gives Way' is
  authored at the desk and the game runs it").
- **Journal preview** renders stage prose with binding placeholders
  styled as chips — Strata shows the *template*; only the game ever
  knows who `$keeper` turned out to be.

---

## 13 · The milestone ladder

Each rung agent-sized (S ≤ 2 days, M ≈ a week), ships alone,
`test.sh` green; sim-touching rungs run the soak. Q1 is deliberately
the smallest quest through the REAL machinery — no scaffolding that
gets thrown away.

| # | rung | size | done means |
|---|---|---|---|
| **Q1** | **The monotone core**: Conditions v2 (compose + eq/lte/season/time_between/since + `keys_of`) · `Story` autoload v0 (load, index, latch, memoir keys, HUD notify) · journal record format 2 · "The Dry Spell" re-authored as the first v2 record · minimal J screen (threads + prose) | M | the dry spell latches open and closed through real weather, its two entries read in the journal, `test.sh` green |
| **Q2** | **The robustness spine**: quest harness (tests-as-data) + linter in `test.sh` · `journal.*`/`choice.*` into the soak fingerprint · the dry spell's test record | S–M | a deliberate `un-complete` regression fails the harness; soak twice-identical with errands latching |
| **Q3** | **The hooks door**: `QuestHooks` base + `QuestRun` + lifecycle dispatch + `custom`/`watch` predicates + `q.roll` · one hook-flavored errand proving on_stage/on_resolve/condition | M | a custom predicate drives a latch headless; a hook violating purity fails in harness, visibly |
| **Q4** | **Roles v1**: fill queries (require/prefer/is/near, deterministic ranking) · latched bindings · `$role` substitution in keys/prose · `on_fill` override | M | a role-filled errand names a different NPC in a different world state, deterministically, asserted in harness |
| **Q5** | **Dialogue restored**: v1 engine from `1390574^` + v2 conditions + `seal`/`mint`/`hook`/`$role` extensions + its linter rows | M | a conversation seals a choice that latches a stage; branch-shallow exemplar committed |
| **Q6** | **Scenes v1**: `push_activity` + `npc.<id>.at` mirror + the assembler (attempt clock, earshot, fail-forward) — gated on an NPC standing on AgentSim (M4 track, B5) | M | the Keeper walks to the shrine at dusk and waits; the harness drives a scene to played and to forward-failure |
| **Q7** | **"The Bank Gives Way" end-to-end**: fact hook (needs S1/B3), scene, sealed choice, two endings, echo mints, its test — **gated on ★ direction vocabulary + ★ journal voice** | M | the exemplar Story runs live and headless; both endings reachable in harness; the echo fact exists |
| **Q8** | **Deadlines**: `expire` machinery + `on_expire` + the first deadline quest — **gated on ★ tone-test at the table** | S | expiry latches its terminal stage during `advance_hours` catch-up in harness; the prose passes the kitchen table |
| **Q9** | **The desk verbs**: `records schema` · `validate` · `quest_test` · dev `state set` — unblocks Strata L10 | S–M | Strata's window (their build) renders the schema and runs a test over the link |
| **Q10** | **The spine set**: world flips (B14: `group`/`enabled` on placements, `world.group.*`, the `world` effect) · thread records + `after`/`gate` sugar · spine lint (skip-proof, no-wedge structure, recurrent-gates) · a two-chapter exemplar thread whose chapter-one ending flips a group chapter two walks through | M | an authored two-chapter storyline progresses across a real gap of days, visibly changes the world, and its every ending has a passing full-arc test |

Sequencing: Q1→Q2→Q3 are strictly ordered (core, then safety, then
the door). Q4/Q5 are parallel after Q3. Q6 waits on the M4 NPC track.
Q7 is the convergence rung. Q8/Q9 slot anywhere after Q2. Q10 needs
only Q1+Q2 (flips and threads are player-independent — it can run
early if "storylines that progress" wants proving before scenes do).
STORY.md's S-ladder interleaves: S1 (facts) gates Q7's hook; S2
(memory dynamics) gates `opinion_band` going live — neither blocks
Q1–Q6.

---

## 14 · The do-not-build fence

- **No expression language in conditions, ever.** The table in §5 is
  the language; growth = mirrors or hooks. The day someone proposes
  `{"expr": "..."}` this section is the answer.
- **No mutable quest state.** No "current stage" variable, no
  un-latching, no quest reset verb (dev worlds are cheap; memoirs are
  not erasable).
- **No markers, compasses, pins, arrows, or distances.** Not even
  dev-gated in the shipped journal — guidance is text, people, and
  the world.
- **No runtime text generation.** Roles parameterize authored prose;
  brackets (Memory v2) select authored variants. Nothing writes
  sentences at runtime (the standing AI decision, applied to quests).
- **No drama-manager pacing engine.** Seed caps and cooldowns only.
  We pace by scarcity; a storyteller AI is another game.
- **No cutscene system.** Scenes are diegetic: real actors, real
  locomotion, dialogue UI. No camera choreography, no letterbox, v1
  or ever until a game *proves* the need at the table.
- **No multi-actor scene choreography in v1** (single actor + player;
  the assembler's shape leaves the door, we don't walk through it).
- **No separate quest save, no quest database.** WorldState is the
  store; records are the truth; Strata caches nothing authoritative.
- **No per-quest reputation scripting.** Valence tables (Memory v2)
  or nothing.
- **No free-form world mutation from quests.** The `world` effect
  flips placement GROUPS by stable id — authored both ways, placed by
  human hands. No spawning arbitrary scenes/nodes from a stage, no
  procedural set-dressing. (Enable parents, not a level scripter.)
- **No Strata-side evaluation of anything** (their fence, our
  handshake: the validate/`quest_test` verbs and the game are the
  only interpreters).

---

## 15 · Kitchen-table decisions (★)

New stars raised by this document (STORY.md's eight all still stand;
its ★3/★4/★8 are restated below with sharper gates):

1. **Bless stages-not-steps** (§3) as the v2 record shape —
   supersedes STORY.md's `steps` schema section.
2. **Journal voice** (§8): first-person past-tense memoir proposed —
   decide before quest #2, alongside the Wanderer's-identity canon
   question it touches.
3. **Notification loudness** (§8): propose root+terminal latches
   notify, middle stages fill the diary silently.
4. **Scene initiation tone** (§9): beckon-and-wait default vs.
   actor-approaches — with `initiate: true` as the authored
   exception.
5. **Dialogue branchiness** (§9): bless shallow-branch (choices
   return to trunk; the choice writes state, the tree doesn't).
6. **Radiance allowance** (§4): how often role-filled errands may ask
   things of the player — set the per-domain seed caps with the first
   three errands live.
7. **Direction-giving vocabulary** (STORY ★4, now gating Q7).
8. **First deadline tone-test** (STORY ★8, now gating Q8, and
   auditable in the harness first).
9. **Christening** (the systems-get-names corollary): the autoload is
   `Story`; the proposed table name for the whole layer (manager +
   memoir + scenes + threads) is **the Teller** — rename freely at
   the table.
10. **The main thread** (§3): does valley want a capital-M spine — a
    thread the whole game hangs on — and if so its premise is the
    journey-premise canon question (DESIGN.md, still open) finally
    coming due; the machinery is ready either way.
