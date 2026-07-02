extends Node3D
## Distant mountain silhouettes ringing the world, ~1.5-2.6km out.
## Flat unshaded ridgeline cards in palette colors; the distance fog
## supplies aerial perspective and day/night/storm tinting for free.
## Deterministic; placeholder until her painted mountain cutouts.

const COUNT := 14
const SEGMENTS := 16


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in COUNT:
		var ang := (float(i) + rng.randf_range(-0.32, 0.32)) * TAU / COUNT
		var dist := rng.randf_range(1500.0, 2600.0)
		add_child(_ridge(rng, ang, dist))


func _ridge(rng: RandomNumberGenerator, ang: float, dist: float) -> MeshInstance3D:
	var center := Vector3(cos(ang), 0.0, sin(ang)) * dist
	var right := Vector3(-sin(ang), 0.0, cos(ang))
	var width := rng.randf_range(1000.0, 1800.0)
	var height := rng.randf_range(160.0, 420.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops: Array[float] = []
	for s in SEGMENTS + 1:
		var t := float(s) / SEGMENTS
		var envelope := sin(t * PI)
		var jag := 0.55 + 0.45 * rng.randf()
		tops.append(height * envelope * jag)
	for s in SEGMENTS + 1:
		var t := float(s) / SEGMENTS
		var x := (t - 0.5) * width
		st.add_vertex(center + right * x + Vector3(0, -40.0, 0))
		st.add_vertex(center + right * x + Vector3(0, tops[s], 0))
	for s in SEGMENTS:
		var b0 := s * 2
		st.add_index(b0)
		st.add_index(b0 + 1)
		st.add_index(b0 + 2)
		st.add_index(b0 + 2)
		st.add_index(b0 + 1)
		st.add_index(b0 + 3)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Farther ridges sit paler, toward the haze.
	var near_col := Color(0.66, 0.54, 0.52)
	var far_col := Color(0.82, 0.74, 0.70)
	mat.albedo_color = near_col.lerp(far_col, (dist - 1500.0) / 1100.0)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
