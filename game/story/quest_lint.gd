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
##   roles      $role references resolve to declared roles or built-ins
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
## Deferred with their rungs: role
## query shapes (Q4), dialogue graphs (Q5), scene `where` place records
## (B7), world-flip group ownership (Q10 — the `world` effect is refused
## outright until it exists).

const QUESTS_DIR := "res://data/quests"
const THREADS_DIR := "res://data/threads"
const DIALOGUE_DIR := "res://data/dialogue"
const RECURRENT_PATH := "res://data/story/recurrent.json"
const BUILTIN_ROLES: Array[String] = ["player", "hook", "player_region", "self"]
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
					problems.append("%s.%s: 'world' flips land at Q10 — refused until they exist" % [qid, sid])
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

	# -- roles: every $ref resolves (declared or built-in).
	var declared: Array[String] = []
	for role: String in q.get("roles", {}):
		declared.append(role)
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
