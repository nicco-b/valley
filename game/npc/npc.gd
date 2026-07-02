extends CharacterBody3D
## A needs-driven inhabitant (utility AI). The record defines who they
## are — needs with drain weights, and activities that satisfy them at
## places — and behavior emerges: each need drains over game-time, each
## activity scores by how badly its need wants satisfying (gated softly
## by preferred hours), and the best activity wins with hysteresis so
## they don't dither. Needs persist via WorldState.

const SPEED := 3.0
const ACCEL := 8.0
const ARRIVE_DISTANCE := 3.0
const DRAIN_SCALE := 6.0  # need points lost per game-hour at weight 1.0
const SATISFY_SCALE := 10.0  # need points gained per game-hour at rate 1.0
const OFF_HOURS_GATE := 0.15
const KEEP_CURRENT_BIAS := 1.5
const DECIDE_INTERVAL := 0.5  # real seconds between decisions

var npc_id := "npc"
var display_name := "???"
var home := Vector2.ZERO
var needs_def: Dictionary = {}  # need -> drain weight
var activities: Array = []

var needs: Dictionary = {}  # need -> 0..100 (100 = content)
var current: Dictionary = {}
var last_utilities: Dictionary = {}

var _target := Vector3.ZERO
var _decide_accum := 0.0
var _wander_accum := 0.0

@onready var _anim: AnimationPlayer = $Body/Model/AnimationPlayer
@onready var _body: Node3D = $Body


func setup(data: Dictionary) -> void:
	npc_id = data.id
	display_name = data.get("name", data.id)
	needs_def = data.needs
	activities = data.activities
	home = Vector2(data.home.x, data.home.z)


func _ready() -> void:
	add_to_group("npc")
	for n in ["Idle", "Walking"]:
		_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle")
	$Interact.interacted.connect(_on_interacted)

	var saved: Dictionary = WorldState.get_value("npc.%s.needs" % npc_id, {})
	for need in needs_def:
		needs[need] = float(saved.get(need, 70.0))
	GameClock.hour_tick.connect(func(_h: int) -> void:
		WorldState.set_value("npc.%s.needs" % npc_id, needs.duplicate()))
	_decide()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var dt_hours: float = GameClock.hours_delta(delta)
	for need in needs:
		needs[need] = clampf(
			needs[need] - needs_def[need] * DRAIN_SCALE * dt_hours, 0.0, 100.0
		)

	var to := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	var arrived := to.length() < ARRIVE_DISTANCE

	if arrived and not current.is_empty():
		var need: String = current.satisfies
		needs[need] = clampf(
			needs[need] + float(current.get("rate", 6.0)) * SATISFY_SCALE * dt_hours,
			0.0, 100.0
		)
		# Foragers drift around their spot.
		if current.has("wander"):
			_wander_accum += delta
			if _wander_accum > 20.0:
				_wander_accum = 0.0
				_target = _resolve_at(current) + Vector3(
					randf_range(-1.0, 1.0) * float(current.wander), 0.0,
					randf_range(-1.0, 1.0) * float(current.wander)
				)

	_decide_accum += delta
	if _decide_accum >= DECIDE_INTERVAL:
		_decide_accum = 0.0
		_decide()

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
		target_anim = "Sitting" if current.get("pose", "stand") == "sit" else "Idle"
	if _anim.assigned_animation != target_anim:
		_anim.play(target_anim, 0.3)


func _decide() -> void:
	var best: Dictionary = {}
	var best_u := -1.0
	var current_u := 0.0
	last_utilities = {}
	for a in activities:
		var u: float = (100.0 - needs.get(a.satisfies, 50.0)) * _hours_gate(a)
		# Weather changes minds: storm_boost activities spike in bad weather.
		u *= 1.0 + Weather.storminess * float(a.get("storm_boost", 0.0))
		last_utilities[a.id] = u
		if a == current:
			current_u = u
		if u > best_u:
			best_u = u
			best = a
	# Hysteresis: stay with the current activity unless it's satisfied or
	# clearly beaten.
	if not current.is_empty() and needs.get(current.satisfies, 0.0) < 85.0 \
			and current_u * KEEP_CURRENT_BIAS >= best_u:
		return
	if best != current:
		current = best
		_target = _resolve_at(current)


func _hours_gate(a: Dictionary) -> float:
	if not a.has("hours"):
		return 1.0
	var start: float = a.hours[0]
	var end: float = a.hours[1]
	var h: float = GameClock.hours
	var inside := (h >= start and h < end) if start <= end \
			else (h >= start or h < end)  # window wraps midnight
	return 1.0 if inside else OFF_HOURS_GATE


func _resolve_at(a: Dictionary) -> Vector3:
	var xz := home
	if a.get("at") is Dictionary:
		xz = Vector2(a.at.x, a.at.z)
	return Vector3(xz.x, global_position.y, xz.y)


## One-line-per-fact debug dump for the god-mode sim inspector.
func sim_debug() -> String:
	var lines: Array[String] = [display_name, ""]
	lines.append("activity: %s%s" % [
		current.get("id", "—"), " (%s)" % current.get("pose", "stand")
	])
	lines.append("")
	for need in needs:
		var v: float = needs[need]
		var bar := "".rpad(int(v / 10.0), "█").rpad(10, "░")
		lines.append("%-8s %s %3d" % [need, bar, int(v)])
	lines.append("")
	lines.append("utilities:")
	for id in last_utilities:
		lines.append("  %-10s %5.1f" % [id, last_utilities[id]])
	return "\n".join(lines)


## Placeholder greeting until dialogue exists: familiarity from WorldState.
func _on_interacted(by: Node) -> void:
	WorldState.set_flag("npc.%s.met" % npc_id)
	var n: int = WorldState.increment("npc.%s.encounters" % npc_id)
	var text := "%s studies you for a moment — a stranger — then nods once." % display_name
	if n >= 5:
		text = "%s raises a hand before you speak, like an old friend." % display_name
	elif n > 1:
		text = "%s nods. You again." % display_name
	HUD.say(display_name, text)
	if by is Node3D:
		var to: Vector3 = (by as Node3D).global_position - global_position
		_body.rotation.y = atan2(to.x, to.z)
