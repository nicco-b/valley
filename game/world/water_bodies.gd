extends Node3D
## Builds a water surface mesh for every record in data/water/ — the
## scene no longer hardcodes water geometry. Physics (swimming), navmesh
## carving, and moisture all read the same records via Terrain, so a new
## lake is one JSON file.

const WATER_SHADER := preload("res://game/shaders/water.gdshader")


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	for w in Terrain.water_bodies:
		var center: Vector2 = w.center
		var mesh := CylinderMesh.new()
		mesh.top_radius = w.radius
		mesh.bottom_radius = w.radius
		mesh.height = 0.1
		mesh.radial_segments = 64
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.name = String(w.id)
		mi.mesh = mesh
		mi.position = Vector3(center.x, w.surface, center.y)
		add_child(mi)
