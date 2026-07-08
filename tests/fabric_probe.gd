extends Node
## Fabric probe (dev-only, the Toolkit): screenshots of the F1 wind
## fabric — a row of banners, a tent, a ground sheet, and a net dressed
## through the streamer's REAL override path — the A/B check that a gale
## whips the cloth hard over while calm barely stirs it, and that the
## lean agrees with the wind the rest of the world feels. Same recipe as
## sea_probe: Movie Maker, minimized window, env-var-selected weather.
##   FAB_WX=calm|windy|storm godot --rendering-driver opengl3 --path . \
##     --write-movie /tmp/x.avi --fixed-fps 15 res://tests/fabric_probe.tscn
## FAB_POST=<steps> sets the flap_posterize knob on every fabric material
## (the gouache A/B: 0 = smooth sine, 3-4 = motion held in brush strokes).

const SHOT_FRAME := 240
const KINDS := ["calm", "overcast", "drizzle", "windy", "gale", "squall", "storm"]

var _w: Node
var _t := 0
var _wx := "calm"
var _post := -1.0  # <0: leave the shader default alone
var _base := Vector3.ZERO


func _ready() -> void:
	var req := OS.get_environment("FAB_WX")
	if req in KINDS:
		_wx = req
	var post := OS.get_environment("FAB_POST")
	if post != "":
		_post = float(post)
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


## Instance one card file, dress it through the streamer (the real
## fabric-override path), and seat it on the terrain at base + (dx, dz).
func _place(slot: String, variant: int, dx: float, dz: float, yaw := 0.0) -> void:
	var file: String = Cards.resolve(slot, variant)
	var loom: Node = get_tree().get_first_node_in_group("world_streamer")
	var scene: PackedScene = Kit.scene_for(file)
	if scene == null:
		print("[fabric_probe] FAIL: no scene for ", slot, " — placeholder GLBs missing?")
		get_tree().quit(1)
		return
	var inst: Node3D = scene.instantiate()
	loom._dress_placeable(inst, file)
	add_child(inst)
	var x := _base.x + dx
	var z := _base.z + dz
	inst.global_position = Vector3(x, Terrain.height(x, z), z)
	inst.rotation.y = yaw


func _process(_d: float) -> void:
	_t += 1
	if _t % 60 == 0:
		print("[fabric_probe] frame ", _t)
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		# Movie Maker renders flat-out; minimize so the desktop stays
		# usable (region_probe lesson).
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	if _t == 20:
		GameClock.hours = 14.0
		GameClock.time_scale = 0.0
		var pl := get_tree().get_first_node_in_group("player")
		if pl == null:
			print("[fabric_probe] FAIL: no player")
			get_tree().quit(1)
			return
		_base = pl.global_position
		pl.global_position = _base + Vector3(0, 0, -18)  # out of frame, behind the camera
		# The one wind: blow to screen-right (camera will look +z) so the
		# lean reads in profile. Pin the ANGLE too — the clock jump above
		# replays hour ticks and the hourly wander re-derives wind_dir
		# from _wind_angle, silently undoing a dir-only override.
		Weather._wind_angle = 0.0
		Weather.wind_dir = Vector2(1.0, 0.0)
		Weather.fronts.clear()
		Weather.force_kind(_wx)
		# Pre-seed the eased value near its target so the shot doesn't
		# have to sit out the 0.12/s approach (the probe frames the cloth,
		# not the front's arrival).
		Weather.wind = float(Weather.KINDS[_wx].wind)
	if _t == 40:
		# The lineup, spaced along x (the wind axis) facing the camera:
		# three banner variants, the tent, the ground sheet, the net.
		_place("props/textile/banner", 0, -5.0, 0.0)
		_place("props/textile/banner", 1, -2.5, 0.0)
		_place("props/textile/banner", 2, 0.0, 0.0)
		_place("props/camp/tent", 0, 3.5, 0.5)
		_place("props/textile", 0, 5.5, -1.0)
		_place("props/nautical/net", 0, 7.0, -2.0)
		if _post >= 0.0:
			var loom: Node = get_tree().get_first_node_in_group("world_streamer")
			for mat: ShaderMaterial in loom._fabric_mats.values():
				mat.set_shader_parameter("flap_posterize", _post)
	if _t == 60:
		var cam := Camera3D.new()
		add_child(cam)
		cam.make_current()
		# Low three-quarter view from south of the row: pennants in
		# profile, the wind running left-to-right across the frame.
		var cx := _base.x + 0.5
		var cz := _base.z - 10.0
		cam.global_position = Vector3(cx, Terrain.height(cx, cz) + 2.6, cz)
		cam.look_at(Vector3(_base.x + 0.5, _base.y + 1.6, _base.z))
	if _t == SHOT_FRAME - 10:
		var loom: Node = get_tree().get_first_node_in_group("world_streamer")
		print("[fabric_probe] fabric: ", loom.fabric_summary())
		print("[fabric_probe] air:    ", Weather.summary().split("\n")[0])
	if _t == SHOT_FRAME:
		var path := "/tmp/fabric_%s.png" % _wx
		if _post >= 0.0:
			path = "/tmp/fabric_%s_p%d.png" % [_wx, int(_post)]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT WRITTEN " + path)
		get_tree().quit()
