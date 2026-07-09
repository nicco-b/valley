extends Node
## THROWAWAY foam-channel readback (S2 debug): splat one stride-sized op
## into a bare WaveGpu, tick, and print the field's max height/foam per
## second — proves the G channel deposits, decays, and drifts on real
## hardware. Needs a RenderingDevice (vulkan, windowed).

var _gpu: WaveGpu
var _ops := PackedFloat32Array()
var _t := 0


func _ready() -> void:
	_gpu = WaveGpu.new()
	if not _gpu.setup():
		print("[foam_dbg] no RD")
		get_tree().quit(1)
		return
	_ops.resize((WaveGpu.MAX_OPS + WaveGpu.FOAM_OPS) * 4)


func _process(delta: float) -> void:
	_t += 1
	var op_count := 0
	var foam_count := 0
	if _t == 5:
		_ops[0] = 512.0
		_ops[1] = 512.0
		_ops[2] = 7.2  # 0.9m at 12.5cm texels
		_ops[3] = -0.0245  # a hound stride's dent
		op_count = 1
		_ops[WaveGpu.MAX_OPS * 4] = 400.0
		_ops[WaveGpu.MAX_OPS * 4 + 1] = 400.0
		_ops[WaveGpu.MAX_OPS * 4 + 2] = 19.2  # a 2.4m breaker curd
		_ops[WaveGpu.MAX_OPS * 4 + 3] = 0.22
		foam_count = 1
	_gpu.tick(_ops, op_count, foam_count, exp(-delta / 6.0),
		Vector2(0.5, 0.0), delta)
	if _t % 30 == 0 or _t == 6:
		var img := _gpu.display_texture.get_image()
		var maxf_h := 0.0
		var maxf_g := 0.0
		var cx := 0.0
		var tot := 0.0
		for y in range(380, 540, 4):
			for x in range(380, 700, 2):
				var c := img.get_pixel(x, y)
				maxf_h = maxf(maxf_h, absf(c.r))
				maxf_g = maxf(maxf_g, c.g)
				cx += c.g * x
				tot += c.g
		print("[foam_dbg] t=%d fmt=%d |h|max=%.4f gmax=%.4f gcx=%.1f" % [
			_t, img.get_format(), maxf_h, maxf_g, (cx / tot if tot > 0.0 else -1.0)])
	if _t >= 181:
		get_tree().quit()
