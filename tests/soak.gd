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

	# The living systems under soak: wildlife (weather, climate, flora,
	# rumors are autoloads already ticking on hour_tick). The authored
	# inhabitants retired with the old valley — Strata is the world now.
	# WildlifeManager is game content (the hound), not framework: a
	# content-empty scaffolded game soaks its autoload sims alone. When the
	# manager is absent the fingerprint simply carries no herd digest — and
	# valley (manager present) stays bit-identical, since a herdless world
	# would contribute nothing either way.
	var wildlife: Node = null
	if ResourceLoader.exists("res://game/wildlife/wildlife_manager.gd"):
		wildlife = load("res://game/wildlife/wildlife_manager.gd").new()
		add_child(wildlife)

	var t0 := Time.get_ticks_msec()
	GameClock.advance_hours(24.0 * DAYS)
	var elapsed := Time.get_ticks_msec() - t0

	_invariants(wildlife)
	var fp := _fingerprint(wildlife)

	if _failures > 0:
		print("SOAK FAIL: %d invariant(s) broken" % _failures)
	else:
		print("SOAK PASS: %d days in %dms, day=%d weather=%s wetness=%.3f vitality=%.3f"
				% [DAYS, elapsed, GameClock.day, Weather.state,
				Climate.wetness, FloraLife.vitality])
	print("SOAK FINGERPRINT %d" % fp)
	# Contour routing proof (PLAN_ENGINE E2, Mission C1): whether the first
	# SYSTEM-TIER port (flora's hourly vitality ease) ran through the native
	# Contour §6 system inside THIS fingerprinted run, and how many times. Pure
	# diagnostic — never digested, so it cannot move the fingerprint above; it
	# proves the flag-ON soak was NOT a silent GDScript fallback (mode=2, calls
	# climbs to 24*DAYS), and the flag-OFF soak was pure GDScript (mode=1,
	# calls=0). The fingerprint owns FloraLife.vitality (%.4f above), so an
	# engaged run whose Contour ease diverged one ULP would have moved it.
	if FloraLife.has_method("contour_status"):
		var cs: Dictionary = FloraLife.contour_status()
		print("SOAK CONTOUR mode=%d engaged=%s flora_ticks=%d"
			% [int(cs.get("mode", 0)), str(cs.get("engaged", false)), int(cs.get("calls", 0))])
	# Weather's front chain (Mission C2a) — same engaged-path proof: mode=2 +
	# weather_ticks climbing means the fingerprinted Weather.state/wind_dir this
	# run were the Contour §6 system's, not a silent GDScript fallback.
	if Weather.has_method("contour_status"):
		var ws: Dictionary = Weather.contour_status()
		print("SOAK CONTOUR mode=%d engaged=%s weather_ticks=%d"
			% [int(ws.get("mode", 0)), str(ws.get("engaged", false)), int(ws.get("calls", 0))])
	# The SAME proof for the WETNESS FIELD (Mission C2b): the 8×8 grid evolution
	# ran through the native Contour §6 `Climate` system inside THIS run (mode=2,
	# climate_ticks climbs to 24*DAYS), or was pure GDScript (mode=1, calls=0).
	# The fingerprint owns Climate.wetness AND the whole wet_grid digest above,
	# so an engaged run whose Contour cell_step diverged one ULP moves it.
	if Climate.has_method("contour_status"):
		var cc: Dictionary = Climate.contour_status()
		print("SOAK CONTOUR-CLIMATE mode=%d engaged=%s climate_ticks=%d"
			% [int(cc.get("mode", 0)), str(cc.get("engaged", false)), int(cc.get("calls", 0))])
	# Contour routing proof for the Teller (Mission D1e): whether story's latch/index
	# RULES (the index construction, the §3 DAG, $role prose, role order + rank) ran
	# through the native Contour VM inside THIS fingerprinted run, and how many times.
	# Same diagnostic-not-digested discipline as flora above — it proves the flag-ON
	# soak's story section (journal.* rides the digest) was Contour-authored (mode=2,
	# calls>0 from the boot index build + every ambient-errand settle), the flag-OFF
	# soak pure GDScript (mode=1, calls=0). journal latches ARE the digest's story
	# section, so a routed rule that diverged would move the fingerprint above.
	if Story.has_method("contour_status"):
		var ss: Dictionary = Story.contour_status()
		print("SOAK CONTOUR-STORY mode=%d engaged=%s story_calls=%d"
			% [int(ss.get("mode", 0)), str(ss.get("engaged", false)), int(ss.get("calls", 0))])
	# The SAME engaged-path proof for the AGENT MIND (Mission C3): whether every
	# agent's advance() (drain/move/satisfy/decide) ran through the native Contour
	# §6 `AgentMind` system inside THIS run, and how many times. AgentSim is
	# per-instance, so the counter is CLASS-STATIC — mode=2 + agent_ticks climbing
	# to hours × herd size (the star_hounds run this mind) means the fingerprinted
	# sim.pos / sim.current.id above were the Contour system's, not a silent
	# GDScript fallback; mode=1, calls=0 is the pure-GDScript flag-off run. The
	# fingerprint owns every animal's pos + activity, so a routed mind that diverged
	# one ULP would have moved it. (content-empty scaffold: no minds => calls=0,
	# and both flag paths contribute nothing — bit-identical either way.) AgentSim
	# is framework (always registered), so the static reads unconditionally.
	var cs: Dictionary = AgentSim.contour_status()
	print("SOAK CONTOUR-AGENT mode=%d engaged=%s agent_ticks=%d"
		% [int(cs.get("mode", 0)), str(cs.get("engaged", false)), int(cs.get("calls", 0))])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  SOAK INVARIANT FAIL: ", name)


func _invariants(wildlife: Node) -> void:
	_check(GameClock.day == DAYS, "clock advanced exactly %d days" % DAYS)
	_check(Climate.wetness >= 0.0 and Climate.wetness <= 1.0, "wetness in [0,1]")
	for i in Climate.wet_grid.size():
		var w: float = Climate.wet_grid[i]
		_check(is_finite(w) and w >= 0.0 and w <= 1.0, "wet_grid[%d] in [0,1]" % i)
	_check(Climate.snow >= 0.0 and Climate.snow <= 1.0, "snow in [0,1]")
	for id in Hydrology.lake_level:
		var lv: float = Hydrology.lake_level[id]
		_check(lv >= Hydrology.LAKE_LEVEL_MIN and lv <= Hydrology.LAKE_LEVEL_MAX,
			"lake %s level on rails (%.3f)" % [id, lv])
	# Region lakes (the Strata hyd_* import cache) obey the same rails but
	# stay OUT of the fingerprint, like region_storage: cache contents must
	# never move the digest.
	for id in Hydrology.region_lake_level:
		var lv: float = Hydrology.region_lake_level[id]
		_check(lv >= Hydrology.LAKE_LEVEL_MIN and lv <= Hydrology.LAKE_LEVEL_MAX,
			"region lake %s level on rails (%.3f)" % [id, lv])
	for id in Hydrology.river_storage:
		var s: float = Hydrology.river_storage[id]
		_check(is_finite(s) and s >= 0.0, "river %s storage finite and non-negative" % id)
	_check(absf(Weather.wind_dir.length() - 1.0) < 0.01, "wind_dir stays unit")
	_check(FloraLife.vitality >= 0.05 and FloraLife.vitality <= 1.0, "vitality in rails")
	var gathered: Dictionary = WorldState.get_value("flora.cells", {})
	for k: String in gathered:
		var taken := float(gathered[k])
		_check(is_finite(taken) and taken > 0.0 and taken <= 1.0,
			"flora cell %s wound in (0,1]" % k)
	for herd in (wildlife.herds if wildlife != null else []):
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
	# The soak stance on story (DESIGN_QUESTS §10): this run is PLAYERLESS,
	# so only sim-born errands may latch — a journal latch from a story/arc
	# quest is a leak of player-gated logic into sim-driven paths, and any
	# choice.* seal here is impossible by construction (choices are player
	# acts). Caught immediately, forever.
	for key: String in _story_keys():
		if key.begins_with("choice."):
			_check(false, "playerless soak sealed a choice (%s)" % key)
			continue
		var qid := key.trim_prefix("journal.").split(".")[0]
		var tier := String((Story.quests.get(qid, {}) as Dictionary).get("tier", "?"))
		_check(tier == "errand",
			"playerless soak latched only ambient errands (%s is %s-tier)" % [key, tier])


func _grid_digest(grid: PackedFloat32Array) -> String:
	var parts := PackedStringArray()
	for i in grid.size():
		parts.append("%.3f" % grid[i])
	return ",".join(parts)


## Stable digest of everything the sim decided — only deterministic keys
## (no wall-clock-derived values like moon phase or daylight span).
func _fingerprint(wildlife: Node) -> int:
	var parts: Array = [
		Weather.state,
		"%.4f" % Climate.wetness,
		_grid_digest(Climate.wet_grid),
		"%.4f" % Climate.snow,
		"%.3f,%.3f" % [Weather.wind_dir.x, Weather.wind_dir.y],
		"%.4f" % FloraLife.vitality,
		FloraLife.depletion_digest(),
		str(Hydrology.lake_level),
		str(Hydrology.river_storage),
		GameClock.day,
		WorldState.has_flag("flora.bloom"),
		WorldState.has_flag("flora.parched"),
	]
	for herd in (wildlife.herds if wildlife != null else []):
		for ind in herd.individuals:
			var sim: AgentSim = ind.sim
			parts.append("%.1f,%.1f" % [sim.pos.x, sim.pos.y])
			parts.append(str(sim.current.get("id", "")))
	# The journal.* and choice.* namespaces ride the digest whole
	# (DESIGN_QUESTS §10/B13): a playerless soak must latch only sim-born
	# errands, IDENTICALLY, every run — errand determinism asserted for
	# free, forever. Sorted, so dictionary order can never move the hash.
	# The section header (quest count + key count) is ALWAYS digested, so
	# a wiring regression that silently drops the namespace would move
	# the fingerprint instead of hiding.
	var story_keys := _story_keys()
	parts.append("story:%d:%d" % [Story.quests.size(), story_keys.size()])
	for key: String in story_keys:
		parts.append("%s=%s" % [key, JSON.stringify(WorldState.get_value(key))])
	return hash("|".join(parts.map(func(p: Variant) -> String: return str(p))))


## Every quest-state key, sorted: latches (journal.*) and seals (choice.*).
func _story_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: String in WorldState.snapshot():
		if key.begins_with("journal.") or key.begins_with("choice."):
			keys.append(key)
	keys.sort()
	return keys
