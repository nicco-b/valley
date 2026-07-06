extends Node3D
## CaravanBody (the Understory walking the Ways): the embodied
## presentation of one stateless caravan. The route math stays in the
## Caravans autoload (position is a pure function of the clock — this
## node never simulates); each frame the owner seats us on locate()'s
## answer and we handle the flesh: terrain height, facing, walk/idle
## animation, road wear and sand prints, and a passing greeting.
## PLACEHOLDER body: the CC0 robot, same as NPCs (assets/models/
## placeholder/robot.glb) → her caravan walker painting when it lands.

var route_id := "caravan"

var _last := Vector2.INF
var _step_accum := 0.0

@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer
@onready var _body: Node3D = $Body


func _ready() -> void:
	for n in ["Idle", "Walking"]:
		_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Walking")
	$Interact.interacted.connect(_on_interacted)


## Owner calls this every frame with the route math's answer.
func seat(pos: Vector2, en_route: bool) -> void:
	global_position = Vector3(pos.x, Terrain.height(pos.x, pos.y), pos.y)
	if _last.is_finite():
		var moved := pos - _last
		if moved.length() > 0.005:
			# Characters face +Z (the project convention).
			_body.rotation.y = lerp_angle(_body.rotation.y,
				atan2(moved.x, moved.y), 0.15)
			# The road remembers the runner: wear + prints, the NPC rate.
			_step_accum += moved.length()
			if _step_accum >= 0.7:
				_step_accum = 0.0
				InteractionField.wear_only(pos)
				SandField.stamp(pos, _body.rotation.y, SandField.Mask.BOOT, 0.9)
	_last = pos
	var target_anim := "Walking" if en_route else "Idle"
	if _anim.assigned_animation != target_anim:
		_anim.play(target_anim, 0.3)


func _on_interacted(_by: Node) -> void:
	# A runner doesn't stop — presence, not conversation (dialogue
	# arrives with the village pass).
	WorldState.set_flag("caravan.%s.met" % route_id)
	HUD.say("the runner", "A nod in passing — the road does not wait.")
