extends SceneTree
## Map pipeline: derive an elevation GUIDE from the current procedural
## world — 1024px over ±8.2km (16m/px), saved as EXR meters. This makes
## the live archipelago the pipeline's first "painting": repaint any of
## it in an image editor, rebake, fly it. Writes data/world/
## elevation_guide.exr + guide.json (bake settings).
## Run: godot --headless --path . -s res://tests/derive_guide.gd
const RES := 1024
const HALF := 8192.0


func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	var step := HALF * 2.0 / RES
	var img := Image.create(RES, RES, false, Image.FORMAT_RF)
	var block: PackedFloat32Array = t.height_block(
		-HALF + step * 0.5, -HALF + step * 0.5, step, RES, RES)
	for pz in RES:
		for px in RES:
			img.set_pixel(px, pz, Color(block[pz * RES + px], 0, 0))
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://data/world"))
	img.save_exr(ProjectSettings.globalize_path("res://data/world/elevation_guide.exr"))
	var meta := {"world_size": HALF * 2.0, "origin": {"x": -HALF, "z": -HALF},
		"out_res": 2048, "seed": 7, "params": {
			"detail_amp": 12.0, "detail_freq": 0.0025, "sea_level": -2.0,
			"talus_passes": 24, "talus_tan": 0.9, "droplets": 400000,
			"capacity": 3.2, "erosion": 0.28, "deposition": 0.28}}
	var f := FileAccess.open("res://data/world/guide.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t") + "\n")
	f.close()
	print("GUIDE WRITTEN data/world/elevation_guide.exr (%dpx, %.0fm/px)" % [
		RES, step])
	quit()
