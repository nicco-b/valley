extends Node
## Wave-source probe (dev-only, the Watershed / PLAN_SUBSTANCES S1+S2):
## screenshots proving everything that moves rings the water — a hound
## crossing a ford trailing rings, storm rain stippling a lake, and the
## calm control. S2 adds the foam-memory evidence: WAVE_SHOT=wake shoots
## the hound's crossing THREE times (trail being laid / rings dead but
## foam lingering / foam died), WAVE_SHOT=breaker finds a windward strand
## under forced storm swell and shoots the breaker band's deposited foam
## twice, 6s apart (the drift rides it ashore between frames). The ford/
## lake/strand are FOUND on whatever world Strata baked (pinned
## coordinates rot; the sea_probe lesson). Movie Maker recipe, minimized
## window; the wave field needs a RenderingDevice, so NOT opengl3
## (vulkan is this box's CLI-safe driver — the wave_bench note):
##   WAVE_SHOT=hound|rain|calm|wake|breaker godot --rendering-driver \
##     vulkan --path . --write-movie /tmp/x.avi --fixed-fps 15 \
##     res://tests/wave_probe.tscn
## WAVE_POST=n overrides the water shader's ★ ring_posterize on every
## water material (0 = smooth field) — the knob's A/B shots.
## WAVE_FOAM=n overrides WaterWaves.foam_decay (seconds) — the ★ foam
## knob's A/B: same shot schedule, different τ, filenames carry it.

const SETTLE := 360  # frames for streaming + water meshes near the spot
const AMBIENT := 300  # frames of rain/chop before the lake shots
const BACKSTOP := 1600  # shoot no matter what (a stuck hound still reports)
const FPS := 15.0  # the Movie Maker fixed step: frames → seconds

var _w: Node
var _t := 0
var _shot := "hound"
var _post := -1.0
var _foam := -1.0
var _hound: CharacterBody3D
var _mid := Vector2.INF  # the crossing midpoint / lake vantage target
var _across := Vector2.RIGHT  # crossing direction (ford) / view direction
var _shoot_at := -1
var _wake_shots: Array = []  # [[frame, tag], ...] the linger/die schedule
var _fade_off := false  # WAVE_FADE=off: the distance-fade A/B's "before"
var _summaries := 0
var _rings_logged := 0


## The hound must cross WATER, not follow the navmesh around it — water
## is carved out of the bake, so the cursor walks the straight line.
class LineCursor extends PathCursor:
	func waypoint(_delta: float, _from: Vector3, goal: Vector3) -> Vector3:
		return goal


func _ready() -> void:
	var req := OS.get_environment("WAVE_SHOT")
	if req in ["hound", "rain", "calm", "wake", "breaker", "far", "mouth"]:
		_shot = req
	var post := OS.get_environment("WAVE_POST")
	if not post.is_empty():
		_post = float(post)
	var foam := OS.get_environment("WAVE_FOAM")
	if not foam.is_empty():
		_foam = float(foam)
	_fade_off = OS.get_environment("WAVE_FADE") == "off"
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
## The far shot instead wants the biggest lake in frame — a whole water
## body past the fade window (capped so an inland sea doesn't swallow
## the horizon).
func _find_lake() -> bool:
	var best := 1e12
	var target := 50.0 if _shot != "far" else 400.0
	for w in Terrain.water_bodies:
		if absf(float(w.radius) - target) < best:
			best = absf(float(w.radius) - target)
			_mid = w.center
			_across = Vector2.RIGHT
	return _mid.is_finite()


## A hyd river mouth for the seam shot (S2): the last node of a river
## that ends on a lake disc — the exact geometry _mouth_for feathers.
func _find_mouth() -> bool:
	for r in Terrain.rivers:
		var nodes: Array = r.nodes
		if nodes.size() < 2:
			continue
		var last: Dictionary = nodes[nodes.size() - 1]
		var lp: Vector2 = last.pos
		for w in Terrain.water_bodies:
			if lp.distance_to(w.center) < float(w.radius) + float(last.half) * 2.0:
				_mid = lp
				var prev: Dictionary = nodes[nodes.size() - 2]
				_across = (lp - Vector2(prev.pos)).normalized()
				return true
	return false


## A windward strand for the breaker shot (S2): a shoreline texel inside
## the live surf band (the CPU mirror's break_depth) whose ground RISES
## along the swell's travel — the shore the waves actually hit. Coarse
## grid over the world; nearest hit to the world center wins (streaming
## is cheapest there).
func _find_strand() -> bool:
	if Terrain.sea_level < -1e11:
		return false
	var dir: Vector2 = SeaSwell.direction
	var band: float = SeaSwell.break_depth(
		SeaSwell.amp * SeaSwell.PRIMARY_SHARE, SeaSwell.wavelength)
	var sea: float = Terrain.sea_surface()
	var best := 1e12
	for gz in range(-48, 49):
		for gx in range(-48, 49):
			var p := Vector2(gx * 128.0, gz * 128.0)
			var wsurf: float = Terrain.water_surface(p.x, p.y)
			if wsurf < -1e11 or absf(wsurf - sea) > 0.5:
				continue  # dry, or a lake — the surf band is the sea's
			var depth := wsurf - Terrain.height(p.x, p.y)
			if depth < 0.3 or depth > band:
				continue
			# The lee gate, the deposit's own math: rising ground ahead.
			if Terrain.height(p.x + dir.x * 6.0, p.y + dir.y * 6.0) \
					- Terrain.height(p.x, p.y) < 0.3:
				continue
			if p.length() < best:
				best = p.length()
				_mid = p
				_across = dir
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


## The player anchors the wave window and the streamer; park it 45m off —
## outside the hound's SENSE range (26m by day; 20m froze the first shoot
## into a staring contest), inside the 128m window, and on DRY ground: a
## parked player left swimming rings the water itself and pollutes the
## calm control.
func _park_player() -> void:
	var pl := get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var px := _dry_park(_mid + Vector2(-_across.y, _across.x) * 45.0)
	pl.global_position = Vector3(px.x,
		Terrain.height(px.x, px.y) + 1.5, px.y)
	# Statue duty: a live player on a steep bank SLIDES into the
	# water and churns rings all shoot long (the sources=4 lesson)
	# — the anchor only needs a position, so freeze the body.
	pl.set_physics_process(false)


## Push the ★ knob overrides into every live water material (lakes,
## rivers, sea tiers all share the one shader): ring_posterize (WAVE_POST)
## and the foam distance-fade kill (WAVE_FADE=off — the "before" of the
## too-white-at-distance A/B).
func _apply_post() -> void:
	if _post < 0.0 and not _fade_off:
		return
	for mi: MeshInstance3D in _w.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var mat: Material = mi.mesh.surface_get_material(0)
		if mat is ShaderMaterial \
				and (mat as ShaderMaterial).shader != null \
				and (mat as ShaderMaterial).shader.resource_path.ends_with("water.gdshader"):
			if _post >= 0.0:
				(mat as ShaderMaterial).set_shader_parameter("ring_posterize", _post)
			if _fade_off:
				(mat as ShaderMaterial).set_shader_parameter("foam_fade_near", 9e5)
				(mat as ShaderMaterial).set_shader_parameter("foam_fade_far", 1e6)


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
		if _shot in ["rain", "breaker"]:
			Weather.force_kind("storm")
		elif _shot == "far":
			Weather.force_kind("windy")  # chop = what shimmered white before
		else:
			Weather.force_kind("calm")
		if _foam >= 0.0:
			WaterWaves.foam_decay = _foam
			print("[wave_probe] foam_decay FORCED to %.1fs (the ★ A/B)" % _foam)
		if _shot == "breaker":
			# Pin the swell so the surf band is there to deposit — the
			# strand hunt waits for the direction to ease in (frame 90).
			SeaSwell.force_amp = 0.55
		if not WaterWaves.enabled:
			print("[wave_probe] FAIL: wave field off — no RenderingDevice ",
				"(opengl3? headless?)")
			get_tree().quit(1)
			return
		if _shot != "breaker":
			var found: bool
			if _shot in ["hound", "wake"]:
				found = _find_ford()
			elif _shot == "mouth":
				found = _find_mouth()
			else:
				found = _find_lake()
			if not found:
				print("[wave_probe] FAIL: no %s found — tile/hyd caches present?" % _shot)
				get_tree().quit(1)
				return
			print("[wave_probe] %s at (%.0f, %.0f)" % [_shot, _mid.x, _mid.y])
			_park_player()
	if _t == 90 and _shot == "breaker":
		# The swell direction has eased toward the forced storm's travel;
		# now the windward strand is findable.
		if not _find_strand():
			print("[wave_probe] FAIL: no windward strand in the surf band — ",
				"sea missing from this bake?")
			get_tree().quit(1)
			return
		print("[wave_probe] strand at (%.0f, %.0f)  %s" % [
			_mid.x, _mid.y, SeaSwell.summary()])
		_park_player()
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
		if _shot in ["hound", "wake"]:
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
		elif _shot == "breaker":
			# Down the strand from above the dry sand: the band's curds
			# accumulate for AMBIENT frames, then two shots 6s apart —
			# the drift visibly rides the foam ashore between them.
			var wsurf := Terrain.sea_surface()
			var cp := _mid - _across * 22.0
			cam.global_position = Vector3(cp.x, wsurf + 9.0, cp.y)
			cam.look_at(Vector3(_mid.x + _across.x * 6.0, wsurf,
				_mid.y + _across.y * 6.0))
			_wake_shots = [[SETTLE + AMBIENT, "1"],
				[SETTLE + AMBIENT + int(6.0 * FPS), "2"]]
		elif _shot == "far":
			# The distance-fade check: the whole lake sits past the fade
			# window — it must read as one quiet color field.
			var wsurf := Terrain.water_surface(_mid.x, _mid.y)
			var cp := _mid - _across * 430.0
			cam.global_position = Vector3(cp.x, wsurf + 80.0, cp.y)
			cam.look_at(Vector3(_mid.x, wsurf, _mid.y))
			_shoot_at = _t + AMBIENT
		elif _shot == "mouth":
			# Three-quarter down onto the river's last reach and the lake
			# beyond it — the drawn line's old home.
			var wsurf := Terrain.water_surface(_mid.x - _across.x * 20.0,
				_mid.y - _across.y * 20.0)
			if wsurf < -1e11:
				wsurf = Terrain.height(_mid.x, _mid.y)
			var cp := _mid - _across * 42.0 + Vector2(-_across.y, _across.x) * 12.0
			cam.global_position = Vector3(cp.x, wsurf + 16.0, cp.y)
			cam.look_at(Vector3(_mid.x + _across.x * 8.0, wsurf,
				_mid.y + _across.y * 8.0))
			_shoot_at = _t + 90
		else:
			var wsurf := Terrain.water_surface(_mid.x, _mid.y)
			var cp := _mid - _across * (60.0 if _shot != "hound" else 16.0)
			cam.global_position = Vector3(cp.x, wsurf + 8.0, cp.y)
			cam.look_at(Vector3(_mid.x, wsurf, _mid.y))
			_shoot_at = _t + AMBIENT
		cam.make_current()
	if _t > SETTLE and _shot in ["hound", "wake"] and _shoot_at < 0 \
			and _wake_shots.is_empty() and _hound != null:
		var hxz := Vector2(_hound.global_position.x, _hound.global_position.z)
		if hxz.distance_to(_mid) < 2.0:
			# A stride ring lives ~2s before damping under the posterize
			# floor — shoot while the trail is still speaking.
			if _shot == "wake":
				# The linger/die schedule (S2): rings die in ~2s, foam
				# holds for τ≈6s, then steps out through the age bands —
				# a: trail being laid; b: rings dead, foam speaking;
				# c: ~2.7τ later, the water forgot.
				_wake_shots = [[_t + 15, "a"],
					[_t + int(5.0 * FPS), "b"],
					[_t + int(17.0 * FPS), "c"]]
			else:
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
	if _t == 500 and _shot == "breaker":
		# Census: which deposit gate eats the window? (foam=0 forensics)
		var wet := 0
		var band := 0
		var lee := 0
		var amp_prim: float = SeaSwell.amp * SeaSwell.PRIMARY_SHARE
		var pl := get_tree().get_first_node_in_group("player")
		var anch := Vector2(pl.global_position.x, pl.global_position.z)
		for i in 600:
			var q := anch + Vector2(randf() - 0.5, randf() - 0.5) * 128.0
			var qs: float = Terrain.water_surface(q.x, q.y)
			if qs < -1e11:
				continue
			wet += 1
			var ground: float = Terrain.height(q.x, q.y)
			var depth := qs - ground
			if depth < 0.1 or SeaSwell.break_frac(amp_prim,
					SeaSwell.wavelength, depth) < 1.0:
				continue
			band += 1
			var ahead := q + SeaSwell.direction * 3.0
			if Terrain.height(ahead.x, ahead.y) <= ground:
				continue
			lee += 1
		print("[wave_probe] census: wet=%d band=%d lee_pass=%d of 600  amp_prim=%.2f L=%.0f" % [
			wet, band, lee, amp_prim, SeaSwell.wavelength])
	# The S2 shot schedules (wake linger/die, breaker ride): each entry
	# writes its tagged frame; the last one ends the shoot.
	for s: Array in _wake_shots:
		if _t == int(s[0]):
			var suffix := "" if _foam < 0.0 else "_f%d" % int(_foam)
			var spath := "/tmp/wave_%s_%s%s.png" % [_shot, s[1], suffix]
			get_viewport().get_texture().get_image().save_png(spath)
			print("[wave_probe] WAVES ", WaterWaves.summary())
			print("SHOT WRITTEN " + spath)
			if s == _wake_shots[_wake_shots.size() - 1]:
				get_tree().quit()
	if _t == _shoot_at or _t == BACKSTOP:
		var path := "/tmp/wave_%s.png" % _shot
		if _post >= 0.0:
			path = "/tmp/wave_%s_p%d.png" % [_shot, int(_post)]
		if _foam >= 0.0:
			path = "/tmp/wave_%s_f%d.png" % [_shot, int(_foam)]
		if _fade_off or OS.get_environment("WATER_NO_MOUTH") == "1":
			path = "/tmp/wave_%s_before.png" % _shot
		get_viewport().get_texture().get_image().save_png(path)
		print("[wave_probe] WAVES ", WaterWaves.summary())
		print("SHOT WRITTEN " + path)
		get_tree().quit()
