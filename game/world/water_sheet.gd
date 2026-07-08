extends Node3D
## WaterSheet: the renderer for the tier-2 water dynamics field near the
## player — a flat grid patch (~96m at 0.75m vertices) that follows the
## focus; its vertex shader lifts each vertex onto the live GPU field
## (terrain base + water depth) and its fragments discard where the
## field is dry. All the motion is in the textures: the mesh is built
## once and only the node moves. Hidden entirely when the field is off
## (headless / no RenderingDevice).

const SIZE := 96.0
const SIZE_FILL := 288.0  # fill experiment: reach over rivulet detail
const RES := 129  # 0.75m vertices (fill: 2.25m ~ the field's own texels)

var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _built_size := 0.0


func _ready() -> void:
	add_to_group(PreviewTerrain.STEPS_ASIDE_GROUP)  # steps aside during preview
	if not WaterField.enabled:
		set_process(false)
		return
	_mi = MeshInstance3D.new()
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://game/shaders/water_sheet.gdshader")
	_mi.material_override = _mat
	# The vertex shader lifts verts to ABSOLUTE terrain height, so the
	# flat AABB must be seated at local ground level (below) and grown
	# by the relief a patch can span — at y=0 with a 16m margin the
	# whole sheet was frustum-culled anywhere above the home valley
	# (the volcano flank jank).
	_mi.extra_cull_margin = 260.0
	_rebuild(SIZE)
	add_child(_mi)


func _rebuild(size: float) -> void:
	_built_size = size
	_mi.mesh = _grid_mesh(size)
	_mat.set_shader_parameter("patch_size", size)


func _process(_delta: float) -> void:
	# The fill experiment trades vertex density for reach: swap patch
	# size when the toggle flips (one rebuild, ~16k verts).
	var want := SIZE_FILL if WaterField.fill_channels else SIZE
	if want != _built_size:
		_rebuild(want)
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p: Vector3 = player.global_position
	# Snap to the field's 2m texel grid so vertices sample stable texels;
	# seat the node at ground level so the grown AABB brackets the water.
	global_position = Vector3(snappedf(p.x, 2.0),
		Terrain.height(p.x, p.z), snappedf(p.z, 2.0))


func _grid_mesh(size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / (RES - 1)
	for iz in RES:
		for ix in RES:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(
				ix * step - size * 0.5, 0.0, iz * step - size * 0.5))
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
