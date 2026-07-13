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

# == the adopt prebake (adopt-time hydrology rebuild, 2026-07-13) ==
# Boot-loads-never-computes, extended to ADOPT: the in-session bless used to
# hand the game a world whose sea/lake bathymetry, catchments, and tier-2
# water base all recomputed IN-GAME (up to ~2 min of a blocked frame loop on
# big worlds). This pass boots the GAME ITSELF headless once, right here at
# bless time, with STRATA_PREBAKE=1 — the game's own kernels produce the
# cache blobs (bit-identical by construction; no reimplementation anywhere)
# through BathyCache / CatchmentCache / WaterFieldCache, content-keyed to
# the records just imported above. The run quits itself when every bake has
# landed. The adopt that follows LOADS; any genuinely stale entry still
# refuses on its own sha and recomputes loudly (the accelerator law).
# Isolated HOME so user:// (saves) is never touched; the cache blobs are
# res://data/water/* — project-side, exactly where the live boot reads.
# Best-effort: a failed prebake only costs the old in-game compute, never a
# wrong world, so it warns instead of failing the bless. The --quit-after
# frame count is a backstop only (headless frames are cheap and fast) — the
# run quits ITSELF via Prebake.maybe_finish long before it.
echo
echo "== prebake adopt caches (bathy + catchments + water-field base) =="
prebake_home="$(mktemp -d)"
if ! STRATA_PREBAKE=1 HOME="$prebake_home" \
		godot --headless --path "$valley" --quit-after 2000000 2>&1 \
		| grep -E '^\[(prebake|water|hydrology)\] '; then
	echo "prebake did not complete — the adopt will compute in-game (slower, never wrong)" >&2
fi
rm -rf "$prebake_home"

echo
echo "done — the Strata world is live, exactly as baked. Walk it:  ./scripts/run.sh"
