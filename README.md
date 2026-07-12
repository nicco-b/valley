# Valley (working title)

[![ci](https://github.com/nicco-b/valley/actions/workflows/ci.yml/badge.svg)](https://github.com/nicco-b/valley/actions/workflows/ci.yml)

An open-world RPG made by two people: a vast, seamless, lived-in world rendered
in hand-painted illustration, built in Godot 4.

- **Design doc:** [docs/DESIGN.md](docs/DESIGN.md)
- **Lore bible:** [docs/lore/](docs/lore/)

## The framework moved out (2026-07-12)

Valley is now purely the game: content, world, and the tools that author
it. The engine half it once *was* — the world spine under `game/`,
`native/`, and `tools/strata/` — left home and became the **datum**
framework, whose source of truth lives at `~/code/datum/runtime`. Valley
is that framework's consumer #1: it holds a `framework.lock.json` like
any Strata-scaffolded game, pulls the current framework set with
`strata-cli framework update .` (source→game, offer-shaped, never
clobbering a hand-edit), and pushes a fix made here back home with
`strata-cli framework push .` (game→source). The native kernel dylibs
under `native/bin` and `native/contour/bin` still ship in-tree because
valley boots on them; the kernel SOURCE and build now live in datum (the
old tree is preserved on `museum/native-pre-move`). See
[docs/PLAN_FRAMEWORK.md](docs/PLAN_FRAMEWORK.md) — a tombstone pointing
at the living plan in datum.

## Layout

| Path | Purpose |
|---|---|
| `game/` | Scenes, scripts, shaders — the game itself |
| `data/` | Data-driven records: NPCs, items, dialogue, schedules |
| `tools/` | In-house authoring tools ("our Creation Kit") |
| `assets/paintings/` | Illustration exports (PNG, transparent) |
| `assets/audio/` | Ambient beds, positional emitters, field recordings |
| `assets/models/` | 3D characters and kit meshes |
| `docs/` | Design doc + lore bible (source of truth) |

## Running

Open in Godot 4.7+ (`godot --path .` or via the editor). Main scene is the
grayblock valley.
