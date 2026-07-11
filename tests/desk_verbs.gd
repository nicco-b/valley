extends Node
## The desk verbs' headless entry (F5 · Q9, DESIGN_QUESTS §9-10). Strata's
## desk link (Sources/StrataCore DeskQuest, port 46485) shells `godot
## --headless --path <gameDir> res://tests/desk_verbs.tscn` at a game dir to
## AUTHOR AND VALIDATE quest content without the live pane — the runImporter
## precedent inverted into read-only checks. It wraps the game's EXISTING
## machinery (QuestLint, the Records loader) and prints ONE machine-readable
## verdict line the desk parses:
##
##   DESK-VERB <verb> PASS n=<count>     — clean; count is problems checked/found
##   DESK-VERB <verb> FAIL n=<count>     — <count> problems, each on its own
##                                         "  <verb>: <problem>" line above
##
## The verb is chosen by env (a desk shell-out sets it, never an arg the game
## parses — the two-tier law: the game is the interpreter, the desk the caller):
##   STRATA_DESK_VERB=quest_lint          -> QuestLint.lint_all() over the game's
##                                           data/quests + data/threads (the
##                                           authored-arc invariants Records
##                                           can't see)
##   STRATA_DESK_VERB=records_validate    -> every data record judged by the
##     [STRATA_DESK_KIND=<kind>]             game's OWN registered schema +
##                                           semantic validator (Records.
##                                           validate_kind); one kind when
##                                           STRATA_DESK_KIND is set, else every
##                                           kind the autoloads registered
##
## quest_test rides the EXISTING harness (tests/quest_harness.tscn) — this
## scene carries only the two passes that lacked a headless home. Autoloads
## run before this _ready, so the Records schema/validator registry every
## game loader fills at boot is live here (records_validate needs it).

const QUESTS_DIR := "res://data/quests"


func _ready() -> void:
	var verb := String(OS.get_environment("STRATA_DESK_VERB"))
	match verb:
		"quest_lint":
			_run(verb, _quest_lint())
		"records_validate":
			_run(verb, _records_validate(String(OS.get_environment("STRATA_DESK_KIND"))))
		_:
			print("DESK-VERB %s FAIL n=1" % (verb if not verb.is_empty() else "unknown"))
			print("  desk_verbs: unknown STRATA_DESK_VERB '%s' (want quest_lint|records_validate)" % verb)
			get_tree().quit(2)


## Print each problem, then the one verdict line, then quit (0 clean, 1 dirty).
## The desk reads the PASS/FAIL line; the per-problem lines are the honest
## failure detail its log tail surfaces (the runImporter pattern).
func _run(verb: String, problems: Array) -> void:
	for p in problems:
		print("  %s: %s" % [verb, p])
	if problems.is_empty():
		print("DESK-VERB %s PASS n=0" % verb)
		get_tree().quit(0)
	else:
		print("DESK-VERB %s FAIL n=%d" % [verb, problems.size()])
		get_tree().quit(1)


# --- quest_lint: the authored-spine linter over shipped records --------------

func _quest_lint() -> Array:
	return QuestLint.lint_all()


# --- records_validate: every record by the game's own registered judgement ---

## Judge the game's on-disk records by the SAME truth the write-path
## `records validate` verb trusts (Records.validate_kind: the loader's
## required-field schema, then any semantic validator the owning system
## registered — quests -> QuestLint). Scope: the kinds a game loader read
## through `load_dir` (a DIRECTORY of one-record-per-file .json) — the
## registry's `_dirs`, filled at boot. A schema-only kind (names: a single
## file holding an ARRAY of records) is a different loader shape and is NOT
## a per-record dir, so it is out of this verb's scope — including it would
## false-fail on "not a JSON object". One kind when STRATA_DESK_KIND is set
## (refused honestly when it isn't a per-record dir kind), else every dir
## kind. A kind with no dir / no files contributes nothing (content-empty is
## clean, the tile/card SKIP pattern) — never a phantom failure.
func _records_validate(kind: String) -> Array:
	var problems: Array = []
	var kinds: Array = []
	if not kind.is_empty():
		if not Records._dirs.has(kind):
			return ["%s: not a per-record directory kind (known: %s)"
				% [kind, ", ".join(_dir_kinds())]]
		kinds = [kind]
	else:
		kinds = _dir_kinds()
	for k: String in kinds:
		var dir_path: String = Records.dir_for(k)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			# An explicitly-requested kind with no directory is worth naming;
			# a swept kind (all-kinds mode) with none is just content-empty.
			if not kind.is_empty():
				problems.append("%s: no records directory at %s" % [k, dir_path])
			continue
		var files := Array(dir.get_files())
		files = files.filter(func(f: String) -> bool: return f.ends_with(".json"))
		files.sort()
		for f: String in files:
			var rec: Variant = Records.load_json(dir_path + "/" + f)
			if not (rec is Dictionary):
				problems.append("%s/%s: not a JSON object" % [k, f])
				continue
			var msg := Records.validate_kind(k, rec)
			if msg != "":
				problems.append("%s/%s: %s" % [k, f, msg])
	return problems


## The per-record directory kinds the autoloads registered (sorted, stable).
func _dir_kinds() -> Array:
	var ks: Array = Records._dirs.keys()
	ks.sort()
	return ks
