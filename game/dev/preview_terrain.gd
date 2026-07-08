extends Node3D
class_name PreviewTerrain
## The SHAPING viewport (engine-viewport M2, from the spike's prototype):
## one GPU-displaced grid wearing a Strata export DIRECTLY — height.exr
## as a vertex texture, sea level from the manifest, the data layers
## (moisture/temperature/biome/slope) as false-color drapes with
## hillshade + contours. A preview push is a texture upload; the ground
## is new NEXT FRAME instead of after the streamer's ~2.7s rebuild storm.
##
## The lifecycle contract (what "preview" means here):
##  - wear() ENTERS preview: this grid becomes the visible ground, and
##    every node in the "preview_steps_aside" group (the streamed world's
##    dress: cells, far quadtree, sea + lakes, water sheet, sand) hides,
##    each remembering whether it was visible. VISIBILITY ONLY — the
##    sims keep running, streaming keeps streaming, and Terrain (the
##    kernel, the height function, sea_level) is NEVER touched. This is
##    the deliberate opposite of preview_world, which re-tiles the live
##    kernel and pays the rebuild storm.
##  - repeated wears just swap textures (the slider loop) — 7-13ms warm.
##  - leave() restores every remembered node to exactly its recorded
##    visibility and hides the grid. Because the real world's data never
##    changed, restore is one frame — nothing rebuilds.
##
## Driven by StrataLink verbs (strata_link.gd):
##   preview_mesh <dir>   -> wear the export (creates the node on demand)
##   preview_mesh off     -> leave; the streamed world returns exactly
##   view_layer <name>    -> shaded|moisture|temperature|slope|biome

const SHADER := "res://game/shaders/preview_terrain.gdshader"
const GRID := 1023  # subdivisions: 1024^2 verts ~ 16m/vertex over 16km

## Nodes that render the streamed world's ground/water join this group
## in their _ready (world_streamer, far_terrain, water_bodies,
## water_sheet, sand_patch) — the one place the "steps aside during
## preview" set is declared.
const STEPS_ASIDE_GROUP := "preview_steps_aside"

## Layer name -> shader mode (+ source file and normalization for the
## gray data layers; slope computes from the height texture in-shader).
const LAYERS := {
	"shaded": {"mode": 0},
	"moisture": {"mode": 1, "file": "moisture.png", "min": 0.0, "max": 1.0},
	"temperature": {"mode": 2, "file": "temperature.png", "min": 0.0, "max": 1.0},
	"slope": {"mode": 3},
	"biome": {"mode": 4, "file": "colormap.png"},
}

## True while this grid is the visible ground (between wear and leave).
var worn := false

var _mesh: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _height_tex: ImageTexture = null
var _world_size := 16384.0
var _dir := ""            # the worn export dir (layers load lazily from it)
var _layer := "shaded"    # survives re-wears: a slider push keeps the drape
var _layer_cache: Dictionary = {}  # file -> ImageTexture, valid for _dir
var _restore: Array = []  # [node, was_visible] pairs recorded at enter


## Wear an export: height texture + world frame + sea level onto the
## grid, then enter preview (first wear) or just swap textures (re-wear).
## Returns "err ..." or a reply tail: "<size>m sea=<m> wear=<ms>ms".
func wear(dir: String) -> String:
	var t0 := Time.get_ticks_usec()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		dir.path_join("bake_manifest.json")))
	if not (manifest is Dictionary):
		return "err no bake_manifest.json in %s" % dir
	# file_exists first: the honest error, without engine noise in the log.
	if not FileAccess.file_exists(dir.path_join("height.exr")):
		return "err no height.exr in %s" % dir
	var img := Image.load_from_file(dir.path_join("height.exr"))
	if img == null or img.is_empty():
		return "err no height.exr in %s" % dir
	_dir = dir
	_layer_cache.clear()  # new export: every cached drape is stale
	var world: Dictionary = manifest.get("world", {})
	var size_arr: Array = world.get("size_m", [16384.0, 16384.0])
	_world_size = maxf(float(size_arr[0]), float(size_arr[1]))
	var sea := float(world.get("sea_level_m", Terrain.sea_level))
	var mesh_ms := _ensure_mesh()
	var t1 := Time.get_ticks_usec()
	img.convert(Image.FORMAT_RF)
	# Warm path: same-size pushes update the texture in place (the
	# auto-send loop re-exports into one dir at one resolution).
	if _height_tex != null and _height_tex.get_size() == Vector2(img.get_size()) \
			and _height_tex.get_format() == img.get_format():
		_height_tex.update(img)
	else:
		_height_tex = ImageTexture.create_from_image(img)
	_mat.set_shader_parameter("height_map", _height_tex)
	_mat.set_shader_parameter("world_size", _world_size)
	_mat.set_shader_parameter("sea_level", sea)
	_mesh.scale = Vector3(_world_size / 2.0, 1.0, _world_size / 2.0)
	if not worn:
		_enter()
	# The drape survives the push — reload it from the NEW export's bytes.
	# A layer the new export dropped falls back honestly to shaded.
	if _layer != "shaded" and set_layer(_layer).begins_with("err"):
		print("[preview] layer %s missing in new export — back to shaded" % _layer)
		_apply_layer("shaded")
	var total_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("[preview] wear: mesh %.0fms upload %.1fms total %.1fms" % [
		mesh_ms, (Time.get_ticks_usec() - t1) / 1000.0, total_ms])
	return "%.0fm sea=%.1fm wear=%.0fms" % [_world_size, sea, total_ms]


## Switch the false-color drape. Loads the layer texture lazily from the
## worn export dir (cached until the next wear). Returns the reply line.
func set_layer(name: String) -> String:
	if not LAYERS.has(name):
		return "err view_layer needs %s" % "|".join(LAYERS.keys())
	var t0 := Time.get_ticks_usec()
	var spec: Dictionary = LAYERS[name]
	if spec.has("file"):
		var file: String = spec["file"]
		if not _layer_cache.has(file):
			if not FileAccess.file_exists(_dir.path_join(file)):
				return "err layer file missing: %s (re-export from Strata)" % file
			var img := Image.load_from_file(_dir.path_join(file))
			if img == null or img.is_empty():
				return "err layer file missing: %s (re-export from Strata)" % file
			_layer_cache[file] = ImageTexture.create_from_image(img)
		_mat.set_shader_parameter(
			"color_map" if name == "biome" else "data_map", _layer_cache[file])
	_apply_layer(name)
	return "ok layer %s (%.0fms)" % [name, (Time.get_ticks_usec() - t0) / 1000.0]


## Leave preview: the grid hides, every stepped-aside node returns to
## exactly the visibility it had at enter. One frame — the real world's
## data never changed, so nothing rebuilds.
func leave() -> void:
	if not worn:
		return
	visible = false
	for pair: Array in _restore:
		var n: Node = pair[0]
		if is_instance_valid(n):
			(n as Node3D).visible = pair[1]
	_restore.clear()
	worn = false


# Enter preview: record + hide the streamed world's dress. New cells and
# far tiles spawn UNDER their (now hidden) parents, so the set recorded
# here stays complete for the whole stay.
func _enter() -> void:
	_restore.clear()
	for n: Node in get_tree().get_nodes_in_group(STEPS_ASIDE_GROUP):
		if n is Node3D:
			_restore.append([n, (n as Node3D).visible])
			(n as Node3D).visible = false
	visible = true
	worn = true


func _apply_layer(name: String) -> void:
	var spec: Dictionary = LAYERS[name]
	_mat.set_shader_parameter("mode", int(spec["mode"]))
	_mat.set_shader_parameter("data_min", float(spec.get("min", 0.0)))
	_mat.set_shader_parameter("data_max", float(spec.get("max", 1.0)))
	_layer = name


# One flat grid, built once (PlaneMesh in C++, ~46ms — first wear only).
# Returns build ms.
func _ensure_mesh() -> float:
	if _mesh != null:
		return 0.0
	var t0 := Time.get_ticks_usec()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)  # unit; scaled to the world frame
	plane.subdivide_width = GRID
	plane.subdivide_depth = GRID
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = plane
	_mesh.material_override = _mat
	# The displaced grid leaves its flat bounds; keep it always rendered.
	_mesh.custom_aabb = AABB(Vector3(-1, -2000, -1), Vector3(2, 6000, 2))
	_mesh.extra_cull_margin = 16384.0
	add_child(_mesh)
	return (Time.get_ticks_usec() - t0) / 1000.0
