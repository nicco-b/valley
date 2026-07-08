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
	"pond": {  # the home pond: the calm-water hero shot for palette work
		"focus": Vector3(60, 0, -300),
		"cam": Vector3(40, 6.0, -260), "aim": Vector3(65, -1, -300)},
	"wide": {  # aerial: the whole radial drainage, count the rivers
		"focus": Vector3(-3400, 2600, -3450),
		"cam": Vector3(-3400, 2400, -3450), "aim": Vector3(-3399, 0, -3440),
		"absolute": true},
	# "fall" and "hydlake" (ONE_APP P2) are DYNAMIC: the vantages above are
	# pinned to retired archipelago coords, but imported hyd_* records land
	# wherever Strata's solver put them — _vantage() finds the first
	# waterfall lip / the biggest imported lake at runtime.
}

var _w: Node
var _t := 0
var _shot := "close"
var _dyn: Dictionary = {}


func _ready() -> void:
	var req := OS.get_environment("RIVER_SHOT")
	if SHOTS.has(req) or req in ["fall", "hydlake"]:
		_shot = req
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


## The vantage for this run: a SHOTS entry, or one computed from the
## imported hydrology records (cached — needs the loaded world).
func _vantage() -> Dictionary:
	if SHOTS.has(_shot):
		return SHOTS[_shot]
	if not _dyn.is_empty():
		return _dyn
	if _shot == "fall":
		# Stand 60m downstream of the first recorded waterfall lip,
		# looking up into the white water.
		for r in Terrain.rivers:
			var falls: Array = r.get("falls", [])
			if falls.is_empty():
				continue
			var lip: Vector2 = falls[0].pos
			var drop := float(falls[0].drop)
			var below: Vector2 = lip + Terrain.river_tangent(r, lip.x, lip.y) * 60.0
			print("[river_probe] fall vantage: %s lip (%.0f, %.0f) drop %.1fm" % [
				r.id, lip.x, lip.y, drop])
			_dyn = {"focus": Vector3(below.x, 0, below.y),
				"cam": Vector3(below.x, 8.0, below.y),
				"aim": Vector3(lip.x, Terrain.height(lip.x, lip.y) + drop * 0.5, lip.y)}
			return _dyn
	if _shot == "hydlake":
		# The biggest imported lake (records load largest-first), from
		# its eastern shore looking across the water.
		for w in Terrain.water_bodies:
			if String(w.id).begins_with("hyd_"):
				var c: Vector2 = w.center
				var shore: Vector2 = c + Vector2(float(w.radius) * 0.95, 0.0)
				print("[river_probe] lake vantage: %s surface %.1fm r=%.0fm" % [
					w.id, w.surface, w.radius])
				_dyn = {"focus": Vector3(shore.x, 0, shore.y),
					"cam": Vector3(shore.x, 12.0, shore.y),
					"aim": Vector3(c.x, float(w.surface), c.y)}
				return _dyn
	push_warning("[river_probe] no hyd_* records for '%s' — using the close vantage" % _shot)
	_dyn = SHOTS.close
	return _dyn


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
	var s: Dictionary = _vantage() if _t >= 20 else {}
	if s.is_empty():
		return
	if _t == 20:
		GameClock.hours = 14.0
		if OS.get_environment("RIVER_HOUR") == "gold":
			# Just before real sunset — the pink palette's hour.
			GameClock.hours = GameClock.daylight_span().y - 0.2
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
		if OS.get_environment("WATER_FILL") != "":
			WaterField.set_fill(true)
	if _t == _cam_frame():
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
	if _t == _shot_frame() - 10:
		print("[river_probe] field: ", WaterField.summary())
	if _t == _shot_frame():
		var path := "/tmp/river_%s.png" % _shot
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT WRITTEN " + path)
		get_tree().quit()


# The fill experiment needs the field to run before the shot; the
# ribbon path shoots at the usual frame.
func _shot_frame() -> int:
	return 2400 if OS.get_environment("WATER_FILL") != "" else 800


func _cam_frame() -> int:
	return _shot_frame() - 20
