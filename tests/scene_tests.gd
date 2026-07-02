extends Node
## Scene-context tests: anything that needs autoloads alive (Dialogue,
## WorldState interplay). Run by test.sh: godot --headless scene_tests.tscn
## — exits 0/1.

var _failures := 0


func _ready() -> void:
	_test_dialogue()
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
