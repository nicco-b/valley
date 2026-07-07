extends SceneTree
## Map generator: compose a SKETCH (data/world/sketch.json) into the
## elevation guide via LandformGen, then erode it into the world through
## the SAME WorldBake path the hand-painter uses. The result is a full
## eroded world from a dozen high-level stamps — no hand-sculpting.
##   godot --headless --path . -s res://tests/gen_world.gd
const GUIDE_RES := 1024


func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	if t.kernel == null:
		print("GEN FAIL: native kernel required"); quit(); return
	var meta: Dictionary = WorldBake.meta()
	var sketch: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/world/sketch.json"))
	var origin := Vector2(float(meta.origin.x), float(meta.origin.z))
	var world_size := float(meta.world_size)

	# Compose the sketch → meters, then normalize to the guide's 0..1
	# (gamma) range so it bakes exactly like a painted guide.
	var meters := LandformGen.compose(sketch, GUIDE_RES, world_size, origin)
	var gmin := float(meta.guide_min)
	var gspan := float(meta.guide_max) - gmin
	var gamma := float(meta.get("guide_gamma", 1.0))
	var img := Image.create(GUIDE_RES, GUIDE_RES, false, Image.FORMAT_RF)
	for pz in GUIDE_RES:
		for px in GUIDE_RES:
			var lin := clampf((meters[pz * GUIDE_RES + px] - gmin) / gspan, 0.0, 1.0)
			img.set_pixel(px, pz, Color(pow(lin, gamma), 0, 0))
	WorldBake.save_guide(img)

	var t0 := Time.get_ticks_msec()
	var baked := WorldBake.bake(img, meta, t.kernel)
	WorldBake.write_tile(baked, meta)
	print("GEN OK: composed %d stamps, eroded in %d ms → guide + tile" % [
		(sketch.get("stamps", []) as Array).size(), Time.get_ticks_msec() - t0])
	quit()
