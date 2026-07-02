extends Node
## Scene-context tests: anything that needs autoloads alive (Dialogue,
## WorldState interplay). Run by test.sh: godot --headless scene_tests.tscn
## — exits 0/1.

var _failures := 0


func _ready() -> void:
	_test_dialogue()
	_test_quests()
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
