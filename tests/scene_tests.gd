extends Node
## Scene-context tests: anything that needs autoloads alive (Conditions,
## WorldState interplay). Run by test.sh: godot --headless scene_tests.tscn
## — exits 0/1.

var _failures := 0


func _ready() -> void:
	_test_conditions()
	_test_skills()
	_test_clock()
	_test_seasons()
	_test_climate()
	_test_climate_v2()
	_test_water()
	_test_swell()
	_test_hydrology()
	_test_water_field()
	_test_flora()
	_test_moon()
	_test_wildlife()
	_test_wear()
	_test_nav()
	_test_sand_sim()
	_test_tile_override()
	await _test_strata_link()
	if _failures > 0:
		print("SCENE-TESTS FAIL: %d failed" % _failures)
	else:
		print("SCENE-TESTS PASS")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


## StrataLink (ONE_APP P3): the live-link verbs answer over a real local
## socket — ping round-trips, teleport without a player errs honestly,
## unknown verbs never hang the hub. Skips when the link isn't listening
## (release build or the port taken by a running game).
func _test_strata_link() -> void:
	if not StrataLink.summary().begins_with("listening"):
		print("  strata link: SKIP (not listening — port busy or release build)")
		return
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", StrataLink.port) != OK:
		_check(false, "link connect")
		return
	for i in 100:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await get_tree().process_frame
	_check(peer.get_status() == StreamPeerTCP.STATUS_CONNECTED, "link connects")
	var replies := await _link_send(peer, ["ping", "bogus_verb", "teleport 1 2", "status"])
	_check(replies.size() == 4, "one reply per command (got %d)" % replies.size())
	if replies.size() == 4:
		_check(replies[0].begins_with("ok pong"), "ping -> pong")
		_check(replies[1].begins_with("err"), "unknown verb errs, never hangs")
		# No player node in the test scene: the honest error path.
		_check(replies[2] == "err no player in tree", "teleport without player errs")
		_check(replies[3].begins_with("ok") and "focus=" in replies[3], "status reports focus")
	peer.disconnect_from_host()


## Send commands one per line, then pump frames until every reply lands.
func _link_send(peer: StreamPeerTCP, commands: Array) -> Array:
	for c in commands:
		peer.put_data((str(c) + "\n").to_utf8_buffer())
	var buffer := ""
	for i in 300:
		await get_tree().process_frame
		peer.poll()
		while peer.get_available_bytes() > 0:
			buffer += peer.get_string(peer.get_available_bytes())
		if buffer.count("\n") >= commands.size():
			break
	var out: Array = []
	for line in buffer.split("\n", false):
		out.append(line)
	return out


## The pen override layer (P0 seam fix): pens add meters OVER the blessed
## tile — commit reshapes, restore returns the ground bit-identical, and
## the tile on disk is never written. In-memory only (no save here, so a
## dev checkout's data stays untouched). Skips honestly where the baked
## tile cache doesn't exist (fresh clone / CI).
func _test_tile_override() -> void:
	if not Terrain.has_world_tile():
		print("  tile override: SKIP (no baked tile cache)")
		return
	var p := Vector2(1500.0, -1500.0)
	var before: float = Terrain.height(p.x, p.y)
	var snap: Image = Terrain.snapshot_tile_override()
	_check(snap != null, "override snapshot exists once a tile is loaded")
	var painted: Rect2 = Terrain.paint_tile_override(p, 200.0, 5.0)
	_check(painted.size != Vector2.ZERO, "override paint returns its rect")
	_check(Terrain.height(p.x, p.y) == before,
		"paint alone does not reshape (commit does)")
	Terrain.commit_tile_override(painted)
	var lifted: float = Terrain.height(p.x, p.y) - before
	_check(absf(lifted - 5.0) < 0.8,
		"commit raises the ground ~5m (got %.2fm)" % lifted)
	Terrain.restore_tile_override(snap)
	_check(Terrain.height(p.x, p.y) == before,
		"restore returns bit-identical ground")


## The shared condition language (Conditions) — the gate every future
## quest/dialogue will evaluate. The dialogue/quest ENGINES retired with
## the old valley; the language they spoke lives on and stays tested.
func _test_conditions() -> void:
	_check(Conditions.eval({}), "empty condition passes")
	WorldState.set_flag("test.flag")
	_check(Conditions.eval({"flag": "test.flag"}), "flag condition")
	_check(not Conditions.eval({"flag": "test.unset"}), "flag on unset fails")
	_check(not Conditions.eval({"not_flag": "test.flag"}), "not_flag condition")
	_check(Conditions.eval({"not_flag": "test.other"}), "not_flag on unset")
	WorldState.set_value("test.count", 3)
	_check(Conditions.eval({"gte": ["test.count", 3]}), "gte pass")
	_check(not Conditions.eval({"gte": ["test.count", 4]}), "gte fail")
	_check(not Conditions.eval({"item": ["nonexistent_item", 1]}), "item condition")
	# All keys AND together: one failing clause fails the whole gate.
	_check(not Conditions.eval({"flag": "test.flag", "gte": ["test.count", 4]}),
		"clauses AND — one failure fails the gate")


func _test_skills() -> void:
	_check(Skills.defs().size() >= 4, "skill records load")
	WorldState.set_value("player.dist_walked", 1300.0)
	_check(Skills.level("wayfaring") == 2, "wayfaring level from distance")
	WorldState.set_value("player.dist_walked", 0.0)
	_check(Skills.level("wayfaring") == 0, "level derives, never sticks")
	_check(Skills.level("nonexistent") == 0, "unknown skill is level 0")


## advance_hours is the shared catch-up path (load, laptop sleep, debug
## skip): it must tick every skipped hour and roll days across midnight.
func _test_clock() -> void:
	var ticks: Array = []
	var on_tick := func(h: int) -> void: ticks.append(h)
	GameClock.hour_tick.connect(on_tick)
	GameClock.hours = 22.0
	GameClock.day = 3
	GameClock.advance_hours(4.0)
	GameClock.hour_tick.disconnect(on_tick)
	_check(ticks.size() == 4, "advance fires hour_tick for every skipped hour")
	_check(ticks == [23, 0, 1, 2], "ticks pass through midnight in order")
	_check(GameClock.day == 4, "day rolls over during advance")
	_check(absf(GameClock.hours - 2.0) < 0.001, "clock lands on the right hour")
	_check(absf(GameClock.hours_delta(3600.0) - 1.0) < 0.001,
		"1:1 time — one real hour is one game hour")
	var day_before: int = GameClock.day
	GameClock.return_to_now()
	_check(absf(GameClock.hours - GameClock.civil_now()) < 0.01,
		"return_to_now re-anchors to real local time")
	_check(GameClock.day == day_before, "return_to_now keeps days lived")


## Seasons follow the real calendar; daylight, solar noon, and the
## solar-hour warp derive from the real date and the player's location.
func _test_seasons() -> void:
	_check(GameClock.season_for({"month": 1, "day": 15}) == "winter", "january is winter")
	_check(GameClock.season_for({"month": 3, "day": 19}) == "winter", "mar 19 still winter")
	_check(GameClock.season_for({"month": 3, "day": 20}) == "spring", "mar 20 turns spring")
	_check(GameClock.season_for({"month": 7, "day": 2}) == "summer", "july is summer")
	_check(GameClock.season_for({"month": 10, "day": 5}) == "autumn", "october is autumn")
	_check(GameClock.season_for({"month": 12, "day": 21}) == "winter", "dec 21 turns winter")
	_check(GameClock.season_for({"month": 12, "day": 25}, true) == "summer",
		"southern hemisphere flips the season")
	var solstice_summer: float = GameClock.daylight_hours_for(172, 45.0)
	var solstice_winter: float = GameClock.daylight_hours_for(355, 45.0)
	_check(solstice_summer > 15.0, "summer solstice daylight is long at 45N")
	_check(solstice_winter < 9.0, "winter solstice daylight is short at 45N")
	_check(absf(GameClock.daylight_hours_for(172, 0.0) - 12.1) < 0.3,
		"equator stays near 12h year round")
	_check(GameClock.daylight_hours_for(172, -45.0) < 9.0,
		"southern winter in june")
	_check(GameClock.daylight_hours_for(172, 89.0) <= 23.5,
		"polar day clamps — the sun always sets")
	_check(GameClock.season != "", "live season is set")
	_check(WorldState.get_value("time.season") == GameClock.season,
		"season mirrored to WorldState")
	var span: Vector2 = GameClock.daylight_span()
	_check(span.y > span.x, "sunrise precedes sunset")
	var today_dl: float = GameClock.daylight_hours_for(
		GameClock.day_of_year(Time.get_date_dict_from_system()), Settings.latitude)
	_check(absf((span.y - span.x) - today_dl) < 0.01,
		"span width matches the sunrise equation")
	GameClock.hours = fposmod(span.x, 24.0)
	_check(absf(GameClock.solar_hours() - 6.0) < 0.01, "sunrise maps to solar 6:00")
	GameClock.hours = fposmod(span.y - 0.001, 24.0)
	_check(absf(GameClock.solar_hours() - 18.0) < 0.05, "sunset maps to solar 18:00")
	GameClock.hours = fposmod((span.x + span.y) * 0.5, 24.0)
	_check(absf(GameClock.solar_hours() - 12.0) < 0.01, "solar noon maps to 12:00")


## Water contract on the Strata world: authored lakes/rivers retired, so
## the water language must hold with only the world sea present.
func _test_water() -> void:
	# The authored-body arrays are valid (possibly empty) — no crash on
	# a world Strata dressed without hand-placed lakes/rivers.
	_check(Terrain.water_bodies is Array, "water_bodies is a valid (maybe empty) list")
	_check(Terrain.rivers is Array, "rivers is a valid (maybe empty) list")
	# The world sea level loads from the record.
	_check(Terrain.sea_level > -1e11, "the world sea level loads from the record")
	# The home valley is guarded OUT of the open sea (home_guard is 0 in the
	# protected interior). With the authored pond retired, its center is dry.
	var wc := Vector2(65.0, -285.0)  # the watershed center — inside the guard
	_check(Terrain.home_guard(wc.x, wc.y) == 0.0, "home valley sits inside the guard")
	_check(Terrain.water_surface(wc.x, wc.y) < -1e6,
		"no water in the guarded home interior once the pond is retired")
	# Everything beyond the guard is the open world sea.
	_check(Terrain.home_guard(9000.0, 9000.0) > 0.0, "the open world lies outside the guard")
	_check(is_equal_approx(Terrain.water_surface(9000.0, 9000.0), Terrain.sea_surface()),
		"the world sea fills everything outside the home guard")


## W1 ocean swell: presentation-only (off headless), but its energy math
## is a pure function — pin the herald: storm swell precedes the storm,
## grows monotonically as the front nears, peaks overhead, and a calm
## sea still breathes. Physics stays flat: sea_surface() ignores swell.
func _test_swell() -> void:
	var wdir := Vector2(1.0, 0.0)
	var storm_at := func(edge: float) -> Array:
		return [{"kind": "storm", "dx": 1.0, "dz": 0.0, "edge": edge,
			"width": 4000.0, "speed": 4.0}]
	var focus := Vector2.ZERO
	var calm: Dictionary = SeaSwell.compute([], focus, 0.12, wdir)
	var far: Dictionary = SeaSwell.compute(storm_at.call(-8000.0), focus, 0.12, wdir)
	var near_f: Dictionary = SeaSwell.compute(storm_at.call(-2000.0), focus, 0.12, wdir)
	var over: Dictionary = SeaSwell.compute(storm_at.call(1000.0), focus, 0.12, wdir)
	_check(float(calm.amp) > 0.0, "a calm sea still breathes")
	_check(float(far.amp) < float(near_f.amp), "swell grows as the storm nears")
	_check(float(near_f.amp) < float(over.amp), "an overhead storm rolls hardest")
	_check(float(over.amp) > 3.0 * float(calm.amp),
		"storm swell reads far bigger than calm")
	_check(String(near_f.source) == "storm",
		"an approaching storm owns the swell before its rain arrives")
	_check(float(near_f.len) > float(calm.len), "heavy swell runs longer wavelengths")
	_check(Vector2(near_f.dir).is_equal_approx(wdir),
		"swell travels the front's own heading")
	# The sea the sim sees is untouched: flat level + tide only.
	var flat_sea: float = Terrain.sea_surface()
	_check(absf(flat_sea - Terrain.sea_level) <= Terrain.TIDE_AMP + 1e-4,
		"sea_surface() stays flat-sea + tide — the swell is presentation only")


func _test_hydrology() -> void:
	# One tick builds the catchments from real flow routing.
	var was_state: String = Weather.state
	var was_wet: float = Climate.wetness
	Weather.force_kind("calm")
	Climate.wetness = 0.5
	# The domain comes from the watershed record, not code (the map is
	# replaceable; the system isn't).
	_check(Hydrology.center == Vector2(65.0, -285.0) and Hydrology.domain == 2048.0,
		"watershed domain loads from data/water/watersheds/home.json")
	# With the authored pond/brook retired, the watershed routes and runs
	# its hourly balance over empty water — it must not crash, and its
	# level dicts stay valid (empty is fine until Strata proposes rivers).
	for i in 6:
		Hydrology._hourly(0)
	_check(Hydrology.lake_level is Dictionary and Hydrology.river_storage is Dictionary,
		"hydrology runs clean with no authored water bodies")
	for id in Hydrology.lake_level:
		var lv: float = Hydrology.lake_level[id]
		_check(lv >= Hydrology.LAKE_LEVEL_MIN and lv <= Hydrology.LAKE_LEVEL_MAX,
			"any lake level stays on its rails")
	# Snowmelt catch-up (audit finding): _last_snow must resume from the
	# SAVED snow, not boot's 0.0 — else the first replayed hour after a
	# snowy reload drops that hour's meltwater and rivers/lakes diverge
	# from continuous play. Simulate restore: set the saved key, corrupt
	# _last_snow to the boot value, reload.
	var saved_snow: float = float(WorldState.get_value("climate.snow", 0.0))
	WorldState.set_value("climate.snow", 0.4)
	Hydrology._last_snow = 0.0
	Hydrology.load_state()
	_check(is_equal_approx(Hydrology._last_snow, 0.4),
		"load_state resumes _last_snow from saved snow (no dropped meltwater)")
	WorldState.set_value("climate.snow", saved_snow)
	Hydrology._last_snow = Climate.snow
	Weather.force_kind(was_state)
	Climate.wetness = was_wet


func _test_water_field() -> void:
	# Tier 2 is presentation: headless (no RenderingDevice) it stays off,
	# and the whole game must run without it — the canonical water is
	# Hydrology. The scene-test runner is headless, so this is the
	# disabled path, and it must never crash a caller.
	_check(not WaterField.enabled, "tier-2 field disabled without a GPU (headless)")
	_check(WaterField.depth_at(Vector3(70, 0, -310)) == 0.0,
		"field depth reads 0 when disabled")
	# The current fallback is the real gameplay path when the field is off.
	# With the authored rivers retired there is no discharge to push, so
	# dry ground reads zero current everywhere — and nothing crashes.
	_check(WaterField.current_at(Vector3(200, 0, -100)) == Vector2.ZERO,
		"no current on dry ground")
	_check(not WaterWaves.enabled, "tier-2.5 wave field disabled without a GPU")
	# The wave kernel spec (CPU reference = what the GLSL must do):
	# a dent rings OUTWARD, total energy DECAYS, nothing blows up.
	var n := 48
	var prev := PackedFloat32Array()
	prev.resize(n * n)
	var curr := prev.duplicate()
	curr[24 * n + 24] = -0.05  # the splat: a pressed dent
	prev[24 * n + 24] = -0.05
	var e0 := WaveReference.energy(curr)
	var reached_at := -1
	for step_i in 40:
		var next := WaveReference.step(prev, curr, n)
		prev = curr
		curr = next
		if reached_at < 0 and absf(curr[24 * n + 34]) > 0.0005:
			reached_at = step_i  # the ring arrived 10 cells out
	_check(reached_at > 5, "waves propagate at finite speed (arrived step %d)" % reached_at)
	var e1 := WaveReference.energy(curr)
	_check(e1 < e0 and e1 > 0.0, "wave energy decays but persists (%.5f -> %.5f)" % [e0, e1])
	var bounded := true
	for v in curr:
		if not is_finite(v) or absf(v) > 0.1:
			bounded = false
	_check(bounded, "wave field stays bounded (CFL-stable at K=%.2f)" % WaveReference.K)
	_check(is_equal_approx(WaveReference.K, WaveGpu.K)
			and is_equal_approx(WaveReference.DAMP, WaveGpu.DAMP),
		"CPU reference constants match the GPU driver")
	# Every compute kernel must compile to SPIR-V — headless CI never
	# creates a RenderingDevice, so import-time compilation is the only
	# GLSL check any CI can run. Catches syntax errors before a human
	# hits them in a windowed session.
	for kernel in ["sand_apply", "sand_relax", "sand_copy",
			"water_flux", "water_depth", "water_probe",
			"wave_splat", "wave_step", "wave_copy"]:
		var src: RDShaderFile = load("res://game/shaders/compute/%s.glsl" % kernel)
		var ok := src != null and src.get_spirv() != null \
			and src.get_spirv().compile_error_compute == ""
		_check(ok, "compute kernel compiles: " + kernel)


func _test_climate() -> void:
	# Temperature falls with elevation (lapse). Find the lowest and highest of a
	# broad sample — robust to whatever Strata world is loaded, not the old valley.
	var lo_p := Vector2.ZERO
	var hi_p := Vector2.ZERO
	var lo_h := 1e12
	var hi_h := -1e12
	for gx in range(-4, 5):
		for gz in range(-4, 5):
			var p := Vector2(gx * 700.0, gz * 700.0)
			var ph := Terrain.height(p.x, p.y)
			if ph < lo_h:
				lo_h = ph
				lo_p = p
			if ph > hi_h:
				hi_h = ph
				hi_p = p
	_check(Climate.temperature(hi_p.x, hi_p.y) < Climate.temperature(lo_p.x, lo_p.y),
		"higher ground runs colder (lapse rate)")
	var span: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span.x - 2.0, 24.0)  # before dawn
	var predawn: float = Climate.temperature(0.0, -100.0)
	GameClock.hours = fposmod((span.x + span.y) * 0.5 + 3.0, 24.0)  # mid-afternoon
	var afternoon: float = Climate.temperature(0.0, -100.0)
	_check(predawn < afternoon, "pre-dawn is colder than mid-afternoon")
	var was_state: String = Weather.state
	var was_wet: float = Climate.wetness
	Weather.force_kind("storm")
	Climate.wetness = 0.2
	Climate._hourly(0)
	_check(Climate.wetness > 0.2, "storm hours soak the ground")
	Weather.force_kind("calm")
	var wet: float = Climate.wetness
	Climate._hourly(0)
	_check(Climate.wetness < wet, "calm hours dry the ground")
	_check(float(WorldState.get_value("climate.wetness")) == Climate.wetness,
		"wetness mirrored to WorldState")
	_check(Climate.snow_line_for(20.0) > Climate.snow_line_for(2.0),
		"warm air lifts the snowline")
	_check(Climate.snow_line_for(-3.0) < 0.0,
		"a freezing floor drops the snowline below the valley")
	var was_snow: float = Climate.snow
	Weather.force_kind("calm")
	Climate.snow = 0.5
	Climate.wetness = 0.1
	Climate._hourly(0)
	_check(Climate.snow < 0.5, "warm calm hours melt the snow")
	_check(Climate.wetness > 0.0, "meltwater soaks the ground")
	Climate.snow = was_snow
	Weather.force_kind(was_state)
	Climate.wetness = was_wet
	Weather._transition(0)


## Climate v2 phase 1: the rain shadow and the wetness field.
func _test_climate_v2() -> void:
	# Wet air crossing a big wall must leave its lee dry. The test FINDS
	# its wall on whatever world is loaded (the old version was pinned to
	# the retired Range's coordinates): the tallest point on a coarse
	# grid, wind blown in off the nearest sea. It steps aside when the
	# world has no wall worth the name — matching the physics, where only
	# a big sustained barrier wrings the air dry (ORO_CLEAR/ORO_DEEP).
	var peak := Vector2.ZERO
	var peak_h := -1e12
	for gx in range(-14, 15):
		for gz in range(-14, 15):
			var pp := Vector2(gx * 512.0, gz * 512.0)
			var ph := Terrain.height(pp.x, pp.y)
			if ph > peak_h:
				peak_h = ph
				peak = pp
	# Wind travel direction: in off the nearest cardinal sea, over the
	# peak, into the lee (axis-aligned keeps the probe points in separate
	# 2048m wetness cells).
	var d := Vector2.ZERO
	var sea_dist := 1e12
	for card: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2(0, 1), Vector2(0, -1)]:
		for step in range(1, 26):
			var sp := peak + card * (step * 400.0)
			if Terrain.height(sp.x, sp.y) < Terrain.sea_level:
				if step * 400.0 < sea_dist:
					sea_dist = step * 400.0
					d = -card  # air arrives FROM the sea side
				break
	# The peak sits at a probe distance the lee's upwind scan samples
	# exactly (ORO_UP includes 1300m).
	var lee_probe := peak + d * 1300.0
	var excess := peak_h - maxf(Terrain.height(lee_probe.x, lee_probe.y), 0.0)
	if d == Vector2.ZERO or excess < 400.0:
		print("  (skip rain shadow: no wall tall enough on this world — peak %.0fm, excess %.0fm)"
				% [peak_h, excess])
	else:
		var was_angle: float = Weather._wind_angle
		var was_wet: float = Climate.wetness
		var was_snow: float = Climate.snow
		Weather._wind_angle = d.angle()
		Weather.wind_dir = d
		Weather.force_kind("storm")
		var wind_pt := peak - d * 1300.0
		var lee_pt := lee_probe
		var rain_wind: float = Weather.rain_at(wind_pt.x, wind_pt.y)
		var rain_lee: float = Weather.rain_at(lee_pt.x, lee_pt.y)
		_check(rain_wind > rain_lee * 1.5,
			"rain shadow: windward %.2f vs lee %.2f" % [rain_wind, rain_lee])
		# The wetness field diverges under that sky: the windward cell
		# soaks fast while the lee cell only creeps (a long enough storm
		# would eventually soak both — the shadow buys TIME, not immunity).
		Climate.wetness = 0.3
		for i in 5:
			Climate._hourly(0)
		_check(Climate.wetness_at(wind_pt.x, wind_pt.y)
				> Climate.wetness_at(lee_pt.x, lee_pt.y) + 0.1,
			"wetness field: windward soaks, the lee lags")
		Climate.wetness = was_wet
		Climate.snow = was_snow
		Weather._wind_angle = was_angle
		Weather.wind_dir = Vector2.from_angle(was_angle)
		Weather.force_kind("calm")
	# Legacy migration: a save with only the scalar floods the field.
	var keep_wet: float = Climate.wetness
	WorldState.set_value("climate.wet_grid", null)
	WorldState.set_value("climate.wetness", 0.42)
	Climate.load_state()
	_check(absf(Climate.wetness - 0.42) < 0.001,
		"legacy scalar migrates into the field")
	_check(absf(Climate.wetness_at(-6000.0, 6000.0) - 0.42) < 0.001,
		"migration floods every cell")
	Climate.wetness = keep_wet
	# Phase 2 — the thermal field. Aspect is pure: slopes facing the
	# sun's current bearing run warmer, nothing at night or under the
	# noon zenith, and mirrored slopes mirror.
	_check(Climate.aspect_term(-0.5, 9.0) > 0.3,
		"morning warms the east-facing slope")
	_check(Climate.aspect_term(-0.5, 15.0) < -0.3,
		"the same slope cools in the afternoon shade")
	_check(absf(Climate.aspect_term(-0.5, 12.0)) < 0.01,
		"the zenith sun plays no favorites")
	_check(Climate.aspect_term(-0.5, 0.0) == 0.0, "no aspect at night")
	_check(absf(Climate.aspect_term(0.5, 9.0) + Climate.aspect_term(-0.5, 9.0)) < 0.001,
		"mirrored slopes mirror")
	# Maritime: the swing damps with sea proximity. World-agnostic: find
	# one fully-inland land point (no sea in its 1.8km cross → swing 1.0)
	# and one open-sea point on the same coarse grid, and the sea point
	# must read more maritime. Skips only when the world lacks one side.
	var ref_swing: float = Climate._swing(Climate.REFERENCE.x, Climate.REFERENCE.y)
	_check(ref_swing >= Climate.MARITIME_SWING and ref_swing <= 1.0,
		"reference swing bounded (%.2f)" % ref_swing)
	var inland := Vector2.INF
	var offshore := Vector2.INF
	for gx in range(-14, 15):
		for gz in range(-14, 15):
			var mp := Vector2(gx * 512.0, gz * 512.0)
			var mh := Terrain.height(mp.x, mp.y)
			if inland.x == INF and mh > Terrain.sea_level + 5.0 \
					and Climate._swing(mp.x, mp.y) >= 0.999:
				inland = mp
			elif offshore.x == INF and mh < Terrain.sea_level \
					and Climate._swing(mp.x, mp.y) <= Climate.MARITIME_SWING + 0.1:
				offshore = mp
	if inland.x == INF or offshore.x == INF:
		print("  (skip maritime: world lacks a deep-inland or open-sea point)")
	else:
		_check(Climate._swing(offshore.x, offshore.y) < Climate._swing(inland.x, inland.y),
			"open water reads more maritime than deep inland")
	# The reference reads base temperature minus its own altitude lapse (not
	# pinned to a flat valley floor any more — the reference sits on real terrain).
	var ref_h := maxf(Terrain.height(Climate.REFERENCE.x, Climate.REFERENCE.y), 0.0)
	_check(absf(Climate.temperature(Climate.REFERENCE.x, Climate.REFERENCE.y)
			- (Climate.base_temperature() - Climate.LAPSE * ref_h)) < 3.0,
		"temperature at the reference follows the lapse rate")
	# Phase 3 — humidity. Same point, same wind: only the pinned factor
	# moves, so these hold on any map.
	_check(Climate._humidity_for(0.0, -150.0, 0.5, 10.0)
			> Climate._humidity_for(0.0, -150.0, 0.5, 700.0),
		"the air thins dry with altitude")
	_check(Climate._humidity_for(0.0, -150.0, 0.9, 10.0)
			> Climate._humidity_for(0.0, -150.0, 0.1, 10.0),
		"wet ground humidifies the air above it")
	Weather.force_kind("calm")
	var hum_calm: float = Climate.humidity(Climate.REFERENCE.x, Climate.REFERENCE.y)
	Weather.force_kind("storm")
	_check(Climate.humidity(Climate.REFERENCE.x, Climate.REFERENCE.y) > hum_calm + 0.1,
		"a wet front saturates the air")
	Weather.force_kind("calm")
	# Dew at dawn: humid, still, pre-dawn air WETS the ground instead of
	# drying it. Wind set so the upwind probes reach the east sea.
	var was_angle2: float = Weather._wind_angle
	var was_hours: float = GameClock.hours
	Weather.wind_dir = Vector2(-1.0, 0.0)
	Weather._wind_angle = Weather.wind_dir.angle()
	var span2: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span2.x - 1.0, 24.0)  # ~solar 5: the dew window
	Climate.wetness = 0.75
	Climate._hourly(0)
	_check(Climate.wetness > 0.76,
		"pre-dawn saturated air dews the ground (%.3f)" % Climate.wetness)
	GameClock.hours = was_hours
	Weather._wind_angle = was_angle2
	Weather.wind_dir = Vector2.from_angle(was_angle2)
	Climate.wetness = keep_wet
	# The Toolkit sees all of it: the world panel's HERE block composes
	# every per-position query without a camera (falls back to the
	# valley), and the substrate summaries carry the new numbers.
	var here: String = Toolkit._here_summary()
	for token in ["hum=", "wet=", "swing=", "aspect=", "stage=", "biome=", "snowline"]:
		_check(here.contains(token), "world panel HERE block carries " + token)
	_check(Climate.summary().contains("hum("), "Climate summary carries humidity")
	_check(Weather.summary().contains("oro="), "Weather summary carries the oro factor")
	_check(absf(Weather.wind_dir.length() - 1.0) < 0.001,
		"wind direction stays a unit vector as it wanders")


## Flora lifecycle: vitality chases climate, flags latch story-seeds.
func _test_flora() -> void:
	_check(FloraLife.target_for("spring", 0.8, 18.0) > FloraLife.target_for("winter", 0.8, 18.0),
		"spring outgrows winter")
	_check(FloraLife.target_for("summer", 0.1, 34.0) < FloraLife.target_for("summer", 0.7, 22.0),
		"hot and dry starves the flora")
	var was_v: float = FloraLife.vitality
	var was_wet: float = Climate.wetness
	Climate.wetness = 0.0
	FloraLife.vitality = 0.1
	WorldState.set_value("valley.parched", false)
	WorldState.set_value("valley.bloom", false)
	FloraLife._hourly(0)
	_check(WorldState.has_flag("valley.parched"), "dry + starved flora -> parched flag")
	Climate.wetness = 1.0
	FloraLife.vitality = 0.9
	FloraLife._hourly(0)
	_check(WorldState.has_flag("valley.bloom"), "soaked + thriving flora -> bloom flag")
	_check(not WorldState.has_flag("valley.parched"), "recovery clears parched")
	# v2 — species records: loaded, validated, art slots fall back to grow.
	_check(FloraLife.species.size() >= 6, "species records loaded")
	var tuft: Dictionary = {}
	for def: Dictionary in FloraLife.species:
		if str(def.id) == "bloom_tuft":
			tuft = def
	_check(not tuft.is_empty(), "bloom_tuft record exists")
	_check(FloraLife.stage_art(tuft, "bloom") == FloraLife.stage_art(tuft, "grow"),
		"missing stage art falls back to grow (same placeholder slots)")
	_check(str(tuft.get("yields", "")) == "dried_bloom", "bloom_tuft yields dried_bloom")
	# Lifecycle stages are a pure function of season + vitality.
	_check(FloraLife.stage_for("spring", 0.9) == "bloom", "lush spring blooms")
	_check(FloraLife.stage_for("spring", 0.4) == "sprout", "lean spring sprouts")
	_check(FloraLife.stage_for("autumn", 0.7) == "seed", "autumn seeds")
	_check(FloraLife.stage_for("summer", 0.2) == "dry", "parched flora reads dry")
	# Species composition: biome weights + the moisture gate.
	_check(FloraLife.species_weight(tuft, "oasis_green", 0.8) > 0.0,
		"tufts grow in the oasis")
	_check(FloraLife.species_weight(tuft, "bare_peak", 0.8) == 0.0,
		"no tufts on bare peaks")
	_check(FloraLife.species_weight(tuft, "oasis_green", 0.8)
			> FloraLife.species_weight(tuft, "oasis_green", 0.0),
		"drought gates the thirsty species down")
	# Spatial vitality is stateless: it tracks the live moisture field, so
	# the same point reads greener when the ground is wet than when it's dry.
	FloraLife.vitality = 0.5
	Climate.wetness = 0.1
	var dry_v: float = FloraLife.vitality_at(0.0, 0.0)
	Climate.wetness = 0.9
	var wet_v: float = FloraLife.vitality_at(0.0, 0.0)
	_check(wet_v >= dry_v and is_finite(wet_v) and wet_v > 0.0 and wet_v <= 1.0,
		"spatial vitality tracks local moisture (%.3f dry -> %.3f wet)" % [dry_v, wet_v])
	# Honest harvest: gathering wounds the cell, hours heal it, and a
	# healed cell is forgotten (the save only remembers open wounds).
	var cell := Vector2i(0, -3)  # floor((70,-310)/128)
	FloraLife.harvest_at(70.0, -310.0)
	_check(FloraLife.depletion(cell) > 0.0, "gathering wounds the cell")
	_check(not (WorldState.get_value("flora.cells", {}) as Dictionary).is_empty(),
		"wound mirrored to WorldState")
	var before: float = FloraLife.depletion(cell)
	FloraLife._regrow()
	var after: float = FloraLife.depletion(cell)
	_check(after < before and after > 0.0, "an hour regrows a little, not all")
	for i in 400:
		FloraLife._regrow()
	_check(FloraLife.depletion(cell) == 0.0, "the wound heals in time")
	_check((WorldState.get_value("flora.cells", {}) as Dictionary).is_empty(),
		"healed cells are forgotten — save stays lean")
	# Depletion survives a save/load (load_state re-reads the mirror).
	FloraLife.harvest_at(-500.0, 900.0)
	FloraLife.load_state()
	_check(FloraLife.depletion(Vector2i(-4, 7)) > 0.0, "depletion survives load_state")
	for i in 400:
		FloraLife._regrow()
	FloraLife.vitality = was_v
	Climate.wetness = was_wet
	WorldState.set_value("valley.bloom", false)
	WorldState.set_value("valley.parched", false)


## Moon phase: real synodic cycle, stateless in real time.
func _test_moon() -> void:
	var epoch: float = GameClock.NEW_MOON_EPOCH
	_check(GameClock.moon_phase_at(epoch) < 0.001, "epoch is a new moon")
	var half: float = GameClock.SYNODIC_DAYS * 0.5 * 86400.0
	_check(absf(GameClock.moon_phase_at(epoch + half) - 0.5) < 0.001,
		"half a synodic month later is full")
	var full_light := 0.5 - 0.5 * cos(TAU * 0.5)
	_check(absf(full_light - 1.0) < 0.001, "full moon is fully lit")
	var phase: float = GameClock.moon_phase()
	_check(phase >= 0.0 and phase < 1.0, "live phase in range")


## Wildlife tier-3: pure-data animals live full days without a body.
func _test_wildlife() -> void:
	var mgr: Node = load("res://game/wildlife/wildlife_manager.gd").new()
	var herd: Dictionary = mgr.spawn_herd({
		"id": "test_herd", "count": 2.0,
		"home": {"x": 0.0, "z": 0.0}, "range": 100.0,
		"activities": [
			{"id": "drink", "at": {"x": 50.0, "z": 0.0}, "satisfies": "thirst",
				"rate": 16.0, "hours": [5.0, 9.0]},
			{"id": "prowl", "at": "roam", "satisfies": "wander", "rate": 5.0},
		]})
	var sim: AgentSim = herd.individuals[0].sim
	var span: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span.x + 1.0, 24.0)  # solar ~7:00, drink window
	sim.needs.thirst = 10.0
	sim.needs.wander = 90.0
	sim.decide()
	_check(sim.current.id == "drink", "thirsty animal heads to water at dawn")
	var start: Vector2 = sim.pos
	sim.advance(1.0)
	_check((sim.pos - Vector2(50.0, 0.0)).length() < 12.0,
		"an hour of data-tier time completes the journey")
	_check(sim.pos != start, "data animal moved without a body")
	sim.advance(1.0)  # arrived: this hour is spent drinking
	_check(sim.needs.thirst > 10.0, "drinking satisfies thirst")
	mgr._save_state()
	var rows: Array = WorldState.get_value("wildlife.test_herd", [])
	_check(rows.size() == 2, "herd persists to WorldState")
	# Herd cohesion: roam draws near the group's heart, not anywhere.
	for i in herd.individuals.size():
		herd.individuals[i].sim.pos = Vector2(20.0 * i, 0.0)
	mgr._update_cohesion(herd)
	var roamer: AgentSim = herd.individuals[1].sim
	_check(roamer.roam_center.is_finite(), "cohesion sets the herd's heart")
	var roam_spot: Vector2 = roamer.resolve_at({"at": "roam"})
	_check((roam_spot - roamer.roam_center).length() <= roamer.cohesion_radius + 0.1,
		"roam targets stay with the herd")
	mgr.free()  # after every mgr use — a freed Node here cost a long bisect
	var body_script := load("res://game/wildlife/wildlife_body.gd")
	var noon: float = body_script.sense_range_for(12.0, 0.0)
	var dark: float = body_script.sense_range_for(0.0, 0.0)
	var moonlit: float = body_script.sense_range_for(0.0, 1.0)
	_check(noon > dark, "creatures see farther by day than by night")
	_check(moonlit > dark, "a full moon lends the night some sight")
	_check(noon > moonlit, "but never as much as the sun")


## Desire paths persist: footsteps wear permanent cells that fade over
## hours and survive a save/load. (The pantry/rumor long-memory retired
## with the authored inhabitants — it lived on the NPC bodies.)
func _test_wear() -> void:
	var spot := Vector2(4321.5, -4321.5)  # far from any real trail
	for i in 5:
		InteractionField.stamp(spot)
		InteractionField._clock += 30.0  # crowding guard: wear needs revisits, not shuffling
	var snap: Dictionary = InteractionField.wear_snapshot()
	var key := "4321_-4322"
	_check(snap.has(key), "footsteps wear a permanent cell")
	_check(float(snap[key]) > 0.15, "repeated walking deepens the wear")
	InteractionField._age_wear(0)
	var aged: Dictionary = InteractionField.wear_snapshot()
	_check(float(aged[key]) < float(snap[key]), "unwalked paths fade over hours")
	InteractionField.wear_restore(snap)
	_check(absf(float(InteractionField.wear_snapshot()[key]) - float(snap[key])) < 0.002,
		"wear survives a save/load roundtrip")
	InteractionField.wear_restore({})  # leave no test residue in the field


## Near-tier navigation: bake from faces, path across, fall back cleanly.
func _test_nav() -> void:
	# A 20x20m plane in the streamer's exact triangle winding.
	var res := 11
	var step := 2.0
	var faces := PackedVector3Array()
	for iz in res - 1:
		for ix in res - 1:
			var a := Vector3(ix * step, 0.0, iz * step)
			var b := Vector3((ix + 1) * step, 0.0, iz * step)
			var c := Vector3(ix * step, 0.0, (iz + 1) * step)
			var d := Vector3((ix + 1) * step, 0.0, (iz + 1) * step)
			faces.append_array([a, b, c, b, d, c])
	var navmesh: NavigationMesh = Nav.bake_navmesh(faces)
	_check(navmesh.get_polygon_count() > 0, "bake produces walkable polygons")
	var cell := Vector2i(999, 999)
	var origin := Vector3(9990.0, 0.0, 9990.0)
	Nav.add_cell(cell, navmesh, origin)
	NavigationServer3D.map_force_update(Nav._map)
	var p: PackedVector3Array = Nav.path(
		origin + Vector3(2.0, 0.5, 2.0), origin + Vector3(18.0, 0.5, 18.0))
	_check(p.size() >= 2, "path across the baked cell")
	_check(p[p.size() - 1].distance_to(origin + Vector3(18.0, 0.0, 18.0)) < 2.5,
		"path reaches the goal")
	Nav.remove_cell(cell)
	var fallback: PackedVector3Array = Nav.path(Vector3.ZERO, Vector3(10.0, 0.0, 10.0))
	_check(fallback.size() == 2, "no navmesh -> straight-line fallback")


## The granular kernel: sand is conserved, spikes slump to repose, flows
## spread — pure math, no thread, no rendering.
func _test_sand_sim() -> void:
	var g := 16
	var delta_field := PackedFloat32Array()
	delta_field.resize(g * g)
	var base := PackedFloat32Array()
	base.resize(g * g)
	var active := PackedInt32Array()
	var queued := PackedByteArray()
	queued.resize(g * g)
	var center := (g / 2) * g + g / 2
	delta_field[center] = 0.3
	queued[center] = 1
	active.append(center)
	var before := 0.0
	for i in g * g:
		before += delta_field[i]
	for step in 300:
		SandField.relax(delta_field, base, active, queued, g, 0.04, 0.3, 4000)
	var after := 0.0
	var peak := 0.0
	for i in g * g:
		after += delta_field[i]
		peak = maxf(peak, delta_field[i])
	_check(absf(after - before) < 0.0005, "sand is conserved through avalanches")
	_check(peak < 0.29, "a spike slumps toward the angle of repose")
	_check(delta_field[center - 1] > 0.0, "material flows to the neighbors")
	# Steep base terrain: material walks downhill across cells.
	var slope_delta := PackedFloat32Array()
	slope_delta.resize(g * g)
	var slope_base := PackedFloat32Array()
	slope_base.resize(g * g)
	for y in g:
		for x in g:
			slope_base[y * g + x] = -x * 0.1  # falls to +x
	var a2 := PackedInt32Array()
	var q2 := PackedByteArray()
	q2.resize(g * g)
	var mid := (g / 2) * g + 3
	slope_delta[mid] = 0.25
	q2[mid] = 1
	a2.append(mid)
	for step in 300:
		SandField.relax(slope_delta, slope_base, a2, q2, g, 0.04, 0.3, 4000)
	var right := 0.0
	var left := 0.0
	for y in g:
		for x in g:
			if x >= 6:
				right += slope_delta[y * g + x]
			elif x <= 2:
				left += slope_delta[y * g + x]
	_check(right > 0.06 and right > left * 2.0, "piled sand avalanches downhill")
