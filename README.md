# Valley (working title)

[![ci](https://github.com/nicco-b/valley/actions/workflows/ci.yml/badge.svg)](https://github.com/nicco-b/valley/actions/workflows/ci.yml)

An open-world RPG made by two people: a vast, seamless, lived-in world rendered
in hand-painted illustration, built in Godot 4.

- **Design doc:** [docs/DESIGN.md](docs/DESIGN.md)
- **Lore bible:** [docs/lore/](docs/lore/)

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
