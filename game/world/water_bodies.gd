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


func _ready() -> void:
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


# A vertex-dense disc: a DISC_STEP grid clamped to the circle rim, cells
# kept when any corner falls inside. Local coordinates; the node carries
# the world position (the shader reads world via MODEL_MATRIX).
func _disc(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(ceil(radius * 2.0 / DISC_STEP)) + 1
	var verts := {}
	var idx := 0
	var index_of := func(ix: int, iz: int) -> int:
		var key := ix * 10000 + iz
		if not verts.has(key):
			var p := Vector2(ix * DISC_STEP - radius, iz * DISC_STEP - radius)
			if p.length() > radius:
				p = p.normalized() * radius
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, 0.0, p.y))
			verts[key] = idx
			idx += 1
		return verts[key]
	for iz in n:
		for ix in n:
			var inside := 0
			for c in [[ix, iz], [ix + 1, iz], [ix, iz + 1], [ix + 1, iz + 1]]:
				var p := Vector2(c[0] * DISC_STEP - radius, c[1] * DISC_STEP - radius)
				if p.length() <= radius:
					inside += 1
			if inside == 0:
				continue
			var a: int = index_of.call(ix, iz)
			var b: int = index_of.call(ix + 1, iz)
			var c2: int = index_of.call(ix, iz + 1)
			var d: int = index_of.call(ix + 1, iz + 1)
			st.add_index(a)
			st.add_index(b)
			st.add_index(c2)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c2)
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
