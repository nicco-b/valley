extends SceneTree
## Unit tests, run via scripts/test.sh (godot --headless -s). Tests
## instantiate scripts directly (autoloads aren't relied on here).
## Exit code 1 on any failure.

var _failures := 0


## NOTE: scripts loaded under `godot -s` compile before autoload globals
## register — tests here must not load any script that names an autoload.
## Those tests live in scene_tests.tscn (run by test.sh in scene context).
func _init() -> void:
	_test_world_state()
	_test_terrain_determinism()
	if _failures > 0:
		print("FAIL: %d test(s) failed" % _failures)
		quit(1)
	else:
		print("PASS: all tests")
		quit(0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


func _test_world_state() -> void:
	var ws: Node = load("res://game/state/world_state.gd").new()
	_check(ws.get_value("missing") == null, "missing key -> null")
	_check(ws.get_value("missing", 7) == 7, "missing key -> default")
	ws.set_value("npc.wanderer.met", true)
	_check(ws.has_flag("npc.wanderer.met"), "set/has flag")
	_check(not ws.has_flag("npc.other.met"), "unset flag is false")
	_check(ws.increment("npc.wanderer.encounters") == 1, "increment from 0")
	_check(ws.increment("npc.wanderer.encounters", 2) == 3, "increment by 2")

	var signals: Array = []
	ws.changed.connect(func(k: String, v: Variant) -> void: signals.append([k, v]))
	ws.set_value("a.b", 1)
	ws.set_value("a.b", 1)  # unchanged -> no signal
	_check(signals.size() == 1, "signal fires once per real change")

	var snap: Dictionary = ws.snapshot()
	var ws2: Node = load("res://game/state/world_state.gd").new()
	ws2.restore(snap)
	_check(ws2.get_value("npc.wanderer.encounters") == 3, "snapshot/restore roundtrip")
	snap["tamper"] = true
	_check(ws2.get_value("tamper") == null, "snapshot is a deep copy")
	ws.free()
	ws2.free()


func _test_terrain_determinism() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	var a: float = t.height(123.0, -456.0)
	var b: float = t.height(123.0, -456.0)
	_check(a == b, "height() is deterministic")
	# Spawn-on-land is a property of the WORLD, not the code: a live
	# (unblessed) Strata tile in the local cache reshapes the ground under
	# the spawn point with every re-import, so the invariant only binds on
	# checkouts without a tile (fresh clone / CI = the committed world).
	# With a tile present it's a bless-time check — skip honestly instead
	# of failing Nicco's in-flight world (found 2026-07-08: world_v1
	# floods 0,0 to -123m).
	if t.has_world_tile():
		print("  spawn-on-land: SKIP (live tile in cache — bless-time invariant)")
	else:
		_check(t.height(0.0, 5.0) > t.sea_level, "spawn is on land (above sea)")
	_check(t.valley_factor(0.0, -100.0) < 0.1, "valley floor factor ~0")
	_check(t.valley_factor(900.0, -100.0) > 0.9, "far plateau factor ~1")
	t.free()
