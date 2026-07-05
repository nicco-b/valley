extends Node
## Weather (autoload): a state machine on the hour tick — calm, windy,
## storm — exposing two continuous values everything reads:
##   wind (0..1): sway amplitude, wind-bed volume, dust speed
##   storminess (0..1): fog thickening, sun dimming, shelter-seeking
## One source of truth; consumers never roll their own weather.
## The wind value is also published as the global shader parameter
## "wind_strength" so vegetation reacts without per-material plumbing.

const WIND_LEVELS := {"calm": 0.12, "windy": 0.55, "storm": 1.0}
# state -> [[next state, probability], ...] rolled each game hour
const TRANSITIONS := {
	"calm": [["calm", 0.65], ["windy", 0.28], ["storm", 0.07]],
	"windy": [["windy", 0.4], ["calm", 0.4], ["storm", 0.2]],
	"storm": [["windy", 0.5], ["storm", 0.3], ["calm", 0.2]],
}
const EASE := 0.12  # per-second approach rate toward targets
# Storm likelihood scales with the real season (GameClock.season):
# winter broods, summer stretches calm.
const SEASON_STORM_BIAS := {"winter": 1.6, "autumn": 1.25, "spring": 1.0, "summer": 0.6}

var state := "calm"
var wind: float = WIND_LEVELS.calm
var storminess := 0.0
# Fog (the Elements, 2026-07-05): a STATELESS function of the sim —
# dew fog condenses on cold, wet, calm nights (Climate knows both),
# peaks before sunrise, and the real sun burns it off through the
# morning; storms carry their own murk. Sim-contract type (a):
# nothing saved, nothing to catch up, deterministic.
# Toolkit knob: fog_override >= 0 forces the amount (dev only).
var fog_override := -1.0
## Where the wind blows FROM->TO on the xz plane. Wanders a little each
## hour, swings harder in storms; sand ripples, dust, and (later) seed
## drift and audio panning all read it.
var wind_dir := Vector2(1.0, 0.35).normalized()

var _wind_angle := atan2(0.35, 1.0)


## Ground fog right now, 0..1. Dew term: wet air, cold morning, still
## wind. Solar gate: builds after ~1am, peaks ~5:30, burned off by
## ~10:30 — a February player gets fog seasons July never sees.
func fog_amount() -> float:
	if fog_override >= 0.0:
		return clampf(fog_override, 0.0, 1.0)
	var dew := clampf(Climate.wetness * 1.35
		- maxf(Climate.temperature(Climate.REFERENCE.x, Climate.REFERENCE.y), 0.0) * 0.05
		- wind * 0.9, 0.0, 1.0)
	var gate := 1.0 - smoothstep(1.5, 5.0, absf(GameClock.solar_hours() - 5.5))
	return maxf(dew * gate, storminess * 0.35)


## Toolkit: the air, one line.
func summary() -> String:
	return "%s  wind=%.2f dir=(%.2f, %.2f)  storminess=%.2f  fog=%.2f%s" % [
		state, wind, wind_dir.x, wind_dir.y, storminess, fog_amount(),
		"" if fog_override < 0.0 else " (OVERRIDE)"]


func _ready() -> void:
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	load_state()
	GameClock.hour_tick.connect(_transition)


func load_state() -> void:
	state = WorldState.get_value("weather.state", "calm")
	wind = float(WorldState.get_value("weather.wind", WIND_LEVELS[state]))
	_wind_angle = float(WorldState.get_value("weather.wind_angle", _wind_angle))
	wind_dir = Vector2(cos(_wind_angle), sin(_wind_angle))


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-EASE * delta)
	wind = lerpf(wind, WIND_LEVELS[state], blend)
	storminess = lerpf(storminess, 1.0 if state == "storm" else 0.0, blend)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)
	RenderingServer.global_shader_parameter_set("wind_dir", wind_dir)


func _unhandled_input(event: InputEvent) -> void:
	# Debug: Y cycles calm -> windy -> storm.
	if event.is_action_pressed("debug_weather"):
		state = {"calm": "windy", "windy": "storm", "storm": "calm"}[state]
		HUD.notify("weather: " + state)


func _transition(_hour: int) -> void:
	var bias: float = SEASON_STORM_BIAS.get(GameClock.season, 1.0)
	var total := 0.0
	for t in TRANSITIONS[state]:
		total += t[1] * (bias if t[0] == "storm" else 1.0)
	var roll := Rng.stream("weather").randf() * total
	var acc := 0.0
	for t in TRANSITIONS[state]:
		acc += t[1] * (bias if t[0] == "storm" else 1.0)
		if roll <= acc:
			if t[0] != state:
				state = t[0]
				print("[weather] -> ", state)
			break
	# The wind wanders; storms swing it hard enough to notice.
	var swing := 0.15 + 0.5 * storminess
	var drift := Rng.stream("weather").randf_range(-swing, swing)
	_wind_angle = fposmod(_wind_angle + drift, TAU)
	wind_dir = Vector2.from_angle(_wind_angle)
	WorldState.set_value("weather.state", state)
	WorldState.set_value("weather.wind", wind)
	WorldState.set_value("weather.wind_angle", snappedf(_wind_angle, 0.001))
