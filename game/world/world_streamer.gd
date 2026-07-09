extends Node3D
## Streams world cells around the player. The world is a grid of
## CELL_SIZE-meter cells: a flat terrain tile is generated for every cell
## (placeholder until heightmap terrain), and authored content scenes
## (game/world/cells/cell_X_Y.tscn, coordinates in the filename) are
## thread-loaded on top as the player approaches.

const CELL_SIZE := 128.0
const CELLS_DIR := "res://game/world/cells"
const TERRAIN_RES := 49  # vertices per cell side (~2.7m grid; gen is threaded)
# Deformation ring: cells around the focus rebuild at ~0.66m vertex grid
# so footsteps and trails press REAL geometry (the RDR2-snow read needs
# vertices where the feet are). Nav faces and far cells stay coarse.
const NEAR_RES := 193
const NEAR_RING := 1  # Chebyshev radius of dense cells around the focus
# Velocity LOOKAHEAD (2026-07-05, the Toolkit-cam pop-in): the load ring is
# centered not on the focus but on where it will be in LEAD_SECONDS, so
# cells finish before you reach them instead of popping over the far
# LOD at the ring edge. On-foot speeds (<LEAD_MIN_SPEED) get no lead —
# walking is unchanged; only fast flight leads. Same cell count: the
# ring shifts, it doesn't grow.
const LEAD_SECONDS := 5.0
const LEAD_MAX_CELLS := 3
const LEAD_MIN_SPEED := 8.0  # m/s below which no lead (walking)

var load_radius := 2  # Chebyshev radius of cells kept loaded (map widens this)
var _prev_focus := Vector2.INF
var _focus_vel := Vector2.ZERO
var _load_center := Vector2i.ZERO  # lead-biased ring center (see _lead)
var _focus_cell := Vector2i.ZERO   # the true focus cell (union anchor)

var _authored: Dictionary = {}  # Vector2i -> scene path
var _terrain: Dictionary = {}  # Vector2i -> terrain node
var _content: Dictionary = {}  # Vector2i -> instanced authored scene
var _records: Dictionary = {}  # Vector2i -> container of placed-record objects
var _pending: Dictionary = {}  # Vector2i -> path in threaded load
var _terrain_pending: Dictionary = {}  # Vector2i -> WorkerThreadPool task id
var _terrain_results: Array = []  # [cell, mesh, shape, navmesh, res] off-thread
var _terrain_res: Dictionary = {}  # Vector2i -> vertex res the cell was built at
var _results_mutex := Mutex.new()

# Flora comes from species records (data/flora/*.json via FloraLife):
# biome-weighted composition, stage art chosen at cell build, density
# breathing with FloraLife.vitality_at. Billboard meshes are cached per
# species×stage.
const COVER_VISIBLE_RANGE := 75.0
const FORAGE_CANDIDATES := 3  # deterministic gather-spot slots per cell

var _ground_material: ShaderMaterial
var _sway: Shader
var _fabric: Shader  # fabric_wind (PLAN_FABRIC F1): wind-driven world cloth
var _fabric_mats: Dictionary = {}  # slot -> ShaderMaterial (shared; phase is per-instance)
var _fabric_dressed := 0  # instances wearing the wind this session (Toolkit FABRIC line)
var _species_meshes: Dictionary = {}  # "id/stage" -> QuadMesh
var _scatter_groups: Array = []  # model-scatter rules (data/scatter/props.json)
var _cat_slots: Dictionary = {}  # category -> Array[slot id] (from Cards)
var _decal_groups: Array = []  # ground-decal rules (data/scatter/decals.json)
var _water_groups: Array = []  # aquatic-plant rules (data/scatter/water_plants.json)
var _water_meshes: Dictionary = {}  # slot -> Mesh (billboard or flat pad)

@onready var _player: Node3D = get_tree().get_first_node_in_group("player")


var _dirty: Dictionary = {}
var _rebuild_cooldown := 0.0
# Sculpt-feedback split: while the brush is active only the VISUAL mesh
# rebuilds (cheap, instant — the clay must move under the cursor); the
# expensive cell rebuild — trimesh collision, flora scatter, ground
# cover, navmesh, node churn — runs once through the normal threaded
# pipeline after the brush goes quiet. The old collision/scatter/navmesh
# serve in the interim; nobody notices them lagging a second.
var _mesh_instances: Dictionary = {}  # Vector2i -> the cell's MeshInstance3D
var _stale: Dictionary = {}  # sculpted cells awaiting their full rebuild
var _quiet_cooldown := 0.0
var _visual_pending: Dictionary = {}  # cell -> worker task (mesh-only rebuild)
var _visual_results: Array = []  # [cell, mesh] guarded by _results_mutex


func _ready() -> void:
	add_to_group("world_streamer")
	add_to_group(PreviewTerrain.STEPS_ASIDE_GROUP)  # cells hide while a preview grid is worn
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

	# Model scatter: category rules + a category->slots index from the Cards
	# catalog, so every placeable slot auto-dresses the world by biome.
	var cfg = Records.load_json("res://data/scatter/props.json")
	if cfg is Dictionary and cfg.get("groups") is Array:
		_scatter_groups = cfg["groups"]
	var dcfg = Records.load_json("res://data/scatter/decals.json")
	if dcfg is Dictionary and dcfg.get("groups") is Array:
		_decal_groups = dcfg["groups"]
	var wcfg = Records.load_json("res://data/scatter/water_plants.json")
	if wcfg is Dictionary and wcfg.get("groups") is Array:
		_water_groups = wcfg["groups"]
	for e in Cards.placeable():
		var cat: String = e["category"]
		if not _cat_slots.has(cat):
			_cat_slots[cat] = []
		_cat_slots[cat].append(e["slot"])

	# Billboard meshes (sway shader) are built lazily per species×stage.
	_sway = load("res://game/shaders/flora_sway.gdshader")
	# Fabric materials are built lazily per wind-flagged slot (Cards "wind").
	_fabric = load("res://game/shaders/fabric_wind.gdshader")
	# A healed flora cell rebuilds so its cover and gather spots return;
	# wounded cells keep their gaps (the freed spot IS the change).
	FloraLife.cell_changed.connect(_on_flora_cell_changed)

	# Synchronous first fill: the ground must exist before the first physics frame.
	_update_cells(true)


func _process(delta: float) -> void:
	# Focus velocity (smoothed) drives the load lookahead below.
	var fp := _focus_position()
	var fxz := Vector2(fp.x, fp.z)
	if _prev_focus.is_finite() and delta > 0.0:
		_focus_vel = _focus_vel.lerp((fxz - _prev_focus) / delta, 0.35)
	_prev_focus = fxz
	_update_cells(false)
	_poll_pending()
	_drain_terrain_results()
	_rebuild_cooldown -= delta
	if not _dirty.is_empty() and _rebuild_cooldown <= 0.0:
		_rebuild_cooldown = 0.066  # workers carry it; feedback stays snappy
		for c in _dirty.keys():
			if _mesh_instances.has(c) and not _visual_pending.has(c):
				# Visual mesh only, built off-thread: the brush needs to
				# see the clay move, the main thread needs to do nothing.
				_visual_pending[c] = WorkerThreadPool.add_task(
					_thread_visual_mesh.bind(c, _terrain_res.get(c, TERRAIN_RES)))
				_stale[c] = true
		_dirty.clear()
		_quiet_cooldown = 0.8
	_drain_visual_results()
	_quiet_cooldown -= delta
	if _dirty.is_empty() and _quiet_cooldown <= 0.0 and not _stale.is_empty():
		for c in _stale.keys():
			if _terrain.has(c) and not _terrain_pending.has(c):
				# Full rebuild off-thread; _drain_terrain_results swaps the
				# cell (collision, scatter, cover, navmesh) when it lands.
				_terrain_pending[c] = WorkerThreadPool.add_task(
					_thread_build_terrain.bind(c, _terrain_res.get(c, TERRAIN_RES)))


func _exit_tree() -> void:
	# WorkerThreadPool ids must be waited on before the pool tears down.
	# In-flight _thread_build_terrain/_thread_visual_mesh tasks touch
	# _results_mutex, which dies with this node (the exit lock-on-null).
	for c in _terrain_pending:
		WorkerThreadPool.wait_for_task_completion(_terrain_pending[c])
	_terrain_pending.clear()
	for c in _visual_pending:
		WorkerThreadPool.wait_for_task_completion(_visual_pending[c])
	_visual_pending.clear()


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
	# Streaming follows the Toolkit camera or map focus when either is active.
	var p := _player.global_position
	# An open, streaming map drives the view even in the Toolkit (so
	# panning the map builds cells where you look, not at the fly cam).
	if MapScreen.active and MapScreen.wants_streaming():
		p = MapScreen.focus_position()
	elif Toolkit.active:
		p = Toolkit.cam_position()
	return p


func _player_cell() -> Vector2i:
	var p := _focus_position()
	return Vector2i(roundi(p.x / CELL_SIZE), roundi(p.z / CELL_SIZE))


## How many cells ahead to shift the load ring, from the focus velocity.
## Zero at walking speed (integer rounding also gives hysteresis, so the
## ring doesn't thrash cells at the threshold). Capped so a sprint can't
## outrun the finish budget by demanding a huge burst at once.
func _lead() -> Vector2i:
	if _focus_vel.length() < LEAD_MIN_SPEED:
		return Vector2i.ZERO
	var cells := _focus_vel * LEAD_SECONDS / CELL_SIZE
	return Vector2i(
		clampi(roundi(cells.x), -LEAD_MAX_CELLS, LEAD_MAX_CELLS),
		clampi(roundi(cells.y), -LEAD_MAX_CELLS, LEAD_MAX_CELLS))


func _update_cells(sync: bool) -> void:
	var fp := _focus_position()
	var center := _player_cell()
	# The load ring leads the focus; density (res_for) stays keyed on the
	# true focus so the cell under you is always dense.
	var lead := _lead()
	var lcenter := center + lead
	_focus_cell = center
	_load_center = lcenter
	# The far LOD's discard zone stays on the ACTUAL focus (not the lead):
	# full cells always cover under/around you (the union below), so the
	# discard must too, or the far LOD double-draws where you stand. (The
	# lead only ADDS cells ahead; it never drops the ones beneath you —
	# shifting the whole ring forward was the disappearing-terrain bug.)
	RenderingServer.global_shader_parameter_set("stream_center",
		Vector2(fp.x, fp.z))
	# Load the UNION of a ring around the focus and a ring around the lead
	# point: under-you is always covered, lookahead extends toward travel.
	var lo := Vector2i(mini(center.x, lcenter.x), mini(center.y, lcenter.y)) \
		- Vector2i(load_radius, load_radius)
	var hi := Vector2i(maxi(center.x, lcenter.x), maxi(center.y, lcenter.y)) \
		+ Vector2i(load_radius, load_radius)
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cy)
			if _chebyshev(c - center) > load_radius \
					and _chebyshev(c - lcenter) > load_radius:
				continue  # outside both rings — not in the load zone
			if not _terrain.has(c) and not _terrain_pending.has(c):
				if sync:
					_add_terrain_sync(c)
				else:
					_terrain_pending[c] = WorkerThreadPool.add_task(
						_thread_build_terrain.bind(c, _res_for(c, center)))
			elif _terrain.has(c) and not _terrain_pending.has(c) \
					and _terrain_res.get(c, TERRAIN_RES) != _res_for(c, center):
				# Deformation ring moved: promote/demote through the same
				# stale-swap pipeline (built off-thread, swapped when ready).
				_stale[c] = true
				_terrain_pending[c] = WorkerThreadPool.add_task(
					_thread_build_terrain.bind(c, _res_for(c, center)))
			if not _records.has(c) and not CellRecords.records(c).is_empty():
				_add_records(c)
			if _authored.has(c) and not _content.has(c) and not _pending.has(c):
				if sync:
					_add_content(c, load(_authored[c]))
				else:
					ResourceLoader.load_threaded_request(_authored[c])
					_pending[c] = _authored[c]
	# Unload only cells outside BOTH rings (a small hysteresis past the
	# load zone), so nothing under or just-behind you frees mid-flight.
	var unload_radius := load_radius + 1
	for c in _terrain.keys():
		if _chebyshev(c - center) > unload_radius \
				and _chebyshev(c - lcenter) > unload_radius:
			_terrain[c].queue_free()
			_terrain.erase(c)
			_mesh_instances.erase(c)
			_stale.erase(c)
			_terrain_res.erase(c)
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
## reads Terrain + creates resources. res sets the visual vertex grid
## (dense in the deformation ring, coarse beyond); nav faces are strided
## back to ~2.7m at any res, minus anything submerged — pathing never
## pays for footprint fidelity and nobody paths through the pond.
func _build_terrain_mesh(c: Vector2i, with_nav := true, with_shape := true,
		res := TERRAIN_RES) -> Array:
	var origin := Vector3(
		c.x * CELL_SIZE - CELL_SIZE * 0.5, 0.0, c.y * CELL_SIZE - CELL_SIZE * 0.5
	)
	var step := CELL_SIZE / (res - 1)
	var pts := PackedVector3Array()
	var wet := PackedByteArray()
	var indices := PackedInt32Array()
	var mesh: ArrayMesh
	if Terrain.kernel:
		# Native path: the whole vertex/normal/index build runs in C++ —
		# worker threads execute (almost) no GDScript (the descent-crash
		# fix; see Terrain.kernel).
		var built: Dictionary = Terrain.kernel.build_cell(
			origin.x, origin.z, CELL_SIZE, res, with_nav)
		pts = built.vertices
		wet = built.wet
		indices = built.indices
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = built.vertices
		arrays[Mesh.ARRAY_NORMAL] = built.normals
		arrays[Mesh.ARRAY_TEX_UV] = built.uvs
		arrays[Mesh.ARRAY_INDEX] = built.indices
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _ground_material)
	else:
		pts.resize(res * res)
		wet.resize(res * res)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(_ground_material)
		st.set_smooth_group(0)
		for iz in res:
			for ix in res:
				var wx := origin.x + ix * step
				var wz := origin.z + iz * step
				var y := Terrain.height(wx, wz)
				var i := iz * res + ix
				pts[i] = Vector3(ix * step, y, iz * step)
				if with_nav:
					wet[i] = 1 if y < Terrain.water_surface_base(wx, wz) - 0.05 else 0
				st.set_uv(Vector2(wx, wz) * 0.05)
				st.add_vertex(pts[i])
		indices.resize((res - 1) * (res - 1) * 6)
		var w := 0
		for iz in res - 1:
			for ix in res - 1:
				var i := iz * res + ix
				indices[w] = i
				indices[w + 1] = i + 1
				indices[w + 2] = i + res
				indices[w + 3] = i + 1
				indices[w + 4] = i + res + 1
				indices[w + 5] = i + res
				w += 6
		for i in indices:
			st.add_index(i)
		st.generate_normals()
		mesh = st.commit()
	var faces := PackedVector3Array()
	if with_nav:
		var stride := maxi(1, (res - 1) / (TERRAIN_RES - 1))
		var quads := (res - 1) / stride
		for iz in quads:
			for ix in quads:
				var a := (iz * stride) * res + ix * stride
				var b := a + stride
				var d := a + stride * res
				var e := d + stride
				if wet[a] == 0 and wet[b] == 0 and wet[d] == 0:
					faces.append(pts[a])
					faces.append(pts[b])
					faces.append(pts[d])
				if wet[b] == 0 and wet[e] == 0 and wet[d] == 0:
					faces.append(pts[b])
					faces.append(pts[e])
					faces.append(pts[d])
	var navmesh: NavigationMesh = Nav.bake_navmesh(faces) if with_nav else null
	var shape: Shape3D = _trimesh_shape(pts, indices) if with_shape else null
	return [mesh, shape, navmesh]


## Collision trimesh built straight from the vertex/index arrays already in
## hand — NEVER mesh.create_trimesh_shape() on a worker thread: that
## re-fetches the arrays through RenderingServer.mesh_surface_get_arrays, a
## cross-thread push_and_ret that parks the worker until the MAIN thread
## flushes the RS command queue. A zoom-in burst parks enough builders to
## fill the pool's low-priority lane; if the main thread then hard-waits on
## any queued low-priority task before the frame's RS sync (the 2026-07-08
## map-zoom freeze: freeing a streamed-out material waits on its starved
## pipeline-compile task), the whole engine deadlocks. Same faces, no RS.
## Regression: tests/stream_deadlock_probe.tscn.
static func _trimesh_shape(vertices: PackedVector3Array,
		indices: PackedInt32Array) -> ConcavePolygonShape3D:
	if indices.is_empty():
		return null
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = vertices[indices[i]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


func _thread_build_terrain(c: Vector2i, res: int) -> void:
	var built := _build_terrain_mesh(c, true, true, res)
	_results_mutex.lock()
	_terrain_results.append([c, built[0], built[1], built[2], res])
	_results_mutex.unlock()


## The vertex resolution a cell wants: dense inside the deformation ring,
## coarse beyond.
func _res_for(c: Vector2i, center: Vector2i) -> int:
	return NEAR_RES if _chebyshev(c - center) <= NEAR_RING else TERRAIN_RES


# Finishing a cell on the main thread costs real milliseconds (scatter
# nodes, cover MultiMesh upload, the physics body entering the space —
# Jolt builds its BVH there, not when the Shape3D was made — and the
# nav region add). A fast Toolkit-cam flight completes cells in BURSTS, and
# finishing a burst in one frame was the flight stutter (2026-07-05).
# So: drain into a queue, spend at most FINISH_BUDGET_MS per frame.
const FINISH_BUDGET_MS := 4.0
var _finish_queue: Array = []


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
		_finish_queue.append(r)
	var t0 := Time.get_ticks_usec()
	while not _finish_queue.is_empty():
		var r: Array = _finish_queue.pop_front()
		var c: Vector2i = r[0]
		if _terrain.has(c):
			if not _stale.has(c):
				continue  # raced a normal load; the live cell wins
			# Sculpt-stale swap: the fresh full rebuild replaces the old cell.
			_terrain[c].queue_free()
			_terrain.erase(c)
			_mesh_instances.erase(c)
			_stale.erase(c)
		if _chebyshev(c - _focus_cell) > load_radius + 1 \
				and _chebyshev(c - _load_center) > load_radius + 1:
			continue  # streamed past it while building; let it lapse
		_finish_terrain(c, r[1], r[2], r[3], r[4])
		# Always land at least one; stop when the frame's budget is spent.
		if (Time.get_ticks_usec() - t0) / 1000.0 > FINISH_BUDGET_MS:
			break


func _add_terrain_sync(c: Vector2i) -> void:
	var res := _res_for(c, _player_cell())
	var built := _build_terrain_mesh(c, true, true, res)
	_finish_terrain(c, built[0], built[1], built[2], res)


## Mesh-only rebuild for live sculpt feedback, off the main thread.
func _thread_visual_mesh(c: Vector2i, res: int) -> void:
	var built := _build_terrain_mesh(c, false, false, res)
	_results_mutex.lock()
	_visual_results.append([c, built[0]])
	_results_mutex.unlock()


func _drain_visual_results() -> void:
	_results_mutex.lock()
	var results := _visual_results.duplicate()
	_visual_results.clear()
	_results_mutex.unlock()
	for r in results:
		var c: Vector2i = r[0]
		if _visual_pending.has(c):
			WorkerThreadPool.wait_for_task_completion(_visual_pending[c])
			_visual_pending.erase(c)
		if _mesh_instances.has(c) and is_instance_valid(_mesh_instances[c]):
			_mesh_instances[c].mesh = r[1]


func _finish_terrain(c: Vector2i, mesh: ArrayMesh, shape: Shape3D,
		navmesh: NavigationMesh, res := TERRAIN_RES) -> void:
	_terrain_res[c] = res
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
	_mesh_instances[c] = mi
	body.position = origin
	_add_scatter(c, body, origin)
	_add_model_scatter(c, body, origin)
	_add_decal_scatter(c, body, origin)
	_add_water_plants(c, body, origin)
	_add_ground_cover(c, body, origin,
			Terrain.valley_factor(origin.x + CELL_SIZE * 0.5, origin.z + CELL_SIZE * 0.5))
	add_child(body)
	_terrain[c] = body
	if navmesh != null:
		Nav.add_cell(c, navmesh, origin)  # deferred rebakes keep the old region


func _add_scatter(c: Vector2i, parent: Node3D, origin: Vector3) -> void:
	# Deterministic flora scatter: same cell -> same candidate positions,
	# forever. WHAT grows there is the living part: species weighted by
	# the biome under each candidate (composition) and by local ground
	# moisture (drought thins the thirsty first), density breathing with
	# FloraLife.vitality_at, stage art picked from season + vitality at
	# build. Draw order is fixed and independent of world state, so the
	# same cell lands the same layout whatever the weather.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var defs: Array[Dictionary] = FloraLife.species
	var buckets: Dictionary = {}  # "species_idx/stage" -> Array[Transform3D]
	var colliders: Array = []  # [def, transform] for trunked flora
	# Dense on the valley floor, sparse on the plateau.
	var cell_center := Vector2(origin.x + CELL_SIZE * 0.5, origin.z + CELL_SIZE * 0.5)
	var vf: float = Terrain.valley_factor(cell_center.x, cell_center.y)
	# Biome density (Stage B): a desert cell scatters almost nothing, an
	# oasis cell teems. 1.0 where no biome map (valley keeps its feel).
	var biome_mult: float = Terrain.biome_density(cell_center.x, cell_center.y)
	var vit: float = FloraLife.vitality_at(cell_center.x, cell_center.y)
	var stage: String = FloraLife.stage_for(GameClock.season, vit)
	var base_count := int(round(lerpf(34.0, 8.0, vf) * biome_mult
			* lerpf(0.55, 1.15, vit)))
	for i in rng.randi_range(base_count, base_count + 8):
		var lx := rng.randf() * CELL_SIZE
		var lz := rng.randf() * CELL_SIZE
		var roll := rng.randf()
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
		var y := Terrain.height(wx, wz)
		if y < Terrain.water_surface_base(wx, wz) + 0.3:  # nothing grows midstream
			continue
		var idx := _pick_species(defs, false, wx, wz, roll)
		if idx < 0:
			continue
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)),
				Vector3(lx, y, lz))
		var key := "%d/%s" % [idx, stage]
		if not buckets.has(key):
			buckets[key] = [] as Array[Transform3D]
		buckets[key].append(xf)
		if defs[idx].get("collider", false):
			colliders.append([defs[idx], xf])
	for key: String in buckets:
		var idx := int((key as String).get_slice("/", 0))
		_bucket_to_multimesh(buckets[key],
				_species_mesh(defs[idx], (key as String).get_slice("/", 1)),
				parent, -1.0)
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = 5  # world (1) + obstacle (4) for NPC avoidance
		for entry in colliders:
			var s: float = (entry[1] as Transform3D).basis.get_scale().x
			var shape := CylinderShape3D.new()
			shape.radius = float((entry[0] as Dictionary).get("trunk_radius", 0.4)) * s
			shape.height = 4.0 * s
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position = (entry[1] as Transform3D).origin + Vector3(0.0, 2.0 * s, 0.0)
			body.add_child(col)
		parent.add_child(body)
	_add_forage(c, parent, origin, stage)


## Biome-and-moisture-weighted species pick among large flora or cover.
## -1 when nothing wants to grow here.
func _pick_species(defs: Array[Dictionary], cover: bool,
		wx: float, wz: float, roll: float) -> int:
	var biome_idx: int = Terrain.biome_at(wx, wz)
	var biome_id := ""
	if biome_idx >= 0 and biome_idx < Terrain.biomes.size():
		biome_id = str(Terrain.biomes[biome_idx].id)
	var moist: float = Climate.moisture(wx, wz)
	var weights: Array[float] = []
	var total := 0.0
	for def in defs:
		var w := 0.0
		if bool(def.get("cover", false)) == cover:
			w = FloraLife.species_weight(def, biome_id, moist)
		weights.append(w)
		total += w
	if total <= 0.0:
		return -1
	var acc := 0.0
	for v in defs.size():
		acc += weights[v]
		if roll * total <= acc:
			return v
	return defs.size() - 1


func _bucket_to_multimesh(transforms: Array, mesh: QuadMesh,
		parent: Node3D, visible_range: float) -> void:
	if transforms.is_empty() or mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if visible_range > 0.0:
		mmi.visibility_range_end = visible_range
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## Gather spots: species with a `yields` item plant a few interactable
## billboards at deterministic slots; the cell's depletion decides how
## many are up right now. Regrowth restores them via the healed-cell
## rebuild — never a reset.
func _add_forage(c: Vector2i, parent: Node3D, origin: Vector3, stage: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) * 13 + 5
	var shown := FORAGE_CANDIDATES - clampi(
			roundi(FloraLife.depletion(c) * FORAGE_CANDIDATES),
			0, FORAGE_CANDIDATES)
	for def: Dictionary in FloraLife.species:
		var item := str(def.get("yields", ""))
		if item.is_empty():
			continue
		for i in FORAGE_CANDIDATES:
			var lx := rng.randf() * CELL_SIZE
			var lz := rng.randf() * CELL_SIZE
			var yaw := rng.randf() * TAU
			if i >= shown:
				continue
			var wx := origin.x + lx
			var wz := origin.z + lz
			var moist: float = Climate.moisture(wx, wz)
			var biome_idx: int = Terrain.biome_at(wx, wz)
			var biome_id := ""
			if biome_idx >= 0 and biome_idx < Terrain.biomes.size():
				biome_id = str(Terrain.biomes[biome_idx].id)
			if FloraLife.species_weight(def, biome_id, moist) < 0.05:
				continue
			var blocked := false
			for f in Terrain.FLATTENS:
				if Vector2(wx - f[0], wz - f[1]).length() < f[2] * 0.8:
					blocked = true
					break
			if blocked:
				continue
			var y := Terrain.height(wx, wz)
			if y < Terrain.water_surface_base(wx, wz) + 0.15:
				continue
			var spot := ForageSpot.new()
			spot.item_id = item
			spot.position = Vector3(lx, y, lz)
			spot.rotation.y = yaw
			var vis := MeshInstance3D.new()
			vis.mesh = _species_mesh(def, stage)
			spot.add_child(vis)
			parent.add_child(spot)


func _on_flora_cell_changed(c: Vector2i) -> void:
	# Rebuild only when the wound has fully healed: while gathered-out,
	# the freed spots ARE the visible state; on heal the spots and the
	# thinned cover come back through the normal quiet-rebuild pipeline.
	if FloraLife.depletion(c) == 0.0 and _terrain.has(c):
		_stale[c] = true


## Deterministic per-cell model scatter: GLB props auto-dressing the world by
## biome, the flora recipe for the 345 meshes. Same cell -> same layout,
## forever; presentation only (rebuilt from the cell hash at stream time, never
## saved, never fingerprinted). Each group draws every non-gated slot in its
## category, so new cards join with no code change. RNG draws are in a fixed
## order per candidate so acceptance never shifts the layout.
func _add_model_scatter(c: Vector2i, parent: Node3D, origin: Vector3) -> void:
	if _scatter_groups.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) * 47 + 3
	var cc := Vector2(origin.x + CELL_SIZE * 0.5, origin.z + CELL_SIZE * 0.5)
	var biome_mult: float = 0.4 + 0.6 * Terrain.biome_density(cc.x, cc.y)
	for group: Dictionary in _scatter_groups:
		var slots: Array = _cat_slots.get(group.get("category", ""), [])
		if slots.is_empty():
			continue
		var biomes: Dictionary = group.get("biomes", {})
		var srange: Array = group.get("scale", [0.8, 1.2])
		for i in int(group.get("attempts", 4)):
			var lx := rng.randf() * CELL_SIZE
			var lz := rng.randf() * CELL_SIZE
			var pick := rng.randf()
			var accept := rng.randf()
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(float(srange[0]), float(srange[1]))
			var wx := origin.x + lx
			var wz := origin.z + lz
			var bidx: int = Terrain.biome_at(wx, wz)
			var bid := ""
			if bidx >= 0 and bidx < Terrain.biomes.size():
				bid = str(Terrain.biomes[bidx].id)
			if accept > float(biomes.get(bid, 0.0)) * biome_mult:
				continue
			var clear := false
			for f in Terrain.FLATTENS:
				if Vector2(wx - f[0], wz - f[1]).length() < f[2] + f[3]:
					clear = true
					break
			if clear:
				continue
			var y := Terrain.height(wx, wz)
			if y < Terrain.water_surface_base(wx, wz) + 0.2:  # nothing on the water
				continue
			var slot: String = slots[int(pick * slots.size()) % slots.size()]
			var file: String = Cards.resolve(slot, Cards.variant_for(slot, Vector3(wx, 0.0, wz)))
			var scene: PackedScene = Kit.scene_for(file)
			if scene == null:
				continue
			var inst: Node3D = scene.instantiate()
			_dress_placeable(inst, file)
			inst.position = Vector3(lx, y, lz)
			inst.rotation.y = yaw
			inst.scale = Vector3.ONE * s
			parent.add_child(inst)


## Aquatic plants placed at the authored water surface: floating pads on the
## water, emergent reeds rooted in the shallows. Only cells overlapping a water
## body grow anything (water_surface_base gates the rest out fast). Deterministic
## per cell, presentation only.
func _add_water_plants(c: Vector2i, parent: Node3D, origin: Vector3) -> void:
	if _water_groups.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) * 61 + 17
	for group: Dictionary in _water_groups:
		var mode: String = group.get("mode", "emergent")
		var depth: Array = group.get("depth", [-0.2, 1.0])
		var dmin := float(depth[0])
		var dmax := float(depth[1])
		var xfs: Array[Transform3D] = []
		for i in int(group.get("attempts", 6)):
			var lx := rng.randf() * CELL_SIZE
			var lz := rng.randf() * CELL_SIZE
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(0.8, 1.25)
			var wx := origin.x + lx
			var wz := origin.z + lz
			var wsb := Terrain.water_surface_base(wx, wz)
			if wsb < -1.0e5:  # no water body here
				continue
			var y := Terrain.height(wx, wz)
			var d := wsb - y
			if d < dmin or d > dmax:
				continue
			if mode == "float":
				# A flat pad lying on the surface, spun around Y.
				var b := Basis(Vector3(0, 1, 0), yaw) \
						* Basis(Vector3(1, 0, 0), -PI * 0.5).scaled(Vector3(s, s, s))
				xfs.append(Transform3D(b, Vector3(lx, wsb, lz)))
			else:
				xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)),
						Vector3(lx, y, lz)))
		if not xfs.is_empty():
			_bucket_to_multimesh(xfs, _water_mesh(group), parent, -1.0)


## Billboard (emergent) or flat pad (float) mesh for a water-plant slot, cached.
func _water_mesh(group: Dictionary) -> Mesh:
	var slot: String = group.get("slot", "")
	if _water_meshes.has(slot):
		return _water_meshes[slot]
	var path: String = Cards.resolve(slot, 0)
	var h := float(group.get("height", 1.0))
	var mesh: Mesh
	if group.get("mode", "emergent") == "float":
		var tex: Texture2D = load(path)
		var quad := QuadMesh.new()
		quad.size = Vector2(h, h)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # seen from above and below
		mat.vertex_color_use_as_albedo = true
		quad.material = mat
		mesh = quad
	else:
		mesh = _make_billboard_mesh(path, h, _sway, false)
	_water_meshes[slot] = mesh
	return mesh


## Deterministic per-cell ground decals projected onto the terrain, biome-keyed
## (data/scatter/decals.json). Same recipe as the model scatter; presentation
## only. Distance-faded so far cells cost little.
func _add_decal_scatter(c: Vector2i, parent: Node3D, origin: Vector3) -> void:
	if _decal_groups.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) * 53 + 9
	var cc := Vector2(origin.x + CELL_SIZE * 0.5, origin.z + CELL_SIZE * 0.5)
	var biome_mult: float = 0.4 + 0.6 * Terrain.biome_density(cc.x, cc.y)
	for group: Dictionary in _decal_groups:
		var slot: String = group.get("slot", "")
		var tex: Texture2D = load(Cards.resolve(slot,
				Cards.variant_for(slot, Vector3(cc.x, 0.0, cc.y))))
		if tex == null:
			continue
		var biomes: Dictionary = group.get("biomes", {})
		var size: Array = group.get("size", [3, 2, 3])
		for i in int(group.get("attempts", 2)):
			var lx := rng.randf() * CELL_SIZE
			var lz := rng.randf() * CELL_SIZE
			var accept := rng.randf()
			var yaw := rng.randf() * TAU
			var scl := rng.randf_range(0.75, 1.4)
			var wx := origin.x + lx
			var wz := origin.z + lz
			var bidx: int = Terrain.biome_at(wx, wz)
			var bid := ""
			if bidx >= 0 and bidx < Terrain.biomes.size():
				bid = str(Terrain.biomes[bidx].id)
			if accept > float(biomes.get(bid, 0.0)) * biome_mult:
				continue
			var y := Terrain.height(wx, wz)
			if y < Terrain.water_surface_base(wx, wz) + 0.1:
				continue
			var decal := Decal.new()
			decal.texture_albedo = tex
			decal.size = Vector3(float(size[0]) * scl, float(size[1]), float(size[2]) * scl)
			decal.position = Vector3(lx, y, lz)
			decal.rotation.y = yaw
			decal.distance_fade_enabled = true
			decal.distance_fade_begin = 55.0
			decal.distance_fade_length = 18.0
			parent.add_child(decal)


## Make a synth-placeholder GLB read right in-engine. The generator bakes
## color into VERTEX colors with no PBR material, so Godot's default material
## renders it grey — flip vertex_color_use_as_albedo on. And the collision hull
## ships as a visible `-col` mesh (a translucent grey blob over the real mesh);
## hide it, keeping its StaticBody. Materials are shared sub-resources, so the
## flag flips once per GLB and later instances short-circuit.
## `kit_ref` is the resolved res:// file the placement stored (or "" for
## legacy kit scenes): slots whose card says "wind": "fabric" trade the
## flat placeholder material for the fabric_wind override here — the Kit
## applies the wind at placement, per PLAN_FABRIC F1. Presentation only.
func _dress_placeable(root: Node, kit_ref := "") -> void:
	var fabric := _fabric_material(kit_ref)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name.ends_with("-col"):
			mi.visible = false
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		if fabric != null:
			mi.material_override = fabric
			_fabric_dressed += 1
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat is StandardMaterial3D and not mat.vertex_color_use_as_albedo:
				mat.vertex_color_use_as_albedo = true


## The shared fabric_wind material for a wind-flagged slot (null when the
## file's card doesn't wear it). One material per slot: hang length comes
## from the card, per-instance phase from world position in the shader.
func _fabric_material(kit_ref: String) -> ShaderMaterial:
	if kit_ref == "":
		return null
	var e := Cards.entry_for_file(kit_ref)
	if e.is_empty() or e["wind"] != "fabric":
		return null
	var slot: String = e["slot"]
	if not _fabric_mats.has(slot):
		var mat := ShaderMaterial.new()
		mat.shader = _fabric
		mat.set_shader_parameter("hang", e["wind_hang"])
		_fabric_mats[slot] = mat
	return _fabric_mats[slot]


## Toolkit FABRIC line: the wind-fabric ledger — flagged slots, dressed
## instances (this session), and the wind echo the shader is reading.
func fabric_summary() -> String:
	return "%d slots flagged · %d dressed · %d mats · wind=%.2f dir=(%.2f, %.2f)" % [
		Cards.fabric_slots().size(), _fabric_dressed, _fabric_mats.size(),
		Weather.wind, Weather.wind_dir.x, Weather.wind_dir.y]


func _add_records(c: Vector2i) -> void:
	var container := Node3D.new()
	for rec in CellRecords.records(c):
		var scene: PackedScene = Kit.scene_for(rec.kit)
		if scene == null:
			continue
		var node: Node3D = scene.instantiate()
		_dress_placeable(node, rec.kit)
		container.add_child(node)
		# Seat on the CURRENT ground (ground_dy re-seats across terrain
		# regeneration — the Chronicle owns the rule, see CellRecords.seat_y).
		node.position = Vector3(rec.x, CellRecords.seat_y(rec), rec.z)
		node.rotation.y = rec.yaw
		node.scale = Vector3.ONE * rec.get("scale", 1.0)
		# The Threshold (PLAN_INTERIORS): a record wearing a `door` key is
		# still an ordinary placement — the key grows the Interactable.
		if rec.has("door"):
			Interiors.attach_door(node, rec)
	add_child(container)
	_records[c] = container


func _on_records_changed(c: Vector2i) -> void:
	if _records.has(c):
		_records[c].queue_free()
		_records.erase(c)
	if _terrain.has(c) and not CellRecords.records(c).is_empty():
		_add_records(c)


func _make_billboard_mesh(path: String, h: float, sway: Shader,
		is_cover := false) -> QuadMesh:
	var tex: Texture2D = load(path)
	var mat := ShaderMaterial.new()
	mat.shader = sway
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("ground_cover", is_cover)
	var w: float = h * float(tex.get_width()) / float(tex.get_height())
	var mesh := QuadMesh.new()
	mesh.size = Vector2(w, h)
	mesh.center_offset = Vector3(0, h * 0.5, 0)
	mesh.material = mat
	return mesh


func _add_ground_cover(c: Vector2i, parent: Node3D, origin: Vector3, vf: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) * 31 + 7
	var defs: Array[Dictionary] = FloraLife.species
	var cell_center := Vector2(origin.x + CELL_SIZE * 0.5, origin.z + CELL_SIZE * 0.5)
	var biome_mult: float = Terrain.biome_density(cell_center.x, cell_center.y)
	var vit: float = FloraLife.vitality_at(cell_center.x, cell_center.y)
	var stage: String = FloraLife.stage_for(GameClock.season, vit)
	# Cover breathes with vitality and thins where a cell was gathered out.
	var count := int(round(lerpf(240.0, 12.0, vf) * biome_mult
			* lerpf(0.5, 1.2, vit) * (1.0 - 0.6 * FloraLife.depletion(c))))
	var buckets: Dictionary = {}  # species_idx -> Array[Transform3D]
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
		var y := Terrain.height(wx, wz)
		if y < Terrain.water_surface_base(wx, wz) + 0.15:  # no cover midstream
			continue
		var roll := rng.randf()
		var s := rng.randf_range(0.7, 1.35)
		var variant := _pick_species(defs, true, wx, wz, roll)
		if variant < 0:
			continue
		if not buckets.has(variant):
			buckets[variant] = [] as Array[Transform3D]
		buckets[variant].append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)),
				Vector3(lx, y - 0.02, lz)))
	for variant: int in buckets:
		_bucket_to_multimesh(buckets[variant], _species_mesh(defs[variant], stage),
				parent, COVER_VISIBLE_RANGE)


## The shared billboard mesh for a species at a stage, built on first
## use (her stage paintings land in the same slots — see data/flora/).
func _species_mesh(def: Dictionary, stage: String) -> QuadMesh:
	var path: String = FloraLife.stage_art(def, stage)
	if path.is_empty():
		return null
	var key := "%s/%s" % [def.id, path]
	if not _species_meshes.has(key):
		_species_meshes[key] = _make_billboard_mesh(path, float(def.height),
				_sway, bool(def.get("cover", false)))
	return _species_meshes[key]


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
