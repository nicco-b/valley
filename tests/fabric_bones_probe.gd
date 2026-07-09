extends Node
## Fabric F2 probe (dev-only): the bone tier proving itself on what
## exists — the star hound's tail and the fox's ears under forced wind.
## Numbers first: downwind tip deflection, calm vs storm, asserted so
## the Weather coupling is pinned by test, not eyeballed; for the hound
## also the movement coupling (the tail must stream back harder at a
## flee-run than at rest — spring bones lag the body for free). Then
## the A/B screenshot in whatever weather FAB_WX forces.
## Measurement gotcha (hard-won): SkeletonModifier output is
## NON-destructive — script-visible bone poses revert right after the
## skin upload, so a plain get_bone_global_pose() only ever shows the
## animation. The honest read is inside `skeleton_updated`, where poses
## still carry the modified result; the spring's own contribution is
## (modified - raw) sampled the same frame, which also cancels the
## animation out of the number.
## Run windowed (spring bones are headless-gated), Movie Maker,
## minimized, opengl3 (locked-screen Metal boots crash — environmental):
##   FAB_WHO=hound FAB_WX=storm godot --rendering-driver opengl3 \
##     --write-movie /tmp/fab.avi --fixed-fps 30 \
##     res://tests/fabric_bones_probe.tscn
## Writes /tmp/fabric_<who>_<wx>.png and quits 0/1 on the assertions.

const SETTLE := 90   # frames for the springs to find a state
const SAMPLE := 60   # frames averaged per measurement
# The fox ear is a leaf bone: its origin never moves, only its rotation.
# Its measured tip is the FabricSpring virtual lever (rest direction
# from the head, the ear chain's "extend" length).
const EAR_LEVER := Vector3(0.062, 0.258962, -0.023743)

var _world: Node
var _who := "hound"
var _wx := "calm"
var _failures := 0
var _skel: Skeleton3D
var _tip := -1
var _lever := Vector3.ZERO
var _mod_tip := Vector3.ZERO  # captured inside skeleton_updated


func _ready() -> void:
	if OS.get_environment("FAB_WHO") in ["hound", "fox"]:
		_who = OS.get_environment("FAB_WHO")
	if OS.get_environment("FAB_WX") in ["calm", "storm"]:
		_wx = OS.get_environment("FAB_WX")
	_world = load("res://game/world/valley.tscn").instantiate()
	add_child(_world)
	_run.call_deferred()


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  FABRIC FAIL: ", name)


func _run() -> void:
	for i in 30:
		await get_tree().process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	FocusThrottle.queue_free()
	GameClock.hours = 14.0
	GameClock.time_scale = 0.0
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player")
	# The stage is wherever the player's save put them — streamed, flat
	# enough, real light. The wind blows +x so the framing is stable.
	var stage := player.global_position
	Weather.fronts.clear()
	Weather.wind_dir = Vector2(1.0, 0.0)
	Weather.force_kind(_wx)
	var creature: Node3D
	if _who == "hound":
		# Park the player just off-stage: near enough to keep the cells
		# dense and the camera-distance fade at 1, far enough to stay
		# out of frame and out of the hound's PRESS_RANGE.
		player.global_position = stage + Vector3(-2.0, 0.0, 16.0)
		creature = load("res://game/wildlife/hound_body.tscn").instantiate()
		creature.species = "probe_hound"
		# The real record's chains (FW4: no PRESETS left in fabric_spring.gd
		# to fall back on) — the probe rides content, not a private copy.
		var hound_rec: Dictionary = Records.load_json("res://data/wildlife/star_hounds.json")
		creature.fabric_chains = hound_rec.fabric
		add_child(creature)
		creature.global_position = stage + Vector3(0, 0.4, 0)
		creature.set_target(Vector2(stage.x, stage.z))  # stay; idle
	else:
		creature = player
	_skel = creature.find_children("*", "Skeleton3D", true, false)[0]
	_tip = _skel.find_bone("tail_star" if _who == "hound" else "ear.L")
	if _who == "fox":
		_lever = EAR_LEVER.normalized() * 0.14
	for i in 30:
		await get_tree().process_frame
	var sims := _skel.find_children("*", "SpringBoneSimulator3D", true, false)
	_check(sims.size() == 1, "windowed body constructs exactly one simulator")
	if sims.is_empty():
		get_tree().quit(1)
		return
	var fs: FabricSpring = sims[0]
	_skel.skeleton_updated.connect(_capture_modified)
	print("[fabric_probe] %s: %s" % [_who, FabricSpring.summary()])

	# — Numeric: downwind tip deflection, calm vs storm. (modified - raw)
	# isolates the spring from the idle animation; the mean over a window
	# rides out the gust sines.
	fs.influence_override = 1.0
	var defl := {}
	for wx in ["calm", "storm"]:
		Weather.force_kind(wx)
		Weather.wind = float(Weather.KINDS[wx].wind)
		for i in SETTLE:
			await get_tree().process_frame
		var acc := 0.0
		for i in SAMPLE:
			var d := _mod_tip - _raw_tip()
			acc += d.x * Weather.wind_dir.x + d.z * Weather.wind_dir.y
			await get_tree().process_frame
		defl[wx] = acc / SAMPLE
		print("[fabric_probe] %s %s: downwind tip deflection %+.4f m (wind %.2f)" % [
			_who, wx, defl[wx], Weather.wind])
	var floor_m := 0.1 if _who == "hound" else 0.02
	_check(float(defl.storm) > floor_m, "storm pushes the tip hard downwind")
	_check(float(defl.storm) > float(defl.calm) * 3.0,
		"storm reads as a different painting than calm")
	_check(absf(float(defl.storm)) < 1.2, "the chain never explodes")

	# — Movement coupling (hound only): press the player close so the
	# body REALLY flees (attention ladder, real navmesh run), and the
	# spring lag must stream the tail back harder than at rest, then
	# settle once the run ends.
	if _who == "hound":
		Weather.force_kind("calm")
		Weather.wind = 0.12
		for i in SETTLE:
			await get_tree().process_frame
		var rest_back := await _trail_metric(creature)
		player.global_position = creature.global_position + Vector3(0, 0.2, 3.0)
		for i in 40:  # calm -> alert -> fleeing, then up to speed
			await get_tree().process_frame
		var run_back := await _trail_metric(creature)
		print("[fabric_probe] hound spring lag: rest %+.4f m, fleeing %+.4f m" % [
			rest_back, run_back])
		_check(creature.attention == creature.Attention.FLEEING,
			"pressed hound actually flees")
		_check(run_back > rest_back + 0.02, "the tail streams back at a run")
		# Let it get away and stop: the tail must settle, not jiggle on.
		player.global_position = creature.global_position + Vector3(0, 0.2, 200.0)
		creature.set_target(Vector2(creature.global_position.x, creature.global_position.z))
		for i in 150:
			await get_tree().process_frame
		var settled := await _trail_metric(creature)
		print("[fabric_probe] hound spring lag settled: %+.4f m" % settled)
		_check(settled < run_back - 0.02, "the tail settles when the run ends")
		player.global_position = stage + Vector3(-2.0, 0.2, 16.0)
		creature.global_position = stage + Vector3(0, 0.4, 0)
		creature.set_target(Vector2(stage.x, stage.z))

	# — The screenshot: side-on to the wind (+x streams across frame),
	# framed off the live bones so a re-rig can't rot the framing.
	Weather.force_kind(_wx)
	Weather.wind = float(Weather.KINDS[_wx].wind)
	var focus_bone := _skel.find_bone("pelvis" if _who == "hound" else "head")
	for i in SETTLE:
		await get_tree().process_frame
	var look := (_skel.global_transform * _skel.get_bone_global_pose(focus_bone)).origin
	var cam := Camera3D.new()
	add_child(cam)
	var back := 3.2 if _who == "hound" else 1.6
	cam.global_position = look + Vector3(0.0, 0.5, back)
	cam.look_at(look)
	cam.make_current()
	for i in 30:
		await get_tree().process_frame
	var path := "/tmp/fabric_%s_%s.png" % [_who, _wx]
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT WRITTEN " + path)
	print("FABRIC-PROBE %s" % ("FAIL: %d" % _failures if _failures > 0 else "PASS"))
	get_tree().quit(1 if _failures > 0 else 0)


## Inside skeleton_updated the poses still carry the modifier's result.
func _capture_modified() -> void:
	_mod_tip = _tip_world()


## Outside it, the same read is the raw animation pose.
func _raw_tip() -> Vector3:
	return _tip_world()


func _tip_world() -> Vector3:
	var pose := _skel.global_transform * _skel.get_bone_global_pose(_tip)
	return pose.origin + pose.basis * _lever


## Spring lag behind the body (meters, horizontal, along -facing),
## averaged over a sample window: (modified - raw) cancels the walk/run
## animation, leaving only what the springs add — a running body drags
## its tail, a resting one lets the springs go quiet.
func _trail_metric(body: Node3D) -> float:
	var acc := 0.0
	for i in SAMPLE:
		var facing: Vector3 = body.get_node("Body").global_transform.basis * Vector3(0, 0, 1)
		facing.y = 0.0
		facing = facing.normalized()
		acc += (_mod_tip - _raw_tip()).dot(-facing)
		await get_tree().process_frame
	return acc / SAMPLE
