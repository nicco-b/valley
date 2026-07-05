extends Node
## Weather (autoload): a state machine on the hour tick — calm, windy,
## storm — exposing two continuous values everything reads:
##   wind (0..1): sway amplitude, wind-bed volume, dust speed
##   storminess (0..1): fog thickening, sun dimming, shelter-seeking
## One source of truth; consumers never roll their own weather.
## The wind value is also published as the global shader parameter
## "wind_strength" so vegetation reacts without per-material plumbing.

# The taxonomy (phase C, 2026-07-05): a kind is a BUNDLE of continuous
# properties, not a switch — consumers read the numbers (rain, cloud,
# dust, wind, menace), the string is just its name. Seven kinds:
#   calm      still, bright — the desert default
#   overcast  grey lid, dim light, dry
#   drizzle   soft rain that wets the world SLOWLY, low drama
#   windy     honest wind, some dust, loose weather
#   gale      dry sand-blasting wind — the desert's own violence
#   squall    narrow, fast, vicious — wind AND rain, gone in minutes
#   storm     the full system: rain, wind, menace, hours wide
# menace is what the old 'storminess' meant: shelter-seeking, sun
# dimming, dread. wind/rain/cloud/dust each drive their own systems.
const KINDS := {
	"calm": {"wind": 0.12, "rain": 0.0, "cloud": 0.08, "dust": 0.05,
		"menace": 0.0, "speed": 2.2, "width": [7000.0, 16000.0]},
	"overcast": {"wind": 0.22, "rain": 0.0, "cloud": 0.75, "dust": 0.0,
		"menace": 0.15, "speed": 2.6, "width": [6000.0, 12000.0]},
	"drizzle": {"wind": 0.3, "rain": 0.3, "cloud": 0.9, "dust": 0.0,
		"menace": 0.3, "speed": 2.8, "width": [4000.0, 9000.0]},
	"windy": {"wind": 0.55, "rain": 0.0, "cloud": 0.3, "dust": 0.35,
		"menace": 0.2, "speed": 3.2, "width": [4000.0, 9000.0]},
	"gale": {"wind": 0.85, "rain": 0.0, "cloud": 0.2, "dust": 0.9,
		"menace": 0.55, "speed": 3.8, "width": [2800.0, 6000.0]},
	"squall": {"wind": 0.95, "rain": 0.85, "cloud": 0.9, "dust": 0.1,
		"menace": 0.9, "speed": 5.5, "width": [1100.0, 2400.0]},
	"storm": {"wind": 1.0, "rain": 1.0, "cloud": 1.0, "dust": 0.05,
		"menace": 1.0, "speed": 4.0, "width": [2600.0, 6500.0]},
}
# kind -> [[next kind, probability], ...] — the spawn chain windward.
const TRANSITIONS := {
	"calm": [["calm", 0.5], ["overcast", 0.16], ["windy", 0.16],
		["gale", 0.08], ["drizzle", 0.05], ["squall", 0.02], ["storm", 0.03]],
	"overcast": [["overcast", 0.28], ["calm", 0.22], ["drizzle", 0.24],
		["storm", 0.12], ["squall", 0.06], ["windy", 0.08]],
	"drizzle": [["overcast", 0.32], ["drizzle", 0.28], ["storm", 0.2],
		["calm", 0.2]],
	"windy": [["windy", 0.3], ["calm", 0.3], ["gale", 0.18],
		["overcast", 0.12], ["squall", 0.1]],
	"gale": [["calm", 0.34], ["gale", 0.26], ["windy", 0.22],
		["squall", 0.18]],
	"squall": [["calm", 0.3], ["overcast", 0.3], ["windy", 0.22],
		["squall", 0.18]],
	"storm": [["overcast", 0.36], ["drizzle", 0.24], ["storm", 0.2],
		["calm", 0.2]],
}
const EASE := 0.12  # per-second approach rate toward targets
# Wet-weather likelihood scales with the real season; the gale is the
# dry season's own violence.
const SEASON_STORM_BIAS := {"winter": 1.6, "autumn": 1.25, "spring": 1.0, "summer": 0.6}
const SEASON_GALE_BIAS := {"winter": 0.7, "autumn": 0.9, "spring": 1.0, "summer": 1.7}
const WET_KINDS := ["storm", "squall", "drizzle"]

var state := "calm"
var wind := 0.12
var storminess := 0.0  # menace at the focus (the old meaning, eased)
var rain := 0.0        # rainfall at the focus, 0..1
var cloud := 0.08      # cloud cover at the focus, 0..1
var dust := 0.05       # airborne sand at the focus, 0..1

# Fronts (the Elements phase B, 2026-07-05): weather is BANDS with
# positions, not one global switch. Each front spawns windward of the
# world circle, travels along the wind direction it was born with,
# and expires leeward:
#   {kind, dx, dz (unit travel dir), edge (m along dir, the leading
#    edge), width (m), speed (m/s)}
# Local weather anywhere = the YOUNGEST front covering that point,
# with a soft leading edge; between bands it's calm. Weather.state /
# wind / storminess remain the values AT THE FOCUS (player/god cam),
# so every existing consumer keeps working; sims anchored in space
# (Climate at the valley, Hydrology at its watershed) read
# state_at() their own coordinates — rain fills the pond only when a
# front is actually overhead. Sim contract type (b): advanced on
# hour_tick from the "weather" Rng stream, saved as weather.fronts,
# replayed by catch-up, fingerprinted by the soak.
const WORLD_R := 13000.0
const LEAD_SOFT := 800.0  # meters of soft leading edge
var fronts: Array[Dictionary] = []
var _last_kind := "calm"  # spawn chain state (TRANSITIONS walks this)
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


## Toolkit: the air at the focus, then every front on the map.
func summary() -> String:
	var lines := PackedStringArray()
	lines.append("%s  wind=%.2f rain=%.2f cloud=%.2f dust=%.2f menace=%.2f fog=%.2f dir=(%.2f, %.2f)%s" % [
		state, wind, rain, cloud, dust, storminess, fog_amount(),
		wind_dir.x, wind_dir.y,
		"" if fog_override < 0.0 else " (FOG OVERRIDE)"])
	for f in fronts:
		lines.append("  front %s  edge=%.0fm/%0.f  width=%.0fm  dir=(%.2f, %.2f)  %.1fm/s" % [
			f.kind, f.edge, WORLD_R, f.width, f.dx, f.dz, f.speed])
	return "\n".join(lines)


func _ready() -> void:
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	load_state()
	GameClock.hour_tick.connect(_transition)


func load_state() -> void:
	wind = float(WorldState.get_value("weather.wind", 0.12))
	_wind_angle = float(WorldState.get_value("weather.wind_angle", _wind_angle))
	wind_dir = Vector2(cos(_wind_angle), sin(_wind_angle))
	fronts.clear()
	var saved: Variant = WorldState.get_value("weather.fronts", null)
	if saved is Array:
		for f: Variant in saved:
			if f is Dictionary and f.has("kind") and f.has("edge"):
				fronts.append({"kind": String(f.kind), "dx": float(f.dx),
					"dz": float(f.dz), "edge": float(f.edge),
					"width": float(f.width), "speed": float(f.speed)})
	if fronts.is_empty():
		# Fresh world or legacy save: one band of the old global state
		# covering everything, already fully entered.
		var kind := String(WorldState.get_value("weather.state", "calm"))
		if not KINDS.has(kind):
			kind = "calm"
		fronts.append({"kind": kind, "dx": wind_dir.x, "dz": wind_dir.y,
			"edge": WORLD_R, "width": WORLD_R * 2.5,
			"speed": float(KINDS[kind].speed)})
	_last_kind = fronts[fronts.size() - 1].kind
	state = String(fronts[fronts.size() - 1].kind)  # refined next _process


## Local weather band at a point: {kind, lead 0..1 (leading-edge
## softness — 1 deep inside the band)}. Youngest front wins.
func _local(x: float, z: float) -> Dictionary:
	for i in range(fronts.size() - 1, -1, -1):
		var f: Dictionary = fronts[i]
		var s: float = x * f.dx + z * f.dz
		if s <= f.edge and s > f.edge - f.width:
			return {"kind": f.kind,
				"lead": clampf((f.edge - s) / LEAD_SOFT, 0.0, 1.0)}
	return {"kind": "calm", "lead": 1.0}


## Weather kind over a world position — spatial consumers (Climate at
## the valley, Hydrology at its watershed) read THIS, not .state.
func state_at(x: float, z: float) -> String:
	return _local(x, z).kind


## Continuous local properties (lead-softened): the numbers consumers
## should read. prop in [wind, rain, cloud, dust, menace].
func property_at(x: float, z: float, prop: String) -> float:
	var lw := _local(x, z)
	return float(KINDS[lw.kind][prop]) * lw.lead


## Storm/menace intensity over a world position (the old meaning).
func storminess_at(x: float, z: float) -> float:
	return property_at(x, z, "menace")


## Rainfall over a world position, 0..1 — drizzle wets slowly, storms
## pour; Hydrology and Climate read THIS, so rain is continuous.
func rain_at(x: float, z: float) -> float:
	return property_at(x, z, "rain")


func _focus_xz() -> Vector2:
	if GodMode.active:
		var p := GodMode.cam_position()
		return Vector2(p.x, p.z)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		return Vector2(player.global_position.x, player.global_position.z)
	return Climate.REFERENCE


func _process(delta: float) -> void:
	var lw := _local(_focus_xz().x, _focus_xz().y)
	if lw.kind != state:
		state = lw.kind
		print("[weather] front over focus -> ", state)
	var blend := 1.0 - exp(-EASE * delta)
	var k: Dictionary = KINDS[state]
	wind = lerpf(wind, float(k.wind) * lerpf(0.55, 1.0, lw.lead), blend)
	storminess = lerpf(storminess, float(k.menace) * lw.lead, blend)
	rain = lerpf(rain, float(k.rain) * lw.lead, blend)
	cloud = lerpf(cloud, float(k.cloud) * lerpf(0.5, 1.0, lw.lead), blend)
	dust = lerpf(dust, float(k.dust) * lw.lead, blend)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)
	RenderingServer.global_shader_parameter_set("wind_dir", wind_dir)


## Dev/test override: drop a full-cover front of `kind` on the whole
## world, effective everywhere immediately (the Y key and the scene
## tests both use this — forcing .state alone no longer reaches the
## spatial consumers).
func force_kind(kind: String) -> void:
	fronts.append({"kind": kind, "dx": wind_dir.x, "dz": wind_dir.y,
		"edge": WORLD_R, "width": WORLD_R * 2.5,
		"speed": float(KINDS[kind].speed)})
	_last_kind = kind
	state = kind


func _unhandled_input(event: InputEvent) -> void:
	# Debug: Y cycles a forced full-cover front calm -> windy -> storm.
	if event.is_action_pressed("debug_weather"):
		# Cycle through ALL kinds in a fixed order.
		var order := ["calm", "overcast", "drizzle", "windy", "gale", "squall", "storm"]
		var next: String = order[(order.find(state) + 1) % order.size()]
		force_kind(next)
		HUD.notify("weather: " + next + " (forced front)")


func _transition(_hour: int) -> void:
	# March every front one hour along its own heading; drop the spent.
	for f in fronts:
		f.edge = float(f.edge) + float(f.speed) * 3600.0
	fronts = fronts.filter(func(f: Dictionary) -> bool:
		return float(f.edge) - float(f.width) < WORLD_R)
	# Spawn while the windward door is open (catch-up replays may open
	# it several times in one stretch).
	while _door_open():
		_spawn_front()
	# The wind wanders; storms swing it hard enough to notice.
	var swing := 0.15 + 0.5 * storminess
	var drift := Rng.stream("weather").randf_range(-swing, swing)
	_wind_angle = fposmod(_wind_angle + drift, TAU)
	wind_dir = Vector2.from_angle(_wind_angle)
	WorldState.set_value("weather.state", state)
	WorldState.set_value("weather.wind", wind)
	WorldState.set_value("weather.wind_angle", snappedf(_wind_angle, 0.001))
	WorldState.set_value("weather.fronts", fronts.duplicate(true))


## True while the newest front has fully entered the world circle —
## room for the next system behind it.
func _door_open() -> bool:
	if fronts.is_empty():
		return true
	if fronts.size() >= 6:
		return false  # backstop; widths make this near-unreachable
	var last: Dictionary = fronts[fronts.size() - 1]
	return float(last.edge) - float(last.width) >= -WORLD_R


func _weight(kind: String, base: float) -> float:
	if kind in WET_KINDS:
		return base * float(SEASON_STORM_BIAS.get(GameClock.season, 1.0))
	if kind == "gale":
		return base * float(SEASON_GALE_BIAS.get(GameClock.season, 1.0))
	return base


func _spawn_front() -> void:
	var total := 0.0
	for t in TRANSITIONS[_last_kind]:
		total += _weight(t[0], t[1])
	var roll := Rng.stream("weather").randf() * total
	var acc := 0.0
	var kind: String = _last_kind
	for t in TRANSITIONS[_last_kind]:
		acc += _weight(t[0], t[1])
		if roll <= acc:
			kind = t[0]
			break
	var wrange: Array = KINDS[kind].width
	var width: float = Rng.stream("weather").randf_range(wrange[0], wrange[1])
	fronts.append({"kind": kind, "dx": wind_dir.x, "dz": wind_dir.y,
		"edge": -WORLD_R, "width": width, "speed": float(KINDS[kind].speed)})
	_last_kind = kind
	print("[weather] front spawned windward: ", kind, " (", int(width), "m)")
