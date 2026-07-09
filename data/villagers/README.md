# data/villagers/ — a person in the world

One file per villager: a named inhabitant with a daily schedule, raised as
an `AgentSim` mind by the `VillagerManager` autoload (the WildlifeManager
pattern — records → minds → bodies embodied only when the walker is near).
A villager lives by the CLOCK (its schedule's hour windows gate against
wall time), where wildlife lives by the sun.

**Content-empty by default.** Valley ships no villagers yet — this dir
holds only this note. No records here means no minds, no bodies, no ticks,
and a bit-identical soak. Drop a `<name>.json` in and a person walks.

## The record

```json
{
  "id": "mara",
  "name": "Mara",
  "home": {"x": -120, "z": -300},
  "body_scene": "res://game/villagers/villager_body.tscn",
  "schedule": [
    {"id": "garden", "at": {"marker": "p1a2b_3"}, "satisfies": "work",
      "rate": 8, "hours": [8, 12], "note": "tending the garden"},
    {"id": "rest",   "at": {"x": -120, "z": -300}, "satisfies": "rest",
      "rate": 10, "hours": [20, 6]},
    {"id": "wander", "at": "roam", "satisfies": "wander", "rate": 4}
  ]
}
```

- **id / name** — the record id (basename) and the display name the walker
  examines ("Mara").
- **home** — world XZ the mind spawns and rests at.
- **body_scene** — the creature-record pattern (wildlife's `body_scene`,
  reused): the `.tscn` a body wears when embodied. The default,
  `villager_body.tscn`, wears the biped-fox placeholder.
- **schedule** — an activities list, the `star_hounds.json` shape:
  - `id` (required) — the activity's name.
  - `satisfies` (required) — the need it feeds; the mind scores each
    activity by how depleted its need is, gated to the hour window.
  - `at` — where to do it: a raw `{x, z}`, `"roam"` (wander the home
    range), or `{"marker": "<placed-record-id>"}` — a **marker target**.
  - `rate` — how fast it refills the need (default 6).
  - `hours` — `[start, end]` window (wraps midnight if start > end); the
    activity is favoured inside it, dormant outside.
  - `note` — optional human phrase for the examine line ("tending the
    garden"); falls back to `id`.

## Marker targets (CREATION_KIT_REVIEW_V2 #3)

An activity may point at a **placed marker** by its stable cell-record id
instead of a raw XZ. A marker is a placed object authored from a card that
carries `"keyword": "marker"` (`Cards.is_marker`) — an idle/furniture point
("something tends here"). The manager resolves the id to the marker's live
position **at schedule time** (when the mind picks the activity), so a
marker the hand moved is honoured on the next decision. If the marker is
**gone** (deleted), the target falls back to the villager's home — honest,
never a dangling reference. Wildlife records carry no resolver, so a marker
target there simply reads as home.

## Presence, not dialogue

The walker can examine an embodied villager — `"Mara — tending the garden"`,
her name and what she's doing right now. That is the whole interaction: a
name and a line. No conversation, no choices (the ★s gate a dialogue
system; this is the honest v1).
