extends Node
## THE HELD-SNAPSHOT GATE (F3, substrate ladder Rung 3 — docs/SUBSTRATE.md §3).
##
## Rung 3's acceptance in one sentence: "snapshot serializes the held world
## directly; the store IS the world" — so a save that SOURCES a held SINGLETON's
## OWNED keys from its HELD WORLD (Contour.world_snapshot, via
## ContourBridge.held_owned_snapshot) is BYTE-FOR-BYTE the WorldState MIRROR the
## store kept. The six-run soak proves that on the REAL 30-day play state
## (tests/soak.gd::_rung3_snapshot_acceptance, both +HELD runs). THIS gate proves
## the same equality at the BRIDGE level over each real SINGLETON module, and
## pins the two contract facts the soak cannot see:
##   • a MULTIPLEXED bridge's held world is NOT a faithful per-key snapshot source
##     (a sibling's state reads back stale), so held_owned_snapshot() returns {};
##   • the reserved CLOCK (time.elapsed) is NEVER sourced from a held world (each
##     bridge advances it on its own cadence) — only genuinely per-system-OWNED
##     keys (declared writes + this system's continuations) cross.
##
## SKIPs (still PASS) where the native kernel is absent (off macOS / no dylib) —
## the byte-identity assertion only fires where a held world can live. Success is
## the HELD-SNAPSHOT-GATE PASS line, not the exit code (the --quit-after backstop
## exits 0 even on an empty scene). scripts/test.sh runs it under
## STRATA_CONTOUR=1 STRATA_CONTOUR_HELD=1.

var _failures := 0
var _checks := 0


class Store:
	## A minimal WorldState-shaped store (get_value/set_value/snapshot) — the
	## mirror the SINGLETON diff-only apply keeps synced to the held world.
	var _d := {}
	func set_value(k: String, v: Variant) -> void: _d[k] = v
	func get_value(k: String, default: Variant = null) -> Variant: return _d.get(k, default)
	func snapshot() -> Dictionary: return _d.duplicate(true)


func _ready() -> void:
	if not ContourBridge.available():
		print("HELD-SNAPSHOT-GATE SKIP (no native kernel on this host)")
		print("HELD-SNAPSHOT-GATE PASS (0 checks — kernel absent)")
		get_tree().quit()
		return

	var g64 := _grid(64, 0.4)
	var g16 := _grid(16, 1000.0)
	# module ; seeds (declared writes pre-seeded) ; per-tick inputs ; dt
	_case("sand", "res://game/world/sand_field.ct",
		{"sand.repose": 0.6, "sand.decay": 0.02},
		{"sand.wet": 0.3, "sand.wind": 0.5, "sand.cell_m": 1.0}, 0.0)
	_case("flora", "res://game/world/flora_life.ct",
		{"flora.vitality": 0.5},
		{"flora.env": {"season": 1, "moist": 0.4, "temp": 12.0}, "flora.vitality": 0.5}, 3600.0)
	_case("climate", "res://game/world/climate.ct",
		{"climate.wet_grid": g64.duplicate()},
		{"climate.wet_grid": g64.duplicate(), "climate.rain": _grid(64, 0.1),
		 "climate.dry_t": _grid(64, 12.0), "climate.dew": _grid(64, false),
		 "climate.melt": 0.0}, 3600.0)
	_case("hydrology", "res://game/world/hydrology.ct",
		{"hydrology.storage": g16.duplicate()},
		{"hydrology.storage": g16.duplicate(), "hydrology.area": _grid(16, 5.0e6),
		 "hydrology.rain": _grid(16, 0.02), "hydrology.baseflow": _grid(16, 0.3),
		 "hydrology.runoff": 0.4}, 3600.0)

	if _failures == 0:
		print("HELD-SNAPSHOT-GATE PASS (%d checks)" % _checks)
	else:
		print("HELD-SNAPSHOT-GATE FAIL (%d of %d checks failed)" % [_failures, _checks])
	get_tree().quit()


## One module: tick a SINGLETON held world several times (advancing any timed
## continuation), then prove held_owned_snapshot() == the store mirror the
## diff-only apply produced, byte-for-byte — and the MULTIPLEXED / clock guards.
func _case(name: String, module: String, seeds: Dictionary, inputs: Dictionary, dt: float) -> void:
	var store := Store.new()
	for k in seeds:
		store.set_value(k, seeds[k])
	var bridge := ContourBridge.new(store)
	var err := bridge.compile_file(module)
	if err != "":
		_fail("%s: compile failed: %s" % [name, err])
		return
	bridge.set_held_mode(ContourBridge.HELD_MODE_SINGLETON)
	var applied := false
	for _i in 5:
		applied = bridge.tick_held(inputs, dt) or applied
	if not applied:
		_fail("%s: SINGLETON held tick never applied (cannot prove sourcing)" % name)
		return

	# THE ACCEPTANCE — the held-world OWNED snapshot equals the store mirror.
	var held := bridge.held_owned_snapshot()
	_ok(not held.is_empty(), "%s: held_owned_snapshot is non-empty (a live held world sourced it)" % name)
	var mirror := _owned_from_store(bridge, store)
	_ok(_key_set(held) == _key_set(mirror),
		"%s: held-owned key set == mirror-owned key set (%s vs %s)"
			% [name, _key_set(held), _key_set(mirror)])
	for k in mirror:
		_ok(held.has(k) and JSON.stringify(held[k]) == JSON.stringify(mirror[k]),
			"%s: owned key '%s' byte-identical held-vs-mirror" % [name, k])

	# THE PRODUCTION SHAPE — overlaying held-owned onto the mirror (exactly what
	# SaveManager._held_sourced_state does) is byte-identical to the plain mirror:
	# a sourcing change, not a value change.
	var base := store.snapshot()
	var overlaid := base.duplicate(true)
	for k in held:
		overlaid[k] = held[k]
	_ok(JSON.stringify(overlaid) == JSON.stringify(base),
		"%s: save-via-held == save-via-mirror byte-for-byte (production overlay)" % name)

	# THE CLOCK GUARD — time.elapsed is shared bookkeeping, never sourced here.
	_ok(not held.has("time.elapsed") and not held.has("time.dt"),
		"%s: reserved clock is NOT sourced from the held world" % name)

	# THE MODE GUARD — a MULTIPLEXED held world is NOT a snapshot source ({}).
	var mstore := Store.new()
	for k in seeds:
		mstore.set_value(k, seeds[k])
	var mbridge := ContourBridge.new(mstore)
	if mbridge.compile_file(module) == "":
		mbridge.set_held_mode(ContourBridge.HELD_MODE_MULTIPLEXED)
		mbridge.tick_held(inputs, dt)
		_ok(mbridge.held_owned_snapshot().is_empty(),
			"%s: MULTIPLEXED held_owned_snapshot refuses (returns {})" % name)


## The store's values for exactly the keys THIS bridge owns — declared writes
## plus each timed system's continuation. The mirror side of the acceptance.
func _owned_from_store(bridge: ContourBridge, store: Store) -> Dictionary:
	var owned := {}
	for w in bridge.declared_writes():
		var v: Variant = store.get_value(w)
		if v != null:
			owned[w] = v
	for row in bridge.systems():
		if bool((row as Dictionary).get("timed", false)):
			var ck := String((row as Dictionary).get("name", "")) + ".__time"
			var cv: Variant = store.get_value(ck)
			if cv != null:
				owned[ck] = cv
	return owned


func _key_set(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys


func _grid(n: int, v: Variant) -> Array:
	var a := []
	a.resize(n)
	a.fill(v)
	return a


func _ok(condition: bool, name: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


func _fail(msg: String) -> void:
	_checks += 1
	_failures += 1
	print("  FAIL: ", msg)
