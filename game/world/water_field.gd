extends Node
## WaterField (autoload): tier 2 of the whole-watershed water canon
## (DECISIONS 2026-07-04) — the live dynamics field. One GPU depth field
## over the entire routed domain: storm rain lands everywhere, gathers
## into rivulets down the real terrain, pools in hollows, and drains
## into the ground (fast when parched — Climate reads back in) and into
## the authored water bodies (this field's sinks; their levels are
## Hydrology's job, tier 1). The water sheet renders the field near the
## player; a one-thread probe feeds the current that pushes wading
## bodies. Presentation only: never saved, never fingerprinted, and
## headless (no RenderingDevice) it simply stays off — the canonical
## water balance lives in Hydrology.
##
## Rain here is VISUAL rain (~100x physical rate): at true mm/h nothing
## would ever read on screen. Honesty lives in tier 1; this tier is the
## storm you can watch.

# Balance tuned on a headless CPU mirror of the kernels (tests/_wtune):
# flat ground holds a sub-render-threshold film so it never floods, while
# hollows the flux keeps feeding pool visibly, then drain after the storm.
const RAIN_VIS := 0.0012  # m/s of visual rain while storming (~100x real)
const SOAK_BASE := 0.00012  # m/s ground drink, always
const SOAK_DRY_BONUS := 0.00020  # extra on parched ground (soaks first, pools later)
const SEEP := 0.16  # per-second drain proportional to depth — bounds the film
const PROBE_INTERVAL := 0.15
const CURRENT_SCALE := 9.0  # net-flux -> m/s-ish push (mood physics)
const CURRENT_MAX := 2.4

var enabled := false
var _gpu: WaterGpu
var _base_task := -1
var _base_pending := false
var _base_ready := false
var _base_heights: PackedFloat32Array
var _base_sinks: PackedFloat32Array
var _lock := Mutex.new()
var _probe_accum := 0.0
var _probe_pending := false
var _probe_out := Vector4.ZERO
var _probe_pos := Vector2(1e9, 1e9)


func _ready() -> void:
	_gpu = WaterGpu.new()
	enabled = _gpu.setup()
	if not enabled:
		set_process(false)
		return
	RenderingServer.global_shader_parameter_set("water_field_map", _gpu.display_texture)
	RenderingServer.global_shader_parameter_set("water_base_map", _gpu.base_texture)
	RenderingServer.global_shader_parameter_set("water_field_center", Hydrology.center)
	RenderingServer.global_shader_parameter_set("water_field_size", Hydrology.domain)
	# The base bake: 1M terrain samples + the sink mask, once, off-thread.
	# The field sits still (no flow kernel needs it zeroed) until it lands.
	_base_pending = true
	_base_task = WorkerThreadPool.add_task(_bake_base)


func _process(delta: float) -> void:
	if _base_pending:
		_drain_base()
		return
	var rain := RAIN_VIS * delta if Weather.state == "storm" else 0.0
	var soak := (SOAK_BASE + SOAK_DRY_BONUS * (1.0 - Climate.wetness)) * delta
	_gpu.tick(rain, soak, SEEP * delta)
	_probe_accum += delta
	if _probe_accum >= PROBE_INTERVAL:
		_probe_accum = 0.0
		if _probe_pending:
			_probe_out = _gpu.read_probe()
		var player := get_tree().get_first_node_in_group("player")
		if player:
			var p: Vector3 = player.global_position
			_probe_pos = Vector2(p.x, p.z)
			var uv := (_probe_pos - Hydrology.center) \
				/ Hydrology.domain + Vector2(0.5, 0.5)
			_gpu.dispatch_probe(uv)
			_probe_pending = true


## Field water depth under a point (m). The probe tracks the PLAYER;
## a query far from the probed point answers 0 rather than lying with
## someone else's depth (the trap the first NPC caller would hit).
func depth_at(pos: Vector3) -> float:
	if not enabled or Vector2(pos.x, pos.z).distance_to(_probe_pos) > 4.0:
		return 0.0
	return _probe_out.x


## The current pushing a body at this point, m/s in the XZ plane.
## GPU field when live; in an authored river, the spline's flow scaled
## by Hydrology's real discharge — so the brook pushes downstream even
## where the dynamics field has nothing to say.
func current_at(pos: Vector3) -> Vector2:
	if enabled and _probe_out.x > 0.01:
		var net := Vector2(_probe_out.y, _probe_out.z)
		var speed := minf(net.length() / maxf(_probe_out.x, 0.01) * CURRENT_SCALE,
			CURRENT_MAX)
		if speed > 0.05:
			return net.normalized() * speed
	for r in Terrain.rivers:
		var q := Terrain._river_probe(r, pos.x, pos.z)
		if q.x < q.y:  # inside the ribbon
			return Terrain.river_tangent(r, pos.x, pos.z) \
				* (CURRENT_MAX * Hydrology.flow_norm(r.id))
	return Vector2.ZERO


func _bake_base() -> void:
	var g := WaterGpu.GRID
	var step := Hydrology.domain / g
	var origin := Hydrology.center - Vector2.ONE * (Hydrology.domain * 0.5)
	# Bulk sampling through the native kernel when present — no
	# per-sample GDScript on this worker (see Terrain.kernel).
	var heights := Terrain.height_block(
		origin.x + 0.5 * step, origin.y + 0.5 * step, step, g, g)
	var bases := Terrain.water_base_block(
		origin.x + 0.5 * step, origin.y + 0.5 * step, step, g, g)
	var sinks := PackedFloat32Array()
	sinks.resize(g * g)
	for i in g * g:
		sinks[i] = 1.0 if bases[i] > -1e6 else 0.0
	_lock.lock()
	_base_heights = heights
	_base_sinks = sinks
	_base_ready = true
	_lock.unlock()


func _drain_base() -> void:
	_lock.lock()
	var ready := _base_ready
	_lock.unlock()
	if ready:
		WorkerThreadPool.wait_for_task_completion(_base_task)
		_gpu.update_base(_base_heights, _base_sinks)
		_base_pending = false
		print("[water] tier-2 field live: %dx%d at %.1fm texels" % [
			WaterGpu.GRID, WaterGpu.GRID, Hydrology.domain / WaterGpu.GRID])
