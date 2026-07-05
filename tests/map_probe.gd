extends Node
## Map probe (dev-only): boots the valley, opens the map from god mode,
## zooms to the requested level, saves /tmp/map_<zoom>.png. Run under
## Movie Maker, minimized (windowed-probes-annoy-nicco).
##   MAP_ORTHO=6000 godot --write-movie x.avi --fixed-fps 15 res://tests/map_probe.tscn
var _w: Node
var _t := 0


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
		GameClock.hours = 13.0
		GameClock.time_scale = 0.0
		Weather.force_kind("calm")
		GodMode.active = true  # pretend we're in the fly cam
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			pl.global_position = Vector3(400, 40, -1200)
		MapScreen._open()
		MapScreen._ortho = float(OS.get_environment("MAP_ORTHO")) \
			if OS.get_environment("MAP_ORTHO") != "" else 6000.0
		MapScreen._cam.size = MapScreen._ortho
		MapScreen._focus = Vector3(600, 0, -1600)
	if _t == 900:
		var z := int(MapScreen._ortho)
		get_viewport().get_texture().get_image().save_png("/tmp/map_%d.png" % z)
		print("MAP SHOT /tmp/map_%d.png" % z)
		get_tree().quit()
