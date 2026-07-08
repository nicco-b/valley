extends Node
## Map probe (dev-only): boots the valley, opens the ORBIT map, and saves
## a screenshot for the eye check. Run under Movie Maker, minimized
## (windowed-probes-annoy-nicco):
##   MAP_SHOT=storm MAP_WX=storm godot --write-movie /tmp/x.avi \
##     --fixed-fps 15 res://tests/map_probe.tscn
## Knobs: MAP_WX forces the weather kind (calm default; storm proves the
## chart's weather exemption — fog_override rides along at 0.9 so the
## murk would be maximal if the map ever saw it) · MAP_HOUR sets the
## clock (13 default; 0 = the midnight-readability check) · MAP_DIST
## overrides the framing distance (whole tile default; ~800 exercises
## close streaming + the player marker) · MAP_SHOT names the png.
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
		GameClock.hours = float(OS.get_environment("MAP_HOUR")) \
			if OS.get_environment("MAP_HOUR") != "" else 13.0
		GameClock.time_scale = 0.0
		var wx := OS.get_environment("MAP_WX")
		Weather.force_kind(wx if wx != "" else "calm")
		if wx == "storm":
			Weather.fog_override = 0.9  # maximal murk: the exemption's proof
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			pl.global_position = Vector3(600, 4, -1600)
		MapScreen._open()
	if _t > 20:
		# Hold the framing (stray input drift would wander it) so the
		# shot lands at the intended scale; MAP_DIST recenters on the
		# player for the close-up marker check.
		if OS.get_environment("MAP_DIST") != "":
			MapScreen._rig.distance = float(OS.get_environment("MAP_DIST"))
			MapScreen._rig.target = Vector3(600, 0, -1600)
		MapScreen._rig.apply(MapScreen._cam)
	if _t == 900:
		var shot := OS.get_environment("MAP_SHOT")
		if shot == "":
			shot = "probe"
		get_viewport().get_texture().get_image().save_png("/tmp/map_%s.png" % shot)
		print("MAP SHOT /tmp/map_%s.png" % shot)
		get_tree().quit()
