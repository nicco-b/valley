extends Node3D
## Streams world cells around the player. The world is a grid of
## CELL_SIZE-meter cells: a flat terrain tile is generated for every cell
## (placeholder until heightmap terrain), and authored content scenes
## (game/world/cells/cell_X_Y.tscn, coordinates in the filename) are
## thread-loaded on top as the player approaches.

const CELL_SIZE := 128.0
const CELLS_DIR := "res://game/world/cells"
const TERRAIN_RES := 49  # vertices per cell side (~2.7m grid; gen is threaded)

var load_radius := 2  # Chebyshev radius of cells kept loaded (map widens this)

var _authored: Dictionary = {}  # Vector2i -> scene path
var _terrain: Dictionary = {}  # Vector2i -> terrain node
var _content: Dictionary = {}  # Vector2i -> instanced authored scene
var _records: Dictionary = {}  # Vector2i -> container of placed-record objects
var _pending: Dictionary = {}  # Vector2i -> path in threaded load
var _terrain_pending: Dictionary = {}  # Vector2i -> WorkerThreadPool task id
var _terrain_results: Array = []  # [cell, mesh, shape] built off-thread
var _results_mutex := Mutex.new()

# Flora kit: [texture path, height in meters, scatter weight]
const FLORA := [
	["res://assets/paintings/silly_tree.png", 3.5, 0.3],
	["res://assets/paintings/silly_tree_2.png", 1.8, 0.5],
	["res://assets/paintings/silly_tree_3.png", 4.6, 0.2],
]

# Ground cover: the dense low stratum (placeholder SVGs until painted
# tufts arrive — same slots). [texture path, height m, weight]
const GROUND_COVER := [
	["res://assets/paintings/placeholder_tuft_1.svg", 0.5, 0.45],
	["res://assets/paintings/placeholder_tuft_2.svg", 0.35, 0.35],
	["res://assets/paintings/placeholder_pebbles.svg", 0.22, 0.2],
]
const COVER_VISIBLE_RANGE := 75.0

var _ground_material: ShaderMaterial
var _flora_meshes: Array[QuadMesh] = []
var _cover_meshes: Array[QuadMesh] = []

@onready var _player: Node3D = get_tree().get_first_node_in_group("player")


var _dirty: Dictionary = {}
var _rebuild_cooldown := 0.0
# Sculpt-feedback split: the mesh rebuilds immediately (sculpting wants
# it), but navmesh re-bakes are deferred to the worker thread and only
# run once the brush goes quiet — baking + region sync per stroke made
# editing choppy, and nobody notices the walkable surface lagging 1s.
var _nav_dirty: Dictionary = {}  # cells whose navmesh lags a sculpt edit
var _nav_pending: Dictionary = {}  # cell -> worker task id
var _nav_results: Array = []  # [cell, navmesh] built off-thread
var _nav_cooldown := 0.0


func _ready() -> void:
	add_to_group("world_streamer")
	_scan_authored()
	Terrain.edited.connect(_on_terrain_edited)
	CellRecords.changed.connect(_on_records_changed)
	# Painterly terrain material with a shared seamless variation texture.
	var vnoise := FastNoiseLite.new()
	vnoise.seed = 11
	var vtex := NoiseTexture2D.new()
	vtex.seamless = true
	vtex.width = 256
	vtex.height = 256
	vtex.noise = vnoise
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = load("res://game/shaders/terrain.gdshader")
	_ground_material.set_shader_parameter("variation", vtex)

	# Shared billboard meshes for flora and ground cover (sway shader).
	var sway := load("res://game/shaders/flora_sway.gdshader")
	for f in FLORA:
		_flora_meshes.append(_make_billboard_mesh(f[0], f[1], sway))
	for f in GROUND_COVER:
		_cover_meshes.append(_make_billboard_mesh(f[0], f[1], sway))

	# Synchronous first fill: the ground must exist before the first physics frame.
	_update_cells(true)


func _process(delta: float) -> void:
	_update_cells(false)
	_poll_pending()
	_drain_terrain_results()
	_rebuild_cooldown -= delta
	if not _dirty.is_empty() and _rebuild_cooldown <= 0.0:
		_rebuild_cooldown = 0.2
		for c in _dirty.keys():
			if _terrain.has(c):
				_terrain[c].queue_free()
				_terrain.erase(c)
				_add_terrain_sync(c, false)  # sculpting wants immediate feedback
				_nav_dirty[c] = true  # the old navmesh serves until quiet
		_dirty.clear()
		_nav_cooldown = 0.8
	_nav_cooldown -= delta
	if _dirty.is_empty() and _nav_cooldown <= 0.0 and not _nav_dirty.is_empty():
		for c in _nav_dirty.keys():
			if _terrain.has(c) and not _nav_pending.has(c):
				_nav_pending[c] = WorkerThreadPool.add_task(_thread_rebake_nav.bind(c))
		_nav_dirty.clear()
	_drain_nav_results()


func _on_terrain_edited(world_rect: Rect2) -> void:
	var c0 := Vector2i(roundi(world_rect.position.x / CELL_SIZE), roundi(world_rect.position.y / CELL_SIZE))
	var c1 := Vector2i(roundi(world_rect.end.x / CELL_SIZE), roundi(world_rect.end.y / CELL_SIZE))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cy)
			if _terrain.has(c):
				_dirty[c] = true


func _scan_authored() -> void:
	var dir := DirAccess.open(CELLS_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("cell_") and f.ends_with(".tscn"):
			var parts := f.trim_suffix(".tscn").split("_")
			if parts.size() == 3:
				var c := Vector2i(parts[1].to_int(), parts[2].to_int())
				_authored[c] = CELLS_DIR + "/" + f


func _focus_position() -> Vector3:
	# Streaming follows the god camera or map focus when either is active.
	var p := _player.global_position
	if GodMode.active:
		p = GodMode.cam_position()
	elif MapScreen.active:
		p = MapScreen.focus_position()
	return p


func _player_cell() -> Vector2i:
	var p := _focus_position()
	return Vector2i(roundi(p.x / CELL_SIZE), roundi(p.z / CELL_SIZE))


func _update_cells(sync: bool) -> void:
	var fp := _focus_position()
	# The far LOD's discard zone follows wherever full cells exist.
	RenderingServer.global_shader_parameter_set(
		"stream_center", Vector2(fp.x, fp.z))
	var center := _player_cell()
	for dy in range(-load_radius, load_radius + 1):
		for dx in range(-load_radius, load_radius + 1):
			var c := center + Vector2i(dx, dy)
			if not _terrain.has(c) and not _terrain_pending.has(c):
				if sync:
					_add_terrain_sync(c)
				else:
					_terrain_pending[c] = WorkerThreadPool.add_task(
						_thread_build_terrain.bind(c))
			if not _records.has(c) and not CellRecords.records(c).is_empty():
				_add_records(c)
			if _authored.has(c) and not _content.has(c) and not _pending.has(c):
				if sync:
					_add_content(c, load(_authored[c]))
				else:
					ResourceLoader.load_threaded_request(_authored[c])
					_pending[c] = _authored[c]
	var unload_radius := load_radius + 1
	for c in _terrain.keys():
		if _chebyshev(c - center) > unload_radius:
			_terrain[c].queue_free()
			_terrain.erase(c)
			Nav.remove_cell(c)
	for c in _content.keys():
		if _chebyshev(c - center) > unload_radius:
			_content[c].queue_free()
			_content.erase(c)
	for c in _records.keys():
		if _chebyshev(c - center) > unload_radius:
			_records[c].queue_free()
			_records.erase(c)


func _poll_pending() -> void:
	for c in _pending.keys():
		var path: String = _pending[c]
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				_add_content(c, ResourceLoader.load_threaded_get(path))
				_pending.erase(c)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("Failed to stream cell scene: " + path)
				_pending.erase(c)


## Heavy part of cell generation, safe to run on a worker thread: builds
## the mesh, collision shape, and (unless deferred) baked navmesh — only
## reads Terrain + creates resources. The navmesh gets the same triangles
## minus anything submerged — nobody paths through the pond.
func _build_terrain_mesh(c: Vector2i, with_nav := true) -> Array:
	var origin := Vector3(
		c.x * CELL_SIZE - CELL_SIZE * 0.5, 0.0, c.y * CELL_SIZE - CELL_SIZE * 0.5
	)
	var step := CELL_SIZE / (TERRAIN_RES - 1)
	var pts := PackedVector3Array()
	pts.resize(TERRAIN_RES * TERRAIN_RES)
	var wet := PackedByteArray()
	wet.resize(TERRAIN_RES * TERRAIN_RES)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_ground_material)
	st.set_smooth_group(0)
	for iz in TERRAIN_RES:
		for ix in TERRAIN_RES:
			var wx := origin.x + ix * step
			var wz := origin.z + iz * step
			var y := Terrain.height(wx, wz)
			var i := iz * TERRAIN_RES + ix
			pts[i] = Vector3(ix * step, y, iz * step)
			wet[i] = 1 if y < Terrain.water_surface(wx, wz) - 0.05 else 0
			st.set_uv(Vector2(wx, wz) * 0.05)
			st.add_vertex(pts[i])
	var faces := PackedVector3Array()
	for iz in TERRAIN_RES - 1:
		for ix in TERRAIN_RES - 1:
			var i := iz * TERRAIN_RES + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + TERRAIN_RES)
			st.add_index(i + 1)
			st.add_index(i + TERRAIN_RES + 1)
			st.add_index(i + TERRAIN_RES)
			if not with_nav:
				continue
			if wet[i] == 0 and wet[i + 1] == 0 and wet[i + TERRAIN_RES] == 0:
				faces.append(pts[i])
				faces.append(pts[i + 1])
				faces.append(pts[i + TERRAIN_RES])
			if wet[i + 1] == 0 and wet[i + TERRAIN_RES + 1] == 0 and wet[i + TERRAIN_RES] == 0:
				faces.append(pts[i + 1])
				faces.append(pts[i + TERRAIN_RES + 1])
				faces.append(pts[i + TERRAIN_RES])
	st.generate_normals()
	var mesh := st.commit()
	var navmesh: NavigationMesh = Nav.bake_navmesh(faces) if with_nav else null
	return [mesh, mesh.create_trimesh_shape(), navmesh]


func _thread_build_terrain(c: Vector2i) -> void:
	var built := _build_terrain_mesh(c)
	_results_mutex.lock()
	_terrain_results.append([c, built[0], built[1], built[2]])
	_results_mutex.unlock()


func _drain_terrain_results() -> void:
	_results_mutex.lock()
	var results := _terrain_results.duplicate()
	_terrain_results.clear()
	_results_mutex.unlock()
	for r in results:
		var c: Vector2i = r[0]
		if _terrain_pending.has(c):
			WorkerThreadPool.wait_for_task_completion(_terrain_pending[c])
			_terrain_pending.erase(c)
		if _terrain.has(c):
			continue
		if _chebyshev(c - _player_cell()) > load_radius + 1:
			continue  # streamed past it while building; let it lapse
		_finish_terrain(c, r[1], r[2], r[3])


func _add_terrain_sync(c: Vector2i, with_nav := true) -> void:
	var built := _build_terrain_mesh(c, with_nav)
	_finish_terrain(c, built[0], built[1], built[2])


## Deferred navmesh rebake after sculpting, off the main thread.
func _thread_rebake_nav(c: Vector2i) -> void:
	var built := _build_terrain_mesh(c, true)
	_results_mutex.lock()
	_nav_results.append([c, built[2]])
	_results_mutex.unlock()


func _drain_nav_results() -> void:
	_results_mutex.lock()
	var results := _nav_results.duplicate()
	_nav_results.clear()
	_results_mutex.unlock()
	for r in results:
		var c: Vector2i = r[0]
		if _nav_pending.has(c):
			WorkerThreadPool.wait_for_task_completion(_nav_pending[c])
			_nav_pending.erase(c)
		if _terrain.has(c):
			Nav.add_cell(c, r[1], Vector3(
				c.x * CELL_SIZE - CELL_SIZE * 0.5, 0.0, c.y * CELL_SIZE - CELL_SIZE * 0.5))


func _finish_terrain(c: Vector2i, mesh: ArrayMesh, shape: Shape3D,
		navmesh: NavigationMesh) -> void:
	var origin := Vector3(
		c.x * CELL_SIZE - CELL_SIZE * 0.5, 0.0, c.y * CELL_SIZE - CELL_SIZE * 0.5
	)
	var body := StaticBody3D.new()
	body.name = "Terrain_%d_%d" % [c.x, c.y]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(mi)
	body.add_child(col)
	body.position = origin
	_add_scatter(c, body, origin)
	_add_ground_cover(c, body, origin,
			Terrain.valley_factor(origin.x + CELL_SIZE * 0.5, origin.z + CELL_SIZE * 0.5))
	add_child(body)
	_terrain[c] = body
	if navmesh != null:
		Nav.add_cell(c, navmesh, origin)  # deferred rebakes keep the old region


func _add_scatter(c: Vector2i, parent: Node3D, origin: Vector3) -> void:
	# Deterministic flora scatter: same cell -> same trees, forever.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var buckets: Array = []
	for f in FLORA:
		buckets.append([] as Array[Transform3D])
	var colliders: Array = []  # [variant, transform] for large flora
	# Dense on the valley floor, sparse on the plateau.
	var cell_center := Vector2(origin.x + CELL_SIZE * 0.5, origin.z + CELL_SIZE * 0.5)
	var vf: float = Terrain.valley_factor(cell_center.x, cell_center.y)
	var base_count := int(round(lerpf(34.0, 8.0, vf)))
	for i in rng.randi_range(base_count, base_count + 8):
		var lx := rng.randf() * CELL_SIZE
		var lz := rng.randf() * CELL_SIZE
		var variant := _pick_weighted(FLORA, rng.randf())
		var s := rng.randf_range(0.75, 1.15)
		var wx := origin.x + lx
		var wz := origin.z + lz
		var clear := false
		for f in Terrain.FLATTENS:
			if Vector2(wx - f[0], wz - f[1]).length() < f[2] + f[3]:
				clear = true
				break
		if clear:
			continue
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)),
				Vector3(lx, Terrain.height(wx, wz), lz))
		buckets[variant].append(xf)
		if variant != 1:  # the shrub stays walkable; trees get trunks
			colliders.append([variant, xf])
	for v in FLORA.size():
		var transforms: Array[Transform3D] = buckets[v]
		if transforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _flora_meshes[v]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		parent.add_child(mmi)
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = 5  # world (1) + obstacle (4) for NPC avoidance
		for entry in colliders:
			var s: float = entry[1].basis.get_scale().x
			var shape := CylinderShape3D.new()
			shape.radius = (0.35 if entry[0] == 0 else 0.5) * s
			shape.height = 4.0 * s
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = entry[1].origin + Vector3(0.0, 2.0 * s, 0.0)
			body.add_child(col)
		parent.add_child(body)


func _add_records(c: Vector2i) -> void:
	var container := Node3D.new()
	for rec in CellRecords.records(c):
		var scene: PackedScene = Kit.scene(rec.kit)
		if scene == null:
			continue
		var node: Node3D = scene.instantiate()
		container.add_child(node)
		var y: float = rec.y
		if rec.get("snap", false):
			y = Terrain.height(rec.x, rec.z)
		node.position = Vector3(rec.x, y, rec.z)
		node.rotation.y = rec.yaw
		node.scale = Vector3.ONE * rec.get("scale", 1.0)
	add_child(container)
	_records[c] = container


func _on_records_changed(c: Vector2i) -> void:
	if _records.has(c):
		_records[c].queue_free()
		_records.erase(c)
	if _terrain.has(c) and not CellRecords.records(c).is_empty():
		_add_records(c)


func _make_billboard_mesh(path: String, h: float, sway: Shader) -> QuadMesh:
	var tex: Texture2D = load(path)
	var mat := ShaderMaterial.new()
	mat.shader = sway
	mat.set_shader_parameter("albedo_tex", tex)
	var w: float = h * float(tex.get_width()) / float(tex.get_height())
	var mesh := QuadMesh.new()
	mesh.size = Vector2(w, h)
	mesh.center_offset = Vector3(0, h * 0.5, 0)
	mesh.material = mat
	return mesh


func _add_ground_cover(c: Vector2i, parent: Node3D, origin: Vector3, vf: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) * 31 + 7
	var count := int(round(lerpf(240.0, 12.0, vf)))
	var buckets: Array = []
	for f in GROUND_COVER:
		buckets.append([] as Array[Transform3D])
	for i in count:
		var lx := rng.randf() * CELL_SIZE
		var lz := rng.randf() * CELL_SIZE
		var wx := origin.x + lx
		var wz := origin.z + lz
		var in_clearing := false
		for f in Terrain.FLATTENS:
			# Cover may enter clearings' feather but not their core.
			if Vector2(wx - f[0], wz - f[1]).length() < f[2] * 0.8:
				in_clearing = true
				break
		if in_clearing:
			continue
		var variant := _pick_weighted(GROUND_COVER, rng.randf())
		var s := rng.randf_range(0.7, 1.35)
		buckets[variant].append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)),
				Vector3(lx, Terrain.height(wx, wz) - 0.02, lz)))
	for v in GROUND_COVER.size():
		var transforms: Array[Transform3D] = buckets[v]
		if transforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _cover_meshes[v]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = COVER_VISIBLE_RANGE
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


func _pick_weighted(table: Array, roll: float) -> int:
	var acc := 0.0
	for v in table.size():
		acc += table[v][2]
		if roll <= acc:
			return v
	return table.size() - 1


func _add_content(c: Vector2i, scene: PackedScene) -> void:
	var node: Node3D = scene.instantiate()
	node.position = Vector3(c.x * CELL_SIZE, 0.0, c.y * CELL_SIZE)
	add_child(node)
	# Authored content is placed as if the ground were flat; settle each
	# top-level object onto the actual terrain under it.
	for child in node.get_children():
		if child is Node3D:
			var gp: Vector3 = child.global_position
			child.position.y += Terrain.height(gp.x, gp.z)
	_content[c] = node
	print("[world] cell content loaded: ", c)


func _chebyshev(v: Vector2i) -> int:
	return maxi(absi(v.x), absi(v.y))
