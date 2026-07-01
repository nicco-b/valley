# Valley — Design Document

*Working title. Two-person team: Nicco (code, systems, audio, writing) + illustrator (art direction, paintings, character design).*
*Started 2026-07-01. This document is the source of truth for decisions; the lore bible (`docs/lore/`) is the source of truth for the world.*

## Vision

A vast, seamless, open-world RPG that feels like a real, lived-in place —
rendered entirely in one illustrator's hand-painted language. The player is a
traveler on a long journey. The tone is ambient and beautiful; the quiet is
punctuated by monumental encounters.

Reference constellation (each covers a different layer — this is a synthesis, not a clone):

- **Skyrim** — living world: NPC schedules, day/night, towns, the journey structure, sit-and-soak immersion
- **Sable** — proof that two people can ship an illustrated 3D open world; flat-shaded look, ambient traversal
- **Shadow of the Colossus** — the macro-structure: vast quiet world, few monumental guardians
- **Elden Ring** — vegetation density, glow-as-event lighting, deliberate weighty combat, legible layers of history
- **Her paintings** — the genre itself (see World & Genre)

## Pillars

1. **Sitting down is a feature.** The core loop must make stopping in a
   beautiful place feel earned and rewarding. Ambiance (sky, light, sound) is
   first-class content, not polish.
2. **Her art is the world.** Every visual decision defers to the painted
   language. If a technique fights the illustration style, the technique loses.
3. **A real place.** Settlements have reasons to exist, people have routines
   and relationships, history is legible in layers, and the world runs on its
   own internal logic — not fantasy or sci-fi tropes.
4. **Decisions mutate the world.** Player choices write to persistent world
   state that dialogue, schedules, prices, and places all read back.
5. **Sparse and monumental.** Few encounters, few bosses, few of everything —
   each one significant. Density of meaning over density of stuff.

## World & Genre

**A novel genre: not fantasy, not sci-fi.** Method: the setting is *derived
from the paintings* — an invented ecology (segmented bulb-flora, starburst
blooms, horned patterned creatures, colored pools, a close red sun) treated as
a real place.

- **World-axioms:** 2–3 alien premises taken completely seriously; everything
  downstream (plants, creatures, food, tools, culture, ruins) is a consequence.
  → Captured in `docs/lore/axioms.md`. **Status: to be chosen with the artist.**
- **The glow is not "magic."** Light-emission is a named natural phenomenon of
  this world with rules (source, seasons, behavior). The word "magic" is banned
  from the project.
- **Tools come from the world:** upgrade materials are creature/plant/mineral
  products of the ecology, never iron-and-steel defaults. The upgrade tree is a
  worldbuilding device.
- **Lived-in checklist:** every settlement answers *what do they eat, what do
  they trade, why this spot*; two legible historical eras in ruins and
  architecture; NPCs reference each other, not just the player.

## Art Direction

**Hybrid 3D + billboards, unified by palette.**

| Layer | Technique |
|---|---|
| Terrain, buildings | Low-poly meshes, flat-shaded in palette colors. No realistic textures, ever. |
| Vegetation, props, mid/far scenery | Her paintings as billboard cards to start; hero flora graduates to low-poly Blender models with painted textures over time. Dense grass/foliage stays billboard via GPU instancing (MultiMesh) with wind-sway shader — the Elden Ring grass technique. |
| Characters (player, NPCs, creatures) | Real 3D meshes, Sable-like low-poly, flat-shaded in her palette. Designed by her as turnaround sheets, modeled/rigged from those. |
| Sky | Painted gradients — literally her skies. Day/night is a palette shift, not just darkness. |
| Light/glow | The world is matte. **Only** the glow-phenomenon, shrines, and celestial bodies emit light + bloom. Glow is reserved visual language. |

**Visual laws:**

- One color script per biome per time-of-day. Characters use the same shading
  ramps as the world — nothing gets "normal 3D lighting."
- A biome = a palette + a kit family (element variations). New biome ≈ palette
  swap + a few hero elements.
- Paint element *families with variations* (3–4 variants per type) so nothing
  visibly repeats.

**Asset specs (working):** paintings as transparent PNGs, ~2000px tall for
large elements; layered source files kept for possible animation reuse.
Character turnarounds: front/side/back in palette.

## World Architecture (decide-now items — locked)

Target scale: **finite but undecided — the world grows outward.** Terrain is a
quilt of authored **heightmap tiles**: rectangular painted canvases (any size,
any position, ~2m/px, overlap allowed with priority blending) in a world
registry — the rectangle is the canvas, not the place; unpainted canvas defers
to what's beneath. World size = the union of tiles painted so far. Start with
the home valley, add places outward forever. Wherever nothing is authored, an
auto-generated impassable rim (ridge + fog frontier) closes the world;
painting the next tile dissolves that stretch of rim.

**Biomes are a separate, fully irregular layer**: a world-spanning painted
classification mask (low-res color map) deciding palette, flora kit, scatter
rules, and ambience per area. Biome borders meander independently of any tile
edge; systems blend across border bands (scatter crossfade, palette
interpolation, ambience fade). Authored stack, bottom to top: base detail
noise → terrain tiles → biome mask → cell content scenes → landmarks. Generative systems are subordinate detail: fine terrain
noise and deterministic flora scatter on top of authored landforms. Soft
budget: ~12 km world diameter before float-precision engineering returns —
grow radially to spend it slowest.

**The map** derives from the same masters and grows with the quilt: a
functional in-game map rendered from region heightmaps + POI records, and an
illustrated map painted by her, traced from the functional one so they never
disagree.

Architecture locked from day one:

- **Cell grid from day one.** The world is a grid of streamed cells. The first
  valley is cells of the real world map, not a standalone scene. Chunked
  scenes + threaded loading (`ResourceLoader.load_threaded_request`).
- **Large-coordinate plan.** 32-bit floats jitter beyond ~8–10 km from origin.
  Decision needed before the world grows: floating origin vs. Godot
  double-precision build. (Godot compiles from source either way — we keep
  that capability in the toolchain.)
- **Per-cell persistence.** Save/world state is keyed by cell so it scales.
  Consequences live here.
- **One global clock** drives sun, sky palette, schedules, everything.
- **Everything is data.** NPCs, items, dialogue, schedules, lore = records
  (Godot Resources / JSON) in `data/`, authored via our own tools in `tools/`.
  The Bethesda lesson: Skyrim is an engine + a database + kits. We build our
  own small Creation Kit as we go.
- **Interiors:** small structures (one-room huts, shrines) are true world-space
  seamless; complex interiors *may* use door transitions if ever needed. Let
  the game teach us.

## Systems

### Simulation & NPCs
- **Two-tier NPC simulation:** every NPC is a schedule record advancing against
  the global clock (abstract tier); an embodied character spawns only near the
  player. Schedules are data.
- NPC depth over NPC count: a village of 12 who know each other > a city of 200
  who don't. Relationship webs; opinions about each other and about the
  player's deeds.

### Consequence
- Decisions write **world-state flags** (reputation, who lives where, what's
  built/broken/tended, prices, trust).
- Dialogue lines carry conditions + effects; schedules and world objects read
  state.
- **Scope law: consequences mutate existing content, never spawn parallel
  branches.** Impact scales linearly, not combinatorially.

### Dialogue
- Text-only, **no voice acting — by design** (reactivity over performance; the
  world makes the sound, people make words). Start from the Dialogue Manager
  addon, outgrow it into our own data format if needed.
- Lore delivery: in-game books, item descriptions, environmental fragments —
  text is our cheapest asset and biggest strength.

### Progression
- **Use-based skills** (learn-by-doing, Skyrim's own philosophy): progression
  happens while wandering, never interrupts it.
- **Tools as exploration keys** (the Metroidvania layer): upgrades open
  terrain, night activity, crossings. Materials come from the ecology.

### Combat
- **Souls-inspired, not souls-cloned:** deliberate, stamina-based, commitment
  and recovery windows, lock-on. Third-person (settled by lock-on + inhabiting
  the character in vistas).
- Sparse encounters; wildlife mostly indifferent until provoked.
- **Bosses: ~one monumental guardian per biome** (Shadow of the Colossus
  structure). Each is bespoke (model, rig, animset, arena, tuning) — the most
  expensive objects in the game, budgeted accordingly.
- Combat feel = animation quality. Mixamo carries prototypes; hand-tuned
  animation is the long-term requirement.

### Audio
- Ambient-first: wind beds, positional emitters (water, wildlife), dusk/night
  crossfades — sourced from the field-recording library (~/Music/Sound
  Library). Positional audio is a core immersion system, not polish.

## Team Pipeline

- **She:** biome palettes + painted element kits (PNG), character/creature
  turnaround sheets, sky gradients, color scripts. Co-authors lore.
- **He:** all code + tools, Blender character modeling from her sheets,
  Mixamo rigging/retarget, audio design, the bulk of writing.
- Open with her: does she want to learn Blender (low-poly flat-shade is a
  gentle entry)? Biggest open pipeline question.
- Placeholder assets (KayKit / Quaternius packs, Mixamo anims) keep systems
  work unblocked while art pipelines mature.

## Roadmap

Milestones prove pipelines, not features. Each must be *solidly working and
verified* before the next begins.

1. **M1 — Grayblock valley (pipeline proof).** *Done 2026-07-01 (character is still the placeholder capsule; painting + wind are marked placeholders awaiting real assets).* Real world-grid cells.
   Third-person controller; sit mechanic (camera settles, HUD fades, ambiance
   up). Day/night sun + palette shift. One painted billboard element in-world.
   One placeholder 3D character standing among billboards — the make-or-break
   visual test. One wind loop + one positional emitter.
2. **M2 — The living valley.** Biome #1 kit + scatter tooling. Instanced
   vegetation w/ wind. Water. First 3D character from a turnaround. Cutout/
   glow tests. First lore records.
3. **M3 — Streaming proof.** Walk 10+ minutes in one direction across
   generated terrain through cell streaming with no hitch. Large-coordinate
   decision implemented.
4. **M4 — The first village.** 6–12 NPCs with schedules, relationship web,
   dialogue with conditions/effects, first consequences, per-cell persistence.
5. **M5 — First combat.** Weighty melee vs. one creature type; lock-on;
   stamina. Then, much later: the first guardian.

## Open Questions

- World-axioms (with her — founding worldbuilding conversation)
- Journey premise: why is the player traveling?
- Factions? Economy model (money/barter/none)?
- The glow-phenomenon's fiction: name, source, rules
- Boss/guardian fantasies per biome
- Game title
