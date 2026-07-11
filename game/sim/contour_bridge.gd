class_name ContourBridge
extends RefCounted
## The SYSTEMS BRIDGE (PLAN_ENGINE §3 E2, Mission C0): a Contour `system` module
## ticking INSIDE the game against real WorldState, one clock step per call.
##
## Where game/sim/contour.gd::Contour is the raw VM host (compile + call_fn +
## tick + systems), ContourBridge is the honest WORLD ADAPTER on top of it: it
## reads the module's DECLARED reads/writes (Contour.systems()) once at compile,
## then per tick it (1) SEEDS a world dict from the declared resources pulled out
## of WorldState mirrors (reads = inputs; declared writes = the system's own
## persistent state, round-tripped so a resource unwritten this tick keeps its
## value), (2) advances the whole §6/§7 schedule one `dt` step, and (3) applies
## ONLY the declared writes back into WorldState — writes-only, never a blind
## world overwrite. The reserved clock (`time.elapsed`) and each timed
## system's continuation (`<System>.__time`) are persisted into WorldState too,
## so they ride SaveGame's snapshot/restore and a restored run replays
## bit-identically (the §7 replay law, in-process).
##
## DECLARED-ACCESS-ONLY (the acceptance): the seed set is exactly the union of
## declared reads; the apply allow-list is exactly the union of declared writes.
## A system that writes an UNDECLARED resource is refused by the language at
## compile (a compile error compile_file surfaces), so the allow-list is
## exhaustive; and a system that declares a RESERVED write (time.*/*.__time — it
## would corrupt the clock/continuation bookkeeping) is refused LOUDLY here.
##
## SOAK-INERT while unused: nothing ticks unless a game constructs a bridge,
## compiles a module, and calls tick() — exactly the contour.gd no-op discipline.
##
## Consumer contract (C1 wires a real module through this):
##   var bridge := ContourBridge.new(WorldState)     # inject the world store
##   var err := bridge.compile_file("res://<module>.ct")   # "" on success
##   if err == "":
##       # per sim tick (game_clock advance): seed→tick→apply, all declared-only
##       bridge.tick(dt_seconds)

## Reserved world resources the VM maintains (spec §7). Never declarable as a
## system write; persisted across ticks so timelines resume.
const CLOCK_ELAPSED := "time.elapsed"
const CLOCK_DT := "time.dt"
const CONTINUATION_SUFFIX := ".__time"

var _vm: Contour = null
var _ws: Object = null                 # the WorldState store (get_value/set_value)
var _reads: PackedStringArray = []      # union of declared reads (the seed set)
var _writes: PackedStringArray = []     # union of declared writes (the apply allow-list)
var _timed: PackedStringArray = []      # names of timed systems (continuation keys)
var _ready := false


## Construct over a WorldState-shaped store (anything with get_value(key,default)
## and set_value(key,value) — the autoload in-game, a stub in a unit test).
func _init(world_state: Object) -> void:
	_ws = world_state


## Is the native Contour VM loadable at all (macOS + dylib present)? Consumers
## gate their "bridge or GDScript fallback" branch on this — same as Contour.
static func available() -> bool:
	return Contour.available()


## Compile a module from a res:// .ct file, then index its system manifest.
## Returns "" on success (the bridge is live for tick()), else a diagnostic
## (kernel unavailable, a compile error, or a reserved-write refusal).
func compile_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "contour_bridge: no such module " + path
	return compile(FileAccess.get_file_as_string(path))


## Compile a module from source text, then index its system manifest.
func compile(src: String) -> String:
	_ready = false
	_vm = Contour.new()
	var err: String = _vm.compile(src)
	if err != "":
		_vm = null
		return err
	var index_err := _index_systems()
	if index_err != "":
		_vm = null
		return index_err
	_ready = true
	return ""


## True once a module is compiled, its manifest indexed, and the VM live.
func is_ready() -> bool:
	return _ready and _vm != null and _vm.is_ready()


## The raw system manifest (introspection): an Array of
## {name, reads, writes, timed} dictionaries in declaration order.
func systems() -> Array:
	return _vm.systems() if _vm != null else []


## The union of every system's declared reads — exactly the keys the bridge
## seeds from WorldState. (Declaration order across systems.)
func declared_reads() -> PackedStringArray:
	return _reads


## The union of every system's declared writes — exactly the keys the bridge
## applies back to WorldState (the apply allow-list).
func declared_writes() -> PackedStringArray:
	return _writes


## Advance the whole §6/§7 schedule ONE clock step of `dt` seconds. Seeds the
## declared reads (plus the persisted clock/continuations) from WorldState,
## ticks, and applies the declared writes (plus the reserved clock/continuation
## bookkeeping) back into WorldState. Returns true when a tick applied; false
## when the bridge isn't ready or the VM refused the tick.
func tick(dt: float) -> bool:
	if not is_ready():
		return false
	# (1) SEED from the DECLARED resources — WorldState mirrors, declared-access
	# only. Reads are the system's inputs; the declared WRITES are its OWN
	# persistent state, seeded back so a resource a system does NOT re-write this
	# tick (e.g. after an `over` completes) keeps its prior value rather than
	# being re-nulled — the full-world round-trip §7 assumes. A key absent from
	# WorldState (null) is left unseeded: a first-tick write the VM initializes,
	# never a spurious null injected into the world.
	var seed := {}
	for r in _reads:
		var rv: Variant = _ws.get_value(r)
		if rv != null:
			seed[r] = rv
	for w in _writes:
		var wv: Variant = _ws.get_value(w)
		if wv != null:
			seed[w] = wv
	# Resume the injected clock + each timed continuation from the persisted
	# world, so an `over`/`until`/`at` picks up exactly where it suspended.
	var elapsed: Variant = _ws.get_value(CLOCK_ELAPSED)
	if elapsed != null:
		seed[CLOCK_ELAPSED] = elapsed
	for name in _timed:
		var ck := String(name) + CONTINUATION_SUFFIX
		var cont: Variant = _ws.get_value(ck)
		if cont != null:
			seed[ck] = cont
	# (2) TICK the whole schedule one step.
	var world_out: Dictionary = _vm.tick(seed, dt)
	if world_out.is_empty():
		return false   # the VM refused (a fault surfaced through push_error)
	# (3) APPLY the DECLARED writes back — writes-only, never a blind overwrite.
	for w in _writes:
		if world_out.has(w):
			_ws.set_value(w, world_out[w])
	# Persist the reserved bookkeeping so it rides SaveGame snapshot/restore
	# (the §7 replay law): the monotone clock and every timed continuation.
	if world_out.has(CLOCK_ELAPSED):
		_ws.set_value(CLOCK_ELAPSED, world_out[CLOCK_ELAPSED])
	for name in _timed:
		var ck := String(name) + CONTINUATION_SUFFIX
		if world_out.has(ck):
			_ws.set_value(ck, world_out[ck])
	return true


## tick(), but with TRANSIENT declared-read inputs overlaid onto the seed
## (Mission C1). `inputs` maps a declared-read resource -> a value the host
## computed FRESH this tick and does NOT persist in WorldState — a system's live
## environment (e.g. flora's season/moisture/temperature, sampled from the same
## Climate/GameClock reads the GDScript twin makes). The overlay wins over any
## WorldState mirror of the same key for this tick only; declared WRITES are
## still applied back to WorldState exactly as tick() does, and the reserved
## clock/continuations still resume + persist (the §7 replay law is unbroken).
##
## DECLARED-ACCESS-ONLY still holds: every `inputs` key MUST be a declared read
## (else the VM would ignore an unseeded resource and the tick would fault on
## first access) — an undeclared input is refused LOUDLY here, never silently
## dropped. Returns true when a tick applied.
func tick_seeded(inputs: Dictionary, dt: float) -> bool:
	if not is_ready():
		return false
	for k in inputs:
		if not (String(k) in _reads):
			push_error("contour_bridge: tick_seeded input '%s' is not a declared read %s"
				% [String(k), str(_reads)])
			return false
	# (1) SEED from WorldState (declared reads + declared writes = own state),
	# then resume the clock + timed continuations — identical to tick().
	var seed := {}
	for r in _reads:
		var rv: Variant = _ws.get_value(r)
		if rv != null:
			seed[r] = rv
	for w in _writes:
		var wv: Variant = _ws.get_value(w)
		if wv != null:
			seed[w] = wv
	var elapsed: Variant = _ws.get_value(CLOCK_ELAPSED)
	if elapsed != null:
		seed[CLOCK_ELAPSED] = elapsed
	for name in _timed:
		var ck := String(name) + CONTINUATION_SUFFIX
		var cont: Variant = _ws.get_value(ck)
		if cont != null:
			seed[ck] = cont
	# Overlay the transient inputs (win over any mirror; NOT persisted back).
	for k in inputs:
		seed[k] = inputs[k]
	# (2) TICK.
	var world_out: Dictionary = _vm.tick(seed, dt)
	if world_out.is_empty():
		return false
	# (3) APPLY declared writes + persist the reserved bookkeeping.
	for w in _writes:
		if world_out.has(w):
			_ws.set_value(w, world_out[w])
	if world_out.has(CLOCK_ELAPSED):
		_ws.set_value(CLOCK_ELAPSED, world_out[CLOCK_ELAPSED])
	for name in _timed:
		var ck := String(name) + CONTINUATION_SUFFIX
		if world_out.has(ck):
			_ws.set_value(ck, world_out[ck])
	return true


## tick_seeded(), but through the PERSISTENT HELD WORLD (substrate ladder Rung 2,
## docs/SUBSTRATE.md §2). The held world is created ONCE (Contour.world_create,
## seeded from the declared reads/writes/clock/continuations pulled from
## WorldState) and thereafter ticked IN PLACE: each tick injects the SAME declared
## resources tick_seeded seeds (reads + own writes + the transient `inputs` overlay
## + the resumed clock/continuations), advances the held world one `dt` step, and
## gets back ONLY the WRITE-DIFF (the keys whose value moved) — O(writes) across
## the boundary, where tick_seeded re-marshals the whole world (O(world size)).
##
## The APPLY reconstructs tick_seeded's whole-world write-back from the diff: a
## declared write in the diff MOVED (apply the new value), one absent did NOT move
## (apply the pre-tick INJECTED value), plus the reserved clock + each timed
## continuation the same way. Because the full declared set is re-injected each
## tick AND the full declared-write set is applied each tick, the held path's
## WorldState effects are BYTE-IDENTICAL to tick_seeded's — even when ONE bridge
## multiplexes MANY entities through the held world (agent_sim's herd), where the
## between-tick WorldState holds another entity's value and a diff-ONLY apply would
## read back stale. The copy path stays the bit-parity oracle, and the six-run soak
## (2×off / 2×STRATA_CONTOUR / 2×+STRATA_CONTOUR_HELD) shares one fingerprint. The
## held world persisting across ticks + the diff-return ABI are the mechanism under
## test; the injected reconcile keeps it provably equal.
##
## Same DECLARED-ACCESS-ONLY discipline as tick_seeded: every `inputs` key MUST be
## a declared read (refused LOUDLY otherwise). Returns true when a tick applied.
func tick_held(inputs: Dictionary, dt: float) -> bool:
	if not is_ready():
		return false
	for k in inputs:
		if not (String(k) in _reads):
			push_error("contour_bridge: tick_held input '%s' is not a declared read %s"
				% [String(k), str(_reads)])
			return false
	# Build the inject payload — exactly tick_seeded's seed set: declared reads +
	# declared writes (own persistent state) from WorldState, the resumed clock +
	# timed continuations, then the transient `inputs` overlay (wins for this tick).
	var inject := {}
	for r in _reads:
		var rv: Variant = _ws.get_value(r)
		if rv != null:
			inject[r] = rv
	for w in _writes:
		var wv: Variant = _ws.get_value(w)
		if wv != null:
			inject[w] = wv
	var elapsed: Variant = _ws.get_value(CLOCK_ELAPSED)
	if elapsed != null:
		inject[CLOCK_ELAPSED] = elapsed
	for name in _timed:
		var ck := String(name) + CONTINUATION_SUFFIX
		var cont: Variant = _ws.get_value(ck)
		if cont != null:
			inject[ck] = cont
	for k in inputs:
		inject[k] = inputs[k]
	# Create the held world ONCE (first tick), seeded with this same set so every
	# injected key is present from the start (a pure in-place update thereafter).
	if not _vm.world_ready():
		if not _vm.world_create(inject):
			push_error("contour_bridge: world_create refused (held mode)")
			return false
	# Advance the held world IN PLACE; get back ONLY the write-diff.
	var diff: Dictionary = _vm.world_tick(inject, dt)
	if diff.is_empty():
		return false   # the VM refused (a fault surfaced through push_error)
	# APPLY the declared writes back — writes-only, never a blind overwrite — plus
	# the reserved clock + continuations. We apply the FULL declared-write set, not
	# just the diff: a write present in the diff MOVED this tick (apply the new
	# value); one ABSENT from the diff did NOT move (apply the pre-tick INJECTED
	# value). This mirrors tick_seeded EXACTLY — the copy path returns the whole
	# world and applies every declared write each tick, so an unchanged write still
	# overwrites WorldState with the value THIS tick injected. It matters when ONE
	# bridge multiplexes MANY entities through the held world (agent_sim's herd of
	# minds): WorldState between ticks holds the PREVIOUS mind's value, so a
	# diff-only apply would leave an unchanged write reading back stale. For a
	# singleton system (flora/weather/…) WorldState already holds its own prior
	# value, so the injected fallback is a same-value write — bit-identical, the
	# reason the copy path stays the parity oracle.
	for w in _writes:
		if diff.has(w):
			_ws.set_value(w, diff[w])
		elif inject.has(w):
			_ws.set_value(w, inject[w])
	if diff.has(CLOCK_ELAPSED):
		_ws.set_value(CLOCK_ELAPSED, diff[CLOCK_ELAPSED])
	elif inject.has(CLOCK_ELAPSED):
		_ws.set_value(CLOCK_ELAPSED, inject[CLOCK_ELAPSED])
	for name in _timed:
		var ck := String(name) + CONTINUATION_SUFFIX
		if diff.has(ck):
			_ws.set_value(ck, diff[ck])
		elif inject.has(ck):
			_ws.set_value(ck, inject[ck])
	return true


## Index the compiled manifest into the seed set (_reads), the apply allow-list
## (_writes), and the timed-system names (_timed). Refuses LOUDLY (a diagnostic)
## if a system declares a reserved write (time.*/*.__time) — that would corrupt
## the clock/continuation bookkeeping. "" on success.
func _index_systems() -> String:
	var reads := {}     # used as an ordered set (Dictionary preserves insertion)
	var writes := {}
	_timed = PackedStringArray()
	for row in _vm.systems():
		var name := String(row.get("name", ""))
		for r in row.get("reads", []):
			reads[String(r)] = true
		for w in row.get("writes", []):
			var wk := String(w)
			if wk == CLOCK_ELAPSED or wk == CLOCK_DT or wk.ends_with(CONTINUATION_SUFFIX):
				return "contour_bridge: system '%s' declares reserved write '%s' (time.*/*.__time is VM-owned)" % [name, wk]
			writes[wk] = true
		if bool(row.get("timed", false)):
			_timed.append(name)
	_reads = PackedStringArray(reads.keys())
	_writes = PackedStringArray(writes.keys())
	return ""
