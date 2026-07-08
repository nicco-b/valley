# data/ — the game's records

Everything here is content, not code: human-editable JSON (plus the terrain
edit layer), validated on load by the Records autoload, committed to git.
Prefer adding records over adding code.

## cells/ — placed objects
`cell_X_Y.json` (world cell coords, 128m grid): array of
`{kit, x, y, z, yaw, scale}` — world-space position, kit id from
`game/world/kit.gd`. Written by Toolkit place mode; safe to hand-edit.
(Empty since the 2026-07-07 de-valley wipe — new places get composed on
the Strata world.)

## wildlife/ — record-driven animals
One file per herd: needs × activities, same shape the retired NPC records
used (`data/npcs/` comes back when inhabitants are rebuilt on the Strata
world). Behavior emerges from needs × activities. Inspect live:
Toolkit → RMB on an agent.

## items/ — item definitions
`{id, name, desc}`. Inventory lives in WorldState (`player.inventory`).
World pickups are `game/items/pickup.tscn` instances with `item_id` + a
globally unique `uid` (persistence: taken stays taken).

## terrain/ — authored terrain
`edit_layer.exr`: the Toolkit sculpt layer (float heightmap, 2m/px,
4×4km centered on origin), added on top of base noise. Painted region
tiles will join it here (see FOUNDATIONS F3).
