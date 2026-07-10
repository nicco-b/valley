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
##   dev-gate         a framework file may not gate on OS.is_debug_build()
##                    directly (PLAN_SHIP §2 FW5): the dev control plane is
##                    an explicit signal, not a build-flavor accident.
##                    DevMode is the one door — game/dev/dev_mode.gd is the
##                    sole exemption (it reads the raw signal so nothing
##                    else has to). No allowlist: new gates route through
##                    DevMode.active() or they fail the fence.
##   teardown-reap    the TEARDOWN-REAP LAW: a framework file that submits
##                    a WorkerThreadPool task (add_task/add_group_task) or
##                    spins a Thread must reap it in _exit_tree — a
##                    wait_for_task_completion/wait_to_finish call in that
##                    function's own body — before the tree (and the
##                    autoloads an in-flight task reads) tears down under
##                    it. Four crashes earned this one (hydrology
##                    catchments, the toolkit ghost player, sand_patch's
##                    build, water_field's base bake — the last was the
##                    engine-restart blocker). tests/ is exempt, same as
##                    asset-preload/content-id/dev-gate — its probes wait
##                    on their tasks inline, not from a node lifecycle.
##   rd-teardown      the RD-RID LAW (teardown-reap's sibling, 2026-07-09's
##                    leak hunt: 41 leaked RIDs): a framework file that
##                    calls a RenderingDevice RID creator (texture_create,
##                    sampler_create, storage_buffer_create,
##                    shader_create_from_spirv, compute_pipeline_create,
##                    uniform_buffer_create) must free every such RID in a
##                    method reachable from _exit_tree while the RD is
##                    still alive — RID lifetime is manual and a GDScript
##                    object refcounting to zero does NOT reclaim it.
##                    The shipping shape is CROSS-FILE: the creator is a
##                    RefCounted driver (water_gpu.gd, sand_gpu.gd,
##                    wave_gpu.gd) with no _exit_tree of its own, exposing
##                    a teardown() that frees every RID it made; the OWNER
##                    Node (water_field.gd, sand_field.gd, water_waves.gd)
##                    calls that teardown() from its own _exit_tree. A
##                    per-file rule would false-flag all three exemplars
##                    (and every future GPU driver built the same way) and
##                    demand a standing allowlist entry for the NORMAL
##                    case — the opposite of the fence's job. So the check
##                    is honestly cross-file: a creator file passes if (a)
##                    its own _exit_tree frees the RIDs directly (same-file
##                    shape), or (b) it defines some method whose body
##                    frees them AND some framework file's _exit_tree body
##                    calls that method by name. Fails otherwise, naming
##                    the creator file — whether it defines no free method
##                    at all, or defines one nobody ever calls.
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
	# (PLAN_AUDIO A1 removed player.gd's res://assets/audio/steps literal —
	# footsteps are data now, data/audio/footsteps.json — so its
	# asset-preload allowlist entry retired with it.)
	{"path": "game/villagers/villager_manager.gd", "rule": "content-id",
		"literal": "home",
		"reason": "villager-record schema field key (spawn/rest position), not an id "
			+ "reference — coincides with a watershed record id; the wildlife SCHEMA "
			+ "uses the same key but rides as content (unscanned)"},
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
	# -- teardown-reap: none today — every framework file that submits a
	# WorkerThreadPool/Thread task reaps it for real in _exit_tree
	# (hydrology.gd, sand_patch.gd, water_field.gd, sand_field.gd,
	# far_terrain.gd, world_streamer.gd, water_bodies.gd). A future
	# justified exception (a task reaped from somewhere other than
	# _exit_tree, documented) goes here — clearing it retires the entry
	# in the same commit, same discipline as every other rule above. --
	# -- rd-teardown: none today — the three GPU drivers that mint
	# RenderingDevice RIDs (water_gpu.gd, sand_gpu.gd, wave_gpu.gd) each
	# expose a teardown() that frees every RID, and each owner
	# (water_field.gd, sand_field.gd, water_waves.gd) calls it from its
	# own _exit_tree. A future justified exception (RIDs freed from
	# somewhere other than an _exit_tree-reachable method, documented)
	# goes here — same discipline as every other rule above. --
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

	var gatehit := lint_text("probe/dirty4.gd",
		"\tset_process(OS.is_debug_build())\n", [])
	_check(gatehit.size() == 1 and gatehit[0].rule == "dev-gate",
		"probe: dev-gate catches a direct OS.is_debug_build() call")

	var clean := lint_text("probe/clean.gd",
		"# res://assets/ only in a comment, and \"wind_strength\" isn't a data id\n"
		+ "# OS.is_debug_build() in a comment is fine too\n"
		+ "RenderingServer.global_shader_parameter_set(\"wind_strength\", 0.1)\n",
		["probe_id"])
	_check(clean.is_empty(), "probe: a clean file passes with zero hits")

	# teardown-reap: (b) an unreaped task is CAUGHT, two shapes —
	# no _exit_tree at all, and an _exit_tree that never waits.
	var reap_missing := lint_text("probe/reap_dirty_missing.gd",
		"func _ready() -> void:\n"
		+ "\t_task = WorkerThreadPool.add_task(_build)\n",
		[])
	_check(reap_missing.size() == 1 and reap_missing[0].rule == "teardown-reap",
		"probe: teardown-reap catches add_task with no _exit_tree at all")

	var reap_hollow := lint_text("probe/reap_dirty_hollow.gd",
		"func _ready() -> void:\n"
		+ "\t_thread = Thread.new()\n"
		+ "\t_thread.start(_build)\n"
		+ "\n"
		+ "func _exit_tree() -> void:\n"
		+ "\tpass  # forgot to reap\n",
		[])
	_check(reap_hollow.size() == 1 and reap_hollow[0].rule == "teardown-reap",
		"probe: teardown-reap catches an _exit_tree that never waits")

	# teardown-reap: (a) the real shapes in the tree today pass clean —
	# WorkerThreadPool and Thread, both reaped for real in _exit_tree.
	var reap_clean_pool := lint_text("probe/reap_clean_pool.gd",
		"func _ready() -> void:\n"
		+ "\t_task = WorkerThreadPool.add_task(_build)\n"
		+ "\n"
		+ "func _exit_tree() -> void:\n"
		+ "\tif _task != -1:\n"
		+ "\t\tWorkerThreadPool.wait_for_task_completion(_task)\n"
		+ "\t\t_task = -1\n",
		[])
	_check(reap_clean_pool.is_empty(),
		"probe: teardown-reap passes a WorkerThreadPool task reaped in _exit_tree")

	var reap_clean_thread := lint_text("probe/reap_clean_thread.gd",
		"func _ready() -> void:\n"
		+ "\t_thread = Thread.new()\n"
		+ "\t_thread.start(_build)\n"
		+ "\n"
		+ "func _exit_tree() -> void:\n"
		+ "\tif _thread != null:\n"
		+ "\t\t_thread.wait_to_finish()\n",
		[])
	_check(reap_clean_thread.is_empty(),
		"probe: teardown-reap passes a Thread reaped in _exit_tree")

	# rd-teardown: a creator with a texture_create and no free anywhere in
	# the file is CAUGHT outright — no teardown/free method exists at all.
	var rd_dirty := _rd_teardown_hits({"probe/rdgpu_dirty.gd":
		"func setup() -> void:\n\trd.texture_create(fmt, view)\n"})
	_check(rd_dirty.size() == 1 and rd_dirty[0].rule == "rd-teardown",
		"probe: rd-teardown catches texture_create with no free anywhere")

	# rd-teardown: a creator that DOES define a teardown() with free_rid,
	# but that nobody's _exit_tree ever calls, is still CAUGHT — a free
	# method that exists but is never wired is exactly as leaky as none.
	var rd_uncalled := _rd_teardown_hits({
		"probe/rdgpu_creator2.gd":
			"func setup() -> void:\n\trd.texture_create(fmt, view)\n\n"
			+ "func teardown() -> void:\n\trd.free_rid(_tex)\n",
		"probe/rdgpu_owner2.gd":
			"func _exit_tree() -> void:\n\tpass  # forgot to call teardown\n",
	})
	_check(rd_uncalled.size() == 1 and rd_uncalled[0].rule == "rd-teardown",
		"probe: rd-teardown catches a teardown() defined but never called from any _exit_tree")

	# rd-teardown: the real three-file shape PASSES — a RefCounted creator
	# defines teardown() with free_rid, and a separate owner file's own
	# _exit_tree calls it (water_gpu.gd/water_field.gd's real pattern).
	var rd_clean_split := _rd_teardown_hits({
		"probe/rdgpu_creator3.gd":
			"func setup() -> void:\n\trd.texture_create(fmt, view)\n\n"
			+ "func teardown() -> void:\n\trd.free_rid(_tex)\n",
		"probe/rdgpu_owner3.gd":
			"func _exit_tree() -> void:\n\t_gpu.teardown()\n",
	})
	_check(rd_clean_split.is_empty(),
		"probe: rd-teardown passes the real three-file pattern (creator's teardown() "
			+ "called from the owner's _exit_tree)")

	# rd-teardown: the same-file shape also PASSES — a Node that creates
	# RD RIDs directly and frees them in its own _exit_tree, no split.
	var rd_clean_same := _rd_teardown_hits({"probe/rdgpu_node.gd":
		"func _ready() -> void:\n\trd.texture_create(fmt, view)\n\n"
		+ "func _exit_tree() -> void:\n\trd.free_rid(_tex)\n"})
	_check(rd_clean_same.is_empty(),
		"probe: rd-teardown passes a same-file create + free-in-_exit_tree pattern")


# --- pass 2: the real manifest ------------------------------------------

func _run_real() -> void:
	var files := _framework_files()
	_check(not files.is_empty(), "framework.json names at least one file")
	var ids := _content_ids(files)
	print("  scanning %d framework files against %d content ids" % [files.size(), ids.size()])

	var gd_texts: Dictionary = {}  # path -> text, .gd files only (rd-teardown's corpus)
	for path in files:
		var ext := path.get_extension()
		if not SCANNABLE_EXT.has(ext):
			continue
		if not FileAccess.file_exists("res://" + path):
			_check(false, "%s: manifest names a missing file" % path)
			continue
		var text := FileAccess.get_file_as_string("res://" + path)
		if ext == "gd":
			gd_texts[path] = text
		for hit: Dictionary in lint_text(path, text, ids):
			# The verification harness ships in the manifest (FW3) but its
			# job is to probe CONTENT where it ships — every probe rides a
			# content-empty guard. Naming ids/assets there is the harness
			# working, not a framework coupling; only shader-global applies.
			# teardown-reap rides the same exemption: the test probes wait
			# on their tasks inline (SceneTree/probe scripts, no node
			# lifecycle), not from an _exit_tree reap.
			if path.begins_with("tests/") and hit.rule != "shader-global":
				continue
			# DevMode is the one door (PLAN_SHIP §2): dev_mode.gd reads the
			# raw OS.is_debug_build() signal so every other framework file
			# can route through DevMode.active(). Not an allowlist entry —
			# an intrinsic exemption the rule carries.
			if hit.rule == "dev-gate" and hit.path == "game/dev/dev_mode.gd":
				continue
			var allowed := _allowlisted(hit)
			if allowed.is_empty():
				_failures += 1
				print("  FAIL [%s] %s: '%s'" % [hit.rule, hit.path, hit.literal])
			else:
				_observed += 1
				print("  OBSERVE [%s] %s: '%s' (%s)" % [hit.rule, hit.path, hit.literal, allowed.reason])

	# rd-teardown is cross-file (see header doc) so it scans the whole .gd
	# corpus at once rather than one file at a time like the rules above.
	# tests/ rides the same exemption as teardown-reap — its probes free
	# any RD resources they make inline, not from a node lifecycle.
	for hit: Dictionary in _rd_teardown_hits(gd_texts):
		if hit.path.begins_with("tests/"):
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
	var devgate_re := RegEx.create_from_string("OS\\.is_debug_build\\s*\\(")

	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			continue

		for m in asset_re.search_all(line):
			hits.append({"path": path, "rule": "asset-preload",
				"literal": m.get_string().substr(1, m.get_string().length() - 2)})

		for m in devgate_re.search_all(line):
			hits.append({"path": path, "rule": "dev-gate",
				"literal": "OS.is_debug_build"})

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

	# teardown-reap is a whole-file check, not per-line: it needs to see
	# _exit_tree's own body, not just the line a task was submitted on.
	if path.get_extension() == "gd":
		var reap_hit := _reap_hit(path, text)
		if not reap_hit.is_empty():
			hits.append(reap_hit)
	return hits


## The TEARDOWN-REAP LAW, static: does this file submit a WorkerThreadPool
## task or spin a Thread, and if so does its _exit_tree actually wait on
## it? Comment-only lines are skipped, same as the per-line rules above.
## Returns a single {path, rule, literal} hit, or {} if clean.
func _reap_hit(path: String, text: String) -> Dictionary:
	var submit_re := RegEx.create_from_string(
		"WorkerThreadPool\\.(add_task|add_group_task)\\s*\\(|Thread\\.new\\s*\\(")
	var submits := false
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			continue
		if submit_re.search(line):
			submits = true
			break
	if not submits:
		return {}
	var body := _exit_tree_body(text)
	if body.contains("wait_for_task_completion") or body.contains("wait_to_finish"):
		return {}
	return {"path": path, "rule": "teardown-reap",
		"literal": "WorkerThreadPool/Thread task with no _exit_tree reap "
			+ "(TEARDOWN-REAP LAW)"}


## Extracts the body of this file's top-level `func _exit_tree` (from its
## `func` line to the next top-level `func` or end of file), or "" if the
## file has no _exit_tree at all. Top-level funcs start at column 0 —
## Godot's own style — so a nested `func` inside a lambda never ends the
## body early.
func _exit_tree_body(text: String) -> String:
	var lines := text.split("\n")
	var start := -1
	for i in lines.size():
		if lines[i].begins_with("func _exit_tree"):
			start = i
			break
	if start == -1:
		return ""
	var out: Array[String] = []
	for i in range(start + 1, lines.size()):
		if lines[i].begins_with("func "):
			break
		out.append(lines[i])
	return "\n".join(out)


# --- the RD-RID LAW (rd-teardown), cross-file --------------------------

const RD_CREATE_PATTERN := "(texture_create|sampler_create|storage_buffer_create" \
	+ "|shader_create_from_spirv|compute_pipeline_create|uniform_buffer_create)\\s*\\("

## True if this file's source calls one of the RD RID creator methods
## (comment-only lines excluded, same convention as every rule above). The
## `\s*\(` right after the method name is what keeps this from tripping on
## texture_create_from_extension (preview_terrain.gd's wrap-not-create
## call) — that name merely CONTAINS "texture_create" as a substring.
func _creates_rd_rids(text: String) -> bool:
	var re := RegEx.create_from_string(RD_CREATE_PATTERN)
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			continue
		if re.search(line):
			return true
	return false


## Every top-level `func` in this file, name -> body text (from just after
## its `func` line to the next top-level `func` or EOF). Same column-0
## convention as _exit_tree_body, generalized to all functions so
## rd-teardown can find whichever method (if any) frees the RIDs a
## RefCounted creator has no _exit_tree to do it in itself.
func _top_level_func_bodies(text: String) -> Dictionary:
	var bodies: Dictionary = {}
	var name := ""
	var lines_out: Array[String] = []
	for line in text.split("\n"):
		if line.begins_with("func "):
			if name != "":
				bodies[name] = "\n".join(lines_out)
			var after := line.substr(5)
			var paren := after.find("(")
			name = after.substr(0, paren).strip_edges() if paren != -1 else after.strip_edges()
			lines_out = []
		elif name != "":
			lines_out.append(line)
	if name != "":
		bodies[name] = "\n".join(lines_out)
	return bodies


## Method names (excluding _exit_tree itself) whose body contains a
## free_rid call — candidate teardown/free methods a creator file exposes
## for an owner elsewhere to invoke from ITS _exit_tree.
func _free_rid_method_names(text: String) -> Array[String]:
	var out: Array[String] = []
	var bodies := _top_level_func_bodies(text)
	for method_name: String in bodies:
		if method_name == "_exit_tree":
			continue
		var body: String = bodies[method_name]
		if body.contains("free_rid"):
			out.append(method_name)
	return out


## True if some framework file's _exit_tree body (any file, including the
## creator's own — the same-file shape) calls `method_name(...)`. This is
## the cross-file half of the check: a RefCounted driver has no _exit_tree
## of its own, so the wiring that actually reaps its RIDs lives in the
## OWNER Node's _exit_tree instead (water_field.gd calling
## `_gpu.teardown()`, sand_field.gd, water_waves.gd — the shipping shape).
func _exit_tree_calls_method(all_texts: Dictionary, method_name: String) -> bool:
	var call_re := RegEx.create_from_string("\\b" + method_name + "\\s*\\(")
	for path: String in all_texts:
		var body := _exit_tree_body(all_texts[path])
		if body != "" and call_re.search(body):
			return true
	return false


## The RD-RID LAW over the whole .gd corpus at once (path -> text). A file
## that creates RD RIDs passes if (a) its OWN _exit_tree frees them
## directly (a Node driving RD itself, no split needed), or (b) it defines
## some method whose body frees them and some framework file's _exit_tree
## calls that method by name (the real three-file shape: a RefCounted
## creator's teardown(), invoked from its owner Node's _exit_tree). Fails
## otherwise, naming the creator file — whether no free method exists at
## all, or one exists but nothing ever calls it.
func _rd_teardown_hits(all_texts: Dictionary) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for path: String in all_texts:
		var text: String = all_texts[path]
		if not _creates_rd_rids(text):
			continue
		if _exit_tree_body(text).contains("free_rid"):
			continue  # same-file shape: this file frees what it creates
		var candidates := _free_rid_method_names(text)
		if candidates.is_empty():
			hits.append({"path": path, "rule": "rd-teardown",
				"literal": "creates RenderingDevice RIDs but defines no teardown/free "
					+ "method with free_rid, and its own _exit_tree (if any) doesn't "
					+ "free them either (RD-RID LAW)"})
			continue
		var called := false
		for method_name in candidates:
			if _exit_tree_calls_method(all_texts, method_name):
				called = true
				break
		if not called:
			hits.append({"path": path, "rule": "rd-teardown",
				"literal": ("creates RenderingDevice RIDs; defines %s() with free_rid "
					+ "but no framework _exit_tree calls it (RD-RID LAW)") % candidates[0]})
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
