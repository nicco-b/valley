extends SceneTree
## Map pipeline: derive a PAINTABLE elevation guide from the current
## procedural world — 1024px over ±8.2km (16m/px), NORMALIZED 0..1
## (0 = guide_min deep sea, 1 = guide_max peak) so it opens as a normal
## grayscale heightmap you can paint in any editor. The meter range
## lives in guide.json; the bake maps 0..1 back to meters. This makes
## the live archipelago the pipeline's first painting.
## Run: godot --headless --path . -s res://tests/derive_guide.gd
const RES := 1024
const HALF := 8192.0
# Fixed meter range the 0..1 grayscale spans. Paint white for +GUIDE_MAX,
# black for GUIDE_MIN; edit these in guide.json to raise the ceiling.
const GUIDE_MIN := -60.0
const GUIDE_MAX := 1000.0
# Store with a gamma curve so the common 50-300m terrain spreads across
# the tonal range instead of crushing into darks under the 950m range.
# The bake inverts it (pow 1/GAMMA) to recover linear meters.
const GUIDE_GAMMA := 0.5


func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	var step := HALF * 2.0 / RES
	var img := Image.create(RES, RES, false, Image.FORMAT_RF)
	var block: PackedFloat32Array = t.height_block(
		-HALF + step * 0.5, -HALF + step * 0.5, step, RES, RES)
	var span := GUIDE_MAX - GUIDE_MIN
	for pz in RES:
		for px in RES:
			var lin := clampf((block[pz * RES + px] - GUIDE_MIN) / span, 0.0, 1.0)
			var norm := pow(lin, GUIDE_GAMMA)  # lift mid-elevations for painting
			img.set_pixel(px, pz, Color(norm, norm, norm))  # grayscale, paintable
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://data/world"))
	img.save_exr(ProjectSettings.globalize_path(
		"res://data/world/elevation_guide.exr"), true)  # grayscale EXR
	var meta := {"world_size": HALF * 2.0, "origin": {"x": -HALF, "z": -HALF},
		"out_res": 2048, "seed": 7,
		"guide_min": GUIDE_MIN, "guide_max": GUIDE_MAX, "guide_gamma": GUIDE_GAMMA,
		"params": {
			"detail_amp": 12.0, "detail_freq": 0.0025, "sea_level": -2.0,
			"talus_passes": 24, "talus_tan": 0.9, "droplets": 400000,
			"capacity": 3.2, "erosion": 0.28, "deposition": 0.28}}
	var f := FileAccess.open("res://data/world/guide.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t") + "\n")
	f.close()
	print("GUIDE WRITTEN data/world/elevation_guide.exr (%dpx, %.0fm/px, %.0f..%.0fm as 0..1)" % [
		RES, step, GUIDE_MIN, GUIDE_MAX])
	quit()
