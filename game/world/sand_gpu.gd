class_name SandGpu
extends RefCounted
## GPU driver for the granular sand sim: the whole field lives on the
## GPU (1024 x 1024 r32f, 2.3cm texels over 24m) and the relaxation
## kernel runs as a compute shader — CPU touches nothing per-texel, the
## renderer samples the display texture directly (Texture2DRD), zero
## uploads. The CPU thread in sand_field.gd remains the reference
## implementation (unit-tested conservation) and the headless fallback.

const GRID := 1024
const REGION := 24.0
const BASE_GRID := 256
const MAX_OPS := 64
const RELAX_PER_FRAME := 3
const MAX_DELTA := 0.3

var rd: RenderingDevice
var display_texture: Texture2DRD

var _pipeline := {}  # name -> [shader RID, pipeline RID]
var _tex := []  # ping, pong RIDs
var _display: RID
var _base: RID
var _mask_atlas: RID
var _sampler: RID
var _ops_buffer: RID
var _current := 0
var _ok := false


func setup(masks: Array) -> bool:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		return false
	for shader_name in ["sand_apply", "sand_relax", "sand_copy"]:
		var src: RDShaderFile = load("res://game/shaders/compute/%s.glsl" % shader_name)
		if src == null:
			return false
		var spirv := src.get_spirv()
		if spirv == null or spirv.compile_error_compute != "":
			push_error("[sand] compute compile: " + spirv.compile_error_compute)
			return false
		var shader := rd.shader_create_from_spirv(spirv)
		_pipeline[shader_name] = [shader, rd.compute_pipeline_create(shader)]
	var fmt := RDTextureFormat.new()
	fmt.width = GRID
	fmt.height = GRID
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_tex = [rd.texture_create(fmt, RDTextureView.new()),
		rd.texture_create(fmt, RDTextureView.new())]
	_display = rd.texture_create(fmt, RDTextureView.new())
	var bfmt := RDTextureFormat.new()
	bfmt.width = BASE_GRID
	bfmt.height = BASE_GRID
	bfmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	bfmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_base = rd.texture_create(bfmt, RDTextureView.new())
	# Mask atlas: 4 slots of 18px side by side (72 x 18, r32f, meters).
	var afmt := RDTextureFormat.new()
	afmt.width = 18 * 4
	afmt.height = 18
	afmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	afmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var atlas := PackedFloat32Array()
	atlas.resize(18 * 4 * 18)
	for slot in mini(masks.size(), 4):
		var mw: int = masks[slot][0]
		var mh: int = masks[slot][1]
		var data: PackedFloat32Array = masks[slot][2]
		var ox := slot * 18 + (18 - mw) / 2
		var oy := (18 - mh) / 2
		for y in mh:
			for x in mw:
				atlas[(oy + y) * 72 + ox + x] = data[y * mw + x]
	_mask_atlas = rd.texture_create(afmt, RDTextureView.new(), [atlas.to_byte_array()])
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_sampler = rd.sampler_create(ss)
	var empty := PackedFloat32Array()
	empty.resize(MAX_OPS * 8)
	_ops_buffer = rd.storage_buffer_create(empty.to_byte_array().size(),
		empty.to_byte_array())
	# Zero all field textures.
	var zero := PackedFloat32Array()
	zero.resize(GRID * GRID)
	for t in [_tex[0], _tex[1], _display]:
		rd.texture_update(t, 0, zero.to_byte_array())
	display_texture = Texture2DRD.new()
	display_texture.texture_rd_rid = _display
	_ok = true
	return true


func update_base(heights: PackedFloat32Array) -> void:
	if _ok:
		rd.texture_update(_base, 0, heights.to_byte_array())


func scroll(off: Vector2i) -> void:
	if not _ok:
		return
	var push := PackedInt32Array([GRID, off.x, off.y, 0]).to_byte_array()
	_dispatch("sand_copy", [_image_uniform(_tex[_current], 0),
		_image_uniform(_tex[1 - _current], 1)], push)
	_current = 1 - _current


## ops: flat float list, 8 per op. Runs apply + relaxation + display copy.
func tick(ops: PackedFloat32Array, op_count: int, repose_h: float,
		flow: float, decay: float) -> void:
	if not _ok:
		return
	if op_count > 0:
		rd.buffer_update(_ops_buffer, 0, ops.size() * 4, ops.to_byte_array())
		var push := PackedByteArray()
		push.append_array(PackedInt32Array([GRID, op_count]).to_byte_array())
		push.append_array(PackedFloat32Array([MAX_DELTA, 0.0]).to_byte_array())
		_dispatch("sand_apply", [
			_image_uniform(_tex[_current], 0),
			_sampler_uniform(_mask_atlas, 1),
			_buffer_uniform(_ops_buffer, 2),
		], push)
	for i in RELAX_PER_FRAME:
		var push2 := PackedByteArray()
		push2.append_array(PackedInt32Array([GRID]).to_byte_array())
		push2.append_array(PackedFloat32Array([repose_h, flow,
			decay if i == 0 else 0.0]).to_byte_array())
		_dispatch("sand_relax", [
			_image_uniform(_tex[_current], 0),
			_image_uniform(_tex[1 - _current], 1),
			_sampler_uniform(_base, 2),
		], push2)
		_current = 1 - _current
	var push3 := PackedInt32Array([GRID, 0, 0, 0]).to_byte_array()
	_dispatch("sand_copy", [_image_uniform(_tex[_current], 0),
		_image_uniform(_display, 1)], push3)


func _dispatch(shader_name: String, uniforms: Array, push: PackedByteArray) -> void:
	var pl: Array = _pipeline[shader_name]
	var uset := rd.uniform_set_create(uniforms, pl[0], 0)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pl[1])
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	rd.compute_list_set_push_constant(cl, push, push.size())
	@warning_ignore("integer_division")
	rd.compute_list_dispatch(cl, (GRID + 7) / 8, (GRID + 7) / 8, 1)
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
