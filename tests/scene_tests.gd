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


## Seasons follow the real calendar; daylight and the solar-hour warp
## derive from the real date.
func _test_seasons() -> void:
	_check(GameClock.season_for({"month": 1, "day": 15}) == "winter", "january is winter")
	_check(GameClock.season_for({"month": 3, "day": 19}) == "winter", "mar 19 still winter")
	_check(GameClock.season_for({"month": 3, "day": 20}) == "spring", "mar 20 turns spring")
	_check(GameClock.season_for({"month": 7, "day": 2}) == "summer", "july is summer")
	_check(GameClock.season_for({"month": 10, "day": 5}) == "autumn", "october is autumn")
	_check(GameClock.season_for({"month": 12, "day": 21}) == "winter", "dec 21 turns winter")
	var solstice_summer: float = GameClock.daylight_hours_for(172)
	var solstice_winter: float = GameClock.daylight_hours_for(355)
	_check(solstice_summer > 15.0, "summer solstice daylight is long")
	_check(solstice_winter < 9.0, "winter solstice daylight is short")
	_check(GameClock.season != "", "live season is set")
	_check(WorldState.get_value("time.season") == GameClock.season,
		"season mirrored to WorldState")
	var span: Vector2 = GameClock.daylight_span()
	GameClock.hours = span.x
	_check(absf(GameClock.solar_hours() - 6.0) < 0.01, "sunrise maps to solar 6:00")
	GameClock.hours = span.y - 0.001
	_check(absf(GameClock.solar_hours() - 18.0) < 0.05, "sunset maps to solar 18:00")
	GameClock.hours = 12.0
	_check(absf(GameClock.solar_hours() - 12.0) < 0.01, "noon stays noon")
