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
	_test_terrain_tile_frame_guard()
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
	# Spawn-on-land, re-bound: the spawn rides the WORLD, not a static
	# coordinate. import_world.gd records a dry landing spot on the largest
	# island (data/world/spawn.json) and a fresh journey begins there
	# (SaveGame._spawn_fresh). The invariant binds wherever a world records
	# its spawn — the imported ground under it must be dry at high tide.
	# Without a record there is nothing to hold it to: a fresh clone / the
	# tile-less procedural fallback (flooded by the committed sea) and a
	# tile that predates spawn recording both need a (re-)import to pick a
	# spot, so skip honestly instead of asserting a coordinate no importer
	# ever chose (the old 0,5 assert failed the day world_v1 flooded 0,0).
	var sp: Variant = t.recorded_spawn()
	if sp is Vector2:
		_check(t.height(sp.x, sp.y) > t.sea_level + t.TIDE_AMP,
			"spawn is on land (above sea at high tide)")
	else:
		print("  spawn-on-land: SKIP (no recorded spawn — import a world to bind it)")
	_check(t.valley_factor(0.0, -100.0) < 0.1, "valley floor factor ~0")
	_check(t.valley_factor(900.0, -100.0) > 0.9, "far plateau factor ~1")
	t.free()


## DATA-ARMOR: a Strata-provenance world tile whose frame doesn't match
## the game's WORLD_FRAME_M must refuse to load (garbage-ground defense);
## painted region tiles without provenance keep their arbitrary frames.
func _test_terrain_tile_frame_guard() -> void:
	var exr := "user://frame_guard_test.exr"
	var img := Image.create(8, 8, false, Image.FORMAT_RF)
	if img.save_exr(ProjectSettings.globalize_path(exr)) != OK:
		print("  tile frame guard: SKIP (no EXR saver in this binary)")
		return
	var t: Node = load("res://game/world/terrain.gd").new()
	var rec := {"id": "baked_world", "origin": {"x": -1024.0, "z": -1024.0},
		"size": 2048.0, "heightmap": exr, "strata": {"name": "guard_test"}}
	_check(t._load_tile(rec, "baked_world").is_empty(),
		"strata tile at 2048m refused against the %.0fm frame" % t.WORLD_FRAME_M)
	rec.erase("strata")
	_check(not t._load_tile(rec, "painted").is_empty(),
		"painted tile (no provenance) keeps its own frame")
	rec["strata"] = {"name": "guard_test"}
	rec["size"] = t.WORLD_FRAME_M
	_check(not t._load_tile(rec, "baked_world").is_empty(),
		"strata tile at the world frame loads")
	t.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(exr))
