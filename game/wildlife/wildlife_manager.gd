extends Node
## WildlifeManager: creatures with daily lives, and the third simulation
## tier arriving ahead of the village. A herd is DATA — plain records
## (position, drives, activity) advanced by the same utility logic at
## every fidelity. A body (hound_body.tscn) is spawned only when the
## focus comes near and freed when it leaves: embodiment is presentation,
## the simulation never changes shape. Wildlife follows the sun
## (solar hours), not the clock — drink at dawn, shade at noon, prowl
## between.
##
## Records: data/wildlife/*.json — home/range plus NPC-shaped activities.
## Placeholder: bodies reuse the star hound glb until canon names the
## valley's creatures (STATUS ledger).
##
## Sim contract: stateful; advanced by live ticks and by the sim_advance
## group during catch-up; persisted hourly to WorldState
## ("wildlife.<species>"); world_state_reader group. Observability: god
## mode right-click a body → sim_debug, like NPCs.

const BODY_SCENE := preload("res://game/wildlife/hound_body.tscn")
const EMBODY_DISTANCE := 130.0
const DISSOLVE_DISTANCE := 165.0  # hysteresis so the border doesn't flap
const SPEED := 2.2  # m/s, an unhurried trot
const ARRIVE := 4.0
const LIVE_TICK := 0.5  # real seconds between live data ticks
const DRIVE_DRAIN := 5.0  # points per game-hour
const OFF_HOURS_GATE := 0.15
const SATISFY_SCALE := 10.0

var herds: Array = []  # {species, home, range, activities, individuals[]}

var _tick_accum := 0.0


func _ready() -> void:
	add_to_group("sim_advance")
	add_to_group("world_state_reader")
	var records: Dictionary = Records.load_dir("res://data/wildlife", {
		"id": TYPE_STRING, "count": TYPE_FLOAT,
		"home": TYPE_DICTIONARY, "activities": TYPE_ARRAY,
	})
	for key in records:
		spawn_herd(records[key])
	load_state()
	GameClock.hour_tick.connect(func(_h: int) -> void: _save_state())


func spawn_herd(data: Dictionary) -> Dictionary:
	var home := Vector2(data.home.x, data.home.z)
	var herd := {
		"species": data.id,
		"home": home,
		"range": float(data.get("range", 150.0)),
		"activities": data.activities,
		"individuals": [],
	}
	var drives := {}
	for a in data.activities:
		drives[a.satisfies] = 70.0
	for i in int(data.count):
		var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 7.0
		herd.individuals.append({
			"pos": home + jitter,
			"target": home + jitter,
			"drives": drives.duplicate(),
			"activity": {},
			"jitter": jitter,
			"body": null,
		})
	herds.append(herd)
	return herd


## One coarse step for one animal — the same function during live play
## (data tier) and time catch-up. dt can be a whole hour: journeys
## complete and drives cycle while the player is away.
func advance_individual(herd: Dictionary, ind: Dictionary, dt_hours: float) -> void:
	for d in ind.drives:
		ind.drives[d] = clampf(ind.drives[d] - DRIVE_DRAIN * dt_hours, 0.0, 100.0)
	var dt_real := dt_hours * GameClock.day_length_minutes * 60.0 / 24.0
	var to: Vector2 = ind.target - ind.pos
	if to.length() < ARRIVE:
		_satisfy(ind, dt_hours)
	else:
		ind.pos += to.normalized() * minf(SPEED * dt_real, to.length())
	decide(herd, ind)


func _satisfy(ind: Dictionary, dt_hours: float) -> void:
	if ind.activity.is_empty():
		return
	var drive: String = ind.activity.satisfies
	ind.drives[drive] = clampf(
		ind.drives[drive] + float(ind.activity.get("rate", 6.0)) * SATISFY_SCALE * dt_hours,
		0.0, 100.0)


## Same utility scoring as the NPCs (extract a shared sim core when the
## village lands), gated on SOLAR hours — wildlife lives by the sun.
func decide(herd: Dictionary, ind: Dictionary) -> void:
	var best: Dictionary = {}
	var best_u := -1.0
	for a in herd.activities:
		var u: float = (100.0 - ind.drives.get(a.satisfies, 50.0)) * _hours_gate(a)
		if u > best_u:
			best_u = u
			best = a
	if best != ind.activity:
		ind.activity = best
		ind.target = _resolve_at(herd, best) + ind.jitter


func _hours_gate(a: Dictionary) -> float:
	if not a.has("hours"):
		return 1.0
	var start: float = a.hours[0]
	var end: float = a.hours[1]
	var h: float = GameClock.solar_hours()
	var inside := (h >= start and h < end) if start <= end \
			else (h >= start or h < end)
	return 1.0 if inside else OFF_HOURS_GATE


func _resolve_at(herd: Dictionary, a: Dictionary) -> Vector2:
	if a.get("at") is Dictionary:
		return Vector2(a.at.x, a.at.z)
	# "roam": somewhere new inside the herd's range.
	var ang := randf() * TAU
	return herd.home + Vector2(cos(ang), sin(ang)) * randf_range(0.2, 1.0) * herd.range


## Catch-up: every animal lives the skipped hour as data (bodies are
## re-seated on their records afterwards by the live tick).
func sim_advance_hours(dt_hours: float) -> void:
	for herd in herds:
		for ind in herd.individuals:
			if ind.body != null:
				ind.pos = Vector2(ind.body.global_position.x, ind.body.global_position.z)
			advance_individual(herd, ind, dt_hours)
			if ind.body != null:
				ind.body.seat(ind.pos, ind.target)


func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < LIVE_TICK:
		return
	var dt_hours: float = GameClock.hours_delta(_tick_accum)
	_tick_accum = 0.0
	var focus := _focus_position()
	for herd in herds:
		for ind in herd.individuals:
			if ind.body != null:
				# Body owns position; data keeps drives/decisions.
				ind.pos = Vector2(ind.body.global_position.x, ind.body.global_position.z)
				for d in ind.drives:
					ind.drives[d] = clampf(ind.drives[d] - DRIVE_DRAIN * dt_hours, 0.0, 100.0)
				if (ind.target - ind.pos).length() < ARRIVE:
					_satisfy(ind, dt_hours)
				decide(herd, ind)
				ind.body.set_target(ind.target)
			else:
				advance_individual(herd, ind, dt_hours)
			var d2 := focus.distance_to(ind.pos)
			if ind.body == null and d2 < EMBODY_DISTANCE:
				_embody(herd, ind)
			elif ind.body != null and d2 > DISSOLVE_DISTANCE:
				_dissolve(ind)


func _focus_position() -> Vector2:
	if GodMode.active:
		var c := GodMode.cam_position()
		return Vector2(c.x, c.z)
	if MapScreen.active:
		var m := MapScreen.focus_position()
		return Vector2(m.x, m.z)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		return Vector2(player.global_position.x, player.global_position.z)
	return Vector2.INF


func _embody(herd: Dictionary, ind: Dictionary) -> void:
	var body := BODY_SCENE.instantiate()
	body.species = herd.species
	body.info = ind  # shared reference: the inspector reads the live record
	add_child(body)
	body.global_position = Vector3(
		ind.pos.x, Terrain.height(ind.pos.x, ind.pos.y) + 0.4, ind.pos.y)
	body.set_target(ind.target)
	ind.body = body


func _dissolve(ind: Dictionary) -> void:
	ind.pos = Vector2(ind.body.global_position.x, ind.body.global_position.z)
	ind.body.queue_free()
	ind.body = null


func _save_state() -> void:
	for herd in herds:
		var rows: Array = []
		for ind in herd.individuals:
			rows.append({
				"x": ind.pos.x, "z": ind.pos.y,
				"drives": ind.drives.duplicate(),
				"activity": ind.activity.get("id", ""),
			})
		WorldState.set_value("wildlife.%s" % herd.species, rows)


func load_state() -> void:
	for herd in herds:
		var rows: Array = WorldState.get_value("wildlife.%s" % herd.species, [])
		for i in mini(rows.size(), herd.individuals.size()):
			var row: Dictionary = rows[i]
			var ind: Dictionary = herd.individuals[i]
			var x: float = row.x
			var z: float = row.z
			ind.pos = Vector2(x, z)
			for d in row.get("drives", {}):
				ind.drives[d] = float(row.drives[d])
			for a in herd.activities:
				if a.id == str(row.get("activity", "")):
					ind.activity = a
					ind.target = _resolve_at(herd, a) + ind.jitter
					break
