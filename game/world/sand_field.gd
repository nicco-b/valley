extends Node
## SandField (autoload): a real granular heightfield simulation in a 20m
## window around the player — not a decal layer. The field is SIGNED sand
## volume in meters, conserved: a footstep displaces material into an
## ejecta ridge; a plowing stride pushes a bow wave; a landing blasts a
## crater with a rim. Every tick, cells steeper than the angle of repose
## AVALANCHE into their neighbors, so pits slump shut, ridges slide, and
## a wake carved across a dune face sends flows chasing downhill. Wet
## sand holds steeper walls (repose rises with Climate.wetness); wind
## slowly erodes the field back to rest.
##
## The sim runs on its own thread (the kernel is pure and unit-tested —
## conservation is asserted, not assumed); the main thread posts stamps
## and receives texture snapshots. Headless builds never start the
## thread. Canon: this is the near-player response layer DECISIONS
## reserves — the world-scale solver ban stands.
##
## Published globals: deform_map (meters, signed), deform_center,
## deform_size. sand_patch.gd renders it as real geometry.

const REGION := 20.0
const GRID := 256  # 7.8cm cells
const CELL := REGION / GRID
const REANCHOR := 5.0
const MAX_DELTA := 0.3  # sand never piles/digs more than this locally
const SNAPSHOT_INTERVAL := 0.05  # main-thread texture updates, seconds
const REPOSE_DRY := 0.60  # tan(31°): dry sand's angle of repose
const REPOSE_WET_BONUS := 0.55  # wet sand stands steeper
const FLOW := 0.28  # fraction of excess moved per relax visit
const BUDGET := 9000  # cell-updates per sim tick (sparse active set)

enum Mask { FOOT_L, FOOT_R, PAW, BOOT }

var _thread: Thread
var _run := true
var _inbox: Array = []  # thread-safe via _lock: stamps + params + reanchor
var _lock := Mutex.new()
var _snapshot: PackedByteArray = PackedByteArray()
var _snap_ready := false

var _image: Image
var _texture: ImageTexture
var _anchor := Vector2.INF
var _snap_accum := 0.0
var _masks: Array = []  # signed, zero-sum PackedFloat32Array masks [w, h, data]


func _ready() -> void:
	_image = Image.create(GRID, GRID, false, Image.FORMAT_RF)
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set("deform_map", _texture)
	RenderingServer.global_shader_parameter_set("deform_size", REGION)
	_masks = [
		_signed_mask(_foot_shape(false), 0.06),
		_signed_mask(_foot_shape(true), 0.06),
		_signed_mask(_paw_shape(), 0.03),
		_signed_mask(_boot_shape(), 0.05),
	]
	if DisplayServer.get_name() != "headless":
		_thread = Thread.new()
		_thread.start(_sim_loop)


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


## Turn an unsigned pressure shape into a SIGNED, ZERO-SUM displacement
## mask: the pit's volume reappears as a ridge ring around it — sand is
## conserved from the first touch, and relaxation does the rest.
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
	# Ring: every border-adjacent empty cell near the pit takes a share.
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
	_post({"op": "stamp", "pos": world_xz, "yaw": yaw,
		"mask": mask, "strength": minf(strength, 1.0)})


## A moving body shovels sand: dig under the feet, throw it along the
## velocity direction. Sliding shovels much more than walking.
func plow(world_xz: Vector2, dir: Vector2, amount: float) -> void:
	_post({"op": "plow", "pos": world_xz, "dir": dir, "amount": amount})


## A landing blasts a crater with a thrown rim.
func crater(world_xz: Vector2, radius_m: float, depth: float) -> void:
	_post({"op": "crater", "pos": world_xz, "radius": radius_m, "depth": depth})


func _post(msg: Dictionary) -> void:
	_lock.lock()
	_inbox.append(msg)
	_lock.unlock()


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	if _anchor == Vector2.INF or p.distance_to(_anchor) > REANCHOR:
		_anchor = p.snappedf(CELL * 4.0)
		_post({"op": "anchor", "pos": _anchor})
	RenderingServer.global_shader_parameter_set("deform_center", _anchor)
	_post({"op": "env", "wet": Climate.wetness, "wind": Weather.wind})
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


## --- the sim thread --------------------------------------------------------

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
		# Drain the inbox.
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
					_shift_window(delta_field, base, anchor, m.pos)
					anchor = m.pos
					_rebake_base(base, anchor)
					_activate_all(active, queued)
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
			_erode(delta_field, active, queued, wind)
			# Post a snapshot.
			_lock.lock()
			_snapshot = delta_field.to_byte_array()
			_snap_ready = true
			_lock.unlock()
		OS.delay_msec(33)  # ~30Hz sim


## One sparse relaxation pass: pure and static so tests can assert
## conservation and slumping without threads. Cells steeper than the
## repose height difference shed material downhill; both cells reactivate
## so flows propagate as avalanche fronts.
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
		var hi := base[i] + delta_field[i]
		var x := i % grid
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
		hi = base[i] + delta_field[i]
	# Compact the queue: drop the processed prefix.
	if idx > 0:
		var rest := active.slice(idx)
		active.clear()
		active.append_array(rest)


func _erode(delta_field: PackedFloat32Array, active: PackedInt32Array,
		queued: PackedByteArray, wind: float) -> void:
	# The wind takes the field back toward rest, a little everywhere the
	# sim is already looking (active cells) — undisturbed sand costs nothing.
	var rate := 0.0004 + 0.002 * wind
	for k in mini(active.size(), 2000):
		var i := active[k]
		delta_field[i] = move_toward(delta_field[i], 0.0, rate)


func _activate_all(active: PackedInt32Array, queued: PackedByteArray) -> void:
	active.clear()
	for i in GRID * GRID:
		queued[i] = 1
		active.append(i)


func _rebake_base(base: PackedFloat32Array, anchor: Vector2) -> void:
	for y in GRID:
		for x in GRID:
			base[y * GRID + x] = Terrain.height(
				anchor.x + (x + 0.5) * CELL - REGION * 0.5,
				anchor.y + (y + 0.5) * CELL - REGION * 0.5)


func _shift_window(delta_field: PackedFloat32Array, _base: PackedFloat32Array,
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
	# Dig a small scoop under the mover, throw it one step along dir.
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
				v = -depth * (1.0 - d * d)  # bowl
			elif d < 1.5:
				v = depth * 0.9 * (1.5 - d) * 2.0  # thrown rim
			if v != 0.0:
				delta_field[i] = clampf(delta_field[i] + v, -MAX_DELTA, MAX_DELTA)
				_touch(active, queued, i)
