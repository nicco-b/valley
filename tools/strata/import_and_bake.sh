#!/usr/bin/env bash
# import_and_bake — make a Strata world_vN/ export the live Valley world.
#
#   tools/strata/import_and_bake.sh <world_vN_dir>
#
# Point it at a world_vN/ folder — either the Strata app's "Export World…" (⌘E)
# output (bakes exactly what you have tuned) or a `strata-cli bake --out` folder.
# Imports the elevation guide + biome map, then bakes the live terrain. When it
# finishes, walk it: ./scripts/run.sh
set -euo pipefail

world="${1:?usage: import_and_bake.sh <world_vN_dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
valley="$(cd "$here/../.." && pwd)"

[ -f "$world/bake_manifest.json" ] \
	|| { echo "no bake_manifest.json in $world — not a Strata world_vN export" >&2; exit 1; }

echo "== import $world → guide + biome map =="
STRATA_WORLD="$world" godot --headless --path "$valley" -s res://tools/strata/import_world.gd

echo "== bake the live terrain =="
godot --headless --path "$valley" -s res://tests/bake_world.gd

echo
echo "done — the Strata world is live. Walk it:  ./scripts/run.sh"
