extends Node
## Names (autoload): the gazetteer. Places already have STABLE ids — the
## world mints them (water bodies hyd_l*, rivers hyd_r*, regions, tiles,
## interiors, markers, cells). This desk maps those ids to human names, and
## nothing more: `resolve(id)` answers a place's name with an HONEST
## fallback to the id itself, so a caller can always print SOMETHING and no
## surface ever shows a blank where a name would be.
##
## The gazetteer is CONTENT, not framework: names live in data/names/
## names.json (an array of {id, name, kind?} records), edited by the
## records desk like any other record. Content-empty is a first-class state
## — no file, or an empty array, means zero names and ZERO errors (the map
## and panel fall back to ids, the world is unnamed but whole). The
## framework file here (this autoload) never NAMES an id: it only relays
## whatever the content file carries, so the framework lint stays quiet.
##
## Riding the records machinery (no second write path): `_ready` registers
## the kind's field schema and a reloader with Records, so `records
## validate names …` judges an edited name-record by the SAME rule the
## loader trusts and `records reload names` rebinds the live table. The
## `name <id> <text>` link verb writes through `write()` below — validated,
## key-preserving (every other entry survives byte-for-byte in author
## order), atomic (temp+rename, the CellRecords pattern). Strata's records
## desk edits an EXISTING name-record through its own scalar door; `write()`
## is the create-or-update path the desk's byte-splice can't do (append a
## new array element) and the in-game verb.

const DIR := "res://data/names"
const FILE := DIR + "/names.json"
const KIND := "names"
## The field schema the records desk judges a name-record by (the same map
## the loader trusts): a name-record is {id, name} with an optional kind.
const SCHEMA := {"id": TYPE_STRING, "name": TYPE_STRING}

## id -> {"name": String, "kind": String} for every named place the content
## file carries. Rebuilt wholesale on reload; empty when content is empty.
var _by_id: Dictionary = {}


func _ready() -> void:
	# Ride the records desk: the kind's schema answers `records validate`,
	# and the reloader answers `records reload` after a landed write. The
	# framework holds the registries; this game file fills them (the same
	# seam quests/wildlife use).
	Records.register_schema(KIND, SCHEMA)
	Records.register_reloader(KIND, reload)
	reload()


## Read the content file into the live table. Wholesale (clear + rebuild):
## a reload after an edit reflects deletions too. Content-empty — no dir, no
## file, an empty or malformed array — leaves the table empty and pushes NO
## error (an unnamed world is a valid world). `file` is overridable so a
## test can drive a temp file without touching the shipped content.
func reload(file: String = FILE) -> void:
	_by_id.clear()
	for rec: Dictionary in _read_all(file):
		var id := String(rec.get("id", ""))
		if id.is_empty():
			continue
		_by_id[id] = {
			"name": String(rec.get("name", id)),
			"kind": String(rec.get("kind", "")),
		}


## A place's name, or the id itself when it has none — the honest fallback
## that lets every surface print something. Never errors, never blanks.
## Routes through Contour when STRATA_CONTOUR=1 (see the routing block below):
## a String does not cross the kernel ABI bare, so the answer rides back inside
## a one-element LAT_BUF array (the `resolve_abi` wrapper; story.gd's precedent).
func resolve(id: String) -> String:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return String((vm.call_fn("resolve_abi", [_by_id, id]) as Array)[0])
	var rec: Variant = _by_id.get(id, null)
	if rec == null:
		return id
	var name := String((rec as Dictionary).get("name", ""))
	return name if not name.is_empty() else id


## True when the content file carries a name for this id (surfaces that want
## to show a name ONLY for named things — the map's labels — gate on this).
func has_name(id: String) -> bool:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return bool(vm.call_fn("has_name", [_by_id, id]))  # a bool crosses bare
	return _by_id.has(id)


## A named place's declared kind ("" when none) — a soft hint the content
## may carry (lake/river/region/…), never required, never invented.
func kind_of(id: String) -> String:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return String((vm.call_fn("kind_of_abi", [_by_id, id]) as Array)[0])
	var rec: Variant = _by_id.get(id, null)
	return String((rec as Dictionary).get("kind", "")) if rec != null else ""


## Every named id, sorted — the world panel's HERE/WATER annotations and
## Strata's Names section walk this. Routes through Contour when
## STRATA_CONTOUR=1 (see the routing block below): the result is an ARRAY, a
## composite the kernel ABI already carries bare, so — unlike resolve/kind_of
## — it needs no one-element LAT_BUF wrap.
func named_ids() -> Array:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return vm.call_fn("named_ids", [_by_id]) as Array
	var out := _by_id.keys()
	out.sort()
	return out


## The whole table as {id, name, kind} rows, sorted by id — the `names`
## link verb's answer and the desk's list. Routes through Contour when
## STRATA_CONTOUR=1 — an array result, same bare-ABI path as named_ids.
func entries() -> Array:
	var vm := _route()
	if vm != null:
		_contour_calls += 1
		return vm.call_fn("entries", [_by_id]) as Array
	var out: Array = []
	for id: String in named_ids():
		var rec: Dictionary = _by_id[id]
		out.append({"id": id, "name": rec.name, "kind": rec.kind})
	return out


## Write (create-or-update) a place's name — the `name <id> <text>` verb's
## one door. Rides the records machinery: the candidate record is judged by
## `Records.validate_kind(names, …)` (the loader's own schema) BEFORE
## anything reaches disk, so the verb can never write a record the game
## can't read. Key-preserving: every OTHER entry survives verbatim in
## author order; only this id's row is replaced (or appended when new).
## Atomic (temp+rename — a crash truncates the temp, never the table), then
## the live table rebinds. Returns {ok:bool, error:String}. `file`/`reload`
## are overridable so a test drives a temp file end to end.
func write(id: String, name: String, kind: String = "", file: String = FILE) -> Dictionary:
	id = id.strip_edges()
	name = name.strip_edges()
	if id.is_empty():
		return {"ok": false, "error": "an id is required"}
	if name.is_empty():
		return {"ok": false, "error": "a name is required"}

	# The candidate, judged by the game's OWN loader schema (records desk
	# door): a bad shape bounces here with the game's words, never on disk.
	var candidate := {"id": id, "name": name}
	if not kind.is_empty():
		candidate["kind"] = kind
	var msg := Records.validate_kind(KIND, candidate)
	if msg != "":
		return {"ok": false, "error": msg}

	# Key-preserving upsert: keep every existing row (author order), replace
	# the matching id in place, append when new. Carry a row's prior `kind`
	# forward when the verb didn't restate it (a rename shouldn't drop it).
	var rows := _read_all(file)
	var placed := false
	for i in rows.size():
		var row: Dictionary = rows[i]
		if String(row.get("id", "")) == id:
			if kind.is_empty() and row.has("kind"):
				candidate["kind"] = row["kind"]
			rows[i] = candidate
			placed = true
			break
	if not placed:
		rows.append(candidate)

	if not _save(rows, file):
		return {"ok": false, "error": "could not write %s" % file}
	reload(file)
	return {"ok": true, "error": ""}


## Read the content array from disk ([] when absent/empty/malformed — the
## content-empty floor). Only object elements survive; a stray non-object
## is dropped, never fatal.
func _read_all(file: String) -> Array:
	if not FileAccess.file_exists(file):
		return []
	var parsed: Variant = Records.load_json(file)
	if not (parsed is Array):
		return []
	var out: Array = []
	for rec: Variant in parsed:
		if rec is Dictionary:
			out.append(rec)
	return out


## Atomic write of the whole array (tabbed JSON, the house style). Temp +
## rename so a crash mid-write truncates the temp, never the records.
func _save(rows: Array, file: String) -> bool:
	var dir := file.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var tmp := file + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[names] cannot write %s: %s" % [tmp,
			error_string(FileAccess.get_open_error())])
		return false
	var wrote := f.store_string(JSON.stringify(rows, "\t"))
	f.close()
	if not wrote:
		push_error("[names] short write to %s — table on disk untouched" % tmp)
		return false
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(file))
	if err != OK:
		push_error("[names] could not commit %s: %s (table untouched)" % [
			file, error_string(err)])
		return false
	return true


# --- Contour routing (PLAN_ENGINE E2, the conditions/story precedent) ----------
## The three pure registry QUERIES above (resolve/has_name/kind_of) are certified
## bit-identical to their Lattice twin by datum's Plumb harness (names_*.jsonl
## corpora over the byte-identical vendored names.gd — the queries read only the
## seeded `_by_id` table). When STRATA_CONTOUR=1 — a boot-time sim flag, read
## once, DevMode-independent, default OFF — those call sites route through the
## native Contour VM (game/world/names.ct via game/sim/contour.gd) instead of the
## GDScript below. Flag OFF is byte-identical GDScript.
##
## String results ride the LAT_BUF composite ABI wrapped in a one-element array
## (resolve_abi/kind_of_abi return `[value]`; the caller unwraps `(… as Array)[0]`)
## because a bare String does not cross the ContourKernel C ABI yet — that
## bare-string path is a parallel session's. has_name returns a bool, a scalar the
## ABI carries bare, so it routes direct.
##
## NO SILENT FALLBACK (the honesty law): flag ON with the kernel absent (not
## macOS / no dylib) or a module that will not compile is a LOUD refusal
## (push_error, mode -1), never a quiet GDScript pass. The routed queries carry a
## call counter (contour_status) so a scene test can prove the VM actually
## answered, flag-on. The IO path (reload/write/_read_all/_save) never routes —
## it is FileAccess/JSON/Records glue, GDScript by the scope law.
const _CONTOUR_MODULE := "res://game/world/names.ct"

## 0 unresolved · 1 off (flag unset) · 2 engaged (VM live) · -1 refused (flag
## set but kernel/module unavailable — loud, not silent).
static var _contour_mode := 0
static var _contour_vm: Contour = null
static var _contour_calls := 0   # VM-answered query calls (the engaged-path probe)

## The live VM when routing is engaged, else null (flag off, or refused). Resolves
## once at first touch (boot); pure — no side effects, so flag-off is byte-
## identical to the un-routed code.
static func _route() -> Contour:
	if _contour_mode == 0:
		_contour_resolve()
	return _contour_vm


static func _contour_resolve() -> void:
	var verdict := Contour.decide("names")
	if verdict != Contour.ROUTE_ENGAGE:
		_contour_mode = verdict   # ROUTE_FALLBACK (GDScript twin) or ROUTE_REFUSE (loud, mode -1)
		return
	# Routing engaged — compile the module (a compile failure still refuses loudly).
	var vm := Contour.new()
	var err := vm.compile_file(_CONTOUR_MODULE)
	if err != "":
		push_error("[names] STRATA_CONTOUR=1 but %s did not compile: %s — refusing to "
			% [_CONTOUR_MODULE, err] + "silently run the GDScript twin")
		_contour_mode = -1
		return
	_contour_vm = vm
	_contour_mode = 2


## Routing introspection for the scene test (proves the VM answered, not a silent
## fallback): the resolved mode, whether it engaged, and the answered-call count.
static func contour_status() -> Dictionary:
	if _contour_mode == 0:
		_contour_resolve()
	return {"mode": _contour_mode, "engaged": _contour_mode == 2, "calls": _contour_calls}
