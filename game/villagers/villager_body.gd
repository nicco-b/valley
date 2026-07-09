extends CharacterBody3D
## A villager body: presentation plus PRESENCE over an AgentSim owned by
## VillagerManager. The mind decides where to go; the body walks there on
## the baked navmesh (PathCursor, the way wildlife roams), snaps to the
## ground, faces its travel, and animates. Data-tier villagers have no body
## — nobody is near to see them.
##
## Presence, not dialogue (the ★s gate a dialogue system; this is the
## honest v1): the body carries one Interactable so the walker can examine
## it — "Mara — tending the garden", the villager's name and what she's
## doing right now. NO conversation, NO choices; a line and a name.
##
## Placeholder body: the record's body_scene points at villager_body.tscn,
## which wears the biped-fox model (the framework's default-look body)
## until canon gives the valley its people. Reuse, per the mission.

const SPEED := 2.0
const ACCEL := 6.0
const ARRIVE := 4.0
const RIDE_HEIGHT := 0.4  # body origin sits about this far above its feet

var villager_name := "Someone"  # set by the manager before add_child
var sim: AgentSim = null  # the live mind (shared reference with the manager)

var _sim_target := Vector3.ZERO
var _activity_note := ""  # what the examine line says she's doing
var _nav := PathCursor.new()  # embodied walking follows the baked navmesh
var _presence: Interactable = null

@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer
@onready var _body: Node3D = $Body


func _ready() -> void:
	for n in ["Idle", "Walking", "Walk"]:
		if _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if _anim.has_animation("Idle"):
		_anim.play("Idle")
	CharacterPaint.apply($Body/Model)
	# The presence: one Interactable the walker can examine (group
	# "interactable"; the player finds it by proximity + facing). The prompt
	# is the villager's name; using it says what she's doing right now.
	_presence = Interactable.new()
	_presence.prompt = villager_name
	_presence.interacted.connect(_on_examined)
	add_child(_presence)


func set_target(t: Vector2) -> void:
	_sim_target = Vector3(t.x, 0.0, t.y)


## The mind's current activity — feeds the examine line. The activity may
## carry a human `note` ("tending the garden"); else its id is the honest
## fallback ("resting"). Empty activity reads as "idle".
func set_activity(activity: Dictionary) -> void:
	if activity.is_empty():
		_activity_note = ""
	else:
		_activity_note = str(activity.get("note", activity.get("id", "")))


## The examine line: name and what she's doing. No dialogue — a line.
func _on_examined(_by: Node) -> void:
	if _activity_note.is_empty():
		HUD.say("", villager_name)
	else:
		HUD.say("", "%s — %s" % [villager_name, _activity_note])


## Hard re-seat after a time catch-up: the data lived the hours; the body
## teleports to wherever that put it.
func seat(pos: Vector2, target: Vector2) -> void:
	global_position = Vector3(pos.x, Terrain.height(pos.x, pos.y) + RIDE_HEIGHT, pos.y)
	velocity = Vector3.ZERO
	set_target(target)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var to := Vector3(_sim_target.x - global_position.x, 0.0,
		_sim_target.z - global_position.z)
	var arrived := to.length() < ARRIVE
	var blend := 1.0 - exp(-ACCEL * delta)
	var target_velocity := Vector3.ZERO
	if not arrived:
		var wp := _nav.waypoint(delta, global_position,
			Vector3(_sim_target.x, global_position.y, _sim_target.z))
		var to_wp := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
		if to_wp.length() > 0.1:
			target_velocity = to_wp.normalized() * SPEED
	velocity.x = lerpf(velocity.x, target_velocity.x, blend)
	velocity.z = lerpf(velocity.z, target_velocity.z, blend)
	move_and_slide()

	# Footsteps wear the ground into desire paths, like the wildlife's do.
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.3:
		InteractionField.wear_only(Vector2(global_position.x, global_position.z))

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.3:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(flat.x, flat.z), blend)

	var want := "Idle" if arrived else "Walking"
	if not _anim.has_animation(want) and want == "Walking" and _anim.has_animation("Walk"):
		want = "Walk"
	if _anim.has_animation(want) and _anim.assigned_animation != want:
		_anim.play(want, 0.3)


## One-line-per-fact dump for the Toolkit sim inspector (RMB on a body).
func sim_debug() -> String:
	if sim == null:
		return "%s (villager)" % villager_name
	return "%s (villager)\n\n%s" % [villager_name, sim.debug_text()]
