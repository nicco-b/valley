extends SceneTree
## Map pipeline: BAKE the painted elevation guide into believable
## terrain — kernel-side fractal relief + thermal talus + hydraulic
## droplet erosion (coherent drainage, fans, sediment), then write the
## result as an F3 painted-tile record covering the world. The baked
## EXR + record are LOCAL CACHE (gitignored): the guide is the source
## of truth; a missing bake just means the procedural records show
## through until you run this.
##   godot --headless --path . -s res://tests/bake_world.gd
## The running game hot-reloads the tile when the bake lands.
func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	if t.kernel == null:
		print("BAKE FAIL: native kernel required")
		quit()
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/world/guide.json"))
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		"res://data/world/elevation_guide.exr"))
	img.convert(Image.FORMAT_RF)
	# The guide is normalized 0..1 grayscale (paintable); map it back to
	# meters via the range in guide.json before the meter-native bake.
	var gmin := float(meta.get("guide_min", -60.0))
	var gspan := float(meta.get("guide_max", 1000.0)) - gmin
	var inv_gamma := 1.0 / float(meta.get("guide_gamma", 1.0))
	var guide := img.get_data().to_float32_array()
	for i in guide.size():
		guide[i] = gmin + pow(clampf(guide[i], 0.0, 1.0), inv_gamma) * gspan
	var t0 := Time.get_ticks_msec()
	var baked: PackedFloat32Array = t.kernel.bake_terrain(
		guide, img.get_width(), float(meta.world_size),
		int(meta.out_res), int(meta.seed), meta.params)
	print("bake: %d ms (%d droplets on %d^2)" % [Time.get_ticks_msec() - t0,
		int(meta.params.droplets), int(meta.out_res)])
	var res := int(meta.out_res)
	var out := Image.create(res, res, false, Image.FORMAT_RF)
	for pz in res:
		for px in res:
			out.set_pixel(px, pz, Color(baked[pz * res + px], 0, 0))
	out.save_exr(ProjectSettings.globalize_path(
		"res://data/terrain/tiles/baked_world.exr"))
	var rec := {"id": "baked_world", "layer": "surface", "kind": "tile",
		"origin": meta.origin, "size": meta.world_size, "feather": 600,
		"heightmap": "res://data/terrain/tiles/baked_world.exr",
		"height_min": 0.0, "height_max": 1.0}
	var f := FileAccess.open("res://data/regions/baked_world.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rec, "\t") + "\n")
	f.close()
	print("BAKE WRITTEN data/terrain/tiles/baked_world.exr + region record")
	quit()
