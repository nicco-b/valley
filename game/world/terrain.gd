extends Node
## Global terrain height function, autoloaded as Terrain. Deterministic
## (fixed seeds): every run and every cell samples the same world.
## Terrain meshes, collision, and content placement all read from here.
## Hand-authored terrain will later override/blend with this base.

# Flattened disks so authored content sits on level ground:
# [center x, center z, flat radius, feather distance]
# Cleared for the Strata world — the old hand-placed flat clearings (spawn pad,
# shrine, pond clearing) were tied to the retired valley geography and would sit
# below the Strata sea. Re-add per-world if a flat clearing is wanted.
const FLATTENS := []

# Water bodies come from data/water/: circular lakes as basin + surface
# height (top-level *.json), and rivers as node polylines (rivers/*.json).
# Everything water-shaped (swimming, navmesh carving, moisture floors,
# surface meshes) reads these records through here.
const WATER_DIR := "res://data/water"
const RIVER_DIR := "res://data/water/rivers"

# Region tiles (F3, 2026-07-05): PAINTED heightmaps as region records —
# kind "tile", a grayscale/EXR image mapped over a world rect:
#   {id, layer, kind:"tile", origin:{x,z}, size, feather,
#    heightmap:"res://data/terrain/tiles/*.exr", height_min, height_max}
# value = height_min + pixel * (height_max - height_min); the tile
# REPLACES the procedural ground inside its rect (feathered at the
# edge, home-guard gated), then rivers/lakes/sculpt still apply on
# top. This is the pipeline the real 12km map will be painted
# through; the procedural archipelago underneath is the disposable
# draft. Tiles hot-reload in dev (HotReload watches the images).
#
# Region landforms (the Loom, feel-prototype draft v2 2026-07-04): a
# LITERAL archipelago — beyond the home valley the ground drops to a
# seabed under a world sea (data/water/sea.json), and authored islands
# (mesa/ridge/dome records in data/regions/*.json) rise out of it,
# linked by low causeway ridges until boats exist. The sea is the
# world's bound: the procedural ranges fade out with the guard, so the
# horizon is water, not endless mountains. First step toward the F3
# region-record schema: every record carries a `layer` field ("surface"
# today; the underworld will be a second layer). All region and sea
# contribution is gated OUTSIDE the home watershed rect (guard below),
# so the valley and its hydrology are untouched.
const REGION_DIR := "res://data/regions"
# The game's world frame: the edge length (meters, origin-centered) that
# the biome map, the streamer budgets, and every Strata export must agree
# on. The Strata importer (tools/strata/import_world.gd) refuses exports
# baked at any other frame; _load_tile refuses stale records that slipped
# past it — a mismatched tile is garbage ground, never a warning.
const WORLD_FRAME_M := 16384.0
# Regions only act OUTSIDE the home watershed rect (from the watershed
# record, data/water/watersheds/home.json), so every terrain sample the
# Hydrology grid and the soak fingerprint see stays bit-identical.
# Guard ramps 0→1 over this margin beyond the rect edge.
const HOME_GUARD_IN := 150.0
const HOME_GUARD_OUT := 550.0
const WATERSHED_PATH := "res://data/water/watersheds/home.json"
var _home_rect := Rect2(-959, -1309, 2048, 2048)  # fallback; loaded in _ready

# Loaded region records, normalized. Read-only after _ready — worker
# threads sample height() concurrently (same rule as water_bodies).
# `regions`/`_barrens` keep the readable dicts for the Toolkit; the
# packed mirrors below are what the hot path reads — height() runs in
# every bulk sampler (sand patch re-anchor is 103k samples), so the
# per-sample loop must be packed reads + scalar math, no Dictionary
# access, no String match (the river-carve lesson, 2026-07-04).
var regions: Array[Dictionary] = []

const REG_MESA := 0
const REG_DOME := 1
const REG_RIDGE := 2
const REG_VOLCANO := 3  # cone + radial ridge/ravine drainage (Hawaii)
var _reg_kind := PackedInt32Array()
var _reg_bbox := PackedFloat32Array()  # x0,z0,x1,z1 per region (reach-grown)
var _reg_center := PackedVector2Array()
var _reg_radius := PackedFloat32Array()
var _reg_reach := PackedFloat32Array()
var _reg_inner := PackedFloat32Array()
var _reg_height := PackedFloat32Array()
var _reg_tiers := PackedFloat32Array()
var _reg_nodes: Array = []  # PackedVector2Array per region (ridges)
# Coastline noise (per landform): perturbs the radial distance so
# island edges become coves and headlands instead of circles.
var _reg_coast_amp := PackedFloat32Array()
var _reg_coast_freq := PackedFloat32Array()
# Volcano drainage: radial ridge count + ravine depth (0..1).
var _reg_ridges := PackedFloat32Array()
var _reg_ridge_depth := PackedFloat32Array()
# over_bays: landforms that rise OUT of a bay (bay islands) — added
# after the bay carve instead of being erased by it.
var _reg_over_bay := PackedInt32Array()
# Range spines: peak/saddle modulation along a ridge polyline — a
# mountain RANGE with summits instead of one uniform crest.
var _reg_peak_amp := PackedFloat32Array()
var _reg_peak_len := PackedFloat32Array()

# Bays: SUBTRACTIVE regions — the sea reaching into an island (the
# SF-bay interior). Applied after landforms, before painted tiles:
# inside the (coast-noised) footprint the ground pulls down to the
# bay floor. Guard-gated like everything else.
var _bays: Array[Dictionary] = []  # readable (Toolkit/map markers)
var _bay_center := PackedVector2Array()
var _bay_radius := PackedFloat32Array()
var _bay_feather := PackedFloat32Array()
var _bay_floor := PackedFloat32Array()
var _bay_amp := PackedFloat32Array()
var _bay_freq := PackedFloat32Array()

# Painted tiles, normalized: {id, path, x0, z0, size, feather, hmin,
# hmax, res, base: PackedFloat32Array, data: PackedFloat32Array}.
# `base` is the tile exactly as loaded from disk (the BLESSED heightfield
# — Strata bakes it, the game never rewrites it); `data` is what the hot
# path samples: base + the pen override layer, composited below. The two
# share one COW array until an override actually lands. Read-only after
# boot; a dev hot-reload swaps the ARRAY (and the kernel instance)
# wholesale — workers keep sampling the old one mid-build, never a torn mix.
var _tiles: Array[Dictionary] = []

# The pen override layer (P0 seam fix, ONE_APP.md 2026-07-07): the in-game
# TERRAIN pens no longer repaint + re-erode the world — the blessed tile is
# read-only. Pens paint an ADDITIVE meters layer (the sculpt-EXR pattern at
# macro scale, 16m/px over the world tile's frame) that is composited into
# each tile's `data` at load and on commit_tile_override(). Saved beside the
# sculpt layer; the blessed tile survives every pen stroke untouched.
const TILE_OVERRIDE_EXR := "res://data/terrain/tile_override.exr"
const TILE_OVERRIDE_META := "res://data/terrain/tile_override.json"
const TILE_OVERRIDE_RES := 1024
var _tile_override: Image = null
# The override's world frame (defaults to the first tile's rect when the
# first stroke lands; persisted in the sidecar meta so a re-imported world
# of a different size can't silently reframe old strokes).
var _ov_x0 := 0.0
var _ov_z0 := 0.0
var _ov_size := 0.0
# World rect known to hold nonzero override texels — the composite (boot
# and commit) only walks this, so an empty or small override costs nothing.
# Conservative: only ever grows within a session.
var _override_rect := Rect2()

# Loaded lake records, normalized: {id, idx, center: Vector2, radius,
# surface, basin_radius, basin_depth}. Strictly read-only after _ready —
# worker threads sample these concurrently, so NOTHING may write into
# these dictionaries post-boot (a torn Variant write corrupts them).
var water_bodies: Array[Dictionary] = []

# Loaded river records, normalized: {id, idx, depth, feather,
# flow: Vector2, nodes, seg_*/bbox/grid index}. Read-only after _ready,
# same rule as water_bodies. A river is a spline: the bed is carved below
# the authored surface in height(), the live surface (authored + level)
# returned by water_surface() within the ribbon.
var rivers: Array[Dictionary] = []

# Live level offsets, indexed by each record's idx. Hydrology writes these
# hourly from the main thread while workers read: element stores into a
# preallocated PackedFloat32Array are non-structural (no rehash, no COW
# churn), so the worst case is a stale read, never corruption.
var lake_levels := PackedFloat32Array()
var river_levels := PackedFloat32Array()

# The world sea (data/water/sea.json, {"sea": true, "surface": -2}):
# a single surface height filling everything below it OUTSIDE the home
# guard. Not a lake record — no basin carve, no hydrology reservoir
# (the Watershed's domain ends at the home rect); the seabed comes from
# the guard lerp in height().
var sea_level := -1e12
# Seabed depth under the world sea, outside the home guard. A landform
# parameter (FW4): sourced from data/world/landform.json; SEABED_DEFAULT
# is the framework's neutral fallback for a content-empty boot.
var _seabed := SEABED_DEFAULT

# The tide: a stateless function of the clock (sim-contract type (a),
# like the sun and moon) — semidiurnal lunar period, so high water
# returns ~50 minutes later each real day. Live consumers (swimming,
# the sea meshes, the strand shader) read sea_surface(); deterministic
# cell generation keeps the static sea_level through
# water_surface_base(), the same authored-base-vs-live-level split
# lakes use.
const TIDE_AMP := 0.45
const TIDE_PERIOD_H := 12.42


var _clock: Node = null  # GameClock, resolved at runtime: a direct
# identifier would break headless -s dev scripts (parity/map/bench
# load terrain.gd without autoloads and the script won't compile).


## Live sea surface height (authored level + tide), or -1e12 if no sea.
## Without a clock (dev scripts) the tide sits at mean water.
func sea_surface() -> float:
	if sea_level < -1e11:
		return -1e12
	if _clock == null:
		return sea_level
	return sea_level + TIDE_AMP * sin(TAU * _clock.hours / TIDE_PERIOD_H)

# The native kernel (native/, GDExtension): a bit-exact C++ port of
# height()/water_surface_base() plus block/mesh builders. Worker-thread
# builders MUST go through it when present — concurrent GDScript on
# pool threads corrupts the VM (the descent crash; STATUS "OPEN
# BLOCKER"). macOS-only library, loaded at runtime so other platforms
# fall back to the GDScript paths silently. Null when unavailable.
const KERNEL_EXT := "res://native/bin/valleykernel.gdext"
var kernel: RefCounted = null


## Live water surface height at a point (authored + hydrology level), or
## -INF when there's no water there. Physics, moisture, and rendering read
## this; deterministic cell generation reads water_surface_base().
func water_surface(x: float, z: float) -> float:
	for w in water_bodies:
		var c: Vector2 = w.center
		if Vector2(x - c.x, z - c.y).length() < float(w.radius):
			return float(w.surface) + lake_levels[w.idx]
	for r in rivers:
		var q := _river_probe(r, x, z)
		if q.x < q.y:
			return q.z + river_levels[r.idx]
	if sea_level > -1e11 and home_guard(x, z) > 0.0:
		return sea_surface()
	return -1e12


## Authored water surface, ignoring the live hydrology level — the stable
## reference cell generation (flora scatter, navmesh carve) builds against
## so streamed cells stay reproducible whatever the season's water is doing.
func water_surface_base(x: float, z: float) -> float:
	for w in water_bodies:
		var c: Vector2 = w.center
		if Vector2(x - c.x, z - c.y).length() < float(w.radius):
			return w.surface
	for r in rivers:
		var q := _river_probe(r, x, z)
		if q.x < q.y:
			return q.z
	if sea_level > -1e11 and home_guard(x, z) > 0.0:
		return sea_level
	return -1e12


# Beyond this distance from a river's edge no consumer cares (moisture
# reaches half+12, the carve half+feather): queries prune to O(1) via a
# bounding box + coarse segment grid, exact inside the margin. height()
# runs in every bulk sampler in the game (sand patch/base, cell builds,
# wet flags) from several worker threads at once, so the hot probe must
# never allocate: it returns a Vector3 (a value) and reads packed arrays.
const RIVER_MARGIN := 18.0
const RIVER_GRID_STEP := 32.0
const _RIVER_FAR := Vector3(1e12, 0.0, -1e12)


## Closest point on a river's centerline to (x,z) as (distance,
## half-width, surface), interpolated along the spline. Points farther
## than RIVER_MARGIN from the spline get the "far" answer.
func _river_probe(r: Dictionary, x: float, z: float) -> Vector3:
	var bbox: Rect2 = r.bbox
	if x < bbox.position.x or z < bbox.position.y \
			or x >= bbox.end.x or z >= bbox.end.y:
		return _RIVER_FAR
	var gx := int((x - bbox.position.x) / RIVER_GRID_STEP)
	var gz := int((z - bbox.position.y) / RIVER_GRID_STEP)
	var candidates: PackedInt32Array = r.grid[gz * int(r.grid_w) + gx]
	if candidates.is_empty():
		return _RIVER_FAR
	var p := Vector2(x, z)
	var seg_a: PackedVector2Array = r.seg_a
	var seg_ab: PackedVector2Array = r.seg_ab
	var seg_inv_l2: PackedFloat32Array = r.seg_inv_l2
	var seg_half: PackedFloat32Array = r.seg_half
	var seg_surf: PackedFloat32Array = r.seg_surf
	var best := _RIVER_FAR
	for i in candidates:
		var rel := p - seg_a[i]
		var t := clampf(rel.dot(seg_ab[i]) * seg_inv_l2[i], 0.0, 1.0)
		var d := rel.distance_to(seg_ab[i] * t)
		if d < best.x:
			best = Vector3(d,
				lerpf(seg_half[i], seg_half[i + 1], t),
				lerpf(seg_surf[i], seg_surf[i + 1], t))
	return best


## Rivers Hydrology should simulate (excludes generated/no_sim rivers,
## which are presentation-only until per-region watersheds exist).
func sim_rivers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rivers:
		if not r.get("no_sim", false):
			out.append(r)
	return out


## Downstream tangent of the nearest segment at (x,z) — bank-aware
## current direction on curved rivers (the whole-river flow vector
## shoves swimmers into the bank at bends). Cold path: full segment
## scan is fine; the allocation-free hot probe stays untouched.
func river_tangent(r: Dictionary, x: float, z: float) -> Vector2:
	var p := Vector2(x, z)
	var seg_a: PackedVector2Array = r.seg_a
	var seg_ab: PackedVector2Array = r.seg_ab
	var seg_tan: PackedVector2Array = r.seg_tan
	var best_d := 1e12
	var best := Vector2(r.flow)
	for i in seg_a.size():
		var rel := p - seg_a[i]
		var ab := seg_ab[i]
		var t := clampf(rel.dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		var d := rel.distance_to(ab * t)
		if d < best_d:
			best_d = d
			best = seg_tan[i]
	return best


## Dictionary view of _river_probe for cold callers (Climate moisture,
## Hydrology routing): {d, half, surface}.
func river_query(r: Dictionary, x: float, z: float) -> Dictionary:
	var q := _river_probe(r, x, z)
	return {"d": q.x, "half": q.y, "surface": q.z}

# The procedural draft (FW4): the noise-driven base world height() builds
# under the blessed tile — a home valley cut into rolling ground, ridged
# ranges beyond it, an archipelago sinking to the seabed outside the home
# guard. It is a DRAFT: where a Strata tile is present it is entirely
# replaced (the tile is the real ground). Its per-game PARAMETERS —
# the home valley's centerline + shape, the wall height, the seabed, and
# the five noise fields' seeds/frequencies — live in
# data/world/landform.json; valley ships its archipelago as that record.
# The framework file keeps only the interpreter and NEUTRAL defaults
# (no home valley, flat walls, generic noise), so a content-empty game
# boots on plain deterministic ground with no crash. This is the same
# parameter boundary the native kernel already draws (set_base/set_home
# take exactly these values); the draft's fixed amplitude profile
# (floor/wall/range/seabed multipliers) stays baked in both the GDScript
# reference and the C++ kernel as the interpreter's shape.
const LANDFORM_PATH := "res://data/world/landform.json"
const VALLEY_INNER_DEFAULT := 120.0
const VALLEY_OUTER_DEFAULT := 220.0
const WALL_HEIGHT_DEFAULT := 0.0
const SEABED_DEFAULT := 0.0
# Per noise field: seed, frequency, fractal octaves, ridged (else FBM).
const NOISE_DEFAULT := {
	"hills": {"seed": 0, "frequency": 0.0025, "octaves": 4, "ridged": false},
	"dunes": {"seed": 0, "frequency": 0.03, "octaves": 5, "ridged": false},
	"ranges": {"seed": 0, "frequency": 0.0007, "octaves": 3, "ridged": true},
	"island": {"seed": 0, "frequency": 0.0015, "octaves": 2, "ridged": false},
	"coast": {"seed": 0, "frequency": 0.001, "octaves": 5, "ridged": false},
}

# The amplitude PROFILE: the draft's fixed SHAPE constants, lifted out of
# height()/_region_height() into data so 800m alps or 5m dunes need no
# recompile (FW4). Sourced from landform.json's optional "profile" block;
# the DEFAULTS below are EXACTLY the historical hardcoded values, so an
# absent block (or a content-empty game) reproduces today's world
# bit-for-bit. The native kernel mirrors this schema key-for-key in
# set_profile — the two interpreters must read every field identically.
#   floor: base rolling ground (hills+dunes multipliers)
#   wall:  the valley wall's hill-noise gain (added to wall_height)
#   range: mountain amplitude + the [in,out] distance envelope (m)
#   seabed: the archipelago floor's hill+dune texture
#   mesa_blend: how far mesa terraces lerp toward stepped (0..1)
#   volcano_power: the volcanic flank's concavity exponent
const PROFILE_DEFAULT := {
	"floor": {"hills": 3.0, "dunes": 0.6},
	"wall": {"hills": 22.0},
	"range": {"amp": 320.0, "envelope": [1200.0, 2400.0]},
	"seabed": {"hills": 4.0, "dunes": 1.5},
	"mesa_blend": 0.7,
	"volcano_power": 1.55,
}
var _prof_floor_hills := 3.0
var _prof_floor_dunes := 0.6
var _prof_wall_hills := 22.0
var _prof_range_amp := 320.0
var _prof_range_in := 1200.0
var _prof_range_out := 2400.0
var _prof_seabed_hills := 4.0
var _prof_seabed_dunes := 1.5
var _prof_mesa_blend := 0.7
var _prof_volcano_power := 1.55
# The raw profile block as loaded (empty = all defaults); pushed to the
# kernel in _init_kernel.
var _profile_cfg: Dictionary = {}

# The home valley centerline (empty = no authored valley) and its cut
# shape, loaded from LANDFORM_PATH. Read-only after _ready (workers sample
# valley_factor via height()).
var _valley_path := PackedVector2Array()
var _valley_inner := VALLEY_INNER_DEFAULT
var _valley_outer := VALLEY_OUTER_DEFAULT
var _wall_height := WALL_HEIGHT_DEFAULT
var _noise_cfg: Dictionary = NOISE_DEFAULT

# Authored edit layer: a float heightmap sculpted in the Toolkit (and later
# paintable externally), added on top of the base noise. World-anchored,
# EDIT_M_PER_PX meters per pixel, centered on the origin.
const EDIT_SIZE := 2048  # pixels per side
const EDIT_M_PER_PX := 2.0
const EDIT_PATH := "res://data/terrain/edit_layer.exr"

signal edited(world_rect: Rect2)
signal river_added(river: Dictionary)  # a runtime pen river (water_bodies/Hydrology attach)

# The biome substrate (Stage B, 2026-07-05): a painted indexed map over
# the whole world (data/world/biome_map.png, matched to the palette in
# biomes.json). Pure PRESENTATION + flora density — never touches
# height(), so the soak is untouched. Consumers read biome_at(x,z) /
# biome_density(x,z); the terrain shader samples the index + palette
# textures directly (global params). Hot-reloads.
const BIOME_MAP_PATH := "res://data/world/biome_map.png"
const BIOME_PALETTE_PATH := "res://data/world/biomes.json"
var biomes: Array[Dictionary] = []  # palette (index order; carries ink+ground)
var _biome_img: Image  # R8 index map for CPU reads (biome_at)
var _biome_idx_tex: ImageTexture  # the GPU index texture (live paint updates it)
var _biome_origin := Vector2.ZERO
var _biome_size := 0.0
var _biome_res := 0

var _edits: Image
var _hills := FastNoiseLite.new()
var _dunes := FastNoiseLite.new()
var _ranges := FastNoiseLite.new()


var _island := FastNoiseLite.new()
var _coast := FastNoiseLite.new()  # multi-octave: ragged coastlines


func _ready() -> void:
	_clock = get_node_or_null("/root/GameClock")
	_load_landform()
	_load_water()
	_load_regions()
	_load_biomes()
	# The watershed record is content — a fresh game has none and keeps
	# the fixture rect (FW1 content-empty law; valley ships home.json).
	var ws: Variant = null
	if FileAccess.file_exists(WATERSHED_PATH):
		ws = JSON.parse_string(FileAccess.get_file_as_string(WATERSHED_PATH))
	if ws is Dictionary and ws.has("center") and ws.has("size"):
		var c: Dictionary = ws["center"]
		var s := float(ws["size"])
		_home_rect = Rect2(float(c["x"]) - s * 0.5, float(c["z"]) - s * 0.5, s, s)
	# The strand shader gates itself outside the home island with the
	# same rect the guard uses.
	RenderingServer.global_shader_parameter_set("home_rect", Vector4(
		_home_rect.position.x, _home_rect.position.y,
		_home_rect.end.x, _home_rect.end.y))
	_configure_noise()
	if FileAccess.file_exists(EDIT_PATH):
		_edits = Image.load_from_file(ProjectSettings.globalize_path(EDIT_PATH))
		_edits.convert(Image.FORMAT_RF)
	else:
		_edits = Image.create(EDIT_SIZE, EDIT_SIZE, false, Image.FORMAT_RF)
	_init_kernel()


# The procedural draft's parameters from data/world/landform.json, if a
# game ships one — else the neutral defaults above stand (content-empty
# boot law, FW1). Each field is independently overridable; a missing or
# malformed field just leaves its default. Parsed directly (not via
# Records) because Terrain autoloads before Records — the _load_water
# idiom.
func _load_landform() -> void:
	if not FileAccess.file_exists(LANDFORM_PATH):
		return
	var cfg: Variant = JSON.parse_string(FileAccess.get_file_as_string(LANDFORM_PATH))
	if not (cfg is Dictionary):
		push_error("[terrain] bad landform record (not a dict): " + LANDFORM_PATH)
		return
	var v: Variant = cfg.get("valley")
	if v is Dictionary:
		if v.get("path") is Array:
			var pts := PackedVector2Array()
			for n in v["path"]:
				if n is Array and (n as Array).size() == 2:
					pts.append(Vector2(float(n[0]), float(n[1])))
			_valley_path = pts
		if typeof(v.get("inner")) in [TYPE_INT, TYPE_FLOAT]:
			_valley_inner = float(v["inner"])
		if typeof(v.get("outer")) in [TYPE_INT, TYPE_FLOAT]:
			_valley_outer = float(v["outer"])
		if typeof(v.get("wall_height")) in [TYPE_INT, TYPE_FLOAT]:
			_wall_height = float(v["wall_height"])
	if typeof(cfg.get("seabed")) in [TYPE_INT, TYPE_FLOAT]:
		_seabed = float(cfg["seabed"])
	if cfg.get("noise") is Dictionary:
		_noise_cfg = cfg["noise"]
	# The amplitude profile block: absent leaves every default (today's
	# world). Applied to the GDScript fields now; pushed to the kernel in
	# _init_kernel once it exists (apply_profile no-ops the kernel push
	# while kernel is null).
	if cfg.get("profile") is Dictionary:
		_profile_cfg = cfg["profile"]
		apply_profile(_profile_cfg)


# Apply an amplitude-profile dict (landform.json's "profile" schema) to
# the GDScript reference fields AND, if it exists, the live native kernel,
# so the two interpreters stay in lockstep. Every key is optional; an
# absent key leaves the current value untouched. Used by _load_landform at
# boot and by the parity gate to drive a NON-DEFAULT profile through both
# paths (the defaults match trivially, so only a distinct profile proves
# the two readers agree).
func apply_profile(prof: Dictionary) -> void:
	var floor_d: Variant = prof.get("floor")
	if floor_d is Dictionary:
		_prof_floor_hills = _profile_num(floor_d, "hills", _prof_floor_hills)
		_prof_floor_dunes = _profile_num(floor_d, "dunes", _prof_floor_dunes)
	var wall_d: Variant = prof.get("wall")
	if wall_d is Dictionary:
		_prof_wall_hills = _profile_num(wall_d, "hills", _prof_wall_hills)
	var range_d: Variant = prof.get("range")
	if range_d is Dictionary:
		_prof_range_amp = _profile_num(range_d, "amp", _prof_range_amp)
		var env: Variant = range_d.get("envelope")
		if env is Array and (env as Array).size() == 2:
			_prof_range_in = float(env[0])
			_prof_range_out = float(env[1])
	var seabed_d: Variant = prof.get("seabed")
	if seabed_d is Dictionary:
		_prof_seabed_hills = _profile_num(seabed_d, "hills", _prof_seabed_hills)
		_prof_seabed_dunes = _profile_num(seabed_d, "dunes", _prof_seabed_dunes)
	_prof_mesa_blend = _profile_num(prof, "mesa_blend", _prof_mesa_blend)
	_prof_volcano_power = _profile_num(prof, "volcano_power", _prof_volcano_power)
	if kernel:
		kernel.set_profile(prof)


func _profile_num(d: Dictionary, key: String, fallback: float) -> float:
	return float(d[key]) if typeof(d.get(key)) in [TYPE_INT, TYPE_FLOAT] else fallback


# Apply the loaded noise config to the five FastNoiseLite fields. Setting
# each property to its record value (octaves 5 / FBM being the engine
# default) is a no-op where the record matches the default, so valley's
# record reproduces the old hardcoded seeds bit-for-bit.
func _configure_noise() -> void:
	_apply_noise(_hills, _noise_cfg.get("hills", {}))
	_apply_noise(_dunes, _noise_cfg.get("dunes", {}))
	_apply_noise(_ranges, _noise_cfg.get("ranges", {}))
	_apply_noise(_island, _noise_cfg.get("island", {}))
	_apply_noise(_coast, _noise_cfg.get("coast", {}))


func _apply_noise(n: FastNoiseLite, cfg: Dictionary) -> void:
	n.seed = int(cfg.get("seed", 0))
	n.frequency = float(cfg.get("frequency", 0.01))
	n.fractal_octaves = int(cfg.get("octaves", 3))
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if bool(cfg.get("ridged", false)) \
		else FastNoiseLite.FRACTAL_FBM


# Load and configure the native kernel (no-op off macOS or without the
# built library — every caller has a GDScript fallback). The kernel
# holds REFERENCES to the same noise objects and edit Image, so Toolkit
# sculpting is seen live; all other data is copied once and immutable.
func _init_kernel() -> void:
	# class_exists, not can_instantiate: the latter ERRORS on unknown
	# classes, which fails the smoke test's clean-output gate.
	if not ClassDB.class_exists("TerrainKernel"):
		if OS.get_name() != "macOS" or not FileAccess.file_exists(KERNEL_EXT):
			return
		var status := GDExtensionManager.load_extension(KERNEL_EXT)
		if status != GDExtensionManager.LOAD_STATUS_OK \
				or not ClassDB.class_exists("TerrainKernel"):
			push_warning("[terrain] native kernel failed to load (%d); GDScript fallback" % status)
			return
	kernel = ClassDB.instantiate("TerrainKernel")
	var flat := PackedFloat64Array()
	for f in FLATTENS:
		flat.append(f[0])
		flat.append(f[1])
		flat.append(f[2])
		flat.append(f[3])
	kernel.set_coast(_coast)
	kernel.set_base(_hills, _dunes, _ranges, _island, _edits,
		float(EDIT_SIZE), EDIT_M_PER_PX, flat,
		_valley_path,
		_valley_inner, _valley_outer, _wall_height)
	kernel.set_home(_home_rect.position, _home_rect.end,
		HOME_GUARD_IN, HOME_GUARD_OUT, sea_level, _seabed)
	# The amplitude profile: empty dict = every kernel default (today's
	# world); a shipped block overrides per key. Kernel defaults already
	# equal these, so this is a no-op for a game with no profile record.
	kernel.set_profile(_profile_cfg)
	var lc := PackedVector2Array()
	# Float64: lake records are read as doubles in GDScript; a float32
	# hop here moved the pond by 5e-8 m and broke bit-parity.
	var lr := PackedFloat64Array()
	var ls := PackedFloat64Array()
	var lbr := PackedFloat64Array()
	var lbd := PackedFloat64Array()
	for w in water_bodies:
		lc.append(w.center)
		lr.append(w.radius)
		ls.append(w.surface)
		lbr.append(w.basin_radius)
		lbd.append(w.basin_depth)
	kernel.set_lakes(lc, lr, ls, lbr, lbd)
	for r in rivers:
		kernel.add_river({"seg_a": r.seg_a, "seg_ab": r.seg_ab,
			"seg_inv_l2": r.seg_inv_l2, "seg_half": r.seg_half,
			"seg_surf": r.seg_surf, "bbox": r.bbox, "grid": r.grid,
			"grid_w": r.grid_w, "depth": r.depth, "feather": r.feather})
	kernel.set_regions(_reg_kind, _reg_bbox, _reg_center, _reg_radius,
		_reg_reach, _reg_inner, _reg_height, _reg_tiers, _reg_nodes,
		_reg_coast_amp, _reg_coast_freq, _reg_ridges, _reg_ridge_depth,
		_reg_over_bay, _reg_peak_amp, _reg_peak_len)
	kernel.set_bays(_bay_center, _bay_radius, _bay_feather, _bay_floor,
		_bay_amp, _bay_freq)
	kernel.set_tiles(_tiles)
	print("[terrain] native kernel live: worker sampling runs in C++")


## The P8 viewer (StrataLink preview_world): wear a tile record IN MEMORY
## ONLY — replaces the whole tile set (and the sea level) with the given
## record, swaps a fresh kernel, invalidates the world. Nothing touches
## disk: the checkout's tile cache and sea.json stay pristine; a restart
## (or a real import + reload_tile) reverts. The pen override layer rides
## along (composited over the preview like any blessed tile). Returns
## false when the heightmap can't load.
func preview_tile(rec: Dictionary, p_sea_level: float) -> bool:
	var tile := _load_tile(rec, "preview")
	if tile.is_empty():
		return false
	var composited := _composited_tile(tile, _override_rect)
	if not composited.is_empty():
		tile = composited
	var swapped: Array[Dictionary] = [tile]
	_tiles = swapped
	sea_level = p_sea_level
	if kernel:
		# Re-tile the LIVE kernel — set_tiles swaps atomically inside, so
		# worker samplers mid-call keep the old set. (Re-instantiating the
		# kernel here was a torn-Ref crash under the auto-preview loop.)
		kernel.set_tiles(_tiles)
		kernel.set_home(_home_rect.position, _home_rect.end,
			HOME_GUARD_IN, HOME_GUARD_OUT, sea_level, _seabed)
	edited.emit(Rect2(tile.x0, tile.z0, tile.size, tile.size))
	print("[terrain] preview tile worn (in memory): %s" % rec["heightmap"])
	return true


## Dev hot-reload of one painted tile: reload the image, swap the tile
## array and a FRESH kernel wholesale (workers mid-build keep a ref to
## the old one — never a torn mix), then invalidate the tile's rect so
## cells and the far quadtree rebuild. Returns "reloaded" when the swap
## landed, "no-tile" when no loaded tile carries that path (nothing to
## reload), and "failed" when the tile matched but its image would not
## re-read (missing/unreadable/non-square — audit QW3: this used to
## report success). On failure the OLD tile stays live — a failed reload
## never tears down a working world.
func reload_tile(image_path: String) -> String:
	for i in _tiles.size():
		var t: Dictionary = _tiles[i]
		if t.path != image_path:
			continue
		var rec := {"id": t.id, "origin": {"x": t.x0, "z": t.z0},
			"size": t.size, "feather": t.feather, "heightmap": t.path,
			"height_min": t.hmin, "height_max": t.hmax}
		var fresh := _load_tile(rec, t.id)
		if fresh.is_empty():
			return "failed"
		# Re-seat the live override on the fresh blessed tile (unsaved pen
		# strokes survive a re-import landing underneath them).
		var composited := _composited_tile(fresh, _override_rect)
		if not composited.is_empty():
			fresh = composited
		var swapped := _tiles.duplicate()
		swapped[i] = fresh
		_tiles = swapped
		if kernel:
			kernel.set_tiles(_tiles)  # atomic swap inside; workers unharmed
		edited.emit(Rect2(t.x0, t.z0, t.size, t.size))
		print("[terrain] tile reloaded: ", t.id)
		return "reloaded"
	return "no-tile"


## Bulk height samples, row-major nz rows of nx — THE call worker-thread
## builders must use (never per-sample GDScript height() off-main).
func height_block(ox: float, oz: float, step: float, nx: int, nz: int) -> PackedFloat32Array:
	if kernel:
		return kernel.height_block(ox, oz, step, nx, nz)
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			out[iz * nx + ix] = height(ox + ix * step, oz + iz * step)
	return out


## Bulk authored water surfaces (or -1e12 where dry), same layout.
func water_base_block(ox: float, oz: float, step: float, nx: int, nz: int) -> PackedFloat32Array:
	if kernel:
		return kernel.water_base_block(ox, oz, step, nx, nz)
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			out[iz * nx + ix] = water_surface_base(ox + ix * step, oz + iz * step)
	return out


## 0.0 anywhere in/near the home watershed rect, ramping to 1.0 over
## HOME_GUARD_IN..OUT meters past its edge — the seam where the home
## island ends and the sea/archipelago begins. Everything the Hydrology
## grid or the soak fingerprint can see has guard == 0.0 exactly.
func home_guard(x: float, z: float) -> float:
	var gdx := maxf(maxf(_home_rect.position.x - x, x - _home_rect.end.x), 0.0)
	var gdz := maxf(maxf(_home_rect.position.y - z, z - _home_rect.end.y), 0.0)
	# Coast noise breaks the rect silhouette into bays and headlands.
	# The ramp start stays >= 30m past the rect edge, so guard is still
	# exactly 0.0 on every sample the watershed can see.
	var wobble := _hills.get_noise_2d(x * 2.0, z * 2.0) * 120.0
	return smoothstep(HOME_GUARD_IN + wobble, HOME_GUARD_OUT + wobble,
		sqrt(gdx * gdx + gdz * gdz))


## 0.0 on the valley floor, 1.0 on the surrounding plateau.
func valley_factor(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := 1e12
	for i in _valley_path.size() - 1:
		d = minf(d, _segment_distance(p, _valley_path[i], _valley_path[i + 1]))
	return smoothstep(_valley_inner, _valley_outer, d)


func height(x: float, z: float) -> float:
	var floor_h := _hills.get_noise_2d(x, z) * _prof_floor_hills \
		+ _dunes.get_noise_2d(x, z) * _prof_floor_dunes
	var wall_h := _wall_height + _hills.get_noise_2d(x, z) * _prof_wall_hills
	var h := lerpf(floor_h, wall_h, valley_factor(x, z))
	# Mountain ranges: absent near home, real and walkable beyond ~1.2km.
	var range_envelope := smoothstep(_prof_range_in, _prof_range_out, Vector2(x, z).length())
	var range_term := maxf(_ranges.get_noise_2d(x, z), 0.0) * _prof_range_amp * range_envelope
	# The archipelago: outside the home guard the plateau sinks to the
	# seabed, the ranges fade with it (the sea bounds the world — no
	# endless mountains), and authored islands rise from records.
	var guard := home_guard(x, z)
	if guard > 0.0:
		var seabed := _seabed + _hills.get_noise_2d(x, z) * _prof_seabed_hills \
			+ _dunes.get_noise_2d(x, z) * _prof_seabed_dunes
		h = lerpf(h, seabed, guard)
		range_term *= 1.0 - guard
		h += _region_height(x, z) * guard
		if not _bay_center.is_empty():
			h = _bay_carve(x, z, h, guard)
			# Bay islands rise out of the carved water.
			h += _region_height(x, z, 1) * guard
	h += range_term
	# Painted tiles replace whatever the procedural stack made; the water
	# carves and the sculpt layer still apply below/after. Strata is the whole
	# world now — the tile overrides the home valley too, so the blend is no
	# longer gated by guard (home_guard still drives climate/hydrology).
	if not _tiles.is_empty():
		h = _tile_blend(x, z, h, 1.0)
	for f in FLATTENS:
		var d := Vector2(x - f[0], z - f[1]).length()
		h *= smoothstep(f[2], f[2] + f[3], d)
	for w in water_bodies:
		var c: Vector2 = w.center
		var d := Vector2(x - c.x, z - c.y).length()
		h -= float(w.basin_depth) * smoothstep(1.0, 0.0, d / float(w.basin_radius))
	# Rivers carve a banked channel: bed at the centerline, waterline at
	# the half-width edge, feathered back to natural ground beyond. Only
	# ever lower the terrain (min), so a river never builds a levee.
	for r in rivers:
		var q := _river_probe(r, x, z)
		var half := q.y
		var feather: float = r.feather
		if q.x > half + feather:
			continue
		var target: float
		if q.x <= half:
			target = lerpf(q.z - r.depth, q.z, q.x / maxf(half, 1e-4))
		else:
			target = lerpf(q.z, h, (q.x - half) / feather)
		h = minf(h, target)
	return h + edit_height(x, z)


# Records loads after Terrain in the autoload order, so water records are
# parsed here directly (same pattern as the edit-layer EXR). Lakes live at
# the top level of data/water/; rivers in the rivers/ subfolder.
func _load_water() -> void:
	var dir := DirAccess.open(WATER_DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()  # deterministic load order regardless of filesystem
	for f in files:
		if not f.ends_with(".json"):
			continue
		var path := WATER_DIR + "/" + f
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("sea", false):
			sea_level = float(parsed.get("surface", -2.0))
			continue
		if not (parsed is Dictionary and parsed.has("center")
				and parsed.has("radius") and parsed.has("surface")):
			push_error("[terrain] bad lake record (needs center/radius/surface): " + path)
			continue
		var rec: Dictionary = parsed
		var center: Dictionary = rec["center"]
		var basin: Dictionary = rec.get("basin", {})
		water_bodies.append({
			"id": rec.get("id", f.trim_suffix(".json")),
			"idx": water_bodies.size(),
			"center": Vector2(float(center["x"]), float(center["z"])),
			"radius": float(rec["radius"]),
			"surface": float(rec["surface"]),
			"basin_radius": float(basin.get("radius", rec["radius"])),
			"basin_depth": float(basin.get("depth", 0.0)),
			"outlet": rec.get("outlet", "aquifer"),
			# Strata-imported lakes (hyd_*): a regenerable cache, so their
			# levels live on Hydrology's REGION tier, off the soak digest.
			"no_sim": bool(rec.get("no_sim", false)),
			# Real max depth from the hydrology solve (W2 bathymetry rides
			# it); 0.0 for authored lakes, which carve their own basin.
			"depth": float(rec.get("depth", 0.0)),
		})
	lake_levels.resize(water_bodies.size())
	_load_rivers()


func _load_rivers() -> void:
	var dir := DirAccess.open(RIVER_DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var path := RIVER_DIR + "/" + f
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary and parsed.has("nodes")):
			push_error("[terrain] bad river record (needs nodes): " + path)
			continue
		var rec: Dictionary = parsed
		if (rec["nodes"] as Array).size() < 2:
			push_error("[terrain] river needs >=2 nodes: " + path)
			continue
		var river := _river_from_record(rec, f.trim_suffix(".json"))
		_index_river(river)
		rivers.append(river)
	river_levels.resize(rivers.size())


# Normalize a raw river record (nodes as x/z/width/surface dicts) into the
# live river dict. Shared by _load_rivers and the runtime pen (add_river).
func _river_from_record(rec: Dictionary, fallback_id: String) -> Dictionary:
	var raw_nodes: Array = rec["nodes"]
	var nodes: Array[Dictionary] = []
	for n in raw_nodes:
		nodes.append({
			"pos": Vector2(float(n["x"]), float(n["z"])),
			"half": float(n["width"]) * 0.5,
			"surface": float(n["surface"]),
		})
	# Downstream flow direction: first node to last, in the XZ plane.
	var flow: Vector2 = (nodes[nodes.size() - 1].pos - nodes[0].pos)
	flow = flow.normalized() if flow.length() > 1e-4 else Vector2.ZERO
	# Waterfalls (Strata hydrology knickpoints): lip position + total drop.
	# water_bodies foams the ribbon around each lip.
	var falls: Array[Dictionary] = []
	for w in rec.get("waterfalls", []) as Array:
		falls.append({"pos": Vector2(float(w["x"]), float(w["z"])),
			"drop": float(w.get("drop_m", 0.0))})
	return {
		"id": rec.get("id", fallback_id),
		"idx": rivers.size(),
		"depth": float(rec.get("depth", 1.2)),
		"feather": float(rec.get("feather", 4.0)),
		"flow": flow,
		"nodes": nodes,
		# Generated/penned rivers carve and render but are NOT routed on
		# the home watershed grid — Hydrology's REGION tier breathes them
		# instead, off the soak fingerprint (regenerable local cache).
		"no_sim": bool(rec.get("no_sim", false)),
		"catchment": float(rec.get("catchment_m2", 0.0)),
		"falls": falls,
	}


## Add a river from a record at RUNTIME (the map river pen): index it,
## refresh the kernel so worker sampling carves it, and invalidate the
## cells it spans (edited) so the basin re-forms within a rebuild — the
## far quadtree refreshes off the same signal. Returns the live river
## dict; the caller persists the JSON so it survives a restart.
func add_river(rec: Dictionary) -> Dictionary:
	var river := _river_from_record(rec, "river_%d" % rivers.size())
	_index_river(river)
	rivers.append(river)
	river_levels.resize(rivers.size())
	river_levels[river.idx] = 0.0
	if kernel:
		_init_kernel()  # fresh, fully-configured instance sees the new river
	river_added.emit(river)
	edited.emit(river.bbox)
	return river


# Precompute the pruning structures _river_probe() needs: a margin-grown
# bounding box, per-segment packed arrays (origin, direction, inverse
# length², node half-widths and surfaces), and a coarse grid where each
# cell lists the segments within RIVER_MARGIN of it (usually 1-3).
func _index_river(r: Dictionary) -> void:
	var nodes: Array = r.nodes
	var first: Vector2 = nodes[0].pos
	var bbox := Rect2(first, Vector2.ZERO)
	var seg_a := PackedVector2Array()
	var seg_ab := PackedVector2Array()
	var seg_inv_l2 := PackedFloat32Array()
	var seg_half := PackedFloat32Array()
	var seg_surf := PackedFloat32Array()
	for n in nodes:
		bbox = bbox.expand(n.pos)
		seg_half.append(n.half)
		seg_surf.append(n.surface)
	for i in nodes.size() - 1:
		var pa: Vector2 = nodes[i].pos
		var ab: Vector2 = nodes[i + 1].pos - pa
		seg_a.append(pa)
		seg_ab.append(ab)
		seg_inv_l2.append(1.0 / maxf(ab.length_squared(), 1e-4))
	var seg_tan := PackedVector2Array()
	for i in seg_ab.size():
		var ab: Vector2 = seg_ab[i]
		seg_tan.append(ab.normalized() if ab.length() > 1e-4 else Vector2.RIGHT)
	r.seg_tan = seg_tan
	r.seg_a = seg_a
	r.seg_ab = seg_ab
	r.seg_inv_l2 = seg_inv_l2
	r.seg_half = seg_half
	r.seg_surf = seg_surf
	bbox = bbox.grow(RIVER_MARGIN)
	var gw := int(ceil(bbox.size.x / RIVER_GRID_STEP))
	var gh := int(ceil(bbox.size.y / RIVER_GRID_STEP))
	var grid: Array = []
	grid.resize(gw * gh)
	for i in gw * gh:
		grid[i] = PackedInt32Array()
	for s in nodes.size() - 1:
		var a: Vector2 = nodes[s].pos
		var b: Vector2 = nodes[s + 1].pos
		var seg := Rect2(a, Vector2.ZERO).expand(b).grow(RIVER_MARGIN)
		var x0 := maxi(int((seg.position.x - bbox.position.x) / RIVER_GRID_STEP), 0)
		var z0 := maxi(int((seg.position.y - bbox.position.y) / RIVER_GRID_STEP), 0)
		var x1 := mini(int((seg.end.x - bbox.position.x) / RIVER_GRID_STEP), gw - 1)
		var z1 := mini(int((seg.end.y - bbox.position.y) / RIVER_GRID_STEP), gh - 1)
		for gz in range(z0, z1 + 1):
			for gx in range(x0, x1 + 1):
				var cell: PackedInt32Array = grid[gz * gw + gx]
				cell.append(s)
				grid[gz * gw + gx] = cell
	r.bbox = bbox
	r.grid = grid
	r.grid_w = gw


# Region records: authored archipelago landforms. Kinds:
#   mesa   — flat-topped tiered island (the hill-city shape): center,
#            radius (plateau edge), feather (skirt), height, tiers
#   ridge  — a crest polyline: nodes[{x,z}], inner, feather, height
#            (also the causeway shape: a low ridge between islands)
#   dome   — a plain rounded island: center, radius, feather, height
# Every record carries `layer` ("surface" for now — the underworld will
# add a second value; baking the field in from day one per IDEAS).
func _load_regions() -> void:
	var dir := DirAccess.open(REGION_DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()  # deterministic load order regardless of filesystem
	for f in files:
		if not f.ends_with(".json"):
			continue
		var path := REGION_DIR + "/" + f
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary and parsed.has("kind")):
			push_error("[terrain] bad region record (needs kind): " + path)
			continue
		var rec: Dictionary = parsed
		var kind: String = rec["kind"]
		if kind == "tile":
			var tile := _load_tile(rec, f.trim_suffix(".json"))
			if not tile.is_empty():
				_tiles.append(tile)
			continue
		var reg := {
			"id": rec.get("id", f.trim_suffix(".json")),
			"layer": rec.get("layer", "surface"),
			"kind": kind,
			"height": float(rec.get("height", 0.0)),
			"radius": float(rec.get("radius", 0.0)),
			"feather": float(rec.get("feather", 200.0)),
			"tiers": int(rec.get("tiers", 0)),
			"inner": float(rec.get("inner", 100.0)),
			"coast_amp": float(rec.get("coast_amp", 0.0)),
			"coast_freq": float(rec.get("coast_freq", 0.0035)),
			"ridges": int(rec.get("ridges", 9)),
			"ridge_depth": float(rec.get("ridge_depth", 0.35)),
			"over_bays": bool(rec.get("over_bays", false)),
			"peak_amp": float(rec.get("peak_amp", 0.0)),
			"peak_len": float(rec.get("peak_len", 1400.0)),
			"center": Vector2.ZERO,
			"nodes": PackedVector2Array(),
		}
		if rec.has("center"):
			var c: Dictionary = rec["center"]
			reg.center = Vector2(float(c["x"]), float(c["z"]))
		if rec.has("nodes"):
			var pts := PackedVector2Array()
			for n in rec["nodes"]:
				pts.append(Vector2(float(n["x"]), float(n["z"])))
			reg.nodes = pts
		if kind == "bay":
			_bays.append(reg)
			_bay_center.append(reg.center)
			_bay_radius.append(reg.radius)
			_bay_feather.append(reg.feather)
			_bay_floor.append(float(rec.get("floor", -8.0)))
			_bay_amp.append(reg.coast_amp)
			_bay_freq.append(reg.coast_freq)
			continue
		regions.append(reg)
		var is_ridge := kind == "ridge"
		# Coast noise pushes the envelope outward by up to its amplitude.
		var reach: float = (reg.inner if is_ridge else reg.radius) \
			+ reg.feather + reg.coast_amp
		var kind_id := REG_DOME
		if is_ridge:
			kind_id = REG_RIDGE
		elif kind == "volcano":
			kind_id = REG_VOLCANO
		elif kind == "mesa" and reg.tiers > 1:
			kind_id = REG_MESA
		_reg_kind.append(kind_id)
		_reg_center.append(reg.center)
		_reg_radius.append(reg.radius)
		_reg_reach.append(reach)
		_reg_inner.append(reg.inner)
		_reg_height.append(reg.height)
		_reg_tiers.append(float(reg.tiers))
		_reg_nodes.append(reg.nodes)
		_reg_coast_amp.append(reg.coast_amp)
		_reg_coast_freq.append(reg.coast_freq)
		_reg_ridges.append(float(reg.ridges))
		_reg_ridge_depth.append(reg.ridge_depth)
		_reg_over_bay.append(1 if reg.over_bays else 0)
		_reg_peak_amp.append(reg.peak_amp)
		_reg_peak_len.append(reg.peak_len)
		var bbox := Rect2(reg.center, Vector2.ZERO)
		for n: Vector2 in reg.nodes:
			bbox = bbox.expand(n)
		bbox = bbox.grow(reach)
		_reg_bbox.append(bbox.position.x)
		_reg_bbox.append(bbox.position.y)
		_reg_bbox.append(bbox.end.x)
		_reg_bbox.append(bbox.end.y)
	# Pen override layer: load once the tiles exist (its default frame is
	# the world tile's rect), then composite it into every tile's data.
	_load_tile_override()
	for i in _tiles.size():
		var composited := _composited_tile(_tiles[i], _override_rect)
		if not composited.is_empty():
			_tiles[i] = composited


# Load the biome palette + painted map. The colored paint image is
# matched per-pixel to the nearest palette `ink` and stored as an R8
# INDEX image (CPU reads + a global index texture for the shader); a
# 1D palette texture carries each biome's ground albedo to the GPU.
# Missing map = no biomes (shader falls back to its height bands).
func _load_biomes() -> void:
	biomes.clear()
	var pal: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(BIOME_PALETTE_PATH))
	if not (pal is Dictionary and pal.has("biomes")):
		return
	var inks := PackedColorArray()
	for b: Variant in pal["biomes"]:
		var g: Array = b["ground"]
		var ink: Array = b["ink"]
		biomes.append({"id": b.get("id", "biome"),
			"ground": Color(g[0], g[1], g[2]),
			"ink": Color(ink[0], ink[1], ink[2]),  # what save_biome_map writes
			"flora": float(b.get("flora", 0.5)),
			"repose": float(b.get("repose", 0.3)),
			"dust": float(b.get("dust", 0.3))})
		inks.append(Color(ink[0], ink[1], ink[2]))
	# The world rect the biome map covers (same framing as the guide).
	_biome_origin = Vector2(-WORLD_FRAME_M * 0.5, -WORLD_FRAME_M * 0.5)
	_biome_size = WORLD_FRAME_M
	# Palette texture: N×1, each texel a biome's ground albedo.
	var pal_img := Image.create(biomes.size(), 1, false, Image.FORMAT_RGB8)
	for i in biomes.size():
		pal_img.set_pixel(i, 0, biomes[i].ground)
	var pal_tex := ImageTexture.create_from_image(pal_img)
	RenderingServer.global_shader_parameter_set("biome_palette", pal_tex)
	RenderingServer.global_shader_parameter_set("biome_count", biomes.size())
	if not FileAccess.file_exists(BIOME_MAP_PATH):
		RenderingServer.global_shader_parameter_set("biome_present", false)
		return
	var painted := Image.load_from_file(ProjectSettings.globalize_path(BIOME_MAP_PATH))
	_biome_res = painted.get_width()
	# Match each painted pixel to the nearest palette ink → index image.
	_biome_img = Image.create(_biome_res, _biome_res, false, Image.FORMAT_R8)
	for z in _biome_res:
		for x in _biome_res:
			var c := painted.get_pixel(x, z)
			var best := 0
			var best_d := 1e9
			for i in inks.size():
				var d := Vector3(c.r - inks[i].r, c.g - inks[i].g,
					c.b - inks[i].b).length_squared()
				if d < best_d:
					best_d = d
					best = i
			# R8 stores index/255; the shader multiplies back by 255.
			_biome_img.set_pixel(x, z, Color8(best, 0, 0))
	_biome_idx_tex = ImageTexture.create_from_image(_biome_img)
	RenderingServer.global_shader_parameter_set("biome_index_map", _biome_idx_tex)
	RenderingServer.global_shader_parameter_set("biome_index_rect", Vector4(
		_biome_origin.x, _biome_origin.y, _biome_size, _biome_size))
	RenderingServer.global_shader_parameter_set("biome_present", true)


## Water-proximity 0..1 from Terrain data alone (no Climate/autoloads),
## for the biome derive and any cold caller: near lakes/rivers/sea → 1.
func moisture_static(x: float, z: float) -> float:
	var near := 0.0
	for w in water_bodies:
		var c: Vector2 = w.center
		near = maxf(near, 1.0 - smoothstep(w.radius, w.radius + 40.0,
			Vector2(x - c.x, z - c.y).length()))
	for r in rivers:
		var q := _river_probe(r, x, z)
		if q.x < q.y + 30.0:
			near = maxf(near, 1.0 - smoothstep(q.y, q.y + 30.0, q.x))
	if sea_level > -1e11 and home_guard(x, z) > 0.0:
		near = maxf(near, 1.0 - smoothstep(sea_level + 1.0, sea_level + 12.0,
			height(x, z)))
	return near


## Biome index at a world point (-1 if no biome map). CPU consumers
## (flora density, sand physicality) read this.
func biome_at(x: float, z: float) -> int:
	if _biome_img == null:
		return -1
	var u := (x - _biome_origin.x) / _biome_size
	var v := (z - _biome_origin.y) / _biome_size
	if u < 0.0 or v < 0.0 or u >= 1.0 or v >= 1.0:
		return -1
	return _biome_img.get_pixel(int(u * _biome_res), int(v * _biome_res)).r8


## Flora-density multiplier at a point (1.0 where no biome map).
func biome_density(x: float, z: float) -> float:
	var i := biome_at(x, z)
	return float(biomes[i].flora) if i >= 0 and i < biomes.size() else 1.0


## Dev hot-reload of the painted biome map (re-match + re-upload).
func reload_biomes() -> void:
	_load_biomes()
	edited.emit(Rect2(_biome_origin, Vector2(_biome_size, _biome_size)))


## Paint a biome index into the live index map within a world-space disc
## and re-upload the GPU texture — the ground TINT changes instantly (the
## shader samples the texture per-fragment). Flora only re-composes when
## the cells rebuild, so the map tool commits that separately. Returns the
## painted rect (world) so the caller can invalidate exactly what changed.
func paint_biome_index(x: float, z: float, radius_m: float, index: int) -> Rect2:
	if _biome_img == null or index < 0 or index >= biomes.size():
		return Rect2()
	var cx := (x - _biome_origin.x) / _biome_size * _biome_res
	var cz := (z - _biome_origin.y) / _biome_size * _biome_res
	var rad := maxf(radius_m / _biome_size * _biome_res, 0.5)
	var col := Color8(index, 0, 0)
	var center := Vector2(cx, cz)
	for pz in range(maxi(0, int(cz - rad)), mini(_biome_res, int(cz + rad) + 1)):
		for px in range(maxi(0, int(cx - rad)), mini(_biome_res, int(cx + rad) + 1)):
			if Vector2(px + 0.5, pz + 0.5).distance_to(center) <= rad:
				_biome_img.set_pixel(px, pz, col)
	_biome_idx_tex.update(_biome_img)  # cheap 1024^2 R8 re-upload
	return Rect2(x - radius_m, z - radius_m, radius_m * 2.0, radius_m * 2.0)


## Persist the live index map back to the painted colour PNG (index → the
## palette's ink), so a painted biome survives a restart.
func save_biome_map() -> void:
	if _biome_img == null:
		return
	var out := Image.create(_biome_res, _biome_res, false, Image.FORMAT_RGB8)
	for z in _biome_res:
		for x in _biome_res:
			var i: int = _biome_img.get_pixel(x, z).r8
			out.set_pixel(x, z, biomes[i].ink if i < biomes.size() else Color.BLACK)
	out.save_png(ProjectSettings.globalize_path(BIOME_MAP_PATH))


## Rescatter flora over a painted region without reloading from disk (the
## live index map is already current — reload_biomes would re-read the PNG).
func commit_biome_paint(rect: Rect2) -> void:
	edited.emit(rect)


## Biome pen undo support: one-deep snapshot of the live index map (the
## sculpt layer's snapshot_edits pattern — the Toolkit's Z restores it).
func snapshot_biome_map() -> Image:
	return _biome_img.duplicate() if _biome_img != null else null


## Restore a pre-stroke index map: the tint reverts instantly (texture
## re-upload) and flora re-composes over `rect` — the region painted
## since the snapshot (zero rect skips the rescatter: nothing changed).
func restore_biome_map(snap: Image, rect: Rect2) -> void:
	if snap == null or _biome_img == null:
		return
	_biome_img = snap
	_biome_idx_tex.update(_biome_img)
	if rect.size != Vector2.ZERO:
		edited.emit(rect)


## Load one painted-tile record: image → float array, once at boot
## (and on dev hot-reload). Cold path; any failure skips the tile.
func _load_tile(rec: Dictionary, fallback_id: String) -> Dictionary:
	if not (rec.has("origin") and rec.has("size") and rec.has("heightmap")):
		push_error("[terrain] tile record needs origin/size/heightmap: " + fallback_id)
		return {}
	# A Strata-imported world tile must match the game's world frame — the
	# biome map and streamer budgets are framed to WORLD_FRAME_M, so a
	# mismatched export is garbage ground. The importer refuses these at
	# import time; this catches a stale or hand-edited record honestly
	# instead of loading it. (Painted region tiles without Strata
	# provenance keep their arbitrary frames — F3 is untouched.)
	if rec.has("strata") and absf(float(rec["size"]) - WORLD_FRAME_M) > 0.5:
		push_error("[terrain] world tile '%s' is %.0fm but the game's world frame is %.0fm — refusing (re-import an export baked at %.0fm)" % [
			rec.get("id", fallback_id), float(rec["size"]),
			WORLD_FRAME_M, WORLD_FRAME_M])
		return {}
	var path: String = rec["heightmap"]
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_error("[terrain] tile heightmap missing/unreadable: " + path)
		return {}
	img.convert(Image.FORMAT_RF)
	var res := img.get_width()
	if img.get_height() != res:
		push_error("[terrain] tile heightmap must be square: " + path)
		return {}
	var data := img.get_data().to_float32_array()
	var origin: Dictionary = rec["origin"]
	return {
		"id": rec.get("id", fallback_id),
		"path": path,
		"x0": float(origin["x"]),
		"z0": float(origin["z"]),
		"size": float(rec["size"]),
		"feather": float(rec.get("feather", 100.0)),
		"hmin": float(rec.get("height_min", 0.0)),
		"hmax": float(rec.get("height_max", 1.0)),
		"res": res,
		"base": data,  # the blessed heightfield, exactly as on disk
		"data": data,  # what samplers read (base + override once composited)
	}


## True when a painted world tile is loaded (the pens' precondition —
## the override layer rides the tile's frame).
func has_world_tile() -> bool:
	return not _tiles.is_empty()


## The world tile's edge length in meters (0 when no tile) — viewers
## frame the world with it.
func world_tile_size() -> float:
	return float(_tiles[0].size) if not _tiles.is_empty() else 0.0


# Load the pen override layer from disk (no-op when absent). The sidecar
# meta carries the frame it was painted in plus the dirty rect, so boot
# only composites where strokes actually exist.
func _load_tile_override() -> void:
	if _tiles.is_empty() or not FileAccess.file_exists(TILE_OVERRIDE_EXR):
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(TILE_OVERRIDE_EXR))
	if img == null or img.is_empty():
		push_error("[terrain] tile override unreadable: " + TILE_OVERRIDE_EXR)
		return
	img.convert(Image.FORMAT_RF)
	_tile_override = img
	var t := _tiles[0]
	_ov_x0 = t.x0
	_ov_z0 = t.z0
	_ov_size = t.size
	_override_rect = Rect2(_ov_x0, _ov_z0, _ov_size, _ov_size)
	var meta: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TILE_OVERRIDE_META))
	if meta is Dictionary:
		_ov_x0 = float(meta.get("x0", _ov_x0))
		_ov_z0 = float(meta.get("z0", _ov_z0))
		_ov_size = float(meta.get("size", _ov_size))
		var r: Variant = meta.get("rect", null)
		if r is Dictionary:
			_override_rect = Rect2(float(r["x"]), float(r["z"]),
				float(r["w"]), float(r["h"]))


# Create an empty override on the world tile's frame (first pen stroke).
func _ensure_override() -> void:
	if _tile_override != null or _tiles.is_empty():
		return
	var t := _tiles[0]
	_ov_x0 = t.x0
	_ov_z0 = t.z0
	_ov_size = t.size
	_override_rect = Rect2()
	_tile_override = Image.create(TILE_OVERRIDE_RES, TILE_OVERRIDE_RES,
		false, Image.FORMAT_RF)


# A fresh tile dict whose `data` is base + override, recomposited inside
# `world_rect` only (everything outside keeps its current values). Returns
# {} when there is nothing to do. Never mutates `t` — callers swap the
# result in wholesale so workers mid-build keep a coherent old tile.
func _composited_tile(t: Dictionary, world_rect: Rect2) -> Dictionary:
	if _tile_override == null or world_rect.size == Vector2.ZERO:
		return {}
	var tile_rect := Rect2(t.x0, t.z0, t.size, t.size)
	var rect := world_rect.intersection(tile_rect)
	if rect.size == Vector2.ZERO:
		return {}
	var res: int = t.res
	var tx0: float = t.x0
	var tz0: float = t.z0
	var base: PackedFloat32Array = t.base
	var data: PackedFloat32Array = (t.data as PackedFloat32Array).duplicate()
	var ov := _tile_override.get_data().to_float32_array()
	var ores := _tile_override.get_width()
	var scale := (res - 1) / float(t.size)
	var px0 := maxi(int(floorf((rect.position.x - tx0) * scale)), 0)
	var pz0 := maxi(int(floorf((rect.position.y - tz0) * scale)), 0)
	var px1 := mini(int(ceilf((rect.end.x - tx0) * scale)), res - 1)
	var pz1 := mini(int(ceilf((rect.end.y - tz0) * scale)), res - 1)
	var oscale := (ores - 1) / _ov_size
	for pz in range(pz0, pz1 + 1):
		var wz := tz0 + pz / scale
		var oz := clampf((wz - _ov_z0) * oscale, 0.0, ores - 1.001)
		var iz := int(oz)
		var fz := oz - iz
		var row := pz * res
		for px in range(px0, px1 + 1):
			var wx := tx0 + px / scale
			var ox := clampf((wx - _ov_x0) * oscale, 0.0, ores - 1.001)
			var ix := int(ox)
			var fx := ox - ix
			var add := lerpf(
				lerpf(ov[iz * ores + ix], ov[iz * ores + ix + 1], fx),
				lerpf(ov[(iz + 1) * ores + ix], ov[(iz + 1) * ores + ix + 1], fx),
				fz)
			data[row + px] = base[row + px] + add
	var fresh := t.duplicate()
	fresh.data = data
	return fresh


## Pen brush: add meters into the override layer within a world-space
## disc, linear falloff to the rim. Cheap (override texels only) — the
## world reshapes on commit_tile_override(), not per stroke sample.
## Returns the painted world rect (empty when there is no tile to ride).
func paint_tile_override(world_xz: Vector2, radius_m: float, amount_m: float) -> Rect2:
	if _tiles.is_empty():
		return Rect2()
	_ensure_override()
	var ores := _tile_override.get_width()
	var oscale := (ores - 1) / _ov_size
	var cx := (world_xz.x - _ov_x0) * oscale
	var cz := (world_xz.y - _ov_z0) * oscale
	var rad := radius_m * oscale
	if rad < 0.5:
		return Rect2()
	for pz in range(maxi(0, int(cz - rad)), mini(ores, int(cz + rad) + 1)):
		for px in range(maxi(0, int(cx - rad)), mini(ores, int(cx + rad) + 1)):
			var d := Vector2(px - cx, pz - cz).length()
			if d > rad:
				continue
			var v := _tile_override.get_pixel(px, pz).r \
				+ amount_m * (1.0 - d / rad)
			_tile_override.set_pixel(px, pz, Color(v, 0.0, 0.0))
	var painted := Rect2(world_xz.x - radius_m, world_xz.y - radius_m,
		radius_m * 2.0, radius_m * 2.0)
	_override_rect = painted if _override_rect.size == Vector2.ZERO \
			else _override_rect.merge(painted)
	return painted


## Commit pen strokes: recomposite base + override inside `world_rect`,
## swap the tile array and a fresh kernel wholesale (the apply pattern),
## and invalidate the rect so cells and the far quadtree rebuild.
func commit_tile_override(world_rect: Rect2) -> void:
	if _tile_override == null or world_rect.size == Vector2.ZERO:
		return
	var swapped := _tiles.duplicate()
	var changed := false
	for i in swapped.size():
		var fresh := _composited_tile(swapped[i], world_rect)
		if not fresh.is_empty():
			swapped[i] = fresh
			changed = true
	if not changed:
		return
	_tiles = swapped
	if kernel:
		kernel.set_tiles(_tiles)  # atomic swap inside; workers unharmed
	edited.emit(world_rect)


## Pen undo support: one-deep snapshot of the override layer (creates an
## empty one first so a pre-stroke snapshot always exists to restore to).
func snapshot_tile_override() -> Image:
	if _tiles.is_empty():
		return null
	_ensure_override()
	return _tile_override.duplicate()


func restore_tile_override(snap: Image) -> void:
	if snap == null or _tile_override == null:
		return
	_tile_override = snap
	# _override_rect stays conservatively large — everything painted since
	# the snapshot lies inside it, so one recomposite reverts the world.
	commit_tile_override(_override_rect)


## Persist the override layer beside the sculpt layer (F5 / Toolkit exit).
## The blessed tile itself is NEVER written here — Strata owns it.
func save_tile_override() -> void:
	if _tile_override == null:
		return
	var dir := ProjectSettings.globalize_path("res://data/terrain")
	DirAccess.make_dir_recursive_absolute(dir)
	_tile_override.save_exr(ProjectSettings.globalize_path(TILE_OVERRIDE_EXR))
	var meta := {
		"x0": _ov_x0, "z0": _ov_z0, "size": _ov_size,
		"rect": {"x": _override_rect.position.x, "z": _override_rect.position.y,
			"w": _override_rect.size.x, "h": _override_rect.size.y},
	}
	var f := FileAccess.open(TILE_OVERRIDE_META, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t", true) + "\n")
	f.close()
	print("[terrain] tile override saved")


## Painted-tile blend at (x,z): replaces `h` inside any tile's rect,
## feathered at the edge, scaled by the home guard. GDScript reference
## for the kernel path (and the non-macOS fallback).
func _tile_blend(x: float, z: float, h: float, guard: float) -> float:
	for t in _tiles:
		var x0: float = t.x0
		var z0: float = t.z0
		var size: float = t.size
		if x < x0 or z < z0 or x >= x0 + size or z >= z0 + size:
			continue
		var res: int = t.res
		var data: PackedFloat32Array = t.data
		var px := (x - x0) / size * (res - 1)
		var pz := (z - z0) / size * (res - 1)
		var ix := mini(int(px), res - 2)
		var iz := mini(int(pz), res - 2)
		var fx := px - ix
		var fz := pz - iz
		var v := lerpf(
			lerpf(data[iz * res + ix], data[iz * res + ix + 1], fx),
			lerpf(data[(iz + 1) * res + ix], data[(iz + 1) * res + ix + 1], fx),
			fz)
		var target: float = t.hmin + v * (t.hmax - t.hmin)
		var edge := minf(minf(x - x0, x0 + size - x), minf(z - z0, z0 + size - z))
		var w: float = smoothstep(0.0, t.feather, edge) * guard
		h = lerpf(h, target, w)
	return h


## Ragged-coast distance wobble: two scales of the multi-octave coast
## noise — big bites AND fine crenellation. Shared by landforms + bays.
func _coast_wobble(x: float, z: float, amp: float, freq: float) -> float:
	var f := freq * 100.0
	return _coast.get_noise_2d(x * f, z * f) * amp \
		+ _coast.get_noise_2d(x * f * 4.7 + 310.0, z * f * 4.7) * amp * 0.4


## Summed authored island height at (x,z). Hot path (every bulk height
## sampler): packed reads only; bbox reject before any shape math; the
## detail-noise sample is shared and taken at most once per call.
func _region_height(x: float, z: float, over_bay_phase: int = 0) -> float:
	var p := Vector2(x, z)
	var total := 0.0
	var detail := 1e12  # sentinel: noise not yet sampled
	for i in _reg_kind.size():
		if _reg_over_bay[i] != over_bay_phase:
			continue
		var b := i * 4
		if x < _reg_bbox[b] or z < _reg_bbox[b + 1] \
				or x >= _reg_bbox[b + 2] or z >= _reg_bbox[b + 3]:
			continue
		var kind := _reg_kind[i]
		var env: float
		if kind == REG_RIDGE:
			var nodes: PackedVector2Array = _reg_nodes[i]
			var d := 1e12
			var s_along := 0.0
			var walked := 0.0
			for s in nodes.size() - 1:
				var a := nodes[s]
				var ab := nodes[s + 1] - a
				var seg_len := ab.length()
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
				var sd := p.distance_to(a + ab * t)
				if sd < d:
					d = sd
					s_along = walked + t * seg_len
				walked += seg_len
			if _reg_coast_amp[i] > 0.0:
				d = maxf(d + _coast_wobble(x, z, _reg_coast_amp[i],
					_reg_coast_freq[i]), 0.0)
			if d >= _reg_reach[i]:
				continue
			env = 1.0 - smoothstep(_reg_inner[i], _reg_reach[i], d)
			# Ridged profile: sharp crest, long walkable shoulders.
			env = env * env * (3.0 - 2.0 * env)
			if _reg_peak_amp[i] > 0.0:
				# Summits and saddles along the spine: a RANGE, not a wall.
				env *= 1.0 - _reg_peak_amp[i] \
					* (0.5 + 0.5 * sin(s_along * TAU / _reg_peak_len[i]))
		else:
			var d := p.distance_to(_reg_center[i])
			if d >= _reg_reach[i]:
				continue
			# Coastline noise: wobble the radial distance so the shore
			# becomes coves and headlands instead of a circle.
			if _reg_coast_amp[i] > 0.0:
				d = maxf(d + _coast_wobble(x, z, _reg_coast_amp[i],
					_reg_coast_freq[i]), 0.0)
				if d >= _reg_reach[i]:
					continue
			if kind == REG_VOLCANO:
				# Eroded volcanic island (Moorea, not a smooth shield):
				# concave flanks steepening toward the summit, cut by
				# radial ravines — strongest mid-flank, fading at the
				# summit plateau and the coast. Drainage for free.
				var t := 1.0 - smoothstep(0.0, _reg_reach[i], d)
				var profile := pow(t, _prof_volcano_power)
				var ang := atan2(z - _reg_center[i].y, x - _reg_center[i].x)
				var wob := _island.get_noise_2d(
					_reg_center[i].x + cos(ang) * 900.0,
					_reg_center[i].y + sin(ang) * 900.0) * 2.2
				var rib := 0.5 + 0.5 * sin(ang * _reg_ridges[i] + wob)
				var ravine_band := smoothstep(0.12, 0.5, t) * (1.0 - smoothstep(0.8, 0.97, t))
				env = profile * (1.0 - _reg_ridge_depth[i] * rib * ravine_band)
			else:
				# 1 on the plateau/summit, feathered to 0 at the skirt edge.
				env = 1.0 - smoothstep(_reg_radius[i] * 0.35, _reg_reach[i], d)
				if kind == REG_MESA:
					# Terraces with rounded risers: flat treads (the city
					# districts) joined by climbable ramps — smoothstepped
					# so no cliff face goes vertical (feel note 2026-07-04:
					# hard-quantized tiers read as bad, too-vertical walls).
					var t := env * _reg_tiers[i]
					var stepped := (floorf(t) + smoothstep(0.15, 0.85, t - floorf(t))) \
						/ _reg_tiers[i]
					env = lerpf(env, stepped, _prof_mesa_blend)
		if detail == 1e12:
			detail = _island.get_noise_2d(x, z)
		total += _reg_height[i] * (env + detail * 0.06 * env)
	return total


## Bays: pull the ground down toward each bay's floor inside its
## (coast-noised) footprint — the sea reaching into the island.
func _bay_carve(x: float, z: float, h: float, guard: float) -> float:
	var p := Vector2(x, z)
	for i in _bay_center.size():
		var reach := _bay_radius[i] + _bay_feather[i] + _bay_amp[i]
		var d := p.distance_to(_bay_center[i])
		if d >= reach:
			continue
		if _bay_amp[i] > 0.0:
			d = maxf(d + _coast_wobble(x, z, _bay_amp[i], _bay_freq[i]), 0.0)
		var w := (1.0 - smoothstep(_bay_radius[i], reach, d)) * guard
		if w > 0.0:
			h = lerpf(h, _bay_floor[i], w)
	return h


## Toolkit: one line per loaded region record, plus the guard band.
func regions_summary() -> String:
	var lines := PackedStringArray()
	lines.append("regions: %d landforms, sea=%.1fm (guard %d..%dm past %s)" % [
		regions.size(), sea_level,
		int(HOME_GUARD_IN), int(HOME_GUARD_OUT), _home_rect])
	for r in regions:
		lines.append("  %s [%s/%s] h=%.0fm at (%.0f, %.0f)" % [
			r.id, r.layer, r.kind, r.height, r.center.x, r.center.y])
	for b in _bays:
		lines.append("  %s [%s/bay] r=%.0fm at (%.0f, %.0f)" % [
			b.id, b.layer, b.radius, b.center.x, b.center.y])
	for t in _tiles:
		lines.append("  %s [tile %dpx] %s %.0fm at (%.0f, %.0f) h=%.0f..%.0fm" % [
			t.id, t.res, t.path.get_file(), t.size, t.x0, t.z0, t.hmin, t.hmax])
	if _tile_override != null:
		lines.append("  pen override [%dpx, %.0fm/px] dirty %s" % [
			_tile_override.get_width(),
			_ov_size / float(_tile_override.get_width()), _override_rect])
	return "\n".join(lines)


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func edit_height(x: float, z: float) -> float:
	var half := EDIT_SIZE * EDIT_M_PER_PX * 0.5
	var px := (x + half) / EDIT_M_PER_PX
	var pz := (z + half) / EDIT_M_PER_PX
	if px < 0.0 or pz < 0.0 or px >= EDIT_SIZE - 1 or pz >= EDIT_SIZE - 1:
		return 0.0
	var ix := int(px)
	var iz := int(pz)
	var fx := px - ix
	var fz := pz - iz
	var h00 := _edits.get_pixel(ix, iz).r
	var h10 := _edits.get_pixel(ix + 1, iz).r
	var h01 := _edits.get_pixel(ix, iz + 1).r
	var h11 := _edits.get_pixel(ix + 1, iz + 1).r
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func apply_brush(center: Vector3, radius: float, amount: float) -> void:
	var half := EDIT_SIZE * EDIT_M_PER_PX * 0.5
	var r_px := int(ceil(radius / EDIT_M_PER_PX))
	var cx := int((center.x + half) / EDIT_M_PER_PX)
	var cz := int((center.z + half) / EDIT_M_PER_PX)
	# Hot loop (held-brush cadence): iterate the disc row by row — the
	# bounding square's corners are never touched — and keep per-pixel
	# work to scalar math plus the two Image calls.
	var r2 := radius * radius
	var inv_r := 1.0 / radius
	for pz in range(maxi(cz - r_px, 0), mini(cz + r_px + 1, EDIT_SIZE)):
		var dz := pz * EDIT_M_PER_PX - half - center.z
		var row_r2 := r2 - dz * dz
		if row_r2 <= 0.0:
			continue
		var row_px := int(sqrt(row_r2) / EDIT_M_PER_PX) + 1
		for px in range(maxi(cx - row_px, 0), mini(cx + row_px + 1, EDIT_SIZE)):
			var dx := px * EDIT_M_PER_PX - half - center.x
			var d2 := dx * dx + dz * dz
			if d2 >= r2:
				continue
			var falloff := smoothstep(1.0, 0.0, sqrt(d2) * inv_r)
			var h := _edits.get_pixel(px, pz).r + amount * falloff
			_edits.set_pixel(px, pz, Color(h, 0, 0))
	edited.emit(Rect2(center.x - radius, center.z - radius, radius * 2.0, radius * 2.0))


## Flatten brush: pull the ground toward `target` height inside the
## disc (Toolkit sculpt, Ctrl+LMB). Same cadence rules as apply_brush.
func flatten_brush(center: Vector3, radius: float, target: float, strength: float) -> void:
	var half := EDIT_SIZE * EDIT_M_PER_PX * 0.5
	var r_px := int(ceil(radius / EDIT_M_PER_PX))
	var cx := int((center.x + half) / EDIT_M_PER_PX)
	var cz := int((center.z + half) / EDIT_M_PER_PX)
	var r2 := radius * radius
	var inv_r := 1.0 / radius
	for pz in range(maxi(cz - r_px, 0), mini(cz + r_px + 1, EDIT_SIZE)):
		var wz := pz * EDIT_M_PER_PX - half
		for px in range(maxi(cx - r_px, 0), mini(cx + r_px + 1, EDIT_SIZE)):
			var wx := px * EDIT_M_PER_PX - half
			var d2 := (wx - center.x) * (wx - center.x) + (wz - center.z) * (wz - center.z)
			if d2 >= r2:
				continue
			var falloff := smoothstep(1.0, 0.0, sqrt(d2) * inv_r)
			var cur := height(wx, wz)
			var e := _edits.get_pixel(px, pz).r
			_edits.set_pixel(px, pz, Color(e + (target - cur) * falloff * strength, 0, 0))
	edited.emit(Rect2(center.x - radius, center.z - radius, radius * 2.0, radius * 2.0))


## Toolkit sculpt undo support: one-deep snapshot of the edit layer.
func snapshot_edits() -> Image:
	return _edits.duplicate()


func restore_edits(snap: Image) -> void:
	if snap == null:
		return
	_edits = snap
	if kernel:
		_init_kernel()  # fresh kernel sees the restored layer
	edited.emit(Rect2(-EDIT_SIZE, -EDIT_SIZE, EDIT_SIZE * 2.0, EDIT_SIZE * 2.0))


func save_edits() -> void:
	var dir := ProjectSettings.globalize_path("res://data/terrain")
	DirAccess.make_dir_recursive_absolute(dir)
	_edits.save_exr(ProjectSettings.globalize_path(EDIT_PATH))
	print("[terrain] edit layer saved")


# --- Undo v2 (audit R3): region mementos for the paint layers. The
# one-deep snapshot_* dups above take the WHOLE layer — fine for a single
# live memento, ruinous for a bounded stack of strokes (a 2048² RF edit
# layer is 16MB each). layer_region carves out just the painted rect — the
# before/after sub-images the ToolkitHistory command holds — so a long
# session's undo stack stays memory-flat. One helper spans the three
# layers (edits / tile override / biome index map); the world→pixel
# transform and the post-restore refresh are the only per-layer parts.


## The pixel rect a world Rect2 covers in one paint layer's image (floor
## the near edge, ceil the far, so a stroke's disc is fully enclosed).
## Clamped to the image below; here it may run past the edges.
func _layer_px_rect(layer: String, wr: Rect2) -> Rect2i:
	match layer:
		"edits":
			var half := EDIT_SIZE * EDIT_M_PER_PX * 0.5
			var x0 := floori((wr.position.x + half) / EDIT_M_PER_PX)
			var z0 := floori((wr.position.y + half) / EDIT_M_PER_PX)
			var x1 := ceili((wr.end.x + half) / EDIT_M_PER_PX)
			var z1 := ceili((wr.end.y + half) / EDIT_M_PER_PX)
			return Rect2i(x0, z0, x1 - x0, z1 - z0)
		"override":
			if _tile_override == null:
				return Rect2i()
			var oscale := (_tile_override.get_width() - 1) / _ov_size
			var x0 := floori((wr.position.x - _ov_x0) * oscale)
			var z0 := floori((wr.position.y - _ov_z0) * oscale)
			var x1 := ceili((wr.end.x - _ov_x0) * oscale)
			var z1 := ceili((wr.end.y - _ov_z0) * oscale)
			return Rect2i(x0, z0, x1 - x0, z1 - z0)
		"biome":
			if _biome_res <= 0:
				return Rect2i()
			var scale := _biome_res / _biome_size
			var x0 := floori((wr.position.x - _biome_origin.x) * scale)
			var z0 := floori((wr.position.y - _biome_origin.y) * scale)
			var x1 := ceili((wr.end.x - _biome_origin.x) * scale)
			var z1 := ceili((wr.end.y - _biome_origin.y) * scale)
			return Rect2i(x0, z0, x1 - x0, z1 - z0)
	return Rect2i()


func _layer_image(layer: String) -> Image:
	match layer:
		"edits": return _edits
		"override": return _tile_override
		"biome": return _biome_img
	return null


## Capture a region memento of a paint layer: the sub-image covering
## `world_rect` plus the pixel rect it occupies. `src` defaults to the live
## layer; pass a pre-stroke WHOLE-layer snapshot to grab the BEFORE image at
## the exact rect the AFTER capture (src=null) will use. {} when the layer
## is absent or the rect misses it entirely — the caller pushes nothing.
func layer_region(layer: String, world_rect: Rect2, src: Image = null) -> Dictionary:
	var img: Image = src if src != null else _layer_image(layer)
	if img == null or world_rect.size == Vector2.ZERO:
		return {}
	var px := _layer_px_rect(layer, world_rect)
	px = px.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if px.size.x <= 0 or px.size.y <= 0:
		return {}
	return {"layer": layer, "rect": px, "world": world_rect,
		"img": img.get_region(px)}


## Blit a region memento back into its layer and refresh exactly what
## changed (the same repaint each restore_* does, scoped to the rect). The
## inverse-of-inverse identity the undo tests pin rides this: a before/after
## pair captured at one rect restores bit-exact.
func restore_layer_region(mem: Dictionary) -> void:
	if mem.is_empty():
		return
	var layer := String(mem["layer"])
	var rect: Rect2i = mem["rect"]
	var world: Rect2 = mem["world"]
	var sub: Image = mem["img"]
	var dst := _layer_image(layer)
	if dst == null:
		return
	dst.blit_rect(sub, Rect2i(Vector2i.ZERO, rect.size), rect.position)
	match layer:
		"edits":
			if kernel:
				_init_kernel()  # the kernel reads the whole edit layer
			edited.emit(world)
		"override":
			# Grow the persisted dirty rect so save_tile_override writes the
			# reverted region, then recomposite base+override over it.
			_override_rect = world if _override_rect.size == Vector2.ZERO \
					else _override_rect.merge(world)
			commit_tile_override(world)
		"biome":
			_biome_idx_tex.update(_biome_img)
			edited.emit(world)  # re-flora the reverted region


## Remove a runtime-penned river by id (undo v2: the carve joins the undo
## stack). Erases it, REINDEXES the survivors — river.idx is a slot into
## river_levels, so a hole would misread — resets the levels (Hydrology's
## region tier rewrites them next tick), rebuilds the kernel so the carve
## lifts out of the ground, and invalidates the river's span. no_sim penned
## rivers only in practice; returns whether anything was removed.
func remove_river(id: String) -> bool:
	var found := -1
	for i in rivers.size():
		if String(rivers[i].id) == id:
			found = i
			break
	if found < 0:
		return false
	var bbox: Rect2 = rivers[found].bbox
	rivers.remove_at(found)
	for i in rivers.size():
		rivers[i].idx = i
	river_levels.resize(rivers.size())
	for i in rivers.size():
		river_levels[i] = 0.0
	if kernel:
		_init_kernel()  # fresh instance sees the shortened river set
	edited.emit(bbox)
	return true
