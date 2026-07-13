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
	# Vernier (P4): registered before the headless gate below so the
	# tunable exists in every posture, including the scene tests — passive
	# (reads the current false once; never calls set_fill on its own).
	# Bound-method Callables, NOT lambdas — see get_fill_channels()'s doc.
	Vernier.register("water.fill_channels", TYPE_BOOL, false,
		Callable(self, "set_fill"), Callable(self, "get_fill_channels"),
		"Toolkit key K: sim rivers (fill-channels) vs sculpted ribbons.")
	# A whole-world reload (reload_world / import — the in-session bless) swaps
	# the terrain and authored water out from under the window, but the base
	# bake otherwise refreshes only on a ~384m focus DRIFT. Without this the
	# sheet keeps riding the PRE-bless base heights + the stale pooled depth: a
	# flat water sheet floating ABOVE the new shoreline (the reported post-bless
	# "double water"). _on_water_reloaded forces a base rebake (and restarts the
	# dynamics dry). Wired BEFORE the enabled gate — the connection is cheap and
	# fingerprint-neutral, and it lets the headless scene-test gate pin the
	# wiring even though the field itself only runs with a RenderingDevice.
	Terrain.water_reloaded.connect(_on_water_reloaded)
	# The base disk cache (WaterFieldCache, adopt-time hydrology 2026-07-13)
	# follows the BathyCache wiring exactly: a whole-water reload re-keys it
	# (the fresh records refuse old entries on their own shas — and let the
	# bless-time prebake's fresh entry LOAD); a live sculpt stands it down
	# for the session. reload_world's wholesale whole-frame edited is NOT a
	# sculpt (Terrain.world_replacing — the adopt decoupling).
	Terrain.water_reloaded.connect(func() -> void: WaterFieldCache.invalidate_key())
	Terrain.edited.connect(func(_rect: Rect2) -> void:
		if not Terrain.world_replacing:
			WaterFieldCache.mark_dirty())
	_gpu = WaterGpu.new()
	enabled = _gpu.setup()
	if not enabled:
		if Prebake.active():
			# The bless-time prebake run is headless (field off), but the
			# base bake is pure kernel sampling — keep _process alive solely
			# to compute + store it once the player/focus exists.
			return
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
	# Reap the GPU driver's RD resources (7 Texture RIDs + sampler + buffer
	# + shaders/pipelines) while the RenderingDevice is still alive. The
	# base-bake reap above must precede this — the bake touches _gpu.
	if _gpu != null:
		_gpu.teardown()


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


## Vernier's getter for water.fill_channels — a named method, not an
## inline lambda: a GDScript lambda Callable stored in Vernier's STATIC
## (process-lifetime) registry outlives this Node in a way that crashes
## the engine's shutdown ordering (`recursive_mutex lock failed` —
## reproduced empirically; a bound-method Callable via Callable(self, ...)
## does not carry the same baggage and tears down clean). Every Vernier
## registration in this codebase binds real methods for exactly this
## reason — see vernier.gd's file doc.
func get_fill_channels() -> bool:
	return fill_channels


## A whole-world reload (reload_world / import — the in-session bless) changed
## the terrain and authored water under the window. Reseat the field to the new
## ground: force a base rebake (the sheet stops riding the pre-bless heights the
## instant it lands, one off-thread bake later) and clear the live depth so the
## stale pooled water — which would otherwise hang as a second sheet above the
## new shore until it seeped out — is gone at once. Restarting dry mirrors a
## fresh scroll anchor; the next rain refills the new hollows.
func _on_water_reloaded() -> void:
	# Record the rebake intent first, in every posture — _process consumes it on
	# the next live frame, and headless (field off, set_process disabled) it is
	# an inert, never-fingerprinted flag the scene-test gate can read to prove
	# the wiring. The GPU depth clear only makes sense with a live field.
	_force_bake = true
	if not enabled or _gpu == null:
		return
	var dry := PackedFloat32Array()
	dry.resize(WaterGpu.GRID * WaterGpu.GRID)
	_gpu.set_depth(dry)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not DevMode.active():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_K:
		set_fill(not fill_channels)
		# Bookkeeping only (Vernier never called set_fill itself here) —
		# keeps `vernier get water.fill_channels` honest about who last
		# flipped it when that was the debug key, not a `vernier set`.
		Vernier.stamp("water.fill_channels", "debug_key")


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


# --- Contour routing (Wave G2: the re-anchor RULE) --------------------------
## sand's tick_control split, drawn again for the window/anchor decision. Its
## own file/bridge (game/world/water_field_anchor.ct — a name distinct from the
## WaterField autoload, since Contour compiles one MODULE at a time and this
## system's resource namespace/tag must not collide with a future WaterField
## system). NO SILENT FALLBACK: flag ON with the kernel absent / module
## uncompilable / a refused tick is a loud push_error.
const _CONTOUR_MODULE := "res://game/world/water_field_anchor.ct"
var _contour_mode := 0
var _contour_bridge: ContourBridge = null
var _contour_calls := 0   # anchor-decision ticks answered by Contour (the engaged probe)


func _route_anchor(focus: Vector2, center: Vector2, has_center: bool, force: bool) -> Dictionary:
	var bridge := _route_contour()
	if bridge != null:
		_contour_calls += 1
		var inputs := {
			"water_field_anchor.focus": focus, "water_field_anchor.center": center,
			"water_field_anchor.has_center": has_center, "water_field_anchor.force": force}
		var applied := bridge.tick_seeded(inputs, 0.0)
		if not applied:
			push_error("[water_field] STRATA_CONTOUR=1 but the WaterFieldAnchor system tick "
				+ "was refused — refusing to silently run the GDScript twin")
			return {"rebake": false, "center": center, "drifted": false}
		var rebake: Variant = WorldState.get_value("water_field_anchor.rebake", null)
		var drifted: Variant = WorldState.get_value("water_field_anchor.drifted", null)
		var new_center: Variant = WorldState.get_value("water_field_anchor.center", null)
		if rebake == null or drifted == null or new_center == null:
			push_error("[water_field] STRATA_CONTOUR=1 but the WaterFieldAnchor system returned "
				+ "an incomplete decision — refusing to silently run the GDScript twin")
			return {"rebake": false, "center": center, "drifted": false}
		return {"rebake": bool(rebake), "center": new_center as Vector2, "drifted": bool(drifted)}
	return anchor_decision(focus, center, has_center, force)


func _route_contour() -> ContourBridge:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour_bridge


func _contour_resolve() -> void:
	var verdict := Contour.decide("water_field_anchor")
	if verdict != Contour.ROUTE_ENGAGE:
		_contour_mode = verdict
		return
	var bridge := ContourBridge.new(WorldState)
	var err := bridge.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[water_field] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour_bridge = bridge
	_contour_mode = 2


## Routing introspection for the scene test (proves the system ran, not a
## silent fallback): the resolved mode, whether it engaged, the tick count.
func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}


## The scrolling-window re-anchor RULE (docs/PORT_LEDGER.md's water_field row,
## Wave G2 — sand's tick_control split is the precedent): given the focus, the
## current center (has_center=false until the first anchor), and whether a
## rebake was force-requested (the fill-channels toggle), decide whether to
## rebake and, if the focus drifted past RECENTER, the new ANCHOR_SNAP-snapped
## center. Pure — no GPU/thread/RenderingServer/autoload reads. The scroll
## OFFSET the GPU actually scrolls by is a mechanical derived value from this
## decision's old/new center (a Vector2i round, host-side, the same "derived
## writes stay host-side" law Hydrology's river_levels/WorldState mirrors
## follow) — not part of the certified leaf.
static func anchor_decision(focus: Vector2, center: Vector2, has_center: bool, force: bool) -> Dictionary:
	var drifted := (not has_center) or (focus.distance_to(center) > RECENTER)
	if not (drifted or force):
		return {"rebake": false, "center": center, "drifted": false}
	var new_center := center
	if drifted:
		new_center = focus.snappedf(ANCHOR_SNAP)
	return {"rebake": true, "center": new_center, "drifted": drifted}


func _process(delta: float) -> void:
	if not enabled:
		_prebake_base()  # only reachable in the Prebake posture (see _ready)
		return
	# Re-anchor when the focus drifts (never mid-bake: one base at a
	# time, and a fast-traveling focus just re-anchors next frame). A
	# fill-channels toggle forces a rebake in place (no scroll). THE RULE
	# crosses to Contour (Wave G2): the drift-check + snap decision routes
	# through the native §6 `WaterFieldAnchor` system when engaged; the scroll
	# offset (a mechanical Vector2i derived from the decision's center delta)
	# and everything GPU/thread-bound stays host-side either way.
	if not _base_pending:
		var focus := _focus()
		var decision := _route_anchor(focus, _center, _center.is_finite(), _force_bake)
		if bool(decision.get("rebake", false)):
			var old := _center
			if bool(decision.get("drifted", false)):
				_center = decision.center
				if old.is_finite():
					_gpu.scroll(Vector2i(
						((_center - old) / (WINDOW / WaterGpu.GRID)).round()))
				RenderingServer.global_shader_parameter_set(
					"water_field_center", _center)
			_force_bake = false
			# Boot fast path (adopt-time hydrology 2026-07-13): the FIRST
			# base at this anchor can be answered by the bless-time
			# prebake's disk entry — bit-identical to the bake it replaces
			# (raw f32 blobs, sha-verified), refused on ANY mismatch (world
			# key, anchor, grid — WaterFieldCache: an accelerator, never
			# truth). Only the fill=OFF boot base; every later drift/toggle
			# rebakes live exactly as before.
			if not _base_ready_once and not fill_channels:
				var cached := WaterFieldCache.fetch(_center, WaterGpu.GRID, WINDOW)
				if not cached.is_empty():
					var no_sources := PackedFloat32Array()
					no_sources.resize(WaterGpu.GRID * WaterGpu.GRID)
					_fill_on_baked = false
					_gpu.update_base(cached.heights, cached.sinks, no_sources)
					_base_ready_once = true
					print("[water] tier-2 field live: base loaded from disk cache at (%.0f, %.0f)" % [
						_center.x, _center.y])
					Prebake.mark("water_field")  # already on disk — nothing to store
					return
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


## W10b plunge-pool radius (mirrors water_waves.gd's PLUNGE_R_MIN/MAX —
## the bake found the fall, we never re-detect; same clamp, no new sim).
const PLUNGE_R_MIN := 2.5
const PLUNGE_R_MAX := 11.0
const PLUNGE_DROP_REF := 12.0
## W10b river-mouth radius: how far past the last node "the mouth" reaches
## (mirrors water_bodies.gd's _mouth_for span clamp).
const MOUTH_R_MIN := 6.0
const MOUTH_R_MAX := 30.0


## The current pushing a body at this point, m/s in the XZ plane.
## GPU field when live; in an authored river, the spline's flow scaled
## by Hydrology's real discharge — so the brook pushes downstream even
## where the dynamics field has nothing to say. W10b (wading polish):
## a fall's plunge pool pushes OUTWARD from the base (the churn shoving a
## swimmer off the cataract), and a river's mouth drifts SEAWARD/lakeward
## past the ribbon's own end (the current doesn't just stop at the last
## node). Both read ONLY the bake's own falls[]/nodes[] records plus the
## tier-2 flow_norm field already used above — no new sim, no writes, so
## this can never move the soak fingerprint (LAW A1: presentation reads
## the sim, it does not touch it).
func current_at(pos: Vector3) -> Vector2:
	if enabled and _probe_out.x > 0.01:
		var net := Vector2(_probe_out.y, _probe_out.z)
		var speed := minf(net.length() / maxf(_probe_out.x, 0.01) * CURRENT_SCALE,
			CURRENT_MAX)
		if speed > 0.05:
			return net.normalized() * speed
	var here := Vector2(pos.x, pos.z)
	for r in Terrain.rivers:
		var q := Terrain._river_probe(r, pos.x, pos.z)
		if q.x < q.y:  # inside the ribbon
			# Hydrology's region tier answers for generated rivers too.
			return Terrain.river_tangent(r, pos.x, pos.z) \
				* (CURRENT_MAX * Hydrology.flow_norm(r.id))
	# Outside every ribbon: a plunge pool still churns just past its fall's
	# base, and a mouth still drifts just past its river's last node.
	for r in Terrain.rivers:
		for fl in r.get("falls", []) as Array:
			var drop: float = float(fl.get("drop", 0.0))
			if drop < 1.0:
				continue
			var base: Vector2 = fl.get("base", fl.get("pos", Vector2.ZERO))
			var width: float = float(fl.get("width", 0.0))
			var radius := clampf(maxf(width * 0.5, 2.0) + drop * 0.15,
				PLUNGE_R_MIN, PLUNGE_R_MAX)
			var d := here - base
			var dist := d.length()
			if dist > 0.05 and dist < radius:
				var speed := CURRENT_MAX * clampf(drop / PLUNGE_DROP_REF, 0.0, 1.0) \
					* Hydrology.flow_norm(String(r.id))
				return d.normalized() * speed
		var nodes: Array = r.get("nodes", [])
		if nodes.size() >= 2:
			var last: Dictionary = nodes[nodes.size() - 1]
			var lp: Vector2 = last.pos
			var mouth_r := clampf(float(last.half) * 4.0, MOUTH_R_MIN, MOUTH_R_MAX)
			if here.distance_to(lp) < mouth_r:
				var dir: Vector2 = Terrain.river_tangent(r, lp.x, lp.y)
				if dir.length() > 0.01:
					return dir.normalized() * (CURRENT_MAX * 0.5 * Hydrology.flow_norm(String(r.id)))
	return Vector2.ZERO


## Toolkit: the dynamics field.
func summary() -> String:
	if not enabled:
		return "off (headless/no RenderingDevice)"
	return "live 1024^2 window %.0fm at (%.0f, %.0f)%s  fill=%s  probe depth=%.3fm at (%.0f, %.0f)" % [
		WINDOW, _center.x, _center.y, " (baking)" if _base_pending else "",
		"ON" if fill_channels else "off",
		_probe_out.x, _probe_pos.x, _probe_pos.y]

## The bless-time prebake (Prebake posture, headless — the field itself is
## off). Compute the boot base ONCE at the anchor the live boot's first
## _process would choose (the player's spawn focus, ANCHOR_SNAP-snapped —
## same decision, same snap, so the live fetch's center matches) and store
## it through WaterFieldCache. Synchronous on main: this run exists to pay
## the bake, and _bake_base is pure kernel sampling. No kernel (or no
## player yet) = nothing this run could store — mark and idle.
func _prebake_base() -> void:
	if _base_ready_once:
		return  # stored (or proved un-storable); idle until the run quits
	if Terrain.kernel == null:
		_base_ready_once = true
		Prebake.mark("water_field")
		return
	if get_tree().get_first_node_in_group("player") == null:
		return  # the spawn focus doesn't exist yet — next frame
	_center = _focus().snappedf(ANCHOR_SNAP)
	_fill_on_baked = false
	_bake_base()
	WaterFieldCache.store(_center, WaterGpu.GRID, WINDOW, _base_heights, _base_sinks)
	_base_ready_once = true
	print("[water] tier-2 base prebaked + stored at (%.0f, %.0f)" % [_center.x, _center.y])
	Prebake.mark("water_field")


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
			# Persist the boot base (fill=OFF only) as the disk bake: the
			# next cold boot of the SAME inputs at the SAME anchor loads it
			# instead of re-sampling. First base only — drift rebakes are
			# focus-transient and never touch disk (the BathyCache rule).
			if not _fill_on_baked:
				WaterFieldCache.store(_center, WaterGpu.GRID, WINDOW,
					_base_heights, _base_sinks)
			Prebake.mark("water_field")  # a windowed prebake run stores here
			print("[water] tier-2 field live: %dx%d at %.1fm texels, window follows the focus" % [
				WaterGpu.GRID, WaterGpu.GRID, WINDOW / WaterGpu.GRID])
