extends SceneTree
## F2 (substrate TRUE Rung 2) input-side measurement probe — NOT a gate.
## Ticks each singleton system's real ContourBridge over its .ct once in
## MULTIPLEXED (E1d, full re-injection) and once in SINGLETON (this rung), and
## reports the declared payload injected per tick: keys + bytes, before vs after.
## The saving is exactly the pure-persistent-write payload the held world already
## owns and no longer re-crosses. Run:
##   STRATA_CONTOUR=1 STRATA_CONTOUR_MEASURE=1 godot --headless --script \
##     res://tests/held_inject_probe.gd

class Store:
	## A minimal WorldState-shaped store (get_value/set_value) — the bridge only
	## needs these two, plus the pre-seeded declared writes so a MULTIPLEXED tick
	## has something to re-inject.
	var _d := {}
	func set_value(k: String, v: Variant) -> void: _d[k] = v
	func get_value(k: String, default: Variant = null) -> Variant: return _d.get(k, default)


func _measure(name: String, module: String, seeds: Dictionary, inputs: Dictionary,
		dt: float, ticks: int) -> void:
	var full := _run(module, seeds, inputs, dt, ticks, ContourBridge.HELD_MODE_MULTIPLEXED)
	var slim := _run(module, seeds, inputs, dt, ticks, ContourBridge.HELD_MODE_SINGLETON)
	var dk: int = int(full.full_keys) - int(slim.last)
	var db: int = int(full.full_bytes) - int(slim.last_bytes)
	var pk: float = 0.0 if int(full.full_keys) == 0 else 100.0 * float(dk) / float(int(full.full_keys))
	var pb: float = 0.0 if int(full.full_bytes) == 0 else 100.0 * float(db) / float(int(full.full_bytes))
	print("MEASURE %-10s  MULTIPLEXED keys=%d bytes=%d  ->  SINGLETON keys=%d bytes=%d  |  saved keys=%d (%.0f%%) bytes=%d (%.0f%%)  [x%d ticks/soak]"
		% [name, full.full_keys, full.full_bytes, slim.last, slim.last_bytes, dk, pk, db, pb, ticks])


func _run(module: String, seeds: Dictionary, inputs: Dictionary, dt: float,
		ticks: int, mode: int) -> Dictionary:
	var store := Store.new()
	for k in seeds:
		store.set_value(k, seeds[k])
	var bridge := ContourBridge.new(store)
	var err := bridge.compile_file(module)
	if err != "":
		push_error("probe: %s did not compile: %s" % [module, err])
		return {"last": -1, "last_bytes": -1, "full_keys": -1, "full_bytes": -1, "mode": mode}
	bridge.set_held_mode(mode)
	# One tick suffices to record the per-tick inject size (measured BEFORE the
	# advance, so a stub store that cannot fully run a leaf still reports the true
	# injected payload — the metric this probe reports).
	bridge.tick_held(inputs, dt)
	return bridge.held_inject_stats()


func _grid(n: int, v: float) -> Array:
	var a := []
	a.resize(n)
	a.fill(v)
	return a


func _init() -> void:
	if OS.get_environment("STRATA_CONTOUR_MEASURE") != "1":
		print("probe: set STRATA_CONTOUR_MEASURE=1 (and STRATA_CONTOUR=1)")
		quit(1)
		return
	if not ContourBridge.available():
		print("probe: Contour VM unavailable (dylib?)")
		quit(1)
		return
	print("== F2 held-inject measurement — declared payload per held tick, before vs after ==")

	# SAND — pure persistent writes (sand.repose / sand.decay are NOT reads, NOT
	# handed in as inputs): the clean win. Seed the writes so a MULTIPLEXED tick
	# has them to re-inject. dt=0 (the sand control tick does not advance the clock).
	_measure("sand", "res://game/world/sand_field.ct",
		{"sand.repose": 0.6, "sand.decay": 0.02},
		{"sand.wet": 0.3, "sand.wind": 0.5, "sand.cell_m": 1.0}, 0.0, 40)

	# CLIMATE — the 64-cell wetness grid (read AND write, handed in as an input by
	# the host). The pure-write re-injection retired here is the redundant WRITE
	# pull of the same grid; the inputs overlay still carries it (the host owns the
	# grid), so the payload key count holds but the write-pull is gone.
	var g := _grid(64, 0.4)
	_measure("climate", "res://game/world/climate.ct",
		{"climate.wet_grid": g.duplicate()},
		{"climate.wet_grid": g.duplicate(), "climate.rain": _grid(64, 0.1),
		 "climate.dry_t": _grid(64, 12.0), "climate.dew": _grid(64, false),
		 "climate.melt": 0.0}, 3600.0, 720)

	# HYDROLOGY — region reservoir storage (read AND write, host-owned array).
	var st := _grid(16, 1000.0)
	_measure("hydrology", "res://game/world/hydrology.ct",
		{"hydrology.storage": st.duplicate()},
		{"hydrology.storage": st.duplicate(), "hydrology.area": _grid(16, 5.0e6),
		 "hydrology.rain": _grid(16, 0.02), "hydrology.baseflow": _grid(16, 0.3),
		 "hydrology.runoff": 0.4}, 3600.0, 720)

	# FLORA — vitality (read AND write, host-overlaid). One scalar.
	_measure("flora", "res://game/world/flora_life.ct",
		{"flora.vitality": 0.5},
		{"flora.env": {"season": 1, "moist": 0.4, "temp": 12.0}, "flora.vitality": 0.5},
		3600.0, 720)

	quit(0)
