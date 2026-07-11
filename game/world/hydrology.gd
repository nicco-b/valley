extends Node
## Hydrology (autoload): the canonical water tier (DECISIONS 2026-07-04 —
## water is simulated across the whole watershed). A coarse grid over the
## valley is flow-routed downhill (D8) once at first need, giving every
## river and lake its real catchment area; from then on an hourly water
## balance runs forever: storm rain becomes runoff (scaled by how soaked
## the ground already is — Climate.wetness), snowmelt drains in, rivers
## are linear reservoirs whose discharge sets their surface offset, lakes
## integrate inflow minus evaporation and outflow. Terrain.water_surface()
## adds these offsets, so the pond breathes and fords open/close from real
## routed water — no scripting.
##
## Sim contract: state is per-basin scalars (river storages, lake levels);
## everything advances on hour_tick so GameClock.advance_hours replays
## closed/asleep stretches; state persists via WorldState ("water.*") and
## load_state() (world_state_reader). The GPU dynamics tiers (SIM tier 2/3)
## will seed from this tier and are never authoritative.

signal levels_changed  # water surface offsets moved (at most hourly)

# Catchment grid resolution; the DOMAIN (center + size) comes from
# data/water/watersheds/*.json — the map is replaceable, the system
# isn't. One watershed record for now; field-per-watershed when the
# world grows regions.
const GRID_N := 256
const WATERSHED_DIR := "res://data/water/watersheds"

# Loaded watershed domain (defaults match the home valley fixture).
var center := Vector2(65.0, -285.0)
var domain := 2048.0
var grid_m := 8.0  # domain / GRID_N

# Water balance (mood-physics: dimensioned, tuned to feel right).
const STORM_RAIN_M := 0.004  # rain per storm hour (4mm/h)
const RUNOFF_DRY := 0.1  # parched ground soaks rain in...
const RUNOFF_WET := 0.7  # ...saturated ground sheds it into the streams
const SNOW_MELT_M := 0.02  # water equivalent of full snow cover, per unit melted
const RIVER_K := 0.12  # reservoir recession per hour (flashy brook, ~8h e-fold)
const SPRING_M3H := 60.0  # baseflow springs at full wetness (scaled down dry)
const Q_REF := 55.0  # discharge that maps to the authored river surface
const RIVER_LEVEL_MIN := -0.35
const RIVER_LEVEL_MAX := 0.3
const EVAP_M_PER_DEG := 0.00002  # lake evaporation per hour per warm degree
const LAKE_OUT_K := 0.07  # outflow/seepage per hour per meter above deep rail
const LAKE_LEVEL_MIN := -0.5
const LAKE_LEVEL_MAX := 0.35

# Per-basin state (canonical, saved): river id -> storage m^3,
# lake id -> level offset m.
var river_storage: Dictionary = {}
var lake_level: Dictionary = {}

# The REGION tier (2026-07-05): generated (no_sim) rivers breathe too —
# same linear-reservoir balance, rained on through Weather.rain_at at
# their own midpoint (fronts are spatial), catchment measured upstream
# (record catchment_m2 — today that is Strata's D8 flow accumulation,
# hyd_* records via the P2 import; the map pen estimates its own). Kept
# in a SEPARATE dict that the soak fingerprint never digests: imported
# records are a regenerable local cache, and the fingerprint must not
# depend on what's in it. Saved via WorldState water.<id>.* like
# everything else; deterministic all the same (advanced only on
# hour_tick from Weather's Rng-streamed fronts).
const REGION_SPRING_M3H := 25.0  # flat spring floor: idle flow_norm ~0.35,
	# a visibly alive river between rains (mood physics, like SPRING_M3H)
const REGION_BASEFLOW_M := 1e-4  # + m³/h per m² catchment on top
const REGION_CATCHMENT_FALLBACK := 4e4  # old records without catchment_m2
var region_storage: Dictionary = {}
# Per-river flow reference (id -> m³/h), derived from each region river's
# own baseflow at seeding. Strata catchments span 0.04..130 km², so the
# brook-tuned global Q_REF would peg every big river's flow_norm at 1.0
# forever — against its OWN baseflow, idle sits at the tier's design line
# (~0.35, the REGION_SPRING_M3H note) and storms still climb toward 1.
var region_qref: Dictionary = {}
# Region LAKES (ONE_APP P2): Strata-imported lakes (no_sim records, the
# hyd_* cache) breathe on the same hourly balance as authored lakes but
# under their OWN sky (rain_at their center), and their levels live here —
# off the soak digest, same law as region_storage: the fingerprint must
# not depend on what's in a regenerable import cache.
var region_lake_level: Dictionary = {}

# Boot-derived (deterministic function of terrain + records, not saved):
# basin id -> catchment area m^2. Built lazily on the first hour tick so
# a title-screen boot never pays for it.
var catchment_area: Dictionary = {}
# The routed basin per grid cell (index into lakes-then-rivers order, -2 =
# leaves the domain): kept for observability — Toolkit overlays and
# probes read where any point's rain ends up via basin_at_world().
var basin_grid := PackedInt32Array()
var basin_names: Array[String] = []
var _catchments_built := false
var _catch_task := -1
var _last_snow := 0.0

# --- Contour routing (PLAN_ENGINE E2, Wave D2: the RIVER RESERVOIR) --------------
## The hourly per-basin reservoir balance is hydrology's crossing RULE (docs/
## PORT_LEDGER.md Wave D2). THE SPLIT: the D8 flow-routing that MEASURES each
## basin's catchment (a 256² heap-flood + steepest-descent — per-cell grid math,
## loomkernel-class) STAYS engine-side; its output (the catchment aggregate) plus
## the spatial rain sampling (Weather.rain_at at each river's own midpoint — the
## rain shadow) are seeded in, exactly the climate DESIGN-CALL precedent. What
## crosses is the linear-reservoir recession that DECIDES discharge from those
## aggregates — the region rivers' hourly balance — as the Contour §6 `Hydrology`
## system (game/world/hydrology.ct, via game/sim/contour_bridge.gd). When
## STRATA_CONTOUR=1 (boot-time flag, read once, default OFF) the region-river
## evolution routes native; flag OFF is byte-identical GDScript through the SAME
## region_river_step body. NO SILENT FALLBACK (the honesty law): flag ON with the
## kernel absent / the module uncompilable / a refused tick is a LOUD push_error.
## The routed ticks carry a counter so the soak/scene test proves the system ran.
const _CONTOUR_MODULE := "res://game/world/hydrology.ct"
## 0 unresolved · 1 off (flag unset) · 2 engaged (bridge live) · -1 refused.
var _contour_mode := 0
var _contour_bridge: ContourBridge = null
var _contour_calls := 0   # region-river ticks answered by Contour (the engaged probe)


func _ready() -> void:
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	_load_watershed()
	for r in Terrain.sim_rivers():
		river_storage[r.id] = SPRING_M3H / RIVER_K  # boot at baseflow equilibrium
	for r in Terrain.rivers:
		if r.get("no_sim", false):
			_seed_region_river(r)
	for w in Terrain.water_bodies:
		if w.get("no_sim", false):
			_seed_region_lake(w)
		else:
			lake_level[w.id] = 0.0
	load_state()
	# The routing pass costs ~1s of pure Terrain reads — start it on a
	# worker at boot so the first hour tick never hitches the frame.
	_catch_task = WorkerThreadPool.add_task(_build_catchments)
	GameClock.hour_tick.connect(_hourly)
	# The map river pen adds one no_sim river mid-session; seed its reservoir
	# at baseflow so its ribbon flows from the first frame.
	Terrain.river_added.connect(func(r: Dictionary) -> void:
		if r.get("no_sim", false):
			_seed_region_river(r))
	# A whole-water reload (reload_world / Strata import while running) rebuilds
	# Terrain.rivers from disk but leaves the region tier here untouched — the
	# fresh hyd_* rivers would idle at zero discharge. Re-seed the newcomers,
	# preserving every river that is already breathing.
	Terrain.water_reloaded.connect(_reseed_region_water)


func _exit_tree() -> void:
	# Reap the boot-time routing task before the tree (and the autoloads it
	# reads — Terrain above all) tears down under it. A quit that lands
	# inside the task's ~1s window otherwise aborts the process at exit —
	# caught by the unit runner the moment unrelated boot timing shifted.
	if _catch_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_catch_task)
		_catch_task = -1


func _ensure_catchments() -> void:
	if _catchments_built:
		return
	if _catch_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_catch_task)
		_catch_task = -1
	else:
		_build_catchments()


func load_state() -> void:
	for id in river_storage:
		river_storage[id] = float(WorldState.get_value(
			"water.%s.storage" % id, river_storage[id]))
	for id in region_storage:
		region_storage[id] = float(WorldState.get_value(
			"water.%s.storage" % id, region_storage[id]))
	for id in lake_level:
		lake_level[id] = float(WorldState.get_value(
			"water.%s.level" % id, lake_level[id]))
	for id in region_lake_level:
		region_lake_level[id] = float(WorldState.get_value(
			"water.%s.level" % id, region_lake_level[id]))
	# Snowmelt is a per-hour delta (last hour's cover minus this hour's), so
	# _last_snow must resume from the SAVED snow, not boot's 0.0 — otherwise
	# the first replayed catch-up hour drops that hour's meltwater runoff and
	# every river/lake diverges from continuous play. Read it straight from
	# WorldState (fully restored before any load_state runs) so this doesn't
	# depend on Climate's world_state_reader ordering. On a fresh boot the
	# key is absent and this stays 0.0, matching Climate.snow.
	_last_snow = float(WorldState.get_value("climate.snow", _last_snow))
	_push_levels()


# The watershed record: which patch of world this instance simulates.
# Records loads after us in autoload order, so parse directly (the
# Terrain pattern). Missing dir/file keeps the fixture defaults.
func _load_watershed() -> void:
	var dir := DirAccess.open(WATERSHED_DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(WATERSHED_DIR + "/" + f))
		if parsed is Dictionary and parsed.has("center") and parsed.has("size"):
			var rec: Dictionary = parsed
			var c: Dictionary = rec["center"]
			center = Vector2(float(c["x"]), float(c["z"]))
			domain = float(rec["size"])
			grid_m = domain / GRID_N
			return  # one watershed for now; per-region instances later
		push_error("[hydrology] bad watershed record (needs center/size): " + f)


## River discharge right now, m^3/h.
func discharge(river_id: String) -> float:
	if region_storage.has(river_id):
		return float(region_storage[river_id]) * RIVER_K
	return float(river_storage.get(river_id, 0.0)) * RIVER_K


# Seed one region river's reservoir at its baseflow equilibrium and pin its
# flow reference — the shared seeding math for boot, the pen, and reloads.
# A river ALREADY breathing is left exactly as it is: an unrelated reload
# (a paint stroke elsewhere, a re-import of a different tile) must never
# reset a playing world's river state.
func _seed_region_river(r: Dictionary) -> void:
	var id: String = r.id
	if region_storage.has(id):
		return
	region_storage[id] = _region_baseflow(r) / RIVER_K
	region_qref[id] = _region_qref(r)


# Seed one region lake's level, unless it is already tracked (same live-state
# rule as the rivers).
func _seed_region_lake(w: Dictionary) -> void:
	if not region_lake_level.has(w.id):
		region_lake_level[w.id] = 0.0


## Re-seed the REGION tier after a live water reload (Terrain.water_reloaded).
## _reload_water rebuilt Terrain.rivers/water_bodies from disk; every no_sim
## newcomer that lacks a reservoir gets the SAME baseflow seed _ready gives,
## so its discharge/flow_norm read real water from the first frame instead of
## the "0 m3/h, norm 0.00" of an unseeded river. Rivers already breathing keep
## their live storage; their visual level is recomputed from their (preserved)
## discharge, because _reload_water zeroed Terrain.river_levels on the rebuild.
func _reseed_region_water() -> void:
	for r in Terrain.rivers:
		if not r.get("no_sim", false):
			continue
		_seed_region_river(r)
		if r.idx < Terrain.river_levels.size():
			Terrain.river_levels[r.idx] = snappedf(clampf(lerpf(RIVER_LEVEL_MIN,
					RIVER_LEVEL_MAX, flow_norm(r.id)), RIVER_LEVEL_MIN,
					RIVER_LEVEL_MAX), 0.001)
	for w in Terrain.water_bodies:
		if w.get("no_sim", false):
			_seed_region_lake(w)
	_push_levels()


# Spring inflow for a region river, m³/h — scaled to its catchment so a
# big river idles wider than a gully (the brook's flat SPRING_M3H would
# make every generated river identically lazy).
func _region_baseflow(r: Dictionary) -> float:
	return REGION_SPRING_M3H + maxf(float(r.get("catchment", 0.0)),
		REGION_CATCHMENT_FALLBACK) * REGION_BASEFLOW_M


## One region river's next reservoir storage, m³ — the linear-reservoir RULE
## (DECISIONS 2026-07-04: rivers are linear reservoirs whose discharge sets the
## surface offset). Catchment runoff + baseflow flow in; the reservoir sheds a
## fixed fraction (RIVER_K) as discharge; the remainder is snapped and carried.
## The pure per-basin leaf of the hourly balance, extracted so the Contour §6
## `Hydrology` system and this twin share ONE body (game/world/hydrology.ct),
## Plumb-certified bit-identical. `area` (the catchment aggregate the D8 routing
## measured), `rain` (the rain-shadowed local rainfall) and `baseflow` are the
## host-sampled per-river environment — all engine-bound, seeded in; pure over
## its args.
static func region_river_step(storage: float, area: float, rain: float,
		runoff: float, baseflow: float) -> float:
	storage += area * rain * runoff + baseflow
	var q := storage * RIVER_K
	storage -= q
	return snappedf(storage, 0.01)


## One WATERSHED (sim-tier) river's next reservoir storage, m³ — the SIBLING of
## region_river_step for the home-grid rivers (docs/PORT_LEDGER.md Wave D3). Same
## linear reservoir (RIVER_K recession, snappedf 0.01) but a DIFFERENT inflow
## grouping: the sim tier folds meltwater into the runoff term and adds a
## catchment-flat spring — area*(rain*runoff+melt)+spring — where the region tier
## is area*rain*runoff+baseflow. Float add is not associative, so the two
## groupings differ bit-for-bit; each tier keeps its OWN certified leaf (NOT a
## reuse of region_river_step). The pure per-basin leaf of the sim-tier balance,
## extracted so the Contour §6 port (game/world/hydrology.ct) and this twin share
## ONE body, Plumb-certified bit-identical. `area`/`rain`/`melt`/`spring` are the
## host-sampled per-river environment — pure over its args.
static func sim_river_step(storage: float, area: float, rain: float,
		runoff: float, melt: float, spring: float) -> float:
	storage += area * (rain * runoff + melt) + spring
	var q := storage * RIVER_K
	storage -= q
	return snappedf(storage, 0.01)


# Flow reference for a region river: its own baseflow, weighted so the
# idle norm lands on the tier's design line (~0.35).
func _region_qref(r: Dictionary) -> float:
	return _region_baseflow(r) * (1.0 - 0.35) / 0.35


## Discharge normalized 0..1 against the flow reference — shader flow
## speed, waterfall loudness, and story seeds read this. Watershed rivers
## reference the authored-surface Q_REF; region rivers reference their
## own baseflow (their real catchments span four orders of magnitude).
func flow_norm(river_id: String) -> float:
	return flow_norm_of(discharge(river_id), float(region_qref.get(river_id, Q_REF)))


## Discharge normalized against a flow reference: q/(q+qref), the saturating
## curve every shader/story reader sees. The pure leaf of flow_norm, extracted so
## the Contour port (game/world/hydrology.ct) and this twin share ONE body;
## Plumb-certified bit-identical. Reads only its two args — pure.
static func flow_norm_of(q: float, qref: float) -> float:
	return q / (q + qref)


## One lake's next level offset, m — the level-integration RULE (docs/
## PORT_LEDGER.md Wave D3). Inflow (river discharges + own catchment runoff +
## direct rain, all summed by the caller) raises the level; evaporation (warmer
## water loses more) and a level-driven outflow/seepage above the deep rail lower
## it; the result is clamped to the lake's deep/brim rails and snapped. Extracted
## so the Contour §6 port (game/world/hydrology.ct) and this twin share ONE body,
## Plumb-certified bit-identical. The CROSS-BASIN outlet coupling (this lake's
## outflow feeding a DOWNSTREAM river's storage — a different basin) stays
## orchestrated host-side, recomputing the same level-driven outflow from the
## pre-tick level; this leaf is the pure per-lake integration over its four args.
static func lake_step(level: float, inflow: float, lake_area: float,
		lake_t: float) -> float:
	var evap := EVAP_M_PER_DEG * maxf(lake_t, 0.0)
	var outflow := LAKE_OUT_K * maxf(level - LAKE_LEVEL_MIN, 0.0)
	level += inflow / lake_area - evap - outflow
	return snappedf(clampf(level, LAKE_LEVEL_MIN, LAKE_LEVEL_MAX), 0.001)


## A basin's world-panel label: its id, with the gazetteer's name beside it
## when the place has one (`hyd_l1 «The Aquifer Pool»`) — names beside ids,
## the naming desk's WATER surface. Bare id when unnamed (the honest floor).
func _labelled(id: String) -> String:
	return "%s «%s»" % [id, Names.resolve(id)] if Names.has_name(id) else id


## Toolkit: every basin, right now.
func summary() -> String:
	var lines := PackedStringArray()
	for r in Terrain.sim_rivers():
		lines.append("%s: %.0f m3/h (norm %.2f, level %+.2fm)" % [
			_labelled(r.id), discharge(r.id), flow_norm(r.id), Terrain.river_levels[r.idx]])
	for w in Terrain.water_bodies:
		if w.get("no_sim", false):
			lines.append("%s (region): level %+.2fm" % [
				_labelled(w.id), float(region_lake_level.get(w.id, 0.0))])
		else:
			lines.append("%s: level %+.2fm" % [_labelled(w.id), float(lake_level.get(w.id, 0.0))])
	for r in Terrain.rivers:
		if r.get("no_sim", false):
			lines.append("%s (region): %.0f m3/h (norm %.2f, catchment %.1f km2)" % [
				_labelled(r.id), discharge(r.id), flow_norm(r.id),
				float(r.get("catchment", 0.0)) / 1e6])
	return "\n".join(lines)

func _hourly(_h: int) -> void:
	_ensure_catchments()
	# Continuous rain over the watershed (phase C): drizzle feeds the
	# brook gently, a storm floods it; player position irrelevant.
	var rain := STORM_RAIN_M * Weather.rain_at(center.x, center.y)
	var runoff := lerpf(RUNOFF_DRY, RUNOFF_WET, Climate.wetness)
	# Snowmelt: Climate already decided how much cover melted this hour
	# (it runs first on hour_tick); the drop becomes meltwater depth.
	var melt_m := maxf(_last_snow - Climate.snow, 0.0) * SNOW_MELT_M
	_last_snow = Climate.snow
	var t := Climate.temperature(center.x, center.y)

	# Rivers: catchment runoff + springs in, reservoir recession out. The
	# per-basin recession is the sim_river_step leaf (Wave D3) — the sim tier's
	# own inflow grouping, area*(rain*runoff+melt)+spring, distinct from the
	# region tier's. The spatial rain/catchment sampling stays host-side.
	for r in Terrain.sim_rivers():
		var id: String = r.id
		var area: float = catchment_area.get(id, 0.0)
		var spring := SPRING_M3H * lerpf(0.3, 1.3, Climate.wetness)
		river_storage[id] = sim_river_step(river_storage[id], area, rain, runoff, melt_m, spring)
		Terrain.river_levels[r.idx] = snappedf(clampf(lerpf(RIVER_LEVEL_MIN,
				RIVER_LEVEL_MAX, flow_norm(id)), RIVER_LEVEL_MIN, RIVER_LEVEL_MAX), 0.001)
		WorldState.set_value("water.%s.storage" % id, river_storage[id])
		WorldState.set_value("water.%s.flow" % id, snappedf(flow_norm(id), 0.001))

	# Region rivers (generated, off the home watershed grid): the same
	# reservoir balance, but each one lives under ITS OWN sky — rain_at
	# its midpoint — and drains the catchment the erosion bake measured.
	# THE RULE crosses to Contour (Wave D2): the per-basin recession
	# (region_river_step) ticks as the §6 `Hydrology` system when routed; the
	# spatial rain/catchment sampling stays engine-side and is seeded in.
	_route_region_rivers(runoff)

	# Lakes: river discharge + own catchment + direct rain in; evaporation
	# and level-driven outflow/seepage out. Level is depth offset from the
	# authored surface. Region lakes (Strata-imported, no_sim) run the
	# same balance under their own sky — local rain and temperature, fed
	# by the region rivers whose mouths sit on them.
	for w in Terrain.water_bodies:
		var id: String = w.id
		var is_region: bool = w.get("no_sim", false)
		var c: Vector2 = w.center
		var lake_rain := STORM_RAIN_M * Weather.rain_at(c.x, c.y) if is_region else rain
		var lake_t := Climate.temperature(c.x, c.y) if is_region else t
		var lake_area := PI * float(w.radius) * float(w.radius)
		var inflow := 0.0
		for r in (Terrain.rivers if is_region else Terrain.sim_rivers()):
			if r.get("no_sim", false) == is_region and _river_feeds_lake(r, w):
				inflow += discharge(r.id)
		inflow += catchment_area.get(id, 0.0) * (lake_rain * runoff + melt_m)
		inflow += lake_area * lake_rain  # rain falls on the water too
		var level: float = region_lake_level[id] if is_region else lake_level[id]
		# The CROSS-BASIN outlet coupling stays host-side (Wave D3): the outflow
		# goes where the record says — into a DOWNSTREAM river's storage (a
		# different basin, chained water bodies), or "aquifer", the ground, until
		# the underworld exists to receive it. Recompute the same level-driven
		# outflow the lake_step leaf uses (from the pre-tick level) to feed the
		# outlet, then let the leaf integrate this lake's own level.
		var outflow := LAKE_OUT_K * maxf(level - LAKE_LEVEL_MIN, 0.0)
		var outlet: String = w.get("outlet", "aquifer")
		if river_storage.has(outlet):
			river_storage[outlet] = float(river_storage[outlet]) + outflow * lake_area
		level = lake_step(level, inflow, lake_area, lake_t)
		if is_region:
			region_lake_level[id] = level
		else:
			lake_level[id] = level
		Terrain.lake_levels[w.idx] = level
		WorldState.set_value("water.%s.level" % id, level)
	levels_changed.emit()


## The region-river reservoir evolution: routed through the Contour §6 `Hydrology`
## system when engaged (flag ON), else the byte-identical GDScript twin. Both
## sample the SAME engine-bound per-river environment (rain shadow at each
## midpoint, the catchment aggregate, the baseflow floor) and drive the SAME
## region_river_step body — the routed path just runs it native. Derived writes
## (river_levels, WorldState mirrors) stay host-side in both, exactly as before.
func _route_region_rivers(runoff: float) -> void:
	var bridge := _route_contour()
	if bridge != null:
		# Flag ON: seed the per-river environment as parallel arrays and let the
		# §6 `Hydrology` system map region_river_step over them (native), then read
		# hydrology.storage back into region_storage and recompute the mirrors.
		_contour_calls += 1
		var rivers_ordered: Array[Dictionary] = []
		var storage_in: Array = []
		var area_in: Array = []
		var rain_in: Array = []
		var baseflow_in: Array = []
		for r in Terrain.rivers:
			if not r.get("no_sim", false):
				continue
			var nodes: Array = r.nodes
			var mid: Vector2 = nodes[nodes.size() >> 1].pos
			rivers_ordered.append(r)
			storage_in.append(float(region_storage[r.id]))
			area_in.append(maxf(float(r.get("catchment", 0.0)), REGION_CATCHMENT_FALLBACK))
			rain_in.append(STORM_RAIN_M * Weather.rain_at(mid.x, mid.y))
			baseflow_in.append(_region_baseflow(r))
		if not bridge.tick_seeded({
				"hydrology.storage": storage_in, "hydrology.area": area_in,
				"hydrology.rain": rain_in, "hydrology.baseflow": baseflow_in,
				"hydrology.runoff": runoff}, 3600.0):
			push_error("[hydrology] STRATA_CONTOUR=1 but the Hydrology system tick was "
				+ "refused — refusing to silently run the GDScript twin")
			return
		var out: Variant = WorldState.get_value("hydrology.storage", null)
		if not (out is Array and (out as Array).size() == rivers_ordered.size()):
			push_error("[hydrology] STRATA_CONTOUR=1 but the Hydrology system returned no "
				+ "storage array — refusing to silently run the GDScript twin")
			return
		for i in rivers_ordered.size():
			var r: Dictionary = rivers_ordered[i]
			var id: String = r.id
			region_storage[id] = float(out[i])
			Terrain.river_levels[r.idx] = snappedf(clampf(lerpf(RIVER_LEVEL_MIN,
					RIVER_LEVEL_MAX, flow_norm(id)), RIVER_LEVEL_MIN, RIVER_LEVEL_MAX), 0.001)
			WorldState.set_value("water.%s.storage" % id, region_storage[id])
			WorldState.set_value("water.%s.flow" % id, snappedf(flow_norm(id), 0.001))
	else:
		# Flag OFF (default): the GDScript twin, forever byte-identical — each river
		# soaks its catchment and drains through the shared region_river_step body.
		for r in Terrain.rivers:
			if not r.get("no_sim", false):
				continue
			var id: String = r.id
			var nodes: Array = r.nodes
			var mid: Vector2 = nodes[nodes.size() >> 1].pos
			var local_rain := STORM_RAIN_M * Weather.rain_at(mid.x, mid.y)
			var area: float = maxf(float(r.get("catchment", 0.0)),
				REGION_CATCHMENT_FALLBACK)
			region_storage[id] = region_river_step(region_storage[id], area,
				local_rain, runoff, _region_baseflow(r))
			Terrain.river_levels[r.idx] = snappedf(clampf(lerpf(RIVER_LEVEL_MIN,
					RIVER_LEVEL_MAX, flow_norm(id)), RIVER_LEVEL_MIN, RIVER_LEVEL_MAX), 0.001)
			WorldState.set_value("water.%s.storage" % id, region_storage[id])
			WorldState.set_value("water.%s.flow" % id, snappedf(flow_norm(id), 0.001))


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
		push_error("[hydrology] STRATA_CONTOUR=1 but the Contour kernel is unavailable "
			+ "(not macOS / dylib absent) — refusing to silently run the GDScript twin")
		_contour_mode = -1
		return
	var bridge := ContourBridge.new(WorldState)
	var err := bridge.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[hydrology] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour_bridge = bridge
	_contour_mode = 2


## Routing introspection for the scene test / soak (proves the system ran, not a
## silent fallback): the resolved mode, whether it engaged, and the tick count.
func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}


## Does this river's mouth (last node) sit on this lake?
func _river_feeds_lake(r: Dictionary, w: Dictionary) -> bool:
	var nodes: Array = r.nodes
	var mouth: Vector2 = nodes[nodes.size() - 1].pos
	var c: Vector2 = w.center
	return mouth.distance_to(c) < float(w.radius) + float(nodes[nodes.size() - 1].half) + 4.0


func _push_levels() -> void:
	for r in Terrain.sim_rivers():
		Terrain.river_levels[r.idx] = snappedf(clampf(lerpf(RIVER_LEVEL_MIN,
				RIVER_LEVEL_MAX, flow_norm(r.id)), RIVER_LEVEL_MIN, RIVER_LEVEL_MAX), 0.001)
	for w in Terrain.water_bodies:
		Terrain.lake_levels[w.idx] = float(region_lake_level.get(w.id,
				lake_level.get(w.id, 0.0)))
	levels_changed.emit()


## Flow-route the whole watershed once. Two passes, the real-hydrology
## way: (1) priority-flood pit filling — closed hollows (noise dimples,
## sculpted bowls) are raised to their spill height with a tiny monotone
## gradient, so every cell has a strictly downhill path to a drain (a
## water body or the domain edge); (2) D8 steepest descent on the filled
## surface, accumulating each basin's catchment area. Pure function of
## Terrain + records: deterministic, rebuilt lazily each boot, never
## saved. ~65k height samples + a heap flood, paid once.
func _build_catchments() -> void:
	var t0 := Time.get_ticks_msec()
	var n := GRID_N
	var half := domain * 0.5
	# Bulk sampling through the native kernel when present (worker
	# thread; see Terrain.kernel). Same sample points as the loop this
	# replaces — the soak fingerprint hangs off these heights.
	var heights := Terrain.height_block(
		center.x - half, center.y - half, grid_m, n, n)
	var basins: Array[String] = []
	for w in Terrain.water_bodies:
		basins.append(w.id)
	for r in Terrain.sim_rivers():
		basins.append(r.id)
	# Which water body sits under each cell (-1 for dry ground), once.
	var wb := PackedInt32Array()
	wb.resize(n * n)
	for i in n * n:
		wb[i] = _basin_at(i, n, half)
	# Pass 1: priority flood from the drains outward-uphill.
	var filled := _priority_flood(heights, wb, n)
	# Pass 2: D8 on the filled surface, path-compressed.
	# basin per cell: -3 unresolved, -4 on current path, -2 exits, >=0 basin.
	var basin := PackedInt32Array()
	basin.resize(n * n)
	basin.fill(-3)
	var counts := PackedInt32Array()
	counts.resize(basins.size())
	var path := PackedInt32Array()
	for start in n * n:
		if basin[start] != -3:
			continue
		path.clear()
		var i := start
		var terminal := -2
		while true:
			if basin[i] >= -2:
				terminal = basin[i]
				break
			path.append(i)
			basin[i] = -4
			if wb[i] >= 0:
				terminal = wb[i]
				break
			var down := _lowest_neighbor(i, n, filled)
			if down < 0 or basin[down] == -4:
				terminal = -2  # domain edge (or a residual flat loop)
				break
			i = down
		for p in path:
			basin[p] = terminal
			if terminal >= 0:
				counts[terminal] += 1
	for b in basins.size():
		catchment_area[basins[b]] = counts[b] * grid_m * grid_m
	basin_grid = basin
	basin_names = basins
	_catchments_built = true
	print("[hydrology] catchments in %dms: %s" % [
		Time.get_ticks_msec() - t0, catchment_area])


## Where does rain landing at (x,z) end up? A basin id, "exits", or
## "outside" the routed domain.
func basin_at_world(x: float, z: float) -> String:
	_ensure_catchments()
	var half := domain * 0.5
	var ix := int((x - center.x + half) / grid_m)
	var iz := int((z - center.y + half) / grid_m)
	if ix < 0 or iz < 0 or ix >= GRID_N or iz >= GRID_N:
		return "outside"
	var b := basin_grid[iz * GRID_N + ix]
	return basin_names[b] if b >= 0 else "exits"


# Priority-flood depression filling (Barnes et al.): pop the lowest
# frontier cell, raise each unvisited neighbor to at least that height
# plus a hair, push it. Seeded at the drains (water cells at their own
# height, domain-edge cells), so the filled surface drains monotonically.
const FLOOD_EPS := 0.001

var _heap_h := PackedFloat32Array()
var _heap_i := PackedInt32Array()


func _priority_flood(heights: PackedFloat32Array, wb: PackedInt32Array,
		n: int) -> PackedFloat32Array:
	var filled := heights.duplicate()
	var visited := PackedByteArray()
	visited.resize(n * n)
	_heap_h.clear()
	_heap_i.clear()
	for i in n * n:
		@warning_ignore("integer_division")
		var iz := i / n
		var ix := i % n
		if wb[i] >= 0 or ix == 0 or iz == 0 or ix == n - 1 or iz == n - 1:
			visited[i] = 1
			_heap_push(filled[i], i)
	while _heap_h.size() > 0:
		var h := _heap_h[0]
		var i := _heap_pop()
		@warning_ignore("integer_division")
		var iz := i / n
		var ix := i % n
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var jx: int = ix + dx
				var jz: int = iz + dz
				if jx < 0 or jz < 0 or jx >= n or jz >= n:
					continue
				var j := jz * n + jx
				if visited[j] == 1:
					continue
				visited[j] = 1
				filled[j] = maxf(heights[j], h + FLOOD_EPS)
				_heap_push(filled[j], j)
	return filled


func _heap_push(h: float, i: int) -> void:
	_heap_h.append(h)
	_heap_i.append(i)
	var c := _heap_h.size() - 1
	while c > 0:
		@warning_ignore("integer_division")
		var p := (c - 1) / 2
		if _heap_h[p] <= _heap_h[c]:
			break
		var th := _heap_h[p]
		_heap_h[p] = _heap_h[c]
		_heap_h[c] = th
		var ti := _heap_i[p]
		_heap_i[p] = _heap_i[c]
		_heap_i[c] = ti
		c = p


func _heap_pop() -> int:
	var out := _heap_i[0]
	var last := _heap_h.size() - 1
	_heap_h[0] = _heap_h[last]
	_heap_i[0] = _heap_i[last]
	_heap_h.resize(last)
	_heap_i.resize(last)
	var p := 0
	while true:
		var l := p * 2 + 1
		if l >= last:
			break
		var small := l
		if l + 1 < last and _heap_h[l + 1] < _heap_h[l]:
			small = l + 1
		if _heap_h[p] <= _heap_h[small]:
			break
		var th := _heap_h[p]
		_heap_h[p] = _heap_h[small]
		_heap_h[small] = th
		var ti := _heap_i[p]
		_heap_i[p] = _heap_i[small]
		_heap_i[small] = ti
		p = small
	return out


## Which water body (if any) is under grid cell i — index into the
## lakes-then-rivers basin list, or -1.
func _basin_at(i: int, n: int, half: float) -> int:
	var x := center.x - half + (i % n) * grid_m
	@warning_ignore("integer_division")
	var z := center.y - half + (i / n) * grid_m
	var b := 0
	for w in Terrain.water_bodies:
		# Basin ownership follows the same water footprint the surface renders —
		# the TRUE outline when present, the equal-area disc otherwise (identical
		# to the old test for pre-outline lakes).
		if Terrain._in_lake(w, x, z):
			return b
		b += 1
	for r in Terrain.sim_rivers():
		var q := Terrain.river_query(r, x, z)
		if q.d < q.half:
			return b
		b += 1
	return -1


func _lowest_neighbor(i: int, n: int, heights: PackedFloat32Array) -> int:
	var ix := i % n
	@warning_ignore("integer_division")
	var iz := i / n
	var best := -1
	var best_h: float = heights[i]
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var jx: int = ix + dx
			var jz: int = iz + dz
			if jx < 0 or jz < 0 or jx >= n or jz >= n:
				continue
			var j := jz * n + jx
			if heights[j] < best_h:
				best_h = heights[j]
				best = j
	return best
