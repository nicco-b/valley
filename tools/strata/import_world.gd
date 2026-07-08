extends SceneTree
## The Loom / Strata importer — consumes a Strata `world_vN/` export
## (height.exr float32 meters + bake_manifest.json) and writes Valley's
## elevation guide (data/world/elevation_guide.exr + guide.json), the
## stage-A source of truth. Then `tests/bake_world.gd` erodes it into the
## live painted tile like any painted guide. Artifacts flow one way:
## Strata bakes, the game dresses (docs in the strata repo, docs/PLAN.md).
##
##   STRATA_WORLD=/path/to/world_v1 godot --headless --path . -s res://tools/strata/import_world.gd
##
## GUIDE_OUT (optional) redirects output — verify into a scratch dir
## without touching the real guide. Integrity: height.exr must match the
## manifest's sha256 or the import refuses.

const GUIDE_RES := 1024
const GUIDE_GAMMA := 0.5
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
	var out_dir: String = OS.get_environment("GUIDE_OUT")
	if out_dir.is_empty():
		out_dir = ProjectSettings.globalize_path("res://data/world")

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

	# --- load meters ---
	var img := Image.load_from_file(exr_path)
	if img == null:
		push_error("could not load %s" % exr_path)
		quit(1)
		return
	img.convert(Image.FORMAT_RF)
	var world: Dictionary = manifest.get("world", {})
	var size_m: Array = world.get("size_m", [2048.0, 2048.0])
	var world_size := maxf(float(size_m[0]), float(size_m[1]))
	var sea_level := float(world.get("sea_level_m", 0.0))

	# --- meter range for the guide's gamma encoding (small margin so the
	# curve never clips the extremes) ---
	var data := img.get_data().to_float32_array()
	var gmin := INF
	var gmax := -INF
	for h in data:
		gmin = minf(gmin, h)
		gmax = maxf(gmax, h)
	var margin := maxf((gmax - gmin) * 0.02, 1.0)
	gmin -= margin
	gmax += margin

	# --- meters -> normalized guide (inverse of WorldBake.bake's mapping) ---
	var gspan := gmax - gmin
	for i in data.size():
		data[i] = pow(clampf((data[i] - gmin) / gspan, 0.0, 1.0), GUIDE_GAMMA)
	var guide := Image.create_from_data(img.get_width(), img.get_height(),
		false, Image.FORMAT_RF, PackedFloat32Array(data).to_byte_array())
	guide.resize(GUIDE_RES, GUIDE_RES, Image.INTERPOLATE_LANCZOS)

	# --- write guide EXR + companion JSON ---
	DirAccess.make_dir_recursive_absolute(out_dir)
	var exr_out := out_dir.path_join("elevation_guide.exr")
	var err := guide.save_exr(exr_out, true)
	if err != OK:
		push_error("save_exr failed: %s" % err)
		quit(1)
		return
	var meta := {
		"guide_gamma": GUIDE_GAMMA,
		"guide_min": gmin,
		"guide_max": gmax,
		"origin": {"x": -world_size * 0.5, "z": -world_size * 0.5},
		"out_res": 2048,
		"params": WorldBake.meta().get("params", {}),
		"sea_level_hint": sea_level,
		"seed": int(manifest.get("seed", 7)),
		"strata": {
			"name": manifest.get("name", ""),
			"param_hash": manifest.get("param_hash", ""),
			"source": world_dir,
		},
		"world_size": world_size,
	}
	# --- dressed layers: Strata's climate-driven biome map + layer index ---
	var biome_ok := _import_biomes(world_dir, out_dir, manifest)
	meta["biomes"] = {"imported": biome_ok, "res": BIOME_RES,
		"origin": {"x": -world_size * 0.5, "z": -world_size * 0.5}, "world_size": world_size}
	meta["strata_layers"] = _layer_index(world_dir, manifest)

	# Sync the game sea to Strata's sea level so the shallows read as water, not
	# land (skipped when importing to a scratch GUIDE_OUT).
	if OS.get_environment("GUIDE_OUT").is_empty():
		_sync_sea_level(sea_level)

	var f := FileAccess.open(out_dir.path_join("guide.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t", true) + "\n")
	f.close()
	print("IMPORTED %s -> %s" % [manifest.get("name", "?"), out_dir])
	print("  guide %dx%d, %.1f..%.1fm over %.0fm world, seed %d" % [
		GUIDE_RES, GUIDE_RES, gmin, gmax, world_size, int(manifest.get("seed", 7))])
	if biome_ok:
		print("  biome_map %dx%d painted from Strata biomes" % [BIOME_RES, BIOME_RES])
	print("  next: godot --headless --path . -s res://tests/bake_world.gd")
	quit()


## Set the game's sea surface (data/water/sea.json) to Strata's sea level, so a
## point below it reads as sea. Without this the shallows sit above the old sea
## height and render as land.
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


## Paint data/world/biome_map.png from Strata's biome.png, remapping Strata
## biome ids to Valley palette inks (biomes.json). Returns false (and leaves any
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


## Record which dressed layers this export carries, so game systems (and future
## importers) can discover them without re-reading the manifest.
func _layer_index(world_dir: String, manifest: Dictionary) -> Dictionary:
	var out := {}
	for file: String in (manifest.get("files", {}) as Dictionary).keys():
		out[file] = world_dir.path_join(file)
	return out
