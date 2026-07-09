extends CharacterBody3D

const WALK_SPEED := 3.5
const SPRINT_SPEED := 6.5
const JUMP_VELOCITY := 4.5
const ACCEL := 10.0
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := -1.2
const PITCH_MAX := 0.5
const ARM_LENGTH := 4.0
const STICK_LOOK_SPEED := 2.6
const BASE_FOV := 75.0
const SPRINT_FOV := 81.0
const SIT_ARM_LENGTH := 6.5
const SIT_BODY_DROP := 0.0  # the sit animation handles the pose now
const SIT_EASE := 3.0
# River current push. Fights the input-to-zero lerp and (wading) bed
# friction, so the felt brook drift lands ~0.5 m/s — a clear pull you
# walk against; stronger afloat (no bed drag) and in a flood (the current
# scales with real discharge). Measured by tests/current_probe.
const CURRENT_PUSH := 10.0

# Fabric F2: the fox's own chains — content, not framework (FW4: these
# used to live in fabric_spring.gd's PRESETS alongside the hound's).
# Leaf-bone ears extend a virtual tip so a one-bone chain has a lever.
const FABRIC_CHAINS: Array[Dictionary] = [
	{"root": "ear.L", "end": "ear.L", "stiffness": 3.2, "drag": 0.8,
		"gravity": 0.05, "radius": 0.03, "wind": 1.2, "extend": 0.14},
	{"root": "ear.R", "end": "ear.R", "stiffness": 3.2, "drag": 0.8,
		"gravity": 0.05, "radius": 0.03, "wind": 1.2, "extend": 0.14},
]

var _sitting := false
# Underwater swim state (2026-07-04 water review, step 1). PROVISIONAL
# binding: dive = Ctrl / gamepad B (kitchen-table review pending). No
# drowning by decision-in-waiting; the surfacing-instinct hook can bolt
# onto _submerged later.
var _submerged := false
var _uw_rect: ColorRect
var _uw_lowpass := -1
var _target: Interactable = null
var _step_accum := 0.0
var _step_left := false
var _sliding := false
var _sand_puff: GPUParticles3D
var _scuff: GPUParticles3D
var _was_airborne := false
var _fall_speed := 0.0  # |velocity.y| while airborne; floor zeroes velocity
var _steps: AudioStreamPlayer
# Skill xp accumulators, flushed to WorldState every few seconds.
var _xp_walk := 0.0
var _xp_sit := 0.0
var _xp_swim := 0.0
var _xp_flush := 0.0

@onready var _rig: Node3D = $CameraRig
@onready var _arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var _body: Node3D = $Body
@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer
@onready var _camera: Camera3D = $CameraRig/SpringArm3D/Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Idle/Walk/Run are cycles; Sitting and Jump are one-shot gestures that
	# hold their final frame. Alternate rigs may ship a subset, so only touch
	# clips that actually exist.
	for n in ["Idle", "Walking", "Running", "Walk", "Run"]:
		if _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var idle := _resolve_anim("Idle")
	if idle != "":
		_anim.play(idle)
	CharacterPaint.apply($Body/Model)
	# F2 fabric: the fox's ears answer the wind and lag a sprint turn —
	# spring bones, headless-gated (PLAN_FABRIC determinism stance).
	FabricSpring.adopt($Body/Model, FABRIC_CHAINS)
	_sand_puff = _make_sand_puff()
	_scuff = _make_scuff()
	_steps = _make_footsteps()
	SaveGame.load_into_world.call_deferred()


## Maps a locomotion state to a clip this model actually has, so alternate
## rigs degrade gracefully instead of crashing on a missing clip name. The
## star hound ships the full set (Idle/Walking/Running/Sitting/Jump); a rig
## missing a clip resolves down the list or to "" (the caller then just
## holds the current pose).
const _ANIM_FALLBACKS := {
	"Idle": ["Idle"],
	"Walking": ["Walking", "Walk"],
	"Running": ["Running", "Run", "Walking", "Walk"],
	"Sitting": ["Sitting", "Sit"],
	"Jump": ["Jump"],
}


func _resolve_anim(desired: String) -> String:
	for candidate in _ANIM_FALLBACKS.get(desired, [desired]):
		if _anim.has_animation(candidate):
			return candidate
	return ""


## Footstep pool: every wav in assets/audio/steps/ (synth placeholders
## now; drop real recordings in the same folder and they take over).
func _make_footsteps() -> AudioStreamPlayer:
	var randomizer := AudioStreamRandomizer.new()
	randomizer.random_pitch = 1.12
	randomizer.random_volume_offset_db = 2.0
	var dir := DirAccess.open("res://assets/audio/steps")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".wav"):
				randomizer.add_stream(-1, load("res://assets/audio/steps/" + f))
	var player := AudioStreamPlayer.new()
	player.stream = randomizer
	player.volume_db = -13.0
	add_child(player)
	return player


func _flush_xp() -> void:
	if _xp_walk > 0.0:
		WorldState.set_value("player.dist_walked",
				float(WorldState.get_value("player.dist_walked", 0)) + _xp_walk)
		_xp_walk = 0.0
	if _xp_sit > 0.0:
		WorldState.set_value("player.time_sat",
				float(WorldState.get_value("player.time_sat", 0)) + _xp_sit)
		_xp_sit = 0.0
	if _xp_swim > 0.0:
		WorldState.set_value("player.time_swum",
				float(WorldState.get_value("player.time_swum", 0)) + _xp_swim)
		_xp_swim = 0.0


func _play_footstep() -> void:
	if _steps.stream.streams_count > 0:
		_steps.play()


func _make_sand_puff() -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 65.0
	mat.initial_velocity_min = 0.7
	mat.initial_velocity_max = 1.8
	mat.gravity = Vector3(0, -2.6, 0)
	mat.damping_min = 1.2
	mat.damping_max = 2.2
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	# Grows and thins as it drifts — kicked sand blooms, then settles.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(0.4, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.5))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	mat.scale_curve = scale_tex
	var alpha := Gradient.new()
	alpha.set_color(0, Color(0.87, 0.79, 0.63, 0.55))
	alpha.set_color(1, Color(0.87, 0.79, 0.63, 0.0))
	var alpha_tex := GradientTexture1D.new()
	alpha_tex.gradient = alpha
	mat.color_ramp = alpha_tex
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var draw := StandardMaterial3D.new()
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.vertex_color_use_as_albedo = true
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Soft round mote, not a bare quad — a hard-edged square of dust
	# reads as a rendering bug, not sand.
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dot.width = 32
	dot.height = 32
	var dot_grad := Gradient.new()
	dot_grad.set_color(0, Color(1, 1, 1, 1))
	dot_grad.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dot_grad
	draw.albedo_texture = dot
	quad.material = draw
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.8
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.85
	p.process_material = mat
	p.draw_pass_1 = quad
	p.top_level = true  # puffs stay where they were kicked
	add_child(p)
	return p


## Continuous low scuff while sprinting — dragged sand, not bursts.
func _make_scuff() -> GPUParticles3D:
	var src := _make_sand_puff()
	src.queue_free()  # cheapest way to clone the tuned material setup:
	var p := GPUParticles3D.new()
	p.process_material = src.process_material.duplicate()
	p.draw_pass_1 = src.draw_pass_1
	var mat := p.process_material as ParticleProcessMaterial
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 0.9
	mat.direction = Vector3(0, 1, 0)
	p.amount = 24
	p.lifetime = 0.55
	p.one_shot = false
	p.emitting = false
	p.explosiveness = 0.0
	p.top_level = true
	add_child(p)
	return p


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENSITIVITY * Settings.mouse_sensitivity
		_rig.rotation.y -= event.relative.x * sens
		_arm.rotation.x = clampf(
			_arm.rotation.x - event.relative.y * sens, PITCH_MIN, PITCH_MAX
		)
	elif event.is_action_pressed("interact") and _target:
		_target.interact(self)
	elif event.is_action_pressed("firefly_deploy"):
		if Items.count("firefly") > 0:
			Items.add("firefly", -1)
			$Fireflies.deploy()
		else:
			HUD.notify("no fireflies in the satchel")
	elif event.is_action_pressed("firefly_recall"):
		var n: int = $Fireflies.recall_all()
		if n > 0:
			Items.add("firefly", n)
			HUD.notify("the fireflies return  (+%d)" % n)
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not PauseMenu.paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Underwater read: deep-pink veil + muffled world while the CAMERA is
## under the live surface (placeholder for the real post shader + fog
## swap — replacement path: WorldEnvironment underwater profile in
## day_night.gd once its palette hooks exist).
func _ensure_underwater_fx() -> void:
	if _uw_rect != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	_uw_rect = ColorRect.new()
	_uw_rect.color = Color(0.82, 0.45, 0.52, 0.32)
	_uw_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_uw_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_uw_rect.visible = false
	layer.add_child(_uw_rect)
	add_child(layer)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 900.0
	_uw_lowpass = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, lp)
	AudioServer.set_bus_effect_enabled(0, _uw_lowpass, false)


func _update_underwater_fx() -> void:
	_ensure_underwater_fx()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var under := cp.y < Terrain.water_surface(cp.x, cp.z)
	if under != _uw_rect.visible:
		_uw_rect.visible = under
		AudioServer.set_bus_effect_enabled(0, _uw_lowpass, under)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if Input.is_action_just_pressed("sit") and is_on_floor():
		_sitting = not _sitting
		if _sitting:
			WorldState.increment("player.times_sat")
	elif _sitting and (input != Vector2.ZERO or Input.is_action_just_pressed("jump")):
		_sitting = false
	if _sitting:
		input = Vector2.ZERO

	# Water: deep enough and you float; shallow water just slows you.
	var wsurf: float = Terrain.water_surface(global_position.x, global_position.z)
	var water_depth := 0.0
	var swimming := false
	if wsurf > -1e11:
		water_depth = wsurf - Terrain.height(global_position.x, global_position.z)
		swimming = water_depth > 1.1 and global_position.y < wsurf + 0.2

	if not swimming:
		_submerged = false
	if swimming:
		_sitting = false
		if Input.is_action_pressed("dive") and water_depth > 1.6:
			_submerged = true
		if _submerged:
			# Underwater: hold dive to sink, jump to rise, gentle buoyant
			# drift otherwise; breach the surface band and you're back on top.
			var vy := 0.35
			if Input.is_action_pressed("dive"):
				vy = -2.2
			elif Input.is_action_pressed("jump"):
				vy = 2.6
			velocity.y = lerpf(velocity.y, vy, 1.0 - exp(-6.0 * delta))
			if global_position.y > wsurf - 0.9 and not Input.is_action_pressed("dive"):
				_submerged = false
			if is_on_floor() and water_depth < 1.3:
				_submerged = false
		else:
			# Surface: hold the origin ~0.8 under — chest-deep for the
			# 1.5m biped fox, head and ears clear of the water.
			velocity.y = (wsurf - 0.8 - global_position.y) * 3.0
		if not WorldState.has_flag("player.swam"):
			WorldState.set_flag("player.swam")
	elif not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump") and not _sitting:
		velocity.y = JUMP_VELOCITY

	var dir := _rig.global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	speed *= 1.0 + 0.05 * Skills.level("wayfaring")
	if swimming:
		speed *= 0.55 * (1.0 + 0.08 * Skills.level("swimming"))
	elif water_depth > 0.0:
		speed *= lerpf(1.0, 0.55, clampf(water_depth / 1.1, 0.0, 1.0))
	# Loose sand: climbing steep ground costs a little speed.
	if is_on_floor() and dir != Vector3.ZERO:
		var fn := get_floor_normal()
		var downhill := Vector3(fn.x, 0.0, fn.z)
		if downhill.length() > 0.01:
			var uphill := maxf(-dir.dot(downhill.normalized()), 0.0)
			speed *= 1.0 - uphill * clampf((1.0 - fn.y) * 2.2, 0.0, 0.4)
	var blend := 1.0 - exp(-ACCEL * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, blend)
	velocity.z = lerpf(velocity.z, dir.z * speed, blend)

	# River current: standing in flowing water pushes you downstream — a
	# free ride down, real effort up, danger above the falls. Full force
	# afloat, gentler when only wading (feet still grip). Sourced from the
	# live dynamics field, or the river's real discharge where the field
	# has nothing to say (WaterField.current_at handles both).
	if swimming or water_depth > 0.2:
		var cur := WaterField.current_at(global_position)
		if cur != Vector2.ZERO:
			var grip := 1.0 if swimming else clampf(water_depth / 1.1, 0.25, 1.0)
			velocity.x += cur.x * grip * delta * CURRENT_PUSH
			velocity.z += cur.y * grip * delta * CURRENT_PUSH

	# Sand-slide (the Journey move): steep loose ground stops holding you.
	# Gravity's slope component wins over walking friction — you skid
	# downhill, steerable, fast, shoveling a wake the granular sim then
	# avalanches behind you.
	_sliding = false
	if is_on_floor() and not swimming and not _sitting:
		var floor_n := get_floor_normal()
		if floor_n.y < cos(deg_to_rad(28.0)):
			_sliding = true
			var downhill := Vector3(floor_n.x, 0.0, floor_n.z).normalized()
			velocity.x += downhill.x * 16.0 * delta
			velocity.z += downhill.z * 16.0 * delta
			var flat_v := Vector2(velocity.x, velocity.z)
			if flat_v.length() > 10.0:
				flat_v = flat_v.normalized() * 10.0
				velocity.x = flat_v.x
				velocity.z = flat_v.y

	_update_underwater_fx()
	if not is_on_floor():
		_fall_speed = absf(velocity.y)  # captured pre-landing: the floor zeroes it
	move_and_slide()

	# The granular sim: moving feet shovel sand along the velocity;
	# sliding shovels a real trench.
	if is_on_floor() and not swimming:
		var flow_v := Vector2(velocity.x, velocity.z)
		if flow_v.length() > 1.2:
			SandField.plow(Vector2(global_position.x, global_position.z),
				flow_v.normalized(),
				0.0016 * flow_v.length() * (3.0 if _sliding else 1.0))

	# Splashdown: landing in water rings it hard — entry displacement
	# scales with fall speed (water review: submerged capsules inject
	# proportional to speed). The ring law is shared with every entering
	# body (PLAN_SUBSTANCES S1); the player is just size 1.0.
	if _was_airborne and not is_on_floor() and water_depth > 0.25:
		var splash := WaterWaves.splash_ring(absf(velocity.y), 1.0)
		WaterWaves.disturb(Vector2(global_position.x, global_position.z),
			splash.x, splash.y)
		_was_airborne = false

	# Kicked sand: a landing thumps a burst and blasts a real crater,
	# scaled by fall speed like the water splash — a hop dents the
	# ground, a drop off a mesa terrace blasts a real bowl.
	if is_on_floor() and _was_airborne and not swimming and _fall_speed > 2.5:
		_sand_puff.global_position = global_position + Vector3(0, 0.06, 0)
		_sand_puff.amount_ratio = 1.0
		_sand_puff.restart()
		SandField.crater(Vector2(global_position.x, global_position.z),
			clampf(0.28 + _fall_speed * 0.028, 0.3, 0.95),
			clampf(0.018 + _fall_speed * 0.0042, 0.03, 0.11))
		if _fall_speed > 6.0:
			# Hard landings also mark the PERSISTENT wear layer — the
			# sand crater slumps away in minutes, but a favorite
			# jump-down spot slowly becomes a worn hollow (the
			# desire-path idea, vertically).
			InteractionField.stamp(
				Vector2(global_position.x, global_position.z),
				clampf(_fall_speed * 0.09, 0.5, 1.0), 3)
	_was_airborne = not is_on_floor()
	_scuff.emitting = is_on_floor() and not swimming \
			and (_sliding or Input.is_action_pressed("sprint")) \
			and Vector2(velocity.x, velocity.z).length() > 4.0
	if _scuff.emitting:
		_scuff.global_position = global_position + Vector3(0, 0.08, 0)
		# Sliding throws a real spray: plume scales with carve speed
		# instead of the sprint scuff's fixed wisp.
		_scuff.amount_ratio = clampf(
			Vector2(velocity.x, velocity.z).length() / 10.0, 0.5, 1.0) \
			if _sliding else 0.5

	if is_on_floor() or swimming:
		_step_accum += Vector2(velocity.x, velocity.z).length() * delta
		if _step_accum >= 0.7:
			_step_accum = 0.0
			var foot_pos := Vector2(global_position.x, global_position.z)
			var heading := Vector2(sin(_body.rotation.y), cos(_body.rotation.y))
			var perp := Vector2(heading.y, -heading.x)
			_step_left = not _step_left
			SandField.stamp(foot_pos + perp * (0.12 if _step_left else -0.12),
				_body.rotation.y,
				SandField.Mask.FOOT_L if _step_left else SandField.Mask.FOOT_R,
				1.0)
			InteractionField.wear_only(foot_pos)
			if not swimming:
				_sand_puff.global_position = global_position + Vector3(0, 0.06, 0)
				# Sand kicks back off the heel and drifts with the wind;
				# a sprint throws more of it.
				var kick := -Vector3(velocity.x, 0.0, velocity.z).normalized()
				var mat := _sand_puff.process_material as ParticleProcessMaterial
				mat.direction = (Vector3.UP * 1.2 + kick * 0.8
					+ Vector3(Weather.wind_dir.x, 0.0, Weather.wind_dir.y) * Weather.wind)
				_sand_puff.amount_ratio = 1.0 if Input.is_action_pressed("sprint") else 0.6
				_sand_puff.restart()
				_play_footstep()

	# Face the body toward horizontal movement; the camera rig stays independent.
	# (Creature models face +Z by convention, hence no half-turn offset.)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.2:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(flat.x, flat.z), blend)

	var target_anim := "Idle"
	if _sitting:
		target_anim = "Sitting"
	elif not is_on_floor():
		target_anim = "Jump"
	elif flat.length() > 4.5:
		target_anim = "Running"
	elif flat.length() > 0.5:
		target_anim = "Walking"
	# Compare against assigned_animation: current_animation empties when a
	# one-shot clip finishes, which would retrigger it every frame.
	var resolved := _resolve_anim(target_anim)
	if resolved == "":
		_anim.pause()  # no matching clip (e.g. hound has no Idle) — hold pose
	elif _anim.assigned_animation != resolved:
		_anim.play(resolved, 0.3)
	elif not _anim.is_playing() and _anim.get_animation(resolved).loop_mode != Animation.LOOP_NONE:
		_anim.play(resolved)  # resume a looping clip after a pause; finished one-shots hold their pose

	# Skill practice accrues from doing; Stillness bends time while sitting.
	if is_on_floor() and flat.length() > 0.5:
		_xp_walk += flat.length() * delta
	if _sitting:
		_xp_sit += delta
	if swimming:
		_xp_swim += delta
	GameClock.time_scale = 1.0 + 2.0 * Skills.level("stillness") if _sitting else 1.0
	_xp_flush += delta
	if _xp_flush >= 3.0:
		_xp_flush = 0.0
		_flush_xp()

	# Right stick: camera look (polled — sticks aren't motion events).
	var look := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	if look.length() > 0.18:
		var s := STICK_LOOK_SPEED * Settings.mouse_sensitivity * delta
		_rig.rotation.y -= look.x * s
		_arm.rotation.x = clampf(_arm.rotation.x - look.y * s, PITCH_MIN, PITCH_MAX)

	# Sprint widens the view a touch.
	var moving_fast := (_sliding or Input.is_action_pressed("sprint")) and flat.length() > 4.0
	_camera.fov = lerpf(_camera.fov, SPRINT_FOV if moving_fast else BASE_FOV, blend * 0.6)

	# Sitting: settle the body down and ease the camera out to a wider frame.
	var sit_blend := 1.0 - exp(-SIT_EASE * delta)
	_body.position.y = lerpf(_body.position.y, SIT_BODY_DROP if _sitting else 0.0, sit_blend)
	_arm.spring_length = lerpf(
		_arm.spring_length, SIT_ARM_LENGTH if _sitting else ARM_LENGTH, sit_blend
	)

	_update_target()


## Nearest Interactable within reach that the camera roughly faces.
func _update_target() -> void:
	var best: Interactable = null
	var best_d := 2.8
	var fwd := -_rig.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for node in get_tree().get_nodes_in_group("interactable"):
		var it := node as Interactable
		var d := it.global_position.distance_to(global_position)
		if d >= best_d:
			continue
		var to := it.global_position - global_position
		to.y = 0.0
		if d < 1.2 or to.normalized().dot(fwd) > 0.1:
			best = it
			best_d = d
	if best != _target:
		_target = best
		HUD.prompt("" if _target == null else "E — " + _target.prompt)
