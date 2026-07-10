extends SceneTree
## THROWAWAY probe (PLAN_SUBSTANCES S3 measurement — proves the price, not a
## feature). Prices analytic buoyancy: the 4-component Gerstner sum mirrored
## from water.gdshader (2 fixed-point inversion passes to undo the horizontal
## trochoid), sampled at floater probe points. Self-contained and headless-
## safe — the algorithm here is SeaSwell.surface_at with its per-component
## cache (whose CORRECTNESS scene_tests._test_buoyancy pins in autoload
## context; sea_swell can't load under `-s` because its _process names the
## Weather autoload). Every floater in a frame reads one eased swell, so the
## rotated()/sqrt/gate work is precomputed ONCE — mirrored here in _init.
## The law: well under 7.6µs per floater, a 30-floater harbor under 0.25ms.
##   godot --headless -s tests/buoy_bench.gd

# In LOCKSTEP with SeaSwell (LSC/ASC/ROT/SWELL_STEP/TROCHOID/GRAV/iters).
const LSC := [1.0, 0.62, 0.38, 0.23]
const ASC := [0.44, 0.28, 0.17, 0.11]
const ROT := [0.0, 0.35, -0.42, 0.83]
const SWELL_STEP := 3.0
const TROCHOID := 3.0
const GRAV := 9.8
const INVERT_ITERS := 2

const PROBE_SETS := [1, 8, 30]  # floaters (each: 4 footprint corners + center)
const PROBES_PER := 5
const REPS := 2000

# Plausible storm swell so every component is active (no gate skips).
var _amp := 0.8
var _len := 55.0
var _dir := Vector2(0.72, 0.69).normalized()
# Per-component cache (SeaSwell._prep's mirror).
var _n := 0
var _dx := PackedFloat32Array([0, 0, 0, 0])
var _dz := PackedFloat32Array([0, 0, 0, 0])
var _k := PackedFloat32Array([0, 0, 0, 0])
var _w := PackedFloat32Array([0, 0, 0, 0])
var _a := PackedFloat32Array([0, 0, 0, 0])


func _init() -> void:
	for i in 4:
		var wl: float = _len * LSC[i]
		var a: float = _amp * ASC[i] \
				* smoothstep(SWELL_STEP * 2.0, SWELL_STEP * 3.0, wl)
		if a < 1e-4:
			continue
		var d: Vector2 = _dir.rotated(ROT[i])
		var k := TAU / wl
		_dx[_n] = d.x
		_dz[_n] = d.y
		_k[_n] = k
		_w[_n] = sqrt(GRAV * k)
		_a[_n] = a
		_n += 1
	for n_v in PROBE_SETS:
		_bench(int(n_v))
	quit()


func surface_at(x: float, z: float, t: float) -> float:
	var px := x
	var pz := z
	for _it in INVERT_ITERS:
		var hx := 0.0
		var hz := 0.0
		for j in _n:
			var c := cos(_k[j] * (_dx[j] * px + _dz[j] * pz) - _w[j] * t)
			var q: float = TROCHOID * _a[j] * c
			hx -= _dx[j] * q
			hz -= _dz[j] * q
		px = x - hx
		pz = z - hz
	var h := 0.0
	for j in _n:
		h += _a[j] * sin(_k[j] * (_dx[j] * px + _dz[j] * pz) - _w[j] * t)
	return h


func _bench(floaters: int) -> void:
	var pts := floaters * PROBES_PER
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for r in REPS:
		var t := r * 0.016
		for i in pts:
			acc += surface_at(float(i * 7 % 53), float(i * 13 % 47), t)
	var us := Time.get_ticks_usec() - t0
	print("BUOY_BENCH floaters=%d probes=%d us_per_frame=%.2f (acc=%f)" % [
		floaters, pts, float(us) / REPS, acc])
