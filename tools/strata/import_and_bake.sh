#!/usr/bin/env bash
# import_and_bake — make a Strata world_vN/ export the live Valley world.
#
#   tools/strata/import_and_bake.sh <world_vN_dir>
#
# Point it at a world_vN/ folder — either the Strata app's "Export World…" (⌘E)
# output (imports exactly what you have tuned) or a `strata-cli bake --out`
# folder. P0 seam fix (strata ONE_APP.md): the export's height.exr IS the
# baked tile — copied sha-verified at full resolution, zero re-erosion, no
# guide roundtrip. Biome map + sea level ride the same export/manifest.
# (The name keeps its old "and_bake" for muscle memory; nothing rebakes.)
# When it finishes, walk it: ./scripts/run.sh
set -euo pipefail

world="${1:?usage: import_and_bake.sh <world_vN_dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
valley="$(cd "$here/../.." && pwd)"

[ -f "$world/bake_manifest.json" ] \
	|| { echo "no bake_manifest.json in $world — not a Strata world_vN export" >&2; exit 1; }

echo "== import $world → baked tile + biomes + sea level (direct) =="
STRATA_WORLD="$world" godot --headless --path "$valley" -s res://tools/strata/import_world.gd

echo
echo "done — the Strata world is live, exactly as baked. Walk it:  ./scripts/run.sh"
