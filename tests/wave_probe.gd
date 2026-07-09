extends Node
## Wave-source probe (dev-only, the Watershed / PLAN_SUBSTANCES S1):
## screenshots proving everything that moves rings the water — a hound
## crossing a ford trailing rings, storm rain stippling a lake, and the
## calm control. The ford/lake are FOUND on whatever world Strata baked
## (pinned coordinates rot; the sea_probe lesson). Movie Maker recipe,
## minimized window; the wave field needs a RenderingDevice, so NOT
## opengl3 (vulkan is this box's CLI-safe driver — the wave_bench note):
##   WAVE_SHOT=hound|rain|calm godot --rendering-driver vulkan --path . \
##     --write-movie /tmp/x.avi --fixed-fps 15 res://tests/wave_probe.tscn
## WAVE_POST=n overrides the water shader's ★ ring_posterize on every
## water material (0 = smooth field) — the knob's A/B shots.

const SETTLE := 360  # frames for streaming + water meshes near the spot
const AMBIENT := 300  # frames of rain/chop before the lake shots
const BACKSTOP := 1600  # shoot no matter what (a stuck hound still reports)

var _w: Node
var _t := 0
var _shot := "hound"
var _post := -1.0
var _hound: CharacterBody3D
var _mid := Vector2.INF  # the crossing midpoint / lake vantage target
var _across := Vector2.RIGHT  # crossing direction (ford) / view direction
var _shoot_at := -1
var _summaries := 0
var _rings_logged := 0


## The hound must cross WATER, not follow the navmesh around it — water
## is carved out of the bake, so the cursor walks the straight line.
class LineCursor extends PathCursor:
	func waypoint(_delta: float, _from: Vector3, goal: Vector3) -> Vector3:
		return goal


func _ready() -> void:
	var req := OS.get_environment("WAVE_SHOT")
	if req in ["hound", "rain", "calm"]:
		_shot = req
	var post := OS.get_environment("WAVE_POST")
	if not post.is_empty():
		_post = float(post)
	_w = load("res://game/world/valley.tscn").instantiate()
	add_child(_w)


## A ford: the shallowest interior river node that still wets a paw,
## with a modest half-width so the crossing fits one screenshot.
func _find_ford() -> bool:
	var best := 1e12
	for r in Terrain.rivers:
		var nodes: Array = r.nodes
		for i in range(1, nodes.size() - 1):
			var pos: Vector2 = nodes[i].pos
			var half: float = nodes[i].half
			if half < 1.2 or half > 8.0:
				continue
			var wsurf: float = Terrain.water_surface(pos.x, pos.y)
			if wsurf < -1e11:
				continue
			var depth: float = wsurf - Terrain.height(pos.x, pos.y)
			if depth < 0.15 or depth > 1.1:
				continue  # too dry to ring / too deep to be a ford
			# The most wadeable reach wins — belly-deep, not swimming.
			if absf(depth - 0.5) < best:
				best = absf(depth - 0.5)
				_mid = pos
				var seg: Vector2 = (nodes[i + 1].pos as Vector2) \
						- (nodes[i - 1].pos as Vector2)
				_across = Vector2(-seg.y, seg.x).normalized()
	return _mid.is_finite()


## A lake worth stippling: pond-sized (~50m) so the rim is parkable and
## the rain field fills the frame instead of vanishing to a horizon.
func _find_lake() -> bool:
	var best := 1e12
	for w in Terrain.water_bodies:
		if absf(float(w.radius) - 50.0) < best:
			best = absf(float(w.radius) - 50.0)
			_mid = w.center
			_across = Vector2.RIGHT
	return _mid.is_finite()


## Nearest dry ground to `want`, ring-searched outward — never park the
## anchor player in someone's lake.
func _dry_park(want: Vector2) -> Vector2:
	for r in 12:
		for i in 8:
			var p := want + Vector2.from_angle(TAU * i / 8.0) * (r * 6.0)
			if Terrain.water_surface(p.x, p.y) < -1e11:
				return p
	return want


## Push the ★ knob override into every live water material (lakes,
## rivers, sea tiers all share the one shader).
func _apply_post() -> void:
	if _post < 0.0:
		return
	for mi: MeshInstance3D in _w.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var mat: Material = mi.mesh.surface_get_material(0)
		if mat is ShaderMaterial \
				and (mat as ShaderMaterial).shader != null \
				and (mat as ShaderMaterial).shader.resource_path.ends_with("water.gdshader"):
			(mat as ShaderMaterial).set_shader_parameter("ring_posterize", _post)


func _process(_d: float) -> void:
	_t += 1
	if _t % 120 == 0:
		print("[wave_probe] frame ", _t)
	if _t == 2:
		FocusThrottle.queue_free()
		Engine.max_fps = 0
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		# Clock first thing: the sky palette eases toward the hour, and
		# two A/B runs that freeze the clock late can shoot mid-ease —
		# one pink, one teal, and the pair stops being an A/B.
		GameClock.hours = 14.0
		GameClock.time_scale = 0.0
	if _t == 20:
		Weather.fronts.clear()
		Weather.force_kind("storm" if _shot == "rain" else "calm")
		if not WaterWaves.enabled:
			print("[wave_probe] FAIL: wave field off — no RenderingDevice ",
				"(opengl3? headless?)")
			get_tree().quit(1)
			return
		var found := _find_ford() if _shot == "hound" else _find_lake()
		if not found:
			print("[wave_probe] FAIL: no %s found — tile/hyd caches present?" % (
				"ford" if _shot == "hound" else "lake"))
			get_tree().quit(1)
			return
		print("[wave_probe] %s at (%.0f, %.0f)" % [
			"ford" if _shot == "hound" else "lake", _mid.x, _mid.y])
		# The player anchors the wave window and the streamer; park it
		# 45m off — outside the hound's SENSE range (26m by day; 20m
		# froze the first shoot into a staring contest), inside the 128m
		# window, and on DRY ground: a parked player left swimming rings
		# the water itself and pollutes the calm control.
		var pl := get_tree().get_first_node_in_group("player")
		if pl:
			var px := _dry_park(_mid + Vector2(-_across.y, _across.x) * 45.0)
			pl.global_position = Vector3(px.x,
				Terrain.height(px.x, px.y) + 1.5, px.y)
			# Statue duty: a live player on a steep bank SLIDES into the
			# water and churns rings all shoot long (the sources=4 lesson)
			# — the anchor only needs a position, so freeze the body.
			pl.set_physics_process(false)
	if _t == 30:
		# The per-creature price: one water_surface query per stride
		# (~0.3s of travel at a trot) — timed here so the report's number
		# comes from the shipped query on the shipped world.
		var t0 := Time.get_ticks_usec()
		for i in 10000:
			Terrain.water_surface(_mid.x + (i % 40) * 0.5, _mid.y)
		print("[wave_probe] water_surface x10000: %.2f us each" % [
			(Time.get_ticks_usec() - t0) / 10000.0])
	if _t == SETTLE:
		_apply_post()
		var cam := Camera3D.new()
		add_child(cam)
		if _shot == "hound":
			# Three-quarter view down onto the crossing: close enough
			# that a hound-sized ring (0.6m) fills real pixels.
			var cp := _mid - _across * 9.0 + Vector2(-_across.y, _across.x) * 7.0
			var wsurf := Terrain.water_surface(_mid.x, _mid.y)
			cam.global_position = Vector3(cp.x, wsurf + 5.0, cp.y)
			cam.look_at(Vector3(_mid.x, wsurf, _mid.y))
			# The hound: spawned on the near bank, walking the straight
			# line across — the REAL body, so the stride hook itself is
			# what rings the water.
			_hound = load("res://game/wildlife/hound_body.tscn").instantiate() \
					as CharacterBody3D
			_hound.species = "hound"
			add_child(_hound)
			var start := _mid - _across * 14.0
			_hound.global_position = Vector3(start.x,
				Terrain.height(start.x, start.y) + 0.4, start.y)
			_hound._nav = LineCursor.new()
			var goal := _mid + _across * 14.0
			_hound.set_target(goal)
		else:
			var wsurf := Terrain.water_surface(_mid.x, _mid.y)
			var cp := _mid - _across * (60.0 if _shot != "hound" else 16.0)
			cam.global_position = Vector3(cp.x, wsurf + 8.0, cp.y)
			cam.look_at(Vector3(_mid.x, wsurf, _mid.y))
			_shoot_at = _t + AMBIENT
		cam.make_current()
	if _t > SETTLE and _shot == "hound" and _shoot_at < 0 and _hound != null:
		var hxz := Vector2(_hound.global_position.x, _hound.global_position.z)
		if hxz.distance_to(_mid) < 2.0:
			# A stride ring lives ~2s before damping under the posterize
			# floor — shoot while the trail is still speaking.
			_shoot_at = _t + 15
	if _t > SETTLE and _shot == "hound" and _rings_logged < 8 \
			and WaterWaves._last_ops > 0:
		# The stride ops land between the 30-frame summaries — catch a
		# few in the act so the transcript shows WHO rang.
		_rings_logged += 1
		print("[wave_probe] rings landed: sources=%d at frame %d" % [
			WaterWaves._last_ops, _t])
	if _t > SETTLE and _t % 30 == 0 and _summaries < 8:
		_summaries += 1
		print("[wave_probe] WAVES ", WaterWaves.summary(),
			"  wind=%.2f rain=%.2f" % [Weather.wind, Weather.rain])
		if _hound != null:
			print("[wave_probe] hound at (%.1f, %.1f)  mid (%.0f, %.0f)  %s" % [
				_hound.global_position.x, _hound.global_position.z,
				_mid.x, _mid.y,
				["calm", "alert", "fleeing"][_hound.attention]])
	if _t == _shoot_at or _t == BACKSTOP:
		var path := "/tmp/wave_%s.png" % _shot
		if _post >= 0.0:
			path = "/tmp/wave_%s_p%d.png" % [_shot, int(_post)]
		get_viewport().get_texture().get_image().save_png(path)
		print("[wave_probe] WAVES ", WaterWaves.summary())
		print("SHOT WRITTEN " + path)
		get_tree().quit()
