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
## Q4 (roles, §4) adds: role declarations fill from the LIVE world by a
## deterministic query (require filter, prefer + id-sort rank, is/near, no
## RNG); fills LATCH to journal.<q>.role.<name> (replay-safe, never re-roll);
## $role substitutes into condition keys, the seed index, and memoir prose;
## and on_fill (§6) gives the hook the last word over the data-ranked pick.
## Q10 (world flips, §3) adds: the `world` stage effect flips persistent world
## GROUPS — {"enable": [...], "disable": [...]} sets world.group.<id> in
## WorldState. Groups are MUTABLE world truth, not latches (a later stage may
## flip one back — the camp struck, the barrier removed); the value is a plain
## WorldState key, so it is saved/restored verbatim (zero new save code) and
## caught up FOR FREE — a flip rides the stage that carries it, and stages
## re-latch in day order through advance_hours replay, so the final group
## state is deterministic by construction (the catch-up law). CellRecords
## consults world.group.<id> when instancing (placement_active); authored-dark
## placements (`enabled:false`) start a group off until a stage enables it.
## The world.group.* namespace joins the soak fingerprint (§10/B13) so a
## playerless year latches groups identically every run.
## Deferred to their rungs: dialogue (Q5), scenes assembler (Q6 — stage scene
## ids are recorded as requests so the harness can assert them), expire
## machinery + on_expire (Q8).
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

# --- Contour routing (PLAN_ENGINE E2, Mission D1e: the Teller's latch/index rules) --
## The pure RULES tier of the Teller — the index construction (_cond_index_keys), the
## §3 stage DAG (_parents/_stage), $role substitution into prose + conditions
## (_subst_str/_subst_cond), and Q4's deterministic role order + prefer-ranked fill
## (_roles_ordered/_role_fill_when/_rank_by_matrix) — is certified bit-identical to
## its Lattice twin by datum's Plumb harness (story_*.jsonl corpora, over the
## byte-identical vendored bodies). When STRATA_CONTOUR=1 — a boot-time sim flag, read
## once, DevMode-independent, default OFF — these call sites route through the native
## Contour VM (game/story/story.ct via game/sim/contour.gd) instead of the GDScript
## below. Flag OFF is byte-identical GDScript. This is the LATCH PATH: a journal
## latch's TIMING (the index — which key settles which quest), STRUCTURE (the DAG),
## PROSE ($role-resolved memoir), and ROLE binding all resolve through these, and
## journal latches ARE the soak fingerprint's story section (C1's precedent squared).
##
## NO SILENT FALLBACK (the honesty law): flag ON with the kernel absent (not macOS /
## no dylib) or a module that will not compile is a LOUD refusal (push_error, mode
## -1), never a quiet GDScript pass — so a soak that believes it exercised the VM
## cannot secretly be running the twin. The routed functions carry a call counter
## (contour_status) so the scene test / soak can prove the VM actually answered.
##
## The GLUE stays valley-side: the fixpoint _settle loop + its Conditions.eval calls
## (eval reads the WorldState mirror + dispatches the hook resolver — a Callable), the
## QuestHooks .gd dispatch, _subst_map (reads player.region + role bindings from
## WorldState), the candidate SCAN + require/prefer MATCH (mirror reads — the match
## matrix is precomputed here, then handed to the pure _rank_by_matrix).
const _CONTOUR_MODULE := "res://game/story/story.ct"
## 0 unresolved · 1 off (flag unset) · 2 engaged (VM live) · -1 refused (flag set
## but kernel/module unavailable — loud, not silent).
var _contour_mode := 0
var _contour_vm: Contour = null
var _contour_calls := 0   # VM-answered rule calls (the engaged-path probe)

# --- the live hook-dispatch route (E5.8, env hatch STRATA_HOOK_DISPATCH) -----
## E5.4 crossed the pure hook_dispatch DECISION (which effect-refs fire, in what
## order) + certified it byte-identical by Plumb. E5.8 makes that decision LIVE:
## the OO lifecycle dispatch (on_start / on_stage / on_objective / on_resolve) is
## routed THROUGH hook_dispatch instead of calling the QuestHooks virtual straight.
## Each lifecycle event builds a one-row synthetic handler table {trigger: <phase>,
## effect: <phase>} with an always-true answer, hands it to the certified decision,
## and applies the returned effect-ref by calling the OO virtual — the marker split
## verbatim (the DECISION crosses to sim, the effect BODY stays valley-side glue).
## A one-row unscoped table fires exactly once in declared order, so the routed path
## is byte-identical to the direct OO calls over the whole OO corpus (hook_errand /
## hook_replay / role_*) — the honest first LIVE step, proven in both postures.
##
## THE HATCH: STRATA_HOOK_DISPATCH=1 routes live; anything else (default) keeps the
## direct OO calls. Flipping the DEFAULT is a coordinator ruling (kept OFF here). Read
## once, cached; a test setter (_force_hook_dispatch) lets the harness drive BOTH
## postures in one process for the byte-identity proof. A call counter proves the
## routed path actually answered (no silent no-op when the hatch is set).
## 0 unresolved · 1 off (direct OO) · 2 on (routed through hook_dispatch).
var _hd_mode := 0
var _hd_calls := 0   # hook_dispatch-answered lifecycle events (the routed-path probe)


## Is the live hook-dispatch route engaged? Resolves the hatch once (boot), cached.
func _hook_dispatch_live() -> bool:
	if _hd_mode == 0:
		_hd_mode = 2 if OS.get_environment("STRATA_HOOK_DISPATCH") == "1" else 1
	return _hd_mode == 2


## Test-only: force the route on/off so the harness can run both postures in one
## process (the byte-identity proof). Resets the answered-call counter.
func _force_hook_dispatch(on: bool) -> void:
	_hd_mode = 2 if on else 1
	_hd_calls = 0


## Routing introspection for the harness: the posture and the answered-event count
## (proves the routed path actually dispatched, never a silent no-op when set).
func hook_dispatch_status() -> Dictionary:
	return {"live": _hook_dispatch_live(), "calls": _hd_calls}


## Dispatch ONE lifecycle event to a quest's OO hook. When the live route is
## engaged, the WHICH-fires decision crosses through the certified hook_dispatch
## (a one-row synthetic table for this phase, always-true answer); the returned
## effect-ref is applied by calling the OO virtual — byte-identical to the direct
## call, but the decision is now the sim-tier one. `target` scopes the event
## (stage id / objective id / outcome id; "" for on_start).
func _dispatch_hook(hook: QuestHooks, run: QuestRun, phase: String, target: String,
		obj_id: String = "") -> void:
	if _hook_dispatch_live():
		_hd_calls += 1
		var handlers := [{"trigger": phase, "effect": phase}]
		for effect in hook_dispatch(handlers, phase, target, [true]):
			_apply_hook_effect(hook, run, String(effect), target, obj_id)
	else:
		_apply_hook_effect(hook, run, phase, target, obj_id)


## Apply one resolved effect-ref by calling the matching OO lifecycle virtual —
## the valley-side effect body (the marker split's glue half). Total over the
## closed lifecycle vocabulary; an unknown ref is a loud refusal, never silent.
func _apply_hook_effect(hook: QuestHooks, run: QuestRun, effect: String,
		target: String, obj_id: String) -> void:
	match effect:
		"on_start":
			hook.on_start(run)
		"on_stage":
			hook.on_stage(run, target)
		"on_objective":
			hook.on_objective(run, target, obj_id)
		"on_resolve":
			hook.on_resolve(run, target)
		_:
			push_error("[story] hook effect-ref '%s' is not a lifecycle phase" % effect)


## The live VM when routing is engaged, else null (flag off, or refused). Resolves
## once at first touch (boot); pure — no WorldState side effects, so flag-off is
## byte-identical to the un-routed code.
func _route_contour() -> Contour:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour_vm


func _contour_resolve() -> void:
	var verdict := Contour.decide("story")
	if verdict != Contour.ROUTE_ENGAGE:
		_contour_mode = verdict   # ROUTE_FALLBACK (GDScript twin) or ROUTE_REFUSE (loud, mode -1)
		return
	# Routing engaged — compile the module (a compile failure still refuses loudly).
	var vm := Contour.new()
	var err := vm.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[story] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour_vm = vm
	_contour_mode = 2


## Routing introspection for the scene test / soak (proves the VM answered, not a
## silent fallback): the resolved mode, whether it engaged, and the answered-call count.
func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}


## Coerce a VM-returned Array to a typed Array[String] (call_fn returns an untyped
## Array; the ported functions' GDScript signatures type it).
func _ctr_strings(v: Variant) -> Array[String]:
	var out: Array[String] = []
	for e in v:
		out.append(String(e))
	return out


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
		var smap := _subst_map(q)  # resolve $role/$built-in keys after fill (§5)
		# The condition-derived index keys — the CERTIFIED pure rule, routed behind
		# STRATA_CONTOUR: keys_of ∘ _subst_cond over start_if + every stage
		# advance_when + every objective done_if, plus time.day for repeatable/roles.
		# $role keys index after fill, on the binding's latch (§5): the substituted
		# key (npc.wanderer.met) is what a changed touch settles.
		var keys := _cond_index_keys(q, smap)
		# A custom predicate's index keys come from the record's `watch` (folded into
		# keys_of above) AND, if a hook is present, whatever it declares in code via
		# custom_keys — the §6 "records may also declare watch" completion, so a
		# code-declared watch still re-evaluates event-driven, never polled. This
		# merge stays valley-side (it reaches the game's hook .gd, a Callable); the
		# _index is a SET keyed by watched key, so the pure keys and the hook keys
		# compose to the same index regardless of append order.
		var hook := _hook_of(q)
		if hook != null:
			var conds: Array = [q.get("start_if", {})]
			for stage: Dictionary in q.stages:
				conds.append(stage.get("advance_when", {}))
				for obj: Dictionary in stage.get("objectives", []):
					conds.append(obj.get("done_if", {}))
			for cond: Dictionary in conds:
				for name: String in Conditions.custom_names(cond):
					keys.append_array(hook.custom_keys(name))
		for key in keys:
			if not _index.has(key):
				_index[key] = []
			if not (_index[key] as Array).has(qid):
				(_index[key] as Array).append(qid)


## The condition-derived index keys a quest watches — the pure core of _build_index
## (CERTIFIED bit-identical by Plumb, routed behind STRATA_CONTOUR). keys_of ∘
## _subst_cond over start_if + every stage advance_when + every objective done_if,
## plus the day-tick re-arm keys for repeatable/roles. The hook-declared custom_keys
## merge stays valley-side (see _build_index) — a Callable dispatch, never a Contour
## semantic; the index is a set keyed by watched key, so the split is lossless.
func _cond_index_keys(q: Dictionary, subst: Dictionary) -> Array[String]:
	var vm := _route_contour()
	if vm != null:
		_contour_calls += 1
		return _ctr_strings(vm.call_fn("_cond_index_keys", [q, subst]))
	var keys: Array[String] = []
	if q.has("repeatable"):
		keys.append("time.day")  # cooldown re-arm rides the day tick
	if q.has("roles"):
		keys.append("time.day")  # a HELD role retries on the day tick (§4)
	var conds: Array = [q.get("start_if", {})]
	for stage: Dictionary in q.stages:
		conds.append(stage.get("advance_when", {}))
		for obj: Dictionary in stage.get("objectives", []):
			conds.append(obj.get("done_if", {}))
	for cond: Dictionary in conds:
		keys.append_array(Conditions.keys_of(_subst_cond(cond, subst)))
	return keys


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
				if _fill_on_stage(q, sid):  # a held on_stage role got a candidate (§4)
					moved = true
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
	if not _eval_cond(q, q.get("start_if", {})):
		return false
	# Q4 (§4): fill on_start roles before the quest commits. Filling is a
	# deterministic query (require filter, prefer + id-sort rank, no RNG); a
	# role that can't fill HOLDS — the start aborts with NOTHING written and
	# retries next settle (start_if keys + time.day are indexed). All-or-none:
	# a partial fill would look like a started quest to _rebuild_cycles.
	var plan := _plan_on_start(q)
	if not plan.ok:
		return false
	if q.has("repeatable"):
		cyc.active = int(WorldState.get_value("time.day", 0))
	cyc.count = int(cyc.count) + 1
	_cycles[qid] = cyc
	# Seal the bindings (latched, replay-safe) BEFORE the on_start hook and
	# the root prose, so q.role and $role substitution resolve them.
	if not plan.bind.is_empty():
		for rn: String in plan.bind:
			WorldState.set_value("journal.%s.role.%s" % [qid, rn], plan.bind[rn])
		_build_index()  # $role keys index now that the bindings resolve (§5)
	# on_start (§6): after start_if passes and (Q4) roles fill, BEFORE the
	# root seals — the hook may set up world keys the root's prose reads.
	var hook := _hook_of(q)
	if hook != null:
		_dispatch_hook(hook, _run_of(q), "on_start", "")
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
		return _eval_cond(q, stage.advance_when)
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
	var vm := _route_contour()
	if vm != null:
		_contour_calls += 1
		return _ctr_strings(vm.call_fn("_parents", [q, stage]))
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
	# Q4 (§4): fill any role that fills on THIS stage, before the prose
	# resolves — so the memoir names who was actually there (§8).
	_fill_on_stage(q, String(stage.id))
	var day := int(WorldState.get_value("time.day", 0))
	var latch := {"day": day, "season": GameClock.season,
		"prose": _subst_str(String(stage.get("journal", "")), _subst_map(q))}
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
		# Two dispatch calls at a terminal (on_stage THEN on_resolve): the phase
		# SEQUENCING is glue, the per-phase decision crosses through hook_dispatch.
		_dispatch_hook(hook, run, "on_stage", String(stage.id))
		if stage.get("terminal", false):
			_dispatch_hook(hook, run, "on_resolve", String(stage.id))


func _try_latch_objective(q: Dictionary, prefix: String, stage: Dictionary,
		obj: Dictionary) -> bool:
	if objective_done(q.id, stage.id, obj.id):
		return false
	if not _eval_cond(q, obj.get("done_if", {})):
		return false
	WorldState.set_value("%s%s.%s" % [prefix, stage.id, obj.id],
		{"day": int(WorldState.get_value("time.day", 0))})
	var hook := _hook_of(q)
	if hook != null:
		_dispatch_hook(hook, _run_of(q), "on_objective", String(stage.id), String(obj.id))
	return true


## The small closed effect set (§3). `world` flips groups (Q10); `hook` is Q3.
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
			"world":
				_flip_groups(effect.world)
			_:
				push_error("[story] %s: effect '%s' is not in the closed set" % [q.id, kind])


## Q10 world flips (§3): set the persistent group state at world.group.<id>.
## disable before enable, so a group named in both (an author slip the linter
## also warns) resolves enabled. The value is a plain WorldState key — saved,
## restored, and caught up with the stage that carries it; CellRecords reads it
## through placement_active. Groups are mutable truth, so a later stage flipping
## a group back is ordinary (never a latch that could un-happen).
func _flip_groups(flip: Dictionary) -> void:
	for gid: String in flip.get("disable", []):
		WorldState.set_value("world.group." + gid, false)
	for gid: String in flip.get("enable", []):
		WorldState.set_value("world.group." + gid, true)


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


# --- the data-driven hooks door (E5.4, E5_RULINGS #4: the marker precedent) --
## Quest hooks go DATA, not OO — the ruling on E5_RULINGS #4, on the strength of
## the marker precedent (agent_sim's `marker_resolver`, CONTOUR.md §4). The OO
## fragment above (QuestHooks + virtual on_start/on_stage/on_objective/on_resolve)
## grows a DECLARED HANDLER TABLE beside it: a quest's `handlers` is an array of
##   { "trigger": <phase[:id]>, "condition": <ref>, "effect": <ref> }
## records, where
##   * trigger — the lifecycle phase, optionally `:`-scoped to a stage/objective/
##     outcome id, REUSING the `on_stage:<id>` spelling `fill` already speaks
##     (_role_fill_when): on_start · on_stage · on_stage:<id> · on_objective ·
##     on_objective:<id> · on_resolve · on_resolve:<id>. An unscoped trigger fires
##     for every event of its phase; a scoped one only for its named target.
##   * condition — OPTIONAL. A condition-REF the host PRE-RESOLVES to a bool before
##     dispatch (the Callable-as-data door §4): the arbitrary predicate body stays
##     valley-side exactly as marker_resolver does, and Contour sees only the ANSWER.
##     Absent ⇒ unconditional (the host still supplies `true` in its slot).
##   * effect — an effect-REF the host pre-resolves and applies AFTER dispatch, the
##     same Callable-as-data door in reverse: Contour never holds the effect body,
##     it hands the ref back OUT for the host to run through the closed effect set.
##
## THE PURE DECISION crosses (certified below); the two RESOLVERS stay glue — the
## condition resolver (arbitrary predicate → the answers bool) and the effect
## resolver (a returned ref → a world touch) are unbounded GDScript, banned from a
## `sim` tier by construction (§4), so they live valley-side just like the OO
## `condition`/`on_*` bodies do today. This is the marker split, verbatim: the
## RESOLVER is data GDScript-side, the port reads only the resolved data.

## The pure hook dispatch (CERTIFIED bit-identical by Plumb, story_hook_dispatch):
## given a quest's declared handler table, the current lifecycle event (a `phase`
## + a `target` id — "" for on_start), and the host-preresolved `answers` (a bool
## per handler, parallel by index — the Callable-as-data condition door), return
## the ORDERED list of effect-refs to fire. Order-preserving (a stage's handlers
## fire in declared order), total over the closed trigger vocabulary, no world read
## crosses (the answers ARE the world read, done glue-side). The `_trigger_matches`
## phase/scope test mirrors _role_fill_when's `on_stage:<id>` split, so the two
## `:`-scoped conventions stay one shape. A terminal latch's on_stage-then-
## on_resolve sequencing is TWO calls (one per phase) from the caller — the phase
## ordering is glue (the enumerated remainder), the per-phase decision is here.
func hook_dispatch(handlers: Array, phase: String, target: String,
		answers: Array) -> Array:
	var vm := _route_contour()
	if vm != null:
		_contour_calls += 1
		return vm.call_fn("hook_dispatch", [handlers, phase, target, answers])
	var out := []
	for i in handlers.size():
		var h: Dictionary = handlers[i]
		if _trigger_matches(h.trigger, phase, target):
			if answers[i]:
				out.append(h.effect)
	return out


## A handler's trigger vs the current phase/target — the `on_stage:<id>` split
## _role_fill_when already speaks, generalized to every phase. `trigger.split(":")`
## yields [phase] or [phase, id]; the phase must match, and a scoped trigger must
## also match the target (an unscoped one fires for any). Total over the closed
## trigger vocabulary (mirrors quest_lint's `after.split(":")` fence).
func _trigger_matches(trigger: String, phase: String, target: String) -> bool:
	var parts := trigger.split(":")
	if parts[0] != phase:
		return false
	if parts.size() > 1:
		return parts[1] == target
	return true


# --- the roles filler (§4) --------------------------------------------------
## CK's aliases, sim-native: a role is a named slot Story fills from the
## LIVE world when the quest needs it. Filling is a DETERMINISTIC query —
## candidates of the role's `kind` passing `require`, ranked by `prefer` in
## order, ties broken by id sort; no RNG in the fill path (the soak holds us
## to it, and the fork determinism trap is armed on this exact surface — so
## every candidate list is SORTED before it is ranked, never trusting a
## Dictionary's insertion order). Fills are LATCHED (journal.<q>.role.<name>
## = the bound id, a WorldState key that rides snapshot/restore untouched) so
## a bound role survives restore-then-replay bit-identically and NEVER
## re-rolls — the CK alias-recast bug made structurally impossible.
##
## Pinned authored cast (`"is": "keeper"`) fills to the literal id with no
## query. The on_fill hook (§6) may override the data-ranked pick. A role
## that can't fill honors `fallback`: hold (default — retry next settle) or
## abandon (v1: also retried; the "never offers" permanence is a later rung).


## The frontier of the fill plan for on_start roles: bind every on_start role
## into a local map, ALL-OR-NOTHING (a partial commit would look like a
## started quest). {"ok": bool, "bind": {name: id}} — ok=false means a role
## held/abandoned and the caller must abort the start with nothing written.
func _plan_on_start(q: Dictionary) -> Dictionary:
	var bind: Dictionary = {}
	for rn: String in _roles_ordered(q):
		var spec: Dictionary = q.roles[rn]
		if _role_fill_when(spec) != "on_start":
			continue
		if _role_bound(q, rn):
			continue
		var known := _subst_map(q)
		for k: String in bind:  # a later role may reference an earlier binding
			known[k] = bind[k]
		var id := _fill_role_now(q, rn, spec, known)
		if id == "":
			return {"ok": false, "bind": {}}
		bind[rn] = id
	return {"ok": true, "bind": bind}


## Fill roles that bind on THIS stage's latch, best-effort (the stage already
## latched — a hold can't rewind it, so an unfilled role simply retries on the
## next settle). Returns true if any role bound (drives the fixpoint loop).
func _fill_on_stage(q: Dictionary, stage_id: String) -> bool:
	if not q.has("roles"):
		return false
	var moved := false
	for rn: String in _roles_ordered(q):
		var spec: Dictionary = q.roles[rn]
		if _role_fill_when(spec) != ("on_stage:" + stage_id):
			continue
		if _role_bound(q, rn):
			continue
		var id := _fill_role_now(q, rn, spec, _subst_map(q))
		if id != "":
			WorldState.set_value("journal.%s.role.%s" % [q.id, rn], id)
			_build_index()
			moved = true
	return moved


## Fill ONE role: pinned `is` binds its literal id; otherwise the query —
## candidates of `kind`, filtered by `require`, ranked by `prefer` + id sort,
## with on_fill (§6) given the last word. Returns the bound id, or "" when
## nothing qualifies (the caller reads `fallback`).
func _fill_role_now(q: Dictionary, role_name: String, spec: Dictionary,
		known: Dictionary) -> String:
	if spec.has("is"):
		return String(spec["is"])  # pinned authored cast — no query
	var kind := String(spec.get("kind", ""))
	var passing: Array[String] = []
	for id: String in _candidates(kind):
		if _match_all(q, spec.get("require", []), kind, id, known):
			passing.append(id)
	var ranked := _rank(q, passing, spec.get("prefer", []), kind, known)
	var hook := _hook_of(q)
	if hook != null:
		var choice := String(hook.on_fill(_run_of(q), role_name, ranked))
		if choice != "":  # the wit overrides the data-ranked pick (§6)
			return choice
	return ranked[0] if not ranked.is_empty() else ""


## Candidates of a kind: the ids the live world has mirrored under
## <kind>.<id>.* (the mirror law — a present entity has mirrored attrs).
## SORTED, so the ranking never depends on WorldState insertion order (the
## determinism trap). $player is a built-in binding, never a candidate.
func _candidates(kind: String) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	var pre := kind + "."
	for key: String in WorldState.snapshot():
		if not key.begins_with(pre):
			continue
		var id := key.substr(pre.length()).split(".")[0]
		if id.is_empty() or id == "player" or seen.has(id):
			continue
		seen[id] = true
		out.append(id)
	out.sort()
	return out


## Rank passing candidates: `prefer` rows are ordered tie-breakers (first
## discriminating wins — a passer sorts ahead of a failer); the final,
## TOTAL tie-break is the id sort, so the order is deterministic regardless
## of sort stability.
func _rank(q: Dictionary, cands: Array[String], prefer: Array,
		kind: String, known: Dictionary) -> Array[String]:
	# Precompute the prefer-match MATRIX (the mirror reads _match makes — those stay
	# glue), then rank through the certified pure sort (_rank_by_matrix, routed).
	# Precomputing each _match ONCE (vs the comparator's re-evaluations) is
	# bit-identical — _match is pure over the world — and the id-sort tiebreak keeps
	# the order total, so the selection sort and GDScript's introsort agree.
	var matrix: Dictionary = {}
	for id: String in cands:
		var row: Array = []
		for cond: Dictionary in prefer:
			row.append(_match(cond, _match_ctx(q, kind, id, known)))
		matrix[id] = row
	return _ctr_strings(_rank_by_matrix(cands, matrix))


## Rank passing candidates over a PRECOMPUTED prefer-match matrix (matrix[id] = the
## array of `prefer`-row booleans, computed valley-side by _match). The pure sort core
## of _rank (CERTIFIED bit-identical by Plumb, routed behind STRATA_CONTOUR): `prefer`
## rows are ordered tie-breakers (first discriminating wins — a passer sorts ahead of
## a failer); the final, TOTAL tie-break is the id sort, deterministic regardless of
## sort stability.
func _rank_by_matrix(cands: Array, matrix: Dictionary) -> Array:
	var vm := _route_contour()
	if vm != null:
		_contour_calls += 1
		return vm.call_fn("_rank_by_matrix", [cands, matrix])
	var ranked := cands.duplicate()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		var ma: Array = matrix[a]
		var mb: Array = matrix[b]
		for r in ma.size():
			if ma[r] != mb[r]:
				return ma[r]
		return a < b)
	return ranked


## True when EVERY require row matches for this candidate ($self bound to it).
func _match_all(q: Dictionary, require: Array, kind: String, self_id: String,
		known: Dictionary) -> bool:
	var ctx := _match_ctx(q, kind, self_id, known)
	for cond: Dictionary in require:
		if not _match(cond, ctx):
			return false
	return true


func _match_ctx(q: Dictionary, kind: String, self_id: String,
		known: Dictionary) -> Dictionary:
	var subst := known.duplicate()
	subst["self"] = self_id
	return {"kind": kind, "subst": subst, "resolver": _custom_resolver(q)}


## One role-query condition (the shared vocabulary + the role-only predicates
## `tagged` and `near`, which conditions never test — §5). all/any/not
## compose; every other row is substituted ($self/$role/$player_region) and
## delegated to Conditions.eval, so require/prefer speak the same language as
## every gate in the game.
func _match(cond: Dictionary, ctx: Dictionary) -> bool:
	for key: String in cond:
		match key:
			"all":
				for sub: Dictionary in cond.all:
					if not _match(sub, ctx):
						return false
			"any":
				var passed := false
				for sub: Dictionary in cond.any:
					if _match(sub, ctx):
						passed = true
						break
				if not passed:
					return false
			"not":
				if _match(cond["not"], ctx):
					return false
			"tagged":
				# the keyword law: a candidate carries a tag (record data,
				# mirrored to <kind>.<id>.tags). Identity-free, like every
				# radiant gate — one authored quest meets many worlds (§4).
				var id := String(_subst_str(String(cond.tagged[0]), ctx.subst))
				var tags: Variant = WorldState.get_value(
					"%s.%s.tags" % [ctx.kind, id], [])
				if not (tags is Array and (tags as Array).has(cond.tagged[1])):
					return false
			"near":
				# v1 proximity: same region. `near [$self, <region>]` — the
				# candidate's mirrored region equals the (substituted) region.
				var id := String(_subst_str(String(cond.near[0]), ctx.subst))
				var want := _subst_str(String(cond.near[1]), ctx.subst)
				if String(WorldState.get_value(
						"%s.%s.region" % [ctx.kind, id], "")) != want:
					return false
			_:
				var single := {key: cond[key]}
				if not Conditions.eval(_subst_cond(single, ctx.subst), ctx.resolver):
					return false
	return true


# --- $role substitution (§4: everywhere strings meet the system) ------------

## The binding map for a quest: built-ins ($player, $player_region, $hook)
## plus every filled role ($<name> -> bound id). Resolved at read time, so a
## re-index or prose write always sees the freshest bindings.
func _subst_map(q: Dictionary) -> Dictionary:
	var m: Dictionary = {"player": "player"}
	m["player_region"] = String(WorldState.get_value("player.region", ""))
	if q.has("hook"):
		m["hook"] = String(q.hook)  # the fact that started the quest (errands love this)
	for rn: String in q.get("roles", {}):
		var v: Variant = WorldState.get_value("journal.%s.role.%s" % [q.id, rn])
		if v is String and v != "":
			m[rn] = v
	return m


## Substitute $tokens in a string against a binding map ($self/$role/etc.).
## Only $[a-z_]+ tokens with a binding are replaced; anything else is left
## verbatim (a literal $ in prose survives).
func _subst_str(text: String, subst: Dictionary) -> String:
	var vm := _route_contour()
	if vm != null:
		# The memoir prose resolution — routed. Every latched stage's `prose` field
		# (journal.<q>.<stage>.prose, IN the soak fingerprint's story section) is
		# Contour-authored when the flag is on. Routed DIRECT: the embed ABI's
		# LAT_STR result kind carries the rule's bare string result across the C
		# boundary (the wrap-in-array _abi adapter is retired).
		_contour_calls += 1
		return String(vm.call_fn("_subst_str", [text, subst]))
	if not text.contains("$"):
		return text
	var re := RegEx.create_from_string("\\$([a-z_]+)")
	var out := text
	# replace longest-first is unnecessary (token boundary is [a-z_]+); walk
	# matches from the end so earlier offsets stay valid.
	var matches := re.search_all(text)
	for i in range(matches.size() - 1, -1, -1):
		var mm := matches[i]
		var name := mm.get_string(1)
		if subst.has(name):
			out = out.substr(0, mm.get_start()) + String(subst[name]) \
				+ out.substr(mm.get_end())
	return out


## Deep-copy a condition with $tokens substituted in every string position
## (keys are predicate names — never substituted; values and nested
## conditions are). Total over the closed language + role predicates.
func _subst_cond(cond: Dictionary, subst: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in cond:
		out[key] = _subst_value(cond[key], subst)
	return out


func _subst_value(v: Variant, subst: Dictionary) -> Variant:
	if v is String:
		return _subst_str(v, subst)
	if v is Dictionary:
		return _subst_cond(v, subst)
	if v is Array:
		var arr: Array = []
		for e in v:
			arr.append(_subst_value(e, subst))
		return arr
	return v


## Evaluate a main-quest condition with the quest's role bindings resolved.
func _eval_cond(q: Dictionary, cond: Dictionary) -> bool:
	return Conditions.eval(_subst_cond(cond, _subst_map(q)), _custom_resolver(q))


# --- role helpers -----------------------------------------------------------

## Declared roles in a deterministic order: pinned (`is`) first — so a queried
## role may reference the authored cast regardless of name — then queried,
## each alphabetical.
func _roles_ordered(q: Dictionary) -> Array[String]:
	var vm := _route_contour()
	if vm != null:
		_contour_calls += 1
		return _ctr_strings(vm.call_fn("_roles_ordered", [q]))
	var pinned: Array[String] = []
	var queried: Array[String] = []
	for rn: String in q.get("roles", {}):
		if (q.roles[rn] as Dictionary).has("is"):
			pinned.append(rn)
		else:
			queried.append(rn)
	pinned.sort()
	queried.sort()
	return pinned + queried


## When a role fills: "on_start" (default) or "on_stage:<id>".
func _role_fill_when(spec: Dictionary) -> String:
	var vm := _route_contour()
	if vm != null:
		_contour_calls += 1
		return String(vm.call_fn("_role_fill_when", [spec]))
	return String(spec.get("fill", "on_start"))


func _role_bound(q: Dictionary, role_name: String) -> bool:
	var v: Variant = WorldState.get_value("journal.%s.role.%s" % [q.id, role_name])
	return v is String and v != ""


## The latched role binding for the desk / harness (q.role reads the same key).
func role_of(quest_id: String, role_name: String) -> String:
	var v: Variant = WorldState.get_value(
		"journal.%s.role.%s" % [quest_id, role_name], "")
	return String(v) if v is String else ""


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
