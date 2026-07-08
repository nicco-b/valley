extends Node
## The quest harness (the Campfire, DESIGN_QUESTS §10 / rung Q2): drive
## quests headless and assert latch sequences — tests as data. Run by
## scripts/test.sh: godot --headless res://tests/quest_harness.tscn.
##
## Three passes, in order:
##   1. the LINTER over data/quests + data/threads (QuestLint) — the
##      authored-spine truths Records.validate can't see, at commit time
##   2. linter self-probes — deliberately broken records must be caught
##      (a linter that can't bite is worse than none)
##   3. every tests/quests/*.test.json script, each in a fresh world
##
## A test record: {"quest": id, "record": {...}?, "world": {...}?,
## "script": [steps]}. `record` registers an inline quest through the
## REAL machinery (synthetic shapes the shipped content doesn't cover);
## `world` seeds WorldState before the script runs. Steps:
##   {"set": {key: value, ...}}          write keys (the mirror-law door:
##                                       the harness fakes sims by writing
##                                       the keys they would mirror)
##   {"advance_hours": n}                the one time door (catch-up path)
##   {"expect_reached": stage}           latch asserts, against the
##   {"expect_not_reached": stage|[..]}  quest's freshest cycle
##   {"expect_objective": [stage, obj]}
##   {"expect_cycles": n}                cycles ever started (re-arm proof)
##   {"expect_gap": [a, b, days]}        reached_day(b) - reached_day(a)
##                                       — catch-up honesty: the memoir
##                                       stamps the replayed day
##   {"expect_minted": kind}             against Story's mint log
##   {"expect_scene_requested": id}      against Story's request log
##
## The world runs REAL under the harness (autoloads tick through
## advance_hours — the soak's pattern, no player body), so long advances
## belong to tests whose keys the sims don't own.

const HARNESS_SEED := 123456789
const TESTS_DIR := "res://tests/quests"

var _failures := 0


func _ready() -> void:
	WorldState.set_value("world.seed", HARNESS_SEED)
	Rng.load_state()
	GameClock.hours = 9.0
	GameClock.day = 0

	_run_lint()
	_lint_probes()
	_run_tests()

	if _failures > 0:
		print("QUEST-HARNESS FAIL: %d failure(s)" % _failures)
	else:
		print("QUEST-HARNESS PASS")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


# --- pass 1: the linter over shipped records --------------------------------

func _run_lint() -> void:
	var problems := QuestLint.lint_all()
	for p in problems:
		print("  LINT: ", p)
	_check(problems.is_empty(), "quest lint clean (%d problem(s))" % problems.size())


# --- pass 2: the linter bites (broken records must be caught) ---------------

func _lint_probes() -> void:
	_probe("wedge (no way forward)", {"format": 2, "id": "p", "title": "p",
		"tier": "story", "stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "dead", "advance_when": {"flag": "k"}, "journal": "x"},
			{"id": "end", "terminal": true, "after": ["a"], "journal": "x",
				"advance_when": {"flag": "k2"}, "mint": {"kind": "m"}}]},
		"no way forward")
	_probe("skippable required stage", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "must", "required": true, "advance_when": {"flag": "k"}, "journal": "x"},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k2"}, "journal": "x"}]},
		"skippable")
	_probe("reserved predicate", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "start_if": {"opinion_band": ["keeper", "warm"]},
		"stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k"}, "journal": "x"}]},
		"reserved")
	_probe("unknown predicate (closed language)", {"format": 2, "id": "p",
		"title": "p", "tier": "errand", "start_if": {"expr": "1 > 0"},
		"stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k"}, "journal": "x"}]},
		"unknown predicate")
	_probe("custom without watch", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "start_if": {"custom": ["moody"]},
		"stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k"}, "journal": "x"}]},
		"watch")
	_probe("repeatable story", {"format": 2, "id": "p", "title": "p",
		"tier": "story", "repeatable": {"cooldown_days": 3}, "stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k"},
				"journal": "x", "mint": {"kind": "m"}}]},
		"errand-tier only")
	_probe("prose-less terminal", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k"}}]},
		"journal prose")
	_probe("mintless story terminal", {"format": 2, "id": "p", "title": "p",
		"tier": "story", "stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k"}, "journal": "x"}]},
		"must mint")
	_probe("colliding sibling endings", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "stages": [
			{"id": "a", "start": true, "journal": "x"},
			{"id": "e1", "terminal": true, "advance_when": {"flag": "choice.p.x"}, "journal": "x"},
			{"id": "e2", "terminal": true, "advance_when": {"flag": "choice.p.x"}, "journal": "x"}]},
		"disjoint")


func _probe(name: String, record: Dictionary, expect_fragment: String) -> void:
	var problems := QuestLint.lint_quest(record)
	for p in problems:
		if expect_fragment in p:
			return
	_check(false, "lint probe '%s' bites (wanted '%s' in %s)"
			% [name, expect_fragment, problems])


# --- pass 3: tests as data ---------------------------------------------------

func _run_tests() -> void:
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		_check(false, "tests dir exists (%s)" % TESTS_DIR)
		return
	var files := Array(dir.get_files())
	files = files.filter(func(f: String) -> bool: return f.ends_with(".test.json"))
	files.sort()
	_check(not files.is_empty(), "at least one quest test record")
	for f: String in files:
		var test: Variant = Records.load_json(TESTS_DIR + "/" + f)
		if not (test is Dictionary):
			_check(false, "%s parses" % f)
			continue
		_run_test(f, test)


func _run_test(name: String, test: Dictionary) -> void:
	print("  test: ", name)
	_reset_world()
	var inline: Dictionary = test.get("record", {})
	if not inline.is_empty():
		Story.register_quest(inline)
	var qid := String(test.get("quest", inline.get("id", "")))
	_check(Story.quests.has(qid), "%s: quest '%s' exists" % [name, qid])
	var world: Dictionary = test.get("world", {})
	for key: String in world:
		WorldState.set_value(key, world[key])
	var mints_before := Story.minted().size()
	var scenes_before := Story.scene_requests().size()
	var i := -1
	for step: Dictionary in test.get("script", []):
		i += 1
		for verb: String in step:
			var arg: Variant = step[verb]
			var at := "%s[%d] %s" % [name, i, verb]
			match verb:
				"set":
					for key: String in arg:
						WorldState.set_value(key, arg[key])
				"advance_hours":
					GameClock.advance_hours(float(arg))
				"expect_reached":
					_check(Story.reached(qid, arg), "%s %s" % [at, arg])
				"expect_not_reached":
					for sid: String in (arg if arg is Array else [arg]):
						_check(not Story.reached(qid, sid), "%s %s" % [at, sid])
				"expect_objective":
					_check(Story.objective_done(qid, arg[0], arg[1]),
						"%s %s.%s" % [at, arg[0], arg[1]])
				"expect_cycles":
					_check(Story.cycle_count(qid) == int(arg),
						"%s want %d got %d" % [at, int(arg), Story.cycle_count(qid)])
				"expect_gap":
					var gap := Story.reached_day(qid, arg[1]) - Story.reached_day(qid, arg[0])
					_check(gap == int(arg[2]),
						"%s %s->%s want %d got %d" % [at, arg[0], arg[1], int(arg[2]), gap])
				"expect_minted":
					var found := false
					for m: Dictionary in Story.minted().slice(mints_before):
						if m.kind == arg:
							found = true
					_check(found, "%s %s" % [at, arg])
				"expect_scene_requested":
					var hit := false
					for req: String in Story.scene_requests().slice(scenes_before):
						if req == arg or req.ends_with("." + String(arg)):
							hit = true
					_check(hit, "%s %s" % [at, arg])
				_:
					_check(false, "%s: unknown step verb" % at)
	if not inline.is_empty():
		Story.unregister_quest(String(inline.id))


## A fresh world between tests: wipe WorldState, re-seed, re-mirror the
## clock (the day is monotonic — the sim can't unlive hours), and let
## every world_state_reader rebuild from the blank slate.
func _reset_world() -> void:
	WorldState.restore({})
	WorldState.set_value("world.seed", HARNESS_SEED)
	WorldState.set_value("time.day", GameClock.day)
	WorldState.set_value("time.hour", int(GameClock.solar_hours()))
	WorldState.set_value("time.season", GameClock.season)
	get_tree().call_group("world_state_reader", "load_state")
