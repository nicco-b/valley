class_name ToolkitSnap
## Pure snapping math for the Toolkit's placement hand (audit R1 polish:
## snap-to-ground, align-to-normal, grid snap). NO engine state, NO autoload
## lookups — every function is a pure map from its arguments, so the scene
## tests pin the math directly (the acceptance's "pure functions where
## possible"). The Toolkit samples Terrain.height and feeds the results in;
## the streamer reads the resulting record fields back at instantiation.
##
## Three snaps, three record shapes, all data (editable after, like yaw):
##   grid  -> the XZ lands on a `step`-metre lattice (snap_to_grid).
##   ground-> the record seats flush on the terrain (ground_dy = 0; the
##            Toolkit sets the field, seat_y already honours it).
##   normal-> the record carries a `tilt` normal; the streamer lays the mesh
##            against the slope via aligned_basis, then turns it by yaw.
## Grid snap off / a flat normal are the identity — off is never a special
## code path, just step<=0 or up=+Y.


## Snap a world XZ to the nearest intersection of a `step`-metre grid, Y left
## untouched (height is the ground's job, not the grid's — the seat rides
## ground_dy or the tilt afterwards). step <= 0 is the identity map: grid
## snap off changes nothing, no branch at the call site.
static func snap_to_grid(pos: Vector3, step: float) -> Vector3:
	if step <= 0.0:
		return pos
	return Vector3(snappedf(pos.x, step), pos.y, snappedf(pos.z, step))


## The basis for a record aligned to a ground normal, then turned `yaw` about
## that (tilted) up — align-to-normal. up = the normal; the yaw rides around
## the tilted up so a fence still faces where you turned it, only now laid
## against the slope instead of standing proud of it. A degenerate/zero
## normal falls back to +Y (flat), so a bad sample never returns a broken
## basis. Pure: normal + yaw in, an orthonormal basis out (scale is the
## streamer's to apply on top).
static func aligned_basis(normal: Vector3, yaw: float) -> Basis:
	var up := normal.normalized()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	# Tangent = world +X projected onto the plane perpendicular to up (a
	# near-±X up falls back to +Z), so a flat up reproduces the identity and
	# aligned_basis(+Y, yaw) == Basis(Y, yaw) exactly — align-on and align-off
	# agree on where yaw 0 faces. bitangent = tangent x up closes a proper
	# right-handed frame (det +1).
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.RIGHT)) > 0.99 else Vector3.RIGHT
	var tangent := (ref - up * ref.dot(up)).normalized()
	var bitangent := tangent.cross(up)
	# Columns (x, y, z) = (tangent, up, bitangent): local +Y maps to the
	# normal. Post-multiply the yaw about local Y so it turns about the up.
	return Basis(tangent, up, bitangent) * Basis(Vector3.UP, yaw)


## The ground normal from three height samples around a point — a finite-
## difference estimate (the Toolkit samples Terrain.height at the point, `eps`
## east, and `eps` north, and passes the three heights here). Pure: the
## samples in, the unit normal out (always oriented +Y up). Flat ground (all
## three equal) returns exactly (0, 1, 0). `eps` must be > 0.
static func ground_normal(h_center: float, h_east: float, h_north: float,
		eps: float) -> Vector3:
	# Tangent along +X: (eps, dh_east, 0); along +Z: (0, dh_north, eps).
	var east := Vector3(eps, h_east - h_center, 0.0)
	var north := Vector3(0.0, h_north - h_center, eps)
	# north x east points +Y for a rising-to-the-northeast slope; orient it.
	var n := north.cross(east)
	if n.y < 0.0:
		n = -n
	return n.normalized()


## The next grid step in a preset ladder (the H-key cycle: 1 -> 2 -> 4 -> 8
## -> 16 -> 1). `dir` +1 coarsens, -1 refines; the current value snaps to the
## nearest rung first so a link-set odd step still lands on the ladder. Pure.
const GRID_STEPS: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0]
static func cycle_grid_step(current: float, dir: int) -> float:
	# Nearest rung to `current` (a set-from-link value need not be on the
	# ladder); ties break to the LARGER rung (round-half-up), so 3 -> 4.
	var best := 0
	for i in GRID_STEPS.size():
		if absf(GRID_STEPS[i] - current) <= absf(GRID_STEPS[best] - current):
			best = i
	return GRID_STEPS[wrapi(best + dir, 0, GRID_STEPS.size())]


# --- Kit-bashing sockets (L11). A socket is DATA on a card: a local point
# (`pos`) and a facing (`yaw`, radians about +Y) where a piece clicks onto
# another, plus a `type` tag that decides compatibility (two sockets mate iff
# their types match). Snapping is pure math here — the Toolkit reads a card's
# sockets, transforms the placed pieces' sockets to world, and asks these
# functions where the incoming piece must sit so its socket MATES a nearby one
# (positions coincident, facings opposed — the "click together" law). Planar
# by design: kit pieces carry a yaw + scale, never a full tilt, so a socket is
# an (XZ-position, Y, yaw) frame and every function below is closed over
# Vector3 + float + arrays — no engine state, unit-testable like the grid math.


## A socket carried from a piece's LOCAL frame into the world, given the
## piece's planar pose (position, yaw about +Y, uniform scale). The local
## offset rides the piece's scale then its yaw; the socket's facing is the
## piece yaw plus the socket's own local yaw. Returns {pos: Vector3, yaw:
## float}. Pure: pose + local socket in, world socket out.
static func socket_world(piece_pos: Vector3, piece_yaw: float, piece_scale: float,
		local_pos: Vector3, local_yaw: float) -> Dictionary:
	var wpos := piece_pos + (Basis(Vector3.UP, piece_yaw) * (local_pos * piece_scale))
	return {"pos": wpos, "yaw": wrapf(piece_yaw + local_yaw, 0.0, TAU)}


## The pose an incoming piece must take so ITS socket (local `in_local_pos` /
## `in_local_yaw`, at scale `in_scale`) mates a TARGET world socket (`target_pos`
## / `target_yaw`): the two socket points coincide and the incoming socket faces
## OPPOSITE the target (yaw + PI — two ends clicking face to face). Returns the
## incoming piece's {pos: Vector3, yaw: float}. The exact inverse of
## socket_world: feed this result back through socket_world(in_local_*) and the
## world socket returns to `target_pos` facing `target_yaw + PI`. Pure.
static func snap_to_socket(target_pos: Vector3, target_yaw: float,
		in_local_pos: Vector3, in_local_yaw: float, in_scale: float) -> Dictionary:
	var piece_yaw := wrapf(target_yaw + PI - in_local_yaw, 0.0, TAU)
	var piece_pos := target_pos - (Basis(Vector3.UP, piece_yaw) * (in_local_pos * in_scale))
	return {"pos": piece_pos, "yaw": piece_yaw}


## The best socket mate for a piece dropped at `cursor`: among `candidates`
## (world sockets of the pieces already placed nearby, each {type, pos, yaw}),
## find the one NEAREST the cursor in XZ — within `radius` — that shares a type
## with any of the incoming piece's `in_sockets` (local {type, pos, yaw}), and
## return the incoming pose (from snap_to_socket) that mates it. {} when no
## compatible socket is in reach — the caller then places exactly as it would
## with socket snap off (the zero-regression floor). Ties resolve to the LAST
## equal-distance candidate (mirrors find_at); the caller passes candidates in a
## deterministic order. Pure: the cursor + the two socket lists in, a pose out.
static func best_socket_snap(cursor: Vector3, in_sockets: Array, candidates: Array,
		radius: float, in_scale: float) -> Dictionary:
	var best_d := radius
	var best: Dictionary = {}
	for cand: Dictionary in candidates:
		var ctype := String(cand.get("type", ""))
		if ctype == "":
			continue
		# The first incoming socket of the same type (deterministic by the
		# incoming list's order — a card's socket order is stable).
		var isock: Dictionary = {}
		for s: Dictionary in in_sockets:
			if String(s.get("type", "")) == ctype:
				isock = s
				break
		if isock.is_empty():
			continue
		var cpos: Vector3 = cand["pos"]
		var d := Vector2(cpos.x - cursor.x, cpos.z - cursor.z).length()
		if d <= best_d:
			best_d = d
			best = snap_to_socket(cpos, float(cand.get("yaw", 0.0)),
				isock["pos"], float(isock.get("yaw", 0.0)), in_scale)
	return best
