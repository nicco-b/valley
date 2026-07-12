class_name ScatterHand
## The hand's edits to BAKED-scatter instances (ONE_APP P4, the scatter half of
## the overrides round trip; strata M4). A baked prop is placed by Strata's
## scatter export and carries a stable, seed-INDEPENDENT id — so when the
## Toolkit moves or deletes one, we can record {id, op, transform} keyed by that
## id and Strata will REPLAY the delta over any future re-bake: a moved rock
## rides a full seed re-roll, a deleted one stays gone.
##
## This is the game's OWN persistent truth (res://data/scatter/hand.json,
## committed like data/cells), separate from the one-way seam artifact
## overrides.json — overrides.gd reads THIS store to build overrides.json's
## `scatter` section (game -> Strata), never the reverse. Runtime scatter (the
## per-cell hash roll in world_streamer) has no ids and cannot be edited; only
## the baked path routes through here.
##
## SCHEMA (format 1) — sorted keys, tab indent, trailing newline:
## {
##   "format": 1,
##   "deltas": {
##     "<id>": { "op": "move",         # or "delete"
##               "x": float, "y": float, "z": float,   # absolute world meters
##               "yaw": float, "scale": float,
##               "cat": String, "pick": float },        # so a force-added
##                                                       #   moved prop still
##                                                       #   resolves a mesh
##     "<id>": { "op": "delete" }, ...
##   }
## }

const PATH := "res://data/scatter/hand.json"
const FORMAT := 1

## id -> delta dict. Variant (not Dictionary) so it can be null until first
## touch — a typed Dictionary defaults to {}, and the lazy-load guard would
## never fire. A game that never edits baked scatter pays no IO.
static var _deltas: Variant = null


## The current deltas (loads on first call). Callers must not mutate the result.
static func deltas() -> Dictionary:
	if _deltas == null:
		_load()
	return _deltas


static func is_empty() -> bool:
	return deltas().is_empty()


## Record a move of a baked instance to an absolute world transform. `cat`/`pick`
## are the baked prop's own (carried so Strata can force-add it if a re-roll
## rejects the candidate). Marks the seam artifact stale via Overrides.
static func move(id: String, world_pos: Vector3, yaw: float, scale: float,
		cat: String, pick: float) -> void:
	deltas()[id] = {
		"op": "move",
		"x": world_pos.x, "y": world_pos.y, "z": world_pos.z,
		"yaw": yaw, "scale": scale, "cat": cat, "pick": pick,
	}
	_save()


## Record a delete of a baked instance. Deterministic replay drops it forever.
static func remove(id: String) -> void:
	deltas()[id] = {"op": "delete"}
	_save()


## Undo any edit of this instance (it reverts to its baked default).
static func clear(id: String) -> void:
	if deltas().has(id):
		deltas().erase(id)
		_save()


## Apply the hand's delta to a baked placement dict. Returns the effective
## placement (a duplicate, with `moved=true`) or null when the hand deleted it;
## an untouched placement rides through with `moved=false`. Pure — the world
## streamer calls this per baked prop it instances. The overlay-op fold itself
## is apply_delta() below (dict-in/dict-out, Plumb-certified); this wrapper
## only translates the deltas() lookup's null/found split into apply_delta's
## dict-sentinel convention and the empty-dict delete sentinel back to null —
## Contour's value kinds have no null, so the certified leaf never returns one.
static func apply(p: Dictionary) -> Variant:
	var d: Variant = deltas().get(p.get("id", ""), null)
	var out := apply_delta(p, d if d is Dictionary else {})
	return null if out.is_empty() else out


## The pure overlay-op fold: `d` empty means untouched (moved=false rides
## through), `d.op=="delete"` returns an EMPTY dict (apply()'s delete
## sentinel — Contour has no null value kind), anything else is a move
## (x/y/z/yaw/scale overlaid, moved=true). Dict-in/dict-out, no lookup, no
## I/O — the leaf docs/PORT_LEDGER.md's "small leaves" wave certifies.
static func apply_delta(p: Dictionary, d: Dictionary) -> Dictionary:
	if d.is_empty():
		var out := p.duplicate()
		out["moved"] = false
		return out
	if String(d.get("op", "")) == "delete":
		return {}
	var moved := p.duplicate()
	moved["x"] = float(d["x"]); moved["y"] = float(d["y"]); moved["z"] = float(d["z"])
	moved["yaw"] = float(d["yaw"]); moved["scale"] = float(d["scale"])
	moved["moved"] = true
	return moved


## Force a reload from disk (tests; and after an external write).
static func reload() -> void:
	_deltas = null
	_load()


static func _load() -> void:
	_deltas = {}
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary and (parsed.get("deltas", null) is Dictionary):
		_deltas = parsed["deltas"]


static func _save() -> void:
	var doc := {"format": FORMAT, "deltas": _deltas}
	var text := JSON.stringify(doc, "\t", true) + "\n"
	# Unchanged content skips the write (no git noise / mtime churn).
	if FileAccess.get_file_as_string(PATH) == text:
		return
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PATH).get_base_dir())
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[scatter_hand] cannot write %s: %s" % [tmp,
			error_string(FileAccess.get_open_error())])
		return
	f.store_string(text)
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(PATH))
	if err != OK:
		push_error("[scatter_hand] could not commit %s: %s" % [PATH, error_string(err)])
	# The seam artifact is now stale (Overrides autoload present in-game).
	if Engine.has_singleton("Overrides") or _overrides_node() != null:
		var ov := _overrides_node()
		if ov != null:
			ov.pending = true


## The Overrides autoload if it is loaded (headless tools may not have it).
static func _overrides_node() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		return (loop as SceneTree).root.get_node_or_null("Overrides")
	return null
