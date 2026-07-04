extends Node3D
## Builds the water surface meshes for every record in data/water/ — the
## scene no longer hardcodes water geometry. Lakes become discs, rivers
## become ribbons that follow the spline. Physics (swimming), navmesh
## carving, and moisture all read the same records via Terrain, so a new
## body of water is one JSON file. Surfaces track Hydrology: lake discs
## ride their live level, river ribbons rebuild at their offset, and flow
## speed follows real discharge — a drought moves slower before it looks
## shallower.

const WATER_SHADER := preload("res://game/shaders/water.gdshader")

var _lake_meshes: Dictionary = {}  # id -> MeshInstance3D
var _river_meshes: Dictionary = {}  # id -> MeshInstance3D
var _river_mats: Dictionary = {}  # id -> ShaderMaterial


func _ready() -> void:
	for w in Terrain.water_bodies:
		var center: Vector2 = w.center
		var mesh := CylinderMesh.new()
		mesh.top_radius = w.radius
		mesh.bottom_radius = w.radius
		mesh.height = 0.1
		mesh.radial_segments = 64
		mesh.material = _material(Vector2.ZERO)
		var mi := MeshInstance3D.new()
		mi.name = String(w.id)
		mi.mesh = mesh
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


## Stripe drift speed from real discharge: baseline flow ~1, floods ~2,
## a drought crawls.
func _flow_speed(river_id: String) -> float:
	return 2.0 * Hydrology.flow_norm(river_id)


func _material(flow: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("flow", flow)
	return mat


# A flat ribbon through the river nodes: each node offset left/right by
# its half-width along the local perpendicular, stitched into quads. Built
# in world space so the shared water shader (which reads world position)
# lines up seam-free with the pond.
func _ribbon(nodes: Array, level: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in nodes.size():
		var p: Vector2 = nodes[i].pos
		var tangent: Vector2
		if i == 0:
			tangent = nodes[1].pos - p
		elif i == nodes.size() - 1:
			tangent = p - nodes[i - 1].pos
		else:
			tangent = (nodes[i + 1].pos - nodes[i - 1].pos)
		tangent = tangent.normalized() if tangent.length() > 1e-4 else Vector2.RIGHT
		var perp := Vector2(-tangent.y, tangent.x) * float(nodes[i].half)
		var y: float = nodes[i].surface + level
		left.append(Vector3(p.x + perp.x, y, p.y + perp.y))
		right.append(Vector3(p.x - perp.x, y, p.y - perp.y))
	for i in nodes.size() - 1:
		_quad(st, left[i], right[i], left[i + 1], right[i + 1])
	return st.commit()


func _quad(st: SurfaceTool, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3) -> void:
	for v in [l0, r0, l1, r0, r1, l1]:  # two triangles; cull_disabled, so winding is free
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
