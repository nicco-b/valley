extends SceneTree
## The Loom / Strata importer — the P0 seam fix (strata ONE_APP.md,
## 2026-07-07): a Strata `world_vN/` export IS the world. height.exr
## (float32 meters, sha256-verified against bake_manifest.json) is copied
## BYTE-IDENTICAL to the baked-tile cache — no guide roundtrip, no droplet
## re-erosion, no detail noise on top. What Strata bakes is what you walk:
## mesa rims, terraces, and stylize survive. Also imports Strata's biome
## map and syncs the game's sea level from the manifest (the single
## sea-level source). Artifacts still flow one way: Strata bakes, the game
## dresses; in-game pens land on Terrain's OVERRIDE layer, never the tile.
##
##   STRATA_WORLD=/path/to/world_v1 godot --headless --path . -s res://tools/strata/import_world.gd
##
## TILE_OUT (optional) redirects every output into a scratch dir — verify
## an export without touching the live tile, biome map, or sea level.

const TILE_EXR := "res://data/terrain/tiles/baked_world.exr"
const TILE_REC := "res://data/regions/baked_world.json"
const BIOME_RES := 1024

## Strata biome id → Valley palette index (biomes.json order). Strata:
## 0 sea 1 strand 2 marsh 3 dune 4 meadow 5 forest 6 heath 7 alpine 8 snow
## 9 scree.  Valley: 0 deep_sea 1 strand 2 dune_desert 3 scrub 4 oasis_green
## 5 wetland 6 volcanic_rock 7 bare_peak.
const STRATA_TO_VALLEY := [0, 1, 5, 2, 4, 4, 3, 3, 7, 6]


func _init() -> void:
	var world_dir: String = OS.get_environment("STRATA_WORLD")
	if world_dir.is_empty():
		push_error("STRATA_WORLD not set (path to a Strata world_vN/ export)")
		quit(1)
		return
	var out_dir: String = OS.get_environment("TILE_OUT")
	var scratch := not out_dir.is_empty()

	# --- manifest + integrity ---
	var manifest_text := FileAccess.get_file_as_string(world_dir.path_join("bake_manifest.json"))
	if manifest_text.is_empty():
		push_error("no bake_manifest.json in %s" % world_dir)
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(manifest_text)
	var exr_path := world_dir.path_join("height.exr")
	var want_sha: String = manifest.get("files", {}).get("height.exr", "")
	var got_sha := FileAccess.get_sha256(exr_path)
	if want_sha != got_sha:
		push_error("height.exr sha256 mismatch (manifest %s, file %s) — refusing" % [want_sha, got_sha])
		quit(1)
		return

	# --- validate the heightfield (and report its range) ---
	var img := Image.load_from_file(exr_path)
	if img == null or img.is_empty():
		push_error("could not load %s" % exr_path)
		quit(1)
		return
	if img.get_width() != img.get_height():
		push_error("height.exr must be square (got %dx%d)" % [img.get_width(), img.get_height()])
		quit(1)
		return
	img.convert(Image.FORMAT_RF)
	var data := img.get_data().to_float32_array()
	var hmin := INF
	var hmax := -INF
	for h in data:
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)

	var world: Dictionary = manifest.get("world", {})
	var size_m: Array = world.get("size_m", [2048.0, 2048.0])
	var world_size := maxf(float(size_m[0]), float(size_m[1]))
	var sea_level := float(world.get("sea_level_m", 0.0))

	# --- the blessed tile: byte-identical copy, so the manifest sha keeps
	# verifying the live cache forever ---
	var tile_abs := ProjectSettings.globalize_path(TILE_EXR) if not scratch \
			else out_dir.path_join("baked_world.exr")
	var rec_path := TILE_REC if not scratch else out_dir.path_join("baked_world.json")
	DirAccess.make_dir_recursive_absolute(tile_abs.get_base_dir())
	var err := DirAccess.copy_absolute(exr_path, tile_abs)
	if err != OK:
		push_error("copy height.exr -> %s failed: %s" % [tile_abs, err])
		quit(1)
		return

	# --- the F3 region record (heightmap already in meters: hmin 0, hmax 1
	# keep the pixel = the height) + provenance for the Toolkit/registry ---
	var rec := {"id": "baked_world", "layer": "surface", "kind": "tile",
		"origin": {"x": -world_size * 0.5, "z": -world_size * 0.5},
		"size": world_size, "feather": 600,
		"heightmap": TILE_EXR if not scratch else tile_abs,
		"height_min": 0.0, "height_max": 1.0,
		"sea_level": sea_level,
		"strata": {
			"name": manifest.get("name", ""),
			"param_hash": manifest.get("param_hash", ""),
			"source": world_dir,
			"date": manifest.get("date", ""),
			"seed": int(manifest.get("seed", 0)),
			"height_sha256": got_sha,
		}}
	var f := FileAccess.open(rec_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rec, "\t", true) + "\n")
	f.close()

	# --- dressed layers: Strata's climate-driven biome map ---
	var biome_out := ProjectSettings.globalize_path("res://data/world") if not scratch \
			else out_dir
	var biome_ok := _import_biomes(world_dir, biome_out, manifest)

	# Sync the game sea to the manifest's sea level (the ONE sea-level
	# source) so the shallows read as water, not land.
	if not scratch:
		_sync_sea_level(sea_level)

	print("IMPORTED %s -> %s (direct, no re-erosion)" % [
		manifest.get("name", "?"), tile_abs])
	print("  tile %dx%d, %.1f..%.1fm over %.0fm world, sea %.1fm, sha %s…" % [
		img.get_width(), img.get_height(), hmin, hmax, world_size,
		sea_level, got_sha.substr(0, 12)])
	if biome_ok:
		print("  biome_map %dx%d painted from Strata biomes" % [BIOME_RES, BIOME_RES])
	if absf(world_size - 16384.0) > 0.5:
		push_warning("world size %.0fm != 16384m — the biome frame in terrain.gd is hardcoded to 16384m" % world_size)
	print("  the world is live (running game hot-reloads the tile). Walk it: ./scripts/run.sh")
	quit()


## Set the game's sea surface (data/water/sea.json) to the manifest's sea
## level, so a point below it reads as sea. Without this the shallows sit
## above the old sea height and render as land.
func _sync_sea_level(sea_level: float) -> void:
	var path := "res://data/water/sea.json"
	var rec := {"id": "sea", "sea": true, "surface": sea_level}
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			rec = d
			rec["surface"] = sea_level
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rec, "\t", true) + "\n")
	f.close()
	print("  sea level synced to %.1fm" % sea_level)


## Paint biome_map.png from Strata's biome.png, remapping Strata biome ids
## to Valley palette inks (biomes.json). Returns false (and leaves any
## existing map untouched) when the export carries no biome layer.
func _import_biomes(world_dir: String, out_dir: String, manifest: Dictionary) -> bool:
	var biome_path := world_dir.path_join("biome.png")
	if not FileAccess.file_exists(biome_path):
		return false
	var want: String = manifest.get("files", {}).get("biome.png", "")
	if not want.is_empty() and FileAccess.get_sha256(biome_path) != want:
		push_error("biome.png sha256 mismatch — refusing")
		return false

	# Valley palette inks (paint colour per biome index).
	var pal: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/world/biomes.json"))
	if not (pal is Dictionary and pal.has("biomes")):
		push_error("no data/world/biomes.json palette to paint against")
		return false
	var inks: Array = []
	for b: Variant in pal["biomes"]:
		var c: Array = b["ink"]
		inks.append(Color(c[0], c[1], c[2]))

	# Strata biome.png stores the id directly as the grey byte (0..N).
	var bimg := Image.load_from_file(biome_path)
	if bimg == null:
		return false
	bimg.convert(Image.FORMAT_R8)
	var ids := bimg.get_data()  # one byte per pixel = Strata biome id
	var bw := bimg.get_width()
	var bh := bimg.get_height()
	var painted := Image.create(bw, bh, false, Image.FORMAT_RGB8)
	for z in bh:
		for x in bw:
			var sid := int(ids[z * bw + x])
			var vidx: int = STRATA_TO_VALLEY[sid] if sid < STRATA_TO_VALLEY.size() else 3
			painted.set_pixel(x, z, inks[clampi(vidx, 0, inks.size() - 1)])
	if bw != BIOME_RES or bh != BIOME_RES:
		painted.resize(BIOME_RES, BIOME_RES, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var err := painted.save_png(out_dir.path_join("biome_map.png"))
	if err != OK:
		push_error("save biome_map.png failed: %s" % err)
		return false
	return true
