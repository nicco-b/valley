extends Node3D
class_name PreviewTerrain
## The SHAPING viewport (engine-viewport M2, data parity M3): one
## GPU-displaced grid wearing a Strata export DIRECTLY — height.exr as a
## vertex texture, sea level from the manifest, the data layers
## (moisture/temperature/flow/slope/biome) as false-color drapes. A
## preview push is a texture upload; the ground is new NEXT FRAME instead
## of after the streamer's ~2.7s rebuild storm.
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
## Data parity (M3): the drape's colours ARE Strata's. Every export
## carries ramps.png — a LUT strip written from Strata's DataRamps table
## (the one colormap truth; curve baked in) — and the shader samples it,
## so the game can never drift from the app. An old export without
## ramps.png falls back to constants hand-mirrored from Strata's
## render.metal (see the shader). Data layers get the CHART atmosphere
## (see _apply_chart_air); shaded keeps the full game look.
##
## Driven by StrataLink verbs (strata_link.gd):
##   preview_mesh <dir>   -> wear the export (creates the node on demand)
##   preview_mesh off     -> leave; the streamed world returns exactly
##   view_layer <name>    -> shaded|moisture|temperature|flow|slope|biome
##   probe <x> <z>        -> the active layer's value at a world position

const SHADER := "res://game/shaders/preview_terrain.gdshader"
const GRID := 1023  # subdivisions: 1024^2 verts ~ 16m/vertex over 16km

## Nodes that render the streamed world's ground/water join this group
## in their _ready (world_streamer, far_terrain, water_bodies,
## water_sheet, sand_patch) — the one place the "steps aside during
## preview" set is declared.
const STEPS_ASIDE_GROUP := "preview_steps_aside"

## Layer table — MIRRORS Strata (the parity contract, engine-viewport M3):
##  mode: the shader arm; ids match render.metal's viewMode
##        (0 shaded · 1 moisture · 2 temperature · 3 flow · 4 slope · 5 biome).
##  file: the export artifact the drape/probes read.
##  enc:  what the FILE's 0..1 (or raw exr) values mean physically —
##        mirrors WorldExporter (BakeManifest.swift): moisture.png spans
##        [0,1], temperature.png spans [-10,35]°C; exr floats are raw.
##  view: the false-color view range — mirrors Strata's DataRamps
##        (moisture 0..1, temperature -5..30°C, flow 0..60 with a sqrt
##        curve baked into the LUT, slope 0..1 as 1-n.y).
##  row:  the layer's row in ramps.png (DataRamps.lutRows order).
##  fmt:  probe value format — mirrors Strata's LayerProbe.format table.
const LAYERS := {
	"shaded": {"mode": 0, "fmt": "%.1f"},
	"moisture": {"mode": 1, "file": "moisture.png",
		"enc": [0.0, 1.0], "view": [0.0, 1.0], "row": 0, "fmt": "%.2f"},
	"temperature": {"mode": 2, "file": "temperature.png",
		"enc": [-10.0, 35.0], "view": [-5.0, 30.0], "row": 1, "fmt": "%.1f"},
	"flow": {"mode": 3, "file": "flow.exr",
		"enc": [0.0, 1.0], "view": [0.0, 60.0], "row": 2, "fmt": "%.2f"},
	"slope": {"mode": 4, "view": [0.0, 1.0], "row": 3, "fmt": "%.2f"},
	"biome": {"mode": 5, "file": "colormap.png", "fmt": "%d"},
}

## True while this grid is the visible ground (between wear and leave).
var worn := false

var _mesh: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _height_tex: ImageTexture = null
var _height_img: Image = null  # CPU mirror for probe (height + slope)
var _world_size := 16384.0
var _dir := ""            # the worn export dir (layers load lazily from it)
var _layer := "shaded"    # survives re-wears: a slider push keeps the drape
var _layer_cache: Dictionary = {}  # file -> {img, tex}, valid for _dir
var _ramp_tex: ImageTexture = null # ramps.png LUT (null: shader falls back)
var _restore: Array = []  # [node, was_visible] pairs recorded at enter

# The chart air (data layers only — see _apply_chart_air).
var _chart_env: Environment = null
var _chart_cam: Camera3D = null
var _chart_prev_env: Environment = null

# --- the zero-copy shared path (fork-genius #1, see wear_shared) ------------
# When Strata rides the shared-texture transport, the drape/height come from
# raw GPU surfaces wrapped as Texture2DRDs instead of loaded files. _shared
# maps layer name -> {tex0,tex1: Texture2DRD, rid0,rid1: RID, ptr0,ptr1,
# front, w, h, fmt}. The two textures per layer are Strata's double buffer:
# wrapped ONCE (stable pointers), the flip just re-points the material at the
# front. A resolution change (new pointers) re-wraps; leave() frees the rids.
var _shared_mode := false
var _shared: Dictionary = {}
var _shared_gen := 0


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
	_shared_mode = false  # the file path takes over from any shared wear
	_layer_cache.clear()  # new export: every cached drape is stale
	var world: Dictionary = manifest.get("world", {})
	var size_arr: Array = world.get("size_m", [16384.0, 16384.0])
	_world_size = maxf(float(size_arr[0]), float(size_arr[1]))
	var sea := float(world.get("sea_level_m", Terrain.sea_level))
	var mesh_ms := _ensure_mesh()
	var t1 := Time.get_ticks_usec()
	img.convert(Image.FORMAT_RF)
	_height_img = img  # the probe's CPU mirror rides the same bytes
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
	_load_ramp_lut()
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


## Wear Strata's SHARED bake surfaces (the zero-copy path): wrap the raw
## MTLTexture pointers as Texture2DRDs onto this grid — no file, no upload.
## `params` is strata_link's parsed payload {gen,w,h,size,sea,layers}. A warm
## push with stable pointers just re-points at the new front (the double
## buffer flip); a new resolution re-wraps. Returns "err ..." or a reply tail.
func wear_shared(params: Dictionary) -> String:
	var t0 := Time.get_ticks_usec()
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return "err no RenderingDevice for the shared path"
	var layers: Dictionary = params.get("layers", {})
	if not layers.has("height"):
		return "err shared payload has no height layer"
	var w := int(params["w"])
	var h := int(params["h"])
	_ensure_mesh()
	# Wrap / re-point every provided layer. A wrap failure on HEIGHT is fatal
	# (nothing to displace); a failed drape layer is just skipped (its view
	# falls back to shaded via set_layer's honest err).
	for name: String in layers.keys():
		var spec: Dictionary = layers[name]
		if not _ensure_shared_layer(rd, name, spec, w, h) and name == "height":
			return "err could not wrap the shared height surface"
	_world_size = float(params["size"])
	_shared_gen = int(params["gen"])
	_shared_mode = true
	_height_img = null  # no CPU mirror on the shared path (probe errs honestly)
	var sea := float(params["sealevel"])
	_mat.set_shader_parameter("height_map", _shared_front("height"))
	_mat.set_shader_parameter("world_size", _world_size)
	_mat.set_shader_parameter("sea_level", sea)
	# The shared path carries no ramps.png; the shader's mirrored fallback
	# constants answer (same numbers as DataRamps — see the shader header).
	_ramp_tex = null
	_mat.set_shader_parameter("ramp_lut", null)
	_mat.set_shader_parameter("has_lut", false)
	_mesh.scale = Vector3(_world_size / 2.0, 1.0, _world_size / 2.0)
	if not worn:
		_enter()
	# Re-assert the drape from the new surfaces; a layer the shared push can't
	# serve (temperature has no raw-field surface yet) falls back to shaded.
	if _layer != "shaded" and set_layer(_layer).begins_with("err"):
		_apply_layer("shaded")
	var total_ms := (Time.get_ticks_usec() - t0) / 1000.0
	return "%.0fm sea=%.1fm gen=%d wrap=%.1fms" % [_world_size, sea, _shared_gen, total_ms]


## Wrap (or re-point) one shared layer's double buffer. Returns whether the
## front texture is available afterwards. Stable pointers + same size = reuse
## the two Texture2DRDs (the warm flip); anything changed re-wraps and frees
## the old rids.
func _ensure_shared_layer(rd: RenderingDevice, name: String, spec: Dictionary,
		w: int, h: int) -> bool:
	var ptr0 := int(spec["ptr0"])
	var ptr1 := int(spec["ptr1"])
	var front := int(spec["front"])
	var fmt := String(spec["fmt"])
	var have: Dictionary = _shared.get(name, {})
	if have.is_empty() or int(have.get("ptr0", 0)) != ptr0 \
			or int(have.get("ptr1", 0)) != ptr1 \
			or int(have.get("w", 0)) != w or int(have.get("h", 0)) != h:
		_free_shared_layer(name)  # resolution/pointer change: re-wrap
		var t0: Variant = _wrap_shared(rd, ptr0, fmt, w, h)
		var t1: Variant = _wrap_shared(rd, ptr1, fmt, w, h)
		if t0 == null or t1 == null:
			return false
		_shared[name] = {"tex0": t0[0], "rid0": t0[1], "tex1": t1[0], "rid1": t1[1],
			"ptr0": ptr0, "ptr1": ptr1, "front": front, "w": w, "h": h, "fmt": fmt}
	else:
		have["front"] = front
		_shared[name] = have
	return true


## One raw MTLTexture pointer -> [Texture2DRD, RID], or null on failure. Stock
## 4.7 API (proven by SharedTexProbe): texture_create_from_extension wraps the
## host texture, Texture2DRD makes it a sampler2D the shader reads.
func _wrap_shared(rd: RenderingDevice, ptr: int, fmt: String, w: int, h: int) -> Variant:
	var data_fmt := RenderingDevice.DATA_FORMAT_R32_SFLOAT
	if fmt == "rgba8":
		data_fmt = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	var rid := rd.texture_create_from_extension(
		RenderingDevice.TEXTURE_TYPE_2D, data_fmt,
		RenderingDevice.TEXTURE_SAMPLES_1,
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT,
		ptr, w, h, 1, 1)
	if not rid.is_valid():
		return null
	var tex := Texture2DRD.new()
	tex.texture_rd_rid = rid
	return [tex, rid]


## The front Texture2DRD of a wrapped shared layer (null when absent).
func _shared_front(name: String) -> Texture2DRD:
	var e: Dictionary = _shared.get(name, {})
	if e.is_empty():
		return null
	return e["tex1"] if int(e["front"]) == 1 else e["tex0"]


func _free_shared_layer(name: String) -> void:
	var e: Dictionary = _shared.get(name, {})
	if e.is_empty():
		return
	var rd := RenderingServer.get_rendering_device()
	if rd != null:
		for k in ["rid0", "rid1"]:
			var rid: RID = e[k]
			if rid.is_valid():
				rd.free_rid(rid)
	_shared.erase(name)


func _free_shared() -> void:
	for name in _shared.keys().duplicate():
		_free_shared_layer(name)
	_shared.clear()
	_shared_mode = false


## Switch the false-color drape. Loads the layer texture lazily from the
## worn export dir (cached until the next wear). Returns the reply line.
func set_layer(name: String) -> String:
	if not LAYERS.has(name):
		return "err view_layer needs %s" % "|".join(LAYERS.keys())
	var t0 := Time.get_ticks_usec()
	if _shared_mode:
		return _set_layer_shared(name, t0)
	var spec: Dictionary = LAYERS[name]
	if spec.has("file"):
		var entry: Variant = _cached_layer(String(spec["file"]))
		if entry is String:
			return entry  # the honest missing-file err
		_mat.set_shader_parameter(
			"color_map" if name == "biome" else "data_map", entry["tex"])
	_apply_layer(name)
	return "ok layer %s (%.0fms)" % [name, (Time.get_ticks_usec() - t0) / 1000.0]


## The shared-path drape: the false-color layers come from wrapped GPU
## surfaces, not files. shaded/slope ride the height surface (no drape tex);
## moisture/flow bind their raw-field surface (the shader's data_scale/offset
## reproduces the same t the file path computes — moisture and flow store the
## same values raw as their exports); biome binds the colormap surface.
## temperature has no raw-field surface yet (its export normalizes °C), so it
## errs honestly and Strata falls back to the Metal view for that one layer.
func _set_layer_shared(name: String, t0: int) -> String:
	match name:
		"shaded", "slope":
			pass  # derived from the height surface in-shader; no drape texture
		"biome":
			var ctex := _shared_front("colormap")
			if ctex == null:
				return "err shared preview has no colormap surface"
			_mat.set_shader_parameter("color_map", ctex)
		"temperature":
			return "err temperature has no shared surface (Metal view only)"
		_:
			var dtex := _shared_front(name)
			if dtex == null:
				return "err shared preview has no %s surface" % name
			_mat.set_shader_parameter("data_map", dtex)
	_apply_layer(name)
	return "ok layer %s shared (%.0fms)" % [name, (Time.get_ticks_usec() - t0) / 1000.0]


## The active layer's value at a world position — the value-under-cursor
## verb (M3). Reply grammar (pinned by Strata's LayerProbe + the scene
## tests; keep in lockstep): "ok probe <layer> <value> at (<x>, <z>)".
## Values are physical (temperature in °C via the png's encoding range,
## flow raw from the exr, shaded = height in meters, biome = the id from
## biome.png, slope = 1-n.y like the drape and the Metal view).
func probe(x: float, z: float) -> String:
	if not worn:
		return "err no preview mesh worn (preview_mesh <dir> first)"
	if _shared_mode:
		# The zero-copy path keeps no CPU mirror; the value-under-cursor probe
		# reads back from the GPU or answers from Strata's own store — an
		# openEnd. Honest err until then (Strata's data-view readout hides).
		return "err probe unavailable on the shared preview path"
	# ASCII-only replies (the wire contract): no ± and friends.
	var half := _world_size / 2.0
	if absf(x) > half or absf(z) > half:
		return "err probe (%.0f, %.0f) outside the world (max %.0fm from center)" % [
			x, z, half]
	var spec: Dictionary = LAYERS[_layer]
	var value: float
	match _layer:
		"shaded":
			value = _sample(_height_img, x, z)
		"slope":
			value = _slope_at(x, z)
		"biome":
			# The drape wears colormap.png (pre-coloured); the VALUE is the
			# id, which lives in biome.png — loaded lazily like any layer.
			var entry: Variant = _cached_layer("biome.png")
			if entry is String:
				return entry
			value = roundf(_sample(entry["img"], x, z) * 255.0)
		_:
			var entry: Variant = _cached_layer(String(spec["file"]))
			if entry is String:
				return entry
			var enc: Array = spec.get("enc", [0.0, 1.0])
			value = _sample(entry["img"], x, z) \
				* (float(enc[1]) - float(enc[0])) + float(enc[0])
	return "ok probe %s %s at (%.0f, %.0f)" % [
		_layer, String(spec["fmt"]) % value, x, z]


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
	_release_chart_air()
	_free_shared()  # release the wrapped RD textures (no-op on the file path)


# Data layers keep their chart air even when the camera changes hands
# (Toolkit fly<->orbit swaps rewrite cam.environment) — reassert per
# frame; a no-op while the right camera already wears it.
func _process(_delta: float) -> void:
	if worn and _layer != "shaded":
		_apply_chart_air()


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
	# The shader normalizes raw texture values into ramp-t in one fma:
	# t = raw * data_scale + data_offset — computed here from the file's
	# encoding range and the view range (both in the LAYERS table).
	var view: Array = spec.get("view", [0.0, 1.0])
	var enc: Array = spec.get("enc", [0.0, 1.0])
	var span := maxf(float(view[1]) - float(view[0]), 1e-5)
	_mat.set_shader_parameter("data_scale", (float(enc[1]) - float(enc[0])) / span)
	_mat.set_shader_parameter("data_offset", (float(enc[0]) - float(view[0])) / span)
	_mat.set_shader_parameter("ramp_row", int(spec.get("row", 0)))
	_layer = name
	# Atmosphere policy (M3): shaded IS the game (its whole point — keep
	# the world's air); DATA layers are charts and get the exemption.
	if name == "shaded":
		_release_chart_air()
	else:
		_apply_chart_air()


## A layer file's CPU image + GPU texture, loaded once per wear. Returns
## {img, tex} or the honest err String when the export lacks the file.
func _cached_layer(file: String) -> Variant:
	if not _layer_cache.has(file):
		if not FileAccess.file_exists(_dir.path_join(file)):
			return "err layer file missing: %s (re-export from Strata)" % file
		var img := Image.load_from_file(_dir.path_join(file))
		if img == null or img.is_empty():
			return "err layer file missing: %s (re-export from Strata)" % file
		_layer_cache[file] = {"img": img, "tex": ImageTexture.create_from_image(img)}
	return _layer_cache[file]


## ramps.png (the DataRamps LUT strip Strata writes into every export,
## M3): the drape samples IT for exact colormap parity — the game cannot
## drift from the app. Absent (old export): the shader's fallback
## constants answer, hand-mirrored from render.metal.
func _load_ramp_lut() -> void:
	_ramp_tex = null
	if FileAccess.file_exists(_dir.path_join("ramps.png")):
		var img := Image.load_from_file(_dir.path_join("ramps.png"))
		if img != null and not img.is_empty():
			_ramp_tex = ImageTexture.create_from_image(img)
			_mat.set_shader_parameter("lut_rows", img.get_height())
	_mat.set_shader_parameter("ramp_lut", _ramp_tex)
	_mat.set_shader_parameter("has_lut", _ramp_tex != null)


## Sample a layer image at a world position (nearest texel — the probe
## answers what the data SAYS, not a filtered blend). Origin-centered
## world frame, +x = +u, +z = +v — the drape's own mapping.
func _sample(img: Image, x: float, z: float) -> float:
	var u := clampf(x / _world_size + 0.5, 0.0, 1.0)
	var v := clampf(z / _world_size + 0.5, 0.0, 1.0)
	var px := clampi(int(u * img.get_width()), 0, img.get_width() - 1)
	var py := clampi(int(v * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(px, py).r


## Slope at a world position: 1 - n.y of the central-difference normal —
## the same estimator the drape shader and Strata's Metal view use.
func _slope_at(x: float, z: float) -> float:
	var w := _height_img.get_width()
	var h := _height_img.get_height()
	var px := clampi(int((x / _world_size + 0.5) * w), 0, w - 1)
	var py := clampi(int((z / _world_size + 0.5) * h), 0, h - 1)
	var dx := _world_size / float(w)
	var hl := _height_img.get_pixel(maxi(px - 1, 0), py).r
	var hr := _height_img.get_pixel(mini(px + 1, w - 1), py).r
	var hd := _height_img.get_pixel(px, maxi(py - 1, 0)).r
	var hu := _height_img.get_pixel(px, mini(py + 1, h - 1)).r
	var gx := (hl - hr) / (2.0 * dx)
	var gz := (hd - hu) / (2.0 * dx)
	return 1.0 - 1.0 / sqrt(gx * gx + 1.0 + gz * gz)


# --- the chart air (atmosphere policy, M3) ---------------------------------
# Data layers are measurements: the map screen's rendering-only weather
# exemption (OrbitRig.chart_environment — fog/volumetrics off), its flat
# ambient floor so midnight can't turn the chart illegible, PLUS a linear
# tonemap at exposure 1.0 so the ramp colours arrive on screen as the
# DataRamps table wrote them (filmic would re-grade the measurement).
# Rendering only, on the CAMERA — Weather/Climate never hear about it,
# and the sim is untouched, ever. Shaded mode never wears this: seeing
# the world's real air is its point.

func _apply_chart_air() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	if _chart_cam != null and cam != _chart_cam:
		_release_chart_air()  # the view changed hands mid-drape
	if cam.environment != null and cam.environment == _chart_env:
		return  # already wearing it
	if _chart_env == null:
		var env := OrbitRig.chart_environment(get_viewport().world_3d.environment)
		env.fog_enabled = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(1.0, 0.98, 0.94)
		env.ambient_light_energy = 0.6
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.glow_enabled = false
		_chart_env = env
	_chart_cam = cam
	_chart_prev_env = cam.environment
	cam.environment = _chart_env


func _release_chart_air() -> void:
	if _chart_cam != null and is_instance_valid(_chart_cam) \
			and _chart_cam.environment == _chart_env:
		_chart_cam.environment = _chart_prev_env
	_chart_cam = null
	_chart_prev_env = null


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
