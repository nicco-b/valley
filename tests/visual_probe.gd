extends Node
## Visual probe (dev-only, not in test.sh): boots the real valley,
## stamps a synthetic walked trail, waits for the deformation ring and
## trace to settle, and saves screenshots to disk so a session can SEE
## what a change looks like instead of guessing. Run:
##   godot res://tests/visual_probe.tscn
## Writes /tmp/valley_probe_*.png and quits.

const OUT := "/tmp/valley_probe"

var _world: Node


func _ready() -> void:
	_world = load("res://game/world/valley.tscn").instantiate()
	add_child(_world)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player")
	# Open flat sand, afternoon light, calm wind so prints persist.
	player.global_position = Vector3(30.0, Terrain.height(30.0, -80.0) + 1.0, -80.0)
	GameClock.hours = 15.0
	GameClock.time_scale = 0.0  # hold the light still
	Weather.state = "calm"
	Weather.wind = 0.1
	Climate.wetness = 0.0
	# Give the streamer time to build the dense ring around the new spot.
	for i in 90:
		await get_tree().process_frame
	var streamer: Node3D = get_tree().get_first_node_in_group("world_streamer")
	print("[probe] center cell res: ", streamer._terrain_res.get(Vector2i(0, -1), 0))
	var cell: Node = streamer._terrain.get(Vector2i(0, -1))
	if cell:
		print("[probe] cell visible=%s in_tree=%s children=%d pos=%s" % [
			cell.visible, cell.is_inside_tree(), cell.get_child_count(), cell.position])
		var mi: MeshInstance3D = streamer._mesh_instances.get(Vector2i(0, -1))
		if mi and is_instance_valid(mi):
			print("[probe] mesh surfaces=%d aabb=%s visible=%s" % [
				mi.mesh.get_surface_count(), mi.get_aabb(), mi.visible])
			print("[probe] mesh material=%s" % mi.mesh.surface_get_material(0))
	else:
		print("[probe] CENTER CELL BODY MISSING")
	# A walked S-curve behind the player, stamped at the player's real
	# 0.7m stride so the probe shows what walking actually produces.
	for i in 45:
		var t := float(i) * 0.5
		var pos := Vector2(30.0 - t * 0.85, -80.0 - sin(t * 0.35) * 3.0 - t * 0.4)
		InteractionField.stamp(pos, 1.0)
	for i in 40:
		await get_tree().process_frame
	# Verify the stamps landed in the trace texture at a known point.
	var probe_pt := Vector2(30.0 - 7.0, -80.0 - sin(7.0 * 0.35 / 0.35) * 3.0)
	var f := InteractionField
	var uv := (Vector2(25.0, -84.0) - f._anchor) * (f.TEX_SIZE / f.REGION_SIZE) \
			+ Vector2.ONE * (f.TEX_SIZE * 0.5)
	print("[probe] anchor=%s stamp uv=%s trace px=%.3f" % [f._anchor, uv,
		f._image.get_pixel(int(uv.x), int(uv.y)).r])
	# Marker sphere at a trail point so the shot orients itself.
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	marker.mesh = sphere
	add_child(marker)
	marker.global_position = Vector3(25.0, Terrain.height(25.0, -84.0) + 0.3, -84.0)
	_shot("trail")
	# Straight-down close view of the trail: displacement or bust.
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(25.0, Terrain.height(25.0, -84.0) + 9.0, -80.0)
	cam.look_at(Vector3(25.0, 0.0, -84.5))
	cam.make_current()
	for i in 10:
		await get_tree().process_frame
	_shot("topdown")
	# Play-camera framing: behind and above, looking along the trail —
	# the read that actually matters. Shot in BOTH lights: hard afternoon
	# sun (flattering) and soft hazy morning (the one that exposed the
	# smear) — the trail must read in each.
	cam.global_position = Vector3(32.0, Terrain.height(32.0, -78.0) + 2.4, -78.0)
	cam.look_at(Vector3(20.0, 0.0, -87.0))
	for i in 5:
		await get_tree().process_frame
	_shot("playcam")
	var span := GameClock.daylight_span()
	GameClock.hours = span.x + 2.5  # soft mid-morning sun
	Weather.state = "windy"
	Weather.wind = 0.55  # haze, and the wind that erases
	for i in 20:
		await get_tree().process_frame
	_shot("playcam_soft")
	get_tree().quit(0)


func _shot(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [OUT, label])
	print("[probe] wrote %s_%s.png" % [OUT, label])
