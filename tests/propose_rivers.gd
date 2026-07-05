extends SceneTree
## Map pipeline stage C: propose river records from the erosion FLOW map.
## The bake's droplets already found where water wants to run; this
## traces the major channels down the carved valleys and writes them as
## river records (data/water/rivers/gen_*.json, no_sim + gitignored
## local cache). They carve + render like any river but aren't
## sim-routed (Hydrology's domain is the home watershed for now). Delete
## the ones you dislike, or re-run with a different FLOW_PCTILE.
## Run: godot --headless --path . -s res://tests/propose_rivers.gd
const WORK := 512  # tracing grid resolution (32m cells over 16.4km)
const FLOW_PCTILE := 0.90  # only cells above this flow percentile are channels
const MIN_NODES := 8  # skip gullies shorter than ~8 nodes
const MAX_RIVERS := 40
const NODE_STRIDE := 3  # decimate the traced path


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
	var baked: Dictionary = t.kernel.bake_terrain(guide, img.get_width(),
		float(meta.world_size), res, int(meta.seed), meta.params)
	var H: PackedFloat32Array = baked.height
	var FL: PackedFloat32Array = baked.flow

	# Downsample height (avg) + flow (sum) to the WORK grid.
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
	var thresh: float = sorted[int(sorted.size() * FLOW_PCTILE)]
	var sea := float(meta.params.sea_level)
	var cell_m := float(meta.world_size) / WORK
	var origin := Vector2(float(meta.origin.x), float(meta.origin.z))

	# Candidate channel cells, highest-first (headwaters trace before
	# their tributaries so trunks form and tributaries merge in).
	var cands: Array = []
	for i in WORK * WORK:
		if fl[i] >= thresh and h[i] > sea + 3.0:
			cands.append(i)
	cands.sort_custom(func(a: int, b: int) -> bool: return h[a] > h[b])

	var visited := PackedByteArray(); visited.resize(WORK * WORK)
	var rivers: Array = []
	for start: int in cands:
		if visited[start] != 0 or rivers.size() >= MAX_RIVERS:
			continue
		var path: Array = []
		var cur := start
		while true:
			var cx := cur % WORK
			var cz := cur / WORK
			path.append(cur)
			if h[cur] <= sea + 0.5:
				break  # reached the sea
			# steepest descent among the 8-neighborhood
			var lo := cur
			var lo_h := h[cur]
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					var nx := cx + ox
					var nz := cz + oz
					if nx < 0 or nz < 0 or nx >= WORK or nz >= WORK:
						continue
					var ni := nz * WORK + nx
					if h[ni] < lo_h:
						lo_h = h[ni]; lo = ni
			if lo == cur:
				break  # local pit — stop
			cur = lo
			if visited[cur] != 0:
				path.append(cur)  # merge into an existing river, then stop
				break
			if path.size() > WORK * 2:
				break  # safety
		# mark visited (small radius so parallel gullies coalesce)
		for pi: int in path:
			visited[pi] = 1
		if path.size() >= MIN_NODES:
			rivers.append(path)

	# Clear old generated rivers, write the new ones as records.
	var dir := DirAccess.open("res://data/water/rivers")
	if dir:
		for f in dir.get_files():
			if f.begins_with("gen_") and f.ends_with(".json"):
				dir.remove(f)
	var written := 0
	for path: Array in rivers:
		var nodes: Array = []
		for pi in range(0, path.size(), NODE_STRIDE):
			var idx: int = path[pi]
			var wpos := origin + Vector2((idx % WORK) + 0.5, (idx / WORK) + 0.5) * cell_m
			# width grows downstream with flow; surface sits at ground.
			var wdt: float = clampf(2.0 + fl[idx] / thresh * 1.5, 2.5, 14.0)
			nodes.append({"x": snappedf(wpos.x, 0.1), "z": snappedf(wpos.y, 0.1),
				"width": snappedf(wdt, 0.1),
				"surface": snappedf(t.height(wpos.x, wpos.y) + 0.2, 0.1)})
		if nodes.size() < 3:
			continue
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
