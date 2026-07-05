class_name WaveGpu
extends RefCounted
## GPU driver for tier 2.5, the wave field (DECISIONS 2026-07-04: water's
## ceiling is the heightfield; realism lives in surface displacement).
## A 512² damped wave-equation grid in a window that follows the focus:
## disturbances ring outward, the water shaders displace their vertices
## by the display texture. Presentation-only, like every GPU tier.

const GRID := 512
const REGION := 64.0  # meters — 12.5cm texels, ripple-scale
const MAX_OPS := 32
const K := 0.18  # c²dt²/dx², stable < 0.5
const DAMP := 0.975  # settles faster: calm is what makes reactions legible

var display_texture: Texture2DRD

var _rd: RenderingDevice
var _pipeline := {}
var _ring := []  # three r32f fields: indices rotate prev/curr/next
var _display: RID
var _ops_buffer: RID
var _i := 0  # ring position: prev = _i, curr = _i+1, next = _i+2 (mod 3)
var _ok := false


func setup() -> bool:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return false
	for shader_name in ["wave_splat", "wave_step", "wave_copy"]:
		var src: RDShaderFile = load("res://game/shaders/compute/%s.glsl" % shader_name)
		if src == null:
			return false
		var spirv := src.get_spirv()
		if spirv == null or spirv.compile_error_compute != "":
			push_error("[waves] compute compile: " + spirv.compile_error_compute)
			return false
		var shader := _rd.shader_create_from_spirv(spirv)
		_pipeline[shader_name] = [shader, _rd.compute_pipeline_create(shader)]
	var fmt := RDTextureFormat.new()
	fmt.width = GRID
	fmt.height = GRID
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	for i in 3:
		_ring.append(_rd.texture_create(fmt, RDTextureView.new()))
	_display = _rd.texture_create(fmt, RDTextureView.new())
	var zero := PackedFloat32Array()
	zero.resize(GRID * GRID)
	for t in _ring:
		_rd.texture_update(t, 0, zero.to_byte_array())
	var empty := PackedFloat32Array()
	empty.resize(MAX_OPS * 4)
	_ops_buffer = _rd.storage_buffer_create(empty.to_byte_array().size(),
		empty.to_byte_array())
	display_texture = Texture2DRD.new()
	display_texture.texture_rd_rid = _display
	_ok = true
	return true


## One frame: stamp queued disturbances into curr, step the wave
## equation, rotate the ring, publish to the display texture.
func tick(ops: PackedFloat32Array, op_count: int) -> void:
	if not _ok:
		return
	var curr: RID = _ring[(_i + 1) % 3]
	if op_count > 0:
		_rd.buffer_update(_ops_buffer, 0, ops.size() * 4, ops.to_byte_array())
		var push := PackedByteArray()
		push.append_array(PackedInt32Array([GRID, op_count, 0, 0]).to_byte_array())
		_dispatch("wave_splat", [_image(curr, 0), _buffer(_ops_buffer, 1)], push)
	var push2 := PackedByteArray()
	push2.append_array(PackedInt32Array([GRID]).to_byte_array())
	push2.append_array(PackedFloat32Array([K, DAMP, 0.0]).to_byte_array())
	_dispatch("wave_step", [
		_image(_ring[_i % 3], 0),
		_image(curr, 1),
		_image(_ring[(_i + 2) % 3], 2),
	], push2)
	_i = (_i + 1) % 3
	_publish()


## Window moved: shift both live fields by the texel offset.
func scroll(off: Vector2i) -> void:
	if not _ok:
		return
	var push := PackedInt32Array([GRID, off.x, off.y, 0]).to_byte_array()
	var spare: RID = _ring[(_i + 2) % 3]
	for idx in [_i % 3, (_i + 1) % 3]:
		_dispatch("wave_copy", [_image(_ring[idx], 0), _image(spare, 1)], push)
		var t: RID = _ring[idx]
		_ring[idx] = spare
		spare = t
	_publish()


func _publish() -> void:
	var push := PackedInt32Array([GRID, 0, 0, 0]).to_byte_array()
	_dispatch("wave_copy", [_image(_ring[(_i + 1) % 3], 0), _image(_display, 1)], push)


func _dispatch(shader_name: String, uniforms: Array, push: PackedByteArray) -> void:
	var pl: Array = _pipeline[shader_name]
	var uset := _rd.uniform_set_create(uniforms, pl[0], 0)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, pl[1])
	_rd.compute_list_bind_uniform_set(cl, uset, 0)
	_rd.compute_list_set_push_constant(cl, push, push.size())
	@warning_ignore("integer_division")
	_rd.compute_list_dispatch(cl, (GRID + 7) / 8, (GRID + 7) / 8, 1)
	_rd.compute_list_end()
	_rd.free_rid(uset)


func _image(tex: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


func _buffer(buf: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buf)
	return u
