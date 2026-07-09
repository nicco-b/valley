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

## Largest-first lake cap: Strata's solver reports EVERY filled depression
## over its min_lake_area_m2 (an eroded 16km world holds hundreds), but
## every water body sits in Terrain's per-sample loops (height carve,
## water_surface) — records are a budget, not a survey. Rivers arrive
## pre-capped by the doc's max_rivers.
const LAKE_MAX := 24


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

	# --- the frame contract: the export must match the game's world frame
	# (Terrain.WORLD_FRAME_M — the biome map, streamer budgets, and far
	# sheet are all framed to it). A mismatched export lands as garbage
	# ground (misregistered biomes over a tile the frame doesn't cover) —
	# refuse loudly BEFORE anything is written, with both sizes named.
	var game_frame := float(load("res://game/world/terrain.gd").WORLD_FRAME_M)
	if absf(world_size - game_frame) > 0.5:
		push_error(("world size mismatch: export '%s' is %.0fm, the game's " +
			"world frame is %.0fm — refusing (re-bake the Strata doc at " +
			"%.0fm, or change Terrain.WORLD_FRAME_M if the game's frame " +
			"really moved)") % [String(manifest.get("name", "?")), world_size,
			game_frame, game_frame])
		quit(1)
		return

	# --- the blessed tile: byte-identical copy, so the manifest sha keeps
	# verifying the live cache forever ---
	var tile_abs := ProjectSettings.globalize_path(TILE_EXR) if not scratch \
			else out_dir.path_join("baked_world.exr")
	var rec_path := TILE_REC if not scratch else out_dir.path_join("baked_world.json")
	DirAccess.make_dir_recursive_absolute(tile_abs.get_base_dir())
	# data/regions/ can be absent on a fresh clone (every record in it is
	# gitignored cache) — FileAccess.open(WRITE) never creates directories.
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(rec_path.get_base_dir()))
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

	# --- hydrology (ONE_APP P2): Strata's water analysis becomes real
	# water records — rivers, lakes, waterfalls ---
	var water_out := ProjectSettings.globalize_path("res://data/water") if not scratch \
			else out_dir
	var hydro_counts := _import_hydrology(world_dir, water_out, manifest)

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
	if hydro_counts.x >= 0:
		print("  hydrology: %d rivers, %d lakes, %d waterfalls as water records" % [
			hydro_counts.x, hydro_counts.y, hydro_counts.z])
	else:
		print("  no hydrology.json (pre-P2 export) — water records cleared, world loads as before")
	print("  the world is live (running game hot-reloads the tile). Walk it: ./scripts/run.sh")

	# --- the completion stamp (strata post-bless atomicity) ---
	# Written LAST — after every data/ write above and this headless run's
	# own resource reimport — so it can only exist when the importer ran to
	# COMPLETION for THIS world on THIS checkout. Strata reads it at
	# project-open: a stamp that is missing or names a different world means
	# a bless was interrupted (quit / SIGKILL before the import finished, or
	# a half-written .godot cache), leaving terrain + water absent until
	# Godot rebuilds — the "quit and reopen twice" symptom. Strata re-runs
	# this importer before booting the pane when the stamp doesn't match, so
	# ONE relaunch always finds a complete checkout. Local cache, gitignored
	# beside the baked tile it certifies. Skipped on a scratch/verify run
	# (TILE_OUT) — that never touches the live checkout.
	if not scratch:
		_write_import_stamp(world_dir, got_sha, world_size, sea_level, manifest)

	quit()


## The importer's completion marker (data/strata_import.json). Records the
## blessed world's identity — height_sha256 is the fingerprint Strata
## compares against its world registry's canon entry; the rest is
## provenance for anyone reading the checkout by hand.
func _write_import_stamp(world_dir: String, height_sha: String, world_frame_m: float,
		sea_level: float, manifest: Dictionary) -> void:
	var stamp := {
		"schema": 1,
		"height_sha256": height_sha,
		"name": manifest.get("name", ""),
		"param_hash": manifest.get("param_hash", ""),
		"date": manifest.get("date", ""),
		"source": world_dir,
		"world_frame_m": world_frame_m,
		"sea_level_m": sea_level,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
	var f := FileAccess.open("res://data/strata_import.json", FileAccess.WRITE)
	if f == null:
		push_error("cannot write import stamp res://data/strata_import.json")
		return
	f.store_string(JSON.stringify(stamp, "\t", true) + "\n")
	f.close()
	print("  import stamp: data/strata_import.json (sha %s…)" % height_sha.substr(0, 12))


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


## Strata's hydrology stage (ONE_APP P2) → real water records. The export's
## hydrology.json carries priority-flood lakes, D8 rivers (width∝discharge,
## nodes already in the height.exr frame = game world meters), and
## hardness-biased knickpoint waterfalls. Rivers land as no_sim records in
## rivers/hyd_*.json (Hydrology's REGION tier breathes them off the real
## catchment, exactly like the retired propose_rivers gen_*.json cache);
## lakes as hyd_*.json lake records at their fill elevation — basin depth 0
## because the depression is already IN the tile (the solver found it, it
## never carved it). Waterfalls ride the river record; water_bodies foams
## them. Stale hyd_* records from a previous import are cleared first so
## the water always matches the tile beside it — a pre-P2 export (no
## hydrology.json) just clears and returns (-1,-1,-1): the world loads
## exactly as today. Returns (rivers, lakes, waterfalls) written.
func _import_hydrology(world_dir: String, out_dir: String, manifest: Dictionary) -> Vector3i:
	# Records match the tile, or they don't exist.
	_clear_hyd_records(out_dir)
	_clear_hyd_records(out_dir.path_join("rivers"))
	var hydro_path := world_dir.path_join("hydrology.json")
	if not FileAccess.file_exists(hydro_path):
		return Vector3i(-1, -1, -1)
	var want: String = manifest.get("files", {}).get("hydrology.json", "")
	if not want.is_empty() and FileAccess.get_sha256(hydro_path) != want:
		push_error("hydrology.json sha256 mismatch — refusing")
		return Vector3i(-1, -1, -1)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(hydro_path))
	if not (parsed is Dictionary and parsed.has("rivers")):
		push_error("bad hydrology.json (needs rivers)")
		return Vector3i(-1, -1, -1)
	var hydro: Dictionary = parsed

	DirAccess.make_dir_recursive_absolute(out_dir.path_join("rivers"))
	var falls_total := 0
	var rivers: Array = hydro.get("rivers", [])
	for r: Dictionary in rivers:
		var nodes: Array = r.get("nodes", [])
		if nodes.size() < 2:
			continue
		# Channel depth/feather from the river's size (the solver emits
		# width∝√discharge; surface == ground, so the carve makes the bed).
		var mean_w := 0.0
		for n: Dictionary in nodes:
			mean_w += float(n["width"])
		mean_w /= nodes.size()
		var falls: Array = r.get("waterfalls", [])
		falls_total += falls.size()
		var rec := {
			"id": "hyd_%s" % String(r.get("id", "r")),
			"no_sim": true,  # the REGION tier breathes it, off the soak digest
			"depth": snappedf(clampf(0.5 + 0.12 * mean_w, 1.0, 3.0), 0.01),
			"feather": snappedf(clampf(mean_w * 0.5, 4.0, 12.0), 0.1),
			"catchment_m2": float(r.get("catchment_m2", 0.0)),
			"nodes": nodes,
			"waterfalls": falls,
			"source": "strata_hydrology",
		}
		_write_json(out_dir.path_join("rivers/%s.json" % rec["id"]), rec)

	# Lakes come sorted by descending area — keep the LAKE_MAX biggest.
	var lakes: Array = hydro.get("lakes", [])
	var skipped := lakes.size() - mini(lakes.size(), LAKE_MAX)
	lakes = lakes.slice(0, LAKE_MAX)
	if skipped > 0:
		print("  hydrology: kept the %d largest lakes (%d puddles skipped)" % [
			lakes.size(), skipped])
	for l: Dictionary in lakes:
		var rec := {
			"id": "hyd_%s" % String(l.get("id", "l")),
			"no_sim": true,  # region lake: its level stays off the soak digest
			"center": {"x": float(l["x"]), "z": float(l["z"])},
			"radius": float(l["radius"]),
			"surface": float(l["surface"]),
			"depth": float(l.get("depth", 0.0)),  # real max depth (W2 bathymetry)
			# basin depth 0: the tile already holds the depression.
			"basin": {"radius": float(l["radius"]), "depth": 0.0},
			"outlet": "aquifer",
			"source": "strata_hydrology",
		}
		_write_json(out_dir.path_join("%s.json" % rec["id"]), rec)
	return Vector3i(rivers.size(), lakes.size(), falls_total)


## Delete hyd_*.json from one directory (imported-water cache invalidation).
func _clear_hyd_records(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("hyd_") and f.ends_with(".json"):
			dir.remove(f)


func _write_json(path: String, rec: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return
	f.store_string(JSON.stringify(rec, "\t", true) + "\n")
	f.close()


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
