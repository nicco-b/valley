# data/ — the game's records

Everything here is content, not code: human-editable JSON (plus the terrain
edit layer), validated on load by the Records autoload, committed to git.
Prefer adding records over adding code.

## cells/ — placed objects
`cell_X_Y.json` (world cell coords, 128m grid): array of
`{kit, x, y, z, yaw, scale}` — world-space position, kit id from
`game/world/kit.gd`. Written by god-mode place mode; safe to hand-edit.

## npcs/ — inhabitants
One file per NPC:
```json
{
  "id": "wanderer", "name": "The Wanderer",
  "home": {"x": -28, "z": 16},
  "needs": {"rest": 1.0, "water": 1.5},          // drain weight per need
  "activities": [{
    "id": "drink", "at": {"x": 70, "z": -265},   // or "home"
    "satisfies": "water", "rate": 14,             // satisfy speed
    "hours": [20, 6],                             // optional preferred window
    "pose": "sit", "wander": 18, "storm_boost": 8 // all optional
  }]
}
```
Behavior emerges from needs × activities. Inspect live: god mode → RMB.

## items/ — item definitions
`{id, name, desc}`. Inventory lives in WorldState (`player.inventory`).
World pickups are `game/items/pickup.tscn` instances with `item_id` + a
globally unique `uid` (persistence: taken stays taken).

## terrain/ — authored terrain
`edit_layer.exr`: the god-mode sculpt layer (float heightmap, 2m/px,
4×4km centered on origin), added on top of base noise. Painted region
tiles will join it here (see FOUNDATIONS F3).
