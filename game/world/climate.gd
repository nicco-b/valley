extends Node
## Climate (autoload): the shared substrate — two numbers everything reads.
##   temperature(x, z): stateless — season (via daylight length, so it is
##     hemisphere- and latitude-correct for free), time of day (solar),
##     altitude lapse, storm chill.
##   moisture(x, z): one global wetness state (rain soaks, warmth dries)
##     lifted near open water.
## Consumers: flora vitality, wet-ground rendering (ground_wetness global
## shader param), biome mask later, NPC comfort later. New systems should
## read these fields, never roll their own weather-derived logic.
##
## Sim contract: wetness is the only state; it advances on hour_tick, so
## closed/asleep stretches replay correctly through GameClock.advance_hours,
## and it persists via WorldState ("climate.wetness").

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

var wetness := 0.25  # 0 dust-dry .. 1 soaked (global; regional when weather is)
var snow := 0.0  # 0..1 cover above the snowline

var _shader_wetness := 0.25
var _shader_snow := 0.0


func _ready() -> void:
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	load_state()
	GameClock.hour_tick.connect(_hourly)


func load_state() -> void:
	wetness = float(WorldState.get_value("climate.wetness", wetness))
	snow = float(WorldState.get_value("climate.snow", snow))
	_shader_wetness = wetness
	_shader_snow = snow


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-EASE * delta)
	_shader_wetness = lerpf(_shader_wetness, wetness, blend)
	_shader_snow = lerpf(_shader_snow, snow, blend)
	RenderingServer.global_shader_parameter_set("ground_wetness", _shader_wetness)
	RenderingServer.global_shader_parameter_set("snow_cover", _shader_snow)
	RenderingServer.global_shader_parameter_set("snow_line", snow_line())


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


## Ground moisture at a position: the global wetness, lifted near open
## water (pond banks stay damp through a dry spell).
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
	return clampf(maxf(wetness, 0.85 * near), 0.0, 1.0)


func _hourly(_h: int) -> void:
	var t := temperature(REFERENCE.x, REFERENCE.y)
	if Weather.state == "storm":
		wetness = minf(wetness + RAIN_RATE, 1.0)
	else:
		wetness = maxf(wetness - BASE_DRY_RATE - WARM_DRY_RATE * maxf(t, 0.0), 0.0)
	# Snow falls in storms that reach freezing into the valley's relief;
	# melt runs off as wetness — spring mud comes free.
	if Weather.state == "storm" and snow_line() < 60.0:
		snow = minf(snow + SNOW_FALL, 1.0)
	elif snow > 0.0:
		var melt := minf(SNOW_MELT_BASE + SNOW_MELT_WARM * maxf(t, 0.0), snow)
		snow -= melt
		wetness = minf(wetness + melt * MELTWATER, 1.0)
	wetness = snappedf(wetness, 0.001)  # store what we keep: mirror stays exact
	snow = snappedf(snow, 0.001)
	WorldState.set_value("climate.wetness", wetness)
	WorldState.set_value("climate.snow", snow)
	WorldState.set_value("climate.temperature", snappedf(t, 0.1))
