extends Node
## VillagerManager (autoload): a named person with a daily life, on the
## same third simulation tier the wildlife ride (SIM_ROADMAP P1). Each
## villager is an AgentSim — the shared mind (game/sim/agent_sim.gd) —
## living as pure data; a body is spawned only when the focus comes near
## and freed when it leaves. Where wildlife lives by the sun, a villager
## lives by the CLOCK: its schedule's hour windows gate against wall time,
## so it keeps a human day (garden by morning, home by night).
##
## "Every future agent is an AgentSim plus a record" (agent_sim.gd) — this
## is the villager's record kind. Records: data/villagers/*.json — name,
## home, the body scene (the creature-record pattern: WildlifeManager's
## body_scene, reused), and a `schedule` (an activities list: at / satisfies
## / rate / hours, the star_hounds.json shape). An activity's `at` may be a
## raw {x,z}, "roam", or a MARKER — {"marker": "<placed-record-id>"} — which
## resolves at schedule time to the marker's live position (see _resolve_marker;
## CREATION_KIT_REVIEW_V2 #3).
##
## Framework, not content: this machinery ships in every scaffolded game,
## but it is CONTENT-EMPTY by default — no records under data/villagers
## means no minds, no bodies, no ticks, and a bit-identical soak (a mind
## only ever exists when a record does, and valley ships none yet). The
## records desk (Strata R5) edits a villager's day for free: `records
## reload villagers` re-reads and respawns, the same door a restart takes.
##
## Sim contract: stateful; advanced by live ticks and by the sim_advance
## group during catch-up; persisted hourly to WorldState ("villager.<id>").

const EMBODY_DISTANCE := 130.0
const DISSOLVE_DISTANCE := 165.0  # hysteresis so the border doesn't flap
const LIVE_TICK := 0.5  # real seconds between live data ticks
const DATA_DIR := "res://data/villagers"
const SCHEMA := {
	"id": TYPE_STRING, "name": TYPE_STRING,
	"home": TYPE_DICTIONARY, "body_scene": TYPE_STRING,
	"schedule": TYPE_ARRAY,
}

var villagers: Array = []  # [{id, name, body_scene, sim, body}]

var _tick_accum := 0.0


func _ready() -> void:
	add_to_group("sim_advance")
	add_to_group("world_state_reader")
	_load()
	# The records desk (Strata R5): after a landed edit, `records reload
	# villagers` re-reads and respawns — the same door F5 would take on a
	# restart, minus the restart. Its schema (SCHEMA above, registered by
	# _load's load_dir) is what the desk validates an edit against.
	Records.register_reloader("villagers", reload)
	# The world budget's agent axis (a METER, NOT A WALL): every mind counts
	# toward the live-agent tally, embodied or not. Read-only.
	Budget.register_population(_population)
	GameClock.hour_tick.connect(func(_h: int) -> void: _save_state())


## Live agent count for the world budget (0 when content-empty).
func _population() -> int:
	return villagers.size()


## Read the villager records and raise one mind per record, then restore
## persisted state. The boot path AND the desk's reload path — one truth,
## so a live re-read builds exactly what a fresh boot would. A record whose
## schedule is malformed is dropped with a clear error (validate coverage
## for the schedule, over and above the kind's field schema).
func _load() -> void:
	var records: Dictionary = Records.load_dir(DATA_DIR, SCHEMA)
	for key in records:
		spawn_villager(records[key])
	load_state()


## Live re-read (the records desk): dissolve every embodied villager, drop
## the minds, and rebuild from disk. A rebuild, not a diff — positions and
## drives reset to the records' homes; honest (what the next boot gives).
func reload() -> void:
	for v in villagers:
		if v.body != null:
			v.body.queue_free()
	villagers.clear()
	_load()


## Validate a schedule (the activities list) beyond the kind's field
## schema: every activity needs a string `id` and a string `satisfies`
## (the need it feeds — AgentSim scores against it). Returns "" when the
## schedule is sound, else the first activity's failure — the same
## words-back shape Records.validate_message uses, so the desk can surface
## it. Static and pure: the records desk can call it without a manager.
static func validate_schedule(schedule: Array) -> String:
	for i in schedule.size():
		var a: Variant = schedule[i]
		if not (a is Dictionary):
			return "activity %d is not an object" % i
		if not (a.get("id") is String) or String(a.id).is_empty():
			return "activity %d missing string 'id'" % i
		if not (a.get("satisfies") is String) or String(a.satisfies).is_empty():
			return "activity '%s' missing string 'satisfies'" % a.get("id", i)
	return ""


## Raise one villager mind from a record. Returns the villager entry (the
## test drives it directly, the WildlifeManager.spawn_herd shape).
func spawn_villager(data: Dictionary) -> Dictionary:
	var msg := validate_schedule(data.schedule)
	if msg != "":
		push_error("[villagers] %s: %s" % [data.get("id", "?"), msg])
		return {}
	var sim := AgentSim.new()
	sim.setup(str(data.id), Vector2(data.home.x, data.home.z), data.schedule)
	sim.solar_gate = false  # a person lives by the clock, not the sun
	sim.rng_stream = "villager"
	sim.drain_scale = 6.0  # people drain harder than wildlife (agent_sim.gd)
	sim.marker_resolver = _resolve_marker  # schedules may target placed markers
	var entry := {
		"id": str(data.id), "name": str(data.name),
		"body_scene": str(data.body_scene), "sim": sim, "body": null,
	}
	villagers.append(entry)
	return entry


## Turn a schedule's marker id into the marker's live world XZ (schedules
## #3). A marker is a placed cell-record (authored as a card carrying the
## "marker" keyword, Cards.is_marker); we find it by its stable id and hand
## back where it stands. Vector2.INF when it's gone — AgentSim reads that
## as "fall back to home", the honest answer when the hand deleted it.
func _resolve_marker(id: String) -> Vector2:
	var found: Dictionary = CellRecords.find_record(id)
	if found.is_empty():
		return Vector2.INF
	var rec: Dictionary = found.rec
	return Vector2(float(rec.x), float(rec.z))


## Catch-up: every villager lives the skipped hours as data; bodies are
## re-seated on their minds afterwards (the WildlifeManager pattern).
func sim_advance_hours(dt_hours: float) -> void:
	for v in villagers:
		var sim: AgentSim = v.sim
		if v.body != null:
			sim.pos = Vector2(v.body.global_position.x, v.body.global_position.z)
		sim.advance(dt_hours)
		if v.body != null:
			v.body.seat(sim.pos, sim.target)


func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < LIVE_TICK:
		return
	var dt_hours: float = GameClock.hours_delta(_tick_accum)
	_tick_accum = 0.0
	var focus := _focus_position()
	for v in villagers:
		var sim: AgentSim = v.sim
		if v.body != null:
			# Body owns position; the mind keeps drives and decisions.
			sim.pos = Vector2(v.body.global_position.x, v.body.global_position.z)
			sim.drain(dt_hours)
			if sim.arrived():
				sim.satisfy(dt_hours)
			sim.decide()
			v.body.set_target(sim.target)
			v.body.set_activity(sim.current)
		else:
			sim.advance(dt_hours)
		var d := focus.distance_to(sim.pos)
		if v.body == null and d < EMBODY_DISTANCE:
			_embody(v)
		elif v.body != null and d > DISSOLVE_DISTANCE:
			_dissolve(v)


func _focus_position() -> Vector2:
	if Toolkit.active:
		var c := Toolkit.cam_position()
		return Vector2(c.x, c.z)
	if MapScreen.active:
		var m := MapScreen.focus_position()
		return Vector2(m.x, m.z)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		return Vector2(player.global_position.x, player.global_position.z)
	return Vector2.INF


func _embody(v: Dictionary) -> void:
	var sim: AgentSim = v.sim
	# Loaded, not preloaded (FW4): the body scene is a record field, so a
	# content-empty game never touches a missing path, and each villager
	# can wear a different body (the fox/biped placeholder by default).
	var scene: PackedScene = load(v.body_scene)
	var body := scene.instantiate()
	body.villager_name = v.name
	body.sim = sim  # shared reference: the inspector reads the live mind
	add_child(body)
	body.global_position = Vector3(
		sim.pos.x, Terrain.height(sim.pos.x, sim.pos.y) + 0.4, sim.pos.y)
	body.set_target(sim.target)
	body.set_activity(sim.current)
	v.body = body


func _dissolve(v: Dictionary) -> void:
	var sim: AgentSim = v.sim
	sim.pos = Vector2(v.body.global_position.x, v.body.global_position.z)
	v.body.queue_free()
	v.body = null


func _save_state() -> void:
	for v in villagers:
		WorldState.set_value("villager.%s" % v.id, v.sim.to_state())


func load_state() -> void:
	for v in villagers:
		var state: Dictionary = WorldState.get_value("villager.%s" % v.id, {})
		if not state.is_empty():
			v.sim.from_state(state)
