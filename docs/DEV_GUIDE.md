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

| Key | In game | | Key | God mode (F1) |
|---|---|---|---|---|
| WASD | move | | WASD + mouse | fly |
| Shift | sprint | | E / Q | up / down |
| Space | jump | | wheel | fly speed |
| C | sit | | Tab | sculpt ↔ place |
| E | interact / catch | | LMB / Shift+LMB | raise / carve (sculpt) |
| I | satchel | | `[` `]` | brush size |
| J | journal (quests + skills) | | RMB on NPC | sim inspector |
| M | map (pan/zoom, gestures) | | 1–9 | pick kit object (place) |
| F / R | deploy / recall fireflies | | LMB | place object |
| Esc | pause (or close map/talk) | | Z | undo last placement |
| **T** | *debug:* +1 hour | | F5 | save terrain edits |
| **Y** | *debug:* next weather | | F1 | exit **(teleports player)** |


## How the systems fit (two minutes)

**Time** flows from `GameClock` (15-min days; `hour_tick` signal).
**Weather** rolls a state each hour and eases `wind`/`storminess` values
that drive flora sway (global shader param), wind audio, fog, sun, dust,
and NPC decisions. **Terrain** is one height function: noise + the authored
valley landform + your god-mode sculpts (saved to
`data/terrain/edit_layer.exr`). The **streamer** keeps a 5×5 patch of 128m
cells alive around you: per-cell terrain, deterministic flora scatter,
authored cell scenes, and placed records. **NPCs** are needs-driven: their
JSON defines needs (drain weights) and activities (what satisfies which
need, where, when preferred); behavior emerges — watch it with the
inspector. **WorldState** remembers everything (flags/counters; the whole
store saves). **HUD** shows all text. **Items** live in WorldState.

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

**Add an NPC** — copy `data/npcs/wanderer.json`, change id/name/home,
tune needs weights (higher = drains faster) and activities (`at` is
`"home"` or `{x,z}`; optional `hours: [start,end]` preferred window,
`pose: "sit"`, `rate`, `wander`, `storm_boost`). They spawn at home on
launch. Inspect their mind with god-mode RMB.

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
