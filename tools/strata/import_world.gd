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
	var f := FileAccess.open(out_dir.path_join("guide.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t", true) + "\n")
	f.close()
	print("IMPORTED %s -> %s" % [manifest.get("name", "?"), out_dir])
	print("  guide %dx%d, %.1f..%.1fm over %.0fm world, seed %d" % [
		GUIDE_RES, GUIDE_RES, gmin, gmax, world_size, int(manifest.get("seed", 7))])
	print("  next: godot --headless --path . -s res://tests/bake_world.gd")
	quit()
