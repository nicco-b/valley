extends Node
## FloraLife (autoload, the Elements): the flora lifecycle. One global
## vitality value the whole valley's vegetation breathes with (reads the
## Climate substrate and eases toward it over days — a storm doesn't
## green the valley overnight), now refracted through space and species:
##
##   species        data/flora/*.json — billboard art per lifecycle
##                  stage, biome scatter weights, moisture needs, forage
##                  yields. Content is data: a new plant is one JSON file.
##   vitality_at()  STATELESS spatial vitality — the global value shifted
##                  by how the local Climate (moisture, temperature)
##                  differs from the reference clearing. Pond banks stay
##                  green through a dry spell; the snowline browns first.
##                  No per-cell tick, no save growth: derived, not stored.
##   stage_for()    lifecycle stage (sprout/grow/bloom/seed/dry) from
##                  season + vitality, pure — scatter picks stage art at
##                  cell build.
##   depletion      the SPARSE honest-harvest state: only cells someone
##                  actually gathered from hold a value; they regrow on
##                  hour_tick (faster when the land is green) and forget
##                  themselves when whole again. No cell-reset respawns —
##                  regrowth is the sim, and the save only remembers
##                  wounds that haven't healed.
##
## Published as the flora_vitality global shader param (billboards tint
## toward straw as it falls). Writes flora.bloom / flora.parched with
## hysteresis — sim-authored story-seed hooks ("The Dry Spell").
##
## Placeholder: stage art slots all point at the grow painting until her
## stage variants land (same slots); per-species populations (counts,
## seed drift) wait on the life-timescale axiom.
##
## Sim contract: stateful (vitality + depletion), advanced on hour_tick
## (catch-up replays it), persisted via WorldState ("flora.vitality",
## "flora.cells"), world_state_reader group. No randomness — nothing to
## stream.

signal cell_changed(cell: Vector2i)  ## depletion moved (harvest or regrown)

const EASE_PER_HOUR := 0.06  # ~a day to close most of the gap
const SHADER_EASE := 0.3  # per-second visual approach
const SEASON_BASE := {"spring": 0.85, "summer": 0.68, "autumn": 0.5, "winter": 0.35}
## Open valley floor, away from the pond — flora must feel dry spells,
## and pond banks never do (Climate.moisture floors near open water).
const REFERENCE := Vector2(0.0, -150.0)

const CELL_SIZE := 128.0  # must match world_streamer.gd CELL_SIZE
const GATHER_TAKE := 0.34  # one gather's wound; ~3 empty a cell
const REGROW_PER_HOUR := 1.0 / 48.0  # two days to heal at neutral vitality

var vitality := 0.7
var species: Array[Dictionary] = []  # sorted by filename — deterministic

var _shader_vitality := 0.7
var _set_vitality := -1e9  # last-pushed shader value (perf guard)
var _cells: Dictionary = {}  # Vector2i -> taken (0..1]; sparse, self-forgetting

# --- Contour routing (PLAN_ENGINE E2, Mission C1: the FIRST SYSTEM FILE) --------
## The hourly vitality ease is the first SYSTEM-TIER port to run inside the
## shipping sim (docs/PORT_LEDGER.md Wave C). When STRATA_CONTOUR=1 — a boot-time
## sim flag, read once, DevMode-independent, default OFF — _hourly's ease routes
## through the native Contour §6 `Flora` system (game/world/flora_life.ct, via the
## systems bridge game/sim/contour_bridge.gd) instead of the GDScript twin. Flag
## OFF is byte-identical GDScript. NO SILENT FALLBACK (the honesty law): flag ON
## with the kernel absent / the module uncompilable / a refused tick is a LOUD
## push_error, never a quiet twin. The routed ticks carry a counter
## (contour_status) so the soak/scene test can prove the system actually ran
## inside the fingerprinted window.
const _CONTOUR_MODULE := "res://game/world/flora_life.ct"
## 0 unresolved · 1 off (flag unset) · 2 engaged (bridge live) · -1 refused.
var _contour_mode := 0
var _contour_bridge: ContourBridge = null
var _contour_calls := 0   # system ticks answered by Contour (the engaged-path probe)
## The substrate Rung 2 DARK sub-flag: STRATA_CONTOUR_HELD=1 (requires
## STRATA_CONTOUR=1) routes the same Flora system through the PERSISTENT HELD
## WORLD (bridge.tick_held) — created once, ticked in place, only the write-diff
## crossing back — instead of the whole-world copy path (tick_seeded). Default OFF
## and byte-inert; the held ticks carry their OWN counter so the soak proves the
## in-place path ran (a distinct engagement, not a silent copy-path fallback).
var _contour_held := false
var _contour_held_ticks := 0


func _ready() -> void:
	add_to_group("world_state_reader")
	_load_species()
	load_state()
	GameClock.hour_tick.connect(_hourly)


func _load_species() -> void:
	species.clear()
	var records := Records.load_dir("res://data/flora", {
		"id": TYPE_STRING, "name": TYPE_STRING, "height": TYPE_FLOAT,
		"art": TYPE_DICTIONARY, "biomes": TYPE_DICTIONARY,
	})
	var keys := records.keys()
	keys.sort()
	for k in keys:
		species.append(records[k])


func load_state() -> void:
	vitality = float(WorldState.get_value("flora.vitality", vitality))
	_shader_vitality = vitality
	_cells.clear()
	var saved: Variant = WorldState.get_value("flora.cells", {})
	if saved is Dictionary:
		for k: String in saved:
			var parts := (k as String).split("_")
			if parts.size() == 2:
				_cells[Vector2i(parts[0].to_int(), parts[1].to_int())] = float(saved[k])


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-SHADER_EASE * delta)
	_shader_vitality = lerpf(_shader_vitality, vitality, blend)
	# Set-on-change (perf 2026-07-09): the ease converges; skip the
	# redundant RenderingServer push below a visible step.
	if absf(_shader_vitality - _set_vitality) > 5e-4:
		_set_vitality = _shader_vitality
		RenderingServer.global_shader_parameter_set("flora_vitality", _shader_vitality)


## Where vitality wants to settle for a given season, ground moisture,
## and temperature. Static and pure so tests can pin the response.
static func target_for(season: String, moist: float, temp: float) -> float:
	var base: float = SEASON_BASE.get(season, 0.6)
	var water := 0.45 * (moist - 0.35)  # dry ground starves, wet ground feeds
	var heat := -0.03 * maxf(temp - 30.0, 0.0)  # scorching + dry = parched
	var cold := -0.02 * maxf(2.0 - temp, 0.0)  # frost bites what's green
	return clampf(base + water + heat + cold, 0.05, 1.0)


## Local vitality: the global value shifted by how this spot's climate
## target differs from the reference clearing's. Stateless — derived
## from live Climate fields, never stored, never ticked.
func vitality_at(x: float, z: float) -> float:
	var season: String = GameClock.season
	var local := target_for(season, Climate.moisture(x, z), Climate.temperature(x, z))
	var ref := target_for(season,
			Climate.moisture(REFERENCE.x, REFERENCE.y),
			Climate.temperature(REFERENCE.x, REFERENCE.y))
	return clampf(vitality + (local - ref), 0.05, 1.0)


## Lifecycle stage from season + local vitality. Pure; thresholds are
## the contract her stage paintings will land against.
static func stage_for(season: String, v: float) -> String:
	if v < 0.28:
		return "dry"
	match season:
		"spring":
			return "bloom" if v >= 0.8 else ("sprout" if v < 0.5 else "grow")
		"summer":
			return "bloom" if v >= 0.85 else "grow"
		"autumn":
			return "seed" if v >= 0.5 else "grow"
		"winter":
			return "dry" if v < 0.55 else "grow"
	return "grow"


## The billboard texture for a species at a stage; missing stages fall
## back to `grow` (the labeled-placeholder path for her stage variants).
static func stage_art(def: Dictionary, stage: String) -> String:
	var art: Dictionary = def["art"]
	if art.has(stage):
		return str(art[stage])
	return str(art.get("grow", art.values()[0] if not art.is_empty() else ""))


## A species' scatter weight at a spot: biome composition weight, faded
## out as local ground moisture falls below the species' need.
static func species_weight(def: Dictionary, biome_id: String, moist: float) -> float:
	var w: float
	if biome_id.is_empty():
		w = float(def.get("weight_default", 0.0))
	else:
		w = float((def["biomes"] as Dictionary).get(biome_id, 0.0))
	var need := float(def.get("moisture_need", 0.0))
	return w * clampf((moist - need + 0.15) / 0.15, 0.0, 1.0)


## Gathering wounds the cell under (x,z); scatter density and forage
## spots read the wound, and the hourly tick heals it.
func harvest_at(x: float, z: float, take := GATHER_TAKE) -> void:
	var cell := Vector2i(floori(x / CELL_SIZE), floori(z / CELL_SIZE))
	_cells[cell] = minf(float(_cells.get(cell, 0.0)) + take, 1.0)
	_write_cells()
	cell_changed.emit(cell)


## How gathered-out a cell is: 0 untouched .. 1 stripped bare.
func depletion(cell: Vector2i) -> float:
	return float(_cells.get(cell, 0.0))


## Stable digest of the depletion state for the soak fingerprint.
func depletion_digest() -> String:
	var keys := _cells.keys()
	keys.sort()
	var parts := PackedStringArray()
	for c: Vector2i in keys:
		parts.append("%d,%d=%.3f" % [c.x, c.y, float(_cells[c])])
	return ";".join(parts)


## Toolkit: the green line.
func summary() -> String:
	return "vitality=%.2f species=%d gathered_cells=%d%s%s" % [
		vitality, species.size(), _cells.size(),
		"  BLOOM" if WorldState.has_flag("flora.bloom") else "",
		"  PARCHED" if WorldState.has_flag("flora.parched") else ""]


## The live systems bridge when routing is engaged, else null (flag off, or a
## loud refusal). Resolves once at first tick (boot); flag-off is pure GDScript.
func _route_contour() -> ContourBridge:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour_bridge


func _contour_resolve() -> void:
	var verdict := Contour.decide("flora")
	if verdict != Contour.ROUTE_ENGAGE:
		_contour_mode = verdict   # ROUTE_FALLBACK (GDScript twin) or ROUTE_REFUSE (loud, mode -1)
		return
	# Routing engaged — compile the module (a compile failure still refuses loudly).
	var bridge := ContourBridge.new(WorldState)
	var err := bridge.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[flora] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour_bridge = bridge
	_contour_mode = 2
	# The Rung 2 DARK sub-flag: only meaningful once the bridge is live. Off by
	# default; on, the hourly ease routes through the persistent held world.
	_contour_held = OS.get_environment("STRATA_CONTOUR_HELD") == "1"


## Routing introspection for the scene test / soak (proves the system ran, not a
## silent fallback): the resolved mode, whether it engaged, the tick count, and —
## for the substrate Rung 2 sub-flag — whether the held path ran and how often
## (held_ticks climbs only when STRATA_CONTOUR_HELD=1 routed the in-place tick).
func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls,
		"held": _contour_held, "held_ticks": _contour_held_ticks}


func _hourly(_h: int) -> void:
	var moist := Climate.moisture(REFERENCE.x, REFERENCE.y)
	var temp := Climate.temperature(REFERENCE.x, REFERENCE.y)
	var bridge := _route_contour()
	if bridge != null:
		# Flag ON (STRATA_CONTOUR=1): the Contour §6 `Flora` system owns the
		# vitality ease. It reads the SAME environment the twin below reads
		# (season/moist/temp, handed in as flora.env) plus its own persisted
		# state (flora.vitality, overlaid from the live value so a fresh world
		# with no mirror still seeds), advances one hour step, and writes
		# flora.vitality back into WorldState. We read it back — every downstream
		# line (hysteresis, _regrow, the shader ease) runs unchanged on it.
		_contour_calls += 1
		var env := {"season": GameClock.season, "moist": moist, "temp": temp}
		var inputs := {"flora.env": env, "flora.vitality": vitality}
		# STRATA_CONTOUR_HELD=1 (requires STRATA_CONTOUR=1): the PERSISTENT HELD
		# WORLD path (substrate Rung 2) — the held world is created once and ticked
		# IN PLACE, only the write-diff crossing back. Byte-identical WorldState
		# effect to tick_seeded (the copy path stays the oracle); its own counter
		# proves the in-place path ran. Default OFF routes the copy path below.
		var applied: bool
		if _contour_held:
			applied = bridge.tick_held(inputs, 3600.0)
			if applied:
				_contour_held_ticks += 1
		else:
			applied = bridge.tick_seeded(inputs, 3600.0)
		if not applied:
			push_error("[flora] STRATA_CONTOUR=1 but the Flora system tick was refused"
				+ " — refusing to silently run the GDScript twin")
			return
		vitality = float(WorldState.get_value("flora.vitality", vitality))
	else:
		# Flag OFF (default): the GDScript twin, forever byte-identical.
		var target := target_for(GameClock.season, moist, temp)
		vitality = snappedf(clampf(
			vitality + (target - vitality) * EASE_PER_HOUR, 0.0, 1.0), 0.001)
	WorldState.set_value("flora.vitality", vitality)
	# Hysteresis on the flags so a boundary flicker can't spam story-seeds.
	if vitality >= 0.8 and not WorldState.has_flag("flora.bloom"):
		WorldState.set_value("flora.bloom", true)
		HUD.notify("the valley is blooming")
		print("[flora] bloom (vitality %.2f)" % vitality)
	elif vitality < 0.7 and WorldState.has_flag("flora.bloom"):
		WorldState.set_value("flora.bloom", false)
	if vitality <= 0.25 and not WorldState.has_flag("flora.parched"):
		WorldState.set_value("flora.parched", true)
		HUD.notify("the valley is parched")
		print("[flora] parched (vitality %.2f)" % vitality)
	elif vitality > 0.35 and WorldState.has_flag("flora.parched"):
		WorldState.set_value("flora.parched", false)
	_regrow()


## Heal every remembered wound a little; green land heals faster,
## drought slows it. Whole cells are forgotten — selective memory.
func _regrow() -> void:
	if _cells.is_empty():
		return
	var healed: Array[Vector2i] = []
	for cell: Vector2i in _cells:
		var cx := (float(cell.x) + 0.5) * CELL_SIZE
		var cz := (float(cell.y) + 0.5) * CELL_SIZE
		var rate := REGROW_PER_HOUR * lerpf(0.3, 1.4, vitality_at(cx, cz))
		var taken := float(_cells[cell]) - rate
		if taken <= 0.0:
			healed.append(cell)
		else:
			_cells[cell] = snappedf(taken, 0.001)
	for cell in healed:
		_cells.erase(cell)
	_write_cells()
	for cell in healed:
		cell_changed.emit(cell)


func _write_cells() -> void:
	var out: Dictionary = {}
	for cell: Vector2i in _cells:
		out["%d_%d" % [cell.x, cell.y]] = float(_cells[cell])
	WorldState.set_value("flora.cells", out)
