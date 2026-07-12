extends Node
## THE RESTORE-INTO-HELD GATE (G1, substrate ladder Rung 3's OTHER half —
## docs/SUBSTRATE.md §2). F3 landed the SAVE reading the held world; this lane lands
## the LOAD restoring the save INTO a held world, so a load resumes every timeline
## from the loaded snapshot instead of a stale pre-load trajectory. That path — like
## save_migration's — runs at LOAD, once, before the world exists, so the six-run
## SOAK is structurally BLIND to it (the soak starts a fresh seeded world and never
## loads a save). This gate is that missing proof, the D3a/E1e stance carried to the
## held world: a DIFFERENT harness from the soak, asserting the load-path contract
## the fingerprint cannot see.
##
## WHAT IT PROVES (bridge-level, over each real SINGLETON module — the shape
## held_snapshot_gate uses, so it needs no player/world and runs anywhere the kernel
## lives):
##   (1) RESET DESTROYS — after ContourBridge.reset_held() the held world is gone
##       (world not ready), so between a load and the first replayed tick the save
##       sources the RESTORED mirror (held_owned_snapshot -> {}), never stale held
##       state. This is the restore-into-held primitive apply_snapshot fires.
##   (2) RESTORE-INTO-HELD — after reset + a store overwritten to a DISTINCT loaded
##       snapshot B, the next tick re-creates the held world seeded from B (the
##       tested world_create path with fresh reads), and held_owned_snapshot() is
##       BYTE-FOR-BYTE the store's owned mirror the diff-only apply keeps — the held
##       world RESUMED from the loaded snapshot, synced to the mirror.
##   (3) THE RESTORE ACTUALLY MOVED IT (accumulating modules) — the post-restore
##       held-owned differs from the pre-reset snapshot, so the held world reflects
##       the LOADED B, not a stale continuation of A. (Skipped for sand: its owned
##       repose/decay are pure per-tick outputs, recomputed regardless of seed, so
##       there is nothing a restore can move — trivially satisfied.)
##   (4) THE WIRING — ContourBridge exposes reset_held, and every contour_held_source
##       system exposes reset_held_world (the group method apply_snapshot calls), so
##       the load path actually reaches each held world.
##   (5) THE MIGRATION ENGAGEMENT COUNTER (the D3a openEnd, re-pinned here) — under
##       the flag the load-time save_migration routes through the Contour VM
##       (contour_status calls climb), the counter the soak can't see.
##
## SKIPs (still PASS) where the native kernel is absent (off macOS / no dylib) — the
## byte-identity assertions only fire where a held world can live; the wiring checks
## always run. Success is the RESTORE-HELD-GATE PASS line, not the exit code (the
## --quit-after backstop exits 0 even on an empty scene). scripts/test.sh runs it
## under STRATA_CONTOUR=1 STRATA_CONTOUR_HELD=1.

var _failures := 0
var _checks := 0


class Store:
	## A minimal WorldState-shaped store (get_value/set_value/snapshot) — the mirror
	## the SINGLETON diff-only apply keeps synced to the held world. WorldState.restore
	## replaces exactly this dict on a load; here we overwrite the owned keys to a
	## loaded snapshot B to simulate it.
	var _d := {}
	func set_value(k: String, v: Variant) -> void: _d[k] = v
	func get_value(k: String, default: Variant = null) -> Variant: return _d.get(k, default)
	func snapshot() -> Dictionary: return _d.duplicate(true)


func _ready() -> void:
	_gate_wiring()  # (4) — always runs (no kernel needed)
	_gate_migration_engagement()  # (5)
	if not ContourBridge.available():
		print("RESTORE-HELD-GATE SKIP (no native kernel on this host — held-world checks)")
		_verdict()
		return

	var g64a := _grid(64, 0.4)
	var g64b := _grid(64, 0.7)
	var g16a := _grid(16, 1000.0)
	var g16b := _grid(16, 2000.0)
	# name ; module ; seedsA ; inputsA ; seedsB (the loaded snapshot) ; inputsB ; dt ; accumulating
	_case("sand", "res://game/world/sand_field.ct",
		{"sand.repose": 0.6, "sand.decay": 0.02},
		{"sand.wet": 0.3, "sand.wind": 0.5, "sand.cell_m": 1.0},
		{"sand.repose": 0.9, "sand.decay": 0.05},
		{"sand.wet": 0.3, "sand.wind": 0.5, "sand.cell_m": 1.0}, 0.0, false)
	_case("flora", "res://game/world/flora_life.ct",
		{"flora.vitality": 0.5},
		{"flora.env": {"season": 1, "moist": 0.4, "temp": 12.0}, "flora.vitality": 0.5},
		{"flora.vitality": 0.2},
		{"flora.env": {"season": 1, "moist": 0.4, "temp": 12.0}, "flora.vitality": 0.2}, 3600.0, true)
	_case("climate", "res://game/world/climate.ct",
		{"climate.wet_grid": g64a.duplicate()},
		{"climate.wet_grid": g64a.duplicate(), "climate.rain": _grid(64, 0.1),
		 "climate.dry_t": _grid(64, 12.0), "climate.dew": _grid(64, false), "climate.melt": 0.0},
		{"climate.wet_grid": g64b.duplicate()},
		{"climate.wet_grid": g64b.duplicate(), "climate.rain": _grid(64, 0.1),
		 "climate.dry_t": _grid(64, 12.0), "climate.dew": _grid(64, false), "climate.melt": 0.0}, 3600.0, true)
	_case("hydrology", "res://game/world/hydrology.ct",
		{"hydrology.storage": g16a.duplicate()},
		{"hydrology.storage": g16a.duplicate(), "hydrology.area": _grid(16, 5.0e6),
		 "hydrology.rain": _grid(16, 0.02), "hydrology.baseflow": _grid(16, 0.3), "hydrology.runoff": 0.4},
		{"hydrology.storage": g16b.duplicate()},
		{"hydrology.storage": g16b.duplicate(), "hydrology.area": _grid(16, 5.0e6),
		 "hydrology.rain": _grid(16, 0.02), "hydrology.baseflow": _grid(16, 0.3), "hydrology.runoff": 0.4}, 3600.0, true)
	_verdict()


## One module: build a held world over snapshot A, then RESTORE snapshot B into it
## (reset + overwrite the store + tick) and prove the held world resumed from B.
func _case(name: String, module: String, seeds_a: Dictionary, inputs_a: Dictionary,
		seeds_b: Dictionary, inputs_b: Dictionary, dt: float, accumulating: bool) -> void:
	var store := Store.new()
	for k in seeds_a:
		store.set_value(k, seeds_a[k])
	var bridge := ContourBridge.new(store)
	var err := bridge.compile_file(module)
	if err != "":
		_fail("%s: compile failed: %s" % [name, err])
		return
	bridge.set_held_mode(ContourBridge.HELD_MODE_SINGLETON)

	# Build the held world over A.
	var applied := false
	for _i in 5:
		applied = bridge.tick_held(inputs_a, dt) or applied
	if not applied:
		_fail("%s: SINGLETON held tick never applied over A" % name)
		return
	_ok(bridge.is_ready(), "%s: held world is live after ticking A" % name)
	var snap_a := bridge.held_owned_snapshot()
	_ok(not snap_a.is_empty(), "%s: A held-owned snapshot is non-empty" % name)

	# (1) RESET DESTROYS — the held world is gone, so a save now sources the mirror.
	bridge.reset_held()
	_ok(bridge.held_owned_snapshot().is_empty(),
		"%s: after reset_held the held world is absent (save sources the restored mirror)" % name)

	# LOAD snapshot B: WorldState.restore replaces the store; the live var (and thus
	# the tick's owned input) is reloaded to B. Simulate both.
	for k in seeds_b:
		store.set_value(k, seeds_b[k])

	# (2) RESTORE-INTO-HELD — the next tick re-creates the held world seeded from B.
	applied = false
	for _i in 5:
		applied = bridge.tick_held(inputs_b, dt) or applied
	_ok(applied and bridge.is_ready(),
		"%s: held world re-created + ticked from the loaded snapshot B" % name)
	var snap_b := bridge.held_owned_snapshot()
	var mirror := _owned_from_store(bridge, store)
	_ok(_key_set(snap_b) == _key_set(mirror),
		"%s: post-restore held-owned key set == mirror (%s vs %s)"
			% [name, _key_set(snap_b), _key_set(mirror)])
	for k in mirror:
		_ok(snap_b.has(k) and JSON.stringify(snap_b[k]) == JSON.stringify(mirror[k]),
			"%s: post-restore owned key '%s' byte-identical held-vs-mirror (resumed from B, synced)" % [name, k])

	# (3) THE RESTORE ACTUALLY MOVED IT — accumulating owned reflects B, not stale A.
	if accumulating:
		_ok(JSON.stringify(snap_b) != JSON.stringify(snap_a),
			"%s: post-restore held-owned reflects the LOADED B, not a stale continuation of A" % name)


## (4) THE WIRING — the load path's group call reaches each held world.
func _gate_wiring() -> void:
	var b := ContourBridge.new(Store.new())
	_ok(b.has_method("reset_held"),
		"wiring: ContourBridge exposes reset_held (the restore-into-held primitive)")
	var systems := {
		"climate": "res://game/world/climate.gd", "weather": "res://game/world/weather.gd",
		"hydrology": "res://game/world/hydrology.gd", "sand_field": "res://game/world/sand_field.gd",
		"flora_life": "res://game/world/flora_life.gd"}
	for name in systems:
		var script: GDScript = load(systems[name])
		var names := {}
		for m in script.get_script_method_list():
			names[String(m.get("name", ""))] = true
		_ok(names.has("reset_held_world"),
			"wiring: %s exposes reset_held_world (apply_snapshot's contour_held_source call reaches it)" % name)
		_ok(names.has("held_owned_snapshot"),
			"wiring: %s exposes held_owned_snapshot (the F3 save source)" % name)


## (5) THE MIGRATION ENGAGEMENT COUNTER — the load-time save_migration routes through
## the VM under the flag (the D3a openEnd's proof, the soak is blind to it). A pure
## re-pin of the E1e counter, in this load-path gate.
func _gate_migration_engagement() -> void:
	var status: Dictionary = SaveMigration.contour_status()
	var engaged := bool(status.get("engaged", false))
	var before := int(status.get("calls", 0))
	# Drive a migrate (a valid v2 body ladders through untouched).
	var res: Dictionary = SaveMigration.migrate({"version": 2, "player": {"x": 0.0, "z": 0.0}})
	_ok(bool(res.get("ok", false)), "migration: a valid v2 save migrates ok through the load door")
	var after := int(SaveMigration.contour_status().get("calls", 0))
	var want_route := OS.get_environment("STRATA_CONTOUR") == "1" and Contour.available()
	if engaged:
		_ok(after > before,
			"migration: STRATA_CONTOUR routed migrate through the Contour VM (%d->%d calls) — no silent fallback"
				% [before, after])
	else:
		_ok(not want_route,
			"migration: STRATA_CONTOUR=1 with a live kernel MUST engage the VM (mode %d)" % int(status.get("mode", 0)))


func _verdict() -> void:
	if _failures == 0:
		print("RESTORE-HELD-GATE PASS (%d checks)" % _checks)
	else:
		print("RESTORE-HELD-GATE FAIL (%d of %d checks failed)" % [_failures, _checks])
	get_tree().quit()


## The store's values for exactly the keys THIS bridge owns — declared writes plus
## each timed system's continuation. The mirror side of the acceptance.
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
