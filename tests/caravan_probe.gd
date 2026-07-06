extends Node
## Caravan probe (dev-only, the Toolkit): boots the valley, dials the
## clock to mid-leg for the first caravan route, parks the focus beside
## locate()'s answer, and screenshots the embodied runner on the road.
## Movie Maker + minimized (the region_probe recipe).
##   godot --path . --write-movie /tmp/x.avi --fixed-fps 15 \
##     res://tests/caravan_probe.tscn

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
		GameClock.hours = 7.05  # valley_runner departs spawn_camp at 7:00
		GameClock.time_scale = 0.0
		Weather.force_kind("calm")
		if Caravans.routes.is_empty():
			print("CARAVAN PROBE FAIL: no routes"); get_tree().quit(); return
		var at: Dictionary = Caravans.locate(Caravans.routes[0], GameClock.hours)
		print("[caravan_probe] runner at (%.0f, %.0f) en_route=%s" % [
			at.pos.x, at.pos.y, at.en_route])
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			var p: Vector2 = at.pos
			pl.global_position = Vector3(p.x + 6.0,
				Terrain.height(p.x + 6.0, p.y + 4.0) + 2.0, p.y + 4.0)
	if _t == 780:
		var at: Dictionary = Caravans.locate(Caravans.routes[0], GameClock.hours)
		var cam := Camera3D.new()
		add_child(cam)
		cam.make_current()
		var p: Vector2 = at.pos
		cam.global_position = Vector3(p.x + 5.0,
			Terrain.height(p.x, p.y) + 2.2, p.y + 5.0)
		cam.look_at(Vector3(p.x, Terrain.height(p.x, p.y) + 1.0, p.y))
		print("[caravan_probe] ", Caravans.summary())
	if _t == 800:
		get_viewport().get_texture().get_image().save_png("/tmp/caravan.png")
		print("SHOT WRITTEN /tmp/caravan.png")
		get_tree().quit()
