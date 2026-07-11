# data/characters/ — the cast sheet

One file per **character**: a named inhabitant of the world — a villager or
a lone creature — raised as an `AgentSim` mind by the `VillagerManager`
autoload (records → minds → bodies embodied only when the walker is near).
This is the CK "packages door" promoted to a first-class validated record
kind (CREATION_KIT_REVIEW_V2 #3): a creature's day, and a villager's, edited
like a quest.

**Content-empty by default.** Valley ships no live characters yet — this dir
holds only this note. No records here means no minds, no bodies, no ticks,
and a bit-identical soak: a mind exists only when a record does. The worked
example below ships as a lint/scene-test fixture
(`tests/fixtures/characters/mara.json`), dark to the fingerprinted sim; drop
a `<name>.json` in *here* and a person walks the live world.

## The record

```json
{
  "id": "mara",
  "identity": { "name": "Mara", "kind": "villager" },
  "body": {
    "card": "chars/villager_keeper",
    "palette": { "base": [0.72, 0.55, 0.42] },
    "scene": "res://game/villagers/villager_body.tscn"
  },
  "home": { "x": -120, "z": -300 },
  "schedule": [
    { "id": "garden", "at": { "marker": "p1a2b_3" }, "satisfies": "work",
      "rate": 8, "hours": [8, 12], "note": "tending the garden" },
    { "id": "rest",   "at": { "x": -120, "z": -300 }, "satisfies": "rest",
      "rate": 10, "hours": [20, 6] },
    { "id": "wander", "at": "roam", "satisfies": "wander", "rate": 4 }
  ],
  "mind": { "needs": { "work": 1.2, "rest": 1.0 }, "keep_bias": 1.1, "roam_range": 150 }
}
```

- **id** — the record id (its file basename).
- **identity** — `name` (the display name the walker examines, "Mara") and
  `kind`, one of:
  - **`villager`** — lives by the **clock**: schedule hours gate against wall
    time (garden by morning, home by night), and drains harder.
  - **`creature`** — lives by the **sun**: schedule hours gate against *solar*
    time, like the wildlife, but as a lone embodied character (a herd is
    `data/wildlife/`, WildlifeManager's business).
- **body** — how the character looks when embodied:
  - `card` (required) — a model-**card** slot (`Cards`; the card file must
    exist — the character lint checks it). The cast wears placeholder chars
    cards today (`chars/villager_keeper`, …).
  - `palette` (optional) — a CharacterPaint tint; a `base` `[r, g, b]` array
    recolours every surface, so one placeholder mesh wears many faces.
  - `scene` (optional) — the embodiment shell `.tscn`; defaults to
    `villager_body.tscn` (the biped-fox placeholder with a presence).
- **home** — a **place**: a raw `{ "x": …, "z": … }`, or a
  `{ "marker": "<placed-record-id>" }` (resolved to the marker's live
  position; falls back to the origin if the marker is gone).
- **schedule** — an activities list, the `star_hounds.json` shape:
  - `id` (required) — the activity's name.
  - `satisfies` (required) — the need it feeds; the mind scores each activity
    by how depleted its need is, gated to the hour window.
  - `at` — where to do it: a raw `{x, z}`, `"roam"` (wander the home range),
    or `{ "marker": "<placed-record-id>" }` — a **marker target**.
  - `rate` — how fast it refills the need (default 6).
  - `hours` — `[start, end]` window (wraps midnight if start > end); the
    activity is favoured inside it, dormant outside.
  - `note` — optional human phrase for the examine line ("tending the
    garden"); falls back to `id`.
- **mind** (optional) — AgentMind tunables:
  - `needs` — per-need **drain weight** map (need → weight); a need not named
    defaults to weight 1.0. Higher weight drains faster.
  - `keep_bias` — hysteresis (> 1.0 keeps the current activity unless a rival
    clearly beats it), so a character doesn't dither at a boundary.
  - `roam_range` — how far a `"roam"` activity wanders from home.

## Validation (the desk can never write a record the game can't read)

Every field is checked at load time and, identically, by the `records
validate characters` desk verb (`VillagerManager.validate_character`). The
character lint (`CharacterLint`, in `test.sh`) runs the same judgement over
this dir plus an adversarial fixture corpus, and adds: the schedule is sound,
every marker reference is well-shaped, and every `body.card` names a card
that exists. A malformed record is refused with the game's own words, never
silently dropped into a broken mind.

## Marker targets (CREATION_KIT_REVIEW_V2 #3)

A `home`, or a schedule activity's `at`, may point at a **placed marker** by
its stable cell-record id instead of a raw XZ. A marker is a placed object
authored from a card that carries `"keyword": "marker"` (`Cards.is_marker`) —
an idle/furniture point ("something tends here"). The manager resolves the id
to the marker's live position **at schedule time** (when the mind picks the
activity), so a marker the hand moved is honoured on the next decision. If the
marker is **gone** (deleted), the target falls back to the character's home —
honest, never a dangling reference. Wildlife records carry no resolver, so a
marker target there simply reads as home.

## Presence, not dialogue

The walker can examine an embodied character — `"Mara — tending the garden"`,
her name and what she's doing right now. That is the whole interaction: a name
and a line. No conversation, no choices (the ★s gate a dialogue system; this
is the honest v1).
