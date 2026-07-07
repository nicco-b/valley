#!/usr/bin/env bash
# bake-and-walk — the full Strata → Valley round trip.
#
#   tools/strata/bake_and_walk.sh
#
# Bakes the game-sized Strata valley (tools/strata/valley.strata, a 16384m
# world matched to the game frame) into a world_vN/ export, imports it into
# Valley's elevation guide + biome map, then bakes the live painted terrain.
# When it finishes, walk it: ./scripts/run.sh
#
# Env:  STRATA_REPO (default ~/code/strata) · RES (bake resolution, default
#       2048) · WORLD_OUT (export dir, default /tmp/valley_world_v1) ·
#       GUIDE_OUT (import target; default res://data/world — set a scratch
#       dir to preview without touching the real guide).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
valley="$(cd "$here/../.." && pwd)"
strata="${STRATA_REPO:-$HOME/code/strata}"
doc="$here/valley.strata"
world="${WORLD_OUT:-/tmp/valley_world_v1}"
res="${RES:-2048}"

[ -f "$doc" ] || { echo "missing $doc" >&2; exit 1; }
[ -d "$strata" ] || { echo "Strata repo not found at $strata (set STRATA_REPO)" >&2; exit 1; }

echo "== 1/4  build Strata CLI =="
( cd "$strata" && swift build -c release )
cli="$strata/.build/release/strata-cli"

echo "== 2/4  bake $doc → $world (res $res) =="
"$cli" bake "$doc" --res "$res" --out "$world/"

echo "== 3/4  import into Valley (guide + biome map) =="
STRATA_WORLD="$world" godot --headless --path "$valley" -s res://tools/strata/import_world.gd

echo "== 4/4  bake the live terrain from the guide =="
godot --headless --path "$valley" -s res://tests/bake_world.gd

echo
echo "done — the Strata valley is live. Walk it:  ./scripts/run.sh"
