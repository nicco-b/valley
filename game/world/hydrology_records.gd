class_name HydrologyRecords
## ONE water truth, one converter (STUDY_WATER_TERRAIN §4 W4): a Strata
## export's hydrology.json becomes the game's water RECORDS here — the same
## dict schema whether the caller is the blessed importer (writes them to
## data/water/, tools/strata/import_world.gd) or the pre-bless resolve
## (seats them in memory, Terrain.preview_water). Both faces of the pane
## consume the records the SAME builder made; neither ever re-derives
## depth/feather/outline shapes on its own.
##
## Pure and deterministic: dict-in, dicts-out, no I/O, no engine state.
## Key insertion order is load-bearing — the importer JSON-stringifies these
## dicts verbatim, so reordering keys would churn every blessed world file.

## Largest-first lake cap: Strata's solver reports EVERY filled depression
## over its min_lake_area_m2 (an eroded 16km world holds hundreds), but
## every water body sits in Terrain's per-sample loops (height carve,
## water_surface) — records are a budget, not a survey. Rivers arrive
## pre-capped by the doc's max_rivers.
const LAKE_MAX := 24


## The export's rivers → hyd_* river record dicts (the rivers/*.json shape
## Terrain._river_from_record reads). Rivers with fewer than 2 nodes are
## dropped, exactly like the importer always did.
static func river_records(hydro: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Variant in hydro.get("rivers", []) as Array:
		if not (r is Dictionary):
			continue
		var nodes: Array = (r as Dictionary).get("nodes", [])
		if nodes.size() < 2:
			continue
		# Channel depth/feather from the river's size (width ∝ √discharge). The
		# nodes are carried through VERBATIM — one water truth: STUDY_WATER_TERRAIN
		# §4 W2 makes each node's `surface` the honest ε=0 water line (monotone
		# non-increasing head→mouth), curvature-resampled and Chaikin-smoothed at
		# the bake, and adds per-node `discharge` + `grade`. The game ribbon reads
		# that surface straight (W1's carve already seated the bed under it), so
		# the burial the study photographed is gone with no second river renderer.
		var mean_w := 0.0
		for n: Dictionary in nodes:
			mean_w += float(n.get("width", 1.0))
		mean_w /= nodes.size()
		var falls: Array = (r as Dictionary).get("waterfalls", [])
		out.append({
			"id": "hyd_%s" % String((r as Dictionary).get("id", "r")),
			"no_sim": true,  # region-tier water, off the soak digest (importer rule)
			"depth": snappedf(clampf(0.5 + 0.12 * mean_w, 1.0, 3.0), 0.01),
			"feather": snappedf(clampf(mean_w * 0.5, 4.0, 12.0), 0.1),
			"catchment_m2": float((r as Dictionary).get("catchment_m2", 0.0)),
			"nodes": nodes,
			"waterfalls": falls,
			"source": "strata_hydrology",
		})
	return out


## The export's lakes → hyd_* lake record dicts (Terrain._lake_from_record's
## shape), capped to LAKE_MAX — the solver already sorts lakes by descending
## area, so keeping the head of the list keeps the biggest. basin depth 0:
## the export tile already carries the depression (the solver found it, it
## never carved it) — only an authored lake carves its own basin.
static func lake_records(hydro: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lakes: Array = (hydro.get("lakes", []) as Array).slice(0, LAKE_MAX)
	for l: Variant in lakes:
		if not (l is Dictionary and (l as Dictionary).has("x")
				and (l as Dictionary).has("z") and (l as Dictionary).has("radius")
				and (l as Dictionary).has("surface")):
			continue
		var lk: Dictionary = l
		var rec := {
			"id": "hyd_%s" % String(lk.get("id", "l")),
			"no_sim": true,
			"center": {"x": float(lk["x"]), "z": float(lk["z"])},
			"radius": float(lk["radius"]),
			"surface": float(lk["surface"]),
			"depth": float(lk.get("depth", 0.0)),
			"basin": {"radius": float(lk["radius"]), "depth": 0.0},
			"outlet": "aquifer",
			"source": "strata_hydrology",
		}
		# The solver's TRUE shoreline (P2+): an ordered closed polygon in world
		# meters, normalized to plain floats. A pre-outline export simply omits
		# the key (the disc fallback) — and so does the written record, so
		# re-imported blessed files stay byte-identical to the pre-W4 importer.
		var outline_raw: Array = lk.get("outline", [])
		if not outline_raw.is_empty():
			var ring: Array = []
			for p: Dictionary in outline_raw:
				ring.append({"x": float(p["x"]), "z": float(p["z"])})
			rec["outline"] = ring
		out.append(rec)
	return out


## Total waterfalls across every kept river — the reply-line count (import and
## preview both name it), counted straight off the raw export (falls ride
## every river regardless of the LAKE_MAX lake cap, which never touches rivers).
static func fall_count(hydro: Dictionary) -> int:
	var total := 0
	for r: Variant in hydro.get("rivers", []) as Array:
		if r is Dictionary:
			total += ((r as Dictionary).get("waterfalls", []) as Array).size()
	return total
