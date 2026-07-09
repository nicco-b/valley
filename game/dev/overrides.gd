extends Node
## The overrides emitter (ONE_APP P4, audit R2) — hand work in the game
## becomes DATA that Strata's re-rolls respect. Every stroke-quiet flush
## (and F5, and Toolkit exit) rewrites `data/overrides/overrides.json`:
## the seam artifact Strata reads at bless/Send to diff placements by
## stable id and to composite the hand-drawn terrain deltas over a fresh
## bake. The game never reads this file back — it is one-way, game →
## Strata, exactly the `Strata ◀─overrides.json── game` channel of the
## seam contract. Committed like the cell records it summarizes (never
## a gitignored cache: its whole purpose is crossing to the other repo).
##
## SCHEMA (format 1) — sorted keys, tab indent, trailing newline:
## {
##   "format": 1,
##   "placements": {                    # CURRENT records, keyed by stable id
##     "<id>": {                        #   (CellRecords mints ids at add;
##       "kit": String,                 #    legacy rows are named at emit)
##       "x": float, "y": float, "z": float,   # absolute world meters
##       "yaw": float, "scale": float,
##       "ground_dy": float?,           # height above ground at placement —
##                                      #   the re-seat anchor Strata's diff
##                                      #   uses for honest submergence
##       "day": int?, "snap": bool?,    # extra record keys ride verbatim
##       "cell": [int, int]             # the cell file it lives in
##     }, ...
##   },
##   "scatter": {                       # P4 scatter half (strata M4): the hand's
##     "<id>": {                        #   edits to BAKED-scatter instances,
##       "op": "move" | "delete",       #   keyed by their seed-independent id.
##       "x": float, "y": float, "z": float,   # move payload (absolute meters)
##       "yaw": float, "scale": float,
##       "cat": String, "pick": float   # so a re-roll that rejects the candidate
##     }, ...                           #   can still force-add it (Strata's
##   },                                 #   scatter export replays these last)
##   "terrain": {
##     "layers": [                      # additive hand-work layers, meters,
##       {                              #   composited over the blessed bake
##         "id": "pen_override" | "sculpt",
##         "file": "data/overrides/terrain_<id>.f32z",
##         "encoding": "deflate_f32le", # zlib-wrapped DEFLATE of row-major
##                                      #   float32 LE, res[0]*res[1] values
##         "sha256": String,            # of the .f32z file bytes
##         "res": [int, int],           # grid width, height
##         "x0": float, "z0": float,    # world position of texel (0,0)
##         "m_per_px": float,           # texel pitch, meters
##         "source": String,            # the live layer this snapshots
##         "rect": {"x","z","w","h"}?   # world rect known to hold strokes
##       }, ...
##     ]
##   }
## }
## Sampling law (both sides): delta(x,z) = bilinear(grid,
## (x - x0) / m_per_px, (z - z0) / m_per_px), zero outside the grid.
## Effective ground = blessed bake + every layer's delta.

const DIR := "res://data/overrides"
const FILE := DIR + "/overrides.json"
const FORMAT := 1

## Hand edits newer than overrides.json — the Toolkit's stroke-quiet
## flush clock reads this (a place/delete is write-through for the cell
## file but still needs an emit; pen/sculpt saves mark it in emit's
## callers implicitly by being part of the same flush).
var pending := false

## Per-layer skip cache: source path -> {mtime, entry}. A flush that
## saved no terrain re-uses the previous entry instead of re-encoding
## a multi-megabyte grid (correct: the source file IS the save truth).
var _layer_cache: Dictionary = {}


func _ready() -> void:
	# Any record mutation (add/remove/insert/update) makes the artifact
	# stale — even the write-through ones the flush clock can't see.
	CellRecords.changed.connect(func(_cell: Vector2i) -> void: pending = true)


## Rewrite the seam artifact from current truth. Called on the Toolkit's
## stroke-quiet flush, F5, and exit — never from the sim (the soak path
## does no IO here by construction). Returns {placements, layers} so
## callers and tests can be honest about what landed.
func emit() -> Dictionary:
	var placements := _gather_placements()
	var layers := _gather_layers()
	# The hand's baked-scatter edits (ScatterHand's own store) ride the seam
	# artifact so Strata replays them on the next re-bake. Absent (no baked
	# scatter, or none edited) the key is omitted — pre-M4 artifacts unchanged.
	var scatter: Dictionary = ScatterHand.deltas().duplicate(true)
	var doc := {
		"format": FORMAT,
		"placements": placements,
		"terrain": {"layers": layers},
	}
	if not scatter.is_empty():
		doc["scatter"] = scatter
	var text := JSON.stringify(doc, "\t", true) + "\n"
	# Unchanged content skips the write: no mtime churn, no git noise.
	if FileAccess.get_file_as_string(FILE) != text:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		_write_atomic(FILE, text.to_utf8_buffer())
	pending = false
	return {"placements": placements.size(), "layers": layers.size(),
		"scatter": scatter.size()}


## One status line for the link verb (`overrides status`) — Strata's UI
## and probes read counts + last write without parsing the file.
func status_line() -> String:
	var n_placements := 0
	for cell: Vector2i in CellRecords.all_cells():
		n_placements += CellRecords.records(cell).size()
	var last := "never"
	if FileAccess.file_exists(FILE):
		last = Time.get_datetime_string_from_unix_time(
			FileAccess.get_modified_time(FILE)) + "Z"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	var n_layers := 0
	if parsed is Dictionary:
		n_layers = (parsed.get("terrain", {}) as Dictionary).get("layers", []).size()
	var n_scatter := ScatterHand.deltas().size()
	return "overrides placements=%d layers=%d scatter=%d pending=%s last_write=%s file=%s" % [
		n_placements, n_layers, n_scatter, "yes" if pending else "no", last,
		FILE.trim_prefix("res://")]


## Current records by stable id. Legacy rows are named here (ensure_id
## marks their cell dirty) and the follow-up flush writes the names to
## disk — the artifact and the cell files can't disagree on identity.
func _gather_placements() -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in CellRecords.all_cells():
		for rec: Dictionary in CellRecords.records(cell):
			var id := CellRecords.ensure_id(cell, rec)
			var entry := rec.duplicate()
			entry.erase("id")  # the key IS the id
			entry["cell"] = [cell.x, cell.y]
			out[id] = entry
	if CellRecords.has_dirty():
		CellRecords.flush()
	return out


## Snapshot the hand-terrain layers into Strata-readable blobs. Sources
## are the files the flush just saved (the save truth, not live memory):
## the macro pens' tile override and the sculpt brush's edit layer —
## both additive meters over whatever ground is live.
func _gather_layers() -> Array:
	var layers: Array = []
	# The pen override: frame + dirty rect ride its sidecar meta.
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		Terrain.TILE_OVERRIDE_META))
	if meta is Dictionary:
		var entry := _layer_entry("pen_override", Terrain.TILE_OVERRIDE_EXR,
			float(meta.get("x0", 0.0)), float(meta.get("z0", 0.0)),
			float(meta.get("size", 0.0)), meta.get("rect", null))
		if not entry.is_empty():
			layers.append(entry)
	# The sculpt layer: world-anchored constants (terrain.gd).
	var half := Terrain.EDIT_SIZE * Terrain.EDIT_M_PER_PX * 0.5
	var sculpt := _layer_entry("sculpt", Terrain.EDIT_PATH,
		-half, -half, 0.0, null, Terrain.EDIT_M_PER_PX)
	if not sculpt.is_empty():
		layers.append(sculpt)
	return layers


## Encode one layer source EXR -> data/overrides/terrain_<id>.f32z +
## its manifest entry. `size_m` 0 means "use m_per_px" (the sculpt
## convention); otherwise m_per_px = size / (res - 1) (the pen layer's
## edge-to-edge frame). {} when the source is missing or unreadable.
func _layer_entry(id: String, source: String, x0: float, z0: float,
		size_m: float, rect: Variant, m_per_px := 0.0) -> Dictionary:
	if not FileAccess.file_exists(source):
		return {}
	var mtime := FileAccess.get_modified_time(source)
	var blob_path := "%s/terrain_%s.f32z" % [DIR, id]
	var cached: Dictionary = _layer_cache.get(source, {})
	if int(cached.get("mtime", -1)) == mtime and FileAccess.file_exists(blob_path):
		return cached["entry"]
	var img := Image.load_from_file(ProjectSettings.globalize_path(source))
	if img == null or img.is_empty():
		push_warning("[overrides] layer source unreadable: " + source)
		return {}
	img.convert(Image.FORMAT_RF)
	var raw := img.get_data()
	var blob := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	# Unchanged bytes skip the write (same law as the JSON): a flush that
	# re-encodes an identical layer must not churn mtimes or git.
	if FileAccess.get_file_as_bytes(blob_path) != blob:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		_write_atomic(blob_path, blob)
	var entry := {
		"id": id,
		"file": blob_path.trim_prefix("res://"),
		"encoding": "deflate_f32le",
		"sha256": FileAccess.get_sha256(blob_path),
		"res": [img.get_width(), img.get_height()],
		"x0": x0, "z0": z0,
		"m_per_px": m_per_px if m_per_px > 0.0 \
				else size_m / float(img.get_width() - 1),
		"source": source.trim_prefix("res://"),
	}
	if rect is Dictionary:
		entry["rect"] = rect
	_layer_cache[source] = {"mtime": mtime, "entry": entry}
	return entry


## Atomic write: temp + rename, the cell-records pattern — a crash
## mid-write can only ever truncate the temp file.
func _write_atomic(path: String, bytes: PackedByteArray) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[overrides] cannot write %s: %s" % [tmp,
			error_string(FileAccess.get_open_error())])
		return
	var wrote := f.store_buffer(bytes)
	f.close()
	if not wrote:
		push_error("[overrides] short write to %s — artifact on disk untouched" % tmp)
		return
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("[overrides] could not commit %s: %s" % [path, error_string(err)])
