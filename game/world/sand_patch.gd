extends Node3D
## SandPatch: the dense ground under the player — a 24m disc of terrain
## at 18.75cm vertices (the streamed cells are 0.66m at best) that
## displaces by SandField's 4.7cm deformation map. Footsteps become
## actual heel-and-toe pits with walls and rims, in geometry. The
## terrain shader opens a hole under the patch (patch_center global);
## the patch discards outside the same circle with a small overlap band
## where it sits 2cm proud, so there is never a gap or a z-fight.
## Rebuilt on the worker thread when SandField re-anchors; the old patch
## serves until the new one lands.

const SIZE := 24.0
const RES := 321  # 7.5cm vertex grid: the geometry carries the pit, not paint

var _anchor := Vector2.INF
var _pending_anchor := Vector2.INF
var _task := -1
var _built_mutex := Mutex.new()
var _built: Array = []  # [anchor, ArrayMesh]
var _mi: MeshInstance3D


func _ready() -> void:
	add_to_group(PreviewTerrain.STEPS_ASIDE_GROUP)  # steps aside during preview
	_mi = MeshInstance3D.new()
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		var mat: ShaderMaterial = streamer._ground_material.duplicate()
		mat.set_shader_parameter("sand_patch", true)
		_mi.material_override = mat
	add_child(_mi)


func _exit_tree() -> void:
	# Reap the in-flight build before the node (and the autoloads the task
	# reads — Terrain/its kernel) tears down under it: a quit landing inside
	# the build window otherwise dereferences freed members from the worker
	# ("Cannot call method lock on a null value") — the hydrology catchment
	# lesson, same fix.
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(_delta: float) -> void:
	var want: Vector2 = SandField._anchor
	if want.is_finite() and want != _anchor and _task == -1 and want != _pending_anchor:
		_pending_anchor = want
		_task = WorkerThreadPool.add_task(_thread_build.bind(want))
	_built_mutex.lock()
	var done := _built.duplicate()
	_built.clear()
	_built_mutex.unlock()
	if not done.is_empty():
		if _task != -1:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		var latest: Array = done[done.size() - 1]
		_anchor = latest[0]
		_mi.mesh = latest[1]
		# Kernel-built meshes are corner-origin (build_cell layout);
		# GDScript-built ones are centered. Same world placement.
		_mi.position = Vector3(-SIZE * 0.5, 0.0, -SIZE * 0.5) if latest[2] \
			else Vector3.ZERO
		global_position = Vector3(_anchor.x, 0.0, _anchor.y)
		# The hole in the terrain follows the ground that fills it.
		RenderingServer.global_shader_parameter_set("patch_center", _anchor)


## True local terrain at footprint resolution, built off-thread.
func _thread_build(anchor: Vector2) -> void:
	if Terrain.kernel:
		# Native path: no GDScript sampling on this thread (see
		# Terrain.kernel — this exact loop was the descent crash's
		# final abort site, sand_patch re-anchoring while falling).
		var built: Dictionary = Terrain.kernel.build_cell(
			anchor.x - SIZE * 0.5, anchor.y - SIZE * 0.5, SIZE, RES, false)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = built.vertices
		arrays[Mesh.ARRAY_NORMAL] = built.normals
		arrays[Mesh.ARRAY_TEX_UV] = built.uvs
		arrays[Mesh.ARRAY_INDEX] = built.indices
		var kmesh := ArrayMesh.new()
		kmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_built_mutex.lock()
		_built.append([anchor, kmesh, true])
		_built_mutex.unlock()
		return
	var step := SIZE / (RES - 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for iz in RES:
		for ix in RES:
			var lx := ix * step - SIZE * 0.5
			var lz := iz * step - SIZE * 0.5
			st.set_uv(Vector2(anchor.x + lx, anchor.y + lz) * 0.05)
			st.add_vertex(Vector3(lx, Terrain.height(anchor.x + lx, anchor.y + lz), lz))
	for iz in RES - 1:
		for ix in RES - 1:
			var i := iz * RES + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + RES)
			st.add_index(i + 1)
			st.add_index(i + RES + 1)
			st.add_index(i + RES)
	st.generate_normals()
	var mesh := st.commit()
	_built_mutex.lock()
	_built.append([anchor, mesh, false])
	_built_mutex.unlock()
