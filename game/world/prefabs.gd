extends Node
## Prefabs (autoload) — composed places as reusable records (Creation Kit
## audit §2.1: "a composed place (well + fence + crates) can't be saved as
## a reusable thing"). A PREFAB is a record, filesystem-truth like every
## other content row: data/prefabs/<name>.json holds a `members` array
## captured from a selection — each member a
## {kit, dx, dz, yaw, scale, ground_dy}:
##   kit        the RESOLVED file, never a slot — retiring a placeholder
##              can't move a prefab's parts (the cell-records law, one truth
##              for placement identity);
##   dx, dz     the XZ offset from the selection's ANCHOR (its members'
##              centroid) — so the whole cluster stamps down around wherever
##              the cursor lands;
##   yaw, scale the member's own transform, captured as data;
##   ground_dy  the member's height ABOVE THE GROUND at capture — placing
##              re-seats each part on the CURRENT ground + this offset, so
##              the regeneration-hazard defense (ONE_APP) holds by
##              construction: prefab parts land as ordinary cell records.
##
## Placing a prefab instantiates every member through CellRecords.add (see
## Toolkit._place_prefab_at) as ONE ToolkitHistory action — one Z undoes the
## whole stamp. Because the parts are ordinary cell records, the P4 overrides
## contract needs nothing new (a placed member IS an override-native row).
##
## The record round-trips Strata's records browser for free: data/prefabs/
## sits under data/**, so RecordCatalog's scan already discovers the
## "prefabs" kind (one object file = one record). CONTENT, not manifest —
## the framework fence (FW5) never names these; they live in data/, like
## cells and quests.
##
## Tolerant like Cards: a missing data/prefabs/ (a content-empty game) is
## simply an empty catalog, and a malformed prefab file is skipped with a
## warning, never a crash.

const DIR := "res://data/prefabs"

var _prefabs: Dictionary = {}  # name -> {"members": Array[Dictionary]}
var load_warnings: Array[String] = []


func _ready() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return  # content-empty game (or no prefabs yet): the empty catalog
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path := DIR + "/" + f
		var parsed: Variant = Records.load_json(path)
		if not (parsed is Dictionary) \
				or not Records.validate(parsed, {"members": TYPE_ARRAY}, path):
			_warn("%s is not a prefab record — skipped" % f)
			continue
		_prefabs[f.trim_suffix(".json")] = parsed


func _warn(msg: String) -> void:
	push_warning("[prefabs] " + msg)
	load_warnings.append(msg)


## Prefab names present, sorted (the PLACE palette and the link's `prefab
## list` read this).
func names() -> Array:
	var out: Array = _prefabs.keys()
	out.sort()
	return out


func count() -> int:
	return _prefabs.size()


func has(name: String) -> bool:
	return _prefabs.has(name)


## The prefab record ({} when unknown) — its `members` array is the truth
## a placement walks.
func get_prefab(name: String) -> Dictionary:
	return _prefabs.get(name, {})


## The member list for a prefab ([] when unknown).
func members(name: String) -> Array:
	return _prefabs.get(name, {}).get("members", [])


## Capture a selection of cell records as a reusable prefab. `records` are
## live cell-record dicts (each with kit/x/z/yaw/scale and a height vintage
## seat_y understands); the anchor is their XZ centroid, so members store
## offsets from the cluster's middle. Writes data/prefabs/<name>.json
## atomically (temp + rename, the cell-records law) and adds it to the live
## catalog. Returns the stored record, {} on a bad name or empty selection.
func capture(name: String, records: Array) -> Dictionary:
	var clean := _sanitize(name)
	if clean == "" or records.is_empty():
		return {}
	var cx := 0.0
	var cz := 0.0
	for rec: Dictionary in records:
		cx += float(rec.get("x", 0.0))
		cz += float(rec.get("z", 0.0))
	cx /= records.size()
	cz /= records.size()
	var out_members: Array = []
	for rec: Dictionary in records:
		var x := float(rec.get("x", 0.0))
		var z := float(rec.get("z", 0.0))
		# seat_y is the one truth for where the record rides today (snap,
		# ground_dy, and legacy absolute-Y vintages all fold through it),
		# so the captured ground offset is vintage-safe.
		var gdy := CellRecords.seat_y(rec) - Terrain.height(x, z)
		out_members.append({
			"kit": String(rec.get("kit", "")),
			"dx": x - cx, "dz": z - cz,
			"yaw": float(rec.get("yaw", 0.0)),
			"scale": float(rec.get("scale", 1.0)),
			"ground_dy": gdy,
		})
	var record := {"members": out_members}
	if not _write(clean, record):
		return {}
	_prefabs[clean] = record
	return record


## Lowercase the name to a filesystem-safe stem (letters, digits, _ and -),
## spaces to _. "" when nothing survives — capture refuses it.
func _sanitize(name: String) -> String:
	var out := ""
	for ch in name.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") \
				or ch == "_" or ch == "-":
			out += ch
		elif ch == " ":
			out += "_"
	return out


## Atomic write (temp + rename — a crash can only truncate the temp file,
## never a live prefab). Returns whether it landed.
func _write(name: String, record: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := "%s/%s.json" % [DIR, name]
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("[prefabs] cannot write %s: %s" % [tmp,
			error_string(FileAccess.get_open_error())])
		return false
	var wrote := file.store_string(JSON.stringify(record, "\t"))
	file.close()
	if not wrote:
		push_error("[prefabs] short write to %s — prefab on disk untouched" % tmp)
		return false
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("[prefabs] could not commit %s: %s" % [path, error_string(err)])
		return false
	return true
