extends QuestHooks
## SYNTHETIC FIXTURE (DESIGN_QUESTS §6 / rung Q3) — a pure, full-featured
## hook the quest harness drives to prove every lifecycle entry point and
## the `custom` predicate door. Not shipped content: exercised only by
## tests/quests/hook_errand.test.json and hook_replay.test.json.
##
## Purity by construction: it touches the world ONLY through q (WorldState/
## Items) and its ONLY randomness is q.roll — so it replays bit-identically
## through advance_hours catch-up. Every write is namespaced test.probe.<id>.
## so parallel fixtures never collide.
##
## It declares one bound property (threshold: TYPE_FLOAT) so it doubles as
## the subject of the linter's bind-vs-properties() check.


func _p(q: QuestRun) -> String:
	return "test.probe.%s." % q.id


func on_start(q: QuestRun) -> void:
	q.set_value(_p(q) + "started", true)


func on_stage(q: QuestRun, stage: String) -> void:
	q.set_value(_p(q) + "stage." + stage, true)


func on_objective(q: QuestRun, _stage: String, obj: String) -> void:
	q.set_value(_p(q) + "obj." + obj, true)


func on_resolve(q: QuestRun, outcome: String) -> void:
	q.set_value(_p(q) + "resolved", outcome)
	# q.roll — the only sanctioned randomness, seeded by day: replay-stable.
	q.set_value(_p(q) + "dice", q.roll("resolve"))


## The custom predicate door — the game's hook is the only interpreter.
##   "ready"            the world's level meets the RECORD-BOUND threshold
##   "elapsed" [s, n]   n days have passed since stage s latched — a pure,
##                      deterministic time gate that fires INSIDE
##                      advance_hours replay. The anchor stage rides in the
##                      args (never a source literal — the framework
##                      content-id fence forbids naming a data record's id).
func condition(q: QuestRun, name: String, args: Array) -> bool:
	match name:
		"ready":
			return float(q.get_value("test.hook.level", 0.0)) >= float(q.prop("threshold"))
		"elapsed":
			var since := q.reached_day(String(args[0]))
			if since < 0:
				return false
			return int(q.get_value("time.day", 0)) - since >= int(args[1])
		_:
			return false


func custom_keys(name: String) -> Array[String]:
	match name:
		"ready":
			return ["test.hook.level"]
		"elapsed":
			return ["time.day"]
		_:
			return []


func properties() -> Dictionary:
	return {"threshold": TYPE_FLOAT}
