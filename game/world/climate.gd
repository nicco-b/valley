extends Node
## Climate (autoload, the Elements): the shared substrate — two numbers
## everything reads.
##   temperature(x, z): stateless — season (via daylight length, so it is
##     hemisphere- and latitude-correct for free), time of day (solar),
##     altitude lapse, storm chill.
##   moisture(x, z): ground wetness at a position — the WETNESS FIELD
##     value there, lifted near open water.
## Consumers: flora vitality, wet-ground rendering (ground_wetness global
## shader param), biome mask later, NPC comfort later. New systems should
## read these fields, never roll their own weather-derived logic.
##
## The wetness FIELD (Climate v2 phase 1, 2026-07-05): one global scalar
## became an 8x8 grid of 2048m cells over the 16384m world frame. Each
## cell wets under the rain actually falling on IT (Weather.rain_at —
## which now carries the rain shadow, so the lee of the Range dries out
## while the windward flank soaks) and dries by its own temperature.
## `wetness` stays as a PROPERTY for compatibility: reading it gives the
## home-valley cell (everything anchored there — Hydrology runoff, fog
## in the valley, the soak line — keeps its meaning); assigning it
## flood-fills the whole field (the old global semantic, which is
## exactly what tests and dev knobs want).
##
## Sim contract: wetness field + snow are the state; they advance on
## hour_tick, so closed/asleep stretches replay correctly through
## GameClock.advance_hours, and persist via WorldState ("climate.wet_grid",
## legacy "climate.wetness" migrates old saves). No randomness.

const RAIN_RATE := 0.16  # wetness gained per storm hour (soaked in ~5h)
const BASE_DRY_RATE := 0.015  # wetness lost per hour at freezing
const WARM_DRY_RATE := 0.004  # extra drying per hour per degree above 0
const LAPSE := 0.06  # degrees lost per meter of altitude — ridges run colder
const SNOW_FALL := 0.12  # cover gained per storm hour when it's cold enough
const SNOW_MELT_BASE := 0.004
const SNOW_MELT_WARM := 0.01  # extra melt per degree above freezing
const MELTWATER := 0.4  # melted snow soaks the ground (spring mud, for free)
const EASE := 0.4  # per-second visual approach for the shader params
const REFERENCE := Vector2(70.0, -310.0)  # pond clearing: the valley's thermometer

# The wetness field frame (matches the guide/biome-map framing).
const GRID_N := 8
const GRID_ORIGIN := -8192.0
const GRID_CELL := 2048.0

var wet_grid := _fresh_grid()  # row-major GRID_N x GRID_N, 0 dust-dry .. 1 soaked
var snow := 0.0  # 0..1 cover above the snowline (global, valley-anchored)

## The home valley's wetness (get), or flood-fill the world (set — the
## legacy global semantic; only tests and dev knobs assign this).
var wetness: float:
	get:
		return wet_grid[_cell_index(REFERENCE.x, REFERENCE.y)]
	set(v):
		wet_grid.fill(clampf(v, 0.0, 1.0))

var _shader_wetness := 0.25
var _shader_snow := 0.0


static func _fresh_grid() -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(GRID_N * GRID_N)
	g.fill(0.25)
	return g


func _ready() -> void:
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	load_state()
	GameClock.hour_tick.connect(_hourly)


func load_state() -> void:
	var saved: Variant = WorldState.get_value("climate.wet_grid", null)
	if saved is Array and (saved as Array).size() == GRID_N * GRID_N:
		for i in GRID_N * GRID_N:
			wet_grid[i] = clampf(float(saved[i]), 0.0, 1.0)
	else:
		# Legacy save (or fresh world): the old global scalar floods the field.
		wetness = float(WorldState.get_value("climate.wetness", 0.25))
	snow = float(WorldState.get_value("climate.snow", snow))
	_shader_wetness = wetness
	_shader_snow = snow


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-EASE * delta)
	var fx := _focus_xz()
	_shader_wetness = lerpf(_shader_wetness, wetness_at(fx.x, fx.y), blend)
	_shader_snow = lerpf(_shader_snow, snow, blend)
	RenderingServer.global_shader_parameter_set("ground_wetness", _shader_wetness)
	RenderingServer.global_shader_parameter_set("snow_cover", _shader_snow)
	RenderingServer.global_shader_parameter_set("snow_line", snow_line())


func _focus_xz() -> Vector2:
	if GodMode.active:
		var p := GodMode.cam_position()
		return Vector2(p.x, p.z)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		return Vector2(player.global_position.x, player.global_position.z)
	return REFERENCE


func _cell_index(x: float, z: float) -> int:
	var cx := clampi(int((x - GRID_ORIGIN) / GRID_CELL), 0, GRID_N - 1)
	var cz := clampi(int((z - GRID_ORIGIN) / GRID_CELL), 0, GRID_N - 1)
	return cz * GRID_N + cx


## The wetness field at a position (nearest cell; the near-water floors
## in moisture() carry the fine grain).
func wetness_at(x: float, z: float) -> float:
	return wet_grid[_cell_index(x, z)]


## The valley-floor air, before altitude: season (via daylight length,
## so calendar/hemisphere come from GameClock), time of day (coldest
## pre-dawn, warmest mid-afternoon, flattened under storm cloud), storm
## chill.
func base_temperature() -> float:
	var span := GameClock.daylight_span()
	var seasonal := lerpf(0.0, 26.0, clampf(((span.y - span.x) - 8.5) / 7.0, 0.0, 1.0))
	var diurnal := -cos(TAU * (GameClock.solar_hours() - 3.0) / 24.0) \
			* 5.0 * (1.0 - 0.5 * Weather.storminess)
	return seasonal + diurnal - 3.0 * Weather.storminess


## Air temperature (degrees-ish; mood, not meteorology) at a position.
func temperature(x: float, z: float) -> float:
	return base_temperature() - LAPSE * maxf(Terrain.height(x, z), 0.0)


## The altitude where the air crosses freezing — the snowline literally
## falls out of the lapse rate. Summer noon: hundreds of meters overhead
## (no snow anywhere); a winter storm night: below the valley floor
## (everything whitens). The terrain shader draws it.
func snow_line() -> float:
	return base_temperature() / LAPSE


static func snow_line_for(base_t: float) -> float:
	return base_t / LAPSE


## Ground moisture at a position: the wetness field there, lifted near
## open water (pond banks stay damp through a dry spell).
func moisture(x: float, z: float) -> float:
	var near := 0.0
	for w in Terrain.water_bodies:
		var c: Vector2 = w.center
		var r: float = w.radius
		var d := Vector2(x - c.x, z - c.y).length()
		near = maxf(near, 1.0 - smoothstep(r, r + 18.0, d))
	for river in Terrain.rivers:
		var q := Terrain.river_query(river, x, z)
		near = maxf(near, 1.0 - smoothstep(q.half, q.half + 12.0, q.d))
	# The sea damps its shores by ELEVATION: anywhere outside the home
	# island within ~2.5m of sea level reads as wet strand (beaches,
	# causeway edges) — the tide line without a tide (yet).
	if Terrain.sea_level > -1e11 and Terrain.home_guard(x, z) > 0.0:
		var h: float = Terrain.height(x, z)
		near = maxf(near, 1.0 - smoothstep(
			Terrain.sea_level + 0.6, Terrain.sea_level + 2.5, h))
	return clampf(maxf(wetness_at(x, z), 0.85 * near), 0.0, 1.0)


## Toolkit: the substrate, one line — valley value plus field extremes.
func summary() -> String:
	var lo := 1.0
	var hi := 0.0
	for i in GRID_N * GRID_N:
		lo = minf(lo, wet_grid[i])
		hi = maxf(hi, wet_grid[i])
	return "wetness(valley)=%.2f field=[%.2f..%.2f] snow=%.2f snowline=%.0fm  t(valley)=%.1f  moisture(pond)=%.2f" % [
		wetness, lo, hi, snow, snow_line(),
		temperature(REFERENCE.x, REFERENCE.y),
		moisture(REFERENCE.x, REFERENCE.y)]


func _hourly(_h: int) -> void:
	var ref_t := temperature(REFERENCE.x, REFERENCE.y)
	# Snow first (valley-anchored, as before): freezing rainfall over the
	# valley's relief whitens; melt runs off as wetness everywhere below.
	var ref_rain := Weather.rain_at(REFERENCE.x, REFERENCE.y)
	var melt := 0.0
	if ref_rain > 0.05 and snow_line() < 60.0:
		snow = minf(snow + SNOW_FALL, 1.0)
	elif snow > 0.0:
		melt = minf(SNOW_MELT_BASE + SNOW_MELT_WARM * maxf(ref_t, 0.0), snow)
		snow -= melt
	snow = snappedf(snow, 0.001)
	# The field: every cell lives under ITS OWN sky — rain (with the
	# shadow already in it) soaks, local warmth dries, meltwater soaks.
	for i in GRID_N * GRID_N:
		var cx := GRID_ORIGIN + (float(i % GRID_N) + 0.5) * GRID_CELL
		var cz := GRID_ORIGIN + (float(i / GRID_N) + 0.5) * GRID_CELL
		var local_rain := Weather.rain_at(cx, cz)
		var w := wet_grid[i]
		if local_rain > 0.05:
			w = minf(w + RAIN_RATE * local_rain, 1.0)
		else:
			w = maxf(w - BASE_DRY_RATE
					- WARM_DRY_RATE * maxf(temperature(cx, cz), 0.0), 0.0)
		wet_grid[i] = snappedf(minf(w + melt * MELTWATER, 1.0), 0.001)
	WorldState.set_value("climate.wetness", wetness)
	WorldState.set_value("climate.snow", snow)
	WorldState.set_value("climate.temperature", snappedf(ref_t, 0.1))
	var out: Array = []
	for i in GRID_N * GRID_N:
		out.append(wet_grid[i])
	WorldState.set_value("climate.wet_grid", out)
