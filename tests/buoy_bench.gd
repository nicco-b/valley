extends SceneTree
## THROWAWAY probe (plan/substances, PLAN_SUBSTANCES measurement).
## Prices CPU-side analytic buoyancy: evaluating the W1/W2 Gerstner sum
## (4 components, the shader's math mirrored) at floater probe points,
## with 2 fixed-point iterations to undo the horizontal Gerstner
## displacement (height-at-a-fixed-x needs the inverse). Headless-safe.
##   godot --headless -s tests/buoy_bench.gd

const COMPONENTS := 4
const ITERS := 2          # fixed-point inversion passes
const PROBE_SETS := [1, 8, 30]  # floaters (raft=4 probes + 1 center each)
const PROBES_PER := 5
const REPS := 2000

var _wl := PackedFloat32Array()
var _amp := PackedFloat32Array()
var _dx := PackedFloat32Array()
var _dz := PackedFloat32Array()
var _spd := PackedFloat32Array()

func _init() -> void:
	# Plausible W1 spectrum (values shaped like the shader's bands).
	var base_dir := Vector2(0.72, 0.69).normalized()
	for i in COMPONENTS:
		var wl := 26.0 / (1.0 + 0.7 * i)
		_wl.append(wl)
		_amp.append(0.35 / (1.0 + 0.9 * i))
		var rot := 0.35 * (i - 1.5)
		var d := base_dir.rotated(rot)
		_dx.append(d.x)
		_dz.append(d.y)
		_spd.append(sqrt(9.81 * wl / TAU))
	for n_v in PROBE_SETS:
		var n: int = n_v
		_bench(n)
	quit()

func surface_at(x: float, z: float, t: float) -> float:
	# Invert the horizontal displacement: iterate p so that p + D(p) = x.
	var px := x
	var pz := z
	for _i in ITERS:
		var ox := 0.0
		var oz := 0.0
		for c in COMPONENTS:
			var k := TAU / _wl[c]
			var ph := k * (_dx[c] * px + _dz[c] * pz - _spd[c] * t)
			var s := sin(ph)
			var q := 0.6 * _amp[c]
			ox += q * _dx[c] * cos(ph)
			oz += q * _dz[c] * cos(ph)
			if _i == ITERS - 1:
				pass
			s = s  # keep tight loop shape honest
		px = x - ox
		pz = z - oz
	var h := 0.0
	for c in COMPONENTS:
		var k := TAU / _wl[c]
		var ph := k * (_dx[c] * px + _dz[c] * pz - _spd[c] * t)
		h += _amp[c] * sin(ph)
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
