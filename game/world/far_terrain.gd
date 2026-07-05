extends Node3D
## Far-terrain LOD: a coarse 6.4km mesh sampling the SAME Terrain.height
## function as the streamed cells. Whatever you see on the horizon is the
## real ground — walk toward it and the streamer builds full-resolution
## cells from the same function.
##  - Rebuilds on the worker thread (synchronous recenters hitched).
##  - Tracks sculpt edits (debounced): god-mode terrain work used to
##    leave a stale coarse sheet floating over — or under — the real
##    ground.
##  - Discards its fragments inside the streamed footprint (far_lod flag
##    + stream_center global in terrain.gdshader): 67m sampling smears a
##    sharp sculpt into a broad bulge the 1.5m sink can't hide, and near
##    the focus the real cells are always there to win anyway.

const SIZE := 6400.0
const RES := 96  # vertices per side (~67m sampling)
const RECENTER_DISTANCE := 600.0
const SINK := 1.5  # sits below true height so near cells win at distance
const EDIT_REBUILD_DELAY := 1.2  # settle time after the last brush stroke

var _anchor := Vector2.INF
var _mesh_instance: MeshInstance3D
# Dedicated thread, NOT WorkerThreadPool: a recenter into fresh terrain
# queues ~100 cell builds + navmesh bakes on the shared pool, and the
# horizon rebuild would sit behind all of them — a stale far mesh for
# minutes exactly when the player is covering new ground.
var _thread: Thread
var _built_mutex := Mutex.new()
var _built: Array = []  # meshes finished by the worker
var _edit_pending := false
var _edit_cooldown := 0.0


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		var mat: ShaderMaterial = streamer._ground_material.duplicate()
		mat.set_shader_parameter("far_lod", true)
		_mesh_instance.material_override = mat
	add_child(_mesh_instance)
	Terrain.edited.connect(func(_rect: Rect2) -> void:
		_edit_pending = true
		_edit_cooldown = EDIT_REBUILD_DELAY)


func _process(delta: float) -> void:
	var focus := Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player")
	if GodMode.active:
		var p := GodMode.cam_position()
		focus = Vector2(p.x, p.z)
	elif MapScreen.active:
		var p := MapScreen.focus_position()
		focus = Vector2(p.x, p.z)
	elif player:
		focus = Vector2(player.global_position.x, player.global_position.z)

	if _edit_pending:
		_edit_cooldown -= delta

	var recenter := _anchor == Vector2.INF \
			or focus.distance_to(_anchor) > RECENTER_DISTANCE
	var edits_settled := _edit_pending and _edit_cooldown <= 0.0
	if _thread == null and (recenter or edits_settled):
		if recenter:
			_anchor = focus.snappedf(256.0)
		_edit_pending = false
		_thread = Thread.new()
		_thread.start(_thread_build.bind(_anchor))

	_built_mutex.lock()
	var done := _built.duplicate()
	_built.clear()
	_built_mutex.unlock()
	if not done.is_empty():
		if _thread != null:
			_thread.wait_to_finish()
			_thread = null
		_mesh_instance.mesh = done[done.size() - 1]


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


## Heavy sampling (RES^2 height reads), safe on a worker: only reads
## Terrain and builds resources.
func _thread_build(anchor: Vector2) -> void:
	var step := SIZE / (RES - 1)
	var origin := anchor - Vector2.ONE * SIZE * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for iz in RES:
		for ix in RES:
			var wx := origin.x + ix * step
			var wz := origin.y + iz * step
			st.add_vertex(Vector3(wx, Terrain.height(wx, wz) - SINK, wz))
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
	_built.append(mesh)
	_built_mutex.unlock()
