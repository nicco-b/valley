extends Node3D
## Far-terrain quadtree (the Loom, F3): the horizon as cached LOD
## tiles instead of one re-sampled 6.4km sheet. Root tiles of 8192m
## split toward the focus down to 1024m leaves — constant 33 verts per
## tile side, so meters-per-vertex scales with distance (32m close,
## 256m at the rim). Tiles build one at a time on a dedicated thread
## (never the worker pool — cell builds starved the horizon there),
## through the native kernel when present, and are CACHED by world
## grid key: recrossing the archipelago re-shows tiles instead of
## re-sampling them. Skirts hide the cracks between LOD levels; the
## terrain shader still discards fragments inside the streamed
## footprint (far_lod + stream_center) so near cells win.
##  - Sculpt edits (and tile hot-reloads) invalidate intersecting
##    tiles via Terrain.edited, debounced.
##  - "If you can see it, you can go there": same height function as
##    the streamed cells, all the way to the world rim.

const WORLD_REACH := 12288.0  # tiles considered within this radius
const ROOT_SIZE := 8192.0
const MIN_TILE := 1024.0
const SPLIT_K := 1.2  # split while focus is within K * size of the tile
const TILE_RES := 33  # vertices per tile side, every LOD level
const SINK := 1.5  # sits below true height so near cells win at distance
const EDIT_REBUILD_DELAY := 1.2  # settle time after the last brush stroke
const CACHE_MAX := 220  # tiles kept warm (hidden) beyond the desired set

var _material: ShaderMaterial
var _cache: Dictionary = {}  # key -> MeshInstance3D (child of self)
var _cache_age: Dictionary = {}  # key -> last-desired tick (LRU)
var _tick := 0
var _thread: Thread
var _building_key := ""
var _built_mutex := Mutex.new()
var _built: Array = []  # [key, mesh] finished by the builder thread
var _pending_edits: Array[Rect2] = []
var _edit_cooldown := 0.0


func _ready() -> void:
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		_material = streamer._ground_material.duplicate()
		_material.set_shader_parameter("far_lod", true)
	Terrain.edited.connect(func(rect: Rect2) -> void:
		_pending_edits.append(rect)
		_edit_cooldown = EDIT_REBUILD_DELAY)


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _process(delta: float) -> void:
	var focus := _focus()
	_tick += 1

	# Sculpt/tile edits: drop intersecting tiles once the brush settles.
	if not _pending_edits.is_empty():
		_edit_cooldown -= delta
		if _edit_cooldown <= 0.0:
			for rect in _pending_edits:
				_invalidate(rect)
			_pending_edits.clear()

	# Collect finished builds (thread appends; main applies).
	_built_mutex.lock()
	var done := _built.duplicate()
	_built.clear()
	_built_mutex.unlock()
	if not done.is_empty():
		if _thread != null:
			_thread.wait_to_finish()
			_thread = null
		_building_key = ""
		for b in done:
			_adopt(b[0], b[1])

	# Desired leaf set for this focus; show cached, queue the nearest
	# missing tile, hide the rest.
	var desired := {}
	_collect_leaves(focus, desired)
	var best_key := ""
	var best_d := 1e18
	for key: String in desired:
		_cache_age[key] = _tick
		var mi: MeshInstance3D = _cache.get(key)
		if mi != null:
			mi.visible = true
			continue
		if key == _building_key:
			continue
		var t: Vector3 = desired[key]  # size, ix, iz
		var center := Vector2((t.y + 0.5) * t.x, (t.z + 0.5) * t.x)
		var d := focus.distance_squared_to(center)
		if d < best_d:
			best_d = d
			best_key = key
	for key: String in _cache:
		if not desired.has(key):
			_cache[key].visible = false
	if best_key != "" and _thread == null:
		var t: Vector3 = desired[best_key]
		_building_key = best_key
		_thread = Thread.new()
		_thread.start(_thread_build.bind(best_key, t.x, t.y, t.z))
	_evict()


func _focus() -> Vector2:
	var p := Vector3.ZERO
	var player := get_tree().get_first_node_in_group("player")
	if Toolkit.active:
		p = Toolkit.cam_position()
	elif MapScreen.active:
		p = MapScreen.focus_position()
	elif player:
		p = player.global_position
	return Vector2(p.x, p.z)


## Recursive split: root tiles overlapping the reach square, split
## toward the focus. Leaves land in `out` as key -> (size, ix, iz).
func _collect_leaves(focus: Vector2, out: Dictionary) -> void:
	var r0 := int(floor((focus.x - WORLD_REACH) / ROOT_SIZE))
	var r1 := int(floor((focus.x + WORLD_REACH) / ROOT_SIZE))
	var c0 := int(floor((focus.y - WORLD_REACH) / ROOT_SIZE))
	var c1 := int(floor((focus.y + WORLD_REACH) / ROOT_SIZE))
	for iz in range(c0, c1 + 1):
		for ix in range(r0, r1 + 1):
			_split(focus, ROOT_SIZE, ix, iz, out)


func _split(focus: Vector2, size: float, ix: int, iz: int, out: Dictionary) -> void:
	var rect := Rect2(ix * size, iz * size, size, size)
	# Distance from focus to the tile rect.
	var dx := maxf(maxf(rect.position.x - focus.x, focus.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - focus.y, focus.y - rect.end.y), 0.0)
	var d := sqrt(dx * dx + dz * dz)
	if d > WORLD_REACH:
		return
	if size > MIN_TILE and d < size * SPLIT_K:
		var half := size * 0.5
		_split(focus, half, ix * 2, iz * 2, out)
		_split(focus, half, ix * 2 + 1, iz * 2, out)
		_split(focus, half, ix * 2, iz * 2 + 1, out)
		_split(focus, half, ix * 2 + 1, iz * 2 + 1, out)
		return
	out["%d_%d_%d" % [int(size), ix, iz]] = Vector3(size, ix, iz)


## Heavy sampling on the dedicated thread; kernel when present.
func _thread_build(key: String, size: float, ix: float, iz: float) -> void:
	var ox := ix * size
	var oz := iz * size
	var skirt := 4.0 + size * 0.02
	var mesh: ArrayMesh
	if Terrain.kernel:
		var built: Dictionary = Terrain.kernel.build_far(
			ox, oz, size, TILE_RES, SINK, skirt)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = built.vertices
		arrays[Mesh.ARRAY_NORMAL] = built.normals
		arrays[Mesh.ARRAY_INDEX] = built.indices
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		var step := size / (TILE_RES - 1)
		for tz in TILE_RES:
			for tx in TILE_RES:
				var wx := ox + tx * step
				var wz := oz + tz * step
				st.add_vertex(Vector3(wx, Terrain.height(wx, wz) - SINK, wz))
		for tz in TILE_RES - 1:
			for tx in TILE_RES - 1:
				var i := tz * TILE_RES + tx
				st.add_index(i)
				st.add_index(i + 1)
				st.add_index(i + TILE_RES)
				st.add_index(i + 1)
				st.add_index(i + TILE_RES + 1)
				st.add_index(i + TILE_RES)
		st.generate_normals()
		mesh = st.commit()
	_built_mutex.lock()
	_built.append([key, mesh])
	_built_mutex.unlock()


func _adopt(key: String, mesh: ArrayMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _material:
		mi.material_override = _material
	add_child(mi)
	_cache[key] = mi
	_cache_age[key] = _tick


func _invalidate(world_rect: Rect2) -> void:
	for key: String in _cache.keys():
		var parts := key.split("_")
		var size := float(parts[0])
		var rect := Rect2(float(parts[1]) * size, float(parts[2]) * size, size, size)
		if rect.intersects(world_rect):
			_cache[key].queue_free()
			_cache.erase(key)
			_cache_age.erase(key)


func _evict() -> void:
	if _cache.size() <= CACHE_MAX:
		return
	var keys := _cache.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(_cache_age.get(a, 0)) < int(_cache_age.get(b, 0)))
	for i in _cache.size() - CACHE_MAX:
		var key: String = keys[i]
		if _cache[key].visible:
			continue
		_cache[key].queue_free()
		_cache.erase(key)
		_cache_age.erase(key)
