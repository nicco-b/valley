#!/usr/bin/env bash
# bake-and-walk — the full Strata → Valley round trip from the committed doc.
#
#   tools/strata/bake_and_walk.sh [doc.strata]
#
# Builds the Strata CLI, bakes a .strata doc (default tools/strata/valley.strata,
# a 16384m world matched to the game frame) into a world_vN/ export, then imports
# it DIRECTLY as the live tile (via import_and_bake.sh — P0 seam fix: what
# Strata bakes is what you walk, no re-erosion). Walk it: ./scripts/run.sh
#
# To bake what you've tuned in the Strata APP instead, use its Export World (⌘E)
# and run:  tools/strata/import_and_bake.sh <exported world_vN dir>
#
# Env:  STRATA_REPO (default ~/code/strata) · RES (bake resolution, default
#       2048) · WORLD_OUT (export dir, default /tmp/valley_world_v1).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
strata="${STRATA_REPO:-$HOME/code/strata}"
doc="${1:-$here/valley.strata}"
world="${WORLD_OUT:-/tmp/valley_world_v1}"
res="${RES:-2048}"

[ -f "$doc" ] || { echo "missing doc: $doc" >&2; exit 1; }
[ -d "$strata" ] || { echo "Strata repo not found at $strata (set STRATA_REPO)" >&2; exit 1; }

echo "== build Strata CLI =="
( cd "$strata" && swift build -c release )

echo "== bake $doc → $world (res $res) =="
"$strata/.build/release/strata-cli" bake "$doc" --res "$res" --out "$world/"

exec "$here/import_and_bake.sh" "$world"
