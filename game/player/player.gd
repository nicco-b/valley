extends CharacterBody3D

const WALK_SPEED := 3.5
const SPRINT_SPEED := 6.5
const JUMP_VELOCITY := 4.5
const ACCEL := 10.0
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := -1.2
const PITCH_MAX := 0.5
const ARM_LENGTH := 4.0
const SIT_ARM_LENGTH := 6.5
const SIT_BODY_DROP := 0.0  # the sit animation handles the pose now
const SIT_EASE := 3.0

var _sitting := false
var _target: Interactable = null
var _step_accum := 0.0
var _sand_puff: GPUParticles3D

@onready var _rig: Node3D = $CameraRig
@onready var _arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var _body: Node3D = $Body
@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Idle/Walk/Run are cycles; Sitting and Jump are one-shot gestures that
	# hold their final frame.
	for n in ["Idle", "Walking", "Running"]:
		_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	_sand_puff = _make_sand_puff()


func _make_sand_puff() -> GPUParticles3D:
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 55.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.3
	mat.gravity = Vector3(0, -3.5, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = Color(0.85, 0.78, 0.64, 0.5)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var draw := StandardMaterial3D.new()
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.vertex_color_use_as_albedo = true
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = draw
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 0.45
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.process_material = mat
	p.draw_pass_1 = quad
	p.top_level = true  # puffs stay where they were kicked
	add_child(p)
	return p


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rig.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_arm.rotation.x = clampf(
			_arm.rotation.x - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX
		)
	elif event.is_action_pressed("interact") and _target:
		_target.interact(self)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if Input.is_action_just_pressed("sit") and is_on_floor():
		_sitting = not _sitting
	elif _sitting and (input != Vector2.ZERO or Input.is_action_just_pressed("jump")):
		_sitting = false
	if _sitting:
		input = Vector2.ZERO

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump") and not _sitting:
		velocity.y = JUMP_VELOCITY

	var dir := _rig.global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO

	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
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

	move_and_slide()

	if is_on_floor():
		_step_accum += Vector2(velocity.x, velocity.z).length() * delta
		if _step_accum >= 0.7:
			_step_accum = 0.0
			InteractionField.stamp(Vector2(global_position.x, global_position.z))
			_sand_puff.global_position = global_position + Vector3(0, 0.06, 0)
			_sand_puff.restart()

	# Face the body toward horizontal movement; the camera rig stays independent.
	# (The robot model faces +Z, hence no half-turn offset.)
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
	if _anim.assigned_animation != target_anim:
		_anim.play(target_anim, 0.3)

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
