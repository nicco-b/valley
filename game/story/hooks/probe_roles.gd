extends QuestHooks
## SYNTHETIC FIXTURE (DESIGN_QUESTS §4/§6 / rung Q4) — a pure hook the quest
## harness drives to prove the roles door: on_fill (the wit overrides the
## data-ranked pick) and q.role (a hook reads the LATCHED binding). Not
## shipped content: exercised only by tests/quests/role_on_fill.test.json.
##
## Purity by construction: it touches the world ONLY through q, names no
## content id (the framework content-id fence), and every write is
## namespaced test.probe.<id>. so parallel fixtures never collide.


## The wit gets the last word (§6): override the data-ranked fill with the
## LAST candidate — a choice the require/prefer data alone would never make
## (id sort puts it last), so a passing assert can only mean on_fill fired.
func on_fill(_q: QuestRun, role: String, candidates: Array) -> String:
	if role == "hauler" and candidates.size() >= 2:
		return String(candidates[candidates.size() - 1])
	return ""


## Read the latched binding from inside a hook — on_start runs AFTER the
## roles seal (§4), so q.role answers the real id, not "".
func on_start(q: QuestRun) -> void:
	q.set_value("test.probe.%s.hauler" % q.id, q.role("hauler"))
