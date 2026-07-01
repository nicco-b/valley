extends Node3D
## Streams world cells around the player. The world is a grid of
## CELL_SIZE-meter cells: a flat terrain tile is generated for every cell
## (placeholder until heightmap terrain), and authored content scenes
## (game/world/cells/cell_X_Y.tscn, coordinates in the filename) are
## thread-loaded on top as the player approaches.

const CELL_SIZE := 128.0
const LOAD_RADIUS := 2  # Chebyshev radius of cells kept loaded
const UNLOAD_RADIUS := 3  # hysteresis so border cells don't thrash
const CELLS_DIR := "res://game/world/cells"
const TERRAIN_RES := 33  # vertices per cell side (4m grid)

var _authored: Dictionary = {}  # Vector2i -> scene path
var _terrain: Dictionary = {}  # Vector2i -> terrain node
var _content: Dictionary = {}  # Vector2i -> instanced authored scene
var _pending: Dictionary = {}  # Vector2i -> path in threaded load

# Flora kit: [texture path, height in meters, scatter weight]
const FLORA := [
	["res://assets/paintings/silly_tree.png", 3.5, 0.3],
	["res://assets/paintings/silly_tree_2.png", 1.8, 0.5],
	["res://assets/paintings/silly_tree_3.png", 4.6, 0.2],
]

var _ground_material: StandardMaterial3D
var _flora_meshes: Array[QuadMesh] = []

@onready var _player: Node3D = get_tree().get_first_node_in_group("player")


func _ready() -> void:
	_scan_authored()
	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_color = Color(0.929, 0.89, 0.82)
	_ground_material.roughness = 1.0

	# Shared billboard meshes, one per flora kit entry.
	for f in FLORA:
		var tex: Texture2D = load(f[0])
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		mat.billboard_keep_scale = true
		mat.roughness = 1.0
		var h: float = f[1]
		var w: float = h * float(tex.get_width()) / float(tex.get_height())
		var mesh := QuadMesh.new()
		mesh.size = Vector2(w, h)
		mesh.center_offset = Vector3(0, h * 0.5, 0)
		mesh.material = mat
		_flora_meshes.append(mesh)

	# Synchronous first fill: the ground must exist before the first physics frame.
	_update_cells(true)


func _process(_delta: float) -> void:
	_update_cells(false)
	_poll_pending()


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


func _player_cell() -> Vector2i:
	var p := _player.global_position
	return Vector2i(roundi(p.x / CELL_SIZE), roundi(p.z / CELL_SIZE))


func _update_cells(sync: bool) -> void:
	var center := _player_cell()
	for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var c := center + Vector2i(dx, dy)
			if not _terrain.has(c):
				_add_terrain(c)
			if _authored.has(c) and not _content.has(c) and not _pending.has(c):
				if sync:
					_add_content(c, load(_authored[c]))
				else:
					ResourceLoader.load_threaded_request(_authored[c])
					_pending[c] = _authored[c]
	for c in _terrain.keys():
		if _chebyshev(c - center) > UNLOAD_RADIUS:
			_terrain[c].queue_free()
			_terrain.erase(c)
	for c in _content.keys():
		if _chebyshev(c - center) > UNLOAD_RADIUS:
			_content[c].queue_free()
			_content.erase(c)


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


func _add_terrain(c: Vector2i) -> void:
	var origin := Vector3(
		c.x * CELL_SIZE - CELL_SIZE * 0.5, 0.0, c.y * CELL_SIZE - CELL_SIZE * 0.5
	)
	var step := CELL_SIZE / (TERRAIN_RES - 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_ground_material)
	st.set_smooth_group(0)
	for iz in TERRAIN_RES:
		for ix in TERRAIN_RES:
			var wx := origin.x + ix * step
			var wz := origin.z + iz * step
			st.set_uv(Vector2(wx, wz) * 0.05)
			st.add_vertex(Vector3(ix * step, Terrain.height(wx, wz), iz * step))
	for iz in TERRAIN_RES - 1:
		for ix in TERRAIN_RES - 1:
			var i := iz * TERRAIN_RES + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + TERRAIN_RES)
			st.add_index(i + 1)
			st.add_index(i + TERRAIN_RES + 1)
			st.add_index(i + TERRAIN_RES)
	st.generate_normals()
	var mesh := st.commit()

	var body := StaticBody3D.new()
	body.name = "Terrain_%d_%d" % [c.x, c.y]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(mi)
	body.add_child(col)
	body.position = origin
	_add_scatter(c, body, origin)
	add_child(body)
	_terrain[c] = body


func _add_scatter(c: Vector2i, parent: Node3D, origin: Vector3) -> void:
	# Deterministic flora scatter: same cell -> same trees, forever.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var buckets: Array = []
	for f in FLORA:
		buckets.append([] as Array[Transform3D])
	for i in rng.randi_range(10, 20):
		var lx := rng.randf() * CELL_SIZE
		var lz := rng.randf() * CELL_SIZE
		var variant := _pick_flora(rng.randf())
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
		buckets[variant].append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)),
				Vector3(lx, Terrain.height(wx, wz), lz)))
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


func _pick_flora(roll: float) -> int:
	var acc := 0.0
	for v in FLORA.size():
		acc += FLORA[v][2]
		if roll <= acc:
			return v
	return FLORA.size() - 1


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
