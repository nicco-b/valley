# Foundations Plan

*Written 2026-07-01, after the first build day. This is the groundwork map:
what exists, what's missing, what to build in what order, and how the project
stays workable for a solo human. Read alongside [DESIGN.md](DESIGN.md).*

## Where we are (honest audit)

| Domain | State | Debt / gap |
|---|---|---|
| World streaming | ✅ v1 — cell grid, threaded content loads, follows player/god/map | Terrain gen is main-thread (hitches on fast map pans) |
| Terrain | ✅ v1 — global height fn: noise + valley landform + sculpt layer (EXR) | Parametric valley should eventually become painted/sculpted region tiles; no erosion bake |
| Biomes | ❌ | Single implicit biome; no biome mask, records, or blending |
| Water | ⚠️ hardcoded | One pond as a landmark node; needs a water-bodies system |
| Flora/scatter | ✅ v1 — kit table, weighted, sway shader, trunk collision | Placed-kit trees don't sway (two code paths); no ground-cover stratum yet |
| Day/night | ✅ — GameClock + palette keyframes + fog + ambience crossfade | Palettes will move into biome records |
| NPC | ✅ v1 — schedule records, one inhabitant | No navigation (walks through nothing-yet, into things-eventually); no two-tier; no interaction |
| RPG spine | ❌ | No world-state store, no interaction layer, no UI baseline, no dialogue, no items |
| Characters | ⚠️ placeholder | CC0 robot; Blender pipeline not started |
| Tools | ✅ god mode (sculpt/place/fly), hot-reload, live map | No erosion bake, no region/biome painting, no nav debug; place mode lacks select/move |
| Save | ✅ skeleton — position, clock, versioned | Per-cell world state is a stub; NPC state unsaved |
| Data/records | ✅ pattern proven (cells, npcs) | No shared loader/validation; items/dialogue/flags don't exist |
| Canon | ⚠️ | Lore bible scaffolded; **axioms undecided** — blocks all writing |
| Project hygiene | ⚠️ | **No remote backup.** No dev guide, no test script, no CLAUDE.md |

## Principles (why the plan looks like this)

1. **Everything is a record** (the Bethesda lesson). NPCs, placements, items,
   dialogue, biomes, regions: JSON/resources in `data/`, loaded through one
   validated path. Code is the machine; data is the game.
2. **One source of truth per domain.** Height = `Terrain.height()`. Time =
   `GameClock`. State = `WorldState` (to build). Every consumer reads the
   source, never a copy.
3. **Tools live in the game** (god mode pattern). Debug builds carry the
   editor with them; shipped builds don't.
4. **Simulation amplifies authored intent, never replaces it** (Skyrim's
   erosion-then-hand-finish, not Starfield's generate-and-pray).
5. **Placeholders are honest.** Everything fake is labeled and has a
   named replacement path.

## The plan

### F1 — RPG spine (build first; everything Skyrim-like sits on these)

| # | What | Where | Notes |
|---|---|---|---|
| 1 | **WorldState** — flags/values store, signals on change, saves into the per-cell/global save scaffold | `game/state/world_state.gd` (autoload) | The consequence backbone. Design the naming scheme (`npc.wanderer.met`, `valley.bridge.repaired`) before code |
| 2 | **Records loader** — one JSON loader with schema validation + error reporting; migrate cells/npcs onto it | `game/data/records.gd` | Catches typos at load, not at runtime |
| 3 | **Interaction layer** — `Interactable` component (verb, prompt, signal), player raycast targeting, E key | `game/interact/` | Dialogue, examining, doors, harvesting, sitting-on-things all share this |
| 4 | **UI baseline** — one HUD singleton (prompt line, subtitle/notify line), one Theme resource in project palette | `game/ui/hud.gd`, `game/ui/theme.tres` | Everything on-screen goes through it; god/map HUDs migrate later |
| 5 | **Items v0** — item records + a pickup Interactable + a bare inventory list on the player | `data/items/`, `game/items/` | Just enough to prove record→world→player flow; no UI polish |

Then dialogue (engine choice: start with the Dialogue Manager addon; its
conditions/effects wire straight into WorldState) — but only after the
axioms conversation gives the writing a world. **Dialogue is gated on canon,
not on code.**

### F2 — engineering debts (small, do between features)

- **Threaded terrain generation** (WorkerThreadPool in `world_streamer.gd`)
- **NPC navigation**: runtime-baked navmesh per cell (NavigationRegion3D)
  or steering+avoidance; decide before NPC #2, required before the village
- **Two-tier NPC interface**: even with one NPC, split "abstract schedule
  tick" from "embodied body" so the village doesn't require a rewrite
- **NPC state in saves** (position, current schedule leg)
- **Unify placed-kit and scattered flora rendering** (one sway path)
- **Smoke test script**: `scripts/test.sh` = headless run + grep for errors
  (the check that already caught real bugs, made one command)

### F3 — world authoring maturation (as the world grows past the valley)

- **Region tiles**: painted heightmap registry (`data/regions/` + images);
  god-sculpt saves per-region; the parametric valley migrates into the first
  painted tile; frontier rim generated at unauthored edges
- **Biome system**: world biome mask (painted image) + biome records
  (`data/biomes/*.json`: palette keyframes, flora table, ambience beds,
  params like temperature/wind) — scatter, day/night, and audio all read
  the biome under the camera; blending at borders
- **Water bodies** as records (basin + surface), not landmarks
- **Erosion/hydrology bake** (`tools/erode.py`, EXR in → EXR out): weather
  the painted landforms; hydrology output feeds water placement and
  settlement logic ("why here?" answered by where water flows)
- **Distant LOD**: landmark impostors + far-cell low meshes (Skyrim LOD) —
  only when the quilt outgrows the fog

### F4 — the Blender pipeline (yes: characters, buildings, hero flora, props)

Blender becomes the third pillar of the pipeline (paint / Blender / Godot).
What flows through it, in order of arrival:

1. **Characters** (player + NPCs): her turnaround sheets → low-poly mesh →
   palette texture (tiny gradient atlas, the Sable technique — no painted
   UVs, just palette lookup) → rig (Rigify or Mixamo skeleton for retarget) →
   glTF with animation clips
2. **Architecture kits** (the village depends on this): modular snapping
   pieces (walls/roofs/doors on a grid — the Skyrim kit method)
3. **Hero flora/rocks**: billboard graduates for close-up areas
4. **Creatures, eventually guardians**: the deep end — bespoke rig + animset

**Conventions (adopt from file one):**
- Scale 1 unit = 1m; character forward = **+Z** (matches our controller math)
- Source `.blend` files in `assets/blender/<category>/<name>.blend`,
  exports to `assets/models/<category>/<name>.glb` — export is one click,
  source and export always commit together
- Godot import suffixes do the busywork: name a mesh `*-col` in Blender and
  Godot builds its collision on import (also `-occ`, `-navmesh`)
- Animation clip names are canon: `Idle`, `Walk`, `Run`, `SitDown`,
  `SitIdle`, `StandUp`, `Talk`, `Work` … (three-clip sit — we learned this
  from the robot)
- A **character record** (`data/characters/*.json`: model path, anim map,
  palette) binds art to game; player/NPC code consumes records, so swapping
  the robot for her first character is a data change
- Git handles binaries fine at our scale; revisit LFS if the repo passes
  ~1GB (decision logged here)

**Learning path (him, ~evenings across a few weeks):** Blender fundamentals
→ low-poly modeling from her turnarounds (boxy is *on-style*) → Rigify rig +
weight painting on one character → glTF export loop into Godot. Her paintings
already define silhouette and palette; the 3D translation is the learnable
part. Grant Abbitt's low-poly character series is the right speed.

### F5 — working without Claude (do continuously, starting now)

- [ ] **Push to a private GitHub remote — P0.** The entire project lives on
  one SSD right now
- [ ] `docs/DEV_GUIDE.md` — the manual: how to run, where everything lives,
  and **recipes**: add a flora / add an NPC / add a kit object / add a
  schedule / sculpt & save / re-export a painting / add a records file
- [ ] `docs/DECISIONS.md` — the why-log (engine, billboards, camera, no-VO,
  finite quilt world…), so future-you doesn't relitigate settled questions
- [ ] `CLAUDE.md` at repo root — project conventions for any future AI
  session: run/test commands, tscn gotchas (sub_resources before nodes,
  importer loop enum = 2, force-reimport dance), record patterns, style
- [ ] `scripts/run.sh`, `scripts/test.sh`, `scripts/reimport.sh` — the
  whole dev loop as three commands
- [ ] Data folder READMEs — every `data/*` dir explains its schema in 10
  lines
- [ ] `docs/ART_BIBLE.md` — the visual laws (matte world, glow reserved,
  palette ramps, billboard vs mesh rules) + asset specs for her

## Build order

```
F5 backup+scripts (today-sized)
→ F1.1 WorldState → F1.2 Records loader → F1.3 Interaction → F1.4 UI → F1.5 Items
→ F2 debts (threaded gen, nav, two-tier) — interleaved
→ [axioms conversation] → dialogue v1 → second NPC → village planning
→ F4 starts the day the first turnaround sheet exists (parallel track)
→ F3 lands when content outgrows the valley (region #2 forces it)
```

## Open questions (decide, don't drift into)

- Axioms + the glow's name + the Wanderer's identity (canon; blocks writing)
- Nav approach: navmesh-per-cell vs steering (prototype before NPC #2)
- Dialogue: how far the addon carries before custom tooling
- Sit verb migrates onto Interaction layer? (probably yes, later)
