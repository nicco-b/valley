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
var drain_scale := DRAIN_SCALE  # NPCs drain harder (6.0) than wildlife
var solar_gate := false  # wildlife lives by the sun; people by the clock
var roam_range := 150.0
var rng_stream := "npc"
## Herd cohesion: when set (by a manager, to the group's centroid), roam
## targets draw near it instead of anywhere in range — the group drifts
## through its territory as a group.
var roam_center := Vector2.INF
var cohesion_radius := 30.0
## Marker targeting (CREATION_KIT_REVIEW_V2 #3, schedules): an activity may
## name a placed marker by its stable record id instead of a raw XZ; the
## owning manager (VillagerManager, over CellRecords) wires this to turn
## that id into the marker's live position. Left unset (wildlife, plain
## agents) a marker target simply falls back to home — no coupling, no crash.
var marker_resolver := Callable()  # (String id) -> Vector2 world XZ; INF if gone

var needs_def: Dictionary = {}  # need -> drain weight
var needs: Dictionary = {}  # need -> 0..100 (100 = content)
var activities: Array = []
var current: Dictionary = {}
var last_utilities: Dictionary = {}
var produced: Dictionary = {}  # item -> amount accrued; the owner flushes

# --- Contour routing (PLAN_ENGINE E2, Mission C3: the agent mind's RULES tier) --
## advance()'s hour tick (drain + move/satisfy + decide utility scoring) is a
## SYSTEM-TIER port routed through the native Contour §6 `AgentMind` system
## (game/sim/agent_sim.ct, via game/sim/contour_bridge.gd) when STRATA_CONTOUR=1 —
## a boot-time sim flag, read once, default OFF. Flag OFF is byte-identical
## GDScript. NO SILENT FALLBACK (the honesty law): flag ON with the kernel absent
## / the module uncompilable / a refused tick is a LOUD push_error, never a quiet
## twin. The system consumes the SEEDED pcg stream threaded through agent.rng,
## seeded from — and written back to — Rng.stream(rng_stream).state, so both paths
## draw the SAME shared stream in lockstep (pcg_* is bit-exact to RandomPCG).
##
## Every AgentSim shares ONE bridge + routing decision (the module is
## framework-agnostic; each tick fully re-seeds the mind's state), so the state is
## CLASS-STATIC — and the engagement counter is class-wide, so the soak can prove
## the herd's minds ran through Contour (contour_status), not a silent fallback.
## What stays GDScript: body spawn/embody, the live-tick body handoff (managers'
## _process micro-ticks call drain/decide directly, like weather's _process ease),
## to_state/from_state persistence, debug_text — engine-bound, not this write set.
const _CONTOUR_MODULE := "res://game/sim/agent_sim.ct"
## 0 unresolved · 1 off (flag unset) · 2 engaged (bridge live) · -1 refused.
static var _contour_mode := 0
static var _contour_bridge: ContourBridge = null
static var _contour_calls := 0  # advance()s answered by Contour (engaged-path probe)
## The substrate Rung 2 DARK sub-flag: STRATA_CONTOUR_HELD=1 (requires
## STRATA_CONTOUR=1) routes the same AgentMind system through the PERSISTENT HELD
## WORLD (bridge.tick_held) — created once, ticked in place, only the write-diff
## crossing back — instead of the whole-world copy path (tick_seeded). The full
## mind record is re-injected every tick (as tick_seeded seeds it), so every mind
## sharing the ONE held world overwrites it in place and the WorldState effect is
## byte-identical to the copy path. Default OFF; CLASS-STATIC like the counter, so
## the soak proves the in-place path ran across the whole herd.
static var _contour_held := false
static var _contour_held_ticks := 0


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
	# Flag ON (STRATA_CONTOUR=1): the Contour §6 `AgentMind` system owns the whole
	# tick (drain + move/satisfy + decide), consuming the SAME seeded stream. Flag
	# OFF (default) is the byte-identical GDScript twin below — the four-run matrix's
	# bar. A refused tick already push_error'd; never a silent twin.
	var bridge := _route_contour()
	if bridge != null:
		_advance_contour(bridge, dt_hours)
		return
	# --- GDScript twin (flag OFF, default — forever byte-identical) ---
	drain(dt_hours)
	var to := target - pos
	if to.length() < arrive:
		satisfy(dt_hours)
	else:
		var dt_real := dt_hours * GameClock.day_length_minutes * 60.0 / 24.0
		pos += to.normalized() * minf(speed * dt_real, to.length())
	decide()


## The live systems bridge when routing is engaged, else null (flag off, or a
## loud refusal). Resolves once at first tick (boot); flag-off is pure GDScript.
## Static: one bridge for every mind (the module is framework-agnostic).
static func _route_contour() -> ContourBridge:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour_bridge


static func _contour_resolve() -> void:
	if OS.get_environment("STRATA_CONTOUR") != "1":
		_contour_mode = 1   # flag off — the GDScript twin, forever byte-identical
		return
	# Flag ON: engage the bridge, or REFUSE loudly (never a silent GDScript pass).
	if not ContourBridge.available():
		push_error("[agent_sim] STRATA_CONTOUR=1 but the Contour kernel is unavailable "
			+ "(not macOS / dylib absent) — refusing to silently run the GDScript twin")
		_contour_mode = -1
		return
	var bridge := ContourBridge.new(WorldState)
	var err := bridge.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[agent_sim] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	# agent_sim MULTIPLEXES the whole herd through ONE held world — every mind is
	# re-injected and read back each tick, so the held path MUST keep full-set
	# injection + diff-or-inject apply (a between-mind WorldState holds the prior
	# mind's value; a singleton diff-only apply would read back stale). Declared
	# EXPLICITLY (never inferred) so a future default flip can't silently break it
	# — this is E1d's hard lesson (docs/SUBSTRATE.md §1, the F2 rung).
	bridge.set_held_mode(ContourBridge.HELD_MODE_MULTIPLEXED)
	_contour_bridge = bridge
	_contour_mode = 2
	# The Rung 2 DARK sub-flag: only meaningful once the bridge is live. Off by
	# default; on, every mind's advance() routes through the persistent held world.
	_contour_held = OS.get_environment("STRATA_CONTOUR_HELD") == "1"


## Routing introspection for the soak (proves the herd's minds ran through
## Contour, not a silent fallback): the resolved mode, whether it engaged, the
## class-wide advance() tick count, and — for the substrate Rung 2 sub-flag —
## whether the held path ran and how often (held_ticks climbs only when
## STRATA_CONTOUR_HELD=1 routed the in-place tick). Static — shared by every mind.
static func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls,
		"held": _contour_held, "held_ticks": _contour_held_ticks}


## The flag-ON tick: hand this mind's whole record + live environment to the
## Contour `AgentMind` system. Seeds the SAME inputs the twin reads (the drives,
## tunables, activities; the hour — solar or clock, chosen by solar_gate; the
## storm boost's storminess; day_length for the move) and the persistent state it
## owns (needs/pos/target/current/produced), plus the SEEDED stream pulled off
## Rng.stream(rng_stream) — so the system draws from the identical shared stream
## and, on write-back, we thread the advanced state BACK so the autoload persists
## it and both paths stay in lockstep. The Callable marker_resolver is PRE-RESOLVED
## into data (agent.markers) GDScript-side (CONTOUR.md §4). Returns false on a
## refused tick (loud — never a silent GDScript pass).
func _advance_contour(bridge: ContourBridge, dt_hours: float) -> bool:
	var stream := Rng.stream(rng_stream)
	var cohesive := roam_center.is_finite()
	var inputs := {
		"agent.needs": needs,
		"agent.needs_def": needs_def,
		"agent.activities": activities,
		"agent.current": current,
		"agent.produced": produced,
		"agent.pos": pos,
		"agent.target": target,
		"agent.home": home,
		"agent.jitter": jitter,
		"agent.roam_center": roam_center if cohesive else Vector2.ZERO,
		"agent.has_cohesion": cohesive,
		"agent.roam_range": roam_range,
		"agent.cohesion_radius": cohesion_radius,
		"agent.markers": _resolve_markers(),
		"agent.hour": GameClock.solar_hours() if solar_gate else GameClock.hours,
		"agent.storminess": Weather.storminess,
		"agent.speed": speed,
		"agent.arrive": arrive,
		"agent.keep_bias": keep_bias,
		"agent.drain_scale": drain_scale,
		"agent.day_length_minutes": GameClock.day_length_minutes,
		"agent.dt_hours": dt_hours,
		"agent.rng": int(stream.state),
	}
	_contour_calls += 1
	# STRATA_CONTOUR_HELD=1: the PERSISTENT HELD WORLD path (substrate Rung 2) —
	# the ONE held world (shared across every mind) is created once and ticked IN
	# PLACE, only the write-diff crossing back. Each tick re-injects this mind's
	# whole record, so the held world is fully overwritten per mind and the
	# WorldState effect is byte-identical to tick_seeded (the copy path stays the
	# oracle); its own class-wide counter proves the in-place path ran.
	var applied: bool
	if _contour_held:
		applied = bridge.tick_held(inputs, dt_hours)
		if applied:
			_contour_held_ticks += 1
	else:
		applied = bridge.tick_seeded(inputs, dt_hours)
	if not applied:
		push_error("[agent_sim] STRATA_CONTOUR=1 but the AgentMind system tick was refused"
			+ " — refusing to silently run the GDScript twin")
		return false
	# Read back the system's declared writes; thread the advanced stream state back
	# into the autoload so it persists and the next mind continues the SAME stream.
	needs = WorldState.get_value("agent.needs", needs)
	pos = WorldState.get_value("agent.pos", pos)
	target = WorldState.get_value("agent.target", target)
	current = WorldState.get_value("agent.current", current)
	produced = WorldState.get_value("agent.produced", produced)
	last_utilities = WorldState.get_value("agent.last_utilities", last_utilities)
	stream.state = int(WorldState.get_value("agent.rng", int(stream.state)))
	return true


## Pre-resolve every marker an activity names into a live world XZ (the Callable
## marker_resolver's job, done as DATA GDScript-side — CONTOUR.md §4). A marker
## whose resolver is unbound (wildlife) or returns INF (deleted) is simply OMITTED,
## and the port reads an absent marker as "fall back to home" — byte-identical to
## resolve_at's marker branch. Only marker-shaped `at`s are resolved.
func _resolve_markers() -> Dictionary:
	var out: Dictionary = {}
	if not marker_resolver.is_valid():
		return out
	for a in activities:
		var at_v: Variant = a.get("at")
		if at_v is Dictionary and (at_v as Dictionary).has("marker"):
			var mid := String((at_v as Dictionary).marker)
			var p: Vector2 = marker_resolver.call(mid)
			if p.is_finite():
				out[mid] = p
	return out


func arrived() -> bool:
	return (target - pos).length() < arrive


func drain(dt_hours: float) -> void:
	for need in needs:
		needs[need] = clampf(
			needs[need] - needs_def.get(need, 1.0) * drain_scale * dt_hours,
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
	var at: Variant = a.get("at")
	if at is Dictionary:
		# A marker target (schedules #3): the activity names a placed marker
		# by its stable cell-record id; the owner's resolver turns it into the
		# marker's live XZ. Resolution happens HERE — at schedule time, when a
		# new activity is chosen — so a marker the hand moved is honoured on
		# the next decision. A marker that's GONE (deleted), or an agent with
		# no resolver (wildlife), falls back to home: honest, never a crash.
		if at.has("marker"):
			if marker_resolver.is_valid():
				var p: Vector2 = marker_resolver.call(String(at.marker))
				if p.is_finite():
					return p
			return home
		return Vector2(at.x, at.z)
	if at == "roam":
		var rng := Rng.stream(rng_stream)
		var center := home
		var radius := roam_range
		if roam_center.is_finite():
			center = roam_center
			radius = cohesion_radius
		var ang := rng.randf() * TAU
		return center + Vector2(cos(ang), sin(ang)) * rng.randf_range(0.2, 1.0) * radius
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


## One-line-per-fact dump for the Toolkit sim inspector.
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
