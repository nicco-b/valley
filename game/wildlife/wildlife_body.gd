extends CharacterBody3D
## A wildlife body: pure presentation over a data individual owned by
## WildlifeManager. The manager decides where to go; the body walks
## there, snaps to terrain, animates, and answers the god-mode inspector.
## Placeholder: the model is the star hound glb until canon names the
## valley's creatures.

const SPEED := 2.2
const ACCEL := 6.0
const ARRIVE := 4.0

var species := "creature"
var info: Dictionary = {}  # the live individual record (shared reference)

var _target := Vector3.ZERO

@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer
@onready var _body: Node3D = $Body


func _ready() -> void:
	for n in ["Idle", "Walking"]:
		if _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if _anim.has_animation("Idle"):
		_anim.play("Idle")
	CharacterPaint.apply($Body/Model)


func set_target(t: Vector2) -> void:
	_target = Vector3(t.x, 0.0, t.y)


## Hard re-seat after a time catch-up: the data lived the hours; the
## body teleports to wherever that put it.
func seat(pos: Vector2, target: Vector2) -> void:
	global_position = Vector3(pos.x, Terrain.height(pos.x, pos.y) + 0.4, pos.y)
	velocity = Vector3.ZERO
	set_target(target)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var to := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	var arrived := to.length() < ARRIVE
	var blend := 1.0 - exp(-ACCEL * delta)
	var target_velocity := Vector3.ZERO if arrived else to.normalized() * SPEED
	velocity.x = lerpf(velocity.x, target_velocity.x, blend)
	velocity.z = lerpf(velocity.z, target_velocity.z, blend)
	move_and_slide()

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.3:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(flat.x, flat.z), blend)

	var target_anim := "Idle" if arrived else "Walking"
	if _anim.has_animation(target_anim) and _anim.assigned_animation != target_anim:
		_anim.play(target_anim, 0.3)


## One-line-per-fact dump for the god-mode sim inspector.
func sim_debug() -> String:
	var lines: Array[String] = ["%s (wild)" % species, ""]
	lines.append("activity: %s" % str(info.get("activity", {}).get("id", "—")))
	lines.append("")
	var drives: Dictionary = info.get("drives", {})
	for d in drives:
		var v: float = drives[d]
		var bar := "".rpad(int(v / 10.0), "█").rpad(10, "░")
		lines.append("%-8s %s %3d" % [d, bar, int(v)])
	return "\n".join(lines)
