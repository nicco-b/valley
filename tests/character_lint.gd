extends Node
## The character lint harness (CREATION_KIT_REVIEW_V2 #3, the cast sheet):
## drive CharacterLint headless and assert it bites — the quest_harness
## sibling for data/characters. Run by scripts/test.sh:
## godot --headless res://tests/character_lint.tscn. Success is the
## CHARACTER-LINT PASS line (the quit-after backstop makes the exit code 0
## regardless), the scene-test / quest-harness idiom.
##
## Three passes, in order:
##   1. the LINTER over data/characters (the live dir — content-empty, so
##      clean) and over tests/fixtures/characters (the shipped example
##      Mara — a full, sound record; her card must exist)
##   2. linter self-probes — deliberately broken records must be caught, each
##      with the game's own refusal SENTENCE (a linter that can't bite is
##      worse than none); every field of the CHARACTER record is exercised
##   3. the example record spawns a living mind (validate_character gates
##      spawn_character) — the desk's judgement and the loader's are one

var _failures := 0
var _checks := 0


func _ready() -> void:
	_test_live_and_fixture_clean()
	_test_selfprobes()
	_test_example_spawns()
	if _failures > 0:
		print("CHARACTER-LINT FAIL: %d failure(s)" % _failures)
	else:
		print("CHARACTER-LINT PASS (%d checks)" % _checks)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


## A sound CHARACTER record — the self-probes break exactly one field of this
## so each refusal is isolated. `chars/villager_keeper` is a shipped card, so
## the base clears the card arm too.
func _good() -> Dictionary:
	return {
		"id": "probe", "identity": {"name": "Probe", "kind": "villager"},
		"body": {"card": "chars/villager_keeper", "palette": {"base": [0.5, 0.5, 0.5]},
			"scene": "res://game/villagers/villager_body.tscn"},
		"home": {"x": 0.0, "z": 0.0},
		"schedule": [{"id": "rest", "at": {"x": 0.0, "z": 0.0}, "satisfies": "rest"}],
		"mind": {"needs": {"rest": 1.0}, "keep_bias": 1.1, "roam_range": 150.0},
	}


## Pass 1: the live dir lints clean (content-empty), and — where the example's
## card is present (valley; a scaffolded game's cards are content, excluded) —
## the shipped example fixture lints clean through every arm (shape, card,
## marker shape). The card arm SKIPs when the card is absent (the tile/card
## SKIP pattern), so a content-empty game still verifies itself.
func _test_live_and_fixture_clean() -> void:
	var live := CharacterLint.lint_all("res://data/characters")
	for p in live:
		print("  LINT (live): ", p)
	_check(live.is_empty(),
		"data/characters lints clean (content-empty, %d problem(s))" % live.size())
	if not Cards.has("chars/villager_keeper"):
		print("  character lint: SKIP fixture/card arms (chars/villager_keeper absent)")
		return
	var fixtures := CharacterLint.lint_all("res://tests/fixtures/characters")
	for p in fixtures:
		print("  LINT (fixture): ", p)
	_check(fixtures.is_empty(),
		"the shipped example (Mara) lints clean (%d problem(s))" % fixtures.size())
	# The base record the probes mutate must itself be clean, or every probe
	# below is a false positive.
	_check(CharacterLint.lint_record(_good()).is_empty(),
		"the probe base is sound (no accidental problem)")


## Pass 2: break one field at a time; the lint must name each with the game's
## own words. `frag` is asserted as a substring of some problem — the exact
## refusal SENTENCES, so a reworded message that stops meaning what it says is
## caught here (the port keeps validate_schedule's words load-bearing).
func _probe(name: String, mutate: Callable, frag: String) -> void:
	var rec := _good()
	mutate.call(rec)
	var problems := CharacterLint.lint_record(rec)
	for p in problems:
		if frag in p:
			_check(true, "probe '%s' bites: %s" % [name, frag])
			return
	_check(false, "probe '%s' wanted '%s' in %s" % [name, frag, problems])


func _test_selfprobes() -> void:
	# --- the field schema (Records.validate_message) — a missing whole field ---
	_probe("no schedule field", func(r): r.erase("schedule"),
		"missing field 'schedule'")
	_probe("no identity field", func(r): r.erase("identity"),
		"missing field 'identity'")
	# --- identity ---
	# a wrong TOP-LEVEL type is caught by the field schema first (before the
	# semantic validator's own object-shape guard) — the desk's field-then-
	# semantic order, surfaced.
	_probe("identity not object", func(r): r.identity = "Mara",
		"field 'identity' should be Dictionary")
	_probe("identity no name", func(r): r.identity = {"kind": "villager"},
		"identity missing string 'name'")
	_probe("identity empty name", func(r): r.identity.name = "",
		"identity missing string 'name'")
	_probe("identity bad kind", func(r): r.identity.kind = "wizard",
		"identity 'kind' must be one of villager|creature")
	# --- body ---
	_probe("body not object", func(r): r.body = "keeper",
		"field 'body' should be Dictionary")
	_probe("body no card", func(r): r.body = {"palette": {}},
		"body missing string 'card'")
	_probe("body bad scene", func(r): r.body.scene = 3,
		"body 'scene' should be a string")
	_probe("body bad palette", func(r): r.body.palette = [1, 2, 3],
		"body 'palette' should be an object")
	# --- home ---
	_probe("home not place", func(r): r.home = {"foo": 1},
		"home needs x/z or a marker")
	_probe("home bad xz", func(r): r.home = {"x": "left", "z": 0.0},
		"home position x/z must be numbers")
	_probe("home empty marker", func(r): r.home = {"marker": ""},
		"home marker ref must be a non-empty record id")
	# --- schedule (the certified validate_schedule + the `at` grammar) ---
	_probe("schedule no satisfies",
		func(r): r.schedule = [{"id": "a"}],
		"activity 'a' missing string 'satisfies'")
	_probe("schedule no id",
		func(r): r.schedule = [{"satisfies": "rest"}],
		"activity 0 missing string 'id'")
	_probe("schedule at bad",
		func(r): r.schedule = [{"id": "a", "satisfies": "rest", "at": {"y": 1}}],
		"needs x/z or a marker")
	_probe("schedule at bad string",
		func(r): r.schedule = [{"id": "a", "satisfies": "rest", "at": "amble"}],
		"must be {x,z}, {marker}, or \"roam\"")
	_probe("schedule at empty marker",
		func(r): r.schedule = [{"id": "a", "satisfies": "rest", "at": {"marker": ""}}],
		"marker ref must be a non-empty record id")
	# --- mind (optional knobs, but typed when present) ---
	_probe("mind not object", func(r): r.mind = 7,
		"field 'mind' should be an object")
	_probe("mind bad needs", func(r): r.mind = {"needs": [1, 2]},
		"mind 'needs' should be an object")
	_probe("mind bad weight", func(r): r.mind = {"needs": {"rest": "hard"}},
		"mind needs weight for 'rest' should be a number")
	_probe("mind bad keep_bias", func(r): r.mind = {"keep_bias": "high"},
		"mind 'keep_bias' should be a number")
	# --- card existence (the disk arm) ---
	_probe("card missing", func(r): r.body.card = "chars/ghost",
		"model card 'chars/ghost' does not exist")


## Pass 3: the shipped example is not just lint-clean — it SPAWNS. Loading it
## through spawn_character (validate_character gates the load) raises a living
## mind whose schedule drives the AgentMind. A local manager (never in the
## tree) drives it directly, the wildlife-test shape.
func _test_example_spawns() -> void:
	var rec: Variant = Records.load_json("res://tests/fixtures/characters/mara.json")
	_check(rec is Dictionary, "the example record parses")
	if not (rec is Dictionary):
		return
	var mgr: Node = load("res://game/villagers/villager_manager.gd").new()
	var v: Dictionary = mgr.spawn_character(rec)
	_check(not v.is_empty(), "the example record spawns a living mind")
	if not v.is_empty():
		var sim: AgentSim = v.sim
		_check(v.name == "Mara", "identity.name rides onto the mind's entry")
		_check(v.kind == "villager", "identity.kind is carried (villager keeps the clock)")
		_check(not sim.solar_gate, "a villager lives by the clock, not the sun")
		# the mind knobs landed from the record's `mind` block
		_check(is_equal_approx(sim.keep_bias, 1.1), "mind.keep_bias tunes the mind")
		_check(is_equal_approx(sim.roam_range, 150.0), "mind.roam_range tunes the mind")
		_check(is_equal_approx(sim.needs_def.get("work", 0.0), 1.2),
			"mind.needs sets the per-need drain weight")
		# the schedule drives a decision: at mid-morning, work depleted, she gardens
		GameClock.hours = 9.0
		sim.needs.work = 5.0
		sim.needs.rest = 95.0
		sim.decide()
		_check(sim.current.id == "garden", "her schedule drives AgentMind (gardens at 9)")
	mgr.free()
