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

## The HELD-WORLD injection mode (substrate ladder Rung 2 → TRUE Rung 2, F2 —
## docs/SUBSTRATE.md §1/§2). Set EXPLICITLY per system (set_held_mode), NEVER
## inferred — the two modes differ ONLY on the held path (tick_held); tick() /
## tick_seeded (the copy oracle) are mode-agnostic.
##
##   HELD_MODE_MULTIPLEXED (default) — one held world drives MANY entities
##     (agent_sim's herd): between ticks the held world holds ANOTHER entity's
##     state, so every tick RE-INJECTS the full declared set (reads + own writes +
##     clock + continuations) and APPLIES the full declared-write set (the diff,
##     or the injected value for a write that did not move). This is E1d's held
##     routing — the always-correct floor, byte-identical to tick_seeded.
##
##   HELD_MODE_SINGLETON — one held world IS the sim-tier truth for ONE system's
##     own state (weather / climate / hydrology / sand / flora). Its persistent
##     declared WRITES live in the held world across ticks, so they are NOT
##     re-injected: each tick injects ONLY the declared reads the held world does
##     not own (external environment written elsewhere + the transient `inputs`
##     overlay) plus the reserved clock / continuations, and APPLIES only the
##     write-diff. The pure-persistent-write re-injection E1d paid on the INPUT
##     side is retired — O(reads-not-held) in, O(writes-moved) out. It is
##     bit-identical to the copy oracle because a diff-only apply keeps WorldState
##     synced to the held world every tick (WS[write] == held[write] by
##     induction from the create seed), so the copy path re-seeds the same value.
##     UNSAFE for a multiplexed world (a between-tick sibling value would read
##     back stale) — hence the mode is explicit, never inferred.
const HELD_MODE_MULTIPLEXED := 0
const HELD_MODE_SINGLETON := 1

var _vm: Contour = null
var _ws: Object = null                 # the WorldState store (get_value/set_value)
var _reads: PackedStringArray = []      # union of declared reads (the seed set)
var _writes: PackedStringArray = []     # union of declared writes (the apply allow-list)
var _timed: PackedStringArray = []      # names of timed systems (continuation keys)
var _ready := false
var _held_mode := HELD_MODE_MULTIPLEXED  # the held-path injection mode (explicit per system)
# Input-side measurement (the F2 rung's payoff, docs/SUBSTRATE.md §1): the count
# of declared keys the LAST held tick injected, and the cumulative total. A
# SINGLETON tick omits the pure-persistent-write keys a MULTIPLEXED tick re-sends.
# `_held_measure` (env STRATA_CONTOUR_MEASURE=1) additionally records the injected
# BYTES and the MULTIPLEXED counterfactual, so a probe can size the saving; it is
# OFF in production (var_to_bytes per tick is a measurement-only cost).
static var _held_measure := OS.get_environment("STRATA_CONTOUR_MEASURE") == "1"
var _held_last_inject_keys := 0
var _held_inject_keys_total := 0
var _held_last_inject_bytes := 0
var _held_last_full_keys := 0    # counterfactual: keys a MULTIPLEXED tick would inject
var _held_last_full_bytes := 0   # counterfactual bytes (measure mode only)


## Construct over a WorldState-shaped store (anything with get_value(key,default)
## and set_value(key,value) — the autoload in-game, a stub in a unit test).
func _init(world_state: Object) -> void:
	_ws = world_state


## Declare the held-world injection mode EXPLICITLY (substrate Rung 2, F2). A
## SINGLETON system (its held world holds its OWN state alone — weather/climate/
## hydrology/sand/flora) drops the pure-persistent-write re-injection; a
## MULTIPLEXED module (agent_sim's herd, one held world for many minds) keeps the
## full-set injection. Never inferred — a system opts in by NAME. Call once,
## before the first tick_held (a mid-stream change would re-mode the live held
## world). The mode is inert for tick()/tick_seeded (the copy oracle).
func set_held_mode(mode: int) -> void:
	assert(mode == HELD_MODE_MULTIPLEXED or mode == HELD_MODE_SINGLETON,
		"contour_bridge: unknown held mode %d" % mode)
	_held_mode = mode


## The declared held-injection mode (introspection).
func held_mode() -> int:
	return _held_mode


## Input-side measurement (docs/SUBSTRATE.md §1): the declared payload the LAST
## held tick injected vs the MULTIPLEXED counterfactual E1d would have re-sent.
## `full_*` and `*_bytes` are populated only under STRATA_CONTOUR_MEASURE=1. The
## saving a SINGLETON earns is exactly the pure-persistent-write keys/bytes it
## stops re-sending each tick (full minus last).
func held_inject_stats() -> Dictionary:
	return {
		"last": _held_last_inject_keys, "total": _held_inject_keys_total,
		"last_bytes": _held_last_inject_bytes,
		"full_keys": _held_last_full_keys, "full_bytes": _held_last_full_bytes,
		"mode": _held_mode}


## Rung 3 (docs/SUBSTRATE.md §2/§3 — "snapshot serializes the held world
## directly; the store IS the world"): the CURRENT held-world value for exactly
## the keys THIS bridge OWNS — its declared writes and its timed continuations —
## pulled from Contour.world_snapshot() (the sim-tier truth), NOT the WorldState
## mirror. The save path (SaveManager.snapshot_data under STRATA_CONTOUR_HELD=1)
## overlays this over the mirror so a save sources held-owned state from the held
## world it already advances in place, instead of the copy the store kept.
##
## SINGLETON ONLY, and BYTE-IDENTICAL to the mirror by construction (that is the
## rung's acceptance): a SINGLETON held world holds ONE system's state, kept
## synced to WorldState by the diff-only apply — WS[owned] == held[owned] every
## tick by induction from the create seed — so sourcing from either is the same
## bytes. A MULTIPLEXED held world holds only the LAST-ticked entity's state
## between ticks (a sibling's keys read back stale), so it is NOT a faithful
## per-key snapshot source: this returns {} for it, never a false truth. Empty
## too when no held world is live (never engaged / the copy path / kernel absent)
## — the mirror stays authoritative until the held world exists.
##
## The reserved CLOCK (time.elapsed) is deliberately NOT sourced here: it is
## shared bookkeeping each bridge advances on its OWN cadence, so a given held
## world's elapsed need not equal the mirror's last-writer value. Only genuinely
## per-system-OWNED keys cross (declared writes + this system's continuations),
## and those never collide across bridges — so the overlay is order-preserving
## and conflict-free, and time.elapsed keeps the mirror as its single authority.
func held_owned_snapshot() -> Dictionary:
	if _held_mode != HELD_MODE_SINGLETON:
		return {}
	if _vm == null or not _vm.world_ready():
		return {}
	var snap: Dictionary = _vm.world_snapshot()
	if snap.is_empty():
		return {}
	var owned := {}
	for w in _writes:
		if snap.has(w):
			owned[w] = snap[w]
	for name in _timed:
		var ck := String(name) + CONTINUATION_SUFFIX
		if snap.has(ck):
			owned[ck] = snap[ck]
	return owned


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
## seeded from the full declared reads/writes/clock/continuations pulled from
## WorldState) and thereafter ticked IN PLACE: advances one `dt` step and gets
## back ONLY the WRITE-DIFF (the keys whose value moved) — O(writes) OUT, where
## tick_seeded re-marshals the whole world (O(world size)).
##
## The per-tick injection + apply depend on the EXPLICIT held mode (set_held_mode):
##
##   MULTIPLEXED (default, E1d) — re-inject the FULL declared set (reads + own
##     writes + clock + continuations + the `inputs` overlay), and apply the full
##     declared-write set (the diff, or the injected value for a write that did
##     not move). REQUIRED when ONE bridge multiplexes MANY entities (agent_sim's
##     herd): the between-tick held world holds a sibling's state, so both the
##     input re-inject and the diff-or-inject apply are load-bearing.
##
##   SINGLETON (F2, TRUE Rung 2) — the held world IS this system's sole state, so
##     its pure persistent WRITES are NOT re-injected (held-world truth); each
##     tick injects only the reads it does not own + reserved clock/continuations
##     + `inputs` overlay, and applies DIFF-ONLY. WorldState stays synced to the
##     held world (WS[write] == held[write] by induction from the create seed), so
##     it is BYTE-IDENTICAL to tick_seeded while retiring the input-side
##     round-trip of state the store already owns (docs/SUBSTRATE.md §1).
##
## Either way the copy path (tick_seeded) stays the bit-parity ORACLE, and the
## six-run soak (2×off / 2×STRATA_CONTOUR / 2×+STRATA_CONTOUR_HELD) shares one
## fingerprint. The held world persisting across ticks + the diff-return ABI are
## the mechanism under test; the mode-correct reconcile keeps it provably equal.
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
	var singleton := _held_mode == HELD_MODE_SINGLETON
	# The CREATE seed is ALWAYS the full declared set (both modes) so the held
	# world starts equal to WorldState — its held writes/clock/continuations are
	# correct from tick 1, and every later injection is a pure in-place update.
	if not _vm.world_ready():
		if not _vm.world_create(_build_inject(inputs, true)):
			push_error("contour_bridge: world_create refused (held mode)")
			return false
	# The per-tick INJECT:
	#   MULTIPLEXED re-injects the full declared set (the held world may hold a
	#     sibling entity's state between ticks — it must be re-established).
	#   SINGLETON injects only the reads the held world does NOT own — reads that
	#     are not the system's own writes, the reserved clock/continuations, and
	#     the transient `inputs` overlay. The system's pure persistent WRITES are
	#     held-world truth and are NOT re-sent (the F2 rung's input-side payoff).
	var inject := _build_inject(inputs, not singleton)
	_held_last_inject_keys = inject.size()
	_held_inject_keys_total += inject.size()
	if _held_measure:
		_held_last_inject_bytes = var_to_bytes(inject).size()
		# The MULTIPLEXED counterfactual — what E1d re-injects every tick — so the
		# probe can size exactly the pure-persistent-write payload this rung retires.
		var full := inject if not singleton else _build_inject(inputs, true)
		_held_last_full_keys = full.size()
		_held_last_full_bytes = var_to_bytes(full).size()
	# Advance the held world IN PLACE; get back ONLY the write-diff.
	var diff: Dictionary = _vm.world_tick(inject, dt)
	if diff.is_empty():
		return false   # the VM refused (a fault surfaced through push_error)
	# APPLY the writes back — writes-only, never a blind overwrite.
	if singleton:
		# DIFF-ONLY: the held world is the sim-tier truth for its own writes /
		# clock / continuations, and WorldState stays synced to it (WS[write] ==
		# held[write] by induction from the create seed — a moved write rides the
		# diff, an unmoved one is unchanged in both). No inject fallback: a write
		# absent from the diff did not move, and WorldState already holds it. This
		# is bit-identical to tick_seeded for a SINGLETON world and is the whole
		# point of the rung — the store no longer round-trips state it already owns.
		for w in _writes:
			if diff.has(w):
				_ws.set_value(w, diff[w])
		if diff.has(CLOCK_ELAPSED):
			_ws.set_value(CLOCK_ELAPSED, diff[CLOCK_ELAPSED])
		for name in _timed:
			var ck := String(name) + CONTINUATION_SUFFIX
			if diff.has(ck):
				_ws.set_value(ck, diff[ck])
	else:
		# FULL declared-write set, diff-or-inject fallback: a write present in the
		# diff MOVED (apply the new value); one ABSENT did NOT move (apply the
		# pre-tick INJECTED value). This mirrors tick_seeded EXACTLY, and it is
		# REQUIRED when ONE bridge multiplexes MANY entities (agent_sim's herd):
		# WorldState between ticks holds the PREVIOUS mind's value, so an unchanged
		# write must still overwrite it with THIS mind's injected value.
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


## RESTORE-INTO-HELD (substrate Rung 3's other half — docs/SUBSTRATE.md §2, the
## restore side of "the store IS the world"). A LOAD replaced WorldState wholesale
## (SaveManager.apply_snapshot -> WorldState.restore), so the live held world now
## holds the PRE-LOAD trajectory, not the restored save. This DESTROYS it: the next
## tick_held re-creates it via world_create, seeded from the (now restored)
## WorldState + that tick's fresh declared-read inputs — so the held world RESUMES
## from the loaded snapshot, exactly the create-seed path already tested, never a
## stale sibling of the mirror. Between the reset and that first tick the held world
## is absent, so held_owned_snapshot() returns {} and the save falls back to the
## restored mirror (correct) — no window where a save reads stale held state.
##
## Why reset here, re-create lazily on the first tick (not an eager create now): the
## create seed needs the fresh per-tick `inputs` (the transient declared reads the
## host samples live — climate.rain, weather's stream, ...), which do not exist at
## load time. Re-creating on the first tick reuses the one tested seeding path with
## the real inputs; an eager load-time create would seed those reads from a stale or
## absent mirror. Idempotent + inert off the held path (no held world -> a no-op),
## so it is byte-inert under STRATA_CONTOUR_HELD unset.
func reset_held() -> void:
	if _vm != null and _vm.world_ready():
		_vm.world_destroy()


## Build the held-world injection dict. `include_writes` seeds the system's OWN
## persistent declared writes from WorldState (the MULTIPLEXED / world_create
## path); a SINGLETON per-tick inject sets it FALSE, so a read that is ALSO a
## write is skipped from the WorldState pull (held-world truth — re-supplied by
## the `inputs` overlay only when the host explicitly owns it). The reserved
## clock + timed continuations ride BOTH modes (shared/reserved bookkeeping, not
## "persistent writes" — the F2 rung retires only the pure-write re-injection).
## The transient `inputs` overlay always wins (the host's fresh declared reads).
func _build_inject(inputs: Dictionary, include_writes: bool) -> Dictionary:
	var inject := {}
	var writeset := {}
	if not include_writes:
		for w in _writes:
			writeset[w] = true
	for r in _reads:
		if writeset.has(r):
			continue   # a read that is ALSO a write — held-world truth this tick
		var rv: Variant = _ws.get_value(r)
		if rv != null:
			inject[r] = rv
	if include_writes:
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
	return inject


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
