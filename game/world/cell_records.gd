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

signal changed(cell: Vector2i)

const DIR := "res://data/cells"
const CELL_SIZE := 128.0

var _cells: Dictionary = {}  # Vector2i -> Array[Dictionary]


func _ready() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("cell_") and f.ends_with(".json"):
			var parts := f.trim_suffix(".json").split("_")
			if parts.size() != 3:
				continue
			var parsed = Records.load_json(DIR + "/" + f)
			if parsed is Array:
				var valid: Array = []
				for rec in parsed:
					if rec is Dictionary and Records.validate(rec, {
						"kit": TYPE_STRING, "x": TYPE_FLOAT, "y": TYPE_FLOAT,
						"z": TYPE_FLOAT, "yaw": TYPE_FLOAT,
					}, DIR + "/" + f):
						valid.append(rec)
				_cells[Vector2i(parts[1].to_int(), parts[2].to_int())] = valid


func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / CELL_SIZE), roundi(pos.z / CELL_SIZE))


func records(cell: Vector2i) -> Array:
	return _cells.get(cell, [])


func add(pos: Vector3, kit_id: String, yaw: float, scale: float) -> void:
	var cell := cell_of(pos)
	if not _cells.has(cell):
		_cells[cell] = []
	_cells[cell].append({
		"kit": kit_id, "x": pos.x, "y": pos.y, "z": pos.z, "yaw": yaw, "scale": scale,
		"ground_dy": pos.y - Terrain.height(pos.x, pos.z),  # ground-relative anchor
		"day": GameClock.day,  # age of the placement — weathering reads this later
	})
	_save(cell)
	changed.emit(cell)


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
	# anchor whenever their cell is saved anyway — no forced rewrite of
	# every file at load (the ground under them is the best truth we have).
	for rec: Dictionary in _cells[cell]:
		if not rec.has("ground_dy"):
			var x: float = rec.x
			var z: float = rec.z
			rec["ground_dy"] = float(rec.y) - Terrain.height(x, z)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := "%s/cell_%d_%d.json" % [DIR, cell.x, cell.y]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_cells[cell], "\t"))
