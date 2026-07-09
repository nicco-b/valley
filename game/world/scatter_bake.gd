class_name ScatterBake
## Loads Strata's BAKED scatter export (strata M4) — the offline answer to the
## runtime per-cell hash roll. When Strata's bless writes `world_vN/scatter/`
## and the importer copies it to `res://data/scatter/baked/`, the world streamer
## instances THESE placements instead of rolling its own: same props, but frozen
## (so the world is identical bless-to-bless) and — the point — with stable ids,
## so a hand-moved instance persists (ScatterHand) and survives a seed re-roll.
##
## When no baked export exists (a content-empty game, or a world blessed before
## M4), has_baked() is false and the streamer falls back to the runtime roll —
## valley-today behavior byte-for-byte, the FW1 content-empty boot law.
##
## FORMAT (Sources/StrataCore/Export/ScatterExport.swift is the contract):
##   data/scatter/baked/manifest.json  { format, cell_size_m, count, world,
##                                       cells:[{cell:[cx,cz], file, count, sha256}] }
##   data/scatter/baked/cell_<cx>_<cz>.json  [{id, cat, x, y, z, yaw, scale, pick}]
## The cell index matches the streamer's own (cell c centered on c*CELL_SIZE),
## so cell (cx,cz) loads directly — no re-bucketing.

const DIR := "res://data/scatter/baked"
const MANIFEST := DIR + "/manifest.json"

## Cached manifest (null = not yet probed, {} = probed and absent/invalid).
static var _manifest: Variant = null


## Is a usable baked scatter export present? Cheap after the first probe.
static func has_baked() -> bool:
	return not _read_manifest().is_empty()


## The baked cell grid size in meters (0 when no export). The streamer asserts
## this matches its own CELL_SIZE before trusting a cell file.
static func cell_size() -> float:
	var m := _read_manifest()
	return float(m.get("cell_size_m", 0.0))


## Baked placements for one cell, with the hand's edits (ScatterHand) applied:
## moved props repositioned, deleted props dropped. [] when there is no baked
## export or the cell holds no props. Each entry: {id, cat, x, y, z, yaw, scale,
## pick, moved}. Read at stream time — one small file per cell.
static func load_cell(c: Vector2i) -> Array:
	if not has_baked():
		return []
	var path := "%s/cell_%d_%d.json" % [DIR, c.x, c.y]
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Array):
		push_warning("[scatter_bake] malformed cell file: " + path)
		return []
	var out: Array = []
	for raw: Variant in parsed:
		if not (raw is Dictionary):
			continue
		var eff: Variant = ScatterHand.apply(raw)
		if eff == null:  # hand-deleted
			continue
		out.append(eff)
	return out


## Drop the cached manifest so a fresh import (or a test) is seen. Called by the
## importer after it writes the baked dir, and by tests.
static func reset() -> void:
	_manifest = null


static func _read_manifest() -> Dictionary:
	if _manifest != null:
		return _manifest
	_manifest = {}
	if not FileAccess.file_exists(MANIFEST):
		return _manifest
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary and int((parsed as Dictionary).get("format", 0)) == 1:
		_manifest = parsed
	else:
		push_warning("[scatter_bake] unreadable manifest: " + MANIFEST)
	return _manifest
