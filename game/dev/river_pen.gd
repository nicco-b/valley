class_name RiverPen
extends RefCounted
## The river pen's shared core (the Toolkit): turn a hand-drawn course
## into a live, persisted river record. Used by BOTH pens — the map
## (top-down clicks) and the flyover (points dropped on the ground) —
## so the densify/surface/clamp rules can never drift apart. The clicked
## polyline is densified to node spacing, each node takes its surface
## from the CURRENT terrain clamped monotonically downhill, width tapers
## head→mouth, then Terrain.add_river carves it live and the record is
## written to data/water/rivers/pen_N.json (survives restart).

const NODE_SPACING := 50.0   # densify the clicked course to this
const SURFACE_DIP := 0.3     # waterline sits this far below ground
const MAX_CARVE := 3.0       # a node's surface can't sit deeper than this
	# below its OWN ground — so a hand-drawn path that rises never gouges
	# a canyon (the monotone clamp would otherwise drag the bed to the
	# lowest point seen; bounding it trades physical purity for no-gouge)
const WIDTH_HEAD := 3.0
const WIDTH_MOUTH := 11.0
const DEPTH := 1.6
const FEATHER := 8.0
const RIVER_DIR := "res://data/water/rivers"


## Commit a drawn course (world-XZ points). Returns the live river dict,
## or {} if the course is too short.
static func commit(points: Array) -> Dictionary:
	if points.size() < 2:
		return {}
	var pts := densify(points, NODE_SPACING)
	var nodes: Array = []
	var running := INF  # monotone-downhill waterline cap
	var length := 0.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var ground: float = Terrain.height(p.x, p.y)
		running = minf(running, ground - SURFACE_DIP)
		# Monotone downhill, but never deeper than MAX_CARVE below THIS
		# node's ground: a course that climbs lifts the waterline back up
		# with the terrain instead of gouging a trench down to it.
		var surf: float = maxf(running, ground - MAX_CARVE)
		if i > 0:
			length += p.distance_to(pts[i - 1])
		var f := float(i) / maxf(pts.size() - 1, 1)
		nodes.append({
			"x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1),
			"width": snappedf(lerpf(WIDTH_HEAD, WIDTH_MOUTH, f), 0.1),
			"surface": snappedf(surf, 0.1)})
	var n := next_index()
	# Rough catchment for the region tier: a ~200m drainage strip along
	# the course (mood physics; a longer river breathes wider).
	var rec := {"id": "pen_%d" % n, "no_sim": true,
		"depth": DEPTH, "feather": FEATHER,
		"catchment_m2": snappedf(length * 200.0, 1.0), "nodes": nodes}
	var river := Terrain.add_river(rec)
	var fh := FileAccess.open("%s/pen_%d.json" % [RIVER_DIR, n], FileAccess.WRITE)
	fh.store_string(JSON.stringify(rec, "\t") + "\n")
	fh.close()
	HUD.notify("river penned (%d nodes, %.0fm) — carving" % [nodes.size(), length])
	return river


## Uniform arc-length resample of a clicked polyline (endpoints kept), so
## the carve's node-lerped bed follows the terrain instead of bridging
## between far-apart clicks.
static func densify(pts: Array, spacing: float) -> Array:
	var out: Array = [pts[0]]
	var carry := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var ab: Vector2 = pts[i + 1] - a
		var seg := ab.length()
		if seg < 1e-4:
			continue
		var s := spacing - carry
		while s < seg:
			out.append(a + ab * (s / seg))
			s += spacing
		carry = seg - (s - spacing)
	out.append(pts[pts.size() - 1])
	return out


static func next_index() -> int:
	var n := 0
	var dir := DirAccess.open(RIVER_DIR)
	if dir:
		for f in dir.get_files():
			if f.begins_with("pen_") and f.ends_with(".json"):
				n = maxi(n, f.trim_prefix("pen_").trim_suffix(".json").to_int() + 1)
	return n
