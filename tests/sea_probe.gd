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
## W2 shoaling: SEA_SHOT=windward|lee aims the forced weather's travel
## AT the found strand (windward: swell runs ashore, breakers) or OFF it
## (lee: the same strand becomes the island's sheltered side — swell
## runs out to sea, no surf). Same shore, flipped swell direction: the
## A/B that the breaker line obeys the swell heading, not just depth.

const SHOT_FRAME := 800
const MARCH_STEP := 25.0
const MARCH_MAX := 12000.0

var _w: Node
var _t := 0
var _wx := "calm"
var _shot := ""  # "" (W1 default: windward framing), "windward" or "lee"
var _strand := Vector3.ZERO
var _seaward := Vector2(1.0, 0.0)


func _ready() -> void:
	var req := OS.get_environment("SEA_WX")
	if req in ["calm", "storm"]:
		_wx = req
	var shot := OS.get_environment("SEA_SHOT")
	if shot in ["windward", "lee"]:
		_shot = shot
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


## Meters of gentle shelf off this strand: the width of the SUBMERGED
## 0.3..3m band (land above the waterline doesn't count — an emergent
## bar fooled the first version). The surf zone needs room to exist —
## breakers live between the ~2m line and the sand.
func _shelf_width(strand: Vector3, dir: Vector2) -> float:
	var d := 0.0
	var wet_from := -1.0
	while d < 400.0:
		var p := Vector2(strand.x, strand.z) + dir * d
		var depth: float = Terrain.sea_level - Terrain.height(p.x, p.y)
		if depth > 3.0:
			return (d - wet_from) if wet_from >= 0.0 else 0.0
		if wet_from < 0.0 and depth > 0.3:
			wet_from = d
		d += 5.0
	return 400.0 - maxf(wet_from, 0.0) if wet_from >= 0.0 else 0.0


## True if the next ~2.5km along `dir` past `d` stays under the sea.
func _open_water(dir: Vector2, d: float) -> bool:
	var probe := d + 250.0
	while probe < d + 2500.0:
		var p := dir * probe
		if Terrain.height(p.x, p.y) > Terrain.sea_level - 2.0:
			return false
		probe += 250.0
	return true


## W2 debug ledger: the seaward depth profile with the mirror math's
## break fraction, plus the near disc's BAKED depth at the same spots —
## the shot must agree with these numbers or the bake lies.
func _print_surf_line() -> void:
	var wb: Node3D = _w.find_children("WaterBodies", "", true, false)[0]
	var st: Dictionary = wb._bathy.get("near", {})
	var amp_p: float = SeaSwell.amp * SeaSwell.PRIMARY_SHARE
	for i in 14:
		var dist := 5.0 + 10.0 * i
		var p := Vector2(_strand.x, _strand.z) + _seaward * dist
		var depth: float = Terrain.sea_level - Terrain.height(p.x, p.y)
		var baked := -1e12
		if not st.is_empty():
			var anchor: Vector2 = st.anchor
			var n: int = st.n
			var ix := int(round((p.x - (anchor.x - st.radius)) / st.step))
			var iz := int(round((p.y - (anchor.y - st.radius)) / st.step))
			if ix >= 0 and ix < n and iz >= 0 and iz < n:
				baked = st.out[(iz * n + ix) * 3]
		print("[sea_probe]  %3.0fm out: depth=%.2f baked=%.2f break_x=%.2f" % [
			dist, depth, baked, SeaSwell.break_frac(amp_p, SeaSwell.wavelength, depth)])


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
		# until one walks off the land into open sea. W2 shots want the
		# GENTLEST shelf of the lot — the surf zone (waves break by
		# ~2m depth) is only wide enough to read on a shelving shore;
		# a plunging coast keeps its breaker line meters from the sand.
		_strand = Vector3.INF
		var best_shelf := -1.0
		var headings := 12 if _shot == "" else 24
		for i in headings:
			var dir := Vector2.from_angle(TAU * float(i) / float(headings))
			var s := _find_strand(dir)
			if s == Vector3.INF:
				continue
			if _shot == "":
				_seaward = dir
				_strand = s
				break
			var shelf := _shelf_width(s, dir)
			if shelf > best_shelf:
				best_shelf = shelf
				_seaward = dir
				_strand = s
		if _strand == Vector3.INF:
			print("[sea_probe] FAIL: no strand found — is the tile cache present?")
			get_tree().quit(1)
			return
		if _shot != "":
			print("[sea_probe] %s shelf: %.0fm of submerged 0.3-3m band" % [
				_shot, best_shelf])
		print("[sea_probe] strand at (%.0f, %.0f) facing (%.2f, %.2f)" % [
			_strand.x, _strand.z, _seaward.x, _seaward.y])
		# The swell should roll TOWARD the strand: aim the wind (and so
		# the forced front's travel heading) shoreward before forcing.
		# Clear the live sim's leftover fronts first — an off-screen gale
		# would radiate swell into the calm baseline (the herald working
		# as designed, but the A/B needs a clean sky).
		# W2 lee shot: flip the heading — swell runs OFF this shore, so
		# it is the sheltered side and the surf must stay home.
		Weather.wind_dir = _seaward if _shot == "lee" else -_seaward
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
		if _shot == "":
			# W1 framing: from the sand, long over the water, the swell
			# filling the frame to the horizon.
			var cx := _strand.x - _seaward.x * 12.0
			var cz := _strand.z - _seaward.y * 12.0
			var cy := maxf(Terrain.height(cx, cz), Terrain.sea_level) + 5.0
			cam.global_position = Vector3(cx, cy, cz)
			cam.look_at(Vector3(_strand.x + _seaward.x * 600.0,
					Terrain.sea_level, _strand.z + _seaward.y * 600.0))
		else:
			# W2 framing: a high three-quarter view DOWN the coast. The
			# surf zone on this world's steep shores is a ~10-20m ribbon
			# hugging the waterline — a grazing beach shot can't frame
			# it, but from up here the breaker line reads as the white
			# seam between sand and open sea (and the lee shot's seam
			# must stay clean).
			var along := Vector2(-_seaward.y, _seaward.x)
			var wl := Vector2(_strand.x, _strand.z) + _seaward * 20.0
			cam.global_position = Vector3(wl.x - along.x * 40.0,
					Terrain.sea_level + 55.0, wl.y - along.y * 40.0)
			var tgt := wl + along * 140.0 + _seaward * 30.0
			cam.look_at(Vector3(tgt.x, Terrain.sea_level, tgt.y))
	if _t == SHOT_FRAME - 10:
		print("[sea_probe] swell: ", SeaSwell.summary())
		print("[sea_probe] air:   ", Weather.summary().split("\n")[0])
		if _shot != "":
			_print_surf_line()
	if _t == SHOT_FRAME:
		var path := "/tmp/sea_%s.png" % _wx
		if _shot != "":
			path = "/tmp/sea_%s_%s.png" % [_wx, _shot]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT WRITTEN " + path)
		get_tree().quit()
