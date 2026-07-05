extends Node
## Global terrain height function, autoloaded as Terrain. Deterministic
## (fixed seeds): every run and every cell samples the same world.
## Terrain meshes, collision, and content placement all read from here.
## Hand-authored terrain will later override/blend with this base.

# Flattened disks so authored content sits on level ground:
# [center x, center z, flat radius, feather distance]
const FLATTENS := [
	[0.0, 0.0, 60.0, 70.0],  # spawn area & starter rocks
	[120.0, -620.0, 35.0, 60.0],  # shrine
	[70.0, -310.0, 45.0, 40.0],  # pond clearing (also keeps flora out of water)
]

# Water bodies come from data/water/: circular lakes as basin + surface
# height (top-level *.json), and rivers as node polylines (rivers/*.json).
# Everything water-shaped (swimming, navmesh carving, moisture floors,
# surface meshes) reads these records through here.
const WATER_DIR := "res://data/water"
const RIVER_DIR := "res://data/water/rivers"

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

# The home valley: an authored landform. Centerline from behind spawn,
# past the pond, to the shrine; floor stays low and dense, walls rise
# into an enclosing ridge plateau (doubles as the frontier rim).
const VALLEY_PATH := [
	Vector2(0, 220), Vector2(0, 0), Vector2(30, -160), Vector2(70, -310),
	Vector2(95, -470), Vector2(120, -620), Vector2(130, -790),
]
const VALLEY_INNER := 120.0
const VALLEY_OUTER := 220.0
const WALL_HEIGHT := 42.0

# Authored edit layer: a float heightmap sculpted in god mode (and later
# paintable externally), added on top of the base noise. World-anchored,
# EDIT_M_PER_PX meters per pixel, centered on the origin.
const EDIT_SIZE := 2048  # pixels per side
const EDIT_M_PER_PX := 2.0
const EDIT_PATH := "res://data/terrain/edit_layer.exr"

signal edited(world_rect: Rect2)

var _edits: Image
var _hills := FastNoiseLite.new()
var _dunes := FastNoiseLite.new()
var _ranges := FastNoiseLite.new()


func _ready() -> void:
	_load_water()
	_hills.seed = 7
	_hills.frequency = 0.0025
	_hills.fractal_octaves = 4
	_dunes.seed = 40
	_dunes.frequency = 0.03
	# Real distant mountains ("if you can see it, you can go there"):
	# ridged ranges that stay out of the home valley and rise beyond it.
	_ranges.seed = 23
	_ranges.frequency = 0.0007
	_ranges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ranges.fractal_octaves = 3
	if FileAccess.file_exists(EDIT_PATH):
		_edits = Image.load_from_file(ProjectSettings.globalize_path(EDIT_PATH))
		_edits.convert(Image.FORMAT_RF)
	else:
		_edits = Image.create(EDIT_SIZE, EDIT_SIZE, false, Image.FORMAT_RF)


## 0.0 on the valley floor, 1.0 on the surrounding plateau.
func valley_factor(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := 1e12
	for i in VALLEY_PATH.size() - 1:
		d = minf(d, _segment_distance(p, VALLEY_PATH[i], VALLEY_PATH[i + 1]))
	return smoothstep(VALLEY_INNER, VALLEY_OUTER, d)


func height(x: float, z: float) -> float:
	var floor_h := _hills.get_noise_2d(x, z) * 3.0 + _dunes.get_noise_2d(x, z) * 0.6
	var wall_h := WALL_HEIGHT + _hills.get_noise_2d(x, z) * 22.0
	var h := lerpf(floor_h, wall_h, valley_factor(x, z))
	# Mountain ranges: absent near home, real and walkable beyond ~1.2km.
	var range_envelope := smoothstep(1200.0, 2400.0, Vector2(x, z).length())
	h += maxf(_ranges.get_noise_2d(x, z), 0.0) * 320.0 * range_envelope
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
		var raw_nodes: Array = rec["nodes"]
		if raw_nodes.size() < 2:
			push_error("[terrain] river needs >=2 nodes: " + path)
			continue
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
		var river := {
			"id": rec.get("id", f.trim_suffix(".json")),
			"idx": rivers.size(),
			"depth": float(rec.get("depth", 1.2)),
			"feather": float(rec.get("feather", 4.0)),
			"flow": flow,
			"nodes": nodes,
		}
		_index_river(river)
		rivers.append(river)
	river_levels.resize(rivers.size())


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


func save_edits() -> void:
	var dir := ProjectSettings.globalize_path("res://data/terrain")
	DirAccess.make_dir_recursive_absolute(dir)
	_edits.save_exr(ProjectSettings.globalize_path(EDIT_PATH))
	print("[terrain] edit layer saved")
