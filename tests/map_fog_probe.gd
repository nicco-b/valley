extends Node
var _w: Node
var _t := 0
func _ready() -> void:
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)
func _process(_d: float) -> void:
	_t += 1
	if _t == 2:
		FocusThrottle.queue_free(); Engine.max_fps = 0
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	if _t == 20:
		GameClock.hours = 6.0; GameClock.time_scale = 0.0
		Weather.force_kind("storm"); Weather.fog_override = 0.9
		var pl := get_tree().get_first_node_in_group("player")
		if pl: pl.global_position = Vector3(600, 4, -1600)
		MapScreen._open(); MapScreen._focus = Vector3(600, 0, -1600)
	if _t > 20:
		MapScreen._ortho = 5000.0; MapScreen._cam.size = 5000.0
	if _t == 500:
		get_viewport().get_texture().get_image().save_png("/tmp/map_stormy.png")
		print("MAP SHOT"); get_tree().quit()
