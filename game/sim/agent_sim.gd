class_name AgentSim
extends RefCounted
## The shared agent mind — one sim core, any presentation (SIM_ROADMAP
## P1: embodied node, coarse node, or pure data record). Needs drain over
## game-hours; activities score against them (hour-gated, weather-
## modulated); the best wins, with optional hysteresis; position advances
## toward the chosen place in steps of any size, so an hour-chunk of
## catch-up completes journeys the same way a live tick does.
##
## Wildlife runs on this now; NPCs are the second adopter (their node
## keeps physics/dialogue/rumors — the mind moves here). Every future
## agent — villager, predator, caravan — is an AgentSim plus a record.
## Determinism: all randomness through Rng.stream(rng_stream).

const DRAIN_SCALE := 5.0  # need points lost per game-hour at weight 1.0
const SATISFY_SCALE := 10.0  # points gained per game-hour at rate 1.0
const OFF_HOURS_GATE := 0.15

var id := "agent"
var home := Vector2.ZERO
var pos := Vector2.ZERO
var target := Vector2.ZERO
var jitter := Vector2.ZERO  # personal offset so groups don't stack
var speed := 2.2  # m/s
var arrive := 4.0
var keep_bias := 1.0  # >1.0 adds hysteresis: keep current unless clearly beaten
var solar_gate := false  # wildlife lives by the sun; people by the clock
var roam_range := 150.0
var rng_stream := "npc"

var needs_def: Dictionary = {}  # need -> drain weight
var needs: Dictionary = {}  # need -> 0..100 (100 = content)
var activities: Array = []
var current: Dictionary = {}
var last_utilities: Dictionary = {}
var produced: Dictionary = {}  # item -> amount accrued; the owner flushes


func setup(agent_id: String, agent_home: Vector2, acts: Array,
		weights: Dictionary = {}) -> void:
	id = agent_id
	home = agent_home
	pos = agent_home
	target = agent_home
	activities = acts
	if weights.is_empty():
		for a in acts:
			needs_def[a.satisfies] = 1.0
	else:
		needs_def = weights.duplicate()
	for need in needs_def:
		needs[need] = 70.0


## One step of life, any size. An hour of catch-up and half a second of
## live tick take the same path.
func advance(dt_hours: float) -> void:
	drain(dt_hours)
	var to := target - pos
	if to.length() < arrive:
		satisfy(dt_hours)
	else:
		var dt_real := dt_hours * GameClock.day_length_minutes * 60.0 / 24.0
		pos += to.normalized() * minf(speed * dt_real, to.length())
	decide()


func arrived() -> bool:
	return (target - pos).length() < arrive


func drain(dt_hours: float) -> void:
	for need in needs:
		needs[need] = clampf(
			needs[need] - needs_def.get(need, 1.0) * DRAIN_SCALE * dt_hours,
			0.0, 100.0)


func satisfy(dt_hours: float) -> void:
	if current.is_empty():
		return
	var need: String = current.satisfies
	needs[need] = clampf(
		needs[need] + float(current.get("rate", 6.0)) * SATISFY_SCALE * dt_hours,
		0.0, 100.0)
	var produces: Dictionary = current.get("produces", {})
	for item in produces:
		produced[item] = float(produced.get(item, 0.0)) \
				+ float(produces[item]) * dt_hours


## Utility scoring: how badly does each activity's need want satisfying,
## gated softly by preferred hours, spiked by weather (storm_boost).
func decide() -> void:
	var best: Dictionary = {}
	var best_u := -1.0
	var current_u := 0.0
	last_utilities = {}
	for a in activities:
		var u: float = (100.0 - needs.get(a.satisfies, 50.0)) * _hours_gate(a)
		u *= 1.0 + Weather.storminess * float(a.get("storm_boost", 0.0))
		last_utilities[a.id] = u
		if a == current:
			current_u = u
		if u > best_u:
			best_u = u
			best = a
	if not current.is_empty() and needs.get(current.satisfies, 0.0) < 85.0 \
			and current_u * keep_bias >= best_u:
		return
	if best != current:
		current = best
		target = resolve_at(best) + jitter


func _hours_gate(a: Dictionary) -> float:
	if not a.has("hours"):
		return 1.0
	var start: float = a.hours[0]
	var end: float = a.hours[1]
	var h: float = GameClock.solar_hours() if solar_gate else GameClock.hours
	var inside := (h >= start and h < end) if start <= end \
			else (h >= start or h < end)  # window wraps midnight
	return 1.0 if inside else OFF_HOURS_GATE


func resolve_at(a: Dictionary) -> Vector2:
	if a.get("at") is Dictionary:
		return Vector2(a.at.x, a.at.z)
	if a.get("at") == "roam":
		var rng := Rng.stream(rng_stream)
		var ang := rng.randf() * TAU
		return home + Vector2(cos(ang), sin(ang)) * rng.randf_range(0.2, 1.0) * roam_range
	return home


## Persistence: everything the mind is, as JSON-safe data.
func to_state() -> Dictionary:
	return {
		"x": pos.x, "z": pos.y,
		"needs": needs.duplicate(),
		"activity": current.get("id", ""),
	}


func from_state(state: Dictionary) -> void:
	var x: float = state.x
	var z: float = state.z
	pos = Vector2(x, z)
	for need in state.get("needs", {}):
		needs[need] = float(state.needs[need])
	for a in activities:
		if a.id == str(state.get("activity", "")):
			current = a
			target = resolve_at(a) + jitter
			break


## One-line-per-fact dump for the god-mode sim inspector.
func debug_text() -> String:
	var lines: Array[String] = []
	lines.append("activity: %s" % current.get("id", "—"))
	lines.append("")
	for need in needs:
		var v: float = needs[need]
		var bar := "".rpad(int(v / 10.0), "█").rpad(10, "░")
		lines.append("%-8s %s %3d" % [need, bar, int(v)])
	lines.append("")
	lines.append("utilities:")
	for aid in last_utilities:
		lines.append("  %-10s %5.1f" % [aid, last_utilities[aid]])
	return "\n".join(lines)
