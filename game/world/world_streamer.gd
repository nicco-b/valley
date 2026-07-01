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

var _ground_material: StandardMaterial3D

@onready var _player: Node3D = get_tree().get_first_node_in_group("player")


func _ready() -> void:
	_scan_authored()
	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_color = Color(0.929, 0.89, 0.82)
	_ground_material.roughness = 1.0
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
	add_child(body)
	_terrain[c] = body


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
