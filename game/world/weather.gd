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


func _ready() -> void:
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	load_state()
	GameClock.hour_tick.connect(_transition)


func load_state() -> void:
	state = WorldState.get_value("weather.state", "calm")
	wind = float(WorldState.get_value("weather.wind", WIND_LEVELS[state]))


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-EASE * delta)
	wind = lerpf(wind, WIND_LEVELS[state], blend)
	storminess = lerpf(storminess, 1.0 if state == "storm" else 0.0, blend)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)


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
	WorldState.set_value("weather.state", state)
	WorldState.set_value("weather.wind", wind)
