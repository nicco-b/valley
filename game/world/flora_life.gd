extends Node
## FloraLife (autoload): the flora lifecycle — one vitality value the whole
## valley's vegetation breathes with. Reads the Climate substrate (season
## via daylight, moisture, heat) and eases toward it over days, the way
## plants actually respond — a storm doesn't green the valley overnight.
##
## Published as the flora_vitality global shader param (billboard flora
## tints toward straw as it falls). Writes valley.bloom / valley.parched
## to WorldState with hysteresis — the first simulation-authored story-seed
## hooks: a quest with start_if {flag: valley.parched} now fires when the
## world itself dries out.
##
## Placeholder: one global value + shader tint. Replacement path: per-cell
## vitality feeding scatter density at cell build, and her painted seasonal
## flora states in the same billboard slots.
##
## Sim contract: stateful, advanced on hour_tick (catch-up replays it),
## persisted via WorldState ("flora.vitality"), world_state_reader group.

const EASE_PER_HOUR := 0.06  # ~a day to close most of the gap
const SHADER_EASE := 0.3  # per-second visual approach
const SEASON_BASE := {"spring": 0.85, "summer": 0.68, "autumn": 0.5, "winter": 0.35}
## Open valley floor, away from the pond — flora must feel dry spells,
## and pond banks never do (Climate.moisture floors near open water).
const REFERENCE := Vector2(0.0, -150.0)

var vitality := 0.7

var _shader_vitality := 0.7


func _ready() -> void:
	add_to_group("world_state_reader")
	load_state()
	GameClock.hour_tick.connect(_hourly)


func load_state() -> void:
	vitality = float(WorldState.get_value("flora.vitality", vitality))
	_shader_vitality = vitality


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-SHADER_EASE * delta)
	_shader_vitality = lerpf(_shader_vitality, vitality, blend)
	RenderingServer.global_shader_parameter_set("flora_vitality", _shader_vitality)


## Where vitality wants to settle for a given season, ground moisture,
## and temperature. Static and pure so tests can pin the response.
static func target_for(season: String, moist: float, temp: float) -> float:
	var base: float = SEASON_BASE.get(season, 0.6)
	var water := 0.45 * (moist - 0.35)  # dry ground starves, wet ground feeds
	var heat := -0.03 * maxf(temp - 30.0, 0.0)  # scorching + dry = parched
	var cold := -0.02 * maxf(2.0 - temp, 0.0)  # frost bites what's green
	return clampf(base + water + heat + cold, 0.05, 1.0)


func _hourly(_h: int) -> void:
	var moist := Climate.moisture(REFERENCE.x, REFERENCE.y)
	var temp := Climate.temperature(REFERENCE.x, REFERENCE.y)
	var target := target_for(GameClock.season, moist, temp)
	vitality = snappedf(clampf(
		vitality + (target - vitality) * EASE_PER_HOUR, 0.0, 1.0), 0.001)
	WorldState.set_value("flora.vitality", vitality)
	# Hysteresis on the flags so a boundary flicker can't spam story-seeds.
	if vitality >= 0.8 and not WorldState.has_flag("valley.bloom"):
		WorldState.set_value("valley.bloom", true)
		HUD.notify("the valley is blooming")
		print("[flora] bloom (vitality %.2f)" % vitality)
	elif vitality < 0.7 and WorldState.has_flag("valley.bloom"):
		WorldState.set_value("valley.bloom", false)
	if vitality <= 0.25 and not WorldState.has_flag("valley.parched"):
		WorldState.set_value("valley.parched", true)
		HUD.notify("the valley is parched")
		print("[flora] parched (vitality %.2f)" % vitality)
	elif vitality > 0.35 and WorldState.has_flag("valley.parched"):
		WorldState.set_value("valley.parched", false)
