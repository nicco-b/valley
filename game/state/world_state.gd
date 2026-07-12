extends Node
## WorldState (autoload): the single store for everything the world
## remembers about itself — flags, counters, values. The consequence
## backbone: dialogue conditions, NPC opinions, quest state, and the
## simulation all read and write here, nowhere else.
##
## Keys are dot-namespaced strings, lowercase:
##   npc.wanderer.met = true
##   npc.wanderer.encounters = 3
##   valley.bridge.repaired = true
##   time.day = 12
## Values are JSON-compatible (bool/int/float/String/Array/Dictionary).
## Everything here is saved and restored verbatim by SaveGame.

signal changed(key: String, value: Variant)

var _state: Dictionary = {}

## THE PER-KEY MIRROR FLIP (substrate Rung 3 — docs/SUBSTRATE.md §2a). When
## STRATA_CONTOUR_MIRROR=0 the store STOPS keeping a second copy of a SINGLETON
## held-owned key that is MIRROR_ELIGIBLE: get_value/snapshot of it READ THROUGH to
## the owning bridge's held world (the sim-tier truth), and set_value of it is a
## no-op (the held world is authoritative — mutated only by the tick, or by the
## forcing door's write-through). Default UNCHANGED (unset / any value but "0" ==
## mirror-on, byte-identical to before). The flip only BITES once a SINGLETON bridge
## has registered its eligible keys AND its held world is live — under the copy path
## (no held world) held_read returns {} and every key falls to the plain _state
## fast path, so STRATA_CONTOUR_MIRROR=0 is inert without STRATA_CONTOUR_HELD=1.
static var _mirror_flip := OS.get_environment("STRATA_CONTOUR_MIRROR") == "0"

## Read-through provider registry: an eligible held-owned key -> the SINGLETON
## ContourBridge that owns it (registered at engage via bridge.register_read_through).
## Empty off the held path; a key never registered stays a plain mirror key.
var _read_through: Dictionary = {}


## Is the per-key mirror flip armed (STRATA_CONTOUR_MIRROR=0)? The bridge queries
## this to route an eligible moved write to notify_changed instead of a mirror copy.
func mirror_flipped() -> bool:
	return _mirror_flip


## Register `provider` (a SINGLETON ContourBridge) as the read-through source for
## `key` — the mirror-flip wiring (docs/SUBSTRATE.md §2a). Idempotent.
func register_read_through(key: String, provider: Object) -> void:
	_read_through[key] = provider


## The live held-world value for `key` when the flip is armed, `key` has a provider,
## and that provider's held world is live and owns it: returns [true, value]. Else
## [false, null] — the caller falls to the plain _state store. held_read returns a
## {key: value} dict when held (a held `null` crosses as {key: null}, non-empty),
## an EMPTY {} when not — so a not-yet-created / destroyed held world reads as "fall
## to the mirror", exactly the lazy-create / post-restore window the mirror covers.
func _read_through_value(key: String) -> Array:
	if not _mirror_flip:
		return [false, null]
	var provider: Variant = _read_through.get(key)
	if provider == null:
		return [false, null]
	var got: Dictionary = provider.held_read(key)
	if got.is_empty():
		return [false, null]
	return [true, got[key]]


## Introspection for the soak/gate proofs (docs/SUBSTRATE.md §2a): how many
## read-through providers are registered, and how many ELIGIBLE keys still keep a
## raw `_state` copy while their held world is live (a LEAK — the retirement means
## zero). `mirror_copies_of_eligible() == 0` under the flip is the proof the copy
## was actually retired, not merely shadowed.
func read_through_count() -> int:
	return _read_through.size()


func mirror_copies_of_eligible() -> int:
	var leaked := 0
	for key: String in _read_through:
		if _state.has(key) and _read_through_value(key)[0]:
			leaked += 1
	return leaked


func set_value(key: String, value: Variant) -> void:
	# THE MIRROR FLIP (docs/SUBSTRATE.md §2a): an eligible held-owned key whose held
	# world is LIVE is authoritative in the held world — the store keeps no second
	# copy, so a set_value of it is a no-op here. (The tick's own apply routes
	# through notify_changed, not this; the forcing door routes through force_value's
	# write-through. A twin's redundant tail write of a value it just read back from
	# the held world lands HERE and is correctly dropped.) Before the held world is
	# live (the create-seed window, kernel absent) the read-through is empty and the
	# write falls through normally — that seed is what world_create reads.
	if _mirror_flip and _read_through.has(key) and _read_through_value(key)[0]:
		# Truly RETIRE the copy: a stale _state value from the create-seed window (or
		# a restore that overlaid it) would otherwise linger, shadowed but present.
		if _state.has(key):
			_state.erase(key)
		return
	# Same-type compare only: `==` across mismatched Variant types (String vs
	# Vector2) is a RUNTIME ERROR that aborts this function BEFORE the store —
	# the new value never lands and the stale one wedges in forever. Seen live:
	# a pre-contract save's stringified vector met a typed rewrite and froze
	# every agent mind. A type CHANGE is always a real change; store it.
	var prior: Variant = _state.get(key)
	if typeof(prior) == typeof(value) and prior == value:
		return
	_state[key] = value
	changed.emit(key, value)


## Emit the `changed` signal for a key WITHOUT touching the store — the mirror
## flip's post-tick diff emission (docs/SUBSTRATE.md §2a design point 2). The
## SINGLETON bridge calls this for each MOVED eligible write from its commit point,
## so a presentation/story subscriber hears the coalesced post-tick diff even though
## the value now lives only in the held world. No same-value guard: the bridge
## passes only keys the write-diff reports moved.
func notify_changed(key: String, value: Variant) -> void:
	changed.emit(key, value)


## Force an arbitrary key (the B12 forcing door, `state set` — docs/SUBSTRATE.md §2a
## design point 5). For an eligible held-owned key with a live held world the value
## must be WRITTEN THROUGH to the held world (the sim-tier truth) so the next tick
## resumes from the forced value instead of clobbering it with held truth; then emit
## `changed` for the subscriber. For any other key it is a plain set_value.
func force_value(key: String, value: Variant) -> void:
	if _mirror_flip and _read_through.has(key):
		var provider: Object = _read_through[key]
		if provider.held_write(key, value):
			changed.emit(key, value)
			return
	set_value(key, value)


func get_value(key: String, default: Variant = null) -> Variant:
	var rt: Array = _read_through_value(key)
	if rt[0]:
		return rt[1]
	return _state.get(key, default)


func set_flag(key: String) -> void:
	set_value(key, true)


func has_flag(key: String) -> bool:
	return get_value(key, false) == true


func increment(key: String, by: int = 1) -> int:
	var value: int = int(get_value(key, 0)) + by
	set_value(key, value)
	return value


## Full snapshot for the save system. Under the mirror flip (docs/SUBSTRATE.md §2a)
## the store no longer keeps a copy of a live held-owned eligible key, so OVERLAY
## each such key's read-through value — the snapshot stays complete and byte-
## identical to the mirror-on save (the same value F3's held_owned_snapshot sources).
## Off the flip / before a held world is live, this is the plain store duplicate.
func snapshot() -> Dictionary:
	var s: Dictionary = _state.duplicate(true)
	if _mirror_flip:
		for key: String in _read_through:
			var rt: Array = _read_through_value(key)
			if rt[0]:
				s[key] = rt[1]
	return s


## Restore from a save. Replaces everything; emits no signals (loading is
## not a world event).
func restore(data: Dictionary) -> void:
	_state = data.duplicate(true)
