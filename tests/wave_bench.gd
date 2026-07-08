extends Node
## THROWAWAY probe (plan/substances, PLAN_SUBSTANCES measurement).
## Times the SHIPPED tier-2.5 wave kernel (wave_step.glsl) on a local
## RenderingDevice at several grid sizes, plus the cost of a tiny
## blocking readback (the buoyancy-probe stall question).
## Run WINDOWED (local RD does not exist headless):
##   godot --path . --write-movie /tmp/wb.avi --fixed-fps 15 \
##     res://tests/wave_bench.tscn   (Movie Maker recipe, window minimized)
## Deliberately touches no sim; quits itself.

const GRIDS := [512, 1024, 2048]
const STEPS := 240  # dispatches per timing block

var _frames := 0
var _done := false

func _ready() -> void:
	get_window().mode = Window.MODE_MINIMIZED

func _process(_delta: float) -> void:
	# Wait a few frames: dispatching compute during app launch races
	# AppKit/Metal init and aborts (the placement_probe lesson).
	_frames += 1
	if _frames < 8 or _done:
		return
	_done = true
	_run()
	get_tree().quit()

func _run() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		print("WAVE_BENCH: no local RenderingDevice (are we headless?)")
		return
	print("WAVE_BENCH device=", rd.get_device_name())
	var shader_file: RDShaderFile = load("res://game/shaders/compute/wave_step.glsl")
	var spirv := shader_file.get_spirv()
	var shader := rd.shader_create_from_spirv(spirv)

	for grid_v in GRIDS:
		var grid: int = grid_v
		_bench_grid(rd, shader, grid)

	# Readback stall: a 4-float buffer_get_data after one dispatch —
	# the price of ONE blocking buoyancy probe per frame.
	_bench_readback(rd)
	rd.free()

func _make_tex(rd: RenderingDevice, grid: int) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = grid
	fmt.height = grid
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var data := PackedByteArray()
	data.resize(grid * grid * 4)
	return rd.texture_create(fmt, RDTextureView.new(), [data])

func _uniform(binding: int, tex: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u

func _bench_grid(rd: RenderingDevice, shader: RID, grid: int) -> void:
	var tex: Array[RID] = [_make_tex(rd, grid), _make_tex(rd, grid), _make_tex(rd, grid)]
	# Three rotating uniform sets (prev, curr, next) like wave_gpu ping-pongs.
	var sets: Array[RID] = []
	for i in 3:
		sets.append(rd.uniform_set_create([
			_uniform(0, tex[i % 3]), _uniform(1, tex[(i + 1) % 3]), _uniform(2, tex[(i + 2) % 3]),
		], shader, 0))
	var push := PackedByteArray()
	push.resize(16)
	push.encode_s32(0, grid)
	push.encode_float(4, 0.4)   # k, stable
	push.encode_float(8, 0.998) # damp
	var groups := (grid + 7) / 8
	# Warmup
	for i in 16:
		_dispatch(rd, shader, sets[i % 3], push, groups)
	rd.submit()
	rd.sync()
	# Timed
	var t0 := Time.get_ticks_usec()
	for i in STEPS:
		_dispatch(rd, shader, sets[i % 3], push, groups)
	rd.submit()
	rd.sync()
	var us := Time.get_ticks_usec() - t0
	print("WAVE_BENCH grid=%d steps=%d total_ms=%.2f ms_per_step=%.4f" % [
		grid, STEPS, us / 1000.0, us / 1000.0 / STEPS])
	for s in sets:
		rd.free_rid(s)
	for t in tex:
		rd.free_rid(t)

func _dispatch(rd: RenderingDevice, shader: RID, uset: RID, push: PackedByteArray, groups: int) -> void:
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipeline(rd, shader))
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	rd.compute_list_set_push_constant(cl, push, push.size())
	rd.compute_list_dispatch(cl, groups, groups, 1)
	rd.compute_list_end()

var _pipe := RID()
func _pipeline(rd: RenderingDevice, shader: RID) -> RID:
	if not _pipe.is_valid():
		_pipe = rd.compute_pipeline_create(shader)
	return _pipe

func _bench_readback(rd: RenderingDevice) -> void:
	var buf := rd.storage_buffer_create(16, PackedByteArray([0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0]))
	var t0 := Time.get_ticks_usec()
	var n := 60
	for i in n:
		rd.submit()
		rd.sync()
		var _bytes := rd.buffer_get_data(buf)
	var us := Time.get_ticks_usec() - t0
	print("WAVE_BENCH readback_16B_x%d total_ms=%.2f ms_each=%.4f" % [n, us / 1000.0, us / 1000.0 / n])
	rd.free_rid(buf)
