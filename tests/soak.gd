extends Node
## World soak (scripts/soak.sh): run the whole simulation N game-days
## headless, assert invariants, and print a determinism fingerprint —
## the harness that keeps emergence shippable (SIM_ROADMAP: the Radiant
## AI lesson institutionalized). soak.sh runs this twice and compares
## fingerprints: same seed, same span → identical world, or the build
## is red.

const DAYS := 30
const SOAK_SEED := 123456789
const SNAPSHOT_BUDGET := 300_000  # bytes of WorldState JSON after 30 days

var _failures := 0


func _ready() -> void:
	# Fix everything time- and chance-shaped before any sim draws.
	WorldState.set_value("world.seed", SOAK_SEED)
	Rng.load_state()
	GameClock.hours = 9.0
	GameClock.day = 0

	# The living systems under soak: inhabitants and wildlife (weather,
	# climate, flora, rumors are autoloads already ticking on hour_tick).
	var npcs: Node = load("res://game/npc/npc_manager.gd").new()
	add_child(npcs)
	var wildlife: Node = load("res://game/wildlife/wildlife_manager.gd").new()
	add_child(wildlife)

	var t0 := Time.get_ticks_msec()
	GameClock.advance_hours(24.0 * DAYS)
	var elapsed := Time.get_ticks_msec() - t0

	_invariants(npcs, wildlife)
	var fp := _fingerprint(npcs, wildlife)

	if _failures > 0:
		print("SOAK FAIL: %d invariant(s) broken" % _failures)
	else:
		print("SOAK PASS: %d days in %dms, day=%d weather=%s wetness=%.3f vitality=%.3f"
				% [DAYS, elapsed, GameClock.day, Weather.state,
				Climate.wetness, FloraLife.vitality])
	print("SOAK FINGERPRINT %d" % fp)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  SOAK INVARIANT FAIL: ", name)


func _invariants(npcs: Node, wildlife: Node) -> void:
	_check(GameClock.day == DAYS, "clock advanced exactly %d days" % DAYS)
	_check(Climate.wetness >= 0.0 and Climate.wetness <= 1.0, "wetness in [0,1]")
	_check(Climate.snow >= 0.0 and Climate.snow <= 1.0, "snow in [0,1]")
	_check(absf(Weather.wind_dir.length() - 1.0) < 0.01, "wind_dir stays unit")
	_check(FloraLife.vitality >= 0.05 and FloraLife.vitality <= 1.0, "vitality in rails")
	for npc in npcs.get_children():
		for need in npc.needs:
			var v: float = npc.needs[need]
			_check(is_finite(v) and v >= 0.0 and v <= 100.0,
				"%s need %s bounded (%.1f)" % [npc.npc_id, need, v])
		_check(npc.global_position.is_finite(), "%s position finite" % npc.npc_id)
		_check(npc.global_position.length() < 5000.0, "%s inside the world" % npc.npc_id)
		_check(npc.rumors.size() <= npc.MAX_RUMORS, "%s memory capped" % npc.npc_id)
	for herd in wildlife.herds:
		for ind in herd.individuals:
			var sim: AgentSim = ind.sim
			_check(sim.pos.is_finite(), "%s animal position finite" % herd.species)
			_check((sim.pos - sim.home).length() < sim.roam_range * 3.0,
				"%s animal near its range" % herd.species)
			for need in sim.needs:
				var v: float = sim.needs[need]
				_check(is_finite(v) and v >= 0.0 and v <= 100.0,
					"%s drive %s bounded" % [herd.species, need])
	var size := JSON.stringify(WorldState.snapshot()).length()
	_check(size < SNAPSHOT_BUDGET,
		"save under budget (%d / %d bytes)" % [size, SNAPSHOT_BUDGET])


## Stable digest of everything the sim decided — only deterministic keys
## (no wall-clock-derived values like moon phase or daylight span).
func _fingerprint(npcs: Node, wildlife: Node) -> int:
	var parts: Array = [
		Weather.state,
		"%.4f" % Climate.wetness,
		"%.4f" % Climate.snow,
		"%.3f,%.3f" % [Weather.wind_dir.x, Weather.wind_dir.y],
		"%.4f" % FloraLife.vitality,
		GameClock.day,
		WorldState.has_flag("valley.bloom"),
		WorldState.has_flag("valley.parched"),
	]
	for npc in npcs.get_children():
		parts.append(npc.npc_id)
		parts.append("%.1f,%.1f" % [npc.global_position.x, npc.global_position.z])
		parts.append(str(npc.rumors))
		for need in npc.needs:
			parts.append("%.2f" % npc.needs[need])
	for herd in wildlife.herds:
		for ind in herd.individuals:
			var sim: AgentSim = ind.sim
			parts.append("%.1f,%.1f" % [sim.pos.x, sim.pos.y])
			parts.append(str(sim.current.get("id", "")))
	return hash("|".join(parts.map(func(p: Variant) -> String: return str(p))))
