extends CharacterBody3D
## A schedule-driven inhabitant. The schedule is data (see data/npcs/):
## sorted entries {hour, x, z, pose}; the NPC walks to the entry whose
## hour has most recently passed and holds its pose there.

const SPEED := 3.0
const ACCEL := 8.0
const ARRIVE_DISTANCE := 3.0

var schedule: Array = []

@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer
@onready var _body: Node3D = $Body


func _ready() -> void:
	add_to_group("npc")
	for n in ["Idle", "Walking"]:
		_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var entry := _current_entry()
	var to := Vector3(entry.x - global_position.x, 0.0, entry.z - global_position.z)
	var arrived := to.length() < ARRIVE_DISTANCE
	var blend := 1.0 - exp(-ACCEL * delta)
	var target_velocity := Vector3.ZERO if arrived else to.normalized() * SPEED
	velocity.x = lerpf(velocity.x, target_velocity.x, blend)
	velocity.z = lerpf(velocity.z, target_velocity.z, blend)
	move_and_slide()

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.3:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(flat.x, flat.z), blend)

	var target_anim := "Walking"
	if arrived:
		target_anim = "Sitting" if entry.get("pose", "stand") == "sit" else "Idle"
	if _anim.assigned_animation != target_anim:
		_anim.play(target_anim, 0.3)


func _current_entry() -> Dictionary:
	var h: float = GameClock.hours
	var best: Dictionary = schedule.back()  # before the first entry -> still on last night's
	for e in schedule:
		if e.hour <= h:
			best = e
	return best
