extends Node
## Nav (autoload): near-tier navigation, the Creation Kit way — nobody
## maps where anyone walks. Every streamed cell bakes a NavigationMesh
## from its terrain triangles on the worker thread (water carved out,
## steep slopes filtered by the bake), registered as a region on the
## world map; adjacent cells knit at their shared border vertices.
## Bodies query path() and walk waypoints (PathCursor); wherever no
## navmesh exists — the far tier, unstreamed cells — path() falls back
## to the straight line, which is the data tier's honest approximation.

var _regions: Dictionary = {}  # Vector2i -> region RID
var _map: RID


func _ready() -> void:
	_map = get_tree().root.world_3d.navigation_map


## Bake a navmesh from a triangle soup in cell-local coordinates.
## Pure resource work — safe on a worker thread (that's the point).
static func bake_navmesh(faces: PackedVector3Array) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = 0.5
	navmesh.cell_height = 0.3
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.8
	navmesh.agent_max_climb = 0.6  # exact multiple of cell_height (bake floors it anyway)
	navmesh.agent_max_slope = 42.0
	if faces.is_empty():
		return navmesh
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
	return navmesh


## Toolkit: the walkable world.
func summary() -> String:
	return "navmesh cells=%d" % _regions.size()


func add_cell(c: Vector2i, navmesh: NavigationMesh, origin: Vector3) -> void:
	remove_cell(c)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, _map)
	NavigationServer3D.region_set_transform(region, Transform3D(Basis(), origin))
	NavigationServer3D.region_set_navigation_mesh(region, navmesh)
	_regions[c] = region


func remove_cell(c: Vector2i) -> void:
	if _regions.has(c):
		NavigationServer3D.free_rid(_regions[c])
		_regions.erase(c)


## A walkable route, or the straight line where the map has nothing —
## callers never need to know which tier they're on.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var p := NavigationServer3D.map_get_path(_map, from, to, true)
	if p.size() >= 2:
		return p
	# No navmesh route — the far tier's honest approximation is the
	# straight line (roads/waypoint graph retired with the old valley).
	return PackedVector3Array([from, to])
