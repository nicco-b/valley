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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rig.rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_arm.rotation.x = clampf(
			_arm.rotation.x - event.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX
		)
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
	var blend := 1.0 - exp(-ACCEL * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, blend)
	velocity.z = lerpf(velocity.z, dir.z * speed, blend)

	move_and_slide()

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
