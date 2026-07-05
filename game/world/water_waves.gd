extends Node
## WaterWaves (autoload): tier 2.5 of the water canon — the wave field
## that makes surfaces MOVE. A 512² wave-equation window follows the
## player; wading bodies ring the water, storm rain pocks it, wind keeps
## a restless chop; the pond/river shaders displace their vertices by
## the field. Presentation only: never saved, never fingerprinted, off
## headless. Randomness here is cosmetic and uses a local RNG — the
## deterministic Rng streams are for canonical sims only.

const REANCHOR := 8.0
const WADE_INTERVAL := 0.12
const WADE_RADIUS := 0.9
const WADE_STRENGTH := 0.035  # meters of dent per stride
const RAIN_PER_SEC := 26.0  # drop splats/sec across the window in a storm
const CHOP_PER_SEC := 2.5  # wind ripple seeds/sec at full wind

var enabled := false
var _gpu: WaveGpu
var _anchor := Vector2.INF
var _ops := PackedFloat32Array()
var _op_count := 0
var _wade_accum := 0.0
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
	# moves it). Swimming rings wider and softer.
	var wsurf: float = Terrain.water_surface(p.x, p.z)
	if wsurf > -1e11 and p.y < wsurf + 1.0:
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		_wade_accum += delta
		if speed > 1.0 and _wade_accum >= WADE_INTERVAL:
			_wade_accum = 0.0
			disturb(pxz, WADE_RADIUS, WADE_STRENGTH * minf(speed / 3.5, 1.6))

	# Ambient life: storm rain pocks everything, wind keeps a small chop.
	# Splats land anywhere in the window — only water meshes sample the
	# field, so dry-land splats simply never render.
	var rate := 0.0
	if Weather.state == "storm":
		rate += RAIN_PER_SEC
	rate += CHOP_PER_SEC * Weather.wind
	_emit_accum += rate * delta
	while _emit_accum >= 1.0 and _op_count < WaveGpu.MAX_OPS:
		_emit_accum -= 1.0
		var off := Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5) * WaveGpu.REGION
		var rain := Weather.state == "storm"
		disturb(_anchor + off, 0.35 if rain else 1.6,
			(0.008 if rain else 0.002) * (0.5 + _rng.randf()))
		if not rain:
			# Chop streaks along the wind: each seed gets a downwind twin.
			disturb(_anchor + off + Vector2(Weather.wind_dir) * 1.4, 1.6,
				0.0015 * (0.5 + _rng.randf()))

	_gpu.tick(_ops, _op_count)
	_op_count = 0
