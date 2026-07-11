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
##   {"expect_flag": key}                a hook side-effect key is set
##   {"expect_not_flag": key}            — and its negative
##   {"expect_key": [key, value]}        a hook wrote value at key
##   {"expect_role": [role, id]}         the latched role binding (§4)
##   {"expect_group": [gid, enabled]}    a world flip's group state, read
##                                       through CellRecords (Q10, §3); bare
##                                       gid means enabled==true
##   {"expect_placement": [rec, active]} the instancing predicate: does a
##                                       placement {group, enabled?} instance
##                                       now (authored-dark default rides here)
##   {"replay_advance": n}               advance n hours TWICE from a
##                                       restored snapshot and assert the
##                                       quest namespaces are bit-identical
##                                       (the hooks door's determinism proof,
##                                       §10 — an impure hook diverges here)
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
	_flip_probes()
	_hook_probes()
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
	# -- world flips (Q10, §3): a MALFORMED `world` effect must bounce. fstages
	# is a minimal valid errand graph carrying the flip under test on the root.
	var fstages: Callable = func(flip: Variant) -> Array:
		return [{"id": "a", "start": true, "journal": "x", "effects": [{"world": flip}]},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k"}, "journal": "x"}]
	_probe("world flip is not a dictionary", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "stages": fstages.call(["brook_bridge.rebuilt"])},
		"must be a dictionary")
	_probe("world flip has an unknown key", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "stages": fstages.call({"toggle": ["g"]})},
		"only 'enable'/'disable'")
	_probe("world flip direction is not an array", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "stages": fstages.call({"enable": "g"})},
		"array of group ids")
	_probe("world flip group id is empty", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "stages": fstages.call({"enable": [""]})},
		"non-empty string")
	_probe("world flip names no groups", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "stages": fstages.call({"enable": [], "disable": []})},
		"no-op effect")
	# -- the hooks door (§6): the bind-vs-properties() catch. probe_errand
	# declares { threshold: TYPE_FLOAT } — a bind that misses it, mistypes
	# it, or names a phantom property must bounce at commit, not runtime.
	var hook_stages: Array = [
		{"id": "a", "start": true, "journal": "x"},
		{"id": "end", "terminal": true, "advance_when": {"flag": "k"}, "journal": "x"}]
	_probe("hook bind missing a declared property", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "hooks": {"script": "hooks/probe_errand.gd", "bind": {}},
		"stages": hook_stages}, "missing property 'threshold'")
	_probe("hook bind mistypes a property", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "hooks": {"script": "hooks/probe_errand.gd", "bind": {"threshold": "high"}},
		"stages": hook_stages}, "mistyped")
	_probe("hook bind names a phantom property", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "hooks": {"script": "hooks/probe_errand.gd",
			"bind": {"threshold": 0.5, "bogus": 1}}, "stages": hook_stages}, "not a declared property")
	_probe("hook script does not exist", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "hooks": "hooks/no_such_hook.gd", "stages": hook_stages}, "does not exist")
	# -- roles (§4): a MALFORMED role must bounce at commit. rstages is a
	# minimal valid errand graph so only the role under test is the fault.
	var rstages: Array = [
		{"id": "a", "start": true, "journal": "x"},
		{"id": "end", "terminal": true, "advance_when": {"flag": "k"}, "journal": "x"}]
	_probe("role with an unknown kind", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "roles": {"hauler": {"kind": "creature"}}, "stages": rstages},
		"kind must be")
	_probe("role fills on an unknown stage", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "roles": {"hauler": {"kind": "npc", "fill": "on_stage:ghost"}},
		"stages": rstages}, "unknown stage")
	_probe("role with a bad fallback", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "roles": {"hauler": {"kind": "npc", "fallback": "wait"}},
		"stages": rstages}, "fallback must be")
	_probe("role require is not an array", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "roles": {"hauler": {"kind": "npc", "require": {"flag": "k"}}},
		"stages": rstages}, "must be an array")
	_probe("role require row is an unknown predicate", {"format": 2, "id": "p", "title": "p",
		"tier": "errand", "roles": {"hauler": {"kind": "npc",
			"require": [{"expr": "1 > 0"}]}}, "stages": rstages}, "unknown predicate")


func _probe(name: String, record: Dictionary, expect_fragment: String) -> void:
	var problems := QuestLint.lint_quest(record)
	for p in problems:
		if expect_fragment in p:
			return
	_check(false, "lint probe '%s' bites (wanted '%s' in %s)"
			% [name, expect_fragment, problems])


# --- pass 2c: world-flip cross-quest guardrail (Q10, §3) ---------------------

## The contested-flip warning is cross-quest, so it lives in lint_all, not
## lint_quest. Two quests enabling the same group must be caught; ONE quest
## flipping a group across two stages must NOT — the quest owns it. A single
## valid flip on ONE quest must lint clean (the passing case _run_lint over
## shipped records also proves through the fixture).
func _flip_probes() -> void:
	var flip_stage := func(qid: String, dir: String, gid: String) -> Dictionary:
		return {"format": 2, "id": qid, "title": qid, "tier": "errand", "stages": [
			{"id": "a", "start": true, "journal": "x", "effects": [{"world": {dir: [gid]}}]},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k"}, "journal": "x"}]}
	# Two quests both enabling brook_bridge.rebuilt — contested.
	var contested: Dictionary = {
		"q1": flip_stage.call("q1", "enable", "brook_bridge.rebuilt"),
		"q2": flip_stage.call("q2", "enable", "brook_bridge.rebuilt")}
	var problems := QuestLint._lint_contested_flips(contested)
	var bit := false
	for p in problems:
		if "contested-flip" in p and "brook_bridge.rebuilt" in p:
			bit = true
	_check(bit, "contested flip caught (two quests enable one group): %s" % problems)
	# One quest, two stages, same group — NOT contested (it owns the group).
	var owned: Dictionary = {"q1": {"format": 2, "id": "q1", "title": "q1", "tier": "errand",
		"stages": [
			{"id": "a", "start": true, "journal": "x", "effects": [{"world": {"enable": ["g"]}}]},
			{"id": "b", "advance_when": {"flag": "k"}, "journal": "x",
				"effects": [{"world": {"disable": ["g"]}}]},
			{"id": "end", "terminal": true, "advance_when": {"flag": "k2"}, "journal": "x"}]}}
	_check(QuestLint._lint_contested_flips(owned).is_empty(),
		"one quest flipping its own group both ways is not contested")
	# Opposite directions by two quests on one group — NOT contested (one owner
	# per direction; enable and disable are different owners, which is allowed).
	var opposite: Dictionary = {
		"q1": flip_stage.call("q1", "enable", "g"),
		"q2": flip_stage.call("q2", "disable", "g")}
	_check(QuestLint._lint_contested_flips(opposite).is_empty(),
		"one quest enables + another disables one group is not contested")


# --- pass 2b: the hook surface + purity (the door's own probes) --------------

## The QuestRun surface laws and the visible-violation guarantee (§6):
##   - q.roll is a PURE function of the day (replay-stable dice)
##   - q.actor is null headless / q.role empty pre-Q4 (the two-tier law)
##   - an IMPURE hook (bare randf) is NOT replay-stable — the harness sees
##     it (run twice from an identical state, the outputs must DIFFER). The
##     same restore-then-replay identity that keeps honest hooks bit-stable
##     is what makes a purity violation visible.
func _hook_probes() -> void:
	print("  hook probes")
	# q.roll: same seed + same day + same tag → same value; a new day moves it.
	WorldState.set_value("world.seed", HARNESS_SEED)
	var run := QuestRun.new("roll_probe", Story, {})
	WorldState.set_value("time.day", 5)
	var r1 := run.roll("t")
	_check(is_equal_approx(r1, run.roll("t")), "q.roll is stable within a day (same tag)")
	_check(not is_equal_approx(run.roll("t"), run.roll("u")), "q.roll varies by tag")
	WorldState.set_value("time.day", 6)
	_check(not is_equal_approx(run.roll("t"), r1), "q.roll varies by day (catch-up honest)")
	# the two-tier law at the hook boundary.
	_check(run.actor("keeper") == null, "q.actor is null headless (data-tier has no body)")
	_check(run.role("keeper") == "", "q.role is empty until Q4 fills it")

	# the visible-violation guarantee: an impure hook diverges across two
	# identical runs — the harness would fail a replay-identity assert on it.
	var impure := {"format": 2, "id": "impure_probe", "title": "Impure", "tier": "errand",
		"start_if": {"flag": "test.impure.start"}, "hooks": "hooks/probe_impure.gd",
		"stages": [
			{"id": "open", "start": true, "journal": "x"},
			{"id": "done", "terminal": true, "advance_when": {"flag": "test.impure.finish"},
				"journal": "y"}]}
	var draws: Array[String] = []
	for _pass in 2:
		_reset_world()
		Story.register_quest(impure)
		WorldState.set_value("test.impure.start", true)  # latch open → on_stage → randf
		draws.append(String(WorldState.get_value("test.impure.draw", "")))
		Story.unregister_quest("impure_probe")
	_check(not draws[0].is_empty() and draws[0] != draws[1],
		"purity probe: an impure hook (bare randf) is NOT replay-stable — the harness sees it")


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
				"expect_flag":
					_check(_flag(String(arg)), "%s %s set" % [at, arg])
				"expect_not_flag":
					_check(not _flag(String(arg)), "%s %s unset" % [at, arg])
				"expect_key":
					var got: Variant = WorldState.get_value(String(arg[0]))
					_check(_same(got, arg[1]), "%s %s want %s got %s" % [at, arg[0], arg[1], got])
				"expect_role":
					var bound := Story.role_of(qid, String(arg[0]))
					_check(bound == String(arg[1]),
						"%s role %s want %s got %s" % [at, arg[0], arg[1], bound])
				"expect_group":
					# [gid, enabled] (or bare gid → true): the raw persistent
					# flip state at world.group.<gid> (default enabled), read
					# through CellRecords (Q10, §3).
					var gid := String(arg[0]) if arg is Array else String(arg)
					var want := bool(arg[1]) if arg is Array else true
					_check(CellRecords.group_enabled(gid) == want,
						"%s group %s want %s got %s" % [at, gid, want, CellRecords.group_enabled(gid)])
				"expect_placement":
					# [{group, enabled?}, active]: the instancing predicate the
					# streamer consults — a grouped record instances iff its
					# group is enabled (the flipped state if present, else the
					# record's authored `enabled` default; authored-dark rides
					# HERE, not in the raw group state above).
					var rec: Dictionary = arg[0]
					var active := bool(arg[1])
					_check(CellRecords.placement_active(rec) == active,
						"%s placement %s want active=%s got %s"
							% [at, rec, active, CellRecords.placement_active(rec)])
				"replay_advance":
					# The hooks door's determinism proof (§10): advance the
					# same span TWICE from a restored snapshot (clock rewound
					# too) and demand the journal.*/choice.*/test.* namespaces
					# match byte-for-byte. Any impurity in a hook fired inside
					# advance_hours — bare randf, a wall-clock read — diverges
					# here. Leaves the world in the replayed state so the
					# asserts after this step run against real latches.
					_check(_replay_advance(float(arg)), "%s bit-identical replay" % at)
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


## "Set" for assertions: present and not false (latch dicts read as set).
func _flag(key: String) -> bool:
	var v: Variant = WorldState.get_value(key)
	return v != null and not (v is bool and v == false)


## Loose equality: JSON numbers are floats, so compare numerics approximately.
func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


## Restore-then-replay: snapshot the world AND the clock, advance the span,
## digest the quest namespaces, rewind everything, advance again, digest
## again — identical means a deterministic, replay-safe run. Returns true on
## a match and leaves the world in the (second) replayed state.
func _replay_advance(hours: float) -> bool:
	var d0 := GameClock.day
	var h0 := GameClock.hours
	var lh0: int = GameClock._last_hour
	var snap := WorldState.snapshot()
	GameClock.advance_hours(hours)
	var first := _replay_digest()
	# rewind the clock's own state (WorldState alone doesn't carry it), restore
	# the world, let every world_state_reader rebuild derived runtime, replay.
	GameClock.day = d0
	GameClock.hours = h0
	GameClock._last_hour = lh0
	WorldState.restore(snap)
	get_tree().call_group("world_state_reader", "load_state")
	GameClock.advance_hours(hours)
	var second := _replay_digest()
	if first != second:
		print("    replay diverged:\n      A: ", first, "\n      B: ", second)
	return first == second


## A canonical digest of the quest-owned namespaces (journal.*/choice.*/
## test.*/world.group.*), key-sorted so insertion order can't fake a
## mismatch, values JSON-stringified (latch dicts have a fixed key order, so
## this is stable). world.group.* rides here so a flip that lands during
## advance_hours catch-up must replay bit-identically — the flip's own
## catch-up law, asserted (Q10, §3/§10).
func _replay_digest() -> String:
	var snap := WorldState.snapshot()
	var keys: Array[String] = []
	for k: String in snap:
		if k.begins_with("journal.") or k.begins_with("choice.") \
				or k.begins_with("test.") or k.begins_with("world.group."):
			keys.append(k)
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [k, JSON.stringify(snap[k])])
	return "\n".join(parts)
