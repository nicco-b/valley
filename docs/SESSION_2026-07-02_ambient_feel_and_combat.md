# Session Notes — Ambient Machine, Feel, Cozy/Explorable, Combat

*Design conversation, 2026-07-02. A synthesis pass, not new canon — it mostly
sharpens and extends [DESIGN.md](DESIGN.md) / [FOUNDATIONS.md](FOUNDATIONS.md)
/ [IDEAS.md](IDEAS.md), with a few concrete new systems and **one genuine
contradiction with existing canon flagged for a decision** (voice acting).*

**How to read this if you're a fresh context:** the game is already well
documented — start with STATUS.md, then DESIGN.md. This file is an addendum
covering ground that conversation opened up. Where it says **CONFIRMS**, canon
already had it and this is just reinforcement. Where it says **EXTENDS**, it's
a new mechanism serving an existing pillar. Where it says **TENSION**, it does
not agree with a settled decision and someone has to choose.

---

## 0. The framing that organized everything: the ambient machine

The sharpened lens this session: **the game is something a person leaves
running on their Mac all day and drops into on breaks from work** — a place to
*be*, not a task list to clear. This is the "Sitting down is a feature" pillar
(DESIGN Pillar 1) taken to its logical end: the world should be worth glancing
at, and worth returning to, precisely *because it kept living while you were
gone*.

This reframes the "simulation the player can't perceive is cut" rule (DESIGN /
FOUNDATIONS F1.5). The precise version:

- **Cut:** computation with *zero eventual output* (literal n-body orbits;
  grain-level granular solvers). Never perceivable, never a consequence.
- **Keep — the golden category:** **"unseen now, seen later."** Offscreen
  village lives, ecology, weather that ran for the eight hours you were at
  work — the player doesn't watch it happen, but sees its *consequences* on
  return. That is the whole point of an ambient world, and it's the
  justification for deep offscreen sim.

Everything below serves: *feels amazing to be in, works as a machine you leave
on.*

---

## 1. Always-on: five concrete engineering gaps (EXTENDS FOUNDATIONS F1.5)

The two-tier sim (embodied near / coarse far, in `game/npc/npc.gd`) is already
built and good. But "leave it running 24/7 and reconcile when you return"
stresses five things the current code doesn't handle yet. None are rewrites —
all are extensions of existing systems.

1. **Focus-aware throttle (highest priority for the ambient pitch).**
   `GameClock._process` and every NPC's `_process` run at full framerate even
   when the window is unfocused. On a laptop that spins fans and drains battery
   while someone is trying to work — directly sabotaging "leave it on." Add a
   focus handler (`NOTIFICATION_APPLICATION_FOCUS_OUT/_IN`) that, when
   unfocused, drops `Engine.max_fps` (or `OS.low_processor_usage_mode`) and/or
   flips every agent to coarse regardless of distance. Cheap; decisive for
   good-citizen behavior.

2. **Time reconciliation across closes.** `game/save/save_manager.gd` stores
   `hours`/`day` and restores them verbatim — so the world is *frozen while
   the app is closed* and resumes exactly where it left off. That's a valid
   choice, but it must be a *deliberate* one. If the world should keep living
   while closed: save a real wall-clock timestamp, and on load compute elapsed
   real time → game-hours and **fast-forward the sim**. This is the same
   timestamp infrastructure the optional real-local-time feature needs (§7).

3. **The catch-up must be a shared `advance(hours)` function.** Weather
   (`weather.gd`) and NPC needs (`npc.gd`) only advance on live `hour_tick`
   signals — set `GameClock.hours` directly and they go stale. One shared
   "advance simulation by N hours" routine, called by both the live tick and
   the load path, must drain needs, step coarse decisions, and roll weather
   transitions for skipped hours. Tractable because `_drain` is linear
   (closed-form for any dt); but decisions are a state machine, so **step in
   game-hour chunks**, never one giant dt leap (a single leap makes an NPC pick
   one activity for 8 hours instead of cycling sleep→eat→work).

4. **A third tier for village scale: dormant statistical agents.** Today every
   NPC is a persistent node under `npc_manager` that `_process`es forever, even
   ones kilometers away, untied to cell streaming. Fine for two inhabitants;
   won't reach the "first village" (M4) of 6–12, let alone bigger. The third
   tier is **agents that aren't nodes at all** — a plain data record advanced
   by the same closed-form math, instantiated into a `CharacterBody3D` only
   when the player nears. Near = full node, mid = coarse node, far = pure data.
   Same simulation, three fidelities. FOUNDATIONS already anticipates this
   ("the abstract far-tier arrives with the village") — this is that.

5. **NPC position/activity persistence.** Needs are saved to WorldState on
   `hour_tick`, but position and current activity are not — on load,
   `npc_manager` respawns everyone at `home`. An inhabitant mid-journey
   teleports home between sessions, breaking the "check in and see where
   everyone is" loop that makes an ambient world worth returning to.

---

## 2. Endless storylines via reactive story-seeds (EXTENDS DESIGN "systemic reactivity"; big idea)

The most important architectural realization of the session:

**Quests are already declarative queries over world state, not scripted
sequences.** In `journal.gd`, a quest is *active* when `start_if` passes and
*done* when every step's `done_if` passes over WorldState — no state machine,
no per-quest save data. The consequence: **anything that writes to WorldState
can open a storyline, including the simulation.**

So infinite content need not be Skyrim's repetitive radiant filler. It's a
**library of authored, condition-gated story-seeds that the living world
activates when its state matches.** When the ecology sim writes
`valley.drought`, a seed with `start_if: {flag: valley.drought}` appears —
authored once, triggered by the world itself, possibly hundreds of hours in.
This is the concrete mechanism for DESIGN's "RPG depth via systemic
reactivity" pillar, and it's the honest answer to "many storylines, never
ends": **fewer things written by hand, more situations the sim recombines.**
It also eases the writing-volume burden for a two-person team (see §6 tension).

This is exactly the Story-Manager idea, done observably and tied to a world
that actually simulates enough state to make it meaningful — the thing Skyrim's
radiant system couldn't quite do.

**Scaling caveats specific to "forever" (EXTENDS G1 save work):**
- WorldState is a flat dict saved as a *full* JSON snapshot every 30s. Over
  hundreds of hours it grows unbounded (flags, opinions, desire-path cells,
  event-log). Needs **selective memory — what the world forgets.** Decay is
  both performance and *design*: a world that remembers literally everything
  loses the meaning of permanence.
- Quests re-evaluate on every `WorldState.changed`. A large seed library needs
  **indexing** (evaluate only seeds plausibly relevant by region / involved
  NPC / time), the same tiering discipline as the sim.

---

## 3. Cozy × explorable as one spatial structure (EXTENDS Pillars 1 & 5)

"A beautiful world that feels cozy and explorable" is a designable structure,
not a vibe — and it unifies the whole design, combat included.

**The two are in productive tension:** cozy wants safety, warmth, familiarity,
return; explorable wants the unknown, the pull outward, a little risk. All-cozy
is a screensaver; all-explorable is exhausting. The resolution is **spatial: a
warm center and a wild edge that define each other.**

- **The hearth** — valley floor, shrine, water, inhabitants, worn paths. Safe,
  known, yours; where Stillness happens; consequence-light so it stays restful
  to leave running.
- **The wild edge** — ridges, deep places, boundaries. The unknown, the pull,
  and the *only* place sparse danger lives.
- This single structure yields coziness (center), explorability (pull outward),
  sparse combat (edges only, never the hearth), and stakes (the edge can cost
  you — which is *what makes returning to the warm center mean something*).

**Traversal skills are the exploration gate (CONFIRMS "tools as exploration
keys," EXTENDS it to the skill list).** Wayfaring / Swimming / Stillness aren't
combat stats — they're *keys to places*: a distance you can't yet endure, water
you can't yet cross, a patience a place demands. The valley reveals itself in
**rings** as you become able to reach further. This is Metroid ability-gating +
Outer Wilds knowledge-gating fused with the contemplative skill list, and it
keeps the *same map* explorable for a very long time — exactly what an endless
game needs.

**Progression must stay horizontal (CONFIRMS "no XP levels").** Skyrim breaks
at the top: you become a god and stakes evaporate. Use-based, experiential
skills (`time_sat` etc.) can't trivialize the world — they deepen your relation
to it. Keep all progression mastery/knowledge/relationship/world-shaping, never
power. Genuine "better than Skyrim" axis.

**Stakes without combat, since danger is sparse (CONFIRMS sparse/monumental):**
the tension engine is **impermanence and consequence** — NPCs age and die,
seasons pass and don't return, choices close doors the world remembers. "This
valley keeps what it's given" is already the theme; make memory the stakes.
(Spiritfarer / Outer Wilds / Death Stranding generate real stakes with zero
combat.)

---

## 4. Affect: the Snow White principle, authored-primary (EXTENDS Art Direction; important correction)

**The affective primitive: enclosure + darkness + cold = terror; enclosure +
light + warmth = cozy. Same geometry, opposite affect, flipped by light and
audio.** Snow White's scary woods and cozy cottage are the *same spatial idea*
in opposite lighting. Consequence: **there is no separate horror system and
coziness system.** The existing palette (`day_night.gd` keyframes), weather
(`weather.gd`), and fog (`fog_density`) systems *are* the dread-and-comfort
dials — pointed at enclosed geometry and swung.

**A biome is an emotional instrument with a range, not a texture set.** The
real primitive is **biome × time × weather = mood** (two-thirds already owned).
Each biome should contain *both poles* — its own hearth and its own wild
(mountain cabin *and* whiteout ridge; sunlit glade *and* claustrophobic
tangle; oasis *and* killing dune-openness) — so the whole map stays alive, not
one safe zone + one scary zone. An overall gradient (further rings skew wilder)
is fine, but every place should breathe both ways. Biome mask can be *informed*
by temperature + moisture (Whittaker: cold-high, wet-near-water, hot-dry-basin)
so biome/weather/ecology/rings fall out of the same two fields — **but authored,
not generated** (see the correction below).

### 4a. THE CORRECTION — authored intent is primary (CONFIRMS Principle #4, overrides an earlier over-emphasis on emergence)

Place-mood must be **handcrafted and intentional**, not dictated by weather and
time. The hierarchy:

> **Authored intent is the source of truth for a place. Weather and time only
> modulate within bounds the author sets, and only if the author opts in.**

A place has a designed identity true at noon in clear weather: a glade
*designed* sacred-cozy, a hollow *designed* dread — and it reads that way
regardless of conditions. The systemic layer at most *deepens* a mood the
author already placed; it never *decides* it. The sacred grove can stay holy in
a storm. **This is why Snow White works — that forest was storyboarded frame by
frame; no emergent system produces *that* forest.** The craft is the
intentionality.

**Mechanism — the affect zone (EXTENDS the landmark/cell-scene pattern):** an
authored volume (like `shrine.tscn`, or a record) carrying a designed identity:
target palette, audio bed, lighting/fog intent, and a `weather_influence` dial
from **0 (locked — ambient can't touch this mood)** to **1 (breathes freely
with conditions)**. On enter, the zone *asserts* its authored mood, pushing the
systemic day-night/weather/fog values toward the composed target by the amount
allowed. Same pattern as terrain: **systemic base, authored override where it
matters.**

**Division of labor (this is just what Skyrim is under the hood):**
- **Handcrafted set-pieces carry the emotional weight** — cottage, dread
  hollow, sacred grove, every combat threshold, every landmark that means
  something. Authored, mood-locked or lightly modulated by hand.
- **Systemic ambient runs everywhere as texture** — the wilderness *between*
  set-pieces, where drifting weather/time variation is a feature, because
  nobody composed those square meters and nobody needs to.
- Emotional authorship goes where the player's emotional attention goes; the
  rest is weather.

**Tone note (restraint is the craft):** Snow White's scary scene has *no
monster* — pure dread that dissolves at the cottage. For sparse combat: danger
being *possible and unseen* (a coarse-tier agent you hear but can't see in a
fog-closed night wood — nearly free, it's the existing far-tier NPC with the
mesh hidden) is scarier than danger present. Dread is the texture; the fight is
the rare payoff. And cozy only reads against cold — always author the two poles
as a pair (the exposed ridge exists to make the cabin's lit window mean
something).

---

## 5. Combat: feel target and the anti-spiral (CONFIRMS combat canon; adds warnings)

Existing canon is already right and this session reinforces it: **souls-
*inspired*, not souls-*cloned*; deliberate/stamina/lock-on; sparse; SotC
structure of ~one monumental guardian per biome; combat feel = animation
quality.** Additions from the conversation:

- **"Avoidable by certain builds" (new emphasis, EXTENDS "wildlife indifferent
  until provoked").** Author *situations with multiple resolution classes*, not
  combat walls: fight / evade via Wayfaring / talk down / know-a-secret /
  use-the-environment. Works natively because quests read *outcomes*
  (`{flag: valley.west_path_cleared}`), not methods — same world-state, many
  paths in. The Conditions language already expresses build-gating
  (`if: {gte: [player.wayfaring, 3]}`), exactly like dialogue choices.
- **Encounter = resolvable-situation schema (EXTENDS dialogue engine).** An
  approaching threat opens a node graph (structurally the dialogue engine): one
  branch gated on a martial skill drops into the combat state; another gated on
  a social skill sets the outcome flag directly; another gated on Wayfaring
  just lets you leave. A fight, a conversation, and a quiet exit become the
  same data structure the quest system already reads.
- **Combat reuses the utility AI (EXTENDS needs/utility NPC).** A hostile
  creature is the same needs-driven agent with a threat/safety drive and a
  predation activity set (the `storm_boost` pattern already proves
  context-modulated drives). The `star_hound` is an agent that hunts when
  hungry / flees when outmatched. Combat *emerges from the same sim*, and a
  predator pushed into the valley by the ecology sim becomes a reactive
  story-seed (§2). Combat + ecology + narrative = one system, three faces.

**Two warnings (the anti-spiral):**
- **Elden Ring *breadth* is a trap; ER *weight/readability* is the target.**
  Soulslike melee feel is ~70% animation, iterated by FromSoft across ~15
  years, and needs crystalline readable 3D animation — somewhat *opposed* to a
  hand-painted billboard aesthetic. More decisively: **deep combat has content-
  gravity.** A deep melee system *demands to be used*, fills the world with
  enemies to justify itself, and quietly kills the sparse cozy ambient game.
  The two dreams ("ER melee" and "sparse, avoidable, leave-it-running") are in
  direct tension; only one can be the center of gravity. The coherent wish is
  **deep *feel* per encounter, small *footprint* in the world** — the SotC
  shape (weight, consequence, readability; tiny moveset; bespoke, rare fights),
  which stays sparse *automatically* because the fiction doesn't manufacture an
  enemy stream. Canon already chose this — hold it.
- **Feel is discovered by prototyping, not decided by doc.** Being unsure how
  combat should feel is the correct state. Before any system rewrite, build
  **one fight** — player vs. `star_hound`, reusing the existing agent AI — and
  iterate on feel for a week. That vertical slice teaches what *this* game's
  combat wants far better than upfront design, and costs nothing structural.
  (Matches M5's "weighty melee vs. one creature type" — do it as a feel probe,
  early and throwaway, not as the M5 build.)

---

## 6. Meta-principle: advance by composition, not rewrite (guidance for the whole backlog)

Stated instinct: "each system probably needs a full rewrite to make it more
advanced and complex." Clarified to mean *"a genius interlocking system with
emergent behavior"* — which is the **right** goal, but the method matters:

> Depth in a living-world sim is **emergent from simple composable primitives**,
> not authored into each system. The genius is in the *interfaces between*
> simple systems being rich enough that behavior no one wrote falls out.

The current systems are good *in the way that scales*: the utility AI is small
and already believable; quests are declarative; WorldState is a dumb shared
blackboard. That simplicity is *why* they compose (ecology can trigger a
storyline; a number changes an NPC's mind; one Conditions language serves
dialogue + quests + encounters). Dwarf Fortress / RimWorld — the deepest sims
shipped — run on simple rules that interact. **Advance by growing the seams
between simple systems, not by rewriting any one into a cathedral.** Rewriting
the clean utility AI into an elaborate behavior-tree edifice buys more code,
less emergence, and a much higher chance of never shipping. "Simple parts,
genius seams" — at the scale of the whole game, cozy hearth → wild edge →
traversal-gated rings → threshold combat → permanence-stakes → return wears
desire-paths → world remembers → keeps living while away → dropping in is a
small homecoming. Every named system is a facet of one shape: *a warm known
place, and the pull of the unknown around it.*

---

## 7. Optional feature: real-local-time + accurate sun (EXTENDS IDEAS "celestial clockwork")

Considered but not required. An ambient always-on game can match the player's
**real local time and sun position** (Animal-Crossing-style), which is genuinely
cozy. Does **not** need any solar-system simulation — it needs one **solar
position algorithm** (NOAA / PSA / Meeus): feed latitude, longitude, date,
time → get sun azimuth + elevation, which drives the `Sun` DirectionalLight
directly. The equation analytically bakes in Earth's orbit and 23.44° axial
tilt, so **seasons come free** (the sun's arc correctly changes with the date).
An n-body sim would, after vastly more work, return the same angle. In Godot,
read the system clock via `Time`, get player lat/long (mobile GPS; desktop has
no clean GPS — use IP geolocation or a settings-screen location picker), feed
both in. Same wall-clock timestamp infra as §1.2. Note this coexists with the
invented ecology/red-sun canon — it's an *optional real-time mode*, not a
replacement for the world's own celestial fiction (which stays authored, per
axioms + "celestial clockwork").

---

## 8. TENSION — voice acting contradicts settled canon (needs a decision)

**This session's stated desire:** *full voice acting, for deep immersion.*

**Existing canon (DESIGN "Dialogue"; DECISIONS):** *"Text-only, **no voice
acting — by design** (reactivity over performance; the world makes the sound,
people make words)."* The rationale is real: VO caps reactivity (every
conditional line must be recorded), is a massive production bottleneck, and the
project's "unfair advantage" is text + ambient/positional audio, not
performance. Diegetic-music-only and field-recording ambience lean the same way.

**This is a direct contradiction and must be decided deliberately — do not let
it drift.** Points raised in conversation:
- Full voice for a Skyrim-scale, reactive, systemic-dialogue RPG is the single
  largest production commitment available, and it fights the systemic-
  reactivity pillar (recorded lines resist conditional variation).
- A two-person team can't voice a full cast without repetition; players clock
  reused voices fast.
- **If pursued anyway, the architecture is sound and decouples the risk:** give
  every dialogue line a **stable ID**; keep text/conditions/branching in data;
  make voice files *swappable assets keyed to IDs*, loaded if present, skipped
  if not. This lets the game ship fully text-driven and thicken with voice over
  years without touching game logic (also enables localization). **Design the
  ID + voice-file naming convention *now*, before there's much content —
  retrofitting it onto thousands of lines is miserable.** A synthetic-voice
  *scratch track* → real-actor replacement (in priority order) is the
  incremental path if VO happens, because ID-keyed assets swap in place. (Mind
  consent/rights on synthetic voice, and keep one consistent voice identity per
  character.)
- **Recommendation for the new context:** treat this as *open*, surface it to
  the humans, and — critically — **do the ID-keyed decoupling regardless**,
  since it costs nothing and preserves both futures. Don't silently overwrite
  the canon "no VO" decision; don't silently ignore the stated desire either.

---

## 9. Reconciliation summary (for a fresh context)

**CONFIRMS (canon already had it; session reinforced):** sparse/monumental
combat; souls-inspired-not-cloned; SotC guardian-per-biome; simulation as a
pillar with the Radiant-AI discipline (inspector, coarse tier, guardrails,
player-visible-or-cut); two-tier sim; painted biome mask blended across
borders; use-based horizontal skills; tools/skills as exploration keys;
systemic reactivity over branching; "if you can see it you can go there";
authored-primary / simulation-amplifies (Principle #4); desire paths (IDEAS ★);
no-compass navigation direction; ambient/positional audio as core.

**EXTENDS (new mechanisms serving existing pillars):** the ambient-machine
framing + "unseen now, seen later"; five always-on engineering gaps
(focus-throttle, wall-clock reconciliation, shared `advance(hours)`, dormant
statistical third tier, NPC position persistence); reactive story-seeds
(sim-triggered quests) + save-scaling/indexing caveats; cozy/explorable ring
structure with traversal-gated reveal; affect zones with `weather_influence`;
biome-as-emotional-instrument (biome×time×weather=mood, both poles per biome);
encounter-as-resolvable-situation schema + combat reusing utility AI;
composition-not-rewrite meta-principle; optional real-local-time solar
algorithm.

**TENSION (contradicts settled canon — decide):** **voice acting** (session
wants full VO; canon is text-only-by-design). Do the ID-keyed voice decoupling
regardless; surface the decision to the humans.

**Unchanged blockers (from STATUS/DECISIONS):** world-axioms + the glow's name
+ the Wanderer's identity still gate real writing; nav approach (navmesh vs
steering) still to prototype before NPC #2; large-coordinate decision still
pending before the world grows.
