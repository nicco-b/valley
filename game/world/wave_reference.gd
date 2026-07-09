class_name WaveReference
extends RefCounted
## The tier-2.5 wave kernel as a pure CPU function — the SPEC the GPU
## implements (the sand discipline: game/shaders/compute/wave_step.glsl
## must behave exactly like this). Scene-tested for propagation, decay,
## and boundedness; if the GLSL ever drifts from this, the tests are
## the argument about which one is wrong.
## S2 adds the foam channel's spec: deposit law (wave_splat.glsl),
## time-based decay + drift advection + crest re-deposit (wave_step.glsl).

const K := 0.18  # must match WaveGpu.K
const DAMP := 0.975  # must match WaveGpu.DAMP
# Foam constants — must match wave_splat.glsl / wave_step.glsl.
const FOAM_FLOOR := 0.004  # meters of dent that deposit nothing (chop)
const FOAM_GAIN := 25.0    # foam per meter of dent past the floor
const CREST_H := 0.05      # meters of |height| before a crest feeds foam
const CREST_GAIN := 6.0    # foam/sec deposited by a full-rail crest


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
			next[i] = clampf((2.0 * c - prev[i] + K * lap) * DAMP, -0.2, 0.2)
	return next


## The splat's foam deposit law (wave_splat.glsl): a disturbance of
## `strength_m` deposits this much foam at its center. Pure — chop under
## the floor leaves the water clean; a splash saturates.
static func foam_deposit(strength_m: float) -> float:
	return maxf(0.0, absf(strength_m) - FOAM_FLOOR) * FOAM_GAIN


## One foam step (wave_step.glsl's G channel): pull back along `drift`
## (texels; bilinear, clamped borders), decay by `decay_f` — the caller
## computes exp(-dt/τ), so decay is a function of TIME, never of steps —
## then let travelling crests in `heights` re-deposit over `dt` seconds.
static func foam_step(foam: PackedFloat32Array, heights: PackedFloat32Array,
		n: int, decay_f: float, drift: Vector2, dt: float) -> PackedFloat32Array:
	var next := PackedFloat32Array()
	next.resize(n * n)
	for z in n:
		for x in n:
			var i := z * n + x
			var fm: float
			if drift == Vector2.ZERO:
				fm = foam[i]
			else:
				var sx := x - drift.x
				var sz := z - drift.y
				var fx := floorf(sx)
				var fz := floorf(sz)
				var rx := sx - fx
				var rz := sz - fz
				var x0 := clampi(int(fx), 0, n - 1)
				var x1 := clampi(int(fx) + 1, 0, n - 1)
				var z0 := clampi(int(fz), 0, n - 1)
				var z1 := clampi(int(fz) + 1, 0, n - 1)
				fm = lerpf(
					lerpf(foam[z0 * n + x0], foam[z0 * n + x1], rx),
					lerpf(foam[z1 * n + x0], foam[z1 * n + x1], rx), rz)
			fm = fm * decay_f \
				+ maxf(0.0, absf(heights[i]) - CREST_H) * CREST_GAIN * dt
			next[i] = clampf(fm, 0.0, 1.0)
	return next


static func energy(field: PackedFloat32Array) -> float:
	var e := 0.0
	for v in field:
		e += v * v
	return e
