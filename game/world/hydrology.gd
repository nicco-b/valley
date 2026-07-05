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

# Boot-derived (deterministic function of terrain + records, not saved):
# basin id -> catchment area m^2. Built lazily on the first hour tick so
# a title-screen boot never pays for it.
var catchment_area: Dictionary = {}
# The routed basin per grid cell (index into lakes-then-rivers order, -2 =
# leaves the domain): kept for observability — god-mode overlays and
# probes read where any point's rain ends up via basin_at_world().
var basin_grid := PackedInt32Array()
var basin_names: Array[String] = []
var _catchments_built := false
var _catch_task := -1
var _last_snow := 0.0


func _ready() -> void:
	add_to_group("world_state_reader")  # SaveGame re-calls load_state post-restore
	_load_watershed()
	for r in Terrain.rivers:
		river_storage[r.id] = SPRING_M3H / RIVER_K  # boot at baseflow equilibrium
	for w in Terrain.water_bodies:
		lake_level[w.id] = 0.0
	load_state()
	# The routing pass costs ~1s of pure Terrain reads — start it on a
	# worker at boot so the first hour tick never hitches the frame.
	_catch_task = WorkerThreadPool.add_task(_build_catchments)
	GameClock.hour_tick.connect(_hourly)


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
	for id in lake_level:
		lake_level[id] = float(WorldState.get_value(
			"water.%s.level" % id, lake_level[id]))
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
	return float(river_storage.get(river_id, 0.0)) * RIVER_K


## Discharge normalized 0..1 against the authored-surface reference —
## shader flow speed, waterfall loudness, and story seeds read this.
func flow_norm(river_id: String) -> float:
	var q := discharge(river_id)
	return q / (q + Q_REF)


func _hourly(_h: int) -> void:
	_ensure_catchments()
	var rain := STORM_RAIN_M if Weather.state == "storm" else 0.0
	var runoff := lerpf(RUNOFF_DRY, RUNOFF_WET, Climate.wetness)
	# Snowmelt: Climate already decided how much cover melted this hour
	# (it runs first on hour_tick); the drop becomes meltwater depth.
	var melt_m := maxf(_last_snow - Climate.snow, 0.0) * SNOW_MELT_M
	_last_snow = Climate.snow
	var t := Climate.temperature(center.x, center.y)

	# Rivers: catchment runoff + springs in, reservoir recession out.
	for r in Terrain.rivers:
		var id: String = r.id
		var area: float = catchment_area.get(id, 0.0)
		var spring := SPRING_M3H * lerpf(0.3, 1.3, Climate.wetness)
		var storage: float = river_storage[id]
		storage += area * (rain * runoff + melt_m) + spring
		var q := storage * RIVER_K
		storage -= q
		river_storage[id] = snappedf(storage, 0.01)
		Terrain.river_levels[r.idx] = snappedf(clampf(lerpf(RIVER_LEVEL_MIN,
				RIVER_LEVEL_MAX, flow_norm(id)), RIVER_LEVEL_MIN, RIVER_LEVEL_MAX), 0.001)
		WorldState.set_value("water.%s.storage" % id, river_storage[id])
		WorldState.set_value("water.%s.flow" % id, snappedf(flow_norm(id), 0.001))

	# Lakes: river discharge + own catchment + direct rain in; evaporation
	# and level-driven outflow/seepage out. Level is depth offset from the
	# authored surface.
	for w in Terrain.water_bodies:
		var id: String = w.id
		var lake_area := PI * float(w.radius) * float(w.radius)
		var inflow := 0.0
		for r in Terrain.rivers:
			if _river_feeds_lake(r, w):
				inflow += discharge(r.id)
		inflow += catchment_area.get(id, 0.0) * (rain * runoff + melt_m)
		inflow += lake_area * rain  # rain falls on the water too
		var level: float = lake_level[id]
		var evap := EVAP_M_PER_DEG * maxf(t, 0.0)
		var outflow := LAKE_OUT_K * maxf(level - LAKE_LEVEL_MIN, 0.0)
		# The outflow goes where the record says: into a downstream
		# river's storage (chained water bodies), or "aquifer" — the
		# ground, until the underworld exists to receive it.
		var outlet: String = w.get("outlet", "aquifer")
		if river_storage.has(outlet):
			river_storage[outlet] = float(river_storage[outlet]) + outflow * lake_area
		level += inflow / lake_area - evap - outflow
		level = snappedf(clampf(level, LAKE_LEVEL_MIN, LAKE_LEVEL_MAX), 0.001)
		lake_level[id] = level
		Terrain.lake_levels[w.idx] = level
		WorldState.set_value("water.%s.level" % id, level)
	levels_changed.emit()


## Does this river's mouth (last node) sit on this lake?
func _river_feeds_lake(r: Dictionary, w: Dictionary) -> bool:
	var nodes: Array = r.nodes
	var mouth: Vector2 = nodes[nodes.size() - 1].pos
	var c: Vector2 = w.center
	return mouth.distance_to(c) < float(w.radius) + float(nodes[nodes.size() - 1].half) + 4.0


func _push_levels() -> void:
	for r in Terrain.rivers:
		Terrain.river_levels[r.idx] = snappedf(clampf(lerpf(RIVER_LEVEL_MIN,
				RIVER_LEVEL_MAX, flow_norm(r.id)), RIVER_LEVEL_MIN, RIVER_LEVEL_MAX), 0.001)
	for w in Terrain.water_bodies:
		Terrain.lake_levels[w.idx] = float(lake_level.get(w.id, 0.0))
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
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in n:
		for ix in n:
			heights[iz * n + ix] = Terrain.height(
				center.x - half + ix * grid_m,
				center.y - half + iz * grid_m)
	var basins: Array[String] = []
	for w in Terrain.water_bodies:
		basins.append(w.id)
	for r in Terrain.rivers:
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
		var c: Vector2 = w.center
		if Vector2(x - c.x, z - c.y).length() < float(w.radius):
			return b
		b += 1
	for r in Terrain.rivers:
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
