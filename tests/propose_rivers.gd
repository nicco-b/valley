extends SceneTree
## Map pipeline stage C: propose river records from the erosion FLOW map
## (the Toolkit). The bake's droplets already found where water wants to
## run; this traces the MAJOR channels down the carved valleys and writes
## them as river records (data/water/rivers/gen_*.json, no_sim + gitignored
## local cache). Rebuilt 2026-07-05 after the first pass's playtest:
##  - ~5-10 rivers, not 40: headwaters trace first, a wide claim mask
##    makes parallel gullies coalesce, tributaries merge into trunks,
##    and only channels that reach the sea (or a trunk) survive.
##  - meanders, not grid corners: Chaikin-smoothed after tracing, then
##    resampled at a uniform node spacing.
##  - water LIES ON the terrain: nodes every ~45m, surface bilinear from
##    the BAKED heightfield (same bake the tile record ships, so the
##    ribbon sits in the carved valleys), clamped monotonically
##    non-increasing downstream. The carve interpolates the same
##    segments the ribbon does, so the bed stays below every span.
## Delete the ones you dislike, or re-run with different knobs.
## Run: godot --headless --path . -s res://tests/propose_rivers.gd
const WORK := 512  # tracing grid resolution (32m cells over 16.4km)
const FLOW_PCTILE := 0.90  # only cells above this flow percentile seed traces
const MAX_RIVERS := 10
const CLAIM_R := 5  # cells (~160m): gullies this close to a river coalesce
const MIN_CELLS := 20  # drop channels shorter than ~640m
const NODE_SPACING := 45.0  # meters between record nodes (dense = grounded)
const SURFACE_DIP := 0.2  # waterline sits this far below the baked ground


func _init() -> void:
	var t: Node = load("res://game/world/terrain.gd").new()
	t._ready()
	if t.kernel == null:
		print("PROPOSE FAIL: native kernel required"); quit(); return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/world/guide.json"))
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		"res://data/world/elevation_guide.exr"))
	img.convert(Image.FORMAT_RF)
	var gmin := float(meta.guide_min)
	var gspan := float(meta.guide_max) - gmin
	var inv_gamma := 1.0 / float(meta.get("guide_gamma", 1.0))
	var guide := img.get_data().to_float32_array()
	for i in guide.size():
		guide[i] = gmin + pow(clampf(guide[i], 0.0, 1.0), inv_gamma) * gspan
	var res := int(meta.out_res)
	var world_size := float(meta.world_size)
	var origin := Vector2(float(meta.origin.x), float(meta.origin.z))
	var baked: Dictionary = t.kernel.bake_terrain(guide, img.get_width(),
		world_size, res, int(meta.seed), meta.params)
	var H: PackedFloat32Array = baked.height
	var FL: PackedFloat32Array = baked.flow

	# Downsample height (avg) + flow (sum) to the WORK grid for tracing.
	var down := res / WORK
	var h := PackedFloat32Array(); h.resize(WORK * WORK)
	var fl := PackedFloat32Array(); fl.resize(WORK * WORK)
	for wz in WORK:
		for wx in WORK:
			var hs := 0.0
			var fs := 0.0
			for dz in down:
				for dx in down:
					var i := (wz * down + dz) * res + (wx * down + dx)
					hs += H[i]; fs += FL[i]
			h[wz * WORK + wx] = hs / (down * down)
			fl[wz * WORK + wx] = fs

	# Flow threshold at the percentile.
	var sorted := fl.duplicate(); sorted.sort()
	var thresh: float = maxf(sorted[int(sorted.size() * FLOW_PCTILE)], 1.0)
	var sea := float(meta.params.sea_level)
	var cell_m := world_size / WORK

	# Candidate headwaters, highest-first (trunks form before tributaries).
	var cands: Array = []
	for i in WORK * WORK:
		if fl[i] >= thresh and h[i] > sea + 3.0:
			cands.append(i)
	cands.sort_custom(func(a: int, b: int) -> bool: return h[a] > h[b])

	# on_river = exact channel cells; claimed = wide coalescing halo.
	var on_river := PackedByteArray(); on_river.resize(WORK * WORK)
	var claimed := PackedByteArray(); claimed.resize(WORK * WORK)
	var rivers: Array = []
	for start: int in cands:
		if claimed[start] != 0 or rivers.size() >= MAX_RIVERS:
			continue
		var path: Array = []
		var cur := start
		var ends_ok := false  # reached the sea or merged into a trunk
		while true:
			path.append(cur)
			if h[cur] <= sea + 0.5:
				ends_ok = true
				break  # reached the sea
			# Descend into the neighbor the droplets carved hardest:
			# among the strictly-lower 8-neighbors, take the max flow
			# (keeps the trace in the valley floor instead of cutting
			# corners down the steepest face).
			var cx := cur % WORK
			var cz := cur / WORK
			var nxt := -1
			var nxt_fl := -1.0
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					var nx := cx + ox
					var nz := cz + oz
					if nx < 0 or nz < 0 or nx >= WORK or nz >= WORK:
						continue
					var ni := nz * WORK + nx
					if h[ni] < h[cur] and fl[ni] > nxt_fl:
						nxt_fl = fl[ni]; nxt = ni
			if nxt < 0:
				break  # local pit above the sea — not a river, drop it
			cur = nxt
			if on_river[cur] != 0:
				path.append(cur)  # tributary: join the trunk's channel
				ends_ok = true
				break
			if path.size() > WORK * 2:
				break  # safety
		if not ends_ok or path.size() < MIN_CELLS:
			continue
		rivers.append(path)
		for pi: int in path:
			on_river[pi] = 1
			var px := pi % WORK
			var pz := pi / WORK
			for oz in range(-CLAIM_R, CLAIM_R + 1):
				for ox in range(-CLAIM_R, CLAIM_R + 1):
					var qx := px + ox
					var qz := pz + oz
					if qx >= 0 and qz >= 0 and qx < WORK and qz < WORK:
						claimed[qz * WORK + qx] = 1

	# Clear old generated rivers, write the new ones as records.
	var dir := DirAccess.open("res://data/water/rivers")
	if dir:
		for f in dir.get_files():
			if f.begins_with("gen_") and f.ends_with(".json"):
				dir.remove(f)
	var written := 0
	for path: Array in rivers:
		# Cell centers → world points, Chaikin ×2, uniform resample.
		var pts: Array = []
		for pi: int in path:
			pts.append(origin + Vector2((pi % WORK) + 0.5,
				(pi / WORK) + 0.5) * cell_m)
		pts = _chaikin(_chaikin(_chaikin(pts)))
		pts = _resample(pts, NODE_SPACING)
		if pts.size() < 3:
			continue
		var nodes: Array = []
		var surf := 1e12
		var wdt := 0.0
		for p: Vector2 in pts:
			# Surface from the BAKED heightfield (what the tile record
			# ships), never Terrain.height: the water must sit in the
			# same carved valleys the terrain will show. Downhill only.
			surf = minf(surf, _bilinear(H, res, origin, world_size, p) - SURFACE_DIP)
			# Width grows with flow and never narrows downstream.
			var ci := clampi(int((p.y - origin.y) / cell_m), 0, WORK - 1) * WORK \
				+ clampi(int((p.x - origin.x) / cell_m), 0, WORK - 1)
			wdt = maxf(wdt, clampf(2.5 + fl[ci] / thresh * 0.9, 3.0, 16.0))
			nodes.append({"x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1),
				"width": snappedf(wdt, 0.1), "surface": snappedf(surf, 0.1)})
		var rec := {"id": "gen_%d" % written, "no_sim": true,
			"depth": 1.4, "feather": 6.0, "nodes": nodes}
		var fh := FileAccess.open("res://data/water/rivers/gen_%d.json" % written,
			FileAccess.WRITE)
		fh.store_string(JSON.stringify(rec, "\t") + "\n")
		fh.close()
		written += 1
	print("RIVERS PROPOSED: %d (from %d channel candidates, flow>%.0f)" % [
		written, cands.size(), thresh])
	quit()


# One Chaikin corner-cutting pass (endpoints kept): grid staircases → curves.
func _chaikin(pts: Array) -> Array:
	if pts.size() < 3:
		return pts
	var out: Array = [pts[0]]
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out


# Uniform arc-length resample at `spacing` meters (endpoints kept).
func _resample(pts: Array, spacing: float) -> Array:
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


func _bilinear(H: PackedFloat32Array, res: int, origin: Vector2,
		world_size: float, p: Vector2) -> float:
	var u := clampf((p.x - origin.x) / world_size * res - 0.5, 0.0, res - 1.001)
	var v := clampf((p.y - origin.y) / world_size * res - 0.5, 0.0, res - 1.001)
	var x0 := int(u)
	var z0 := int(v)
	var fx := u - x0
	var fz := v - z0
	var x1 := mini(x0 + 1, res - 1)
	var z1 := mini(z0 + 1, res - 1)
	return lerpf(
		lerpf(H[z0 * res + x0], H[z0 * res + x1], fx),
		lerpf(H[z1 * res + x0], H[z1 * res + x1], fx), fz)
