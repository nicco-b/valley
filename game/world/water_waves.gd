extends Node
## WaterWaves (autoload): tier 2.5 of the water canon — the wave field
## that makes surfaces MOVE (the Watershed). A 1024² wave-equation window
## follows the player; wading bodies ring the water — the player AND the
## wildlife (PLAN_SUBSTANCES S1: everything that moves rings the water) —
## storm rain pocks it, wind keeps a restless chop, swimmers tow a wake,
## and deep entries splash one big ring; the pond/river shaders displace
## their vertices by the field. S2 (the water remembers): the field's
## second channel is FOAM — every disturbance deposits it, the breaker
## band stipples it where the surf criterion trips, it drifts with the
## window's one current (swell ashore, river downstream) and dies on a
## TIME constant (foam_decay ★, seconds — never per-step). Presentation
## only: never saved, never fingerprinted, off headless. Randomness here
## is cosmetic and uses a local RNG — the deterministic Rng streams are
## for canonical sims only; body sources carry NO randomness at all (pure
## functions of sim-owned position and speed, the flora phase-hash
## discipline).

const REANCHOR := 8.0
const WADE_INTERVAL := 0.12
const WADE_RADIUS := 0.9  # meters, a player-sized stride ring
const WADE_STRENGTH := 0.035  # meters of dent per stride
# Ambient rates are per m² so the stipple DENSITY survives the ★ window
# knob (26 drops/sec across the old 64m window, same sky at any size).
const RAIN_PER_M2 := 26.0 / (64.0 * 64.0)  # drop splats/sec/m² in a storm
const CHOP_PER_M2 := 2.5 / (64.0 * 64.0)  # wind ripple seeds/sec/m² at full wind
const SPLASH_RADIUS := 1.4  # meters, a player-sized entry ring
const WAKE_ASTERN := 1.1  # wake splats land this far behind the stroke
const WAKE_SIDE := 0.6  # ...swinging this far port/starboard, alternating
# S2 breaker-band foam: Monte-Carlo stipple — a few probe points per
# frame, deposited where the CPU surf mirror (SeaSwell.break_frac) says
# the swell breaks and the ground ahead rises (the lee gate, cheap).
const BREAKER_TRIES := 8  # probe points per frame
const BREAKER_MIN_AMP := 0.15  # swell below this raises no surf worth marking
const BREAKER_FOAM := 0.22  # foam deposited per hit (accumulates into the band)
const BREAKER_RADIUS := 2.4  # meters, one painted curd
# The surf strip is ~1% of the window (measured: 6/600 uniform samples) —
# uniform tries starve it. Importance-sample: 2/3 of tries land near the
# LAST hit (the band is locally a strip through it), 1/3 keep exploring
# so new stretches join and the band follows the window.
const BREAKER_NEAR := 14.0  # meters of scatter around the last hit
# S2 drift: foam rides the window's one current — the swell's travel
# where it breaks (shoreward by the lee gate), the river's current under
# a swimmer. One vector for the whole window: approximate, paints true.
const DRIFT_SWELL := 1.1  # m/s of foam ride at full storm swell
const DRIFT_MAX := 1.5  # m/s cap on the summed window drift

# ★ Foam decay (PLAN_SUBSTANCES S2): the taste knob — seconds for a
# deposit to fall to 1/e. ~6s reads as memory without wearing a scum;
# the probe A/B (WAVE_FOAM=n) re-shoots it. TIME-based by law: the
# kernel gets exp(-dt/τ) each frame, so slow frames decay the same water.
var foam_decay := 6.0

var enabled := false
var _gpu: WaveGpu
var _anchor := Vector2.INF
var _ops := PackedFloat32Array()
var _op_count := 0
var _foam_count := 0
var _last_ops := 0  # sources that spoke last frame (the Toolkit WAVES line)
var _last_foam := 0  # foam deposits that landed last frame (Toolkit)
var _drift := Vector2.ZERO  # last frame's window current, m/s (Toolkit)
var _wade_accum := 0.0
var _stroke := 0  # swim stride parity: the wake alternates sides by count, not RNG
var _emit_accum := 0.0
var _band_seed := Vector2.INF  # last breaker hit — biases the next tries
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_gpu = WaveGpu.new()
	enabled = _gpu.setup()
	if not enabled:
		set_process(false)
		return
	_ops.resize((WaveGpu.MAX_OPS + WaveGpu.FOAM_OPS) * 4)
	_rng.randomize()
	RenderingServer.global_shader_parameter_set("wave_map", _gpu.display_texture)
	RenderingServer.global_shader_parameter_set("wave_size", WaveGpu.REGION)


## Ring the water at a world point (wading feet, landings, dropped things).
func disturb(world_xz: Vector2, radius_m: float, strength_m: float) -> void:
	if not enabled or not _anchor.is_finite() or _op_count >= WaveGpu.MAX_OPS:
		return
	var px := _to_px(world_xz)
	var texel := WaveGpu.REGION / WaveGpu.GRID
	var i := _op_count * 4
	_ops[i] = px.x
	_ops[i + 1] = px.y
	_ops[i + 2] = maxf(radius_m / texel, 1.5)
	_ops[i + 3] = -strength_m  # press down; the equation rings it back up
	_op_count += 1


## Deposit foam WITHOUT denting the water (S2) — the breaker band and any
## future foam-only speaker (swash tongues, waterfall plunge pools).
func deposit_foam(world_xz: Vector2, radius_m: float, amount: float) -> void:
	if not enabled or not _anchor.is_finite() or _foam_count >= WaveGpu.FOAM_OPS:
		return
	var px := _to_px(world_xz)
	var texel := WaveGpu.REGION / WaveGpu.GRID
	var i := (WaveGpu.MAX_OPS + _foam_count) * 4
	_ops[i] = px.x
	_ops[i + 1] = px.y
	_ops[i + 2] = maxf(radius_m / texel, 1.5)
	_ops[i + 3] = amount
	_foam_count += 1


func _to_px(world_xz: Vector2) -> Vector2:
	return ((world_xz - _anchor) / WaveGpu.REGION + Vector2(0.5, 0.5)) * WaveGpu.GRID


## A wading body's stride ring — pure, so the scene tests can pin the
## source law headless (the GPU field is off there). `dip` is how far the
## body rides below its dry stance (<= 0 on dry ground), `size` scales a
## body against the player's 1.0 (a hound is 0.7). Speed scales the dent;
## a standing body returns ZERO — still water for a still animal.
static func wade_ring(dip: float, speed: float, size: float) -> Vector2:
	if dip <= 0.0 or speed <= 1.0:
		return Vector2.ZERO
	return Vector2(WADE_RADIUS * size,
		WADE_STRENGTH * size * minf(speed / 3.5, 1.6))


## The one big ring a body entering deep water throws — splashdown
## (player.gd rings this on landing) and wildlife wading past its depth.
## The crown of spray is S6's business; the ring is S1's.
static func splash_ring(entry_speed: float, size: float) -> Vector2:
	return Vector2(SPLASH_RADIUS * size,
		clampf(0.02 + entry_speed * 0.012, 0.02, 0.09) * size)


## Droplet rings/sec across the live window — rain is the only term, so
## a calm sky rings nothing (pure; the Elements' rain is the one truth).
static func rain_rate(rain: float) -> float:
	return RAIN_PER_M2 * rain * WaveGpu.REGION * WaveGpu.REGION


## Wind-chop seeds/sec across the live window (pure, same law).
static func chop_rate(wind: float) -> float:
	return CHOP_PER_M2 * wind * WaveGpu.REGION * WaveGpu.REGION


## Toolkit: the window, who spoke to it last frame, and the foam state.
func summary() -> String:
	if not enabled:
		return "off (no RenderingDevice — headless or GL)"
	return "window=%.0fm @ %d²  sources=%d/%d  foam=%d/%d τ=%.1fs  drift=(%.2f, %.2f)m/s  anchor=(%.0f, %.0f)" % [
		WaveGpu.REGION, WaveGpu.GRID, _last_ops, WaveGpu.MAX_OPS,
		_last_foam, WaveGpu.FOAM_OPS, foam_decay,
		_drift.x, _drift.y, _anchor.x, _anchor.y]


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p: Vector3 = player.global_position
	var pxz := Vector2(p.x, p.z)
	if _anchor == Vector2.INF or pxz.distance_to(_anchor) > REANCHOR:
		var texel := WaveGpu.REGION / WaveGpu.GRID
		var new_anchor := pxz.snappedf(texel * 8.0)
		if _anchor.is_finite():
			_gpu.scroll(Vector2i(((new_anchor - _anchor) / texel).round()))
		_anchor = new_anchor
		# Push only when it moves (perf 2026-07-09): the global is a
		# constant between re-anchors; re-setting it per frame was churn.
		RenderingServer.global_shader_parameter_set("wave_center", _anchor)

	# Wading strides ring the surface (the trace map brightens it; this
	# moves it). Swimming rings wider and softer — and tows a wake:
	# alternate splats astern of the stroke, offset port/starboard, and
	# the rings' interference draws the V for free (PLAN_SUBSTANCES S1).
	var wsurf: float = Terrain.water_surface(p.x, p.z)
	if wsurf > -1e11 and p.y < wsurf + 1.0:
		var vel := Vector2(player.velocity.x, player.velocity.z)
		var speed := vel.length()
		_wade_accum += delta
		if speed > 1.0 and _wade_accum >= WADE_INTERVAL:
			_wade_accum = 0.0
			var ring := wade_ring(wsurf + 1.0 - p.y, speed, 1.0)
			if ring != Vector2.ZERO:
				disturb(pxz, ring.x, ring.y)
			if p.y < wsurf + 0.2 and speed > 1.2:  # swimming, not wading
				_stroke += 1
				var dir := vel / speed
				var side := Vector2(-dir.y, dir.x) \
						* (WAKE_SIDE if _stroke % 2 == 0 else -WAKE_SIDE)
				disturb(pxz - dir * WAKE_ASTERN + side, 0.7, 0.012)

	# Ambient life: storm rain pocks everything, wind keeps a small chop.
	# Splats land anywhere in the window — only water meshes sample the
	# field, so dry-land splats simply never render.
	var rate := rain_rate(Weather.rain) + chop_rate(Weather.wind)
	_emit_accum += rate * delta
	while _emit_accum >= 1.0 and _op_count < WaveGpu.MAX_OPS:
		_emit_accum -= 1.0
		var off := Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5) * WaveGpu.REGION
		var rain := Weather.rain > 0.3
		disturb(_anchor + off, 0.35 if rain else 1.6,
			(0.008 if rain else 0.002) * (0.5 + _rng.randf()))
		if not rain:
			# Chop streaks along the wind: each seed gets a downwind twin.
			disturb(_anchor + off + Vector2(Weather.wind_dir) * 1.4, 1.6,
				0.0015 * (0.5 + _rng.randf()))

	# S2: the breaker band deposits foam — probe a few window points per
	# frame against the CPU surf mirror; where the swell breaks and the
	# ground ahead rises (windward — the lee shore stays clean), one curd
	# lands. The band assembles over frames; the drift rides it ashore.
	if SeaSwell.enabled and SeaSwell.amp > BREAKER_MIN_AMP:
		var amp_prim: float = SeaSwell.amp * SeaSwell.PRIMARY_SHARE
		if _band_seed.is_finite() \
				and _band_seed.distance_to(_anchor) > WaveGpu.REGION * 0.7:
			_band_seed = Vector2.INF  # the window left the band behind
		for i in BREAKER_TRIES:
			if _foam_count >= WaveGpu.FOAM_OPS:
				break
			var q: Vector2
			if _band_seed.is_finite() and i % 3 != 0:
				q = _band_seed + Vector2(_rng.randf_range(-BREAKER_NEAR, BREAKER_NEAR),
					_rng.randf_range(-BREAKER_NEAR, BREAKER_NEAR))
			else:
				q = _anchor + Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5) \
						* WaveGpu.REGION
			var qs: float = Terrain.water_surface(q.x, q.y)
			if qs < -1e11:
				continue
			var ground: float = Terrain.height(q.x, q.y)
			var depth := qs - ground
			if depth < 0.1 or SeaSwell.break_frac(amp_prim, SeaSwell.wavelength, depth) < 1.0:
				continue
			# The lee gate on the cheap: shallower along the swell's travel
			# means this shore faces the waves; deeper means the lee.
			var ahead := q + SeaSwell.direction * 3.0
			if Terrain.height(ahead.x, ahead.y) <= ground:
				continue
			_band_seed = q
			deposit_foam(q, BREAKER_RADIUS,
				BREAKER_FOAM * (0.6 + 0.4 * _rng.randf()))

	# The window's one current: swell travel (shoreward wherever it can
	# break — the lee gate killed the rest) + the river/field current at
	# the focus. Approximate by construction; the foam paints downstream.
	var drift := Vector2.ZERO
	if SeaSwell.enabled and SeaSwell.amp > 0.1:
		drift += SeaSwell.direction \
				* (DRIFT_SWELL * clampf(SeaSwell.amp / SeaSwell.SWELL_MAX, 0.0, 1.0))
	if wsurf > -1e11:  # only pay the current query when the focus is on water
		drift += WaterField.current_at(p) * 0.8
	drift = drift.limit_length(DRIFT_MAX)
	_drift = drift

	_last_ops = _op_count
	_last_foam = _foam_count
	var texel := WaveGpu.REGION / WaveGpu.GRID
	_gpu.tick(_ops, _op_count, _foam_count,
		exp(-delta / maxf(foam_decay, 0.1)), drift * (delta / texel), delta)
	_op_count = 0
	_foam_count = 0
