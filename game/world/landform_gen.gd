class_name LandformGen
extends RefCounted
## The map generator's composer (the Loom / the Toolkit). Turns a
## high-level SKETCH — a land outline plus typed elevation stamps (range,
## peak, plateau, basin, hills, volcano) — into an elevation field in
## METERS. The erosion bake (WorldBake.bake) then weathers it into
## believable terrain: you mark WHERE the mountains go, erosion makes
## GOOD mountains (drainage, valleys, talus). This replaces painting the
## grayscale guide by hand; the sketch is the source of truth, the guide
## its rendered intermediate.
##
## Sketch record (data/world/sketch.json):
##   {"sea_level": -2, "land_base": 6, "sea_base": -40,
##    "land": [ [[x,z],[x,z],...], ... ],          # coastline polygons
##    "stamps": [
##      {"kind":"range","nodes":[[x,z],...],"radius":700,"height":600,
##        "roughness":0.4},
##      {"kind":"peak","x":..,"z":..,"radius":400,"height":300},
##      {"kind":"plateau","x":..,"z":..,"radius":600,"height":180,"flat":0.5},
##      {"kind":"basin","x":..,"z":..,"radius":500,"depth":120},
##      {"kind":"hills","x":..,"z":..,"radius":900,"amp":45,"freq":0.004},
##      {"kind":"volcano","x":..,"z":..,"radius":650,"height":820,
##        "crater":0.12} ] }

const LAND_FEATHER := 220.0  # coastline softness (m)


## Compose the sketch into a meter heightfield, row-major res×res over a
## world_size square anchored at origin.
static func compose(sketch: Dictionary, res: int, world_size: float,
		origin: Vector2) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(res * res)
	var cell := world_size / res
	var sea_base := float(sketch.get("sea_base", -40.0))
	var land_base := float(sketch.get("land_base", 6.0))
	h.fill(sea_base)

	# Rolling base relief across ALL land — WITHOUT it the flats are dead
	# and erosion has nothing to carve; this is what makes the whole
	# continent read as terrain, not a plane with mountains dropped on it.
	var base_amp := float(sketch.get("base_relief", 38.0))
	var base_noise := FastNoiseLite.new()
	base_noise.seed = 7
	base_noise.frequency = float(sketch.get("base_freq", 0.0007))
	base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	base_noise.fractal_octaves = 4
	# Coastline noise: wiggle the outline in/out so coasts are coves and
	# headlands, not straight polygon edges.
	var coast_amp := float(sketch.get("coast_amp", 240.0))
	var coast_noise := FastNoiseLite.new()
	coast_noise.seed = 23
	coast_noise.frequency = float(sketch.get("coast_freq", 0.0011))
	coast_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	coast_noise.fractal_octaves = 3

	# 1) The coast + base: raise land polygon interiors to the shelf plus
	# rolling relief, feathered out to sea across a noised coastline.
	var land: Array = sketch.get("land", [])
	if not land.is_empty():
		for i in res * res:
			var p := origin + Vector2((i % res) + 0.5, (i / res) + 0.5) * cell
			var sd := _land_signed_distance(p, land) \
				+ coast_noise.get_noise_2d(p.x, p.y) * coast_amp
			var t := clampf(sd / LAND_FEATHER * 0.5 + 0.5, 0.0, 1.0)
			var landness := smoothstep(0.0, 1.0, t)
			var relief := (0.5 + 0.5 * base_noise.get_noise_2d(p.x, p.y)) * base_amp
			h[i] = lerpf(sea_base, land_base + relief, landness)

	# 2) The stamps, added on top of the shelf.
	var ridge_noise := FastNoiseLite.new()
	ridge_noise.seed = 1337
	ridge_noise.frequency = 0.0018
	var hill_noise := FastNoiseLite.new()
	hill_noise.seed = 91
	hill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	for s: Dictionary in sketch.get("stamps", []):
		_stamp(h, s, res, cell, origin, ridge_noise, hill_noise)
	return h


static func _stamp(h: PackedFloat32Array, s: Dictionary, res: int,
		cell: float, origin: Vector2, ridge_noise: FastNoiseLite,
		hill_noise: FastNoiseLite) -> void:
	var kind := String(s.get("kind", "peak"))
	var radius := float(s.get("radius", 400.0))
	# Bounding box in grid space (+ a margin) so we only touch nearby cells.
	var nodes: Array = s.get("nodes", [[s.get("x", 0.0), s.get("z", 0.0)]])
	var bb := Rect2(Vector2(nodes[0][0], nodes[0][1]), Vector2.ZERO)
	for n in nodes:
		bb = bb.expand(Vector2(n[0], n[1]))
	bb = bb.grow(radius + 4.0 * cell)
	var x0 := maxi(int((bb.position.x - origin.x) / cell), 0)
	var z0 := maxi(int((bb.position.y - origin.y) / cell), 0)
	var x1 := mini(int((bb.end.x - origin.x) / cell), res - 1)
	var z1 := mini(int((bb.end.y - origin.y) / cell), res - 1)
	var height := float(s.get("height", 300.0))
	for gz in range(z0, z1 + 1):
		for gx in range(x0, x1 + 1):
			var p := origin + Vector2(gx + 0.5, gz + 0.5) * cell
			var d := _dist_to_nodes(p, nodes)
			if d > radius:
				continue
			var t := d / radius  # 0 center .. 1 rim
			var i := gz * res + gx
			match kind:
				"peak", "range":
					# Smooth mound; ridges modulate along their length with
					# noise so a range has summits and saddles, not a wall.
					var f := smoothstep(1.0, 0.0, t)
					var rough := float(s.get("roughness", 0.35))
					var m := 1.0 - rough * (0.5 + 0.5 * ridge_noise.get_noise_2d(p.x, p.y))
					h[i] += height * f * f * m
				"plateau":
					# Flat top out to `flat`, steep shoulders to the rim.
					var flat := float(s.get("flat", 0.5))
					var f2 := smoothstep(1.0, flat, t)
					h[i] += height * f2
				"basin":
					var depth := float(s.get("depth", 120.0))
					h[i] -= depth * smoothstep(1.0, 0.0, t)
				"hills":
					var amp := float(s.get("amp", 45.0))
					hill_noise.frequency = float(s.get("freq", 0.004))
					var n := 0.5 + 0.5 * hill_noise.get_noise_2d(p.x, p.y)
					h[i] += amp * n * smoothstep(1.0, 0.0, t)
				"volcano":
					# Cone up to `height`, then a crater dip near the summit.
					var cone := smoothstep(1.0, 0.0, t)
					var crater := float(s.get("crater", 0.12))
					var dip := smoothstep(crater, 0.0, t) * height * 0.35
					h[i] += height * pow(cone, 1.3) - dip


# Distance from p to the nearest node/segment of a stamp (0 for a
# single-node peak inside its center).
static func _dist_to_nodes(p: Vector2, nodes: Array) -> float:
	if nodes.size() == 1:
		return p.distance_to(Vector2(nodes[0][0], nodes[0][1]))
	var best := 1e12
	for i in nodes.size() - 1:
		var a := Vector2(nodes[i][0], nodes[i][1])
		var b := Vector2(nodes[i + 1][0], nodes[i + 1][1])
		var ab := b - a
		var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * tt))
	return best


# Signed distance to the land region (positive inside any polygon,
# negative outside — the nearest edge distance). Coarse but smooth
# enough for a feathered coast.
static func _land_signed_distance(p: Vector2, land: Array) -> float:
	var best := 1e12
	var inside := false
	for poly: Array in land:
		if _point_in_poly(p, poly):
			inside = true
		best = minf(best, _dist_to_poly_edge(p, poly))
	return best if inside else -best


static func _point_in_poly(p: Vector2, poly: Array) -> bool:
	var n := poly.size()
	var c := false
	var j := n - 1
	for i in n:
		var vi := Vector2(poly[i][0], poly[i][1])
		var vj := Vector2(poly[j][0], poly[j][1])
		if ((vi.y > p.y) != (vj.y > p.y)) and \
				(p.x < (vj.x - vi.x) * (p.y - vi.y) / (vj.y - vi.y) + vi.x):
			c = not c
		j = i
	return c


static func _dist_to_poly_edge(p: Vector2, poly: Array) -> float:
	var best := 1e12
	var n := poly.size()
	for i in n:
		var a := Vector2(poly[i][0], poly[i][1])
		var b := Vector2(poly[(i + 1) % n][0], poly[(i + 1) % n][1])
		var ab := b - a
		var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * tt))
	return best
