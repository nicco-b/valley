extends Node
## Story (autoload, the Campfire — the layer the design christens "the
## Teller", DESIGN_QUESTS §0/§3/§5): loads quest records, owns the
## condition index, latches stages, and writes the memoir.
##
## THE MONOTONE QUEST: there is no quest state machine and no mutable
## "current stage" variable. A quest is a small DAG of stages; quest
## state is an append-only set of latches — the moment a stage's
## conditions pass while a parent is reached, Story seals
## journal.<quest>.<stage> = {day, season, prose} into WorldState.
## Latches are never cleared, re-evaluated, or edited; failure/expiry
## and every ending are terminal stages like any other; the frontier is
## DERIVED (reached stages with no reached child). Nothing un-happens.
##
## The journal is a memoir written once: prose is resolved and stored IN
## the latch, so the save carries its own text history (a record update
## can never tear out pages — §10 versioning).
##
## Evaluation is event-driven off WorldState.changed through an index
## built by mechanical key extraction (Conditions.keys_of — total,
## because the language is closed). Mirrors update through hour_tick, so
## conditions see replayed time in order and catch-up is correct by
## construction: a quest that should have latched on day 3 of a week
## away latches during replay, stamped with day 3.
##
## v0 (Q1 rung) ships: records + loader validation, the index, latching
## with effects (set/inc/give/take/seal), repeatable errand cycles, HUD
## notify on root/terminal (★3 as ruled at the table: middle stages
## fill the diary silently), the minimal J screen, summary() for the
## Toolkit panel.
## Q3 (the hooks door) adds: a quest record may name a QuestHooks fragment
## (§6); Story instantiates it, builds one QuestRun handle per quest, and
## dispatches typed lifecycle entry points (on_start / on_stage /
## on_objective / on_resolve) plus the `custom` condition predicate — the
## game's hook is the ONLY interpreter, dispatched through a resolver bound
## to the owning quest (never a Strata-invented semantic). Hooks fire from
## latch processing, which is changed-driven, so they replay bit-identically
## through advance_hours catch-up (the harness holds us to it).
## Deferred to their rungs: roles + on_fill (Q4), dialogue (Q5), scenes
## assembler (Q6 — stage scene ids are recorded as requests so the harness
## can assert them), expire machinery + on_expire (Q8), world flips (Q10).
## `mint` records into an in-memory log (harness-visible) and logs once —
## it rides Memory v2's fact channels when S1/B3 lands.
##
## Sim contract: stateless over WorldState (all quest state IS WorldState
## keys under journal.* / choice.*); world_state_reader group rebuilds
## the derived runtime (repeatable cycles) after a save restores.

const QUESTS_DIR := "res://data/quests"
const TIERS: Array[String] = ["errand", "story", "arc"]

var quests: Dictionary = {}  # id -> record, filename order (deterministic)

## key -> Array[String] quest ids watching it (built once from records —
## the design's seed index at quest granularity: a changed key settles
## the handful of small quests that read it; entry-level granularity is
## an optimization the content scale doesn't need yet).
var _index: Dictionary = {}

## Repeatable-cycle runtime, DERIVED from latches (rebuilt on load_state):
## quest id -> {"active": int cycle day or -1, "resolved": int last
## resolve day or -1, "count": int cycles ever started}.
var _cycles: Dictionary = {}

## In-memory mint log (the harness asserts expect_minted against this).
## NOT saved: mints become real fact records when S1/B3 lands.
var _minted: Array[Dictionary] = []
var _mint_logged := false

## Scene requests recorded at stage latch (the assembler is Q6; the
## harness asserts expect_scene_requested against this).
var _scene_requests: Array[String] = []

var _settling: Dictionary = {}  # quest id -> true while _settle runs
var _journal_ui: CanvasLayer = null

## The hooks door (Q3, §6): per-quest QuestHooks instance and the single
## QuestRun handle it receives. Both are pure/stateless (props bound once
## from the record) — cached by quest id, lazily. A cached value of null
## means "loaded, no hook" (the common case; we don't reload every latch).
var _hooks: Dictionary = {}  # quest id -> QuestHooks or null
var _runs: Dictionary = {}   # quest id -> QuestRun


func _ready() -> void:
	add_to_group("world_state_reader")
	_load_quests()
	_build_index()
	WorldState.changed.connect(_on_changed)
	_journal_ui = load("res://game/story/journal_ui.gd").new()
	add_child(_journal_ui)
	_rebuild_cycles()
	_settle_all()  # catch-up: conditions may already hold at boot
	print("[story] %d quest record(s), %d indexed key(s)" % [
		quests.size(), _index.size()])


## Boot _ready runs before a save restores; SaveGame re-calls this after
## restore (world_state_reader contract): rebuild derived runtime from
## the restored latches, then settle — conditions that came true while
## the record set changed (additive updates) latch now.
func load_state() -> void:
	_rebuild_cycles()
	_settle_all()


# --- records ---------------------------------------------------------------

func _load_quests() -> void:
	quests.clear()
	var records := Records.load_dir(QUESTS_DIR, {
		"format": TYPE_FLOAT, "id": TYPE_STRING, "title": TYPE_STRING,
		"tier": TYPE_STRING, "stages": TYPE_ARRAY,
	})
	# The one graph edge quests declare (PLAN.md axiom-4 amendment): a stage's
	# `after` list names its parent stages (§3's explicit-parent rule). Strata's
	# quest flow view renders these arrows and, licensed by THIS declaration,
	# edits them — every drag is a validated `after` write, never a semantics
	# Strata invented. The semantic judge is QuestLint (cycles, unreachable,
	# unknown targets) — the SAME rules test.sh enforces, wired as the kind's
	# validator so an edge edit bounces with the game's own lint words.
	Records.register_edges("quests", [{"field": "after", "to": "stage-id"}])
	Records.register_validator("quests",
		func(rec: Dictionary) -> String:
			var problems := QuestLint.lint_quest(rec)
			return "" if problems.is_empty() else problems[0])
	var keys := records.keys()
	keys.sort()
	for k: String in keys:
		var rec: Dictionary = records[k]
		if int(rec.format) != 2:
			push_error("[story] %s: format %s (this loader speaks 2)" % [k, rec.format])
			continue
		if not (rec.tier in TIERS):
			push_error("[story] %s: unknown tier '%s'" % [k, rec.tier])
			continue
		quests[rec.id] = rec


## The harness door: register a quest record built in a test (and index
## it). Shipped content loads from data/quests — this is for tests-as-
## data driving synthetic shapes through the REAL machinery.
func register_quest(rec: Dictionary) -> void:
	quests[rec.id] = rec
	_build_index()
	_rebuild_cycles()
	_settle(rec.id)


func unregister_quest(id: String) -> void:
	quests.erase(id)
	_cycles.erase(id)
	_hooks.erase(id)
	_runs.erase(id)
	_build_index()


# --- the condition index ---------------------------------------------------

func _build_index() -> void:
	_index.clear()
	for qid: String in quests:
		var q: Dictionary = quests[qid]
		var keys: Array[String] = []
		var conds: Array = [q.get("start_if", {})]
		if q.has("repeatable"):
			keys.append("time.day")  # cooldown re-arm rides the day tick
		for stage: Dictionary in q.stages:
			conds.append(stage.get("advance_when", {}))
			for obj: Dictionary in stage.get("objectives", []):
				conds.append(obj.get("done_if", {}))
		var hook := _hook_of(q)
		for cond: Dictionary in conds:
			keys.append_array(Conditions.keys_of(cond))
			# A custom predicate's index keys come from the record's `watch`
			# (via keys_of above) AND, if a hook is present, whatever it
			# declares in code via custom_keys — the §6 "records may also
			# declare watch" completion, so a code-declared watch still
			# re-evaluates event-driven, never polled.
			if hook != null:
				for name: String in Conditions.custom_names(cond):
					keys.append_array(hook.custom_keys(name))
		for key in keys:
			if not _index.has(key):
				_index[key] = []
			if not (_index[key] as Array).has(qid):
				(_index[key] as Array).append(qid)


func _on_changed(key: String, _value: Variant) -> void:
	if not _index.has(key):
		return
	for qid: String in _index[key]:
		_settle(qid)


func _settle_all() -> void:
	for qid: String in quests:
		_settle(qid)


# --- latching (the monotone core) ------------------------------------------

## Settle one quest to fixpoint: start it if its hour has come, latch
## every stage whose reach condition passes while a parent is reached,
## latch objectives of reached stages. A latch can enable the next test
## in the same instant (a root with no objectives, a child whose key
## changed long ago), so loop until nothing moves. Re-entrant settles of
## the same quest (our own latch writes fire `changed`) are skipped —
## the fixpoint loop catches whatever they would have.
func _settle(qid: String) -> void:
	if _settling.get(qid, false):
		return
	if not quests.has(qid):
		return
	_settling[qid] = true
	var q: Dictionary = quests[qid]
	var moved := true
	while moved:
		moved = false
		if _try_start(q):
			moved = true
		var prefix := _latch_prefix(q)
		if prefix.is_empty():
			break  # never started (and no cycle live)
		for stage: Dictionary in q.stages:
			var sid: String = stage.id
			if reached(qid, sid):
				for obj: Dictionary in stage.get("objectives", []):
					if _try_latch_objective(q, prefix, stage, obj):
						moved = true
			elif _eligible(q, stage) and _reach_passes(q, stage):
				_latch_stage(q, prefix, stage)
				moved = true
	_settling[qid] = false
	if _journal_ui != null and _journal_ui.visible:
		_journal_ui.refresh()


## Latch the root(s) if the quest's start_if holds and it may start:
## plain quests start once, ever; repeatable errands re-arm cooldown_days
## after a cycle resolves, each cycle keyed journal.<id>.<day>.<stage>.
func _try_start(q: Dictionary) -> bool:
	var qid: String = q.id
	var cyc: Dictionary = _cycles.get(qid, {"active": -1, "resolved": -1, "count": 0})
	if q.has("repeatable"):
		if int(cyc.active) >= 0:
			return false  # a cycle is live
		var cooldown := int((q.repeatable as Dictionary).get("cooldown_days", 0))
		if int(cyc.resolved) >= 0 \
				and int(WorldState.get_value("time.day", 0)) < int(cyc.resolved) + cooldown:
			return false
	elif int(cyc.count) > 0:
		return false  # stories never re-arm (§7)
	if not Conditions.eval(q.get("start_if", {}), _custom_resolver(q)):
		return false
	if q.has("repeatable"):
		cyc.active = int(WorldState.get_value("time.day", 0))
	cyc.count = int(cyc.count) + 1
	_cycles[qid] = cyc
	# on_start (§6): after start_if passes and (Q4) roles fill, BEFORE the
	# root seals — the hook may set up world keys the root's prose reads.
	var hook := _hook_of(q)
	if hook != null:
		hook.on_start(_run_of(q))
	var prefix := _latch_prefix(q)
	var rooted := false
	for stage: Dictionary in q.stages:
		if stage.get("start", false):
			_latch_stage(q, prefix, stage)
			rooted = true
	if not rooted:
		push_error("[story] %s: no stage marked start — nothing to latch" % qid)
	return rooted


## A stage is eligible while any parent is reached (roots ride _try_start).
func _eligible(q: Dictionary, stage: Dictionary) -> bool:
	if stage.get("start", false):
		return false
	for pid: String in _parents(q, stage):
		if reached(q.id, pid):
			return true
	return false


## The reach condition: advance_when if declared; otherwise the quest
## advances when a reached parent's non-optional objectives are all
## latched (a parent with no objectives hands off on its own latch).
func _reach_passes(q: Dictionary, stage: Dictionary) -> bool:
	if stage.has("advance_when"):
		return Conditions.eval(stage.advance_when, _custom_resolver(q))
	for pid: String in _parents(q, stage):
		if not reached(q.id, pid):
			continue
		var parent := _stage(q, pid)
		var complete := true
		for obj: Dictionary in parent.get("objectives", []):
			if obj.get("optional", false):
				continue
			if not objective_done(q.id, pid, obj.id):
				complete = false
				break
		if complete:
			return true
	return false


## Implicit DAG (§3): a stage's parents are every earlier non-terminal
## stage, unless it names "after" explicitly.
func _parents(q: Dictionary, stage: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if stage.has("after"):
		for pid: String in stage.after:
			out.append(pid)
		return out
	for other: Dictionary in q.stages:
		if other.id == stage.id:
			break
		if not other.get("terminal", false):
			out.append(other.id)
	return out


## Seal the latch: memoir prose + the day, written ONCE. Effects run,
## mints record, scene requests log, roots and terminals notify (★3).
func _latch_stage(q: Dictionary, prefix: String, stage: Dictionary) -> void:
	var day := int(WorldState.get_value("time.day", 0))
	var latch := {"day": day, "season": GameClock.season,
		"prose": String(stage.get("journal", ""))}
	WorldState.set_value(prefix + String(stage.id), latch)
	print("[story] %s.%s latched (day %d)" % [q.id, stage.id, day])
	for effect: Dictionary in stage.get("effects", []):
		_run_effect(q, effect)
	if stage.has("mint"):
		_mint(q, stage, stage.mint)
	for scene_id: String in stage.get("scenes", []):
		_scene_requests.append("%s.%s" % [q.id, scene_id])
	if stage.get("terminal", false):
		var cyc: Dictionary = _cycles.get(q.id, {"active": -1, "resolved": -1, "count": 1})
		cyc.active = -1
		cyc.resolved = day
		_cycles[q.id] = cyc
	if stage.get("start", false) or stage.get("terminal", false):
		HUD.notify("journal — %s" % _first_words(String(stage.get("journal", q.title))))
	# The hooks door (§6): the CK fragment fires AFTER the latch is sealed
	# and its effects/mint/scenes ran, so the hook sees a consistent world.
	# A terminal also fires on_resolve, after the cycle bookkeeping above so
	# q.reached reflects the resolution.
	var hook := _hook_of(q)
	if hook != null:
		var run := _run_of(q)
		hook.on_stage(run, String(stage.id))
		if stage.get("terminal", false):
			hook.on_resolve(run, String(stage.id))


func _try_latch_objective(q: Dictionary, prefix: String, stage: Dictionary,
		obj: Dictionary) -> bool:
	if objective_done(q.id, stage.id, obj.id):
		return false
	if not Conditions.eval(obj.get("done_if", {}), _custom_resolver(q)):
		return false
	WorldState.set_value("%s%s.%s" % [prefix, stage.id, obj.id],
		{"day": int(WorldState.get_value("time.day", 0))})
	var hook := _hook_of(q)
	if hook != null:
		hook.on_objective(_run_of(q), String(stage.id), String(obj.id))
	return true


## The small closed effect set (§3). `world` flips are Q10; `hook` is Q3.
func _run_effect(q: Dictionary, effect: Dictionary) -> void:
	for kind: String in effect:
		match kind:
			"set":
				WorldState.set_value(effect.set[0], effect.set[1])
			"inc":
				WorldState.increment(effect.inc[0], int(effect.inc[1]))
			"give":
				Items.add(effect.give[0], int(effect.give[1]))
			"take":
				Items.add(effect.take[0], -int(effect.take[1]))
			"latch":
				seal(effect.latch[0], effect.latch[1])
			"mint":
				_mint(q, {}, effect.mint)
			_:
				push_error("[story] %s: effect '%s' is not in the closed set" % [q.id, kind])


## The R2 choice seal: the value AND its flag spelling (conditions gate
## on {"flag": "choice.bank_marker.water"}), written together.
func seal(key: String, value: Variant) -> void:
	WorldState.set_value(key, value)
	WorldState.set_value("%s.%s" % [key, str(value)], true)


func _mint(q: Dictionary, stage: Dictionary, mint: Dictionary) -> void:
	_minted.append({"kind": mint.get("kind", ""), "quest": q.get("id", ""),
		"stage": stage.get("id", ""), "day": int(WorldState.get_value("time.day", 0))})
	if not _mint_logged:
		_mint_logged = true
		print("[story] mint '%s' recorded in memory — fact channels land with S1/B3"
				% mint.get("kind", ""))


# --- the hooks door (§6) ----------------------------------------------------

## The QuestHooks fragment for a quest, loaded and cached lazily. A record
## may name it bare ("hooks": "hooks/x.gd") or bound
## ({"script": ..., "bind": {...}}). Cache null when there is no hook so we
## don't reload every latch. A script that fails to load, or does not extend
## QuestHooks, is an error and caches null (fail safe, never crash).
func _hook_of(q: Dictionary) -> QuestHooks:
	var qid: String = q.id
	if _hooks.has(qid):
		return _hooks[qid]
	var hook: QuestHooks = null
	if q.has("hooks"):
		var path := String(q.hooks) if q.hooks is String \
				else String((q.hooks as Dictionary).get("script", ""))
		var script: Variant = load("res://game/story/" + path)
		if script is GDScript:
			var inst: Variant = (script as GDScript).new()
			if inst is QuestHooks:
				hook = inst
			else:
				push_error("[story] %s: hooks script '%s' does not extend QuestHooks" % [qid, path])
		else:
			push_error("[story] %s: hooks script '%s' failed to load" % [qid, path])
	_hooks[qid] = hook
	return hook


## The single QuestRun handle a quest's hook receives (props bound once from
## the record). Built lazily, reused across every lifecycle call.
func _run_of(q: Dictionary) -> QuestRun:
	var qid: String = q.id
	if _runs.has(qid):
		return _runs[qid]
	var props: Dictionary = {}
	if q.get("hooks") is Dictionary:
		props = (q.hooks as Dictionary).get("bind", {})
	var run := QuestRun.new(qid, self, props)
	_runs[qid] = run
	return run


## A custom-predicate resolver bound to THIS quest's hook — the door that
## lets the closed condition language dispatch a game-declared predicate
## without Story ever inventing a semantic. Returns an empty Callable for
## an unhooked quest (custom then fails closed, honestly).
func _custom_resolver(q: Dictionary) -> Callable:
	if not q.has("hooks"):
		return Callable()
	return func(name: String, args: Array) -> bool:
		var hook := _hook_of(q)
		if hook == null:
			return false
		return hook.condition(_run_of(q), name, args)


## q.latch — advance a stage by fiat from a hook. Monotone holds: an
## already-reached stage is a no-op; the seal (and its own on_stage/
## on_resolve dispatch) run exactly as any other latch.
func hook_latch(qid: String, stage_id: String) -> void:
	if not quests.has(qid):
		return
	var q: Dictionary = quests[qid]
	var stage := _stage(q, stage_id)
	if stage.is_empty():
		push_error("[story] %s: hook latched unknown stage '%s'" % [qid, stage_id])
		return
	if reached(qid, stage_id):
		return
	var prefix := _latch_prefix(q)
	if prefix.is_empty():
		return  # never started — nothing to hang the latch on
	_latch_stage(q, prefix, stage)


## q.mint — a hook mints a fact (harness-visible until S1/B3's channels).
func hook_mint(qid: String, data: Dictionary) -> void:
	_mint(quests.get(qid, {"id": qid}), {}, data)


## q.request_scene — a hook records a scene request (Q6 assembler asserts it).
func hook_request_scene(qid: String, scene_id: String) -> void:
	_scene_requests.append("%s.%s" % [qid, scene_id])


# --- readings (all derived from WorldState) ---------------------------------

## journal.<id>. for plain quests; journal.<id>.<cycle_day>. for the
## LATEST cycle of a repeatable errand (older cycles stay in the save,
## keyed by their day — the journal shows the freshest).
func _latch_prefix(q: Dictionary) -> String:
	if not q.has("repeatable"):
		return "journal.%s." % q.id
	var cyc: Dictionary = _cycles.get(q.id, {})
	var day := int(cyc.get("active", -1))
	if day < 0:
		day = _latest_cycle_day(q.id)
	if day < 0:
		return ""
	return "journal.%s.%d." % [q.id, day]


func reached(quest_id: String, stage_id: String) -> bool:
	var q: Dictionary = quests.get(quest_id, {})
	if q.is_empty():
		return false
	var prefix := _latch_prefix(q)
	if prefix.is_empty():
		return false
	return WorldState.get_value(prefix + stage_id) is Dictionary


func reached_day(quest_id: String, stage_id: String) -> int:
	var q: Dictionary = quests.get(quest_id, {})
	if q.is_empty():
		return -1
	return Conditions.latch_day(WorldState.get_value(_latch_prefix(q) + stage_id))


func objective_done(quest_id: String, stage_id: String, obj_id: String) -> bool:
	var q: Dictionary = quests.get(quest_id, {})
	if q.is_empty():
		return false
	return WorldState.get_value("%s%s.%s" % [_latch_prefix(q), stage_id, obj_id]) \
			is Dictionary


## Cycles ever started (repeatables count re-arms; plain quests 0 or 1).
func cycle_count(quest_id: String) -> int:
	return int((_cycles.get(quest_id, {}) as Dictionary).get("count", 0))


## A quest is resolved when any terminal stage of its latest cycle is
## reached (repeatable quests: resolved between cycles).
func resolved(quest_id: String) -> bool:
	var q: Dictionary = quests.get(quest_id, {})
	for stage: Dictionary in q.get("stages", []):
		if stage.get("terminal", false) and reached(quest_id, stage.id):
			return true
	return false


func started(quest_id: String) -> bool:
	return cycle_count(quest_id) > 0


## The derived frontier: reached stages with no reached child.
func frontier(quest_id: String) -> Array[String]:
	var q: Dictionary = quests.get(quest_id, {})
	var out: Array[String] = []
	for stage: Dictionary in q.get("stages", []):
		if not reached(quest_id, stage.id):
			continue
		var has_reached_child := false
		for other: Dictionary in q.stages:
			if other.id != stage.id and _parents(q, other).has(String(stage.id)) \
					and reached(quest_id, other.id):
				has_reached_child = true
				break
		if not has_reached_child:
			out.append(String(stage.id))
	return out


func minted() -> Array[Dictionary]:
	return _minted


func scene_requests() -> Array[String]:
	return _scene_requests


func _stage(q: Dictionary, stage_id: String) -> Dictionary:
	for stage: Dictionary in q.stages:
		if stage.id == stage_id:
			return stage
	return {}


## Rebuild the repeatable-cycle runtime from the latches in WorldState —
## the ONLY derived state Story keeps (everything else reads through).
func _rebuild_cycles() -> void:
	_cycles.clear()
	var snapshot := WorldState.snapshot()
	for qid: String in quests:
		var q: Dictionary = quests[qid]
		var cyc := {"active": -1, "resolved": -1, "count": 0}
		if not q.has("repeatable"):
			var prefix := "journal.%s." % qid
			for key: String in snapshot:
				if key.begins_with(prefix):
					cyc.count = 1
					break
			if cyc.count == 1:
				for stage: Dictionary in q.stages:
					if stage.get("terminal", false) \
							and snapshot.get(prefix + String(stage.id)) is Dictionary:
						cyc.resolved = Conditions.latch_day(snapshot[prefix + String(stage.id)])
		else:
			var days: Array[int] = []
			var prefix := "journal.%s." % qid
			for key: String in snapshot:
				if key.begins_with(prefix):
					var head := key.trim_prefix(prefix).split(".")[0]
					if head.is_valid_int() and not days.has(head.to_int()):
						days.append(head.to_int())
			days.sort()
			cyc.count = days.size()
			if not days.is_empty():
				var latest: int = days.back()
				var live := true
				for stage: Dictionary in q.stages:
					if stage.get("terminal", false) and snapshot.get(
							"journal.%s.%d.%s" % [qid, latest, stage.id]) is Dictionary:
						cyc.resolved = Conditions.latch_day(
							snapshot["journal.%s.%d.%s" % [qid, latest, stage.id]])
						live = false
						break
				if live:
					cyc.active = latest
		_cycles[qid] = cyc


func _latest_cycle_day(qid: String) -> int:
	var latest := -1
	var prefix := "journal.%s." % qid
	for key: String in WorldState.snapshot():
		if key.begins_with(prefix):
			var head := (key as String).trim_prefix(prefix).split(".")[0]
			if head.is_valid_int():
				latest = maxi(latest, head.to_int())
	return latest


func _first_words(prose: String, count: int = 7) -> String:
	var words := prose.split(" ", false)
	if words.size() <= count:
		return prose
	return " ".join(words.slice(0, count)) + "…"


## Toolkit world panel line (F1.5: systems the Toolkit can't see are debt).
func summary() -> String:
	var active := 0
	var done := 0
	for qid: String in quests:
		if not started(qid):
			continue
		if resolved(qid):
			done += 1
		else:
			active += 1
	return "%d quest record(s), %d active, %d remembered, %d minted" % [
		quests.size(), active, done, _minted.size()]
