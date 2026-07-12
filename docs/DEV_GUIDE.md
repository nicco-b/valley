# Dev Guide

*The manual. How to run, what the keys do, how each system works, and
recipes for the common tasks. Companion to [DESIGN.md](DESIGN.md) (vision)
and [FOUNDATIONS.md](FOUNDATIONS.md) (build plan).*

## Running

- `./scripts/run.sh` — play
- `godot --path . -e` — open the Godot editor
- `./scripts/test.sh` — run before every commit
- Saves live in `user://save.json`
  (`~/Library/Application Support/Godot/app_userdata/Valley/`); delete to
  start fresh.

## Controls

| Key | In game | | Key | Toolkit (F1) |
|---|---|---|---|---|
| WASD | move | | WASD + mouse | fly |
| Shift | sprint | | E / Q | up / down |
| Space | jump | | wheel | fly speed |
| C | sit | | Tab | sculpt ↔ place |
| E | interact / catch | | LMB / Shift+LMB | raise / carve (sculpt) |
| I | satchel | | `[` `]` | brush size |
| | | | RMB on agent | sim inspector |
| M | map — a real 3D orbit view: drag orbit, wheel zoom, WASD pan; weather-exempt, midnight-readable | | 1–9 | pick kit object (place) |
| | | | N | toggle navmesh overlay |
| | | | O | world panel (every system + HERE: t/humidity/wetness/vitality under the camera) |
| F / R | deploy / recall fireflies | | LMB | place object |
| Esc | menu — world keeps running (or close map) | | Z | undo last placement |
| **T** | *debug:* → next sunrise/noon/sunset/midnight | | F5 | save terrain edits |
| **Ctrl+T / Ctrl+Shift+T** | *debug:* +1 hour / +15 min | | | |
| **Shift+T / Alt+T** | *debug:* +1 day / +1 week | | | |
| **Shift+Alt+T** | *debug:* back to now (real time) | | | |
| **Y** | *debug:* next weather | | F1 | exit **(teleports player)** |


## How the systems fit (two minutes)

**Time** flows from `GameClock` (1:1 with the real world — a game day is a
real day, anchored to your local time; real-calendar seasons and real
local sunrise/sunset from Settings' geolocated latitude/longitude;
`hour_tick` signal; dev time travel on T always *lives* the skipped hours
through `advance_hours`, so weather and NPCs experience them — there is no
travelling back).
**Weather** rolls a state each hour and eases `wind`/`storminess` values
that drive flora sway (global shader param), wind audio, fog, sun, dust,
and NPC decisions. **Terrain** is one height function: noise + the authored
valley landform + your Toolkit sculpts (saved to
`data/terrain/edit_layer.exr`). The **streamer** keeps a 5×5 patch of 128m
cells alive around you: per-cell terrain, deterministic flora scatter,
authored cell scenes, and placed records. **NPCs** are needs-driven: their
JSON defines needs (drain weights) and activities (what satisfies which
need, where, when preferred); behavior emerges — watch it with the
inspector. **WorldState** remembers everything (flags/counters; the whole
store saves). **HUD** shows all text. **Items** live in WorldState.

## WorldState & the substrate — the mirror retirement (engine tail)

`WorldState` (`game/state/world_state.gd`) is the dotted-key store AND, under
`STRATA_CONTOUR_HELD=1`, a MIRROR of the held world the 7 Contour SINGLETON
systems (weather, climate, flora, hydrology, sand, story, AgentMind) advance in
place: `ContourBridge.tick_held` keeps `WS[owned] == held[owned]` every tick by a
diff-only `set_value` (F2). The last substrate rung retires that second copy for
SINGLETON domains — the held world becomes the single sim truth, `changed` is
re-provided as a post-tick diff, and `get_value` reads a held-owned key THROUGH to
the held world.

**The canonical design + the full consumer map live in datum
`docs/SUBSTRATE.md §2a`** — every writer/reader/`changed`-subscriber classified,
the per-SINGLETON design, and the shim that stays. Read it before touching this.
Load-bearing valley facts:

- **`WorldState` is NOT deleted** — it stays the store for every key no Contour
  system owns (`journal.*`, `player.inventory`, `skill.*`, NPC opinions, flags),
  the save serializer, and the presentation-`changed` bus.
- **Per-SINGLETON only.** agent_sim's MULTIPLEXED herd keeps the mirror (F2 law) —
  a between-tick sibling reads back stale from a multiplexed held world.
- **`changed` presentation readers are disjoint from the retired set:** HUD
  (`player.inventory`) and skills (`skill.*`) watch non-held keys, so the post-tick
  diff never perturbs them. **Story `_on_changed`** is the one subscriber that can
  watch a held-owned key (a quest gating on `weather.state`) — it is re-provided
  the moved write from the bridge's post-commit diff.
- **The B12 forcing door** (`strata_link.gd:_state_set`, `state set <key> <value>`)
  must write THROUGH to the held world for a held-owned key post-retirement, else
  the forced value is clobbered next tick.

**Gating remainder (why the flip is NOT landed here):**

1. **Read-through kernel binding.** Datum landed the O(1) primitive
   `lattice_world_read` (proven bit-identical to snapshot-index — SUBSTRATE.md
   §2a). The valley `Contour` GDExtension (`native/contour/contour_kernel.cpp`)
   still needs a `world_read(key)` method wrapping it — an engine kernel rebuild.
   Until then `WorldState` cannot read through and the SINGLETON copy cannot be
   removed.
2. **Forcing-door write-through** needs the matching `world_write` kernel binding.
3. **Sequencing law (planner):** the retirement lands only AFTER restore-into-held
   (Rung 3's other half) is matrix-proven — the mirror is that rung's parity ORACLE
   and must survive until then. The `agent/g1-restore-held` lane owns restore +
   save_migration + the `.ct` canonical-form move; do not touch save/load here.

**Deferred gate protocol (ALL mandatory before the flip merges):**

1. `./test.sh` green **twice** (parse + behavior + the held-snapshot gate).
2. The **six-run soak matrix** bit-stable: `2×off / 2×STRATA_CONTOUR /
   2×+STRATA_CONTOUR_HELD` share ONE fingerprint, `held_ticks` earned — AND the
   new mirror-retire flag run must join it bit-identical (identity is the law; a
   moved fingerprint means the post-tick-diff or read-through changed truth — a red
   flag to redesign, not to re-pin).
3. **Plumb re-certification** of every affected leaf (the 7 SINGLETON `.ct`s) vs the
   tree, bit-identical.
4. A **save/load covenant pass**: a save written pre-flip loads post-flip and back,
   byte-for-byte (the save format is a substrate invariant), and a windowed load
   over a real multi-day world settles quests identically.

## Recipes

**Add a flora painting** — export transparent PNG into `assets/paintings/`,
add one line to `FLORA` in `game/world/world_streamer.gd` (path, height in
meters, scatter weight). If the game is running, re-exporting the PNG
hot-reloads it live.

**Add a placeable kit object** — make a small scene in `game/world/kit/`
(root StaticBody3D or Node3D, origin at ground level), add an entry to
`ENTRIES` in `game/world/kit.gd`. It appears in place mode (F1 → Tab).

**Compose a place** — F1, fly there, Tab, pick objects with 1–5, click.
Placements save instantly to `data/cells/cell_X_Y.json` (commit them).

**Shape terrain** — F1, sculpt with LMB / Shift+LMB, F5 (or exit) saves.

**Add an NPC** — retired with the old valley (2026-07-07 de-valley wipe;
the record-driven NPC system comes back when inhabitants are rebuilt on
the Strata world). Wildlife still works the same way: copy a record in
`data/wildlife/`, tune activities. Inspect any agent's mind with
Toolkit RMB.

**Add an item** — JSON in `data/items/` (id, name, desc). To place one in
the world: instance `game/items/pickup.tscn` in a cell scene, set
`item_id` and a globally unique `uid` (this is what makes taking it
permanent).

**Add examinable lore** — add an Area3D with `game/interact/examinable.gd`
to any scene; set `prompt`, `text`, optional WorldState `flag`.

**Change the day length** — `day_length_minutes` in
`game/world/game_clock.gd`. Palette keyframes: `KEYS` in
`game/world/day_night.gd`. Weather odds: `TRANSITIONS` in
`game/world/weather.gd`. World metabolism (need drain, hysteresis):
constants atop `game/npc/npc.gd`.

**Reshape the world** — the landform is authored in **Strata**
(`~/code/strata`); import an export with
`tools/strata/import_and_bake.sh <world_vN dir>` — its `height.exr`
becomes the live tile directly (sha-verified, full res, zero
re-erosion; biome map + sea level ride the same manifest). Local
touch-ups in-game: Toolkit sculpt (fine, 2m/px near the origin) or the
TERRAIN/map pens, which paint an **override layer**
(`data/terrain/tile_override.exr`, additive meters) composited over
the read-only blessed tile. The old elevation-guide pipeline
(guide EXR → erosion rebake) and its Blender trip
(`assets/blender/terrain/valley_terrain.py`) are retired — P0 seam
fix, `strata/docs/ONE_APP.md`.

**Swap placeholder audio** — replace `assets/audio/wind_loop.wav` /
`night_loop.wav` with real recordings (seamless loops), then
`./scripts/reimport.sh wind_loop` (force). Check `.import` has
`edit/loop_mode=2`.

## Troubleshooting

- **Scene fails to parse after hand-editing a .tscn** — sub_resources must
  all come before the first node; recount `load_steps` (ext + sub + 1).
- **Changed an .import setting, nothing happened** — `reimport.sh <name>`
  (Godot skips unchanged sources).
- **New class_name not found headless** — run an import (test.sh does).
- **Audio plays once and stops** — loop enum: 2 is Forward, 1 is Disabled.
- **Weird world state while testing** — delete the save (path above);
  placed objects/terrain edits are separate (in `data/`, git-tracked).
- **Something visual broke** — the smoke test can't see pixels; bisect
  with `git log --oneline` + `git checkout <sha>`, then report/fix.
