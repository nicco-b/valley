class_name WaterGpu
extends RefCounted
## GPU driver for the tier-2 water dynamics field (DECISIONS 2026-07-04:
## whole-watershed, three tiers). One fixed 1024x1024 r32f depth field at
## 2m texels covering the same 2048m domain Hydrology routes — the WHOLE
## watershed, no scrolling. Two kernels per substep (outflow fluxes with
## a mass limiter, then integrate + rain + soak + sinks), a display
## texture the water sheet samples directly (Texture2DRD, zero CPU texel
## work), and a one-thread probe kernel for the four floats gameplay
## needs. Presentation tier: never saved, never fingerprinted — the
## canonical water is Hydrology's hourly balance (tier 1).

const GRID := 1024  # texel size scales with the watershed record (domain/GRID)
const SUBSTEPS := 2
const FLOW := 0.22  # per-substep surface-diff transfer (stable < 0.25)

var rd: RenderingDevice
var display_texture: Texture2DRD
var base_texture: Texture2DRD

var _pipeline := {}  # name -> [shader RID, pipeline RID]
var _depth := []  # ping, pong RIDs
var _flux: RID
var _display: RID
var _base: RID
var _sink: RID
var _sampler: RID
var _probe_buffer: RID
var _current := 0
var _ok := false


func setup() -> bool:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return false
	for shader_name in ["water_flux", "water_depth", "water_probe"]:
		var src: RDShaderFile = load("res://game/shaders/compute/%s.glsl" % shader_name)
		if src == null:
			return false
		var spirv := src.get_spirv()
		if spirv == null or spirv.compile_error_compute != "":
			push_error("[water] compute compile: " + spirv.compile_error_compute)
			return false
		var shader := rd.shader_create_from_spirv(spirv)
		_pipeline[shader_name] = [shader, rd.compute_pipeline_create(shader)]
	var r32 := RDTextureFormat.new()
	r32.width = GRID
	r32.height = GRID
	r32.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	r32.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_depth = [rd.texture_create(r32, RDTextureView.new()),
		rd.texture_create(r32, RDTextureView.new())]
	_base = rd.texture_create(r32, RDTextureView.new())
	_sink = rd.texture_create(r32, RDTextureView.new())
	var rgba := RDTextureFormat.new()
	rgba.width = GRID
	rgba.height = GRID
	rgba.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	rgba.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	_flux = rd.texture_create(rgba, RDTextureView.new())
	var rg := RDTextureFormat.new()
	rg.width = GRID
	rg.height = GRID
	rg.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	rg.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_display = rd.texture_create(rg, RDTextureView.new())
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_sampler = rd.sampler_create(ss)
	var four := PackedFloat32Array([0.0, 0.0, 0.0, 0.0]).to_byte_array()
	_probe_buffer = rd.storage_buffer_create(four.size(), four)
	var zero := PackedFloat32Array()
	zero.resize(GRID * GRID)
	for t in [_depth[0], _depth[1], _base, _sink]:
		rd.texture_update(t, 0, zero.to_byte_array())
	display_texture = Texture2DRD.new()
	display_texture.texture_rd_rid = _display
	base_texture = Texture2DRD.new()
	base_texture.texture_rd_rid = _base
	_ok = true
	return true


## Terrain heights + authored-water sink mask, baked on a worker thread.
func update_base(heights: PackedFloat32Array, sinks: PackedFloat32Array) -> void:
	if _ok:
		rd.texture_update(_base, 0, heights.to_byte_array())
		rd.texture_update(_sink, 0, sinks.to_byte_array())


## One frame of dynamics. rain/soak in meters per frame, seep per frame
## as a fraction of depth (all already scaled by delta).
func tick(rain: float, soak: float, seep: float) -> void:
	if not _ok:
		return
	var rain_step := rain / SUBSTEPS
	var soak_step := soak / SUBSTEPS
	var seep_step := seep / SUBSTEPS
	for i in SUBSTEPS:
		var push1 := PackedByteArray()
		push1.append_array(PackedInt32Array([GRID]).to_byte_array())
		push1.append_array(PackedFloat32Array([FLOW, 0.0, 0.0]).to_byte_array())
		_dispatch("water_flux", [
			_image_uniform(_depth[_current], 0),
			_sampler_uniform(_base, 1),
			_image_uniform(_flux, 2),
		], push1, GRID)
		var push2 := PackedByteArray()
		push2.append_array(PackedInt32Array([GRID]).to_byte_array())
		push2.append_array(PackedFloat32Array(
			[rain_step, soak_step, 0.12, seep_step]).to_byte_array())
		_dispatch("water_depth", [
			_image_uniform(_depth[_current], 0),
			_image_uniform(_flux, 1),
			_image_uniform(_depth[1 - _current], 2),
			_sampler_uniform(_sink, 3),
			_image_uniform(_display, 4),
		], push2, GRID)
		_current = 1 - _current


## Queue the probe at a field uv; read_probe() collects it next frame.
func dispatch_probe(uv: Vector2) -> void:
	if not _ok:
		return
	var push := PackedByteArray()
	push.append_array(PackedInt32Array([GRID]).to_byte_array())
	push.append_array(PackedFloat32Array([uv.x, uv.y, 0.0]).to_byte_array())
	_dispatch("water_probe", [
		_image_uniform(_depth[_current], 0),
		_image_uniform(_flux, 1),
		_buffer_uniform(_probe_buffer, 2),
	], push, 1)


## The probe's four floats: depth (m), net flux x, net flux z.
func read_probe() -> Vector4:
	if not _ok:
		return Vector4.ZERO
	var bytes := rd.buffer_get_data(_probe_buffer)
	var f := bytes.to_float32_array()
	return Vector4(f[0], f[1], f[2], f[3])


func _dispatch(shader_name: String, uniforms: Array, push: PackedByteArray,
		size: int) -> void:
	var pl: Array = _pipeline[shader_name]
	var uset := rd.uniform_set_create(uniforms, pl[0], 0)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pl[1])
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	rd.compute_list_set_push_constant(cl, push, push.size())
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(cl, (size + 7) / 8 if size > 1 else 1,
		(size + 7) / 8 if size > 1 else 1, 1)
	rd.compute_list_end()
	rd.free_rid(uset)


func _image_uniform(tex: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


func _sampler_uniform(tex: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_sampler)
	u.add_id(tex)
	return u


func _buffer_uniform(buf: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buf)
	return u
