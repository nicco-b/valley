extends Node
## Placed-object records (autoload). One JSON file per cell in data/cells;
## each record: {kit, x, y, z, yaw, scale}. Place mode writes these, the
## streamer instantiates them. This is the seed of the data-driven content
## layer (and, later, of save-game world mutation).

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
		"day": GameClock.day,  # age of the placement — weathering reads this later
	})
	_save(cell)
	changed.emit(cell)


func remove_last(cell: Vector2i) -> void:
	if not _cells.has(cell) or _cells[cell].is_empty():
		return
	_cells[cell].pop_back()
	_save(cell)
	changed.emit(cell)


func _save(cell: Vector2i) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := "%s/cell_%d_%d.json" % [DIR, cell.x, cell.y]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_cells[cell], "\t"))
