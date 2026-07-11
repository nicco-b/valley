class_name QuestLint
## The Campfire — the quest linter (DESIGN_QUESTS §10): the authored-
## spine truths Records.validate can't see, checked at commit time in
## test.sh (via tests/quest_harness.tscn), not discovered in bug
## reports. Static and side-effect free: lint_all() returns problems.
##
## Rules carried (Q1/Q2 scope):
##   graph      rooted (≥1 start), acyclic, every stage reachable from a
##              root, stage ids unique
##   forward    every non-terminal stage has a way forward (≥1 child
##              edge or a quest-level expire)
##   no-wedge   the structural layer: from EVERY stage some terminal
##              stays reachable (an expire counts — it closes forward)
##   required   `required: true` stages lie on every root→terminal path
##              (the skip-proof; an expire edge is a path and is named
##              when it is the leak)
##   memoir     terminal stages carry journal prose; story-tier
##              terminals mint (craft rule 5, enforced)
##   language   every condition parses against the closed table
##              (Conditions.lint): unknown predicates, reserved rows
##              (told/opinion_band), custom without watch
##   tiers      repeatable only on errand tier, cooldown_days ≥ 1
##   endings    sibling terminals disjoint on the same sealed key
##              (best-effort: two terminals gating on the identical
##              choice.* flag can both latch — refused)
##   roles      $role references resolve to declared roles or built-ins;
##              each declared role is well shaped (§4): kind enumerated,
##              pinned `is` a string, require/prefer arrays of role-query
##              conditions (shared vocabulary + tagged/near), fill on_start
##              or on_stage:<existing>, fallback hold|abandon
##   targets    stage scene ids exist; scene dialogue records exist;
##              hooks scripts exist; thread `after` targets exist
##   hooks      the named script extends QuestHooks and its `bind`
##              satisfies properties() — every declared prop bound, none
##              extra, each the right type (CK property binding, §6)
##   spine      on spine: true threads, chapters' paths-to-terminal gate
##              only on player-writable keys or the recurrent list
##              (data/story/recurrent.json) — start_if is exempt (one-
##              shot sim events may OPEN spine content, never bar its
##              path). §3's spine-gating rule, the checkable part.
##
## World flips (Q10, §3): the `world` stage effect ({enable/disable} group
## lists) is validated for shape here, and a cross-quest pass warns when one
## group is flipped the same direction by two quests (contested-flip — one
## owning quest per direction, the guardrail against two storylines fighting
## over the same bridge).
##
## Deferred with their rungs: role
## query shapes (Q4), dialogue graphs (Q5), scene `where` place records
## (B7).

const QUESTS_DIR := "res://data/quests"
const THREADS_DIR := "res://data/threads"
const DIALOGUE_DIR := "res://data/dialogue"
const RECURRENT_PATH := "res://data/story/recurrent.json"
const BUILTIN_ROLES: Array[String] = ["player", "hook", "player_region", "self"]
## Role kinds the filler queries (§4).
const ROLE_KINDS: Array[String] = ["npc", "wildlife", "place", "item"]
## Key namespaces the player can reach (actions, seals, scenes, elapsed
## time, items) — the non-recurrent half of the spine-gating rule.
const PLAYER_WRITABLE: Array[String] = ["player.", "journal.", "choice.",
	"scene.", "npc.player.", "time.day"]
const EFFECT_KINDS: Array[String] = ["set", "inc", "give", "take", "latch", "mint"]


## Lint every quest and thread record. Returns problems ([] = clean).
static func lint_all() -> Array[String]:
	var problems: Array[String] = []
	var quests: Dictionary = Records.load_dir(QUESTS_DIR, {
		"format": TYPE_FLOAT, "id": TYPE_STRING, "title": TYPE_STRING,
		"tier": TYPE_STRING, "stages": TYPE_ARRAY})
	for key: String in quests:
		problems.append_array(lint_quest(quests[key]))
	# World flips (Q10, §3): the contested-flip guardrail is cross-quest — one
	# owning quest per group per direction — so it runs once over the whole set.
	problems.append_array(_lint_contested_flips(quests))
	var threads: Dictionary = Records.load_dir(THREADS_DIR, {
		"format": TYPE_FLOAT, "id": TYPE_STRING, "chapters": TYPE_ARRAY})
	var by_id: Dictionary = {}
	for key: String in quests:
		by_id[quests[key].id] = quests[key]
	for key: String in threads:
		problems.append_array(lint_thread(threads[key], by_id, recurrent_keys()))
	return problems


## The keys whose states the sim guarantees return — owned by the game
## (data/story/recurrent.json), read by the spine lint.
static func recurrent_keys() -> Array[String]:
	var rec: Variant = Records.load_json(RECURRENT_PATH)
	var out: Array[String] = []
	if rec is Dictionary:
		for k: String in (rec as Dictionary).get("keys", []):
			out.append(k)
	return out


static func lint_quest(q: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var qid: String = q.id
	if int(q.format) != 2:
		problems.append("%s: format must be 2" % qid)
	if not (q.tier in ["errand", "story", "arc"]):
		problems.append("%s: tier must be errand|story|arc" % qid)
	if q.has("repeatable"):
		if q.tier != "errand":
			problems.append("%s: repeatable is errand-tier only (stories never re-arm, §7)" % qid)
		if int((q.repeatable as Dictionary).get("cooldown_days", 0)) < 1:
			problems.append("%s: repeatable.cooldown_days must be ≥ 1" % qid)

	# -- stages: ids, roots, conditions, prose, effects.
	var ids: Array[String] = []
	var roots: Array[String] = []
	var terminals: Array[String] = []
	for stage: Dictionary in q.stages:
		if not (stage.get("id") is String):
			problems.append("%s: a stage is missing its id" % qid)
			continue
		var sid: String = stage.id
		if ids.has(sid):
			problems.append("%s: duplicate stage id '%s'" % [qid, sid])
		ids.append(sid)
		if stage.get("start", false):
			roots.append(sid)
		if stage.get("terminal", false):
			terminals.append(sid)
			if String(stage.get("journal", "")).is_empty():
				problems.append("%s.%s: terminal stage without journal prose" % [qid, sid])
			if q.tier == "story" and not _mints(stage):
				problems.append("%s.%s: a Story's terminal stages must mint (craft rule 5)" % [qid, sid])
		if stage.has("advance_when"):
			problems.append_array(Conditions.lint(stage.advance_when,
				"%s.%s.advance_when" % [qid, sid]))
		for obj: Dictionary in stage.get("objectives", []):
			if not (obj.get("id") is String) or not (obj.get("text") is String):
				problems.append("%s.%s: objective needs id and text" % [qid, sid])
			problems.append_array(Conditions.lint(obj.get("done_if", {}),
				"%s.%s.%s.done_if" % [qid, sid, obj.get("id", "?")]))
		for effect: Dictionary in stage.get("effects", []):
			for kind: String in effect:
				if kind == "world":
					problems.append_array(_lint_world_effect(qid, sid, effect.world))
				elif not (kind in EFFECT_KINDS):
					problems.append("%s.%s: effect '%s' is not in the closed set" % [qid, sid, kind])
		for pid: String in stage.get("after", []):
			if not _has_stage(q, pid):
				problems.append("%s.%s: after names unknown stage '%s'" % [qid, sid, pid])
	if roots.is_empty():
		problems.append("%s: no stage marked start" % qid)
	if terminals.is_empty():
		problems.append("%s: no terminal stage — the quest can never resolve" % qid)
	problems.append_array(Conditions.lint(q.get("start_if", {}), "%s.start_if" % qid))

	# -- expire: target exists and is terminal.
	var has_expire: bool = q.has("expire")
	if has_expire:
		var to := String((q.expire as Dictionary).get("to", ""))
		if not _has_stage(q, to):
			problems.append("%s: expire.to names unknown stage '%s'" % [qid, to])
		elif not _stage_of(q, to).get("terminal", false):
			problems.append("%s: expire.to '%s' must be a terminal stage" % [qid, to])

	# -- the graph: children from the implicit/explicit parent rule.
	var children := _children(q)
	if _cyclic(ids, children):
		problems.append("%s: stage graph has a cycle (after edges must point forward)" % qid)
		return problems  # reachability walks below would spin

	var from_roots := _reachable(roots, children)
	for sid in ids:
		if not from_roots.has(sid):
			problems.append("%s.%s: unreachable from any root" % [qid, sid])
	for stage: Dictionary in q.stages:
		var sid: String = stage.id
		if stage.get("terminal", false):
			continue
		if (children.get(sid, []) as Array).is_empty() and not has_expire:
			problems.append("%s.%s: no way forward (no child edge, no expire)" % [qid, sid])
		if not _terminal_reachable(sid, children, q, has_expire):
			problems.append("%s.%s: WEDGE — no terminal reachable from here (§10 no-wedge law)" % [qid, sid])

	# -- required: on every root→terminal path (the skip-proof).
	for stage: Dictionary in q.stages:
		if not stage.get("required", false):
			continue
		var sid: String = stage.id
		var skipped := _reachable_skipping(roots, children, sid)
		for tid in terminals:
			if tid != sid and skipped.has(tid):
				problems.append("%s: required stage '%s' is skippable (a path reaches '%s' around it)"
						% [qid, sid, tid])
		if has_expire and String((q.expire as Dictionary).get("to", "")) != sid:
			problems.append("%s: required stage '%s' is skippable via expire — prefer gates that wait (§7)"
					% [qid, sid])

	# -- sibling terminals: disjoint on the same sealed key (best-effort).
	for i in terminals.size():
		for j in range(i + 1, terminals.size()):
			var a := _choice_flags(_stage_of(q, terminals[i]).get("advance_when", {}))
			var b := _choice_flags(_stage_of(q, terminals[j]).get("advance_when", {}))
			for key: String in a:
				if b.has(key):
					problems.append("%s: terminals '%s' and '%s' both gate on '%s' — endings must be disjoint"
							% [qid, terminals[i], terminals[j], key])

	# -- roles (§4): every $ref resolves, and every declared role is well
	# shaped — kind valid, is/require/prefer/fill/fallback checked so a
	# malformed role bounces at commit, not at fill time.
	var declared: Array[String] = []
	for role: String in q.get("roles", {}):
		declared.append(role)
		problems.append_array(_lint_role(q, role, q.roles[role], ids))
	for ref in _role_refs(q):
		if not declared.has(ref) and not BUILTIN_ROLES.has(ref):
			problems.append("%s: $%s is not a declared role" % [qid, ref])

	# -- scenes: stage scene ids exist; dialogue records exist on disk.
	var scene_ids: Array[String] = []
	for scene: Dictionary in q.get("scenes", []):
		scene_ids.append(String(scene.get("id", "")))
		var dialogue := String(scene.get("dialogue", ""))
		if not dialogue.is_empty() and not FileAccess.file_exists(
				DIALOGUE_DIR + "/" + dialogue + ".json"):
			problems.append("%s: scene '%s' names missing dialogue '%s'" % [qid, scene.get("id"), dialogue])
	for stage: Dictionary in q.stages:
		for sid: String in stage.get("scenes", []):
			if not scene_ids.has(sid):
				problems.append("%s.%s: names undeclared scene '%s'" % [qid, stage.id, sid])

	# -- hooks (§6): the named script exists, extends QuestHooks, and its
	# bind satisfies the script's properties() (CK property binding checked
	# at commit, not discovered at runtime — missing, extra, or mistyped).
	if q.has("hooks"):
		var path := String(q.hooks) if q.hooks is String \
				else String((q.hooks as Dictionary).get("script", ""))
		var full := "res://game/story/" + path
		if not FileAccess.file_exists(full):
			problems.append("%s: hooks script 'game/story/%s' does not exist" % [qid, path])
		else:
			problems.append_array(_lint_hook_bind(q, full))
	return problems


## The property-binding check (§6): load the hooks script, read its
## properties() (name -> TYPE_*), and hold the record's `bind` to it — every
## declared property bound, none extra, each the right type (JSON ints stand
## in for floats). Static and headless: the base touches no autoload on new().
static func _lint_hook_bind(q: Dictionary, full: String) -> Array[String]:
	var problems: Array[String] = []
	var qid: String = q.id
	var script: Variant = load(full)
	if not (script is GDScript):
		problems.append("%s: hooks script '%s' failed to load" % [qid, full])
		return problems
	var inst: Variant = (script as GDScript).new()
	if not (inst is QuestHooks):
		problems.append("%s: hooks script '%s' does not extend QuestHooks" % [qid, full])
		return problems
	var props: Dictionary = inst.properties()
	var bind: Dictionary = (q.hooks as Dictionary).get("bind", {}) if q.hooks is Dictionary else {}
	for pname: String in props:
		if not bind.has(pname):
			problems.append("%s: hooks bind is missing property '%s' (properties() declares it)" % [qid, pname])
		elif not _type_ok(bind[pname], int(props[pname])):
			problems.append("%s: hooks bind '%s' is mistyped (properties() wants %s)"
					% [qid, pname, type_string(int(props[pname]))])
	for bname: String in bind:
		if not props.has(bname):
			problems.append("%s: hooks bind names '%s', not a declared property()" % [qid, bname])
	return problems


static func _type_ok(value: Variant, t: int) -> bool:
	match t:
		TYPE_STRING: return value is String
		TYPE_FLOAT: return (value is float) or (value is int)  # JSON ints are floats
		TYPE_INT: return value is int
		TYPE_BOOL: return value is bool
		TYPE_ARRAY: return value is Array
		TYPE_DICTIONARY: return value is Dictionary
		_: return true


## Thread lint (§3): chapters name real quests/stages; spine threads
## obey the spine-gating rule over data/story/recurrent.json.
static func lint_thread(t: Dictionary, quests: Dictionary,
		recurrent: Array[String]) -> Array[String]:
	var problems: Array[String] = []
	var tid: String = t.id
	for chapter: Dictionary in t.chapters:
		var qid := String(chapter.get("quest", ""))
		if not quests.has(qid):
			problems.append("%s: chapter names unknown quest '%s'" % [tid, qid])
			continue
		var after := String(chapter.get("after", ""))
		if not after.is_empty():
			var target := after.split(":")
			if not quests.has(target[0]) or (target.size() > 1 and target[1] != "*"
					and not _has_stage(quests[target[0]], target[1])):
				problems.append("%s: after '%s' names an unknown quest or stage" % [tid, after])
		if t.get("spine", false):
			problems.append_array(_lint_spine_gates(quests[qid], recurrent, tid))
	return problems


## The checkable part of the spine-gating rule: every key on a spine
## chapter's path to terminal (advance_when / done_if / gates that
## close) is player-writable or recurrent. start_if is exempt — sim
## one-shots may OPEN spine content, never bar its path.
static func _lint_spine_gates(q: Dictionary, recurrent: Array[String],
		tid: String) -> Array[String]:
	var problems: Array[String] = []
	for stage: Dictionary in q.stages:
		var keys: Array[String] = Conditions.keys_of(stage.get("advance_when", {}))
		for obj: Dictionary in stage.get("objectives", []):
			keys.append_array(Conditions.keys_of(obj.get("done_if", {})))
		for key in keys:
			if not _spine_ok(key, recurrent):
				problems.append("%s: spine quest '%s' stage '%s' gates on '%s' — not player-writable or recurrent (§3)"
						% [tid, q.id, stage.id, key])
	return problems


static func _spine_ok(key: String, recurrent: Array[String]) -> bool:
	if recurrent.has(key):
		return true
	for prefix in PLAYER_WRITABLE:
		if key == prefix or key.begins_with(prefix):
			return true
	return false


## One role's shape (§4). kind is required and enumerated; a pinned `is`
## must be a string; require/prefer are arrays of role-query conditions
## (the shared vocabulary + the role-only `tagged`/`near`); fill is on_start
## or on_stage:<existing stage>; fallback is hold or abandon.
static func _lint_role(q: Dictionary, name: String, spec: Variant,
		stage_ids: Array[String]) -> Array[String]:
	var problems: Array[String] = []
	var qid: String = q.id
	if not (spec is Dictionary):
		problems.append("%s: role '%s' must be a dictionary" % [qid, name])
		return problems
	var s: Dictionary = spec
	if not (String(s.get("kind", "")) in ROLE_KINDS):
		problems.append("%s: role '%s' kind must be npc|wildlife|place|item" % [qid, name])
	if s.has("is") and not (s["is"] is String):
		problems.append("%s: role '%s' pinned 'is' must be a string id" % [qid, name])
	for field: String in ["require", "prefer"]:
		if not s.has(field):
			continue
		if not (s[field] is Array):
			problems.append("%s: role '%s' %s must be an array of conditions" % [qid, name, field])
			continue
		for i in (s[field] as Array).size():
			problems.append_array(_lint_role_cond(s[field][i],
				"%s: role '%s' %s[%d]" % [qid, name, field, i]))
	if s.has("fill"):
		var fill := String(s.fill)
		if fill != "on_start" and not fill.begins_with("on_stage:"):
			problems.append("%s: role '%s' fill must be on_start or on_stage:<id>" % [qid, name])
		elif fill.begins_with("on_stage:"):
			var sid := fill.trim_prefix("on_stage:")
			if not stage_ids.has(sid):
				problems.append("%s: role '%s' fills on unknown stage '%s'" % [qid, name, sid])
	if s.has("fallback") and not (String(s.fallback) in ["hold", "abandon"]):
		problems.append("%s: role '%s' fallback must be hold or abandon" % [qid, name])
	return problems


## A role-query condition: the shared closed language PLUS the role-only
## predicates `tagged`/`near` (which conditions never test — §5). Delegates
## every standard row to Conditions.lint so unknown/reserved/malformed rows
## are caught with the game's own words.
static func _lint_role_cond(c: Variant, context: String) -> Array[String]:
	var problems: Array[String] = []
	if not (c is Dictionary):
		problems.append("%s: condition must be a dictionary" % context)
		return problems
	var dict := c as Dictionary
	for key: String in dict:
		if key in ["tagged", "near"]:
			if not (dict[key] is Array) or (dict[key] as Array).size() < 2:
				problems.append("%s: '%s' takes [$self, value]" % [context, key])
		elif key in ["all", "any"]:
			if dict[key] is Array:
				for i in (dict[key] as Array).size():
					problems.append_array(_lint_role_cond(dict[key][i], "%s.%s[%d]" % [context, key, i]))
			else:
				problems.append("%s: '%s' takes an array of conditions" % [context, key])
		elif key == "not":
			problems.append_array(_lint_role_cond(dict[key], context + ".not"))
		else:
			problems.append_array(Conditions.lint({key: dict[key]}, context))
	return problems


# --- graph helpers ----------------------------------------------------------

## children[sid] -> Array[String], inverted from the §3 parent rule:
## explicit `after`, else every earlier non-terminal stage.
static func _children(q: Dictionary) -> Dictionary:
	var children: Dictionary = {}
	for stage: Dictionary in q.stages:
		children[String(stage.id)] = []
	for stage: Dictionary in q.stages:
		for pid: String in _parents(q, stage):
			if children.has(pid):
				(children[pid] as Array).append(String(stage.id))
	return children


static func _parents(q: Dictionary, stage: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if stage.has("after"):
		for pid: String in stage.after:
			out.append(pid)
		return out
	if stage.get("start", false):
		return out
	for other: Dictionary in q.stages:
		if other.id == stage.id:
			break
		if not other.get("terminal", false):
			out.append(String(other.id))
	return out


static func _reachable(roots: Array[String], children: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var stack := roots.duplicate()
	while not stack.is_empty():
		var sid: String = stack.pop_back()
		if seen.has(sid):
			continue
		seen[sid] = true
		for child: String in children.get(sid, []):
			stack.append(child)
	return seen


static func _reachable_skipping(roots: Array[String], children: Dictionary,
		skip: String) -> Dictionary:
	var seen: Dictionary = {}
	var stack: Array[String] = []
	for r in roots:
		if r != skip:
			stack.append(r)
	while not stack.is_empty():
		var sid: String = stack.pop_back()
		if seen.has(sid) or sid == skip:
			continue
		seen[sid] = true
		for child: String in children.get(sid, []):
			stack.append(child)
	return seen


static func _terminal_reachable(from: String, children: Dictionary,
		q: Dictionary, has_expire: bool) -> bool:
	if has_expire:
		return true  # the expiry terminal closes every open path forward
	var seen := _reachable([from], children)
	for stage: Dictionary in q.stages:
		if stage.get("terminal", false) and seen.has(String(stage.id)):
			return true
	return false


static func _cyclic(ids: Array[String], children: Dictionary) -> bool:
	var state: Dictionary = {}  # 1 visiting, 2 done
	for sid in ids:
		if _cycle_walk(sid, children, state):
			return true
	return false


static func _cycle_walk(sid: String, children: Dictionary, state: Dictionary) -> bool:
	if int(state.get(sid, 0)) == 1:
		return true
	if int(state.get(sid, 0)) == 2:
		return false
	state[sid] = 1
	for child: String in children.get(sid, []):
		if _cycle_walk(child, children, state):
			return true
	state[sid] = 2
	return false


# --- record helpers ---------------------------------------------------------

static func _has_stage(q: Dictionary, sid: String) -> bool:
	return not _stage_of(q, sid).is_empty()


static func _stage_of(q: Dictionary, sid: String) -> Dictionary:
	for stage: Dictionary in q.stages:
		if stage.id == sid:
			return stage
	return {}


static func _mints(stage: Dictionary) -> bool:
	if stage.has("mint"):
		return true
	for effect: Dictionary in stage.get("effects", []):
		if effect.has("mint"):
			return true
	return false


## Q10 world flip grammar (§3): a `world` effect is a dictionary of `enable`
## and/or `disable`, each an array of non-empty group-id strings. Anything
## else is refused — the effect names a set of placements, nothing more.
const FLIP_DIRS: Array[String] = ["enable", "disable"]

static func _lint_world_effect(qid: String, sid: String, flip: Variant) -> Array[String]:
	var problems: Array[String] = []
	if not (flip is Dictionary):
		problems.append("%s.%s: 'world' flip must be a dictionary of enable/disable group lists" % [qid, sid])
		return problems
	var d := flip as Dictionary
	var groups := 0
	for dir: String in d:
		if not (dir in FLIP_DIRS):
			problems.append("%s.%s: 'world' flip key '%s' — only 'enable'/'disable'" % [qid, sid, dir])
			continue
		if not (d[dir] is Array):
			problems.append("%s.%s: 'world' %s must be an array of group ids" % [qid, sid, dir])
			continue
		for gid: Variant in d[dir]:
			if not (gid is String) or (gid as String).is_empty():
				problems.append("%s.%s: 'world' %s group id must be a non-empty string" % [qid, sid, dir])
			else:
				groups += 1
	if groups == 0 and problems.is_empty():
		problems.append("%s.%s: 'world' flip names no groups (a no-op effect)" % [qid, sid])
	return problems


## The contested-flip guardrail (§3): one group, one owning quest per
## direction. Two different quests enabling (or two disabling) the same group
## are fighting over the world's furniture — warned, deterministically, in
## group-then-direction order. Multiple stages of ONE quest flipping a group
## is fine — the quest owns it.
static func _lint_contested_flips(quests: Dictionary) -> Array[String]:
	var owners: Dictionary = {}  # gid -> {"enable": [qids], "disable": [qids]}
	var qkeys := quests.keys()
	qkeys.sort()
	for key: String in qkeys:
		var q: Dictionary = quests[key]
		var qid := String(q.get("id", ""))
		for stage: Dictionary in q.get("stages", []):
			for effect: Dictionary in stage.get("effects", []):
				if not effect.has("world") or not (effect.world is Dictionary):
					continue
				var flip: Dictionary = effect.world
				for dir: String in FLIP_DIRS:
					for gid: Variant in flip.get(dir, []):
						if not (gid is String) or (gid as String).is_empty():
							continue
						var slot: Dictionary = owners.get(gid,
							{"enable": [] as Array[String], "disable": [] as Array[String]})
						if not (slot[dir] as Array).has(qid):
							(slot[dir] as Array).append(qid)
						owners[gid] = slot
	var problems: Array[String] = []
	var gids := owners.keys()
	gids.sort()
	for gid: String in gids:
		for dir: String in FLIP_DIRS:
			var qs: Array = owners[gid][dir]
			if qs.size() > 1:
				problems.append("world flip: group '%s' is %sd by %d quests (%s) — one owning quest per direction (§3 contested-flip)"
					% [gid, dir, qs.size(), ", ".join(qs)])
	return problems


## flag-form choice keys inside a condition (choice.<seal>.<value>) —
## the sibling-terminal disjointness probe.
static func _choice_flags(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in Conditions.keys_of(c):
		if key.begins_with("choice."):
			out.append(key)
	return out


## Every $name reference in conditions, scenes, and prose.
static func _role_refs(q: Dictionary) -> Array[String]:
	var refs: Array[String] = []
	var re := RegEx.create_from_string("\\$([a-z_]+)")
	for m in re.search_all(JSON.stringify(q)):
		var name := m.get_string(1)
		if not refs.has(name):
			refs.append(name)
	return refs
