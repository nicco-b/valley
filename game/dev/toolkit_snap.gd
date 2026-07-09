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
