extends SceneTree
## The fence gets teeth (PLAN_FRAMEWORK.md FW5): a static lint over every
## file `framework.json` lists, run via scripts/test.sh. Pure text
## scanning — no autoloads, no scene, no engine state — because the rules
## are all "does this framework file's SOURCE mention content" and every
## framework file is a plain text file on disk. Fast and honest, same
## spirit as tests/run_tests.gd's `godot -s` unit pass.
##
## Rules (Q1/Q3's "the cheap fence in between" a full directory split):
##   asset-preload   a framework file's source may not carry a literal
##                    "res://assets/..." string (preload/load or
##                    otherwise) — that path names game CONTENT.
##   content-id      a framework file's source may not carry a quoted
##                    string literal that exactly matches a content id
##                    minted by a record under data/ (cards/records
##                    live there; naming one by hand is a coupling).
##   shader-global    a framework file may not write a shader-global key
##                    literally namespaced "valley.*" — that bakes this
##                    game's name into machinery every game shares.
##
## ALLOWLIST is the FW1-era honesty valve: known hits, each tagged with
## WHY it's not failing the build today — either a pending FW4 rung that
## clears it (named), or RESIDUE (no rung claims it yet; the standing
## review's evidence). Allowlisted hits still print, as OBSERVE lines —
## the fence has teeth for anything NEW, and remembers what's already
## bitten. Removing a landed branch's entries here is that branch's own
## merge cleanup, not this rung's.

const MANIFEST_PATH := "res://framework.json"
const DATA_DIR := "res://data"
const SCANNABLE_EXT: Array[String] = ["gd", "gdshader", "glsl"]
const MIN_ID_LEN := 3

## {path, rule, literal, reason} — a known hit that does not fail the
## build. `reason` starts with the branch name that clears it, or
## "RESIDUE" if no pending rung claims it (see the ledger in the FW5
## report).
const ALLOWLIST: Array[Dictionary] = [
	# -- asset-preload: directory-taxonomy resolvers (asset KIND -> its
	# folder — every game has assets/models, assets/paintings; this
	# names the taxonomy, not a specific piece of content) --
	{"path": "game/data/cards.gd", "rule": "asset-preload",
		"literal": "res://assets/models",
		"reason": "kind->folder taxonomy (gltf_mesh), not specific content"},
	{"path": "game/data/cards.gd", "rule": "asset-preload",
		"literal": "res://assets/paintings",
		"reason": "kind->folder taxonomy (billboard_png), not specific content"},
	{"path": "game/dev/hot_reload.gd", "rule": "asset-preload",
		"literal": "res://assets/paintings",
		"reason": "dev hot-reload watches the paintings folder generically"},
	# -- content-id: framework-level enum names that coincide with
	# data/overrides/overrides.json's own layer-kind keys (the override
	# taxonomy is toolkit machinery, not narrative content) --
	{"path": "game/dev/overrides.gd", "rule": "content-id",
		"literal": "pen_override",
		"reason": "toolkit override-layer kind name (framework enum)"},
	{"path": "game/dev/overrides.gd", "rule": "content-id",
		"literal": "sculpt",
		"reason": "toolkit override-layer kind name (framework enum)"},
	{"path": "game/dev/toolkit.gd", "rule": "content-id",
		"literal": "sculpt",
		"reason": "toolkit tool-name enum (framework UI)"},
	{"path": "game/world/terrain.gd", "rule": "content-id",
		"literal": "sea",
		"reason": "schema field key (water-body bool flag), not an id reference"},
	{"path": "game/villagers/villager_manager.gd", "rule": "content-id",
		"literal": "home",
		"reason": "villager-record schema field key (spawn/rest position), not an id "
			+ "reference — coincides with a watershed record id; the wildlife SCHEMA "
			+ "uses the same key but rides as content (unscanned)"},
	{"path": "game/player/player.gd", "rule": "asset-preload",
		"literal": "res://assets/audio/steps",
		"reason": "content marked in place — Q1 wants character records (none exist "
			+ "yet, per the fence); one named, existence-guarded const until they do"},
	# -- content-id: RESIDUE. Real leaks, no pending rung claims them. --
	{"path": "game/player/player.gd", "rule": "content-id",
		"literal": "wayfaring",
		"reason": "RESIDUE - hardcoded skill id read by the player controller, unclaimed"},
	{"path": "game/player/player.gd", "rule": "content-id",
		"literal": "swimming",
		"reason": "RESIDUE - hardcoded skill id read by the player controller, unclaimed"},
	{"path": "game/player/player.gd", "rule": "content-id",
		"literal": "stillness",
		"reason": "RESIDUE - hardcoded skill id read by the player controller, unclaimed"},
	{"path": "game/player/player.gd", "rule": "content-id",
		"literal": "firefly",
		"reason": "RESIDUE - Q5 kitchen table: firefly item id named directly, unclaimed"},
	{"path": "game/items/firefly.gd", "rule": "content-id",
		"literal": "firefly",
		"reason": "RESIDUE - Q5 kitchen table: firefly item id named directly, unclaimed"},
	# -- content-id: Q1's "a Strata convention, not valley content — name it
	# once" — strata_link.gd and import_world.gd both now reference
	# StrataConventions.BAKED_WORLD_ID; the raw literal lives in exactly one
	# place, the convention file itself, where it necessarily defines it. --
	{"path": "game/dev/strata_conventions.gd", "rule": "content-id",
		"literal": "baked_world",
		"reason": "the one place the Strata tile-id convention is named (FW5, Q1)"},
	{"path": "tools/strata/import_world.gd", "rule": "content-id",
		"literal": "sea",
		"reason": "RESIDUE - the import tool mints the base ocean record's id by hand, unclaimed"},
]

var _failures := 0
var _observed := 0


func _init() -> void:
	_run_probes()
	_run_real()
	if _failures > 0:
		print("FRAMEWORK-LINT FAIL: %d failure(s), %d observed" % [_failures, _observed])
		quit(1)
	else:
		print("FRAMEWORK-LINT PASS (%d observed, allowlisted)" % _observed)
		quit(0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


# --- pass 1: self-probes (the fixtures) --------------------------------

func _run_probes() -> void:
	var dirty := lint_text("probe/dirty.gd",
		"const X := \"res://assets/paintings/x.png\"\n", ["probe_id"])
	_check(dirty.size() == 1 and dirty[0].rule == "asset-preload",
		"probe: asset-preload catches a literal res://assets/ path")

	var idhit := lint_text("probe/dirty2.gd",
		"var k := \"probe_id\"\n", ["probe_id"])
	_check(idhit.size() == 1 and idhit[0].rule == "content-id",
		"probe: content-id catches a literal data-record id")

	var globalhit := lint_text("probe/dirty3.gd",
		"RenderingServer.global_shader_parameter_set(\"valley.bloom\", true)\n", [])
	_check(globalhit.size() == 1 and globalhit[0].rule == "shader-global",
		"probe: shader-global catches an un-namespaced valley.* key")

	var clean := lint_text("probe/clean.gd",
		"# res://assets/ only in a comment, and \"wind_strength\" isn't a data id\n"
		+ "RenderingServer.global_shader_parameter_set(\"wind_strength\", 0.1)\n",
		["probe_id"])
	_check(clean.is_empty(), "probe: a clean file passes with zero hits")


# --- pass 2: the real manifest ------------------------------------------

func _run_real() -> void:
	var files := _framework_files()
	_check(not files.is_empty(), "framework.json names at least one file")
	var ids := _content_ids(files)
	print("  scanning %d framework files against %d content ids" % [files.size(), ids.size()])

	for path in files:
		var ext := path.get_extension()
		if not SCANNABLE_EXT.has(ext):
			continue
		if not FileAccess.file_exists("res://" + path):
			_check(false, "%s: manifest names a missing file" % path)
			continue
		var text := FileAccess.get_file_as_string("res://" + path)
		for hit: Dictionary in lint_text(path, text, ids):
			# The verification harness ships in the manifest (FW3) but its
			# job is to probe CONTENT where it ships — every probe rides a
			# content-empty guard. Naming ids/assets there is the harness
			# working, not a framework coupling; only shader-global applies.
			if path.begins_with("tests/") and hit.rule != "shader-global":
				continue
			var allowed := _allowlisted(hit)
			if allowed.is_empty():
				_failures += 1
				print("  FAIL [%s] %s: '%s'" % [hit.rule, hit.path, hit.literal])
			else:
				_observed += 1
				print("  OBSERVE [%s] %s: '%s' (%s)" % [hit.rule, hit.path, hit.literal, allowed.reason])


func _allowlisted(hit: Dictionary) -> Dictionary:
	for entry: Dictionary in ALLOWLIST:
		if entry.path == hit.path and entry.rule == hit.rule and entry.literal == hit.literal:
			return entry
	return {}


# --- the rules, over raw text (unit-testable without touching disk) -----

## Returns Array[Dictionary]: {path, rule, literal}. Comment-only lines
## (trimmed, starting with '#') are skipped — doc prose mentioning a
## path or an id isn't a coupling.
func lint_text(path: String, text: String, ids: Array) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var asset_re := RegEx.create_from_string("[\"']res://assets/[^\"']*[\"']")
	var lit_re := RegEx.create_from_string("[\"']([^\"']*)[\"']")
	var global_re := RegEx.create_from_string(
		"global_shader_parameter_(set|get)(_override)?\\s*\\(\\s*[\"']valley\\.[^\"']*[\"']")

	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			continue

		for m in asset_re.search_all(line):
			hits.append({"path": path, "rule": "asset-preload",
				"literal": m.get_string().substr(1, m.get_string().length() - 2)})

		for m in global_re.search_all(line):
			var full := m.get_string()
			var start := full.find("valley.")
			var lit := full.substr(start).rstrip("\"'")
			hits.append({"path": path, "rule": "shader-global", "literal": lit})

		if not ids.is_empty():
			for m in lit_re.search_all(line):
				var lit: String = m.get_string(1)
				if lit.length() >= MIN_ID_LEN and ids.has(lit):
					hits.append({"path": path, "rule": "content-id", "literal": lit})
	return hits


# --- manifest + content-id corpus ---------------------------------------

## Every path framework.json lists, flattened across its "systems" table.
func _framework_files() -> Array[String]:
	var out: Array[String] = []
	var manifest: Variant = _load_json(MANIFEST_PATH)
	if not (manifest is Dictionary):
		return out
	var systems: Dictionary = (manifest as Dictionary).get("systems", {})
	for key: String in systems:
		for f: String in systems[key]:
			out.append(String(f))
	return out


## Every "id" string minted by a record under data/, EXCEPT records that
## live in a file the manifest itself ships (data/world/biomes.json is
## the one marked exception — the default palette the importer paints
## against; its biome names are framework defaults, not this game's
## content, so they don't belong in the "don't name me" corpus).
func _content_ids(framework_files: Array[String]) -> Array[String]:
	var exempt: Dictionary = {}
	for f in framework_files:
		if f.begins_with("data/"):
			exempt[f] = true
	var ids: Dictionary = {}
	_walk_data_ids(DATA_DIR, exempt, ids)
	var out: Array[String] = []
	for k: String in ids:
		out.append(k)
	return out


func _walk_data_ids(dir_path: String, exempt: Dictionary, ids: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var full := dir_path + "/" + name
		if dir.current_is_dir():
			_walk_data_ids(full, exempt, ids)
		elif name.ends_with(".json"):
			var rel := full.trim_prefix("res://")
			if not exempt.has(rel):
				_collect_ids(_load_json(full), ids)
		name = dir.get_next()
	dir.list_dir_end()


func _collect_ids(node: Variant, ids: Dictionary) -> void:
	if node is Dictionary:
		var d: Dictionary = node
		if d.get("id") is String and String(d.id).length() >= MIN_ID_LEN:
			ids[String(d.id)] = true
		for v in d.values():
			_collect_ids(v, ids)
	elif node is Array:
		for v in node:
			_collect_ids(v, ids)


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var result: Variant = JSON.parse_string(text)
	return result
