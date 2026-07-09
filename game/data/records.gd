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
## kind -> the directory its records were scanned from. `load_dir`
## remembers it (kind = the dir's basename); a loader whose records live
## in a NESTED dir whose basename doesn't match its desk kind (audio_sfx
## lives at data/audio/sfx, audio_ambience at data/audio/ambience)
## registers it by name via `register_dir`. The reload verb re-scans HERE
## instead of the naive data/<kind>, so a nested-dir kind counts right —
## the A1 wart ("records reload audio_sfx" counted the absent data/audio_sfx).
var _dirs: Dictionary = {}
## kind -> Callable() that re-reads that kind's records and rebinds them
## in the live sim (registered by the owning system at _ready).
var _reloaders: Dictionary = {}
## kind -> Array of edge DECLARATIONS the game published for this kind:
## each is {"field": String, "to": String} — which record field carries
## graph edges and what its ids reference (quests: [{"field":"after",
## "to":"stage-id"}]). The framework stays edge-agnostic: it only relays
## what a game declared. Strata's graph view renders/edits ONLY declared
## edge fields — no declaration, no edge editing (PLAN.md axiom-4
## amendment: "a graph view MAY render and edit fields the game's schema
## declares as edges … Strata never defines an evaluation model").
var _edges: Dictionary = {}
## kind -> Callable(record: Dictionary) -> String: a SEMANTIC validator the
## owning system registers (quests -> QuestLint). Returns "" when the whole
## record is sound, else the game's own first failure words. `validate_kind`
## runs it AFTER the required-field check, so an edge edit that makes a
## cycle / names an unknown stage bounces with the game's lint, not a
## Strata invention (quest_lint/story stay the only semantic truth).
var _validators: Dictionary = {}

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
	# record by the exact same required-field map its loader trusts, and
	# the dir so `records reload` re-scans the place it was loaded from.
	register_schema(dir_path.get_file(), required)
	register_dir(dir_path.get_file(), dir_path)
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
## schema its loader registered, THEN by any semantic validator the owning
## system registered (quests -> QuestLint: cycles, unreachable stages,
## unknown `after` targets — the truths the required-field map can't see).
## An unknown kind (loaded by hand via load_json, or not yet loaded) has no
## field schema and no validator — a record that parsed as an object is all
## the game can promise, so it passes. Returns "" on ok, else the game's
## own failure words.
func validate_kind(kind: String, record: Dictionary) -> String:
	var msg := validate_message(record, _schemas.get(kind, {}))
	if msg != "":
		return msg
	var validator: Callable = _validators.get(kind, Callable())
	if validator.is_valid():
		return String(validator.call(record))
	return ""


## Register a kind's required-field schema by NAME, independent of a
## `load_dir` call. `load_dir` routes through here (kind = the directory's
## basename); a loader whose records live in a NESTED dir whose basename
## doesn't match the desk kind it wants (data/audio/sfx served as kind
## "audio_sfx") registers the schema itself, so `records validate <kind>`
## judges by the same map the loader trusts. Idempotent — the last writer
## for a kind wins, as with load_dir.
func register_schema(kind: String, required: Dictionary) -> void:
	_schemas[kind] = required


## The required-field schema a kind registered (empty when none) — the
## `records schema` verb turns this into the desk's per-field type hints.
func schema_for(kind: String) -> Dictionary:
	return _schemas.get(kind, {})


## Register the directory a kind's records were scanned from. `load_dir`
## routes through here (kind = the dir's basename); a NESTED-dir loader
## whose desk kind differs from the basename (audio_sfx -> data/audio/sfx)
## registers it explicitly so the reload verb re-scans the true path, not
## the naive res://data/<kind>. Idempotent — last writer wins.
func register_dir(kind: String, dir_path: String) -> void:
	_dirs[kind] = dir_path


## The directory a kind was loaded from, or the naive res://data/<kind>
## when none was registered (the honest default: most kinds ARE a top-level
## data dir named for the kind).
func dir_for(kind: String) -> String:
	return _dirs.get(kind, "res://data/" + kind)


## Count the valid records a kind currently has on disk — the reload verb's
## fresh tally. Scans the kind's REGISTERED dir with its REGISTERED schema
## and judges each by the same required-field map `load_dir` trusts, WITHOUT
## load_dir's side effects (re-registering schema/dir under the scanned
## basename would clobber a nested-dir kind, e.g. count data/audio/sfx as
## kind "sfx"). Content-empty (no dir / no files) counts zero, errors nothing.
func count_dir(kind: String) -> int:
	var dir := DirAccess.open(dir_for(kind))
	if dir == null:
		return 0
	var schema: Dictionary = _schemas.get(kind, {})
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var rec = load_json(dir_for(kind) + "/" + f)
		if rec is Dictionary and validate_message(rec, schema) == "":
			n += 1
	return n


## Publish a kind's edge declarations (the graph fields Strata may render
## and edit). `edges` is an Array of {"field": String, "to": String}. The
## owning system calls this once at _ready (quests -> after -> stage-id).
func register_edges(kind: String, edges: Array) -> void:
	_edges[kind] = edges


## A kind's edge declarations (empty when none) — the `records schema` verb
## appends these so Strata's graph view knows which fields are edges.
func edges_for(kind: String) -> Array:
	return _edges.get(kind, [])


## Register a kind's SEMANTIC validator (record -> failure words, "" = ok).
## The owning system supplies the game's own judgement (quests -> QuestLint)
## so an edited record is judged by the same rules test.sh enforces, never
## by a rule Strata invented.
func register_validator(kind: String, validator: Callable) -> void:
	_validators[kind] = validator


## A system that can re-read its records and rebind them live registers a
## reloader here (kind -> Callable()); the `records reload` verb calls it
## after a landed write so the running game reflects the edit.
func register_reloader(kind: String, reloader: Callable) -> void:
	_reloaders[kind] = reloader


func reloader_for(kind: String) -> Callable:
	return _reloaders.get(kind, Callable())
