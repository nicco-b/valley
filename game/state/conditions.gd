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
##       declares index keys; dispatch lands with QuestHooks. Until then
##       custom evaluates false, honestly.

## Predicate spellings the evaluator answers — the linter's closed table.
const PREDICATES: Array[String] = ["flag", "not_flag", "eq", "gte", "lte",
	"item", "item_tag", "season", "time_between", "since", "knows",
	"weather", "custom"]
## Parse-known, not yet live (S1 provenance / S2 sediment).
const RESERVED: Array[String] = ["told", "opinion_band"]
## Composition spellings.
const COMPOSE: Array[String] = ["all", "any", "not"]


static func eval(c: Dictionary) -> bool:
	for key: String in c:
		match key:
			"all":
				for sub: Dictionary in c.all:
					if not eval(sub):
						return false
			"any":
				var passed := false
				for sub: Dictionary in c.any:
					if eval(sub):
						passed = true
						break
				if not passed:
					return false
			"not":
				if eval(c["not"]):
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
				# The hooks door opens at Q3 (QuestHooks.condition). Until a
				# dispatcher exists, an authored custom row fails closed.
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
static func keys_of(c: Dictionary) -> Array[String]:
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
	if value is Dictionary and (value as Dictionary).has("day"):
		return int(value.day)
	if value is int or value is float:
		return int(value)
	return -1


## "Set" for condition purposes: present and not false. Latch values are
## dictionaries (the memoir rides in the save) and still read as flags.
static func _truthy(value: Variant) -> bool:
	return value != null and not (value is bool and value == false)


static func _loose_eq(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


static func _one_of(value: Variant, allowed: Variant) -> bool:
	if allowed is Array:
		return value in (allowed as Array)
	return value == allowed
