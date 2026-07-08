extends Node
## The Chronicle — placed-object records (autoload). One JSON file per cell
## in data/cells; each record: {kit, x, y, z, yaw, scale, ground_dy}. Place
## mode writes these, the streamer instantiates them (through seat_y). This
## is the seed of the data-driven content layer (and, later, of save-game
## world mutation).
##
## ground_dy is the record's height ABOVE THE GROUND at placement time —
## the regeneration-hazard defense (ONE_APP): when Strata regenerates the
## terrain under a placement, seat_y() rides the CURRENT ground plus that
## offset instead of a stale absolute Y, so nothing floats or buries.
## Legacy records (absolute-Y only) keep their stored Y and gain a
## ground_dy opportunistically the next time their cell saves anyway.
##
## Placement editing v2 (audit #1): every record carries a stable `id`,
## minted at add — the Toolkit's selection, the {record-id, before-state}
## undo memento, and the coming overrides emitter (P4) all name THIS
## object by it, across edits, saves, and cell migrations. Legacy rows
## gain an id the same way they gain ground_dy: on their cell's next
## save (or the moment the hand picks them). Edits go through update():
## memory and visuals change NOW, the record migrates cell files when
## x/z cross a boundary, and the DISK write waits for flush() — the
## Toolkit's stroke-quiet clock fires it, so a nudge stream is one
## write, not thirty. add/remove stay write-through (one click, one save).

signal changed(cell: Vector2i)

const DIR := "res://data/cells"
const CELL_SIZE := 128.0

var _cells: Dictionary = {}  # Vector2i -> Array[Dictionary]
var _dirty: Dictionary = {}  # Vector2i -> true: edited cells awaiting flush()
var _id_serial := 0  # per-session tiebreak inside one millisecond

## Boot-time corruption reports (one line per bad file) — the Toolkit and
## tests read these; each is also push_warning'd and HUD-notified. A
## truncated cell file must never crash the boot or silently vanish:
## the bad file is kept aside as *.corrupt, everything that parses lives.
var load_warnings: Array[String] = []


func _ready() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("cell_") and f.ends_with(".json"):
			var parts := f.trim_suffix(".json").split("_")
			if parts.size() != 3:
				continue
			var path := DIR + "/" + f
			var parsed: Variant = Records.load_json(path)
			if not (parsed is Array):
				# Truncated / malformed file (a crash mid-write, a bad merge):
				# move it aside so no later save can overwrite the evidence,
				# boot with the cell empty, and say so where it can be seen.
				_warn("%s is unreadable — kept aside as %s, cell boots empty"
					% [f, _quarantine(path).get_file()])
				continue
			var valid: Array = []
			var dropped := 0
			for rec in parsed:
				if rec is Dictionary and Records.validate(rec, {
					"kit": TYPE_STRING, "x": TYPE_FLOAT, "y": TYPE_FLOAT,
					"z": TYPE_FLOAT, "yaw": TYPE_FLOAT,
				}, path):
					valid.append(rec)
				else:
					dropped += 1
			if dropped > 0:
				# Partially bad: the survivors load, but the next save would
				# rewrite the file without the bad rows — copy the original
				# aside FIRST so nothing is silently lost.
				_warn("%s: %d bad record(s) dropped (%d survive) — original kept as %s"
					% [f, dropped, valid.size(), _preserve(path).get_file()])
			_cells[Vector2i(parts[1].to_int(), parts[2].to_int())] = valid


## Surface a placed-records problem everywhere it can be seen: the log,
## the load_warnings ledger, and the HUD (deferred — _ready runs before
## the first frame; long timeout because boot notices are easy to miss).
func _warn(msg: String) -> void:
	push_warning("[cells] " + msg)
	load_warnings.append(msg)
	HUD.notify.call_deferred("Placed objects: " + msg, 10.0)


## Move a bad cell file aside as *.corrupt (never delete, never leave it
## where the next save would overwrite it). Returns the path it landed on.
func _quarantine(path: String) -> String:
	var aside := _corrupt_name(path)
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(aside))
	if err != OK:
		push_error("[cells] could not quarantine %s: %s" % [path, error_string(err)])
	return aside


## Copy a partially-bad cell file aside as *.corrupt, leaving the live
## file in place (its parsed records are still in play).
func _preserve(path: String) -> String:
	var aside := _corrupt_name(path)
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(aside))
	if err != OK:
		push_error("[cells] could not preserve %s: %s" % [path, error_string(err)])
	return aside


## First free *.corrupt name beside the file (an older quarantine is
## evidence too — never overwrite it).
func _corrupt_name(path: String) -> String:
	var aside := path + ".corrupt"
	var n := 1
	while FileAccess.file_exists(aside):
		aside = "%s.%d.corrupt" % [path, n]
		n += 1
	return aside


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / CELL_SIZE), roundi(pos.z / CELL_SIZE))


func records(cell: Vector2i) -> Array:
	return _cells.get(cell, [])


## The record with this id in this cell ({} when it isn't there — the
## selection's liveness check reads through this every frame).
func record(cell: Vector2i, id: String) -> Dictionary:
	for rec: Dictionary in _cells.get(cell, []):
		if String(rec.get("id", "")) == id:
			return rec
	return {}


## Nearest record within `radius` meters (XZ) of a world position — the
## Toolkit's pick. The audit's fork survey verified editor-grade picking
## needs no engine work: the records already know where they stand.
## Searches the 3x3 cells around the point so a pick near a cell seam
## still finds its neighbor. {} or {"cell": Vector2i, "rec": Dictionary}.
func find_at(pos: Vector3, radius: float) -> Dictionary:
	var center := cell_of(pos)
	var best_d := radius
	var best: Dictionary = {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cell := center + Vector2i(dx, dz)
			for rec: Dictionary in _cells.get(cell, []):
				var d := Vector2(float(rec.x) - pos.x, float(rec.z) - pos.z).length()
				if d <= best_d:
					best_d = d
					best = {"cell": cell, "rec": rec}
	return best


## Mint a record id: unique across sessions (millisecond clock) and
## within one (serial) — and short enough to sit on a HUD line.
func _new_id() -> String:
	_id_serial += 1
	return "p%x_%x" % [int(Time.get_unix_time_from_system() * 1000.0), _id_serial]


## Name a legacy record NOW (the hand just picked it — selection needs
## identity before the cell's next save would mint one anyway). The
## dirty mark makes sure the name reaches disk even if nothing else
## changes. Returns the id either way.
func ensure_id(cell: Vector2i, rec: Dictionary) -> String:
	if not rec.has("id"):
		rec["id"] = _new_id()
		_dirty[cell] = true
	return String(rec["id"])


func add(pos: Vector3, kit_id: String, yaw: float, scale: float) -> Dictionary:
	var cell := cell_of(pos)
	if not _cells.has(cell):
		_cells[cell] = []
	var rec := {
		"id": _new_id(),  # stable identity (selection, undo, P4 diffs)
		"kit": kit_id, "x": pos.x, "y": pos.y, "z": pos.z, "yaw": yaw, "scale": scale,
		"ground_dy": pos.y - Terrain.height(pos.x, pos.z),  # ground-relative anchor
		"day": GameClock.day,  # age of the placement — weathering reads this later
	}
	_cells[cell].append(rec)
	_save(cell)
	changed.emit(cell)
	return rec


## Pop the newest record in a cell (the PLACE tool's LIFO Z). Answers
## whether anything was actually removed, so the caller can be honest
## about an empty cell instead of silently doing nothing.
func remove_last(cell: Vector2i) -> bool:
	if not _cells.has(cell) or _cells[cell].is_empty():
		return false
	_cells[cell].pop_back()
	_save(cell)
	changed.emit(cell)
	return true


## Remove THE record (targeted delete, placement v2 — never LIFO).
## Returns the removed record ({} when it wasn't there) so the undo
## memento can bring it back bit-exact.
func remove(cell: Vector2i, id: String) -> Dictionary:
	var arr: Array = _cells.get(cell, [])
	for i in arr.size():
		if String((arr[i] as Dictionary).get("id", "")) == id:
			var rec: Dictionary = arr[i]
			arr.remove_at(i)
			_save(cell)
			changed.emit(cell)
			return rec
	return {}


## Re-insert a record exactly as given — the undo of a delete or an
## edit (unknown keys ride along untouched; the id comes back with it).
## Returns the cell it landed in.
func insert(rec: Dictionary) -> Vector2i:
	var cell := cell_of(Vector3(float(rec.x), 0.0, float(rec.z)))
	if not _cells.has(cell):
		_cells[cell] = []
	_cells[cell].append(rec)
	_save(cell)
	changed.emit(cell)
	return cell


## Patch a record's fields in place (move/rotate/scale). Memory and
## visuals change NOW (`changed` rebuilds the cell); the record migrates
## between cell files when x/z cross a boundary; the disk write waits
## for flush(). Returns the cell the record lives in afterwards (the
## caller's selection follows it), unchanged when the id isn't there.
func update(cell: Vector2i, id: String, fields: Dictionary) -> Vector2i:
	var rec := record(cell, id)
	if rec.is_empty():
		return cell
	for k: String in fields:
		rec[k] = fields[k]
	var now := cell_of(Vector3(float(rec.x), 0.0, float(rec.z)))
	if now != cell:
		_cells[cell].erase(rec)
		if not _cells.has(now):
			_cells[now] = []
		_cells[now].append(rec)
		_dirty[cell] = true
		changed.emit(cell)
	_dirty[now] = true
	changed.emit(now)
	return now


## Any edited cells still waiting on their disk write? (The Toolkit's
## stroke-quiet flush clock reads this.)
func has_dirty() -> bool:
	return not _dirty.is_empty()


## Write every edited cell through the same guarded save adds use — the
## Toolkit's F5 / stroke-quiet flush / exit all land here.
func flush() -> void:
	for cell: Vector2i in _dirty.keys():
		_save(cell)
	_dirty.clear()


## The Y a record seats at RIGHT NOW — the streamer's one answer. snap
## rides the ground exactly; ground_dy rides the CURRENT ground plus the
## authored offset (the terrain may have regenerated since placement);
## legacy records hold their stored absolute Y until a save migrates them.
func seat_y(rec: Dictionary) -> float:
	var x: float = rec.x
	var z: float = rec.z
	if bool(rec.get("snap", false)):
		return Terrain.height(x, z)
	if rec.has("ground_dy"):
		return Terrain.height(x, z) + float(rec.ground_dy)
	return float(rec.y)


func _save(cell: Vector2i) -> void:
	# Opportunistic migration: legacy records gain their ground-relative
	# anchor — and their stable id — whenever their cell is saved anyway;
	# no forced rewrite of every file at load (the ground under them is
	# the best truth we have).
	for rec: Dictionary in _cells[cell]:
		if not rec.has("ground_dy"):
			var x: float = rec.x
			var z: float = rec.z
			rec["ground_dy"] = float(rec.y) - Terrain.height(x, z)
		if not rec.has("id"):
			rec["id"] = _new_id()
	_dirty.erase(cell)  # this write IS the flush for this cell
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := "%s/cell_%d_%d.json" % [DIR, cell.x, cell.y]
	# Atomic write: temp + rename. A crash mid-write can only ever truncate
	# the temp file — the records themselves are never open for truncation.
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("[cells] cannot write %s: %s" % [tmp,
			error_string(FileAccess.get_open_error())])
		return
	var wrote := file.store_string(JSON.stringify(_cells[cell], "\t"))
	file.close()
	if not wrote:
		push_error("[cells] short write to %s — records on disk untouched" % tmp)
		return
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("[cells] could not commit %s: %s (records on disk untouched)"
			% [path, error_string(err)])
