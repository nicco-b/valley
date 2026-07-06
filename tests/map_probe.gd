extends Node
## Map probe (dev-only): boots the valley, opens the map from the Toolkit,
## zooms to the requested level, saves /tmp/map_<zoom>.png. Run under
## Movie Maker, minimized (windowed-probes-annoy-nicco).
##   MAP_ORTHO=6000 godot --write-movie x.avi --fixed-fps 15 res://tests/map_probe.tscn
var _w: Node
var _t := 0
var _ortho := 6000.0


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
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			pl.global_position = Vector3(600, 4, -1600)
		MapScreen._open()
		_ortho = float(OS.get_environment("MAP_ORTHO")) \
			if OS.get_environment("MAP_ORTHO") != "" else 6000.0
		MapScreen._focus = Vector3(600, 0, -1600)
	if _t > 20:
		# Hold the zoom fixed (the eased _cam.size + stray input drift
		# otherwise wander it) so the shot lands at the intended scale.
		MapScreen._ortho = _ortho
		MapScreen._cam.size = _ortho
	if _t == 900:
		var z := int(_ortho)
		get_viewport().get_texture().get_image().save_png("/tmp/map_%d.png" % z)
		print("MAP SHOT /tmp/map_%d.png" % z)
		get_tree().quit()
