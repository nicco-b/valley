extends Node
## River probe (dev-only, the Toolkit): screenshots of the stage-C
## generated rivers so a human (or an AI session) can verify the ribbons
## lie in their carved channels. Same recipe as region_probe: Movie
## Maker, minimized window, one RIVER_SHOT vantage per run.
##   RIVER_SHOT=close godot --path . --write-movie /tmp/x.avi \
##     --fixed-fps 15 res://tests/river_probe.tscn
const SHOTS := {
	"close": {  # gen_1 mid-flank: ribbon in its channel, up close
		"focus": Vector3(-3300, 0, -3772),
		"cam": Vector3(-3260, 18.0, -3720), "aim": Vector3(-3320, 495, -3800)},
	"flank": {  # down the volcano flank along a river's run
		"focus": Vector3(-3120, 0, -4300),
		"cam": Vector3(-3120, 30.0, -4300), "aim": Vector3(-3300, 500, -3772)},
	"wide": {  # aerial: the whole radial drainage, count the rivers
		"focus": Vector3(-3400, 2600, -3450),
		"cam": Vector3(-3400, 2400, -3450), "aim": Vector3(-3399, 0, -3440),
		"absolute": true},
}

var _w: Node
var _t := 0
var _shot := "close"


func _ready() -> void:
	var req := OS.get_environment("RIVER_SHOT")
	if SHOTS.has(req):
		_shot = req
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


func _process(_d: float) -> void:
	_t += 1
	if _t % 60 == 0:
		print("[river_probe] frame ", _t)
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		# Movie Maker renders flat-out; minimize so the desktop stays
		# usable (region_probe lesson).
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var s: Dictionary = SHOTS[_shot]
	if _t == 20:
		GameClock.hours = 14.0
		GameClock.time_scale = 0.0
		# RIVER_WX=storm shows the live water field working the slope.
		var wx := OS.get_environment("RIVER_WX")
		Weather.force_kind(wx if wx != "" else "calm")
		var we: WorldEnvironment = _w.find_children("*", "WorldEnvironment", true, false)[0]
		we.environment.fog_enabled = false
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			var f: Vector3 = s.focus
			if not s.get("absolute", false):
				f.y = Terrain.height(f.x, f.z) + 2.0
			pl.global_position = f
	if _t == 780:
		var cam := Camera3D.new()
		add_child(cam)
		cam.far = 12000.0
		cam.make_current()
		var c: Vector3 = s.cam
		if not s.get("absolute", false):
			c.y += Terrain.height(c.x, c.z)
		cam.global_position = c
		cam.look_at(s.aim)
	if _t == 400 and OS.get_environment("RIVER_WALK") != "":
		# Drag the focus far enough to force a field re-anchor: exercises
		# the scroll kernel + base rebake mid-run.
		var pl2 := get_tree().get_first_node_in_group("player")
		if pl2:
			pl2.global_position.x += 600.0
			pl2.global_position.y = Terrain.height(
				pl2.global_position.x, pl2.global_position.z) + 2.0
	if _t == 790:
		print("[river_probe] field: ", WaterField.summary())
	if _t == 800:
		var path := "/tmp/river_%s.png" % _shot
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT WRITTEN " + path)
		get_tree().quit()
