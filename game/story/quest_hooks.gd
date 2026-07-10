class_name QuestHooks
extends RefCounted
## The Campfire — base class for per-quest script fragments (DESIGN_QUESTS
## §6, the Papyrus-fragment pattern with our determinism discipline). A
## quest record names one hooks script living in the GAME repo (never in
## Strata, never in data): "hooks": "hooks/<name>.gd", or the bound form
## { "script": ..., "bind": { <property>: <value> } }. The script extends
## this base; every entry point is OPTIONAL (override only what you need).
##
## The laws that keep the door safe (§6):
##   1. Hooks are PURE over (WorldState, Items, q). No scene-tree walking,
##      no engine singletons beyond the sanctioned reads, no bare randf
##      (use q.roll), no wall clock (use time.* keys). The harness makes a
##      violation visible — restore-then-replay stops being bit-identical.
##   2. Hooks run identically in live play, catch-up, harness, and soak —
##      they are called from latch processing, which is changed-driven,
##      which is deterministic. A hook that moves the soak fingerprint is a
##      bug, full stop.
##   3. Strata shows hook NAMES, never edits code. The record names the
##      entry point and binds typed properties; the game owns the text.
##   4. The hook is the LAST resort: mirror -> condition -> effect -> hook.
##
## Property binding (CK's best trick — data does the pointing): a hook
## declares typed needs in properties(); the record binds them; Story
## injects them before any entry point runs; the linter refuses a bind
## that doesn't satisfy properties() (missing, extra, or mistyped). One
## fragment, many quests — reuse by rebinding, never rewriting.

## After start_if latches and (Q4) roles fill, BEFORE the root stage seals.
func on_start(_q: QuestRun) -> void:
	pass


## Override the data-ranked role fill; return an id, or "" to defer (Q4).
func on_fill(_q: QuestRun, _role: String, _candidates: Array) -> String:
	return ""


## The CK fragment — a stage just latched (fires after its effects/mint).
func on_stage(_q: QuestRun, _stage: String) -> void:
	pass


## An objective just latched.
func on_objective(_q: QuestRun, _stage: String, _obj: String) -> void:
	pass


## The deadline passed; runs before the expire stage latches (Q8 wires it).
func on_expire(_q: QuestRun) -> void:
	pass


## A terminal stage latched — `outcome` is that stage's id.
func on_resolve(_q: QuestRun, _outcome: String) -> void:
	pass


## Answer a {"custom": [name, ...args]} predicate row. The game's hook is
## the ONLY interpreter — Story dispatches here, never inventing a semantic.
## Must be pure and deterministic over (WorldState, Items, q).
func condition(_q: QuestRun, _name: String, _args: Array) -> bool:
	return false


## Index keys a custom predicate watches, declared in CODE (beside, or
## instead of, the record's `watch`). Story merges these into the seed
## index so a custom row re-evaluates when its inputs change.
func custom_keys(_name: String) -> Array[String]:
	return []


## Typed needs the RECORD must bind (CK property binding). name -> TYPE_*.
## Bound values arrive as q.prop(name).
func properties() -> Dictionary:
	return {}
