extends Node
## Pond probe (dev-only): boots the valley windowed, kills FocusThrottle
## (an unfocused window is near-idle throttled — screenshots stall
## without this), frames the pond, saves /tmp/pond_shot.png, quits.
## Run: godot res://tests/pond_probe.tscn  (with a ~90s watchdog).
## THE tool that caught the invisible-pond bug: probe geometry lies fair
## (verts/AABB can be fine while every triangle is degenerate) — only a
## rendered image proves water is wet.
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
	if _t == 20:
		GameClock.hours = 14.0
		GameClock.time_scale = 0.0
		Weather.force_kind("calm")
		var pl := get_tree().get_first_node_in_group("player")
		if pl: pl.global_position = Vector3(70, 3, -280)
	if _t == 100:
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = Vector3(70, 14, -270)
		cam.look_at(Vector3(70, -1, -312))
		cam.make_current()
	if _t == 115:
		get_viewport().get_texture().get_image().save_png("/tmp/pond_shot.png")
		print("SHOT WRITTEN")
		get_tree().quit()
