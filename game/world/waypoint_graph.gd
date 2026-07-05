extends Node
## WaypointGraph (autoload): the far-tier road network — SIM_ROADMAP
## Phase A's last piece. Roads are node polylines in data/roads/*.json
## (authored, disposable fixtures until the 12km map); the graph derives:
## consecutive nodes edge together, coincident nodes (<6m) across roads
## junction. Callers get world-space waypoint routes via route(); Nav
## uses it as the honest middle tier between navmesh and straight line.
## Pure data — no scene nodes, works unstreamed, caravans will walk it.

const JOIN_RADIUS := 6.0

var points: Array[Vector2] = []
var edges: Array[PackedInt32Array] = []  # adjacency per point


func _ready() -> void:
	var dir := DirAccess.open("res://data/roads")
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/roads/" + f))
		if not (parsed is Dictionary and parsed.has("nodes")):
			push_error("[roads] bad road record: " + f)
			continue
		var rec: Dictionary = parsed
		var prev := -1
		for n in rec["nodes"]:
			var p := Vector2(float(n["x"]), float(n["z"]))
			var idx := _point_at(p)
			if prev >= 0 and idx != prev:
				edges[prev].append(idx)
				edges[idx].append(prev)
			prev = idx
	print("[roads] graph: %d points" % points.size())


func _point_at(p: Vector2) -> int:
	for i in points.size():
		if points[i].distance_to(p) < JOIN_RADIUS:
			return i
	points.append(p)
	edges.append(PackedInt32Array())
	return points.size() - 1


func nearest(p: Vector2) -> int:
	var best := -1
	var best_d := 1e12
	for i in points.size():
		var d := points[i].distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## A* over the road graph; world waypoints from's-nearest -> to's-nearest.
## Empty when there is no graph.
func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	var a := nearest(from)
	var b := nearest(to)
	var open := [a]
	var came := {a: -1}
	var g := {a: 0.0}
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			var fa: float = g[open[i]] + points[open[i]].distance_to(points[b])
			var fb: float = g[open[best_i]] + points[open[best_i]].distance_to(points[b])
			if fa < fb:
				best_i = i
		var cur: int = open.pop_at(best_i)
		if cur == b:
			break
		for nb in edges[cur]:
			var ng: float = g[cur] + points[cur].distance_to(points[nb])
			if not g.has(nb) or ng < g[nb]:
				g[nb] = ng
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)
	if not came.has(b):
		return out
	var i := b
	while i != -1:
		out.append(points[i])
		i = came[i]
	out.reverse()
	return out
