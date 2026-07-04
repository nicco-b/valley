extends Node
## Scene-context tests: anything that needs autoloads alive (Dialogue,
## WorldState interplay). Run by test.sh: godot --headless scene_tests.tscn
## — exits 0/1.

var _failures := 0


func _ready() -> void:
	_test_dialogue()
	_test_quests()
	_test_skills()
	_test_clock()
	_test_seasons()
	_test_climate()
	_test_water()
	_test_hydrology()
	_test_flora()
	_test_moon()
	_test_rumors()
	_test_wildlife()
	_test_long_memory()
	_test_nav()
	_test_sand_sim()
	if _failures > 0:
		print("SCENE-TESTS FAIL: %d failed" % _failures)
	else:
		print("SCENE-TESTS PASS")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


func _test_dialogue() -> void:
	_check(Dialogue._eval({}), "empty condition passes")
	WorldState.set_flag("test.flag")
	_check(Dialogue._eval({"flag": "test.flag"}), "flag condition")
	_check(not Dialogue._eval({"not_flag": "test.flag"}), "not_flag condition")
	_check(Dialogue._eval({"not_flag": "test.other"}), "not_flag on unset")
	WorldState.set_value("test.count", 3)
	_check(Dialogue._eval({"gte": ["test.count", 3]}), "gte pass")
	_check(not Dialogue._eval({"gte": ["test.count", 4]}), "gte fail")
	Dialogue._apply([{"set": "test.applied"}, {"inc": "test.count"}])
	_check(WorldState.has_flag("test.applied"), "effect set")
	_check(WorldState.get_value("test.count") == 4, "effect inc")
	Dialogue._current = {"start": [
		{"if": {"gte": ["test.count", 10]}, "node": "a"},
		{"if": {"flag": "test.flag"}, "node": "b"},
		{"node": "c"},
	]}
	_check(Dialogue._pick_start() == "b", "start selection honors conditions")
	_check(Dialogue.has_dialogue("wanderer"), "wanderer dialogue record loads")


func _test_quests() -> void:
	_check(Journal._quests.size() >= 2, "quest records load")
	var q: Dictionary = {"id": "t", "title": "T", "steps": [
		{"id": "a", "text": "a", "done_if": {"flag": "test.q.a"}},
		{"id": "b", "text": "b", "done_if": {"gte": ["test.q.n", 2]}},
	]}
	_check(Journal.quest_active(q), "quest starts active")
	_check(not Journal.quest_done(q), "quest not done initially")
	WorldState.set_flag("test.q.a")
	_check(Journal.step_done(q.steps[0]), "step completes via flag")
	_check(not Journal.quest_done(q), "quest still open")
	WorldState.set_value("test.q.n", 2)
	_check(Journal.quest_done(q), "quest completes when all steps pass")
	_check(not Journal.quest_active(q), "complete quest no longer active")
	var seed: Dictionary = {"id": "t_seed", "title": "S",
		"start_if": {"flag": "test.seed.on"},
		"steps": [{"id": "x", "text": "x", "done_if": {"flag": "test.seed.done"}}]}
	_check(not Journal.quest_active(seed), "seed dormant before its state")
	WorldState.set_flag("test.seed.on")
	_check(Journal.quest_active(seed), "seed activates on sim state")
	WorldState.set_value("test.seed.on", false)
	_check(Journal.quest_active(seed), "seed stays latched when the state passes")
	_check(Conditions.eval({"item": ["nonexistent_item", 1]}) == false, "item condition")


func _test_skills() -> void:
	_check(Skills.defs().size() >= 4, "skill records load")
	WorldState.set_value("player.dist_walked", 1300.0)
	_check(Skills.level("wayfaring") == 2, "wayfaring level from distance")
	WorldState.set_value("player.dist_walked", 0.0)
	_check(Skills.level("wayfaring") == 0, "level derives, never sticks")
	_check(Skills.level("nonexistent") == 0, "unknown skill is level 0")


## advance_hours is the shared catch-up path (load, laptop sleep, debug
## skip): it must tick every skipped hour and roll days across midnight.
func _test_clock() -> void:
	var ticks: Array = []
	var on_tick := func(h: int) -> void: ticks.append(h)
	GameClock.hour_tick.connect(on_tick)
	GameClock.hours = 22.0
	GameClock.day = 3
	GameClock.advance_hours(4.0)
	GameClock.hour_tick.disconnect(on_tick)
	_check(ticks.size() == 4, "advance fires hour_tick for every skipped hour")
	_check(ticks == [23, 0, 1, 2], "ticks pass through midnight in order")
	_check(GameClock.day == 4, "day rolls over during advance")
	_check(absf(GameClock.hours - 2.0) < 0.001, "clock lands on the right hour")
	_check(absf(GameClock.hours_delta(3600.0) - 1.0) < 0.001,
		"1:1 time — one real hour is one game hour")
	var day_before: int = GameClock.day
	GameClock.return_to_now()
	_check(absf(GameClock.hours - GameClock.civil_now()) < 0.01,
		"return_to_now re-anchors to real local time")
	_check(GameClock.day == day_before, "return_to_now keeps days lived")


## Seasons follow the real calendar; daylight, solar noon, and the
## solar-hour warp derive from the real date and the player's location.
func _test_seasons() -> void:
	_check(GameClock.season_for({"month": 1, "day": 15}) == "winter", "january is winter")
	_check(GameClock.season_for({"month": 3, "day": 19}) == "winter", "mar 19 still winter")
	_check(GameClock.season_for({"month": 3, "day": 20}) == "spring", "mar 20 turns spring")
	_check(GameClock.season_for({"month": 7, "day": 2}) == "summer", "july is summer")
	_check(GameClock.season_for({"month": 10, "day": 5}) == "autumn", "october is autumn")
	_check(GameClock.season_for({"month": 12, "day": 21}) == "winter", "dec 21 turns winter")
	_check(GameClock.season_for({"month": 12, "day": 25}, true) == "summer",
		"southern hemisphere flips the season")
	var solstice_summer: float = GameClock.daylight_hours_for(172, 45.0)
	var solstice_winter: float = GameClock.daylight_hours_for(355, 45.0)
	_check(solstice_summer > 15.0, "summer solstice daylight is long at 45N")
	_check(solstice_winter < 9.0, "winter solstice daylight is short at 45N")
	_check(absf(GameClock.daylight_hours_for(172, 0.0) - 12.1) < 0.3,
		"equator stays near 12h year round")
	_check(GameClock.daylight_hours_for(172, -45.0) < 9.0,
		"southern winter in june")
	_check(GameClock.daylight_hours_for(172, 89.0) <= 23.5,
		"polar day clamps — the sun always sets")
	_check(GameClock.season != "", "live season is set")
	_check(WorldState.get_value("time.season") == GameClock.season,
		"season mirrored to WorldState")
	var span: Vector2 = GameClock.daylight_span()
	_check(span.y > span.x, "sunrise precedes sunset")
	var today_dl: float = GameClock.daylight_hours_for(
		GameClock.day_of_year(Time.get_date_dict_from_system()), Settings.latitude)
	_check(absf((span.y - span.x) - today_dl) < 0.01,
		"span width matches the sunrise equation")
	GameClock.hours = fposmod(span.x, 24.0)
	_check(absf(GameClock.solar_hours() - 6.0) < 0.01, "sunrise maps to solar 6:00")
	GameClock.hours = fposmod(span.y - 0.001, 24.0)
	_check(absf(GameClock.solar_hours() - 18.0) < 0.05, "sunset maps to solar 18:00")
	GameClock.hours = fposmod((span.x + span.y) * 0.5, 24.0)
	_check(absf(GameClock.solar_hours() - 12.0) < 0.01, "solar noon maps to 12:00")


## Climate: the temperature/moisture substrate other systems read.
func _test_water() -> void:
	# Records load: the pond as a lake, the brook as a river.
	_check(Terrain.water_bodies.size() >= 1, "lake records load")
	_check(Terrain.rivers.size() >= 1, "river records load")
	# The pond surface answers within its radius, -INF outside. (The live
	# surface rides Hydrology's level, so the authored check reads base.)
	_check(is_equal_approx(Terrain.water_surface_base(70.0, -310.0), -0.9),
		"pond base surface reads from the record")
	_check(Terrain.water_surface(70.0, -120.0) < -1e6, "no water on dry ground")
	# The brook: surface on the centerline, and the bed carved below it.
	var mid := Vector2(63.0, -256.0)
	var surf: float = Terrain.water_surface(mid.x, mid.y)
	_check(surf > -1e6, "brook has a surface on its centerline")
	_check(Terrain.height(mid.x, mid.y) < surf - 0.5,
		"the channel bed is carved below the brook surface")
	# A few metres off the bank there's neither water nor a channel.
	_check(Terrain.water_surface(30.0, -228.0) < -1e6, "brook is dry off to the side")
	# Moisture is lifted along the river, like a lake's banks.
	var was_wet: float = Climate.wetness
	Climate.wetness = 0.0
	_check(Climate.moisture(mid.x, mid.y) > Climate.moisture(30.0, -228.0),
		"river banks stay damp through a dry spell")
	Climate.wetness = was_wet


func _test_hydrology() -> void:
	# One tick builds the catchments from real flow routing.
	var was_state: String = Weather.state
	var was_wet: float = Climate.wetness
	Weather.state = "calm"
	Climate.wetness = 0.5
	Hydrology._hourly(0)
	_check(Hydrology.catchment_area.get("brook", 0.0) > 10_000.0,
		"the brook drains a real catchment (routed, not authored)")
	_check(Hydrology._river_feeds_lake(Terrain.rivers[0], Terrain.water_bodies[0]),
		"the brook's mouth feeds the pond")
	# Storm hours must raise the brook; calm hours must recede it.
	var calm_q: float = Hydrology.discharge("brook")
	Weather.state = "storm"
	Climate.wetness = 0.8
	for i in 6:
		Hydrology._hourly(0)
	var storm_q: float = Hydrology.discharge("brook")
	_check(storm_q > calm_q * 1.25 and storm_q - calm_q > 12.0,
		"storm hours swell the brook (%.0f -> %.0f m3/h)" % [calm_q, storm_q])
	var flood_level: float = Terrain.rivers[0].level
	_check(flood_level > Hydrology.RIVER_LEVEL_MIN, "flood raises the river surface")
	Weather.state = "calm"
	Climate.wetness = 0.1
	for i in 48:
		Hydrology._hourly(0)
	_check(Hydrology.discharge("brook") < storm_q * 0.5,
		"dry days recede the brook")
	# The live surface follows the level; the authored base never moves.
	var w: Dictionary = Terrain.water_bodies[0]
	var c: Vector2 = w.center
	_check(is_equal_approx(Terrain.water_surface(c.x, c.y),
			float(w.surface) + float(w.level)),
		"live water surface = authored + hydrology level")
	_check(is_equal_approx(Terrain.water_surface_base(c.x, c.y), float(w.surface)),
		"base water surface ignores the level")
	# Levels stay on their rails and round-trip through WorldState.
	_check(float(w.level) >= Hydrology.LAKE_LEVEL_MIN
			and float(w.level) <= Hydrology.LAKE_LEVEL_MAX, "pond level on rails")
	_check(float(WorldState.get_value("water.pond.level")) == float(w.level),
		"pond level mirrored to WorldState")
	Weather.state = was_state
	Climate.wetness = was_wet


func _test_climate() -> void:
	var floor_temp: float = Climate.temperature(0.0, -100.0)
	var ridge_temp: float = Climate.temperature(900.0, -100.0)
	_check(ridge_temp < floor_temp, "ridges run colder than the valley floor")
	var span: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span.x - 2.0, 24.0)  # before dawn
	var predawn: float = Climate.temperature(0.0, -100.0)
	GameClock.hours = fposmod((span.x + span.y) * 0.5 + 3.0, 24.0)  # mid-afternoon
	var afternoon: float = Climate.temperature(0.0, -100.0)
	_check(predawn < afternoon, "pre-dawn is colder than mid-afternoon")
	var was_state: String = Weather.state
	var was_wet: float = Climate.wetness
	Weather.state = "storm"
	Climate.wetness = 0.2
	Climate._hourly(0)
	_check(Climate.wetness > 0.2, "storm hours soak the ground")
	Weather.state = "calm"
	var wet: float = Climate.wetness
	Climate._hourly(0)
	_check(Climate.wetness < wet, "calm hours dry the ground")
	_check(float(WorldState.get_value("climate.wetness")) == Climate.wetness,
		"wetness mirrored to WorldState")
	Climate.wetness = 0.0
	_check(Climate.moisture(72.0, -280.0) > Climate.moisture(400.0, -100.0),
		"pond banks stay damp through a dry spell")
	_check(Climate.snow_line_for(20.0) > Climate.snow_line_for(2.0),
		"warm air lifts the snowline")
	_check(Climate.snow_line_for(-3.0) < 0.0,
		"a freezing floor drops the snowline below the valley")
	var was_snow: float = Climate.snow
	Weather.state = "calm"
	Climate.snow = 0.5
	Climate.wetness = 0.1
	Climate._hourly(0)
	_check(Climate.snow < 0.5, "warm calm hours melt the snow")
	_check(Climate.wetness > 0.0, "meltwater soaks the ground")
	Climate.snow = was_snow
	Weather.state = was_state
	Climate.wetness = was_wet
	Weather._transition(0)
	_check(absf(Weather.wind_dir.length() - 1.0) < 0.001,
		"wind direction stays a unit vector as it wanders")


## Flora lifecycle: vitality chases climate, flags latch story-seeds.
func _test_flora() -> void:
	_check(FloraLife.target_for("spring", 0.8, 18.0) > FloraLife.target_for("winter", 0.8, 18.0),
		"spring outgrows winter")
	_check(FloraLife.target_for("summer", 0.1, 34.0) < FloraLife.target_for("summer", 0.7, 22.0),
		"hot and dry starves the flora")
	var was_v: float = FloraLife.vitality
	var was_wet: float = Climate.wetness
	Climate.wetness = 0.0
	FloraLife.vitality = 0.1
	WorldState.set_value("valley.parched", false)
	WorldState.set_value("valley.bloom", false)
	FloraLife._hourly(0)
	_check(WorldState.has_flag("valley.parched"), "dry + starved flora -> parched flag")
	Climate.wetness = 1.0
	FloraLife.vitality = 0.9
	FloraLife._hourly(0)
	_check(WorldState.has_flag("valley.bloom"), "soaked + thriving flora -> bloom flag")
	_check(not WorldState.has_flag("valley.parched"), "recovery clears parched")
	FloraLife.vitality = was_v
	Climate.wetness = was_wet
	WorldState.set_value("valley.bloom", false)
	WorldState.set_value("valley.parched", false)


## Moon phase: real synodic cycle, stateless in real time.
func _test_moon() -> void:
	var epoch: float = GameClock.NEW_MOON_EPOCH
	_check(GameClock.moon_phase_at(epoch) < 0.001, "epoch is a new moon")
	var half: float = GameClock.SYNODIC_DAYS * 0.5 * 86400.0
	_check(absf(GameClock.moon_phase_at(epoch + half) - 0.5) < 0.001,
		"half a synodic month later is full")
	var full_light := 0.5 - 0.5 * cos(TAU * 0.5)
	_check(absf(full_light - 1.0) < 0.001, "full moon is fully lit")
	var phase: float = GameClock.moon_phase()
	_check(phase >= 0.0 and phase < 1.0, "live phase in range")


## Rumors: learn, mirror to flags, forget at capacity, pass between minds.
func _test_rumors() -> void:
	var npc_script := load("res://game/npc/npc.gd")
	var a: CharacterBody3D = npc_script.new()
	a.npc_id = "test_a"
	var b: CharacterBody3D = npc_script.new()
	b.npc_id = "test_b"
	a.learn("valley_parched")
	_check(a.knows("valley_parched"), "npc learns a fact")
	_check(WorldState.has_flag("npc.test_a.knows.valley_parched"),
		"fact mirrored as a dialogue-readable flag")
	for i in 15:
		a.learn("filler_%d" % i)
	_check(not a.knows("valley_parched"), "oldest rumor forgotten at capacity")
	_check(not WorldState.has_flag("npc.test_a.knows.valley_parched"),
		"forgotten rumor's flag clears")
	b.learn("weathered_storm")
	b.learn("met_player")
	var mgr: Node = load("res://game/npc/npc_manager.gd").new()
	mgr._tell_one(b, a)
	_check(a.knows("weathered_storm"), "rumor passes between npcs")
	mgr._tell_one(b, a)
	_check(not a.knows("met_player"), "meeting someone is not a catchable rumor")
	a.free()
	b.free()
	mgr.free()


## Wildlife tier-3: pure-data animals live full days without a body.
func _test_wildlife() -> void:
	var mgr: Node = load("res://game/wildlife/wildlife_manager.gd").new()
	var herd: Dictionary = mgr.spawn_herd({
		"id": "test_herd", "count": 2.0,
		"home": {"x": 0.0, "z": 0.0}, "range": 100.0,
		"activities": [
			{"id": "drink", "at": {"x": 50.0, "z": 0.0}, "satisfies": "thirst",
				"rate": 16.0, "hours": [5.0, 9.0]},
			{"id": "prowl", "at": "roam", "satisfies": "wander", "rate": 5.0},
		]})
	var sim: AgentSim = herd.individuals[0].sim
	var span: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span.x + 1.0, 24.0)  # solar ~7:00, drink window
	sim.needs.thirst = 10.0
	sim.needs.wander = 90.0
	sim.decide()
	_check(sim.current.id == "drink", "thirsty animal heads to water at dawn")
	var start: Vector2 = sim.pos
	sim.advance(1.0)
	_check((sim.pos - Vector2(50.0, 0.0)).length() < 12.0,
		"an hour of data-tier time completes the journey")
	_check(sim.pos != start, "data animal moved without a body")
	sim.advance(1.0)  # arrived: this hour is spent drinking
	_check(sim.needs.thirst > 10.0, "drinking satisfies thirst")
	mgr._save_state()
	var rows: Array = WorldState.get_value("wildlife.test_herd", [])
	_check(rows.size() == 2, "herd persists to WorldState")
	# Herd cohesion: roam draws near the group's heart, not anywhere.
	for i in herd.individuals.size():
		herd.individuals[i].sim.pos = Vector2(20.0 * i, 0.0)
	mgr._update_cohesion(herd)
	var roamer: AgentSim = herd.individuals[1].sim
	_check(roamer.roam_center.is_finite(), "cohesion sets the herd's heart")
	var roam_spot: Vector2 = roamer.resolve_at({"at": "roam"})
	_check((roam_spot - roamer.roam_center).length() <= roamer.cohesion_radius + 0.1,
		"roam targets stay with the herd")
	mgr.free()  # after every mgr use — a freed Node here cost a long bisect
	var body_script := load("res://game/wildlife/wildlife_body.gd")
	var noon: float = body_script.sense_range_for(12.0, 0.0)
	var dark: float = body_script.sense_range_for(0.0, 0.0)
	var moonlit: float = body_script.sense_range_for(0.0, 1.0)
	_check(noon > dark, "creatures see farther by day than by night")
	_check(moonlit > dark, "a full moon lends the night some sight")
	_check(noon > moonlit, "but never as much as the sun")


## Long memory: pantry stocks accrue from work; desire paths persist.
func _test_long_memory() -> void:
	var npc_script := load("res://game/npc/npc.gd")
	var n: CharacterBody3D = npc_script.new()
	n.npc_id = "test_worker"
	n.needs = {"purpose": 50.0}
	n.current = {"id": "tend", "satisfies": "purpose", "rate": 8.0,
		"produces": {"offerings": 0.25}}
	n._satisfy(2.0)  # two hours at the shrine
	n._save_state()
	var stock: float = float(WorldState.get_value("npc.test_worker.stock.offerings", 0.0))
	_check(absf(stock - 0.5) < 0.01, "work accrues stock at the record's rate")
	n._satisfy(1.0)
	n._save_state()
	_check(float(WorldState.get_value("npc.test_worker.stock.offerings", 0.0)) > stock,
		"stock accumulates across flushes")
	n.free()

	var spot := Vector2(4321.5, -4321.5)  # far from any real trail
	for i in 5:
		InteractionField.stamp(spot)
		InteractionField._clock += 30.0  # crowding guard: wear needs revisits, not shuffling
	var snap: Dictionary = InteractionField.wear_snapshot()
	var key := "4321_-4322"
	_check(snap.has(key), "footsteps wear a permanent cell")
	_check(float(snap[key]) > 0.15, "repeated walking deepens the wear")
	InteractionField._age_wear(0)
	var aged: Dictionary = InteractionField.wear_snapshot()
	_check(float(aged[key]) < float(snap[key]), "unwalked paths fade over hours")
	InteractionField.wear_restore(snap)
	_check(absf(float(InteractionField.wear_snapshot()[key]) - float(snap[key])) < 0.002,
		"wear survives a save/load roundtrip")
	InteractionField.wear_restore({})  # leave no test residue in the field


## Near-tier navigation: bake from faces, path across, fall back cleanly.
func _test_nav() -> void:
	# A 20x20m plane in the streamer's exact triangle winding.
	var res := 11
	var step := 2.0
	var faces := PackedVector3Array()
	for iz in res - 1:
		for ix in res - 1:
			var a := Vector3(ix * step, 0.0, iz * step)
			var b := Vector3((ix + 1) * step, 0.0, iz * step)
			var c := Vector3(ix * step, 0.0, (iz + 1) * step)
			var d := Vector3((ix + 1) * step, 0.0, (iz + 1) * step)
			faces.append_array([a, b, c, b, d, c])
	var navmesh: NavigationMesh = Nav.bake_navmesh(faces)
	_check(navmesh.get_polygon_count() > 0, "bake produces walkable polygons")
	var cell := Vector2i(999, 999)
	var origin := Vector3(9990.0, 0.0, 9990.0)
	Nav.add_cell(cell, navmesh, origin)
	NavigationServer3D.map_force_update(Nav._map)
	var p: PackedVector3Array = Nav.path(
		origin + Vector3(2.0, 0.5, 2.0), origin + Vector3(18.0, 0.5, 18.0))
	_check(p.size() >= 2, "path across the baked cell")
	_check(p[p.size() - 1].distance_to(origin + Vector3(18.0, 0.0, 18.0)) < 2.5,
		"path reaches the goal")
	Nav.remove_cell(cell)
	var fallback: PackedVector3Array = Nav.path(Vector3.ZERO, Vector3(10.0, 0.0, 10.0))
	_check(fallback.size() == 2, "no navmesh -> straight-line fallback")


## The granular kernel: sand is conserved, spikes slump to repose, flows
## spread — pure math, no thread, no rendering.
func _test_sand_sim() -> void:
	var g := 16
	var delta_field := PackedFloat32Array()
	delta_field.resize(g * g)
	var base := PackedFloat32Array()
	base.resize(g * g)
	var active := PackedInt32Array()
	var queued := PackedByteArray()
	queued.resize(g * g)
	var center := (g / 2) * g + g / 2
	delta_field[center] = 0.3
	queued[center] = 1
	active.append(center)
	var before := 0.0
	for i in g * g:
		before += delta_field[i]
	for step in 300:
		SandField.relax(delta_field, base, active, queued, g, 0.04, 0.3, 4000)
	var after := 0.0
	var peak := 0.0
	for i in g * g:
		after += delta_field[i]
		peak = maxf(peak, delta_field[i])
	_check(absf(after - before) < 0.0005, "sand is conserved through avalanches")
	_check(peak < 0.29, "a spike slumps toward the angle of repose")
	_check(delta_field[center - 1] > 0.0, "material flows to the neighbors")
	# Steep base terrain: material walks downhill across cells.
	var slope_delta := PackedFloat32Array()
	slope_delta.resize(g * g)
	var slope_base := PackedFloat32Array()
	slope_base.resize(g * g)
	for y in g:
		for x in g:
			slope_base[y * g + x] = -x * 0.1  # falls to +x
	var a2 := PackedInt32Array()
	var q2 := PackedByteArray()
	q2.resize(g * g)
	var mid := (g / 2) * g + 3
	slope_delta[mid] = 0.25
	q2[mid] = 1
	a2.append(mid)
	for step in 300:
		SandField.relax(slope_delta, slope_base, a2, q2, g, 0.04, 0.3, 4000)
	var right := 0.0
	var left := 0.0
	for y in g:
		for x in g:
			if x >= 6:
				right += slope_delta[y * g + x]
			elif x <= 2:
				left += slope_delta[y * g + x]
	_check(right > 0.06 and right > left * 2.0, "piled sand avalanches downhill")
