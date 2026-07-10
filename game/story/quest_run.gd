class_name QuestRun
extends RefCounted
## The Campfire — the handle a QuestHooks fragment receives (DESIGN_QUESTS
## §6). A hook touches the world ONLY through this and WorldState — never
## scene nodes directly (the guardrail that keeps quests headless-testable
## and soak-honest). One QuestRun per quest, built by Story and reused
## across every lifecycle call; it is pure over (WorldState, Items, q).
##
## Determinism law (§6): a hook runs identically in live play, catch-up,
## harness, and soak. Its ONLY sanctioned randomness is q.roll (seeded
## from world.seed + quest id + tag + time.day, so the dice are
## replay-stable); its ONLY clock is the time.* keys. A hook that reaches
## past this surface (bare randf, a wall-clock read, a scene-tree walk)
## breaks the harness's restore-then-replay identity — visibly.
##
## Note on q.set/q.get: §6 spells the WorldState door q.set/q.get; we name
## them set_value/get_value to avoid shadowing Object.set/Object.get (the
## engine calls those natively — overriding them is a footgun). Same door,
## safer spelling.

var id: String

var _story: Node                 # the Story autoload (delegation target)
var _props: Dictionary = {}      # the record-bound properties (CK binding)
var _seed: int = 0               # world.seed, cached at build (roll's base)


func _init(quest_id: String, story: Node, props: Dictionary) -> void:
	id = quest_id
	_story = story
	_props = props
	_seed = int(WorldState.get_value("world.seed", 0))


# --- record-bound properties (CK property binding) --------------------------

## A typed value the record bound to this hook's declared properties() —
## data does the pointing, the fragment stays reusable (§6).
func prop(name: String) -> Variant:
	return _props.get(name, null)


# --- latch readings (all derived from WorldState) ---------------------------

func reached(stage: String) -> bool:
	return _story.reached(id, stage)


func reached_day(stage: String) -> int:
	return _story.reached_day(id, stage)


## The latched role binding (Q4 — until roles land this reads the key and
## returns "" when unfilled; the surface is stable for the rung that fills it).
func role(name: String) -> String:
	var v: Variant = get_value("journal.%s.role.%s" % [id, name], "")
	return String(v) if v is String else ""


# --- the imperative door (what the closed condition language can't say) -----

## Advance a stage by fiat — the escape hatch for reach logic conditions
## cannot express. Monotone still holds: latch never un-happens, and an
## already-reached stage is a no-op.
func latch(stage: String) -> void:
	_story.hook_latch(id, stage)


## The R2 choice seal: write the value AND its flag spelling together.
func seal(choice_key: String, value: Variant) -> void:
	_story.seal(choice_key, value)


## Mint a fact (rides Memory v2's channels when S1/B3 lands; harness-visible).
func mint(kind: String, data: Dictionary = {}) -> void:
	var m := data.duplicate()
	m["kind"] = kind
	_story.hook_mint(id, m)


func request_scene(scene_id: String) -> void:
	_story.hook_request_scene(id, scene_id)


# --- WorldState / Items (the sanctioned world touch) ------------------------

func set_value(key: String, value: Variant) -> void:
	WorldState.set_value(key, value)


func get_value(key: String, default: Variant = null) -> Variant:
	return WorldState.get_value(key, default)


func give(item: String, n: int) -> void:
	Items.add(item, n)


func take(item: String, n: int) -> void:
	Items.add(item, -n)


# --- the ONLY sanctioned randomness (replay-stable dice) --------------------

## Seeded from world.seed + quest id + tag + time.day: a hook's dice are
## the same on every replay of the same day. Draws from its OWN RNG, so it
## perturbs no sim stream. Two rolls of the same tag on the same day match
## (the value is a function of the day, not a consuming stream) — determinism
## the restore-then-replay harness holds us to.
func roll(tag: String) -> float:
	var day := int(WorldState.get_value("time.day", 0))
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%s:%s:%d" % [_seed, id, tag, day])
	return r.randf()


# --- the two-tier law at the hook boundary ----------------------------------

## The embodied body for a role, or NULL. Data-tier agents (and every
## headless run) have no node — presentation flourishes MUST null-check.
## A hook that dereferences this without a guard crashes headless, which is
## exactly how the harness makes an impure presentation-reaching hook visible.
func actor(_role: String) -> Node3D:
	return null
