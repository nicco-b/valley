extends SceneTree
## Map pipeline: BAKE the painted elevation guide into believable
## terrain — kernel-side fractal relief + thermal talus + hydraulic
## droplet erosion (coherent drainage, fans, sediment), then write the
## result as an F3 painted-tile record covering the world. The baked
## EXR + record are LOCAL CACHE (gitignored): the guide is the source
## of truth; a missing bake just means the procedural records show
## through until you run this.
##   godot --headless --path . -s res://tests/bake_world.gd
## The running game hot-reloads the tile when the bake lands — and the
## in-game map painter bakes through the SAME WorldBake path.
func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	if t.kernel == null:
		print("BAKE FAIL: native kernel required")
		quit()
		return
	var meta := WorldBake.meta()
	var guide := WorldBake.load_guide()
	var t0 := Time.get_ticks_msec()
	var baked := WorldBake.bake(guide, meta, t.kernel)
	print("bake: %d ms (%d droplets on %d^2)" % [Time.get_ticks_msec() - t0,
		int(meta["params"]["droplets"]), int(meta["out_res"])])
	WorldBake.write_tile(baked, meta)
	print("BAKE WRITTEN data/terrain/tiles/baked_world.exr + region record")
	quit()
