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
# The taxonomy + spawn chain are MOOD, not mechanism (FW4): a game's
# `data/climate/weather.json` ("kinds"/"transitions") ships its own;
# these consts are the framework's fallback for a content-empty boot
# (this desert default), replaced by _load_climate_records() below.
const KINDS_DEFAULT := {
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
const TRANSITIONS_DEFAULT := {
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
var KINDS: Dictionary = KINDS_DEFAULT
var TRANSITIONS: Dictionary = TRANSITIONS_DEFAULT
const EASE := 0.12  # per-second approach rate toward targets
# Wet-weather likelihood scales with the real season; the gale is the
# dry season's own violence.
const SEASON_STORM_BIAS := {"winter": 1.6, "autumn": 1.25, "spring": 1.0, "summer": 0.6}
const SEASON_GALE_BIAS := {"winter": 0.7, "autumn": 0.9, "spring": 1.0, "summer": 1.7}
const WET_KINDS := ["storm", "squall", "drizzle"]

## The weather LOCK (Strata's weather lock, 2026-07-09). While held, the
## hourly evolution PAUSES: fronts stop marching, no new fronts spawn, the
## wind stops wandering — _transition early-returns. The Elements keep
## RENDERING the held state (the per-frame _process eases wind/rain/cloud/dust
## toward the current front's targets exactly as before; a still field simply
## stays put), so the sky doesn't freeze visually — it just stops CHANGING.
## Independent of the clock lock: you can hold weather while time flows, or
## the reverse. Mirrored to WorldState "weather.hold" (saves; Strata reads
## truth off the panel's AIR line).
##
## Determinism / soak: the guard is a pure early-return keyed on `held`, which
## a soak never sets — so an unheld world's transitions are byte-identical and
## the fingerprint is unmoved. A held world simply stops drawing from the
## "weather" Rng stream (no spawn, no wind drift), which is deterministic:
## the same held span always yields the same (frozen) fronts.
var held := false

var state := "calm"
var wind := 0.12
# Last-pushed shader values (perf): set-on-change guards for _process.
var _set_wind := -1e9
var _set_wind_dir := Vector2.INF
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
# wind / storminess remain the values AT THE FOCUS (player/Toolkit cam),
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

# --- Contour routing (PLAN_ENGINE E2, Mission C2a: weather's front chain) -------
## The hourly front evolution (_transition's march/spawn/decay + wind drift) is a
## SYSTEM-TIER port routed through the native Contour §6 `Weather` system
## (game/world/weather.ct, via game/sim/contour_bridge.gd) when STRATA_CONTOUR=1
## — a boot-time sim flag, read once, DevMode-independent, default OFF. Flag OFF
## is byte-identical GDScript. NO SILENT FALLBACK (the honesty law): flag ON with
## the kernel absent / the module uncompilable / a refused tick is a LOUD
## push_error, never a quiet twin. The system consumes the SEEDED pcg stream
## (the RNG rung) threaded through weather.rng, seeded from — and written back to
## — Rng.stream("weather").state, so both paths advance the SAME stream in
## lockstep (pcg_* is bit-exact to RandomPCG). Engine-bound reads stay GDScript
## (the split: _biome_scale/_orographic terrain, fog, the _process ease). The
## routed ticks carry a counter (contour_status) so the soak proves the system
## actually ran inside the fingerprinted window.
const _CONTOUR_MODULE := "res://game/world/weather.ct"
## 0 unresolved · 1 off (flag unset) · 2 engaged (bridge live) · -1 refused.
var _contour_mode := 0
var _contour_bridge: ContourBridge = null
var _contour_calls := 0   # system ticks answered by Contour (the engaged-path probe)


## Ground fog right now, 0..1. Dew term: wet air, cold morning, still
## wind. Solar gate: builds after ~1am, peaks ~5:30, burned off by
## ~10:30 — a February player gets fog seasons July never sees.
func fog_amount() -> float:
	if fog_override >= 0.0:
		return clampf(fog_override, 0.0, 1.0)
	var fx := _focus_xz()
	# Fog is the AIR's business now: humidity (sea breath + wet ground +
	# saturated fronts, thin aloft) condenses where it's cold and still —
	# so the coast fogs harder than the interior and summits float clear.
	var dew := clampf(Climate.humidity(fx.x, fx.y) * 1.35
		- maxf(Climate.temperature(Climate.REFERENCE.x, Climate.REFERENCE.y), 0.0) * 0.05
		- wind * 0.9, 0.0, 1.0)
	var gate := 1.0 - smoothstep(1.5, 5.0, absf(GameClock.solar_hours() - 5.5))
	return maxf(dew * gate, storminess * 0.35)


## Toolkit: the air at the focus, then every front on the map.
func summary() -> String:
	var lines := PackedStringArray()
	var fx := _focus_xz()
	var lw := _local(fx.x, fx.y)
	lines.append("%s  wind=%.2f rain=%.2f cloud=%.2f dust=%.2f menace=%.2f fog=%.2f oro=x%.2f dir=(%.2f, %.2f)%s" % [
		state, wind, rain, cloud, dust, storminess, fog_amount(),
		_orographic(fx.x, fx.y, float(lw.dx), float(lw.dz)),
		wind_dir.x, wind_dir.y,
		"" if fog_override < 0.0 else " (FOG OVERRIDE)"])
	for f in fronts:
		lines.append("  front %s  edge=%.0fm/%0.f  width=%.0fm  dir=(%.2f, %.2f)  %.1fm/s" % [
			f.kind, f.edge, WORLD_R, f.width, f.dx, f.dz, f.speed])
	return "\n".join(lines)


## Vernier setter/getter. A named method, NOT a lambda — see
## WaterField.get_fill_channels()'s doc.
func vernier_set_fog_override(v: float) -> void:
	fog_override = v


func vernier_fog_override() -> float:
	return fog_override


## The live systems bridge when routing is engaged, else null (flag off, or a
## loud refusal). Resolves once at first tick (boot); flag-off is pure GDScript.
func _route_contour() -> ContourBridge:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour_bridge


func _contour_resolve() -> void:
	if OS.get_environment("STRATA_CONTOUR") != "1":
		_contour_mode = 1   # flag off — the GDScript twin, forever byte-identical
		return
	# Flag ON: engage the bridge, or REFUSE loudly (never a silent GDScript pass).
	if not ContourBridge.available():
		push_error("[weather] STRATA_CONTOUR=1 but the Contour kernel is unavailable "
			+ "(not macOS / dylib absent) — refusing to silently run the GDScript twin")
		_contour_mode = -1
		return
	var bridge := ContourBridge.new(WorldState)
	var err := bridge.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[weather] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour_bridge = bridge
	_contour_mode = 2


## Routing introspection for the soak (proves the system ran, not a silent
## fallback): the resolved mode, whether it engaged, and the tick count.
func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}


func _ready() -> void:
	# Vernier (P4): passive registration (reads -1.0 once; never calls the
	# setter on its own) — a Toolkit knob nothing ever wired a UI to yet.
	Vernier.register("weather.fog_override", TYPE_FLOAT, -1.0,
		Callable(self, "vernier_set_fog_override"), Callable(self, "vernier_fog_override"),
		"Pins ground fog 0..1; < 0 lets Climate/time-of-day drive it.")
	_load_climate_records()
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	load_state()
	GameClock.hour_tick.connect(_transition)


## The mood: a game's own kinds/transitions from data/climate/weather.json,
## if it ships one — else the desert defaults above stand (content-empty
## boot law, FW1). Bad/malformed records are dropped with a Records error;
## the defaults still stand rather than half-loading.
func _load_climate_records() -> void:
	const PATH := "res://data/climate/weather.json"
	if not FileAccess.file_exists(PATH):
		return
	var cfg: Variant = Records.load_json(PATH)
	if cfg is Dictionary and Records.validate(cfg, {
		"kinds": TYPE_DICTIONARY, "transitions": TYPE_DICTIONARY,
	}, PATH):
		KINDS = cfg["kinds"]
		TRANSITIONS = cfg["transitions"]


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
	held = bool(WorldState.get_value("weather.hold", false))  # the lock survives save/load


## Local weather band at a point: {kind, lead 0..1 (leading-edge
## softness — 1 deep inside the band), dx/dz (the band's travel
## direction — the orographic term needs to know which way the wet air
## came from)}. Youngest front wins.
func _local(x: float, z: float) -> Dictionary:
	for i in range(fronts.size() - 1, -1, -1):
		var f: Dictionary = fronts[i]
		var s: float = x * f.dx + z * f.dz
		if s <= f.edge and s > f.edge - f.width:
			return {"kind": f.kind,
				"lead": clampf((f.edge - s) / LEAD_SOFT, 0.0, 1.0),
				"dx": float(f.dx), "dz": float(f.dz)}
	return {"kind": "calm", "lead": 1.0, "dx": wind_dir.x, "dz": wind_dir.y}


## Weather kind over a world position — spatial consumers (Climate at
## the valley, Hydrology at its watershed) read THIS, not .state.
func state_at(x: float, z: float) -> String:
	return _local(x, z).kind


## Continuous local properties (lead-softened, BIOME-shaped): the
## numbers consumers should read. prop in [wind, rain, cloud, dust,
## menace].
func property_at(x: float, z: float, prop: String) -> float:
	var lw := _local(x, z)
	return _biome_scale(x, z, prop, float(KINDS[lw.kind][prop]) * lw.lead,
			float(lw.dx), float(lw.dz))


# Rain shadow (Climate v2, 2026-07-05): where the wet air CAME FROM
# matters. Probes march upwind along the front's travel direction —
# a barrier that tops this point by ORO_CLEAR starts stealing its
# rain, and a deep wall (the Range at 950m) takes ORO_SHADOW of it.
# Ground that RISES just downwind is the windward slope of the next
# barrier: the air is being forced up right here, so it rains harder.
# One mountain interrupting one wind = a dozen climates.
const ORO_UP := [400.0, 800.0, 1300.0, 1900.0, 2600.0]  # upwind barrier probes (m)
const ORO_DOWN := [450.0, 950.0]  # downwind rise probes (m)
# A valley does NOT sit in the shadow of its own rim — rain falls over
# small barriers; only a big sustained wall (the Range) wrings the air
# dry. Hence the generous clearance before any shading begins.
const ORO_CLEAR := 120.0  # a barrier must top us by this before it shades
const ORO_DEEP := 500.0  # excess barrier height for a full-depth shadow
const ORO_SHADOW := 0.82  # fraction of rain a deep lee loses
const ORO_LIFT := 0.5  # windward-slope bonus at full rise


## Terrain shapes the weather (the biome response): high ground wrings
## rain out of passing fronts, the lee of a big barrier goes DRY (rain
## shadow — the orographic term reads the front's travel direction),
## and ridge-tops run windier; the open sea feeds rain and kills dust;
## low dry ground starves rain and breeds it. Deterministic (pure
## terrain reads), so the hourly sims fingerprint cleanly.
func _biome_scale(x: float, z: float, prop: String, v: float,
		dx := 0.0, dz := 0.0) -> float:
	if v <= 0.0:
		return v
	var h: float = Terrain.height(x, z)
	match prop:
		"rain":
			v *= 0.85 + 0.7 * smoothstep(50.0, 220.0, h)
			if h < Terrain.sea_level + 0.5:
				v *= 1.15  # open water feeds the band
			if dx != 0.0 or dz != 0.0:
				v *= _orographic(x, z, dx, dz)
		"dust":
			if h < Terrain.sea_level + 1.0:
				return 0.0  # no sand to lift off open water
			v *= 0.6 + 0.8 * (1.0 - smoothstep(40.0, 180.0, h))  # low dry basins breed it
		"wind":
			v *= 1.0 + 0.3 * smoothstep(60.0, 220.0, h)  # ridge-tops run windier
	return v


## The rain-shadow factor at a point for wet air traveling along
## (dx,dz): <1 in the lee of a barrier, >1 on a windward slope.
func _orographic(x: float, z: float, dx: float, dz: float) -> float:
	var here: float = maxf(Terrain.height(x, z), 0.0)
	var barrier := 0.0
	for d: float in ORO_UP:
		barrier = maxf(barrier, Terrain.height(x - dx * d, z - dz * d))
	var shadow := 1.0 - ORO_SHADOW * smoothstep(
			ORO_CLEAR, ORO_CLEAR + ORO_DEEP, barrier - here)
	var rise := 0.0
	for d: float in ORO_DOWN:
		rise = maxf(rise, Terrain.height(x + dx * d, z + dz * d) - here)
	return shadow * (1.0 + ORO_LIFT * smoothstep(40.0, 220.0, rise))


## Storm/menace intensity over a world position (the old meaning).
func storminess_at(x: float, z: float) -> float:
	return property_at(x, z, "menace")


## Rainfall over a world position, 0..1 — drizzle wets slowly, storms
## pour; Hydrology and Climate read THIS, so rain is continuous.
func rain_at(x: float, z: float) -> float:
	return property_at(x, z, "rain")


func _focus_xz() -> Vector2:
	if Toolkit.active:
		var p := Toolkit.cam_position()
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
	var fx := _focus_xz()
	# wind keeps a floor at band edges (presentation), then the ridge boost.
	wind = lerpf(wind, _biome_scale(fx.x, fx.y, "wind",
		float(k.wind) * lerpf(0.55, 1.0, lw.lead)), blend)
	storminess = lerpf(storminess, float(k.menace) * lw.lead, blend)
	rain = lerpf(rain, property_at(fx.x, fx.y, "rain"), blend)
	cloud = lerpf(cloud, float(k.cloud) * lerpf(0.5, 1.0, lw.lead), blend)
	dust = lerpf(dust, property_at(fx.x, fx.y, "dust"), blend)
	# Push to the shader only on visible change (perf 2026-07-09): the
	# sim vars above keep their exact per-frame eases — only redundant
	# RenderingServer traffic is skipped (sub-thousandth steps).
	if absf(wind - _set_wind) > 5e-4:
		_set_wind = wind
		RenderingServer.global_shader_parameter_set("wind_strength", wind)
	if wind_dir.distance_squared_to(_set_wind_dir) > 1e-8:
		_set_wind_dir = wind_dir
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


## Engage / release the weather lock. Idempotent; mirrors to WorldState so it
## saves and Strata reads truth. No re-seat is needed on release (unlike the
## clock's swallowed gap): weather evolves on hour_tick, not a wall delta —
## while held the ticks simply did nothing, and the next tick after release
## resumes the chain from the fronts exactly as they stood.
func set_hold(on: bool) -> void:
	if on == held:
		return
	held = on
	WorldState.set_value("weather.hold", held)


func _transition(_hour: int) -> void:
	# The lock (2026-07-09): a held sky skips all evolution — no march, no
	# spawn, no wind wander — and does NOT re-save (nothing changed). The
	# per-frame _process keeps rendering the frozen fronts. Catch-up replays
	# hour_ticks through here, so a lock engaged before a long sleep honestly
	# holds the weather across the whole skipped stretch.
	if held:
		return
	# Flag ON (STRATA_CONTOUR=1): the Contour §6 `Weather` system owns the front
	# chain (march + spawn/decay + wind drift), consuming the SAME seeded stream.
	# The presentation-snapshot writes (state/wind) + the twin's persist shape
	# (snapped wind_angle, deep-copied fronts) stay identical, so flag-ON is
	# byte-identical to the twin below (the four-run matrix's bar).
	var bridge := _route_contour()
	if bridge != null:
		if not _transition_contour(bridge):
			return  # a refused tick already push_error'd — never a silent twin
		WorldState.set_value("weather.state", state)
		WorldState.set_value("weather.wind", wind)
		WorldState.set_value("weather.wind_angle", snappedf(_wind_angle, 0.001))
		WorldState.set_value("weather.fronts", fronts.duplicate(true))
		return
	# --- GDScript twin (flag OFF, default — forever byte-identical) ---
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


## The flag-ON hour tick: hand the front chain to the Contour `Weather` system.
## Seeds the SAME content + focus the twin reads (kinds/transitions/biases,
## season/storminess), the persistent state it owns (fronts/wind_angle/last_kind),
## and the SEEDED stream state pulled off Rng.stream("weather") — so the system
## draws from the identical stream and, on write-back, we thread the advanced
## state BACK into Rng.stream so the autoload persists it and both paths stay in
## lockstep (pcg_* is bit-exact to RandomPCG). Returns false on a refused tick
## (loud — never a silent GDScript pass).
func _transition_contour(bridge: ContourBridge) -> bool:
	var stream := Rng.stream("weather")
	var inputs := {
		"weather.season": GameClock.season,
		"weather.storminess": storminess,
		"weather.kinds": KINDS,
		"weather.transitions": TRANSITIONS,
		"weather.wet_kinds": WET_KINDS,
		"weather.storm_bias": SEASON_STORM_BIAS,
		"weather.gale_bias": SEASON_GALE_BIAS,
		"weather.fronts": fronts,
		"weather.wind_angle": _wind_angle,
		"weather.last_kind": _last_kind,
		"weather.rng": int(stream.state),
	}
	_contour_calls += 1
	if not bridge.tick_seeded(inputs, 3600.0):
		push_error("[weather] STRATA_CONTOUR=1 but the Weather system tick was refused"
			+ " — refusing to silently run the GDScript twin")
		return false
	# Read back the system's declared writes; thread the advanced stream state
	# back into the autoload so it persists and the next tick continues it.
	fronts = _fronts_from(WorldState.get_value("weather.fronts", []))
	_wind_angle = float(WorldState.get_value("weather.wind_angle", _wind_angle))
	_last_kind = String(WorldState.get_value("weather.last_kind", _last_kind))
	stream.state = int(WorldState.get_value("weather.rng", int(stream.state)))
	wind_dir = Vector2.from_angle(_wind_angle)
	return true


## Rebuild a typed Array[Dictionary] of fronts from a Variant array (the bridge
## returns them as untyped dicts) — the load_state reconstruction shape.
func _fronts_from(v: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v is Array:
		for f: Variant in v:
			if f is Dictionary and f.has("kind") and f.has("edge"):
				out.append({"kind": String(f.kind), "dx": float(f.dx),
					"dz": float(f.dz), "edge": float(f.edge),
					"width": float(f.width), "speed": float(f.speed)})
	return out


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
