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
const EASE := 0.4  # per-second visual approach for the shader param
const REFERENCE := Vector2(70.0, -310.0)  # pond clearing: the valley's thermometer

var wetness := 0.25  # 0 dust-dry .. 1 soaked (global; regional when weather is)

var _shader_wetness := 0.25


func _ready() -> void:
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	load_state()
	GameClock.hour_tick.connect(_hourly)


func load_state() -> void:
	wetness = float(WorldState.get_value("climate.wetness", wetness))
	_shader_wetness = wetness


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-EASE * delta)
	_shader_wetness = lerpf(_shader_wetness, wetness, blend)
	RenderingServer.global_shader_parameter_set("ground_wetness", _shader_wetness)


## Air temperature (degrees-ish; mood, not meteorology) at a position.
## Seasonal base follows daylight length — long days are warm days — so
## it inherits the real calendar and hemisphere from GameClock.
func temperature(x: float, z: float) -> float:
	var span := GameClock.daylight_span()
	var seasonal := lerpf(0.0, 26.0, clampf(((span.y - span.x) - 8.5) / 7.0, 0.0, 1.0))
	# Coldest before dawn (solar 3:00), warmest mid-afternoon (15:00);
	# storm cloud cover flattens the swing.
	var diurnal := -cos(TAU * (GameClock.solar_hours() - 3.0) / 24.0) \
			* 5.0 * (1.0 - 0.5 * Weather.storminess)
	var lapse := -0.06 * maxf(Terrain.height(x, z), 0.0)  # ridges run colder
	return seasonal + diurnal + lapse - 3.0 * Weather.storminess


## Ground moisture at a position: the global wetness, lifted near open
## water (pond banks stay damp through a dry spell).
func moisture(x: float, z: float) -> float:
	var near := 0.0
	for w in Terrain.WATER_BODIES:
		var d := Vector2(x - w[0], z - w[1]).length()
		near = maxf(near, 1.0 - smoothstep(w[2], w[2] + 18.0, d))
	return clampf(maxf(wetness, 0.85 * near), 0.0, 1.0)


func _hourly(_h: int) -> void:
	var t := temperature(REFERENCE.x, REFERENCE.y)
	if Weather.state == "storm":
		wetness = minf(wetness + RAIN_RATE, 1.0)
	else:
		wetness = maxf(wetness - BASE_DRY_RATE - WARM_DRY_RATE * maxf(t, 0.0), 0.0)
	wetness = snappedf(wetness, 0.001)  # store what we keep: mirror stays exact
	WorldState.set_value("climate.wetness", wetness)
	WorldState.set_value("climate.temperature", snappedf(t, 0.1))
