extends Node
## The Chronicle's SECOND book (autoload; PLAN_INTERIORS §4) — interior
## placements as first-class records, the same stable-id / edit / undo
## contract as CellRecords, one JSON file per interior in data/interiors.
## While the player is inside a pocket the Toolkit's hand funnels here
## instead of at the world cells (the active-book seam, toolkit `_book()`):
## place / move / rotate / scale / delete / undo all land in THIS store,
## and ToolkitHistory mementos carry which book they touched so Z reverses
## honestly across the threshold.
##
## Row shape is the CellRecords row VERBATIM ({id, kit, x, y, z, yaw,
## scale} — stable ids and all), with two deliberate differences the plan
## names: coordinates are LOCAL to the pocket origin, and `y` is absolute
## (no ground_dy, no seat_y — there is no terrain to seat on; the
## interior's own floor pieces are the ground). To keep the Toolkit — which
## lives entirely in world space (raycasts, gizmo, the selection marker) —
## unchanged, the book holds WORLD coordinates in memory while a pocket
## stands (local + the pocket origin) and translates back to local at the
## disk boundary alone. `focus(id, origin)` loads and translates on enter;
## `_save` reverses it. The Toolkit-facing verbs are the CellRecords verbs,
## same signatures (the `cell` argument is vestigial here — one interior is
## one book), so the hand's generic machinery rides free.
##
## Interiors are content, not sim: nothing here touches height(), the
## hydrology grid, the climate fields, or WorldState canon, and interior
## records are never fingerprinted (§6). The soak digest cannot move.

## An interior's book changed (edited row / add / remove) — Interiors
## rebuilds the live pocket from this; a load (focus) is silent.
signal changed(interior_id: String)

const DIR := "res://data/interiors"

## interior id -> Array[Dictionary] of WORLD-coord records (only for ids
## that have been focused this session; the pocket origin makes the coords
## meaningful).
var _books: Dictionary = {}
## interior id -> Vector3 pocket origin used to translate local<->world.
var _origin: Dictionary = {}
## interior id -> true: edited books awaiting flush().
var _dirty: Dictionary = {}
## The interior the hand is currently pointed at — the vestigial `cell`
## argument is ignored, so this names the target. Retained across exit so a
## cross-threshold undo still reaches the book it touched (single interior
## at a time; §3).
var _active := ""
var _id_serial := 0


## Point the book at an interior standing at `origin` (the pocket's world
## position). Loads the disk rows (local coords) and translates them to
## world so the Toolkit's world-space hand edits them in place. Reloads
## from disk each focus — exit flushed, so disk is the fresh truth. Silent
## (no `changed`): a load is not an edit.
func focus(id: String, origin: Vector3) -> void:
	_active = id
	_origin[id] = origin
	_dirty.erase(id)
	var rows: Array = []
	var def := _definition(id)
	for rec: Dictionary in def.get("placements", []):
		var r: Dictionary = rec.duplicate()
		r["x"] = float(rec.get("x", 0.0)) + origin.x
		r["y"] = float(rec.get("y", 0.0)) + origin.y
		r["z"] = float(rec.get("z", 0.0)) + origin.z
		if not r.has("id"):
			r["id"] = _new_id()
		rows.append(r)
	_books[id] = rows


## The active interior id (the pocket host reads this to rebuild).
func active() -> String:
	return _active


## The live WORLD-coord rows of the active interior (Interiors subtracts
## the pocket origin to seat them locally under the pocket node).
func active_rows() -> Array:
	return _books.get(_active, [])


# --- The CellRecords verb surface (the active-book seam). The `cell`
# argument is vestigial — one interior is one flat book — but the
# signatures match so the Toolkit's generic funnels call either store.


## Vestigial (one interior, one book) — the Toolkit stores whatever this
## returns in _sel_cell and hands it back untouched.
func cell_of(_pos: Vector3) -> Vector2i:
	return Vector2i.ZERO


func records(_cell: Vector2i) -> Array:
	return _books.get(_active, [])


## Every book that currently holds rows (the whole-Chronicle walkers).
func all_cells() -> Array:
	return [Vector2i.ZERO] if not _books.get(_active, []).is_empty() else []


## The record with this id in the active book ({} when it isn't there).
func record(_cell: Vector2i, id: String) -> Dictionary:
	for rec: Dictionary in _books.get(_active, []):
		if String(rec.get("id", "")) == id:
			return rec
	return {}


## Nearest record within `radius` metres (XZ) of a world position — the
## Toolkit's pick. {} or {"cell": Vector2i.ZERO, "rec": Dictionary}.
func find_at(pos: Vector3, radius: float) -> Dictionary:
	var best_d := radius
	var best: Dictionary = {}
	for rec: Dictionary in _books.get(_active, []):
		var d := Vector2(float(rec.x) - pos.x, float(rec.z) - pos.z).length()
		if d <= best_d:
			best_d = d
			best = {"cell": Vector2i.ZERO, "rec": rec}
	return best


## Every record whose XZ falls inside a world-space rectangle — the box
## multi-select. [{cell, id}] sorted by id (group-edit determinism).
func find_in_box(min_xz: Vector2, max_xz: Vector2) -> Array:
	var lo := Vector2(minf(min_xz.x, max_xz.x), minf(min_xz.y, max_xz.y))
	var hi := Vector2(maxf(min_xz.x, max_xz.x), maxf(min_xz.y, max_xz.y))
	var out: Array = []
	for rec: Dictionary in _books.get(_active, []):
		var x := float(rec.x)
		var z := float(rec.z)
		if x >= lo.x and x <= hi.x and z >= lo.y and z <= hi.y:
			out.append({"cell": Vector2i.ZERO, "id": ensure_id(Vector2i.ZERO, rec)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.id) < String(b.id))
	return out


## Every record within `radius` metres (XZ) of a world position — the
## prefab capture's reach. Returns the LIVE record dicts.
func within(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for rec: Dictionary in _books.get(_active, []):
		if Vector2(float(rec.x) - pos.x, float(rec.z) - pos.z).length() <= radius:
			out.append(rec)
	return out


func mint_id() -> String:
	return _new_id()


## Name a legacy record NOW (the hand just picked it). Marks the book
## dirty so the name reaches disk. Returns the id either way.
func ensure_id(_cell: Vector2i, rec: Dictionary) -> String:
	if not rec.has("id"):
		rec["id"] = _new_id()
		_dirty[_active] = true
	return String(rec["id"])


## The record's Y right now — absolute-local (world in memory); no terrain,
## no seat, no ground_dy. The Toolkit's one seating answer inside.
func seat_y(rec: Dictionary) -> float:
	return float(rec.get("y", 0.0))


## The "ground" the Toolkit seats records above — flat zero inside (there
## is no terrain; the interior's own floor pieces are the ground). The
## CellRecords.ground_h counterpart: y = ground_h(x, z) + dy collapses to
## y = dy (preserved) inside, and the tilt/ground_dy fields are gated off.
func ground_h(_x: float, _z: float) -> float:
	return 0.0


## Place a row at a WORLD position — no ground_dy, no day, `y` absolute.
func add(pos: Vector3, kit_id: String, yaw: float, scale: float) -> Dictionary:
	var book: Array = _books.get(_active, [])
	if not _books.has(_active):
		_books[_active] = book
	var rec := {
		"id": _new_id(),
		"kit": kit_id, "x": pos.x, "y": pos.y, "z": pos.z, "yaw": yaw, "scale": scale,
	}
	book.append(rec)
	_save(_active)
	changed.emit(_active)
	return rec


## Pop the newest row (the PLACE tool's LIFO fallback).
func remove_last(_cell: Vector2i) -> bool:
	var book: Array = _books.get(_active, [])
	if book.is_empty():
		return false
	book.pop_back()
	_save(_active)
	changed.emit(_active)
	return true


## Remove THE record by id (targeted delete). Returns it ({} when absent)
## so the undo memento can bring it back bit-exact.
func remove(_cell: Vector2i, id: String) -> Dictionary:
	var book: Array = _books.get(_active, [])
	for i in book.size():
		if String((book[i] as Dictionary).get("id", "")) == id:
			var rec: Dictionary = book[i]
			book.remove_at(i)
			_save(_active)
			changed.emit(_active)
			return rec
	return {}


## Re-insert a record exactly as given (the undo of a delete or edit).
## Returns the vestigial cell it landed in.
func insert(rec: Dictionary) -> Vector2i:
	if not _books.has(_active):
		_books[_active] = []
	_books[_active].append(rec)
	_save(_active)
	changed.emit(_active)
	return Vector2i.ZERO


## Patch a record in place (move / rotate / scale). Memory changes NOW
## (`changed` rebuilds the pocket); the disk write waits for flush(). No
## cell migration — one interior is one book. Returns the vestigial cell.
func update(_cell: Vector2i, id: String, fields: Dictionary) -> Vector2i:
	var rec := record(Vector2i.ZERO, id)
	if rec.is_empty():
		return Vector2i.ZERO
	for k: String in fields:
		if fields[k] == null:
			rec.erase(k)
		else:
			rec[k] = fields[k]
	_dirty[_active] = true
	changed.emit(_active)
	return Vector2i.ZERO


func has_dirty() -> bool:
	return not _dirty.is_empty()


func flush() -> void:
	for id: String in _dirty.keys():
		_save(id)
	_dirty.clear()


## The interior record for an id ({} when missing/malformed) — the same
## shape Interiors.definition reads, kept here so the book owns its loader
## (the records-desk validate verb rides this).
func _definition(id: String) -> Dictionary:
	var path := "%s/%s.json" % [DIR, id]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = Records.load_json(path)
	if not (parsed is Dictionary):
		return {}
	if not Records.validate(parsed, {
		"id": TYPE_STRING, "placements": TYPE_ARRAY,
	}, path):
		return {}
	return parsed


func _new_id() -> String:
	_id_serial += 1
	return "p%x_%x" % [int(Time.get_unix_time_from_system() * 1000.0), _id_serial]


## Write the interior file: WORLD coords translate back to LOCAL (subtract
## the pocket origin), and only the row shape survives — id/kit/x/y/z/yaw/
## scale plus a `door` key when present. ground_dy/tilt/day never reach an
## interior file (there is no terrain to anchor them). Atomic (temp+rename),
## the CellRecords pattern inherited: a crash mid-write truncates the temp,
## never the records.
func _save(id: String) -> void:
	_dirty.erase(id)
	var origin: Vector3 = _origin.get(id, Vector3.ZERO)
	var rows: Array = []
	for rec: Dictionary in _books.get(id, []):
		var out := {
			"id": String(rec.get("id", _new_id())),
			"kit": String(rec.get("kit", "")),
			"x": float(rec.get("x", 0.0)) - origin.x,
			"y": float(rec.get("y", 0.0)) - origin.y,
			"z": float(rec.get("z", 0.0)) - origin.z,
			"yaw": float(rec.get("yaw", 0.0)),
			"scale": float(rec.get("scale", 1.0)),
		}
		if rec.has("door"):
			out["door"] = rec["door"]
		rows.append(out)
	var def := _definition(id)
	var payload := {
		"id": id,
		"name": def.get("name", id),
		"light": def.get("light", "dark_warm"),
		"ambience": def.get("ambience", ""),
		"placements": rows,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := "%s/%s.json" % [DIR, id]
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("[interiors] cannot write %s: %s" % [tmp,
			error_string(FileAccess.get_open_error())])
		return
	var wrote := file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	if not wrote:
		push_error("[interiors] short write to %s — records on disk untouched" % tmp)
		return
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("[interiors] could not commit %s: %s (records on disk untouched)"
			% [path, error_string(err)])
