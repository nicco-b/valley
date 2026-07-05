extends Node3D
## Builds the water surface meshes for every record in data/water/ — the
## scene no longer hardcodes water geometry. Lakes become vertex-dense
## discs, rivers dense ribbons, because tier 2.5 (the wave field)
## displaces water VERTICES — a flat quad can't ripple. Surfaces track
## Hydrology levels; river flow speed follows real discharge.

const WATER_SHADER := preload("res://game/shaders/water.gdshader")
const DISC_STEP := 0.9  # meters between lake verts (ripple-scale)
const RIBBON_STEP := 1.8  # meters between river cross-sections
const RIBBON_ACROSS := 5

var _lake_meshes: Dictionary = {}
var _river_meshes: Dictionary = {}
var _river_mats: Dictionary = {}

# The world sea (Terrain.sea_level): two meshes. A wave-capable patch
# rides with the focus (the 512² wave window is what displaces verts —
# density past it is wasted), and a coarse static disc carries the
# surface to the horizon. Far disc sits 15cm lower to avoid z-fighting
# where they overlap.
const SEA_NEAR_RADIUS := 300.0
const SEA_NEAR_STEP := 3.0
const SEA_FAR_RADIUS := 9000.0
const SEA_FAR_STEP := 250.0
var _sea_near: MeshInstance3D
var _sea_far: MeshInstance3D


func _ready() -> void:
	if Terrain.sea_level > -1e11:
		_sea_near = MeshInstance3D.new()
		_sea_near.name = "sea_near"
		_sea_near.mesh = _disc(SEA_NEAR_RADIUS, SEA_NEAR_STEP)
		_sea_near.mesh.surface_set_material(0, _material(Vector2.ZERO))
		_sea_near.extra_cull_margin = 4.0
		_sea_near.position.y = Terrain.sea_level
		add_child(_sea_near)
		_sea_far = MeshInstance3D.new()
		_sea_far.name = "sea_far"
		_sea_far.mesh = _disc(SEA_FAR_RADIUS, SEA_FAR_STEP)
		_sea_far.mesh.surface_set_material(0, _material(Vector2.ZERO))
		_sea_far.position.y = Terrain.sea_level - 0.15
		add_child(_sea_far)
	for w in Terrain.water_bodies:
		var center: Vector2 = w.center
		var mi := MeshInstance3D.new()
		mi.name = String(w.id)
		mi.mesh = _disc(float(w.radius))
		mi.mesh.surface_set_material(0, _material(Vector2.ZERO))
		mi.extra_cull_margin = 2.0  # waves leave the flat AABB
		mi.position = Vector3(center.x,
				float(w.surface) + Terrain.lake_levels[w.idx], center.y)
		add_child(mi)
		_lake_meshes[w.id] = mi
	for r in Terrain.rivers:
		var mi := MeshInstance3D.new()
		mi.name = String(r.id)
		var mat := _material(r.flow * _flow_speed(r.id))
		mi.mesh = _ribbon(r.nodes, Terrain.river_levels[r.idx])
		mi.mesh.surface_set_material(0, mat)
		mi.extra_cull_margin = 2.0
		add_child(mi)
		_river_meshes[r.id] = mi
		_river_mats[r.id] = mat
	Hydrology.levels_changed.connect(_on_levels_changed)


func _process(_delta: float) -> void:
	if _sea_near == null:
		return
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
	# Snapped so the wave-sampling verts don't shimmer as the focus moves.
	var snapped_focus := focus.snappedf(SEA_NEAR_STEP * 2.0)
	_sea_near.position.x = snapped_focus.x
	_sea_near.position.z = snapped_focus.y
	# The tide: both sheets ride the live surface, and the strand
	# shader's dark band follows it via the sea_level global.
	var live: float = Terrain.sea_surface()
	_sea_near.position.y = live
	_sea_far.position.y = live - 0.15
	RenderingServer.global_shader_parameter_set("sea_level", live)


func _on_levels_changed() -> void:
	for w in Terrain.water_bodies:
		var mi: MeshInstance3D = _lake_meshes.get(w.id)
		if mi:
			mi.position.y = float(w.surface) + Terrain.lake_levels[w.idx]
	for r in Terrain.rivers:
		var mi: MeshInstance3D = _river_meshes.get(r.id)
		if mi:
			mi.mesh = _ribbon(r.nodes, Terrain.river_levels[r.idx])
			mi.mesh.surface_set_material(0, _river_mats[r.id])
			_river_mats[r.id].set_shader_parameter("flow",
					Vector2(r.flow) * _flow_speed(r.id))


## Stripe drift speed from real discharge: baseline ~1, floods ~2.
func _flow_speed(river_id: String) -> float:
	return 2.0 * Hydrology.flow_norm(river_id)


func _material(flow: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("flow", flow)
	return mat


# A vertex-dense disc: every corner of a DISC_STEP grid (clamped to the
# rim), triangulated wherever a cell touches the circle. Plain loops —
# no lambda captures (a captured int counter froze and degenerated every
# triangle to vertex 0: mesh present, nothing drawn. The invisible-pond
# bug of 2026-07-04.)
func _disc(radius: float, step: float = DISC_STEP) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(ceil(radius * 2.0 / step)) + 2
	for iz in n:
		for ix in n:
			var p := Vector2(ix * step - radius, iz * step - radius)
			if p.length() > radius:
				p = p.normalized() * radius
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	for iz in n - 1:
		for ix in n - 1:
			var inside := 0
			for c in [[ix, iz], [ix + 1, iz], [ix, iz + 1], [ix + 1, iz + 1]]:
				var p := Vector2(c[0] * step - radius, c[1] * step - radius)
				if p.length() <= radius:
					inside += 1
			if inside == 0:
				continue
			var a := iz * n + ix
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	return st.commit()


# A dense ribbon: the spline resampled every RIBBON_STEP meters with
# RIBBON_ACROSS verts per cross-section. World-space (seam-free with the
# pond under the shared world-reading shader).
func _ribbon(nodes: Array, level: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Resample the polyline.
	var rows: Array = []
	var carry := 0.0
	for i in nodes.size() - 1:
		var a: Dictionary = nodes[i]
		var b: Dictionary = nodes[i + 1]
		var pa: Vector2 = a.pos
		var ab: Vector2 = b.pos - pa
		var seg_len := ab.length()
		if seg_len < 1e-4:
			continue
		var s := carry
		while s < seg_len:
			var f := s / seg_len
			rows.append([pa + ab * f, lerpf(a.half, b.half, f),
				lerpf(a.surface, b.surface, f), ab.normalized()])
			s += RIBBON_STEP
		carry = s - seg_len
	var last: Dictionary = nodes[nodes.size() - 1]
	var prev: Dictionary = nodes[nodes.size() - 2]
	rows.append([last.pos, float(last.half), float(last.surface),
		(Vector2(last.pos) - Vector2(prev.pos)).normalized()])
	# Emit rows of verts, stitch quads.
	for row in rows:
		var perp: Vector2 = Vector2(-row[3].y, row[3].x)
		for k in RIBBON_ACROSS:
			var u := (float(k) / (RIBBON_ACROSS - 1)) * 2.0 - 1.0
			var p: Vector2 = row[0] + perp * (u * row[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, row[2] + level, p.y))
	for i in rows.size() - 1:
		for k in RIBBON_ACROSS - 1:
			var a := i * RIBBON_ACROSS + k
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + RIBBON_ACROSS)
			st.add_index(a + 1)
			st.add_index(a + RIBBON_ACROSS + 1)
			st.add_index(a + RIBBON_ACROSS)
	return st.commit()
