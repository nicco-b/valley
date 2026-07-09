extends Node
## Records (autoload): the one validated path for loading data/*.json.
## Catches missing fields and wrong types at load time with a clear
## message, instead of mysterious nulls at runtime.
##
## The records desk (Strata R5): the SAME load-time judgement answers the
## `records validate` link verb, so Strata can never write a record the
## game can't read. The framework stays game-agnostic — this file knows
## only "a kind has a required-field schema and maybe a live reloader";
## the SEMANTICS (which fields, which reloader) are supplied by the
## game's own loaders: every `load_dir` call registers its `required`
## schema under the directory's kind, and a system that can re-read its
## records live registers a reloader (WildlifeManager does). A kind with
## no registered schema validates as "parses as an object" — the honest
## floor, never an invented rule.

## kind (data/<kind>) -> the required-field schema its loader passed to
## load_dir; the desk's `records validate/schema` read this.
var _schemas: Dictionary = {}
## kind -> Callable() that re-reads that kind's records and rebinds them
## in the live sim (registered by the owning system at _ready).
var _reloaders: Dictionary = {}

## Parse a JSON file; null (with an error) on failure.
func load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("[records] missing or empty: " + path)
		return null
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("[records] invalid JSON: " + path)
	return parsed


## Load every .json in a directory -> {basename: record}, dropping records
## that fail validation. `required` maps field name -> Variant.Type.
func load_dir(dir_path: String, required: Dictionary = {}) -> Dictionary:
	# Remember the kind's schema so `records validate` judges an edited
	# record by the exact same required-field map its loader trusts.
	_schemas[dir_path.get_file()] = required
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var path := dir_path + "/" + f
		var rec = load_json(path)
		if rec is Dictionary and validate(rec, required, path):
			out[f.trim_suffix(".json")] = rec
	return out


## Check required fields and types. JSON numbers arrive as float; ints
## are accepted where floats are required. Pushes the first failure to
## the error log (load-time behaviour), then returns whether it passed.
func validate(record: Dictionary, required: Dictionary, context: String) -> bool:
	var msg := validate_message(record, required)
	if msg != "":
		push_error("[records] %s: %s" % [context, msg])
		return false
	return true


## The same judgement, but RETURNING the failure text (or "" when the
## record passes) instead of logging it — so the `records validate` link
## verb can hand the game's own words back to the desk's inspector. The
## one truth `validate` and the desk both read.
func validate_message(record: Dictionary, required: Dictionary) -> String:
	for field in required:
		if not record.has(field):
			return "missing field '%s'" % field
		var want: int = required[field]
		var got := typeof(record[field])
		if got != want and not (want == TYPE_FLOAT and got == TYPE_INT):
			return "field '%s' should be %s, got %s" % [
				field, type_string(want), type_string(got)]
	return ""


## The records desk's validation door: judge a record of `kind` by the
## schema its loader registered. An unknown kind (loaded by hand via
## load_json, or not yet loaded) has no field schema — a record that
## parsed as an object is all the game can promise, so it passes. Returns
## "" on ok, else the game's own failure words.
func validate_kind(kind: String, record: Dictionary) -> String:
	return validate_message(record, _schemas.get(kind, {}))


## The required-field schema a kind registered (empty when none) — the
## `records schema` verb turns this into the desk's per-field type hints.
func schema_for(kind: String) -> Dictionary:
	return _schemas.get(kind, {})


## A system that can re-read its records and rebind them live registers a
## reloader here (kind -> Callable()); the `records reload` verb calls it
## after a landed write so the running game reflects the edit.
func register_reloader(kind: String, reloader: Callable) -> void:
	_reloaders[kind] = reloader


func reloader_for(kind: String) -> Callable:
	return _reloaders.get(kind, Callable())
