extends Node
## WildlifeManager: creatures with daily lives on the third simulation
## tier. Each animal is an AgentSim (the shared mind — SIM_ROADMAP P1)
## living as pure data; a body is spawned only when the focus comes near
## and freed when it leaves. Embodiment is presentation; the simulation
## never changes shape. Wildlife lives by the sun (solar-gated
## activities): drink at dawn, shade at noon, prowl between.
##
## Records: data/wildlife/*.json — home/range, activities, the body
## scene path, and the fabric chains its rig dangles (FW4: both used to
## be hardcoded in framework code — `BODY_SCENE`'s preload here and
## `PRESETS` in fabric_spring.gd — now per-creature record fields).
##
## Sim contract: stateful; advanced by live ticks and by the sim_advance
## group during catch-up; persisted hourly to WorldState
## ("wildlife.<species>"); world_state_reader group. Observability: the
## Toolkit right-click a body → sim_debug, like NPCs.

const EMBODY_DISTANCE := 130.0
const DISSOLVE_DISTANCE := 165.0  # hysteresis so the border doesn't flap
const LIVE_TICK := 0.5  # real seconds between live data ticks

var herds: Array = []  # {species, activities, individuals: [{sim, body}]}

var _tick_accum := 0.0


func _ready() -> void:
	add_to_group("sim_advance")
	add_to_group("world_state_reader")
	var records: Dictionary = Records.load_dir("res://data/wildlife", {
		"id": TYPE_STRING, "count": TYPE_FLOAT,
		"home": TYPE_DICTIONARY, "activities": TYPE_ARRAY,
		"body_scene": TYPE_STRING,
	})
	for key in records:
		spawn_herd(records[key])
	load_state()
	GameClock.hour_tick.connect(func(_h: int) -> void: _save_state())


func spawn_herd(data: Dictionary) -> Dictionary:
	var herd := {
		"species": data.id,
		"activities": data.activities,
		"body_scene": data.body_scene,
		"fabric": data.get("fabric", []),
		"individuals": [],
	}
	var rng := Rng.stream("wildlife")
	for i in int(data.count):
		var sim := AgentSim.new()
		sim.setup("%s_%d" % [data.id, i],
			Vector2(data.home.x, data.home.z), data.activities)
		sim.solar_gate = true
		sim.rng_stream = "wildlife"
		sim.roam_range = float(data.get("range", 150.0))
		sim.jitter = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 7.0
		herd.individuals.append({"sim": sim, "body": null})
	herds.append(herd)
	return herd


## Herd cohesion (SIM_ROADMAP wildlife rung 2): roam targets draw around
## the group's centroid, clamped inside the home range — the herd drifts
## through its territory as one animal-shaped cloud, and reads as a herd
## from a ridge away.
func _update_cohesion(herd: Dictionary) -> void:
	if herd.individuals.is_empty():
		return
	var centroid := Vector2.ZERO
	for ind in herd.individuals:
		centroid += ind.sim.pos
	centroid /= herd.individuals.size()
	var lead: AgentSim = herd.individuals[0].sim
	var off := centroid - lead.home
	if off.length() > lead.roam_range:
		centroid = lead.home + off.normalized() * lead.roam_range
	for ind in herd.individuals:
		ind.sim.roam_center = centroid


## Catch-up: every animal lives the skipped hours as data; bodies are
## re-seated on their records afterwards.
func sim_advance_hours(dt_hours: float) -> void:
	for herd in herds:
		_update_cohesion(herd)
		for ind in herd.individuals:
			var sim: AgentSim = ind.sim
			if ind.body != null:
				sim.pos = Vector2(ind.body.global_position.x, ind.body.global_position.z)
			sim.advance(dt_hours)
			if ind.body != null:
				ind.body.seat(sim.pos, sim.target)


func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < LIVE_TICK:
		return
	var dt_hours: float = GameClock.hours_delta(_tick_accum)
	_tick_accum = 0.0
	var focus := _focus_position()
	for herd in herds:
		_update_cohesion(herd)
		for ind in herd.individuals:
			var sim: AgentSim = ind.sim
			if ind.body != null:
				# Body owns position; the mind keeps drives and decisions.
				sim.pos = Vector2(ind.body.global_position.x, ind.body.global_position.z)
				sim.drain(dt_hours)
				if sim.arrived():
					sim.satisfy(dt_hours)
				sim.decide()
				ind.body.set_target(sim.target)
			else:
				sim.advance(dt_hours)
			var d := focus.distance_to(sim.pos)
			if ind.body == null and d < EMBODY_DISTANCE:
				_embody(herd, ind)
			elif ind.body != null and d > DISSOLVE_DISTANCE:
				_dissolve(ind)


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


func _embody(herd: Dictionary, ind: Dictionary) -> void:
	var sim: AgentSim = ind.sim
	# Loaded, not preloaded (FW4): the body scene is a record field, so
	# a content-empty game with no wildlife records never touches a
	# missing path, and each record can point at its own body.
	var scene: PackedScene = load(herd.body_scene)
	var body := scene.instantiate()
	body.species = herd.species
	body.fabric_chains = herd.fabric
	body.sim = sim  # shared reference: the inspector reads the live mind
	add_child(body)
	body.global_position = Vector3(
		sim.pos.x, Terrain.height(sim.pos.x, sim.pos.y) + 0.4, sim.pos.y)
	body.set_target(sim.target)
	ind.body = body


func _dissolve(ind: Dictionary) -> void:
	var sim: AgentSim = ind.sim
	sim.pos = Vector2(ind.body.global_position.x, ind.body.global_position.z)
	ind.body.queue_free()
	ind.body = null


func _save_state() -> void:
	for herd in herds:
		var rows: Array = []
		for ind in herd.individuals:
			rows.append(ind.sim.to_state())
		WorldState.set_value("wildlife.%s" % herd.species, rows)


func load_state() -> void:
	for herd in herds:
		var rows: Array = WorldState.get_value("wildlife.%s" % herd.species, [])
		for i in mini(rows.size(), herd.individuals.size()):
			herd.individuals[i].sim.from_state(rows[i])
