extends Node
## WaterWaves (autoload): tier 2.5 of the water canon — the wave field
## that makes surfaces MOVE (the Watershed). A 1024² wave-equation window
## follows the player; wading bodies ring the water — the player AND the
## wildlife (PLAN_SUBSTANCES S1: everything that moves rings the water) —
## storm rain pocks it, wind keeps a restless chop, swimmers tow a wake,
## and deep entries splash one big ring; the pond/river shaders displace
## their vertices by the field. Presentation only: never saved, never
## fingerprinted, off headless. Randomness here is cosmetic and uses a
## local RNG — the deterministic Rng streams are for canonical sims only;
## body sources carry NO randomness at all (pure functions of sim-owned
## position and speed, the flora phase-hash discipline).

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

var enabled := false
var _gpu: WaveGpu
var _anchor := Vector2.INF
var _ops := PackedFloat32Array()
var _op_count := 0
var _last_ops := 0  # sources that spoke last frame (the Toolkit WAVES line)
var _wade_accum := 0.0
var _stroke := 0  # swim stride parity: the wake alternates sides by count, not RNG
var _emit_accum := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_gpu = WaveGpu.new()
	enabled = _gpu.setup()
	if not enabled:
		set_process(false)
		return
	_ops.resize(WaveGpu.MAX_OPS * 4)
	_rng.randomize()
	RenderingServer.global_shader_parameter_set("wave_map", _gpu.display_texture)
	RenderingServer.global_shader_parameter_set("wave_size", WaveGpu.REGION)


## Ring the water at a world point (wading feet, landings, dropped things).
func disturb(world_xz: Vector2, radius_m: float, strength_m: float) -> void:
	if not enabled or not _anchor.is_finite() or _op_count >= WaveGpu.MAX_OPS:
		return
	var texel := WaveGpu.REGION / WaveGpu.GRID
	var px := ((world_xz - _anchor) / WaveGpu.REGION + Vector2(0.5, 0.5)) * WaveGpu.GRID
	var i := _op_count * 4
	_ops[i] = px.x
	_ops[i + 1] = px.y
	_ops[i + 2] = maxf(radius_m / texel, 1.5)
	_ops[i + 3] = -strength_m  # press down; the equation rings it back up
	_op_count += 1


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


## Toolkit: the window and how many sources spoke to it last frame.
func summary() -> String:
	if not enabled:
		return "off (no RenderingDevice — headless or GL)"
	return "window=%.0fm @ %d²  sources=%d/%d  anchor=(%.0f, %.0f)" % [
		WaveGpu.REGION, WaveGpu.GRID, _last_ops, WaveGpu.MAX_OPS,
		_anchor.x, _anchor.y]


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

	_last_ops = _op_count
	_gpu.tick(_ops, _op_count)
	_op_count = 0
