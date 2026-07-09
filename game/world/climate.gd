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

# REFERENCE + the wetness field frame are the valley's GEOGRAPHY, not
# mechanism (FW4): a game's `data/climate/climate.json` ships its own
# ("reference", "grid_n", "grid_origin", "grid_cell"); these consts are
# the framework's fallback for a content-empty boot (origin-centered,
# matches the guide/biome-map framing). _load_climate_records() (called
# from _ready(), before wet_grid is (re)sized) overrides the vars below.
const REFERENCE_DEFAULT := Vector2(0.0, 0.0)  # world center / spawn: the climate thermometer
const GRID_N_DEFAULT := 8
const GRID_ORIGIN_DEFAULT := -8192.0
const GRID_CELL_DEFAULT := 2048.0

var REFERENCE: Vector2 = REFERENCE_DEFAULT  # world center / spawn: the climate thermometer
var GRID_N: int = GRID_N_DEFAULT
var GRID_ORIGIN: float = GRID_ORIGIN_DEFAULT
var GRID_CELL: float = GRID_CELL_DEFAULT

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
# Last-pushed shader values (perf): set-on-change guards for _process.
var _set_wetness := -1e9
var _set_snow := -1e9
var _set_snow_line := -1e9
var _set_humidity := -1e9
# Static terrain facts per grid cell (swing, gradient, height), cached
# so the hourly field tick — and every catch-up replay hour — pays for
# terrain probes exactly once. Cleared when the terrain itself moves
# (a bake hot-reload reshapes the world under the cache).
var _cell_swing := PackedFloat32Array()
var _cell_grad := PackedFloat32Array()
var _cell_h := PackedFloat32Array()


func _fresh_grid() -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(GRID_N * GRID_N)
	g.fill(0.25)
	return g


## The geography: REFERENCE + grid frame from data/climate/climate.json,
## if a game ships one — else the origin-centered defaults above stand
## (content-empty boot law, FW1). Each field is independently overridable;
## missing/malformed fields just leave that default in place.
func _load_climate_records() -> void:
	const PATH := "res://data/climate/climate.json"
	if not FileAccess.file_exists(PATH):
		return
	var cfg: Variant = Records.load_json(PATH)
	if not (cfg is Dictionary):
		return
	if cfg.get("reference") is Array and (cfg["reference"] as Array).size() == 2:
		REFERENCE = Vector2(float(cfg["reference"][0]), float(cfg["reference"][1]))
	if typeof(cfg.get("grid_n")) in [TYPE_INT, TYPE_FLOAT]:
		GRID_N = int(cfg["grid_n"])
	if typeof(cfg.get("grid_origin")) in [TYPE_INT, TYPE_FLOAT]:
		GRID_ORIGIN = float(cfg["grid_origin"])
	if typeof(cfg.get("grid_cell")) in [TYPE_INT, TYPE_FLOAT]:
		GRID_CELL = float(cfg["grid_cell"])


func _ready() -> void:
	_load_climate_records()
	if wet_grid.size() != GRID_N * GRID_N:
		wet_grid = _fresh_grid()  # the record moved the frame; re-size before load_state
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	load_state()
	GameClock.hour_tick.connect(_hourly)
	Terrain.edited.connect(func(_r: Rect2) -> void:
		_cell_swing.clear()
		_cell_grad.clear()
		_cell_h.clear())


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
	# Push to the shader only on visible change (perf 2026-07-09): the
	# eases converge, and a step below a thousandth of the range is
	# invisible. The eased vars stay exact — only redundant
	# RenderingServer traffic is skipped.
	if absf(_shader_wetness - _set_wetness) > 5e-4:
		_set_wetness = _shader_wetness
		RenderingServer.global_shader_parameter_set("ground_wetness", _shader_wetness)
	if absf(_shader_snow - _set_snow) > 5e-4:
		_set_snow = _shader_snow
		RenderingServer.global_shader_parameter_set("snow_cover", _shader_snow)
	var line := snow_line()
	if absf(line - _set_snow_line) > 0.01:
		_set_snow_line = line
		RenderingServer.global_shader_parameter_set("snow_line", line)
	# The air over the focus: humid nights wash the stars out, dry cold
	# ones sharpen them (the sky shader reads this).
	var hum := humidity(fx.x, fx.y)
	if absf(hum - _set_humidity) > 5e-4:
		_set_humidity = hum
		RenderingServer.global_shader_parameter_set("air_humidity", hum)


func _focus_xz() -> Vector2:
	if Toolkit.active:
		var p := Toolkit.cam_position()
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


# The thermal field (Climate v2 phase 2, 2026-07-05): temperature is
# still stateless, but now it knows WHERE it is beyond altitude —
#   maritime: the sea damps the diurnal swing (coasts never bake or
#     freeze the way the interior does; inland stays exactly as tuned).
#   aspect: this world's sun rises at +Z, passes overhead, sets at -Z
#     (day_night.gd), so there is no permanent warm side — instead,
#     slopes facing the sun's CURRENT bearing run warmer: east flanks
#     thaw first in the morning, west flanks hold the evening heat.
const MARITIME_R := 1800.0  # how far the sea's moderation reaches
const MARITIME_SWING := 0.6  # coastal diurnal swing factor (1.0 inland)
const ASPECT_GAIN := 1.8  # degrees on a full-tilt sun-facing slope
const ASPECT_STEP := 25.0  # gradient sampling baseline (m)


## The valley-floor air, before altitude: season (via daylight length,
## so calendar/hemisphere come from GameClock), time of day (coldest
## pre-dawn, warmest mid-afternoon, flattened under storm cloud), storm
## chill.
func base_temperature() -> float:
	return _seasonal() + _diurnal() - 3.0 * Weather.storminess


func _seasonal() -> float:
	var span := GameClock.daylight_span()
	return lerpf(0.0, 26.0, clampf(((span.y - span.x) - 8.5) / 7.0, 0.0, 1.0))


func _diurnal() -> float:
	return -cos(TAU * (GameClock.solar_hours() - 3.0) / 24.0) \
			* 5.0 * (1.0 - 0.5 * Weather.storminess)


## Air temperature (degrees-ish; mood, not meteorology) at a position:
## season + diurnal (sea-damped) + storm chill + altitude lapse +
## sun-facing slope warmth.
func temperature(x: float, z: float) -> float:
	return _seasonal() + _diurnal() * _swing(x, z) - 3.0 * Weather.storminess \
			- LAPSE * maxf(Terrain.height(x, z), 0.0) \
			+ aspect_term(_gradient_z(x, z), GameClock.solar_hours())


## Diurnal swing factor: 1.0 deep inland (the valley keeps its tuned
## feel), damped toward MARITIME_SWING by how much open sea sits within
## MARITIME_R. Deterministic terrain reads.
func _swing(x: float, z: float) -> float:
	if Terrain.sea_level < -1e11:
		return 1.0
	var sea := 0.0
	if Terrain.height(x + MARITIME_R, z) < Terrain.sea_level:
		sea += 0.25
	if Terrain.height(x - MARITIME_R, z) < Terrain.sea_level:
		sea += 0.25
	if Terrain.height(x, z + MARITIME_R) < Terrain.sea_level:
		sea += 0.25
	if Terrain.height(x, z - MARITIME_R) < Terrain.sea_level:
		sea += 0.25
	return lerpf(1.0, MARITIME_SWING, sea)


# Humidity (Climate v2 phase 3, 2026-07-05): AIR moisture, distinct
# from ground wetness — STATELESS (sim-contract type (a)): derived at
# query time from open water upwind (the sea breath rides the live
# wind), the ground wetness under the air column (recent rain
# humidifies), a wet front overhead (raining air is saturated air),
# all thinning with altitude. Nothing saved, nothing to catch up.
# Consumers: fog's dew term, the dew-at-dawn wetting pulse below,
# star extinction (air_humidity global — the clearest sky of the year
# is a cold dry winter night), food spoilage later.
const HUM_BASE := 0.2
const HUM_WATER := 0.5  # full when every upwind probe sits on open water
const HUM_GROUND := 0.35  # soaked ground humidifies the air above it
const HUM_WET_FRONT := 0.25  # raining air is saturated air
const HUM_PROBES := [600.0, 1400.0, 2600.0, 4200.0]  # upwind water probes (m)
const ALT_DRY_LO := 150.0  # the air starts thinning dry above this
const ALT_DRY_HI := 800.0
const ALT_DRY_FLOOR := 0.45  # humidity multiplier on the peaks
const DEW_RATE := 0.03  # pre-dawn saturated-air wetting per hour
const DEW_HUMIDITY := 0.65  # air at least this humid dews
const DEW_WIND := 0.35  # and near-still
const DEW_FROM := 3.0  # solar hours of the dew window
const DEW_TO := 7.0


## Air humidity at a position, 0..1.
func humidity(x: float, z: float) -> float:
	return _humidity_for(x, z, wetness_at(x, z),
			maxf(Terrain.height(x, z), 0.0))


## The humidity model with ground wetness and altitude supplied (the
## hourly field loop feeds cached values; tests pin single factors).
func _humidity_for(x: float, z: float, ground: float, h: float) -> float:
	var water := 0.0
	var wd: Vector2 = Weather.wind_dir
	for dist: float in HUM_PROBES:
		var px := x - wd.x * dist
		var pz := z - wd.y * dist
		if Terrain.height(px, pz) < Terrain.sea_level \
				or Terrain.water_surface_base(px, pz) > -1e11:
			water += 1.0 / HUM_PROBES.size()
	var wet_front := HUM_WET_FRONT if Weather.state_at(x, z) in Weather.WET_KINDS else 0.0
	var alt := lerpf(1.0, ALT_DRY_FLOOR, smoothstep(ALT_DRY_LO, ALT_DRY_HI, h))
	return clampf((HUM_BASE + HUM_WATER * water + HUM_GROUND * ground
			+ wet_front) * alt, 0.0, 1.0)


func _ensure_cell_cache() -> void:
	if _cell_swing.size() == GRID_N * GRID_N:
		return
	_cell_swing.resize(GRID_N * GRID_N)
	_cell_grad.resize(GRID_N * GRID_N)
	_cell_h.resize(GRID_N * GRID_N)
	for i in GRID_N * GRID_N:
		var cx := GRID_ORIGIN + (float(i % GRID_N) + 0.5) * GRID_CELL
		var cz := GRID_ORIGIN + (float(i / GRID_N) + 0.5) * GRID_CELL
		_cell_swing[i] = _swing(cx, cz)
		_cell_grad[i] = _gradient_z(cx, cz)
		_cell_h[i] = maxf(Terrain.height(cx, cz), 0.0)


## North-south terrain gradient dh/dz — the only axis the sun's arc
## crosses, so the only aspect that matters under this sky.
func _gradient_z(x: float, z: float) -> float:
	return (Terrain.height(x, z + ASPECT_STEP) - Terrain.height(x, z - ASPECT_STEP)) \
			/ (2.0 * ASPECT_STEP)


## Sun-facing slope warmth, pure: gradient_z is dh/dz, solar_h the solar
## hour. The sun's horizontal bearing runs +Z (sunrise) -> overhead ->
## -Z (sunset); a slope FACING +Z has dh/dz < 0. Zero at night and
## under the noon zenith; peaks mid-morning / mid-afternoon.
static func aspect_term(gradient_z: float, solar_h: float) -> float:
	var up := maxf(sin(TAU * (solar_h - 6.0) / 24.0), 0.0)  # day gate
	var bearing := cos(TAU * (solar_h - 6.0) / 24.0)  # +1 dawn .. -1 dusk
	return ASPECT_GAIN * up * bearing * clampf(-gradient_z, -1.0, 1.0)


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
	return "wetness(valley)=%.2f field=[%.2f..%.2f] snow=%.2f snowline=%.0fm  t(valley)=%.1f  hum(valley)=%.2f  moisture(pond)=%.2f" % [
		wetness, lo, hi, snow, snow_line(),
		temperature(REFERENCE.x, REFERENCE.y),
		humidity(REFERENCE.x, REFERENCE.y),
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
	_ensure_cell_cache()
	var seasonal := _seasonal()
	var diurnal := _diurnal()
	var chill := 3.0 * Weather.storminess
	var solar: float = GameClock.solar_hours()
	var dew_window := solar >= DEW_FROM and solar <= DEW_TO
	for i in GRID_N * GRID_N:
		var cx := GRID_ORIGIN + (float(i % GRID_N) + 0.5) * GRID_CELL
		var cz := GRID_ORIGIN + (float(i / GRID_N) + 0.5) * GRID_CELL
		var local_rain := Weather.rain_at(cx, cz)
		var w := wet_grid[i]
		if local_rain > 0.05:
			w = minf(w + RAIN_RATE * local_rain, 1.0)
		elif dew_window and Weather.property_at(cx, cz, "wind") <= DEW_WIND \
				and _humidity_for(cx, cz, w, _cell_h[i]) >= DEW_HUMIDITY:
			# Dew at dawn: saturated still air neither dries the ground
			# nor leaves it alone — a thin film condenses, darkening the
			# pre-dawn ground; the morning sun dries it back off.
			w = minf(w + DEW_RATE, 1.0)
		else:
			var t := seasonal + diurnal * _cell_swing[i] - chill \
					- LAPSE * _cell_h[i] + aspect_term(_cell_grad[i], solar)
			w = maxf(w - BASE_DRY_RATE - WARM_DRY_RATE * maxf(t, 0.0), 0.0)
		wet_grid[i] = snappedf(minf(w + melt * MELTWATER, 1.0), 0.001)
	WorldState.set_value("climate.wetness", wetness)
	WorldState.set_value("climate.snow", snow)
	WorldState.set_value("climate.temperature", snappedf(ref_t, 0.1))
	var out: Array = []
	for i in GRID_N * GRID_N:
		out.append(wet_grid[i])
	WorldState.set_value("climate.wet_grid", out)
