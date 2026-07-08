extends Node
## Sea probe (dev-only, the Toolkit): screenshots of the W1 ocean swell
## from the strand, looking out to open water — the A/B check that storm
## swell reads bigger than calm. Same recipe as river_probe: Movie
## Maker, minimized window, env-var-selected weather.
##   SEA_WX=calm|storm godot --path . --write-movie /tmp/x.avi \
##     --fixed-fps 15 res://tests/sea_probe.tscn
## SEA_HOUR=gold shoots at the pink hour. The strand is FOUND, not
## authored: the probe marches out from world center until the terrain
## drops under the open sea (Strata re-imports move the coastline; a
## pinned coordinate would rot).

const SHOT_FRAME := 800
const MARCH_STEP := 25.0
const MARCH_MAX := 12000.0

var _w: Node
var _t := 0
var _wx := "calm"
var _strand := Vector3.ZERO
var _seaward := Vector2(1.0, 0.0)


func _ready() -> void:
	var req := OS.get_environment("SEA_WX")
	if req in ["calm", "storm"]:
		_wx = req
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


## March from world center along `dir` until the ground dives under the
## open sea; return the last land point before the crossing, or INF.
## The crossing only counts if the water stays open for a while beyond
## it — a shot across a 500m bay can't show the horizon rolling.
func _find_strand(dir: Vector2) -> Vector3:
	var last_land := Vector2.INF
	var d := 0.0
	while d < MARCH_MAX:
		var p := dir * d
		var h: float = Terrain.height(p.x, p.y)
		if Terrain.home_guard(p.x, p.y) > 0.5 and h < Terrain.sea_level - 4.0:
			if not _open_water(dir, d):
				d += MARCH_STEP
				continue
			if last_land.is_finite():
				return Vector3(last_land.x,
					Terrain.height(last_land.x, last_land.y), last_land.y)
			return Vector3(p.x, h, p.y)
		if h > Terrain.sea_level + 1.0:
			last_land = p
		d += MARCH_STEP
	return Vector3.INF


## True if the next ~2.5km along `dir` past `d` stays under the sea.
func _open_water(dir: Vector2, d: float) -> bool:
	var probe := d + 250.0
	while probe < d + 2500.0:
		var p := dir * probe
		if Terrain.height(p.x, p.y) > Terrain.sea_level - 2.0:
			return false
		probe += 250.0
	return true


func _process(_d: float) -> void:
	_t += 1
	if _t % 60 == 0:
		print("[sea_probe] frame ", _t)
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		# Movie Maker renders flat-out; minimize so the desktop stays
		# usable (region_probe lesson).
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	if _t == 20:
		GameClock.hours = 14.0
		if OS.get_environment("SEA_HOUR") == "gold":
			GameClock.hours = GameClock.daylight_span().y - 0.2
		GameClock.time_scale = 0.0
		# Find a strand in whatever world Strata baked: try headings
		# until one walks off the land into open sea.
		for i in 12:
			_seaward = Vector2.from_angle(TAU * float(i) / 12.0)
			_strand = _find_strand(_seaward)
			if _strand != Vector3.INF:
				break
		if _strand == Vector3.INF:
			print("[sea_probe] FAIL: no strand found — is the tile cache present?")
			get_tree().quit(1)
			return
		print("[sea_probe] strand at (%.0f, %.0f) facing (%.2f, %.2f)" % [
			_strand.x, _strand.z, _seaward.x, _seaward.y])
		# The swell should roll TOWARD the strand: aim the wind (and so
		# the forced front's travel heading) shoreward before forcing.
		# Clear the live sim's leftover fronts first — an off-screen gale
		# would radiate swell into the calm baseline (the herald working
		# as designed, but the A/B needs a clean sky).
		Weather.wind_dir = -_seaward
		Weather.fronts.clear()
		Weather.force_kind(_wx)
		var we: WorldEnvironment = _w.find_children("*", "WorldEnvironment", true, false)[0]
		we.environment.fog_enabled = false
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			pl.global_position = _strand + Vector3(0, 2.0, 0)
	if _t == SHOT_FRAME - 20:
		var cam := Camera3D.new()
		add_child(cam)
		cam.far = 12000.0
		cam.make_current()
		# Stand a few meters up the beach, look long over the water so
		# the swell fills the frame out to the horizon line. Camera rides
		# whatever the ground does back there (steep strands exist).
		var cx := _strand.x - _seaward.x * 12.0
		var cz := _strand.z - _seaward.y * 12.0
		var cy := maxf(Terrain.height(cx, cz), Terrain.sea_level) + 5.0
		cam.global_position = Vector3(cx, cy, cz)
		cam.look_at(Vector3(_strand.x + _seaward.x * 600.0, Terrain.sea_level,
				_strand.z + _seaward.y * 600.0))
	if _t == SHOT_FRAME - 10:
		print("[sea_probe] swell: ", SeaSwell.summary())
		print("[sea_probe] air:   ", Weather.summary().split("\n")[0])
	if _t == SHOT_FRAME:
		var path := "/tmp/sea_%s.png" % _wx
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT WRITTEN " + path)
		get_tree().quit()
