extends Node
## VillagerManager (autoload): THE CAST SHEET — a named inhabitant with a
## daily life, raised from a first-class CHARACTER record on the third
## simulation tier the wildlife ride (SIM_ROADMAP P1). Each character is an
## AgentSim — the shared mind (game/sim/agent_sim.gd) — living as pure data;
## a body is spawned only when the focus comes near and freed when it leaves.
##
## The CHARACTER record (data/characters/<id>.json), the CK "packages door"
## promoted to a validated kind (CREATION_KIT_REVIEW_V2 #3):
##
##   {
##     "id": "mara",
##     "identity": { "name": "Mara", "kind": "villager" },   // villager | creature
##     "body":     { "card": "chars/villager_keeper",        // a model-card slot (Cards)
##                   "palette": { "base": [0.7, 0.5, 0.4] },  // optional CharacterPaint tint
##                   "scene": "res://game/villagers/villager_body.tscn" }, // optional shell
##     "home":     { "x": -120, "z": -300 },                 // raw XZ, or { "marker": "<id>" }
##     "schedule": [ ... activities (the star_hounds.json shape) ... ],
##     "mind":     { "needs": { "work": 1.2 }, "keep_bias": 1.15, "roam_range": 150 } // optional
##   }
##
## The `identity.kind` gives the record teeth: a **villager** lives by the
## CLOCK (schedule hours gate against wall time — garden by morning, home by
## night) and drains harder; a **creature** lives by the SUN (solar hours)
## like the wildlife, but as a LONE embodied character rather than a herd.
## `mind` tunes the AgentMind directly: `needs` are per-need drain weights,
## `keep_bias` the hysteresis that keeps a chosen activity, `roam_range` how
## far "roam" wanders. An activity's `at` (and `home`) may be a raw {x,z},
## "roam", or a MARKER — {"marker": "<placed-record-id>"} — resolved at
## schedule time to the marker's live position (see _resolve_marker).
##
## Framework, not content: this machinery ships in every scaffolded game,
## but it is CONTENT-EMPTY by default — no records under data/characters
## means no minds, no bodies, no ticks, and a bit-identical soak (a mind
## only ever exists when a record does, and valley ships none live yet — the
## example character rides tests/fixtures/characters, dark to the sim). The
## records desk (Strata R5) edits a character's day for free: `records
## reload characters` re-reads and respawns, the same door a restart takes.
##
## Sim contract: stateful; advanced by live ticks and by the sim_advance
## group during catch-up; persisted hourly to WorldState ("villager.<id>").

const EMBODY_DISTANCE := 130.0
const DISSOLVE_DISTANCE := 165.0  # hysteresis so the border doesn't flap
const LIVE_TICK := 0.5  # real seconds between live data ticks
const DATA_DIR := "res://data/characters"
const DEFAULT_BODY := "res://game/villagers/villager_body.tscn"
## The record kinds `identity.kind` enumerates. A villager keeps a human
## clock; a creature keeps the sun — the one switch the kind flips (below).
const KINDS: Array[String] = ["villager", "creature"]
## The kind's required-FIELD schema (Records.validate's field-type gate). The
## nested SHAPE inside these — identity's name/kind, body's card, home's
## place, the schedule's soundness, mind's knobs — is the semantic
## validator's job (validate_character); the desk runs both, field-types then
## semantics (the quests -> QuestLint pattern).
const SCHEMA := {
	"id": TYPE_STRING, "identity": TYPE_DICTIONARY,
	"body": TYPE_DICTIONARY, "home": TYPE_DICTIONARY,
	"schedule": TYPE_ARRAY,
}

var villagers: Array = []  # [{id, name, kind, scene, palette, card, sim, body}]

var _tick_accum := 0.0


func _ready() -> void:
	add_to_group("sim_advance")
	add_to_group("world_state_reader")
	_load()
	# The records desk (Strata R5): after a landed edit, `records reload
	# characters` re-reads and respawns — the same door F5 would take on a
	# restart, minus the restart. Its schema (SCHEMA above, registered by
	# _load's load_dir) is what the desk validates an edit against.
	Records.register_reloader("characters", reload)
	# Full validate coverage (CREATION_KIT_REVIEW_V2 #3a, the quests->QuestLint
	# pattern): the field schema alone can only see that `identity`/`body`/`home`
	# are objects and `schedule` an Array; the SHAPE inside them (a villager|
	# creature kind, a card slot, a sound schedule, well-formed places and mind
	# knobs) is a semantic rule only spawn_character knew. Registered here as the
	# kind's validator, `records validate characters` runs the SAME judgement the
	# loader does — so the desk can never green-light a character whose record
	# spawn_character would reject and silently drop. The loader judges the desk.
	Records.register_validator("characters", validate_character)
	# The world budget's agent axis (a METER, NOT A WALL): every mind counts
	# toward the live-agent tally, embodied or not. Read-only.
	Budget.register_population(_population)
	GameClock.hour_tick.connect(func(_h: int) -> void: _save_state())


## Live agent count for the world budget (0 when content-empty).
func _population() -> int:
	return villagers.size()


## Read the character records and raise one mind per record, then restore
## persisted state. The boot path AND the desk's reload path — one truth,
## so a live re-read builds exactly what a fresh boot would. A record whose
## shape is malformed is dropped with a clear error (validate coverage over
## and above the kind's field schema).
func _load() -> void:
	var records: Dictionary = Records.load_dir(DATA_DIR, SCHEMA)
	for key in records:
		spawn_character(records[key])
	load_state()


## Live re-read (the records desk): dissolve every embodied character, drop
## the minds, and rebuild from disk. A rebuild, not a diff — positions and
## drives reset to the records' homes; honest (what the next boot gives).
func reload() -> void:
	for v in villagers:
		if v.body != null:
			v.body.queue_free()
	villagers.clear()
	_load()


## Validate a schedule (the activities list): every activity needs a string
## `id` and a string `satisfies` (the need it feeds — AgentSim scores against
## it). Returns "" when the schedule is sound, else the first activity's
## failure — the same words-back shape Records.validate_message uses, so the
## desk can surface it. Static and pure: the records desk (and the character
## lint) can call it without a manager.
##
## RULES-TIER PORT (Mission C3): this is the manager's one closed sim rule,
## Plumb-certified bit-for-bit vs the Contour port game/villagers/villager_manager.ct
## (validate_schedule) — the error SENTENCES asserted verbatim. Do NOT change its
## words or branches without re-certifying the port. The per-tick sim itself is
## AgentSim.advance, routed through the §6 `AgentMind` system; this desk lint
## stays GDScript (a load-time judgement, no fingerprint pressure).
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


## The characters kind's semantic validator (Records.validate_kind runs it
## after the field schema — the quests->QuestLint pattern — and the character
## lint runs it over the fixture corpus). Judges the nested SHAPE the flat
## field-type map can't see, in the loaders' own validate-table idiom: one
## check per rule, each returning the game's own refusal SENTENCE (the first
## failure wins). Static + pure — the desk calls it without a manager. Returns
## "" when the record is sound.
static func validate_character(record: Dictionary) -> String:
	# identity — a display name and one of the enumerated kinds.
	var identity: Variant = record.get("identity")
	if not (identity is Dictionary):
		return "field 'identity' should be an object (name, kind)"
	if not (identity.get("name") is String) or String(identity.name).is_empty():
		return "identity missing string 'name'"
	if not (identity.get("kind") is String) or not KINDS.has(identity.kind):
		return "identity 'kind' must be one of villager|creature (got '%s')" \
			% str(identity.get("kind"))
	# body — a model-card slot, an optional shell scene, an optional palette.
	var body: Variant = record.get("body")
	if not (body is Dictionary):
		return "field 'body' should be an object (card, palette, scene)"
	if not (body.get("card") is String) or String(body.card).is_empty():
		return "body missing string 'card' (a model-card slot)"
	if body.has("scene") and not (body.get("scene") is String):
		return "body 'scene' should be a string (a res:// path)"
	if body.has("palette") and not (body.get("palette") is Dictionary):
		return "body 'palette' should be an object (surface tints)"
	# home — a place: raw {x,z} or a {marker} ref (no "roam" home).
	var home: Variant = record.get("home")
	if not (home is Dictionary):
		return "field 'home' should be an object ({x,z} or {marker})"
	var home_msg := _validate_place(home, "home", false)
	if home_msg != "":
		return home_msg
	# schedule — the activities list, sound (id + satisfies), each `at` a
	# well-formed place ({x,z}, {marker}, or "roam").
	var schedule: Variant = record.get("schedule")
	if not (schedule is Array):
		return "field 'schedule' should be an array of activities"
	var sched_msg := validate_schedule(schedule)
	if sched_msg != "":
		return sched_msg
	for i in (schedule as Array).size():
		var a: Variant = schedule[i]
		if a is Dictionary and (a as Dictionary).has("at"):
			var at_msg := _validate_place(a.at, "activity '%s'" % a.get("id", i), true)
			if at_msg != "":
				return at_msg
	# mind — optional AgentMind tunables.
	var mind: Variant = record.get("mind", {})
	if not (mind is Dictionary):
		return "field 'mind' should be an object (needs, keep_bias, roam_range)"
	if mind.has("needs"):
		if not (mind.needs is Dictionary):
			return "mind 'needs' should be an object (need -> drain weight)"
		for k in mind.needs:
			if not _is_number(mind.needs[k]):
				return "mind needs weight for '%s' should be a number" % k
	for knob in ["keep_bias", "roam_range"]:
		if mind.has(knob) and not _is_number(mind[knob]):
			return "mind '%s' should be a number" % knob
	return ""


## A place value — a home or a schedule activity's `at`. Well-formed when it
## is a raw {x,z} (numbers), a {marker} carrying a non-empty record id, or (for
## a schedule `at`, allow_roam) the string "roam". Returns "" when sound, else
## the labelled refusal. The marker's RESOLVABILITY is a runtime truth (a
## deleted marker falls back to home by design, never a lint failure); the lint
## checks the reference is well-SHAPED, which is what makes it resolvable at all.
static func _validate_place(place: Variant, label: String, allow_roam: bool) -> String:
	if place is String:
		if allow_roam and place == "roam":
			return ""
		return "%s must be {x,z}, {marker}, or \"roam\"" % label if allow_roam \
			else "%s must be {x,z} or {marker}" % label
	if not (place is Dictionary):
		return "%s must be {x,z}, {marker}, or \"roam\"" % label if allow_roam \
			else "%s must be {x,z} or {marker}" % label
	var d := place as Dictionary
	if d.has("marker"):
		if not (d.get("marker") is String) or String(d.marker).is_empty():
			return "%s marker ref must be a non-empty record id" % label
		return ""
	if d.has("x") and d.has("z"):
		if not _is_number(d.x) or not _is_number(d.z):
			return "%s position x/z must be numbers" % label
		return ""
	return "%s needs x/z or a marker" % label


## Numbers arrive from JSON as float; a hand-typed int is a number too.
static func _is_number(v: Variant) -> bool:
	return v is float or v is int


## Raise one character mind from a record. Returns the entry (the test drives
## it directly, the WildlifeManager.spawn_herd shape). Validated first — a
## malformed record is refused loudly and never becomes a mind (the same
## judgement the desk answers, so a bounced edit and a dropped load agree).
func spawn_character(data: Dictionary) -> Dictionary:
	var msg := validate_character(data)
	if msg != "":
		push_error("[characters] %s: %s" % [data.get("id", "?"), msg])
		return {}
	var identity: Dictionary = data.identity
	var body: Dictionary = data.body
	var ckind := String(identity.kind)
	var home_xz := _place_to_xz(data.home)
	var sim := AgentSim.new()
	sim.setup(str(data.id), home_xz, data.schedule, _needs_weights(data))
	# The one switch identity.kind flips: a villager keeps the human clock, a
	# creature the sun (like the wildlife). Everything else is shared mind.
	sim.solar_gate = ckind == "creature"
	sim.rng_stream = "villager" if ckind == "villager" else "creature"
	sim.drain_scale = 6.0 if ckind == "villager" else 5.0  # people drain harder
	sim.marker_resolver = _resolve_marker  # schedules may target placed markers
	# mind knobs (optional): tune the AgentMind directly from the record.
	var mind: Dictionary = data.get("mind", {})
	if _is_number(mind.get("keep_bias")):
		sim.keep_bias = float(mind.keep_bias)
	if _is_number(mind.get("roam_range")):
		sim.roam_range = float(mind.roam_range)
	var entry := {
		"id": str(data.id), "name": str(identity.name), "kind": ckind,
		"card": str(body.card), "palette": body.get("palette", {}),
		"scene": str(body.get("scene", DEFAULT_BODY)), "sim": sim, "body": null,
	}
	villagers.append(entry)
	return entry


## The record's `needs` mind-knob as AgentSim.setup's weights (need -> drain
## weight). Empty (no mind, or no needs) leaves setup to derive weight 1.0 per
## activity's `satisfies` — the honest default.
func _needs_weights(data: Dictionary) -> Dictionary:
	var mind: Variant = data.get("mind", {})
	if mind is Dictionary and (mind as Dictionary).get("needs") is Dictionary:
		var out: Dictionary = {}
		for k in mind.needs:
			out[k] = float(mind.needs[k])
		return out
	return {}


## A home place -> world XZ at spawn. A raw {x,z} is itself; a {marker} home
## resolves to the marker's live position, falling back to the origin (with a
## warning) when the marker is gone — a home with no anchor is honest about it.
func _place_to_xz(place: Dictionary) -> Vector2:
	if place.has("marker"):
		var p: Vector2 = _resolve_marker(String(place.marker))
		if p.is_finite():
			return p
		push_warning("[characters] home marker '%s' is gone — spawning at origin"
			% place.marker)
		return Vector2.ZERO
	return Vector2(float(place.x), float(place.z))


## Turn a schedule's marker id into the marker's live world XZ (schedules #3).
## A marker is a placed cell-record (authored as a card carrying the "marker"
## keyword, Cards.is_marker); we find it by its stable id and hand back where
## it stands. Vector2.INF when it's gone — AgentSim reads that as "fall back to
## home", the honest answer when the hand deleted it.
func _resolve_marker(id: String) -> Vector2:
	var found: Dictionary = CellRecords.find_record(id)
	if found.is_empty():
		return Vector2.INF
	var rec: Dictionary = found.rec
	return Vector2(float(rec.x), float(rec.z))


## Catch-up: every character lives the skipped hours as data; bodies are
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
	# content-empty game never touches a missing path, and each character
	# can wear a different body (the fox/biped placeholder by default).
	var scene: PackedScene = load(v.scene)
	var body := scene.instantiate()
	body.villager_name = v.name
	body.palette = v.palette  # the record's CharacterPaint tint (empty = flat art)
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
