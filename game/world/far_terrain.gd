extends Node3D
## Far-terrain LOD: a coarse 6.4km mesh sampling the SAME Terrain.height
## function as the streamed cells, sunk slightly beneath them. Whatever
## you see on the horizon is the real ground — walk toward it and the
## streamer builds the full-resolution cells on the same function.
## Re-centers (and rebuilds) when the focus strays far from its anchor.

const SIZE := 6400.0
const RES := 96  # vertices per side (~67m sampling)
const RECENTER_DISTANCE := 600.0
const SINK := 1.5  # sits below true height so near cells always win

var _anchor := Vector2.INF
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer:
		_mesh_instance.material_override = streamer._ground_material
	add_child(_mesh_instance)


func _process(_delta: float) -> void:
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
	if _anchor == Vector2.INF or focus.distance_to(_anchor) > RECENTER_DISTANCE:
		_anchor = focus.snappedf(256.0)
		_rebuild()


func _rebuild() -> void:
	var step := SIZE / (RES - 1)
	var origin := _anchor - Vector2.ONE * SIZE * 0.5
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
	_mesh_instance.mesh = st.commit()
