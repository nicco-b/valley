class_name WaveReference
extends RefCounted
## The tier-2.5 wave kernel as a pure CPU function — the SPEC the GPU
## implements (the sand discipline: game/shaders/compute/wave_step.glsl
## must behave exactly like this). Scene-tested for propagation, decay,
## and boundedness; if the GLSL ever drifts from this, the tests are
## the argument about which one is wrong.

const K := 0.18  # must match WaveGpu.K
const DAMP := 0.985  # must match WaveGpu.DAMP


## One damped Verlet wave step on an n×n field (zero-gradient borders).
static func step(prev: PackedFloat32Array, curr: PackedFloat32Array,
		n: int) -> PackedFloat32Array:
	var next := PackedFloat32Array()
	next.resize(n * n)
	for z in n:
		for x in n:
			var i := z * n + x
			var c := curr[i]
			var lap := (curr[i + 1] if x < n - 1 else c) \
				+ (curr[i - 1] if x > 0 else c) \
				+ (curr[i + n] if z < n - 1 else c) \
				+ (curr[i - n] if z > 0 else c) - 4.0 * c
			next[i] = (2.0 * c - prev[i] + K * lap) * DAMP
	return next


static func energy(field: PackedFloat32Array) -> float:
	var e := 0.0
	for v in field:
		e += v * v
	return e
