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
	_test_dev_mode_compute()
	_test_vernier_registry()
	_test_placement_records()
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
	# The valley floor/plateau shape is a LANDFORM record (data/world/landform.json)
	# — content, excluded from framework.json (valley ships it; a scaffolded /
	# content-empty tree has none, so _valley_path is empty and valley_factor is
	# degenerate). SKIP honestly when the record is absent, exactly like the
	# spawn-on-land probe above; valley's own gate (which ships the landform)
	# still asserts the floor≈0 / plateau≈1 shape.
	if t._valley_path.is_empty():
		print("  valley-factor: SKIP (no landform record — content-empty tree)")
	else:
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


## The dev-gate decision (PLAN_SHIP §2). compute() is a pure function of
## (features, user_args, debug_build) with strict precedence — no engine
## state — so every rung and the two-feature collision are unit-testable
## headless. Loaded directly (like the other tests) rather than via the
## DevMode global, since `godot -s` compiles before class globals register.
func _test_dev_mode_compute() -> void:
	var DM: GDScript = load("res://game/dev/dev_mode.gd")
	var none := PackedStringArray()
	var no_dev := PackedStringArray(["strata_no_dev"])
	var dev := PackedStringArray(["strata_dev"])
	var both := PackedStringArray(["strata_no_dev", "strata_dev"])
	var arg := PackedStringArray(["--strata-dev"])

	# rung 4: legacy default — behavior-preserving (debug on, release off)
	_check(DM.compute(none, none, true) == true, "compute: legacy debug build -> dev on")
	_check(DM.compute(none, none, false) == false, "compute: legacy release build -> dev off")
	# rung 3: --strata-dev user arg forces on, even in a release flavor
	_check(DM.compute(none, arg, false) == true, "compute: --strata-dev arg -> dev on")
	# rung 2: strata_dev feature forces on, even without the arg or debug
	_check(DM.compute(dev, none, false) == true, "compute: strata_dev feature -> dev on")
	# rung 1: strata_no_dev kills it — beats the arg AND a debug build
	_check(DM.compute(no_dev, arg, true) == false, "compute: strata_no_dev arg+debug -> dev off (kill switch)")
	# two-feature collision: no_dev wins (it is checked first)
	_check(DM.compute(both, arg, true) == false, "compute: no_dev+dev collision -> off (no_dev wins)")


## Vernier (P4 — the cvar registry, game/dev/vernier.gd): registration is
## passive (a getter's current value lands, the setter is never called),
## list()/get_value()/set_value() find a tunable by name, an unknown name
## is the ONE honest null/err both share, and a duplicate register() is
## refused loudly rather than silently replacing a live setter. Loaded
## directly (like DevMode above) since `godot -s` compiles before class
## globals register; _reset_for_test() keeps this pass isolated from
## whatever a real game boot would register into the SAME static registry
## (the scene tests exercise those real, wired tunables + the link verb).
## Closures here mutate a Dictionary box, not a local var — GDScript
## lambdas capture locals by value; a Dictionary's VALUE is a reference,
## so the box's contents are the one place a setter closure can honestly
## write. NOTE: lambdas are fine HERE because _reset_for_test() drops
## them well before the process ever reaches engine shutdown — the real
## registrations (water_field.gd etc.) bind named methods instead exactly
## because THEIR entries live for the process's whole life; see
## vernier.gd's CALLABLE CAUTION doc for the crash that taught this.
func _test_vernier_registry() -> void:
	var VN: GDScript = load("res://game/dev/vernier.gd")
	VN._reset_for_test()

	var box := {"live": 0.0}
	VN.register("test.knob", TYPE_FLOAT, -1.0,
		func(v: float) -> void: box["live"] = v,
		func() -> float: return box["live"], "a test knob")

	_check(VN.has("test.knob"), "register: the tunable exists")
	_check(box["live"] == 0.0, "register is passive: the setter was never called")
	_check(VN.get_value("test.knob") == 0.0, "get_value reads through the getter")

	var entry: Object = VN.get_entry("test.knob")
	_check(entry.provenance == "boot", "a fresh registration stamps provenance 'boot'")
	_check(entry.default == -1.0, "the default is recorded")

	var landed: Variant = VN.set_value("test.knob", "2.5", "link")
	_check(landed == 2.5, "set_value coerces wire text to the declared type (got %s)" % str(landed))
	_check(box["live"] == 2.5, "set_value called the REAL setter")
	_check(VN.get_entry("test.knob").provenance == "link", "set_value stamps its provenance")

	VN.stamp("test.knob", "debug_key")
	_check(VN.get_entry("test.knob").provenance == "debug_key",
		"stamp() updates provenance without calling the setter")
	_check(box["live"] == 2.5, "stamp() never touches the live value")

	_check(VN.get_value("missing.knob") == null, "an unknown name reads null")
	_check(not VN.has("missing.knob"), "has() disambiguates null-value from unknown")
	_check(VN.set_value("missing.knob", 1, "link") == null,
		"set_value on an unknown name is a null no-op, not a crash")

	# A bool tunable: wire-text coercion for the honest spellings.
	var flag_box := {"flag": false}
	VN.register("test.flag", TYPE_BOOL, false,
		func(v: bool) -> void: flag_box["flag"] = v,
		func() -> bool: return flag_box["flag"], "a test flag")
	VN.set_value("test.flag", "on", "link")
	_check(flag_box["flag"] == true, "bool coercion: 'on' -> true")
	VN.set_value("test.flag", "0", "link")
	_check(flag_box["flag"] == false, "bool coercion: '0' -> false")

	# Duplicate registration is a programmer error, refused loudly — the
	# FIRST registration's setter/getter stay live, untouched.
	VN.register("test.knob", TYPE_FLOAT, 0.0, func(_v: float) -> void: pass,
		Callable(), "a colliding second registration")
	_check(VN.get_entry("test.knob").default == -1.0,
		"a duplicate register() is refused — the original entry stands")

	VN._reset_for_test()


func _test_placement_records() -> void:
	var PR = load("res://game/world/placement_records.gd")

	# --- The envelope judgement (sentences byte-matched by the Swift twin) ---
	var gen: Dictionary = PR.load_record(
		"res://tests/fixtures/placements/flora_scatter.json", "placement_gen")
	_check(not gen.is_empty(), "flora_scatter fixture loads as placement_gen")
	_check(PR.envelope_message(gen, "placement_set")
		== "declares placement_family 'placement_gen', expected 'placement_set'",
		"family mismatch refuses with the exact sentence")
	_check(PR.envelope_message({}, "placement_gen")
		== "missing field 'placement_family'",
		"empty envelope names the first missing field")
	var newer := gen.duplicate(true)
	newer["format"] = 2
	_check(PR.envelope_message(newer, "placement_gen")
		== "format 2 is newer than this build understands (max 1)",
		"a newer format is refused, never half-read")
	var mistyped := gen.duplicate(true)
	mistyped["params"] = "oops"
	_check(PR.envelope_message(mistyped, "placement_gen")
		== "field 'params' should be Dictionary, got String",
		"a mistyped params refuses with records.gd's wording")

	# --- placement_set rows: judgement + expressibility (no migration) ---
	_check(PR.set_row_message({"what": "res://x.tscn", "x": 1.0, "y": 2.0,
		"z": 3.0, "yaw": 0.5}) == "", "a sound frozen row passes")
	_check(PR.set_row_message({"what": "a", "x": 1.0, "y": 2.0, "z": 3.0})
		== "missing field 'yaw'", "a rowless yaw is named")
	# A Chronicle row (cell_records.gd's shape) is expressible losslessly.
	var chron := {"kit": "res://props/oak.glb", "x": 4.0, "y": 1.0, "z": 9.0,
		"yaw": 0.25, "scale": 1.1, "ground_dy": 0.4, "id": "p1a_2",
		"group": "bridge", "enabled": false}
	var row: Dictionary = PR.row_from_chronicle(chron)
	_check(PR.set_row_message(row) == "", "a Chronicle row maps to a sound row")
	_check(row["what"] == chron["kit"] and row["scale"] == 1.1
		and row["id"] == "p1a_2" and row["enabled"] == false,
		"kit -> what; every other Chronicle key rides through preserved")
	# A baked-scatter row (scatter_bake.gd's shape) is expressible too.
	var baked: Dictionary = PR.row_from_baked({"id": "s7", "cat": "rock_small",
		"x": 2.0, "y": 0.0, "z": 5.0, "yaw": 1.5, "scale": 0.9, "pick": 0.42})
	_check(PR.set_row_message(baked) == "" and baked["what"] == "rock_small"
		and baked["pick"] == 0.42, "cat -> what; pick and id ride through")
	# Per-cell keying on the Ambit grid ("x_y").
	var set_rec := {"placement_family": "placement_set", "format": 1,
		"cell_size": 128.0, "params": {"cells": {"3_-2": [row]}}}
	_check(PR.envelope_message(set_rec, "placement_set") == "",
		"a placement_set envelope passes")
	_check(PR.set_rows(set_rec, Vector2i(3, -2)).size() == 1
		and PR.set_rows(set_rec, Vector2i(0, 0)).is_empty(),
		"set_rows keys cells as x_y on the Ambit grid")

	# --- THE REPRODUCTION PROOF (the round's round-trip, half 1) ---
	# Record-driven generation must equal an INDEPENDENT transcription of
	# world_streamer.gd's own draw loops (_add_scatter / _add_forage), for a
	# representative fixture cell set, bit for bit, twice (stability x2).
	var forage: Dictionary = PR.load_record(
		"res://tests/fixtures/placements/forage_slots.json", "placement_gen")
	_check(not forage.is_empty(), "forage_slots fixture loads as placement_gen")
	var cells := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-3, 7), Vector2i(12, -5)]
	var env := {"valley_factor": 0.25, "biome_mult": 1.0, "vitality": 0.8}
	var fenv := {"yield_items": ["berry", "reed"]}
	for c: Vector2i in cells:
		# world_streamer.gd _add_scatter, transcribed by hand (draw order law:
		# count bound first, then lx, lz, roll, s per candidate, pre-filter).
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(c)
		var base_count := int(round(lerpf(34.0, 8.0, env.valley_factor)
				* env.biome_mult * lerpf(0.55, 1.15, env.vitality)))
		var expect: Array = []
		for i in rng.randi_range(base_count, base_count + 8):
			expect.append({"lx": rng.randf() * 128.0, "lz": rng.randf() * 128.0,
				"roll": rng.randf(), "scale": rng.randf_range(0.75, 1.15)})
		var got: Array = PR.gen_candidates(gen, c, env)
		var got2: Array = PR.gen_candidates(gen, c, env)
		_check(got == expect,
			"flora candidates == streamer transcription for cell %s" % c)
		_check(got == got2, "flora candidates bit-stable x2 for cell %s" % c)
		# world_streamer.gd _add_forage, transcribed by hand (seed *13+5;
		# 3 slots per yielding item; lx, lz, yaw drawn for EVERY slot).
		var frng := RandomNumberGenerator.new()
		frng.seed = hash(c) * 13 + 5
		var fexpect: Array = []
		for item in fenv.yield_items:
			for i in 3:
				fexpect.append({"item": item, "slot": i,
					"lx": frng.randf() * 128.0, "lz": frng.randf() * 128.0,
					"yaw": frng.randf() * TAU})
		_check(PR.gen_candidates(forage, c, fenv) == fexpect,
			"forage slots == streamer transcription for cell %s" % c)
	_check(PR.gen_candidates({"params": {"rule": "martian_maze"}},
		Vector2i.ZERO, {}) == [], "an unknown gen rule is loud and empty")

	# --- THE ROUND-TRIP PROOF (half 2): extract -> load -> stringify is
	# byte-identical to the committed fixture (the transcriber's fixed point).
	for fname: String in ["flora_scatter.json", "forage_slots.json"]:
		var path := "res://tests/fixtures/placements/" + fname
		var raw := FileAccess.get_file_as_string(path)
		var reloaded: Dictionary = PR.load_record(path, "placement_gen")
		_check(PR.stringify(reloaded) == raw,
			"%s round-trips byte-identical" % fname)
