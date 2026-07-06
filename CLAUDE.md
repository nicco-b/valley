# CLAUDE.md — project conventions

**Start every session by reading `docs/STATUS.md`** — live state, placeholder ledger, and what's next.

Two-person open-world RPG ("Valley", working title) in Godot 4.7 on macOS.
Skyrim-inspired living world, hand-painted art by a solo illustrator,
simulation-heavy. Read `docs/DESIGN.md` (what it is), `docs/FOUNDATIONS.md`
(build plan), `docs/DEV_GUIDE.md` (how to work on it).

## Commands

- `./scripts/run.sh` — run the game
- `./scripts/test.sh` — import + unit tests + headless smoke. **Run before
  every commit.** It catches parse errors, missing class cache, and runtime
  errors; it cannot catch visual/layout bugs — those need a human.
- `./scripts/reimport.sh [name]` — reimport assets; with a name fragment,
  force-reimports by clearing that cache (needed when only `.import`
  settings changed)
- `./scripts/soak.sh` — 30 game-days headless, twice: invariants +
  determinism fingerprint must match. **Run before merging sim work.**

## Architecture (one source of truth per domain)

Autoloads, in order: `WorldState` (all flags/values — dot-namespaced keys
like `npc.wanderer.met`; everything consequence-shaped reads/writes here),
`GameClock` (time, 1:1 with real time, wall-clock driven; `hour_tick`
signal, `hours_delta()`, `advance_hours()` chunked catch-up — route ALL
time skips through it; real-calendar seasons — sun-following systems read
`solar_hours()`, never raw hours), `FocusThrottle` (unfocused fps cap),
`Terrain` (the
global height function: noise + valley landform + sculpt edit layer),
`Weather` (wind/storminess; publishes `wind_strength` global shader param),
`Climate` (the substrate fields: `temperature(x,z)` + `moisture(x,z)`;
publishes `ground_wetness` — new sims read these, never roll their own),
`Records` (validated JSON loading), `HUD` (all on-screen text: prompt/say/
notify/satchel), `Items`, `Kit` (placeable palette), `CellRecords` (placed-
object JSON), `Toolkit` (the in-game editor), `HotReload`, `MapScreen`, `SaveGame`.

The world is a 128m cell grid streamed around the player (or Toolkit cam / map
focus) by `game/world/world_streamer.gd`: per-cell terrain mesh + collision,
deterministic flora scatter (seeded by cell coords), authored cell scenes
(`game/world/cells/cell_X_Y.tscn`), placed records (`data/cells/*.json`).

Content is data: NPCs, items, placements in `data/` as JSON, loaded through
`Records` with schema validation. Prefer adding records over adding code.

## System names (blessed 2026-07-04 — use in commits, docs, inspectors)

**The Watershed** water tiers (Hydrology/WaterField/WaterWaves/records) ·
**the Almanac** GameClock: real calendar/sun/moon/seasons · **the
Ambient Machine** advance_hours catch-up + FocusThrottle · **the Grain**
sand field/patch/slide · **the Elements** Weather/Climate/FloraLife/snow ·
**the Loom** world streamer/terrain/far LOD · **the Ways**
Nav/WaypointGraph/roads · **the Traces** InteractionField wear/desire
paths · **the Understory** AgentSim/NPCs/wildlife/rumors (offscreen
lives) · **the Chronicle** WorldState/SaveGame/Records/CellRecords ·
**the Campfire** Dialogue/Journal/quests/Skills · **the Toolkit** the
in-game editor (F1): fly/sculpt/place/inspect/world panel + hot-reload
+ module layer (the Creation Kit decision; "god mode" as a name is
RETIRED 2026-07-05 — the autoload is `Toolkit`, one app forever). Tag
new scripts' ## doc comments with their system name.

## Hard-won gotchas (do not relearn these)

- Hand-written `.tscn`: ALL `[sub_resource]` blocks must precede the first
  `[node]`; `load_steps` = ext_resources + sub_resources + 1; exported
  node references (`@export var x: Node3D`) do NOT resolve from hand-written
  scenes — use `$"../Sibling"` in script instead.
- WAV importer loop enum: `edit/loop_mode=2` is Forward (1 is Disabled).
- `godot --headless --import` skips unchanged sources — editing only the
  `.import` file does nothing until you clear `.godot/imported/<file>-*`
  (that's `reimport.sh <name>`).
- New `class_name` scripts need an import pass before headless runs see
  them (test.sh imports first for this reason).
- HUD/UI: use full-rect labels with text alignment; point-anchored labels
  under a CanvasLayer computed off-screen positions.
- Animation state machines: compare against `assigned_animation`, not
  `current_animation` (which empties when a one-shot finishes and
  retriggers it every frame). One-shot poses (Sitting/Jump) must not loop.
- Characters face **+Z** (three.js/Blender convention we adopted);
  `atan2(dir.x, dir.z)` yaw. The placeholder robot's armature carries a
  baked ×100 scale — model node is scaled 0.65 for ~1.7m.
- Physics: Jolt. Player/NPC on collision layer 2, world on 1.
- **Verify pushes succeeded** (`git log origin/main..main` should be empty).
  A push touching .github/workflows needs the gh token's `workflow` scope —
  rejections once went unnoticed for 11 commits because a command chain
  swallowed the error.
- Audio: exit-time "leaked instance" warnings for playing streams are
  benign; test.sh filters them.

## Style

- GDScript: tabs, typed (`:=` where inferable; explicit types on Variant
  boundaries — JSON access needs explicit types, `:=` fails on Variant),
  `##` doc comments on every script explaining its role in the system.
- Every placeholder is labeled placeholder with its replacement path.
- Simulation code must ship with observability (the Toolkit inspector
  pattern) — see FOUNDATIONS F1.5 rules. **Toolkit control (2026-07-04):**
  every new system ships a Toolkit hook — at minimum a summary()/
  sim_debug() the inspector can print, plus override knobs where the
  system has any (the Toolkit is a product; systems it can't see or
  steer are debt).
- **GDExtension policy (2026-07-04):** GDScript until profiled, then
  port the hot inner loop behind the same interface. Known hot-loop-
  shaped candidates: `Terrain.height()` bulk samplers, hydrology
  routing, CPU sand reference, agent catch-up replay at city scale.
  Physics needs nothing (Jolt is already C++). If/when the double-
  precision Godot build lands, every GDExtension must be compiled
  `precision=double` to match or it will corrupt Variants silently.
- **The sim contract (time is 1:1; DECISIONS 2026-07-02):** every
  simulation is either (a) a stateless function of real time (seasons,
  sun, moon) or (b) stateful and advanced by `hour_tick` /
  `sim_advance_hours` so `GameClock.advance_hours` replays closed/asleep
  stretches. State that mirrors WorldState joins the
  `world_state_reader` group with a `load_state()` (boot `_ready` runs
  before the save restores). A sim that can't catch up doesn't ship.
- Commit style: what + why, present tense; end with the Co-Authored-By
  trailer; push after committing (private repo github.com/nicco-b/valley).
