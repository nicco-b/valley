extends Node
## River-pen probe (dev-only, the Toolkit): drives Terrain.add_river the
## way the map pen does — a hand-drawn course across the range flank —
## and screenshots the carved valley to confirm the basin sculpts live.
## Movie Maker + minimized (region_probe recipe).
##   godot --path . --write-movie /tmp/x.avi --fixed-fps 15 \
##     res://tests/river_pen_probe.tscn

# A course down the volcano flank toward the sea (world XZ).
const COURSE := [
	Vector2(-3400, -3450), Vector2(-3300, -3650), Vector2(-3200, -3850),
	Vector2(-3150, -4050), Vector2(-3120, -4250),
]

var _w: Node
var _t := 0
var _penned := false


func _ready() -> void:
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	if _t == 20:
		GameClock.hours = 14.0
		GameClock.time_scale = 0.0
		Weather.force_kind("calm")
		var we: WorldEnvironment = _w.find_children("*", "WorldEnvironment", true, false)[0]
		we.environment.fog_enabled = false
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			pl.global_position = Vector3(-3250, Terrain.height(-3250, -3750) + 2.0, -3750)
	if _t == 300 and not _penned:
		# Pen the river: densify + surface + monotone clamp, like the map.
		var nodes: Array = []
		var surf := INF
		for i in COURSE.size():
			var p: Vector2 = COURSE[i]
			surf = minf(surf, Terrain.height(p.x, p.y) - 0.3)
			var f := float(i) / float(COURSE.size() - 1)
			nodes.append({"x": p.x, "z": p.y, "width": lerpf(3.0, 11.0, f),
				"surface": surf})
		var rec := {"id": "pen_probe", "no_sim": true, "depth": 1.6,
			"feather": 8.0, "catchment_m2": 200000.0, "nodes": nodes}
		Terrain.add_river(rec)
		print("[pen_probe] river added; carving")
		_penned = true
	if _t == 700:
		var cam := Camera3D.new()
		add_child(cam)
		cam.far = 12000.0
		cam.make_current()
		cam.global_position = Vector3(-3260, Terrain.height(-3260, -3720) + 18.0, -3720)
		cam.look_at(Vector3(-3200, Terrain.height(-3200, -3850) + 2.0, -3850))
	if _t == 720:
		get_viewport().get_texture().get_image().save_png("/tmp/river_pen.png")
		# Confirm the carve is in the height function under the course.
		var mid := Terrain.height(-3200, -3850)
		var bank := Terrain.height(-3160, -3850)
		print("[pen_probe] bed=%.1fm bank=%.1fm (carve depth %.1fm)" % [
			mid, bank, bank - mid])
		print("SHOT WRITTEN /tmp/river_pen.png")
		get_tree().quit()
