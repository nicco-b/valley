extends SceneTree
## Map generator (the source-of-truth path): compose the committed SKETCH
## file (data/world/sketch.json — a land outline + typed elevation stamps)
## into the elevation guide via LandformGen, then erode it into the world
## through the SAME WorldBake path the painted guide uses. Authoring is
## FILE-driven — edit sketch.json (or paint the guide EXR directly) and
## run this; the world is generated offline, no in-game map drawing.
##   godot --headless --path . -s res://tests/gen_world.gd
func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	if t.kernel == null:
		print("GEN FAIL: native kernel required"); quit(); return
	var meta: Dictionary = WorldBake.meta()
	var sketch: Dictionary = WorldBake.load_sketch()
	var t0 := Time.get_ticks_msec()
	var out: Dictionary = WorldBake.generate(sketch, meta, t.kernel)
	WorldBake.save_guide(out.guide)
	WorldBake.write_tile(out.baked, meta)
	print("GEN OK: composed %d stamps, eroded in %d ms → guide + tile" % [
		(sketch.get("stamps", []) as Array).size(), Time.get_ticks_msec() - t0])
	quit()
