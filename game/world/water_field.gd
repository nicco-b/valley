extends Node
## WaterField (autoload): tier 2 of the whole-watershed water canon
## (DECISIONS 2026-07-04) — the live dynamics field. One GPU depth field,
## and since 2026-07-05 a SCROLLING WINDOW (the sand-field recipe): the
## same 1024² grid at 2m texels now follows the focus anywhere in the
## archipelago instead of sitting on the home watershed. Storm rain
## lands everywhere the window is, gathers into rivulets down the real
## terrain, pools in hollows, and drains into the ground (fast when
## parched — Climate reads back in) and into the water bodies — ALL of
## them now, generated rivers and the sea included (water_base_block
## already answers everywhere). On re-anchor the depth field scrolls by
## the texel offset and the terrain base rebakes off-thread through the
## native kernel; entering texels start dry and the next rain refills
## them. The water sheet renders the field near the player; a one-thread
## probe feeds the current that pushes wading bodies. Presentation only:
## never saved, never fingerprinted, and headless (no RenderingDevice)
## it simply stays off — the canonical water balance lives in Hydrology.
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
const WINDOW := 2048.0  # meters — the scrolling domain (2m texels)
const RECENTER := 384.0  # re-anchor when the focus drifts this far
const ANCHOR_SNAP := 16.0  # 8 texels — scroll offsets stay integral

# FILL-CHANNELS EXPERIMENT (2026-07-05, debug key K): stop treating
# river channels as sinks and instead SPRING them here at a
# discharge-scaled rate, so the pipe model fills the carved beds with
# real flowing water (shallow-fast on slopes, deep in pools, finds its
# own path). Off by default — the sculpted ribbon is the shipping look;
# this is the A/B. Sea + lakes stay sinks (their level is tier 1).
const SOURCE_RATE := 0.05  # m/s spring per channel texel at full flow
var fill_channels := false
var _fill_on_baked := false  # what the current base was baked with
var _fill_rate_by_idx: Dictionary = {}  # river idx -> m/s (main-thread snapshot)
var _base_sources: PackedFloat32Array
var _base_prefill: PackedFloat32Array  # channel depth seed: rivers start FULL
var _force_bake := false

var enabled := false
var _center := Vector2.INF  # window center; INF until the first anchor
var _gpu: WaterGpu
var _base_task := -1
var _base_pending := false
var _base_ready := false
var _base_ready_once := false
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
	RenderingServer.global_shader_parameter_set("water_field_size", WINDOW)
	# The first anchor (and every base bake after a scroll) happens in
	# _process once a focus exists.


func _exit_tree() -> void:
	# Reap the in-flight base bake before the tree (and the autoloads it
	# reads — Terrain and its native kernel above all) tears down under it.
	# _bake_base samples Terrain.height_block on a worker thread; a quit
	# (or an embedded engine-restart destroy) landing inside the bake window
	# otherwise dereferences the freed kernel from the pool thread and aborts
	# the process — the hydrology catchment / sand_patch lesson, fourth
	# instance. _base_pending is true exactly while a bake is submitted and
	# not yet drained (_drain_base clears it after its own reap), so it is the
	# right in-flight guard; _base_task alone would double-wait an already
	# drained id.
	if _base_pending and _base_task != -1:
		WorkerThreadPool.wait_for_task_completion(_base_task)
		_base_task = -1
		_base_pending = false


## Toolkit (debug key K): A/B the fill-channels experiment. Forces a
## rebake so the source field + sink mask rebuild for the new mode, and
## the river ribbons hide while the sim fills the beds (water_bodies
## reads fill_channels).
func set_fill(on: bool) -> void:
	if on == fill_channels:
		return
	fill_channels = on
	_force_bake = true
	HUD.notify("water: fill channels %s" % ("ON (sim rivers)" if on else "OFF (ribbons)"))


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not DevMode.active():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_K:
		set_fill(not fill_channels)


# The window follows whoever the world streams around (the water_bodies
# focus rule): the Toolkit cam when flying, else the player.
func _focus() -> Vector2:
	if Toolkit.active:
		var p := Toolkit.cam_position()
		return Vector2(p.x, p.z)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var p: Vector3 = player.global_position
		return Vector2(p.x, p.z)
	return _center if _center.is_finite() else Vector2.ZERO


func _process(delta: float) -> void:
	# Re-anchor when the focus drifts (never mid-bake: one base at a
	# time, and a fast-traveling focus just re-anchors next frame). A
	# fill-channels toggle forces a rebake in place (no scroll).
	if not _base_pending:
		var focus := _focus()
		var drifted := not _center.is_finite() or focus.distance_to(_center) > RECENTER
		if drifted or _force_bake:
			var old := _center
			if drifted:
				_center = focus.snappedf(ANCHOR_SNAP)
				if old.is_finite():
					_gpu.scroll(Vector2i(
						((_center - old) / (WINDOW / WaterGpu.GRID)).round()))
				RenderingServer.global_shader_parameter_set(
					"water_field_center", _center)
			_force_bake = false
			# Snapshot per-river spring rates on the MAIN thread (the bake
			# task must not read Hydrology concurrently).
			_fill_on_baked = fill_channels
			_fill_rate_by_idx.clear()
			if fill_channels:
				for r in Terrain.rivers:
					_fill_rate_by_idx[r.idx] = SOURCE_RATE \
						* maxf(Hydrology.flow_norm(r.id), 0.15)
			_lock.lock()
			_base_ready = false
			_lock.unlock()
			_base_pending = true
			_base_task = WorkerThreadPool.add_task(_bake_base)
	if _base_pending:
		_drain_base()
		return
	var rain := RAIN_VIS * Weather.rain * delta
	var soak := (SOAK_BASE + SOAK_DRY_BONUS * (1.0 - Climate.wetness)) * delta
	_gpu.tick(rain, soak, SEEP * delta, delta)
	_probe_accum += delta
	if _probe_accum >= PROBE_INTERVAL:
		_probe_accum = 0.0
		if _probe_pending:
			_probe_out = _gpu.read_probe()
		var player := get_tree().get_first_node_in_group("player")
		if player:
			var p: Vector3 = player.global_position
			_probe_pos = Vector2(p.x, p.z)
			var uv := (_probe_pos - _center) / WINDOW + Vector2(0.5, 0.5)
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
			# Hydrology's region tier answers for generated rivers too.
			return Terrain.river_tangent(r, pos.x, pos.z) \
				* (CURRENT_MAX * Hydrology.flow_norm(r.id))
	return Vector2.ZERO


## Toolkit: the dynamics field.
func summary() -> String:
	if not enabled:
		return "off (headless/no RenderingDevice)"
	return "live 1024^2 window %.0fm at (%.0f, %.0f)%s  fill=%s  probe depth=%.3fm at (%.0f, %.0f)" % [
		WINDOW, _center.x, _center.y, " (baking)" if _base_pending else "",
		"ON" if fill_channels else "off",
		_probe_out.x, _probe_pos.x, _probe_pos.y]

func _bake_base() -> void:
	var g := WaterGpu.GRID
	var step := WINDOW / g
	var origin := _center - Vector2.ONE * (WINDOW * 0.5)
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
	# Fill experiment: rasterize river channels — they become SOURCES
	# (spring the carved bed full) and drop OUT of the sink mask, so the
	# sea and lakes still drain but the rivers hold live water.
	var sources := PackedFloat32Array()
	sources.resize(g * g)
	var prefill := PackedFloat32Array()
	prefill.resize(g * g)
	if _fill_on_baked:
		var origin2 := _center - Vector2.ONE * (WINDOW * 0.5)
		_rasterize_rivers(sources, sinks, prefill, heights, origin2, step, g)
	_lock.lock()
	_base_heights = heights
	_base_sinks = sinks
	_base_sources = sources
	_base_prefill = prefill
	_base_ready = true
	_lock.unlock()


# Stamp every river's channel into the source field (spring rate),
# clear it from the sink mask, and PRE-FILL the bed: depth seeded to
# the record waterline minus the baked ground, so rivers hold their
# water from the first frame — the sim maintains a river, it doesn't
# excavate one from dry. Walks each segment at half-texel steps,
# discing the local half-width — the same geometry the ribbon draws.
func _rasterize_rivers(sources: PackedFloat32Array, sinks: PackedFloat32Array,
		prefill: PackedFloat32Array, heights: PackedFloat32Array,
		origin: Vector2, step: float, g: int) -> void:
	for r in Terrain.rivers:
		var rate: float = _fill_rate_by_idx.get(r.idx, 0.0)
		if rate <= 0.0:
			continue
		var nodes: Array = r.nodes
		var max_fill: float = float(r.depth) + 0.4  # sanity cap per texel
		for s in nodes.size() - 1:
			var a: Vector2 = nodes[s].pos
			var b: Vector2 = nodes[s + 1].pos
			var ha: float = nodes[s].half
			var hb: float = nodes[s + 1].half
			var sa: float = nodes[s].surface
			var sb: float = nodes[s + 1].surface
			var seg := a.distance_to(b)
			var walk := 0.0
			while walk <= seg:
				var f := walk / maxf(seg, 0.01)
				var p := a.lerp(b, f)
				var half := lerpf(ha, hb, f)
				var surface := lerpf(sa, sb, f)
				var rad_t := int(ceil(half / step)) + 1
				var cx := int((p.x - origin.x) / step)
				var cz := int((p.y - origin.y) / step)
				for oz in range(-rad_t, rad_t + 1):
					for ox in range(-rad_t, rad_t + 1):
						var gx := cx + ox
						var gz := cz + oz
						if gx < 0 or gz < 0 or gx >= g or gz >= g:
							continue
						# meters from the centerline (texel centers)
						var wx := origin.x + (gx + 0.5) * step
						var wz := origin.y + (gz + 0.5) * step
						if Vector2(wx, wz).distance_to(p) > half:
							continue
						var i := gz * g + gx
						sources[i] = maxf(sources[i], rate)
						sinks[i] = 0.0
						# Seed to the waterline over the carved bed.
						prefill[i] = clampf(maxf(prefill[i],
							surface - heights[i]), 0.0, max_fill)
				walk += step * 0.5


func _drain_base() -> void:
	_lock.lock()
	var ready := _base_ready
	_lock.unlock()
	if ready:
		WorkerThreadPool.wait_for_task_completion(_base_task)
		_gpu.update_base(_base_heights, _base_sinks, _base_sources)
		if _fill_on_baked:
			# Rivers start FULL: seed the depth field to the waterline.
			# (Replaces the whole field, so open rain puddles reset on a
			# fill-mode bake — an accepted experiment-mode artifact.)
			_gpu.set_depth(_base_prefill)
		_base_pending = false
		if not _base_ready_once:
			_base_ready_once = true
			print("[water] tier-2 field live: %dx%d at %.1fm texels, window follows the focus" % [
				WaterGpu.GRID, WaterGpu.GRID, WINDOW / WaterGpu.GRID])
