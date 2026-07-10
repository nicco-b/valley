extends Node
## SeaSwell (autoload): W1 ocean swell — the Watershed's open sea gets
## real waves. This node computes WHERE the wave energy is; the waves
## themselves are four Gerstner components summed in the water shader's
## vertex stage (near-free), displacing the sea meshes only. Amplitude/
## wavelength/direction come from the Elements: the local wind raises a
## base sea, and every traveling front radiates swell from its leading
## edge — full inside the band, decaying exponentially AHEAD of it, so
## heavy rollers reach the strand hours before the rain (the herald:
## free foreshadowing). Presentation only, like WaterWaves: a stateless
## function of (time, wind, fronts) — never saved, never fingerprinted,
## off headless. Physics and sims keep reading the flat
## Terrain.sea_surface(); swimming rides mean water at W1.
## W2 adds the shore: water_bodies bakes real bathymetry into the sea
## meshes and the shader shoals/breaks the swell against it — this node
## carries the pure mirror math (shoal_gain/break_frac/break_depth) so
## the surf criterion is scene-testable and the Toolkit can report the
## live breaker depth-band.

const SWELL_MAX := 0.95    # meters of amplitude a full storm earns
const BASE_AMP := 0.05     # a dead-calm sea never goes glassy-flat
const WIND_AMP := 0.30     # the local wind's own sea at wind=1
const LEN_CALM := 24.0     # primary wavelength, calm ripple swell
const LEN_STORM := 60.0    # primary wavelength at full storm energy
const HERALD_M := 5200.0   # e-fold reach of swell AHEAD of a front's edge
const WAKE_M := 2200.0     # swell decay behind a spent front's trailing edge
const EASE := 0.4          # per-second approach (presentation smoothing)

# W2 shoaling — the SHADER-MIRROR constants. water.gdshader owns the
# per-vertex copy of this math (SURF_GAMMA/SHOAL_MAX/DEPTH_MIN there);
# keep both in lockstep or the Toolkit's surf line will lie.
const SURF_GAMMA := 0.78   # break when waveheight/depth tops this
const SHOAL_MAX := 1.7     # Green's-law amplitude gain cap
const DEPTH_MIN := 0.05    # the water column never divides by zero
const PRIMARY_SHARE := 0.44  # the primary Gerstner component's amp share

# S3 buoyancy mirror (PLAN_SUBSTANCES) — the four Gerstner components
# water.gdshader sums in its vertex stage, replayed on the CPU so a floater
# rides the SAME surface the eye sees: analytic swell, never a GPU readback
# (a blocking probe costs 0.17ms; this is 7.6µs/floater — buoy_bench). The
# DEEP-water form (align=0, tanh(kd)->1) — the swell is the meal; a shore
# floater that ever needs the shoaled height reads shoal_gain() on top.
# Keep LSC/ASC/ROT/TROCHOID/GRAV in LOCKSTEP with water.gdshader's vertex()
# (lsc/asc/rot[] + the 3.0 trochoid + sqrt(9.8*k)) or a floater bobs where
# no wave is painted — the same lockstep the shoaling consts above keep.
const LSC := [1.0, 0.62, 0.38, 0.23]   # per-component wavelength scale
const ASC := [0.44, 0.28, 0.17, 0.11]  # per-component amplitude share
const ROT := [0.0, 0.35, -0.42, 0.83]  # per-component heading rotation (rad)
const SWELL_STEP := 3.0    # sea-mesh vertex spacing — the shader's grid gate
const TROCHOID := 3.0      # deep-water horizontal gather (the shader's 3.0)
const GRAV := 9.8          # the shader's g (NOT 9.81 — mirror the vertex math)
const INVERT_ITERS := 2    # fixed-point passes to undo the horizontal displace

var enabled := false
var force_amp := -1.0      # Toolkit knob: >= 0 pins the amplitude (meters)
var force_surf := -1.0     # Toolkit knob: >= 0 pins the breaker foam boost
var amp := 0.0             # live eased amplitude, meters
# Last-pushed shader values (perf): set-on-change guards for _process.
var _set_amp := -1e9
var _set_len := -1e9
var _set_dir := Vector2.INF
var _set_boost := -1e9
var wavelength := LEN_CALM # live eased primary wavelength, meters
var direction := Vector2(1.0, 0.0)  # live eased travel direction
var source := "wind"       # what owns the swell right now (Toolkit line)


func _ready() -> void:
	# Same gate as the GPU water tiers: headless has no swell to show.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	enabled = true


func _process(delta: float) -> void:
	var t := compute(Weather.fronts, _focus_xz(), Weather.wind, Weather.wind_dir)
	source = String(t.source)
	var target_amp := float(t.amp)
	if force_amp >= 0.0:
		target_amp = force_amp
		source = "FORCED"
	var blend := 1.0 - exp(-EASE * delta)
	amp = lerpf(amp, target_amp, blend)
	wavelength = lerpf(wavelength, float(t.len), blend)
	var target_dir: Vector2 = t.dir
	direction = direction.rotated(direction.angle_to(target_dir) * blend).normalized()
	# Push to the shader only on visible change (perf 2026-07-09): the
	# eases converge between weather shifts, and a sub-millimeter step is
	# nothing the painting can show. The live vars above stay exact —
	# only the redundant RenderingServer traffic is skipped.
	if absf(amp - _set_amp) > 1e-4:
		_set_amp = amp
		RenderingServer.global_shader_parameter_set("swell_amp", amp)
	if absf(wavelength - _set_len) > 1e-3:
		_set_len = wavelength
		RenderingServer.global_shader_parameter_set("swell_len", wavelength)
	if direction.distance_squared_to(_set_dir) > 1e-8:
		_set_dir = direction
		RenderingServer.global_shader_parameter_set("swell_dir", direction)
	var boost := force_surf if force_surf >= 0.0 else 1.0
	if boost != _set_boost:
		_set_boost = boost
		RenderingServer.global_shader_parameter_set("surf_boost", boost)


## The energy math, pure + deterministic (scene-tested): swell at `focus`
## given a front list. A front's swell is its wind energy squared (gales
## raise big dry seas; drizzle barely stirs), at full strength inside the
## band, e-folding over HERALD_M ahead of the leading edge — swell
## outruns its weather — and dying over WAKE_M behind the trailing edge.
## The strongest arrival sets the direction (its travel heading); the
## local wind keeps a base sea under everything.
func compute(fronts: Array, focus: Vector2, wind_local: float,
		wind_dir: Vector2) -> Dictionary:
	var best := 0.0
	var best_dir := wind_dir
	var best_src := "wind"
	for f: Dictionary in fronts:
		var kind: Dictionary = Weather.KINDS[String(f.kind)]
		var e := float(kind.wind)
		if e <= 0.2:
			continue  # calm/overcast bands raise no sea worth naming
		var energy := SWELL_MAX * e * e
		var s: float = focus.x * float(f.dx) + focus.y * float(f.dz)
		var reach := 1.0
		if s > float(f.edge):
			reach = exp(-(s - float(f.edge)) / HERALD_M)
		elif s <= float(f.edge) - float(f.width):
			reach = exp(-(float(f.edge) - float(f.width) - s) / WAKE_M)
		var a := energy * reach
		if a > best:
			best = a
			best_dir = Vector2(float(f.dx), float(f.dz)).normalized()
			best_src = String(f.kind)
	var base := BASE_AMP + WIND_AMP * clampf(wind_local, 0.0, 1.0)
	var total := maxf(base, best)
	return {"amp": total,
		"len": lerpf(LEN_CALM, LEN_STORM, clampf(total / SWELL_MAX, 0.0, 1.0)),
		"dir": best_dir if best > base else wind_dir.normalized(),
		"source": best_src if best > base else "wind"}


## W2 shoaling math, pure + deterministic (scene-tested; shader-mirror —
## water.gdshader computes the same per vertex). Amplitude gain as a wave
## of `wavelength_m` climbs into `depth` meters of water: 1.0 in the deep
## (tanh(kd) -> 1: the open sea is untouched), rising by Green's law as
## the wave feels the bottom, capped at SHOAL_MAX.
func shoal_gain(wavelength_m: float, depth: float) -> float:
	var k := TAU / maxf(wavelength_m, 0.1)
	var tk := tanh(k * maxf(depth, DEPTH_MIN))
	return clampf(pow(maxf(tk, 0.02), -0.25), 1.0, SHOAL_MAX)


## The surf criterion: shoaled waveheight over the breakable column.
## >= 1.0 means this depth BREAKS a swell of `amp_m` (one component's
## amplitude, meters) — the breaker line is this function's level set.
func break_frac(amp_m: float, wavelength_m: float, depth: float) -> float:
	var a_s := amp_m * shoal_gain(wavelength_m, depth)
	return a_s / (0.5 * SURF_GAMMA * maxf(depth, DEPTH_MIN))


## The deepest water the primary swell component breaks in (bisection on
## break_frac's monotone depth axis) — the Toolkit's surf line.
func break_depth(amp_m: float, wavelength_m: float) -> float:
	var lo := DEPTH_MIN
	var hi := 60.0
	if break_frac(amp_m, wavelength_m, hi) >= 1.0:
		return hi
	for i in 40:
		var mid := (lo + hi) * 0.5
		if break_frac(amp_m, wavelength_m, mid) >= 1.0:
			lo = mid
		else:
			hi = mid
	return lo


## The analytic sea surface at world (x, z) and time `t` seconds: the CPU
## mirror of water.gdshader's deep-water Gerstner sum (S3 buoyancy). Returns
## Vector3(slope_x, height, slope_z) — `height` is meters ABOVE mean water
## (add Terrain.sea_surface() for the absolute Y); the slope pair is the
## shader's `swell_grad`, the tilt a hull leans into. The horizontal
## trochoid the shader adds to VERTEX.xz is INVERTED here (INVERT_ITERS
## fixed-point passes) so the answer is the surface at a FIXED point — what
## a moored floater actually rides. Pure + deterministic (scene-tested
## against pinned shader cases); reads the same live eased amp/wavelength/
## direction the shader's globals carry. Flat (zero) below the shader's
## 0.001m swell gate, so a dawn-calm sea sits floaters level.
# Per-component derived cache (dx, dy, k, w, a for each ACTIVE component):
# every floater in a frame reads the same eased amp/wavelength/direction, so
# the rotated()/sqrt/gate work is done ONCE per swell change, not 5× per
# floater. This is what buys the 0.25ms/30-floater law (the plan's 216µs
# bench precomputed the same way — recomputing them per call doubled it).
var _cn := 0
var _cdx := PackedFloat32Array([0, 0, 0, 0])
var _cdy := PackedFloat32Array([0, 0, 0, 0])
var _ck := PackedFloat32Array([0, 0, 0, 0])
var _cw := PackedFloat32Array([0, 0, 0, 0])
var _ca := PackedFloat32Array([0, 0, 0, 0])
var _c_amp := -1.0
var _c_len := -1.0
var _c_dir := Vector2.INF


func _prep() -> void:
	if amp == _c_amp and wavelength == _c_len and direction == _c_dir:
		return
	_c_amp = amp
	_c_len = wavelength
	_c_dir = direction
	_cn = 0
	for i in 4:
		var wl: float = wavelength * LSC[i]
		var a: float = amp * ASC[i] \
				* smoothstep(SWELL_STEP * 2.0, SWELL_STEP * 3.0, wl)
		if a < 1e-4:
			continue  # a component the sea mesh can't carry — the shader's gate
		var d: Vector2 = direction.rotated(ROT[i])
		var k := TAU / wl
		_cdx[_cn] = d.x
		_cdy[_cn] = d.y
		_ck[_cn] = k
		_cw[_cn] = sqrt(GRAV * k)
		_ca[_cn] = a
		_cn += 1


func probe_at(x: float, z: float, t: float) -> Vector3:
	if amp < 0.001:
		return Vector3.ZERO
	_prep()
	# Invert the horizontal displacement: find the rest point p whose
	# displaced world position p + hoff(p) lands on (x, z), so height(p) is
	# the surface here. hoff(p) = -sum d * TROCHOID * a * cos(phase) — the
	# shader's `hoff` in the deep, so p = (x,z) - hoff(p) iterated.
	var px := x
	var pz := z
	for _it in INVERT_ITERS:
		var hx := 0.0
		var hz := 0.0
		for j in _cn:
			var c := cos(_ck[j] * (_cdx[j] * px + _cdy[j] * pz) - _cw[j] * t)
			var q: float = TROCHOID * _ca[j] * c
			hx -= _cdx[j] * q
			hz -= _cdy[j] * q
		px = x - hx
		pz = z - hz
	# Height + surface slope at the resolved rest point.
	var h := 0.0
	var gx := 0.0
	var gz := 0.0
	for j in _cn:
		var ph := _ck[j] * (_cdx[j] * px + _cdy[j] * pz) - _cw[j] * t
		h += _ca[j] * sin(ph)
		var kac: float = _ck[j] * _ca[j] * cos(ph)
		gx += _cdx[j] * kac
		gz += _cdy[j] * kac
	return Vector3(gx, h, gz)


## The swell height (meters above mean water) at world (x, z), time `t` —
## the buoyancy scalar. See probe_at() for the full surface state.
func surface_at(x: float, z: float, t: float) -> float:
	return probe_at(x, z, t).y


## Toolkit: the open sea's state in one line — swell energy plus the
## surf band it earns (breakers live shoreward of that depth).
func summary() -> String:
	if not enabled:
		return "off (headless)"
	var surf := break_depth(amp * PRIMARY_SHARE, wavelength)
	# S3 buoyancy hook: how many floaters ride this swell right now (0 until
	# a raft/net card is placed) — the Toolkit's echo that the mirror is live.
	var floaters := "" if FloatBody.alive == 0 else "  floaters=%d" % FloatBody.alive
	return "%s  amp=%.2fm  L=%.0fm  dir=(%.2f, %.2f)  surf<=%.1fm%s%s%s" % [
		source, amp, wavelength, direction.x, direction.y, surf, floaters,
		"" if force_amp < 0.0 else "  (FORCED amp)",
		"" if force_surf < 0.0 else "  (FORCED surf x%.1f)" % force_surf]


func _focus_xz() -> Vector2:
	if Toolkit.active:
		var p := Toolkit.cam_position()
		return Vector2(p.x, p.z)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		return Vector2(player.global_position.x, player.global_position.z)
	return Vector2.ZERO
