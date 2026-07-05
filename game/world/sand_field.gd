extends Node
## SandField (autoload): the granular sand simulation around the player.
## The field is SIGNED sand volume in meters, conserved: footsteps
## displace material into ejecta ridges, landings blast craters with
## thrown rims, moving feet plow bow waves, and cells steeper than the
## angle of repose avalanche downhill every tick. Wet sand stands
## steeper; wind erodes toward rest.
##
## Two engines, one behavior:
##  - GPU (the real one): 1024x1024 field at 2.3cm texels over 24m, the
##    kernels in game/shaders/compute/ — apply, Jacobi relaxation with
##    antisymmetric (mass-exact) flux, scroll. The renderer samples the
##    display texture directly (Texture2DRD); the CPU never touches a
##    texel.
##  - CPU thread (reference + headless fallback): the same physics on a
##    256-grid, sparse active-front relaxation. The kernel is pure and
##    static; scene tests assert conservation, slumping, and downhill
##    transport against IT — the spec the GPU implements.
##
## Canon: this is the near-player fine-response layer DECISIONS reserves;
## the world-scale solver ban stands.

const REGION := 20.0  # CPU-mode window
const GRID := 256
const CELL := REGION / GRID
const REANCHOR := 5.0
const MAX_DELTA := 0.3
const SNAPSHOT_INTERVAL := 0.05
const REPOSE_DRY := 0.60  # tan(31°)
const REPOSE_WET_BONUS := 0.55
const FLOW := 0.28
const BUDGET := 9000

enum Mask { FOOT_L, FOOT_R, PAW, BOOT }

var _gpu: SandGpu
var _gpu_mode := false
var _ops := PackedFloat32Array()
var _op_count := 0
var _base_pending := false
var _base_task := -1
var _base_result: PackedFloat32Array
var _base_ready := false

var _thread: Thread
var _run := true
var _inbox: Array = []
var _lock := Mutex.new()
var _snapshot: PackedByteArray = PackedByteArray()
var _snap_ready := false

var _image: Image
var _texture: ImageTexture
var _anchor := Vector2.INF
var _snap_accum := 0.0
var _masks: Array = []  # signed, zero-sum [w, h, PackedFloat32Array], meters


func _region() -> float:
	return SandGpu.REGION if _gpu_mode else REGION


func _cell_m() -> float:
	return (SandGpu.REGION / SandGpu.GRID) if _gpu_mode else CELL


func _ready() -> void:
	_masks = [
		_signed_mask(_foot_shape(false), 0.085),
		_signed_mask(_foot_shape(true), 0.085),
		_signed_mask(_paw_shape(), 0.045),
		_signed_mask(_boot_shape(), 0.07),
	]
	_gpu = SandGpu.new()
	if DisplayServer.get_name() != "headless" and _gpu.setup(_masks):
		_gpu_mode = true
		_ops.resize(SandGpu.MAX_OPS * 8)
		RenderingServer.global_shader_parameter_set("deform_map", _gpu.display_texture)
		print("[sand] granular sim on GPU: %dx%d, %.1fcm texels"
			% [SandGpu.GRID, SandGpu.GRID, _cell_m() * 100.0])
	else:
		_image = Image.create(GRID, GRID, false, Image.FORMAT_RF)
		_texture = ImageTexture.create_from_image(_image)
		RenderingServer.global_shader_parameter_set("deform_map", _texture)
		if DisplayServer.get_name() != "headless":
			_thread = Thread.new()
			_thread.start(_sim_loop)
	RenderingServer.global_shader_parameter_set("deform_size", _region())


func _exit_tree() -> void:
	_run = false
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


## --- shapes (unsigned pressure, 0..1) ------------------------------------

func _foot_shape(mirror: bool) -> Array:
	var w := 7
	var h := 11
	var data := PackedFloat32Array()
	data.resize(w * h)
	for y in h:
		for x in w:
			var p := Vector2((float(x) + 0.5) / w - 0.5, (float(y) + 0.5) / h - 0.5)
			if mirror:
				p.x = -p.x
			var toe := 1.0 - clampf(p.distance_to(Vector2(0.06, 0.22)) / 0.3, 0.0, 1.0)
			var heel := 1.0 - clampf(p.distance_to(Vector2(-0.03, -0.2)) / 0.26, 0.0, 1.0)
			data[y * w + x] = clampf(maxf(toe * 1.15, heel), 0.0, 1.0)
	return [w, h, data]


func _paw_shape() -> Array:
	var s := 6
	var data := PackedFloat32Array()
	data.resize(s * s)
	for y in s:
		for x in s:
			var p := Vector2((float(x) + 0.5) / s - 0.5, (float(y) + 0.5) / s - 0.5)
			var pad := 1.0 - clampf(p.distance_to(Vector2(0.0, 0.08)) / 0.34, 0.0, 1.0)
			var toes := 1.0 - clampf(absf(p.y - 0.28) / 0.14
				+ absf(fposmod(p.x * 3.4 + 0.5, 1.0) - 0.5) * 0.8, 0.0, 1.0)
			data[y * s + x] = clampf(maxf(pad, toes * 0.8), 0.0, 1.0)
	return [s, s, data]


func _boot_shape() -> Array:
	var w := 6
	var h := 9
	var data := PackedFloat32Array()
	data.resize(w * h)
	for y in h:
		for x in w:
			var p := Vector2((float(x) + 0.5) / w - 0.5, (float(y) + 0.5) / h - 0.5)
			data[y * w + x] = smoothstep(0.0, 0.7, 1.0 - clampf(p.length() / 0.5, 0.0, 1.0))
	return [w, h, data]


## Signed, zero-sum: the pit's volume reappears as a ridge ring — sand is
## conserved from the first touch; relaxation does the rest.
func _signed_mask(shape: Array, depth: float) -> Array:
	var w: int = shape[0]
	var h: int = shape[1]
	var src: PackedFloat32Array = shape[2]
	var out_w := w + 4
	var out_h := h + 4
	var out := PackedFloat32Array()
	out.resize(out_w * out_h)
	var removed := 0.0
	for y in h:
		for x in w:
			var v := src[y * w + x] * depth
			out[(y + 2) * out_w + (x + 2)] = -v
			removed += v
	var ring: Array[int] = []
	for y in out_h:
		for x in out_w:
			if out[y * out_w + x] < 0.0:
				continue
			var near_pit := false
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < out_w and ny < out_h \
							and out[ny * out_w + nx] < 0.0:
						near_pit = true
			if near_pit:
				ring.append(y * out_w + x)
	if not ring.is_empty():
		var share := removed / ring.size()
		for i in ring:
			out[i] += share
	return [out_w, out_h, out]


## --- main-thread API ------------------------------------------------------

func stamp(world_xz: Vector2, yaw: float, mask: Mask, strength := 1.0) -> void:
	if _gpu_mode:
		_queue_op(world_xz, yaw, minf(strength, 1.0), float(mask), Vector2.ZERO, 0.0)
	else:
		_post({"op": "stamp", "pos": world_xz, "yaw": yaw,
			"mask": mask, "strength": minf(strength, 1.0)})


func plow(world_xz: Vector2, dir: Vector2, amount: float) -> void:
	if _gpu_mode:
		_queue_op(world_xz, 0.0, amount, 5.0, dir * (0.5 / _cell_m()), 0.0)
	else:
		_post({"op": "plow", "pos": world_xz, "dir": dir, "amount": amount})


func crater(world_xz: Vector2, radius_m: float, depth: float) -> void:
	if _gpu_mode:
		_queue_op(world_xz, 0.0, depth, 4.0, Vector2.ZERO, radius_m / _cell_m())
	else:
		_post({"op": "crater", "pos": world_xz, "radius": radius_m, "depth": depth})


func _queue_op(pos: Vector2, yaw: float, strength: float, type: float,
		aux: Vector2, radius_px: float) -> void:
	if not _anchor.is_finite() or _op_count >= SandGpu.MAX_OPS:
		return
	var px := ((pos - _anchor) / _region() + Vector2(0.5, 0.5)) * SandGpu.GRID
	var i := _op_count * 8
	_ops[i] = px.x
	_ops[i + 1] = px.y
	_ops[i + 2] = yaw
	_ops[i + 3] = strength
	_ops[i + 4] = type
	_ops[i + 5] = aux.x
	_ops[i + 6] = aux.y
	_ops[i + 7] = radius_px
	_op_count += 1


func _post(msg: Dictionary) -> void:
	_lock.lock()
	_inbox.append(msg)
	_lock.unlock()


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	var reanchor := _anchor == Vector2.INF or p.distance_to(_anchor) > REANCHOR
	if reanchor:
		var old := _anchor
		_anchor = p.snappedf(_cell_m() * 8.0)
		if _gpu_mode:
			if old.is_finite():
				_gpu.scroll(Vector2i(((_anchor - old) / _cell_m()).round()))
			_start_base_bake()
		else:
			_post({"op": "anchor", "pos": _anchor})
	RenderingServer.global_shader_parameter_set("deform_center", _anchor)

	if _gpu_mode:
		_drain_base_bake()
		# Local dampness, not just the global: Climate.moisture floors
		# near open water and on sea strands, so beach sand stands
		# steeper and holds prints (wet-sand feel at the new coasts).
		var wet := maxf(Climate.wetness, Climate.moisture(_anchor.x, _anchor.y))
		var repose := (REPOSE_DRY + REPOSE_WET_BONUS * wet) * _cell_m()
		var flow := 0.0 if _base_pending else FLOW
		# Per-second erosion, applied per frame: calm keeps prints ~2min,
		# a storm scrubs them in ~20s (the CPU path decays only active
		# cells at 30Hz; this must NOT be hotter).
		var decay := (0.0003 + 0.0025 * Weather.wind) * delta
		_gpu.tick(_ops, _op_count, repose, flow, decay)
		_op_count = 0
		return

	_post({"op": "env",
		"wet": maxf(Climate.wetness, Climate.moisture(_anchor.x, _anchor.y)),
		"wind": Weather.wind})
	_snap_accum += delta
	if _snap_accum >= SNAPSHOT_INTERVAL and _snap_ready:
		_snap_accum = 0.0
		_lock.lock()
		var bytes := _snapshot
		_snap_ready = false
		_lock.unlock()
		if bytes.size() == GRID * GRID * 4:
			_image.set_data(GRID, GRID, false, Image.FORMAT_RF, bytes)
			_texture.update(_image)


## Base terrain heights for the GPU window, baked off-thread on re-anchor.
## Relaxation pauses (flow 0) until the fresh base lands.
func _start_base_bake() -> void:
	_base_pending = true
	var anchor := _anchor
	var region := _region()
	_base_task = WorkerThreadPool.add_task(func() -> void:
		var g := SandGpu.BASE_GRID
		var step := region / g
		# Bulk sampling through the native kernel when present — no
		# per-sample GDScript on this worker (see Terrain.kernel).
		var heights := Terrain.height_block(
			anchor.x + 0.5 * step - region * 0.5,
			anchor.y + 0.5 * step - region * 0.5, step, g, g)
		_lock.lock()
		_base_result = heights
		_base_ready = true
		_lock.unlock())


func _drain_base_bake() -> void:
	if not _base_pending:
		return
	_lock.lock()
	var ready := _base_ready
	var heights := _base_result
	_base_ready = false
	_lock.unlock()
	if ready:
		WorkerThreadPool.wait_for_task_completion(_base_task)
		_gpu.update_base(heights)
		_base_pending = false


## --- the CPU sim (reference implementation + headless fallback) -----------

func _sim_loop() -> void:
	var delta_field := PackedFloat32Array()
	delta_field.resize(GRID * GRID)
	var base := PackedFloat32Array()
	base.resize(GRID * GRID)
	var active := PackedInt32Array()
	var queued := PackedByteArray()
	queued.resize(GRID * GRID)
	var anchor := Vector2.INF
	var wet := 0.0
	var wind := 0.1
	while _run:
		_lock.lock()
		var msgs := _inbox.duplicate()
		_inbox.clear()
		_lock.unlock()
		for m in msgs:
			match m.op:
				"env":
					wet = m.wet
					wind = m.wind
				"anchor":
					_shift_window(delta_field, anchor, m.pos)
					anchor = m.pos
					_rebake_base(base, anchor)
					active.clear()
					for i in GRID * GRID:
						queued[i] = 1
						active.append(i)
				"stamp":
					if anchor.is_finite():
						_apply_mask(delta_field, active, queued, anchor,
							_masks[m.mask], m.pos, m.yaw, m.strength)
				"plow":
					if anchor.is_finite():
						_apply_plow(delta_field, active, queued, anchor,
							m.pos, m.dir, m.amount)
				"crater":
					if anchor.is_finite():
						_apply_crater(delta_field, active, queued, anchor,
							m.pos, m.radius, m.depth)
		if anchor.is_finite():
			var repose := (REPOSE_DRY + REPOSE_WET_BONUS * wet) * CELL
			relax(delta_field, base, active, queued, GRID, repose, FLOW, BUDGET)
			var rate := 0.0004 + 0.002 * wind
			for k in mini(active.size(), 2000):
				delta_field[active[k]] = move_toward(delta_field[active[k]], 0.0, rate)
			_lock.lock()
			_snapshot = delta_field.to_byte_array()
			_snap_ready = true
			_lock.unlock()
		OS.delay_msec(33)


## The kernel, pure and static — the tested spec the GPU implements.
static func relax(delta_field: PackedFloat32Array, base: PackedFloat32Array,
		active: PackedInt32Array, queued: PackedByteArray,
		grid: int, repose_h: float, flow: float, budget: int) -> void:
	var processed := 0
	var idx := 0
	while idx < active.size() and processed < budget:
		var i := active[idx]
		idx += 1
		processed += 1
		queued[i] = 0
		var x := i % grid
		@warning_ignore("integer_division")
		var y := i / grid
		for n in 4:
			var nx := x + (1 if n == 0 else (-1 if n == 1 else 0))
			var ny := y + (1 if n == 2 else (-1 if n == 3 else 0))
			if nx < 0 or ny < 0 or nx >= grid or ny >= grid:
				continue
			var j := ny * grid + nx
			var diff := (base[i] + delta_field[i]) - (base[j] + delta_field[j])
			if diff > repose_h:
				var q := (diff - repose_h) * 0.5 * flow
				delta_field[i] -= q
				delta_field[j] += q
				if queued[j] == 0:
					queued[j] = 1
					active.append(j)
				if queued[i] == 0:
					queued[i] = 1
					active.append(i)
	if idx > 0:
		var rest := active.slice(idx)
		active.clear()
		active.append_array(rest)


func _rebake_base(base: PackedFloat32Array, anchor: Vector2) -> void:
	# Runs on the CPU-reference sim thread: bulk sampling through the
	# native kernel when present (see Terrain.kernel).
	var block := Terrain.height_block(
		anchor.x + 0.5 * CELL - REGION * 0.5,
		anchor.y + 0.5 * CELL - REGION * 0.5, CELL, GRID, GRID)
	for i in GRID * GRID:
		base[i] = block[i]


func _shift_window(delta_field: PackedFloat32Array,
		old_anchor: Vector2, new_anchor: Vector2) -> void:
	if not old_anchor.is_finite():
		return
	var off := Vector2i(((new_anchor - old_anchor) / CELL).round())
	var moved := PackedFloat32Array()
	moved.resize(GRID * GRID)
	for y in GRID:
		for x in GRID:
			var sx := x + off.x
			var sy := y + off.y
			if sx >= 0 and sy >= 0 and sx < GRID and sy < GRID:
				moved[y * GRID + x] = delta_field[sy * GRID + sx]
	for i in GRID * GRID:
		delta_field[i] = moved[i]


func _to_cell(anchor: Vector2, world_xz: Vector2) -> Vector2i:
	var uv := (world_xz - anchor) / REGION + Vector2(0.5, 0.5)
	return Vector2i(int(uv.x * GRID), int(uv.y * GRID))


func _touch(active: PackedInt32Array, queued: PackedByteArray, i: int) -> void:
	if queued[i] == 0:
		queued[i] = 1
		active.append(i)


func _apply_mask(delta_field: PackedFloat32Array, active: PackedInt32Array,
		queued: PackedByteArray, anchor: Vector2, mask: Array,
		world_xz: Vector2, yaw: float, strength: float) -> void:
	var mw: int = mask[0]
	var mh: int = mask[1]
	var data: PackedFloat32Array = mask[2]
	var c := _to_cell(anchor, world_xz)
	var half := maxi(mw, mh)
	var co := cos(-yaw)
	var si := sin(-yaw)
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= GRID or y >= GRID:
				continue
			var mx := int(co * dx - si * dy + mw * 0.5)
			var my := int(si * dx + co * dy + mh * 0.5)
			if mx < 0 or my < 0 or mx >= mw or my >= mh:
				continue
			var v := data[my * mw + mx] * strength
			if v == 0.0:
				continue
			var i := y * GRID + x
			delta_field[i] = clampf(delta_field[i] + v, -MAX_DELTA, MAX_DELTA)
			_touch(active, queued, i)


func _apply_plow(delta_field: PackedFloat32Array, active: PackedInt32Array,
		queued: PackedByteArray, anchor: Vector2,
		world_xz: Vector2, dir: Vector2, amount: float) -> void:
	var c := _to_cell(anchor, world_xz)
	var throw := _to_cell(anchor, world_xz + dir * 0.5)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var fall := 1.0 - Vector2(dx, dy).length() / 3.0
			if fall <= 0.0:
				continue
			var x := c.x + dx
			var y := c.y + dy
			if x < 1 or y < 1 or x >= GRID - 1 or y >= GRID - 1:
				continue
			var i := y * GRID + x
			var q := amount * fall
			delta_field[i] = clampf(delta_field[i] - q, -MAX_DELTA, MAX_DELTA)
			_touch(active, queued, i)
			var tx := throw.x + dx
			var ty := throw.y + dy
			if tx >= 0 and ty >= 0 and tx < GRID and ty < GRID:
				var j := ty * GRID + tx
				delta_field[j] = clampf(delta_field[j] + q, -MAX_DELTA, MAX_DELTA)
				_touch(active, queued, j)


func _apply_crater(delta_field: PackedFloat32Array, active: PackedInt32Array,
		queued: PackedByteArray, anchor: Vector2,
		world_xz: Vector2, radius_m: float, depth: float) -> void:
	var c := _to_cell(anchor, world_xz)
	var r := int(radius_m / CELL)
	for dy in range(-r - 2, r + 3):
		for dx in range(-r - 2, r + 3):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= GRID or y >= GRID:
				continue
			var d := Vector2(dx, dy).length() / float(r)
			var i := y * GRID + x
			var v := 0.0
			if d < 1.0:
				v = -depth * (1.0 - d * d)
			elif d < 1.5:
				v = depth * 0.9 * (1.5 - d) * 2.0
			if v != 0.0:
				delta_field[i] = clampf(delta_field[i] + v, -MAX_DELTA, MAX_DELTA)
				_touch(active, queued, i)
