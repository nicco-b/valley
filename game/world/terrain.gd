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

# Loaded lake records, normalized: {id, center: Vector2, radius, surface,
# basin_radius, basin_depth, level}. `surface` is authored; `level` is the
# live offset Hydrology writes hourly. Geometry fields read-only after
# _ready.
var water_bodies: Array[Dictionary] = []

# Loaded river records, normalized: {id, depth, feather, flow: Vector2,
# level, nodes: [{pos: Vector2, half: float, surface: float}]}. A river is
# a spline: the bed is carved below the authored surface in height(), the
# live surface (authored + Hydrology's level) returned by water_surface()
# within the ribbon.
var rivers: Array[Dictionary] = []


## Live water surface height at a point (authored + hydrology level), or
## -INF when there's no water there. Physics, moisture, and rendering read
## this; deterministic cell generation reads water_surface_base().
func water_surface(x: float, z: float) -> float:
	for w in water_bodies:
		var c: Vector2 = w.center
		if Vector2(x - c.x, z - c.y).length() < float(w.radius):
			return float(w.surface) + float(w.level)
	for r in rivers:
		var q := river_query(r, x, z)
		if q.d < q.half:
			return float(q.surface) + float(r.level)
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
		var q := river_query(r, x, z)
		if q.d < q.half:
			return q.surface
	return -1e12


## Closest point on a river's centerline to (x,z): {d, half, surface}
## with half-width and surface height interpolated along the spline.
func river_query(r: Dictionary, x: float, z: float) -> Dictionary:
	var p := Vector2(x, z)
	var nodes: Array = r.nodes
	var best_d := 1e12
	var best_half := 0.0
	var best_surf := 0.0
	for i in nodes.size() - 1:
		var a: Dictionary = nodes[i]
		var b: Dictionary = nodes[i + 1]
		var pa: Vector2 = a.pos
		var ab: Vector2 = b.pos - pa
		var t := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		var d := p.distance_to(pa + ab * t)
		if d < best_d:
			best_d = d
			best_half = lerpf(a.half, b.half, t)
			best_surf = lerpf(a.surface, b.surface, t)
	return {"d": best_d, "half": best_half, "surface": best_surf}

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
		var q := river_query(r, x, z)
		var half: float = q.half
		var feather: float = r.feather
		if q.d > half + feather:
			continue
		var target: float
		if q.d <= half:
			target = lerpf(q.surface - r.depth, q.surface, q.d / maxf(half, 1e-4))
		else:
			target = lerpf(q.surface, h, (q.d - half) / feather)
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
			"center": Vector2(float(center["x"]), float(center["z"])),
			"radius": float(rec["radius"]),
			"surface": float(rec["surface"]),
			"basin_radius": float(basin.get("radius", rec["radius"])),
			"basin_depth": float(basin.get("depth", 0.0)),
			"level": 0.0,
		})
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
		rivers.append({
			"id": rec.get("id", f.trim_suffix(".json")),
			"depth": float(rec.get("depth", 1.2)),
			"feather": float(rec.get("feather", 4.0)),
			"flow": flow,
			"level": 0.0,
			"nodes": nodes,
		})


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
