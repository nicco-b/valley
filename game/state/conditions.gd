class_name Conditions
## The Campfire — the one condition vocabulary (Conditions v2,
## DESIGN_QUESTS §5). Dialogue choices, quest stages, objectives, role
## queries, and any future gate all evaluate the same closed language.
##
## The mirror law: conditions read WorldState keys and NOTHING else. A
## sim truth a quest may test MUST be mirrored into WorldState by its
## owning system (Hydrology mirrors water.<id>.flow; conditions read the
## key — no evaluator ever calls a sim). The language is CLOSED: growth
## is new mirrors or hooks, never new evaluator branches (§14 fence).
##
## Composition: {"all": [...]} AND · {"any": [...]} OR · {"not": {...}}
## — and a bare dictionary of predicates still ANDs, so v1 records read
## unchanged.
##
## Predicates (the whole table, forever — see DESIGN_QUESTS §5):
##   {"flag": key} / {"not_flag": key}      — key set / not set. "Set"
##       means present-and-not-false: journal latches are dictionaries
##       ({day, season, prose}) and still read as flags.
##   {"eq"|"gte"|"lte": [key, v]}           — value compare (numeric or ==)
##   {"item": [id, n]}                      — inventory holds at least n
##   {"item_tag": [tag, n]}                 — n things tagged tag (keyword law)
##   {"season": "summer"} or [..]           — sugar over time.season
##   {"time_between": [a, b]}               — solar hours, inclusive, wraps
##   {"since": [key, days]}                 — days since a latch (latches
##       store their day, so this is a read, not a timer)
##   {"knows": [who, fact]}                 — npc.<who>.knows.<fact> (S1)
##   {"weather": "storm"} or [..]           — sugar over weather.state
##   {"told": ...} / {"opinion_band": ...}  — RESERVED until S1/S2 land:
##       linted as reserved, evaluate false (never a silent pass)
##   {"custom": [name, ...], "watch": [k..]} — the hooks door (Q3): watch
##       declares index keys; the named predicate is answered by the
##       quest's QuestHooks.condition (§6). eval() takes an optional
##       `custom` resolver Callable(name, args) -> bool that Story binds to
##       the owning quest's hook; with NO resolver bound (dialogue rows, an
##       unhooked quest) custom fails closed, honestly — never a silent
##       pass, never a Strata-invented semantic (valley's hook is the only
##       interpreter).

## Predicate spellings the evaluator answers — the linter's closed table.
const PREDICATES: Array[String] = ["flag", "not_flag", "eq", "gte", "lte",
	"item", "item_tag", "season", "time_between", "since", "knows",
	"weather", "custom"]
## Parse-known, not yet live (S1 provenance / S2 sediment).
const RESERVED: Array[String] = ["told", "opinion_band"]
## Composition spellings.
const COMPOSE: Array[String] = ["all", "any", "not"]


static func eval(c: Dictionary, custom: Callable = Callable()) -> bool:
	for key: String in c:
		match key:
			"all":
				for sub: Dictionary in c.all:
					if not eval(sub, custom):
						return false
			"any":
				var passed := false
				for sub: Dictionary in c.any:
					if eval(sub, custom):
						passed = true
						break
				if not passed:
					return false
			"not":
				if eval(c["not"], custom):
					return false
			"flag":
				if not _truthy(WorldState.get_value(c.flag)):
					return false
			"not_flag":
				if _truthy(WorldState.get_value(c.not_flag)):
					return false
			"eq":
				if not _loose_eq(WorldState.get_value(c.eq[0]), c.eq[1]):
					return false
			"gte":
				if float(WorldState.get_value(c.gte[0], 0)) < float(c.gte[1]):
					return false
			"lte":
				if float(WorldState.get_value(c.lte[0], 0)) > float(c.lte[1]):
					return false
			"item":
				if Items.count(c.item[0]) < int(c.item[1]):
					return false
			"item_tag":
				if Items.count_tag(c.item_tag[0]) < int(c.item_tag[1]):
					return false
			"season":
				if not _one_of(WorldState.get_value("time.season", ""), c.season):
					return false
			"time_between":
				var h := int(WorldState.get_value("time.hour", -1))
				var a := int(c.time_between[0])
				var b := int(c.time_between[1])
				var inside := (h >= a and h <= b) if a <= b else (h >= a or h <= b)
				if h < 0 or not inside:
					return false
			"since":
				var day := latch_day(WorldState.get_value(c.since[0]))
				if day < 0:
					return false
				if int(WorldState.get_value("time.day", 0)) - day < int(c.since[1]):
					return false
			"knows":
				if not _truthy(WorldState.get_value(
						"npc.%s.knows.%s" % [c.knows[0], c.knows[1]])):
					return false
			"weather":
				if not _one_of(WorldState.get_value("weather.state", ""), c.weather):
					return false
			"custom":
				# The hooks door (Q3): dispatch the named predicate to the
				# quest's QuestHooks.condition via the bound resolver. With no
				# resolver (dialogue, an unhooked quest) it fails closed — the
				# game's hook is the ONLY interpreter (never a Strata semantic).
				# ANDs with any sibling predicate, like every other row.
				var ok := custom.is_valid() and bool(
					custom.call(String(c.custom[0]), (c.custom as Array).slice(1)))
				if not ok:
					return false
			"watch":
				pass  # index keys for the custom beside it — data, not a test
			"told", "opinion_band":
				# Reserved until S1/S2 (provenance, sediment). Fail closed —
				# the linter refuses these in shipped records.
				return false
			_:
				push_error("[conditions] unknown predicate '%s' — the language is closed (§14)" % key)
				return false
	return true


## Mechanical key extraction — the seed of Story's condition index. Total
## because the language is closed: every predicate's watched keys are in
## the table's "reads" column; `custom` contributes its declared watch.
## Routed (docs/PORT_LEDGER.md D3b's recorded follow-up, landed G2): the
## Contour port already carries this leaf (game/state/conditions.ct), just
## never called — same _route()/no-silent-fallback law as latch_day et al.
static func keys_of(c: Dictionary) -> Array[String]:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		var routed: Array[String] = []
		for k in (vm.call_fn("keys_of", [c]) as Array):
			routed.append(String(k))
		return routed
	var keys: Array[String] = []
	for key: String in c:
		match key:
			"all", "any":
				for sub: Dictionary in c[key]:
					keys.append_array(keys_of(sub))
			"not":
				keys.append_array(keys_of(c["not"]))
			"flag":
				keys.append(c.flag)
			"not_flag":
				keys.append(c.not_flag)
			"eq":
				keys.append(c.eq[0])
			"gte":
				keys.append(c.gte[0])
			"lte":
				keys.append(c.lte[0])
			"item", "item_tag":
				keys.append("player.inventory")
			"season":
				keys.append("time.season")
			"time_between":
				keys.append("time.hour")
			"since":
				keys.append(String(c.since[0]))
				keys.append("time.day")
			"knows":
				keys.append("npc.%s.knows.%s" % [c.knows[0], c.knows[1]])
			"weather":
				keys.append("weather.state")
			"custom":
				for k: String in c.get("watch", []):
					keys.append(k)
	return keys


## The custom-predicate names inside a condition (mechanical, like keys_of).
## Story asks the quest's hook for each name's custom_keys() so a hook may
## declare its own index keys in code, beside (or instead of) the record's
## `watch` — the §6 "records may also declare watch" completion. Routed, the
## same D3b follow-up as keys_of above.
static func custom_names(c: Dictionary) -> Array[String]:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		var routed: Array[String] = []
		for k in (vm.call_fn("custom_names", [c]) as Array):
			routed.append(String(k))
		return routed
	var out: Array[String] = []
	for key: String in c:
		match key:
			"all", "any":
				for sub: Dictionary in c[key]:
					out.append_array(custom_names(sub))
			"not":
				out.append_array(custom_names(c["not"]))
			"custom":
				out.append(String(c.custom[0]))
	return out


## Schema check against the closed table — the linter's condition rows.
## Returns human-readable problems ([] = clean). `context` names the row.
static func lint(c: Variant, context: String) -> Array[String]:
	var problems: Array[String] = []
	if not (c is Dictionary):
		problems.append("%s: condition must be a dictionary" % context)
		return problems
	var dict := c as Dictionary
	for key: String in dict:
		if key in RESERVED:
			problems.append("%s: '%s' is reserved until S1/S2 lands" % [context, key])
		elif key == "custom":
			if not (dict.get("watch") is Array) or (dict.watch as Array).is_empty():
				problems.append("%s: 'custom' requires a non-empty 'watch' key list beside it" % context)
		elif key == "watch":
			if not dict.has("custom"):
				problems.append("%s: 'watch' only rides beside 'custom'" % context)
		elif key in COMPOSE:
			if key == "not":
				problems.append_array(lint(dict[key], context + ".not"))
			elif dict[key] is Array:
				for i in (dict[key] as Array).size():
					problems.append_array(lint(dict[key][i], "%s.%s[%d]" % [context, key, i]))
			else:
				problems.append("%s: '%s' takes an array of conditions" % [context, key])
		elif not (key in PREDICATES):
			problems.append("%s: unknown predicate '%s' — the language is closed (§14)" % [context, key])
		elif key in ["eq", "gte", "lte", "item", "item_tag", "since",
				"knows", "time_between"]:
			if not (dict[key] is Array) or (dict[key] as Array).size() < 2:
				problems.append("%s: '%s' takes [%s]" % [context, key,
					"a, b" if key == "time_between" else "key, value"])
	return problems


## The day sealed into a latch value: latches store {day, ...}; a bare
## int is accepted (a mirror that stores days directly). -1 = no latch.
static func latch_day(value: Variant) -> int:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return int(vm.call_fn("latch_day", [value]))
	if value is Dictionary and (value as Dictionary).has("day"):
		return int(value.day)
	if value is int or value is float:
		return int(value)
	return -1


## "Set" for condition purposes: present and not false. Latch values are
## dictionaries (the memoir rides in the save) and still read as flags.
static func _truthy(value: Variant) -> bool:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return bool(vm.call_fn("_truthy", [value]))
	return value != null and not (value is bool and value == false)


static func _loose_eq(a: Variant, b: Variant) -> bool:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return bool(vm.call_fn("_loose_eq", [a, b]))
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


static func _one_of(value: Variant, allowed: Variant) -> bool:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return bool(vm.call_fn("_one_of", [value, allowed]))
	if allowed is Array:
		return value in (allowed as Array)
	return value == allowed


# --- Contour routing (PLAN_ENGINE E2: the first Contour system under the soak) --
## The four pure leaf helpers above (latch_day/_truthy/_loose_eq/_one_of) are the
## honestly-PURE statics of the Campfire language — certified bit-identical to
## their Lattice twin by datum's Plumb harness (conditions_*.jsonl corpora, over
## the byte-identical vendored conditions.gd). When STRATA_CONTOUR=1 — a boot-time
## sim flag, read once, DevMode-independent, default OFF — these call sites route
## through the native Contour VM (game/state/conditions.ct via game/sim/contour.gd)
## instead of the GDScript below. Flag OFF is byte-identical GDScript.
##
## NO SILENT FALLBACK (the honesty law): flag ON with the kernel absent (not
## macOS / no dylib) or a module that will not compile is a LOUD refusal
## (push_error, mode -1), never a quiet GDScript pass — so a soak that believes
## it exercised the VM cannot secretly be running the twin. The routed helpers
## carry a call counter (contour_status) so a scene test can prove the VM
## actually answered, flag-on.
const _CONTOUR_MODULE := "res://game/state/conditions.ct"

## 0 unresolved · 1 off (flag unset) · 2 engaged (VM live) · -1 refused (flag
## set but kernel/module unavailable — loud, not silent).
static var _contour_mode := 0
static var _contour_vm: Contour = null
static var _contour_calls := 0   # VM-answered leaf calls (the engaged-path probe)

## The live VM when routing is engaged, else null (flag off, or refused). Resolves
## once at first touch (boot); pure — no WorldState side effects, so flag-off is
## byte-identical to the un-routed code.
static func _route() -> Contour:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour_vm


static func _contour_resolve() -> void:
	var verdict := Contour.decide("conditions")
	if verdict != Contour.ROUTE_ENGAGE:
		_contour_mode = verdict   # ROUTE_FALLBACK (GDScript twin) or ROUTE_REFUSE (loud, mode -1)
		return
	# Routing engaged — compile the module (a compile failure still refuses loudly).
	var vm := Contour.new()
	var err := vm.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[conditions] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour_vm = vm
	_contour_mode = 2


## Routing introspection for the scene test (proves the VM answered, not a silent
## fallback): the resolved mode, whether it engaged, and the answered-call count.
static func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}
