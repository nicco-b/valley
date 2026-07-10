class_name FloatBody
extends Node
## Presentation buoyancy (PLAN_SUBSTANCES S3): rides a target Node3D on the
## analytic water surface — the SeaSwell CPU mirror over the open sea, the
## flat hydrology level elsewhere. It springs the hull to the local surface
## height (the MEAN of a small footprint — a raft floats at its footprint's
## average, not one point), leans it into the surface slope (a finite
## difference across the footprint — the shader's swell_grad in the small),
## and lets the current DRIFT it downstream on a mooring tether. The mooring
## holds: a moored raft tugs its line, it does not sail off — RIDING (the
## player carried by a drifting hull) waits for the kitchen table ★, and its
## position would then become sim state (a record + WorldState, the mirror
## law). The bob itself is stateless f(TIME, sim-owned wind/fronts): OFF the
## soak digest by construction, exactly like SeaSwell and WaterWaves. Off
## headless (no surface to show); the pure step(delta, t) drives the scene
## test and never touches wall-clock, so it stays deterministic on demand.

# Live floaters (the Toolkit's SWELL line reads this) — counted only when
# enabled, so the headless sims never see a nonzero here.
static var alive := 0

const RISE := 6.0          # vertical spring approach rate (1/s)
const LEAN_RATE := 5.0     # how fast the hull swings to the surface normal
const LEAN_MAX := deg_to_rad(16.0)  # gouache tilt: a lean, never a capsize
const DRIFT_PUSH := 0.7    # current (m/s) -> tether offset gain
const TETHER_RETURN := 0.4 # mooring pull back toward the anchor (1/s)

var target: Node3D          # the hull to move (defaults to get_parent())
var moor := Vector3.ZERO    # the anchored world position (the mooring)
# Local XZ probe offsets — 4 footprint corners (+ the center is sampled
# too): the height mean floats the hull, the opposing pairs give the tilt.
var footprint := PackedVector2Array([
	Vector2(1.0, 0.0), Vector2(-1.0, 0.0),
	Vector2(0.0, 1.0), Vector2(0.0, -1.0)])
var tether := 2.5           # meters the current may pull off the moor
var rides_swell := true     # open-sea hulls bob on the swell; lake buoys don't
var enabled := false

var _drift := Vector2.ZERO  # current-driven offset from the moor (XZ)
var _t := 0.0
var _yaw := 0.0             # the hull's placed heading, held under the lean
var _scale := Vector3.ONE   # the hull's placed scale, held under the lean
var _lean := Basis.IDENTITY # the current lean, eased toward the surface normal

# Injection seams the headless scene test drives (default to the live world):
#   surface_fn(pos: Vector3, t: float) -> Vector3(slope_x, height, slope_z)
#   current_fn(pos: Vector3) -> Vector2   (m/s in XZ)
var surface_fn := Callable()
var current_fn := Callable()


## Attach a floater to `host`, moored at `moor_pos`, configured from a card's
## `float` block ({footprint, tether, swell}). World_streamer calls this when
## a placed record's card opts in; the scene test builds one by hand.
static func attach(host: Node3D, moor_pos: Vector3, cfg: Dictionary) -> FloatBody:
	var fb := FloatBody.new()
	fb.target = host
	fb.moor = moor_pos
	var r := maxf(float(cfg.get("footprint", 1.0)), 0.05)
	fb.footprint = PackedVector2Array([
		Vector2(r, 0.0), Vector2(-r, 0.0), Vector2(0.0, r), Vector2(0.0, -r)])
	fb.tether = maxf(float(cfg.get("tether", 2.5)), 0.0)
	fb.rides_swell = bool(cfg.get("swell", true))
	host.add_child(fb)
	return fb


func _ready() -> void:
	if target == null:
		target = get_parent() as Node3D
	if target != null:
		# Capture the placed heading + scale so the lean never eats them.
		_yaw = target.rotation.y
		_scale = target.scale
	# Same gate as the water tiers: headless has no surface to ride. The
	# scene test calls step() directly, so it never needs _process.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	enabled = true
	alive += 1
	set_process(true)


func _exit_tree() -> void:
	if enabled:
		alive -= 1
		enabled = false


func _process(delta: float) -> void:
	_t += delta
	step(delta, _t)


## One buoyancy step — pure and callable headless (the scene test's door).
## `t` is the swell clock (seconds); `delta` the frame time.
func step(delta: float, t: float) -> void:
	if target == null:
		return
	var center := moor + Vector3(_drift.x, 0.0, _drift.y)
	# Sample the footprint: mean height floats the hull, the opposing pairs
	# give the pitch/roll. Center is sampled for the +X/-X and +Z/-Z reads.
	var h_sum := _surface(center, t).y
	var n := 1
	var slope := Vector2.ZERO   # (d height / d x, d height / d z)
	var pair := {}              # axis key -> {plus, minus} height, span
	for off in footprint:
		var hp := _surface(center + Vector3(off.x, 0.0, off.y), t).y
		h_sum += hp
		n += 1
		if absf(off.x) > absf(off.y):
			if off.x > 0.0:
				pair["x+"] = hp
			else:
				pair["x-"] = hp
			pair["xspan"] = maxf(pair.get("xspan", 0.0), absf(off.x))
		else:
			if off.y > 0.0:
				pair["z+"] = hp
			else:
				pair["z-"] = hp
			pair["zspan"] = maxf(pair.get("zspan", 0.0), absf(off.y))
	var height := h_sum / float(n)
	if pair.has("x+") and pair.has("x-") and pair.get("xspan", 0.0) > 1e-3:
		slope.x = (pair["x+"] - pair["x-"]) / (2.0 * pair["xspan"])
	if pair.has("z+") and pair.has("z-") and pair.get("zspan", 0.0) > 1e-3:
		slope.y = (pair["z+"] - pair["z-"]) / (2.0 * pair["zspan"])

	# Drift: the current pushes the tether offset; the mooring spring reels
	# it back, and the tether caps how far downstream a hull can wander.
	var cur := _current(center)
	_drift += cur * (DRIFT_PUSH * delta)
	_drift = _drift.lerp(Vector2.ZERO, clampf(TETHER_RETURN * delta, 0.0, 1.0))
	_drift = _drift.limit_length(tether)

	# Apply: horizontal from the tether, vertical a spring to the surface.
	var pos := target.position
	pos.x = moor.x + _drift.x
	pos.z = moor.z + _drift.y
	pos.y = lerpf(pos.y, height, clampf(RISE * delta, 0.0, 1.0))
	target.position = pos

	# Lean: swing local +Y toward the surface normal, clamped to a gentle
	# tilt (the swell rolls a hull; it never rolls it over).
	var normal := Vector3(-slope.x, 1.0, -slope.y)
	var tilt := minf(normal.angle_to(Vector3.UP), LEAN_MAX)
	var goal := Basis.IDENTITY
	if tilt > 1e-4:
		var axis := Vector3.UP.cross(normal)
		if axis.length() > 1e-5:
			goal = Basis(axis.normalized(), tilt)
	# Ease ONLY the lean; the placed heading and scale ride through untouched
	# (rebuilding the basis each frame, not slerping the whole transform, so a
	# scaled or yawed raft keeps both).
	_lean = _lean.slerp(goal, clampf(LEAN_RATE * delta, 0.0, 1.0))
	target.basis = (_lean * Basis(Vector3.UP, _yaw)).scaled(_scale)


func _surface(pos: Vector3, t: float) -> Vector3:
	if surface_fn.is_valid():
		return surface_fn.call(pos, t)
	var base := Terrain.water_surface(pos.x, pos.z)
	if base < -1e11:
		base = moor.y   # off the water (shouldn't happen at a mooring): hold
	var swell := Vector3.ZERO
	if rides_swell and SeaSwell.enabled:
		swell = SeaSwell.probe_at(pos.x, pos.z, t)
	return Vector3(swell.x, base + swell.y, swell.z)


func _current(pos: Vector3) -> Vector2:
	if current_fn.is_valid():
		return current_fn.call(pos)
	return WaterField.current_at(pos)
