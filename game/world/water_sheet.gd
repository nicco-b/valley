extends Node3D
## WaterSheet: the renderer for the tier-2 water dynamics field near the
## player — a flat grid patch (~96m at 0.75m vertices) that follows the
## focus; its vertex shader lifts each vertex onto the live GPU field
## (terrain base + water depth) and its fragments discard where the
## field is dry. All the motion is in the textures: the mesh is built
## once and only the node moves. Hidden entirely when the field is off
## (headless / no RenderingDevice).

const SIZE := 96.0
const RES := 129  # 0.75m vertices — rivulet-scale, not footprint-scale

var _mi: MeshInstance3D


func _ready() -> void:
	if not WaterField.enabled:
		set_process(false)
		return
	_mi = MeshInstance3D.new()
	_mi.mesh = _grid_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://game/shaders/water_sheet.gdshader")
	mat.set_shader_parameter("patch_size", SIZE)
	_mi.material_override = mat
	_mi.extra_cull_margin = 16.0  # vertices leave the flat AABB when wet
	add_child(_mi)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p: Vector3 = player.global_position
	# Snap to the field's 2m texel grid so vertices sample stable texels.
	global_position = Vector3(snappedf(p.x, 2.0), 0.0, snappedf(p.z, 2.0))


func _grid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := SIZE / (RES - 1)
	for iz in RES:
		for ix in RES:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(
				ix * step - SIZE * 0.5, 0.0, iz * step - SIZE * 0.5))
	for iz in RES - 1:
		for ix in RES - 1:
			var i := iz * RES + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + RES)
			st.add_index(i + 1)
			st.add_index(i + RES + 1)
			st.add_index(i + RES)
	return st.commit()
