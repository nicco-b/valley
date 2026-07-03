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
	_test_flora()
	_test_moon()
	_test_rumors()
	_test_wildlife()
	_test_long_memory()
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
	Weather.state = was_state
	Climate.wetness = was_wet


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
	var ind: Dictionary = herd.individuals[0]
	var span: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span.x + 1.0, 24.0)  # solar ~7:00, drink window
	ind.drives.thirst = 10.0
	ind.drives.wander = 90.0
	mgr.decide(herd, ind)
	_check(ind.activity.id == "drink", "thirsty animal heads to water at dawn")
	var start: Vector2 = ind.pos
	mgr.advance_individual(herd, ind, 1.0)
	_check((ind.pos - Vector2(50.0, 0.0)).length() < 12.0,
		"an hour of data-tier time completes the journey")
	_check(ind.pos != start, "data animal moved without a body")
	mgr.advance_individual(herd, ind, 1.0)  # arrived: this hour is spent drinking
	_check(ind.drives.thirst > 10.0, "drinking satisfies thirst")
	mgr._save_state()
	var rows: Array = WorldState.get_value("wildlife.test_herd", [])
	_check(rows.size() == 2, "herd persists to WorldState")
	mgr.free()


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
