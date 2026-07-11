extends Node
## THE SAVE-LOAD GATE (E1e) — the dedicated harness that watches the load-time
## migration path the soak is structurally blind to.
##
## WHY A SEPARATE HARNESS, NOT THE SOAK: SaveMigration.migrate runs at LOAD
## (save_manager.load_into_world / restore_anchor via _read_anchor), ONCE, before
## the world exists — never on the sim tick. The soak (tests/soak.tscn) is the
## standing determinism gate, but it starts a FRESH seeded world and advances 30
## game-days; it NEVER loads a save from disk. So the soak's fingerprint cannot
## see this path — routing migrate behind STRATA_CONTOUR and leaning on the soak
## to prove flag-on inert would be a lie. This gate is that missing proof: it
## loads every real fixture through the real save path and asserts the GDScript
## twin (SaveMigration._migrate_gd, flag-OFF) equals the native Contour VM
## (save_migration.ct, flag-ON) BYTE-FOR-BYTE on the result dict AND the refusal
## sentences VERBATIM, plus the contour_status call counter to prove the VM
## actually answered (never a silent GDScript fallback). scripts/test.sh runs it
## BOTH ways — flag off and STRATA_CONTOUR=1 — in every gate.
##
## Runs on every platform: the byte-verbatim GDScript-twin assertions ALWAYS
## fire (the covenant's refusal sentences are the law with or without a kernel);
## the flag-off==flag-on VM comparison SKIPs where the native kernel is absent
## (off macOS / no dylib — the framework file rides every game). Success is the
## SAVE-LOAD-GATE PASS line, not the exit code (the --quit-after backstop exits 0
## even on an empty scene, so the harness must SAY it passed).

var _failures := 0
var _checks := 0


func _ready() -> void:
	# HERMETIC user:// — the gate writes its fixtures to the REAL save path
	# (user://save.json), and the live-save door reads that file THEN its
	# rotated backups .bak1/.bak2 (save_manager.load_into_world:115) — a
	# newer/torn save "falls back to a slightly older world, never to nothing."
	# Residue from earlier suites in the same test.sh run (scene_tests boots the
	# world; SaveGame's 30s autosave, _process:36, rotates a real day-N world
	# into .bak1) is NOT player-facing anchor data — it is exactly that backup
	# rotation. A save.json-only wipe missed it, so the refuse-newer check
	# lawfully loaded .bak1's day-9 world instead of refusing into nothing —
	# the live-tree "day still 9" failure. Clear the WHOLE live-save set so the
	# covenant is asserted against a known fallback state, not test.sh residue.
	# The gate leaves only its own last fixture behind (test residue, never
	# player data — the real games save under their own project user dirs).
	_clear_live_saves()
	var anchors := DirAccess.open("user://anchors")
	if anchors != null:
		for f in anchors.get_files():
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path("user://anchors/" + f))
	var flag := OS.get_environment("STRATA_CONTOUR")
	print("[gate] STRATA_CONTOUR=%s  kernel_available=%s" % [
		flag if flag != "" else "(unset)", Contour.available()])
	_gate_byte_identity()
	await _gate_real_path()
	if _failures == 0:
		print("SAVE-LOAD-GATE PASS (%d checks)" % _checks)
	else:
		print("SAVE-LOAD-GATE FAIL (%d of %d checks failed)" % [_failures, _checks])
	get_tree().quit()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  FAIL: %s" % msg)


## (1) BYTE-IDENTITY — flag-off (_migrate_gd) == flag-on (VM) over every fixture,
## and every refusal sentence verbatim. The GDScript-twin verbatim assertions run
## everywhere; the VM comparison runs where the kernel is live.
func _gate_byte_identity() -> void:
	# The real save fixtures (the framework-manifest'd valley saves) + the
	# adversarial and refuse-newer shapes the covenant must answer. `err` is the
	# EXACT sentence migrate must speak (tested verbatim — the covenant's voice).
	var NEWER99 := ("this save is from a newer version of the game "
		+ "(save format v99; this build reads up to v2) — update the game to open it")
	var NEWER3 := ("this save is from a newer version of the game "
		+ "(save format v3; this build reads up to v2) — update the game to open it")
	var cases: Array = [
		# real fixtures on disk — loaded exactly as the save path parses them
		{"tag": "v1_pre_interiors (file)", "raw": _fixture("v1_pre_interiors"),
			"ok": true, "newer": false, "err": ""},
		{"tag": "v2_current (file)", "raw": _fixture("v2_current"),
			"ok": true, "newer": false, "err": ""},
		# adversarial (non-dict / no-version / bad-version)
		{"tag": "non-dict string", "raw": "just a string",
			"ok": false, "newer": false, "err": "save is not a JSON object"},
		{"tag": "non-dict int", "raw": 42,
			"ok": false, "newer": false, "err": "save is not a JSON object"},
		{"tag": "torn parse (null)", "raw": null,
			"ok": false, "newer": false, "err": "save is not a JSON object"},
		{"tag": "no version", "raw": {"hello": "world"},
			"ok": false, "newer": false,
			"err": "save carries no version — refusing to guess its format"},
		{"tag": "version 0", "raw": {"version": 0, "player": {"x": 0.0, "z": 0.0}},
			"ok": false, "newer": false, "err": "save version 0 is not a known format"},
		{"tag": "version -3", "raw": {"version": -3},
			"ok": false, "newer": false, "err": "save version -3 is not a known format"},
		# refuse-newer (the covenant's core — never a crash, never a silent reset)
		{"tag": "newer v99", "raw": {"version": 99, "player": {"x": 1.0, "z": 2.0}},
			"ok": false, "newer": true, "err": NEWER99},
		{"tag": "newer v3", "raw": {"version": 3},
			"ok": false, "newer": true, "err": NEWER3},
	]

	# Every fixture parsed (the file cases must actually be on disk).
	_check(cases[0].raw is Dictionary and cases[1].raw is Dictionary,
		"the real save fixtures load from res://tests/fixtures/saves/")

	# The VM twin, compiled once (the flag-on oracle) — SKIP where absent.
	var vm: Contour = null
	if Contour.available():
		vm = Contour.new()
		var err := vm.compile_file("res://game/save/save_migration.ct")
		_check(err == "", "save_migration.ct compiles (%s)" % err)
		if err != "":
			vm = null
	else:
		print("  byte-identity: SKIP VM comparison (no native kernel — GDScript twin only)")

	for c in cases:
		var raw: Variant = c.raw
		# The flag-OFF path: the GDScript twin, always. Its result IS the covenant.
		var gd: Dictionary = SaveMigration._migrate_gd(raw)
		_check(bool(gd.get("ok", not c.ok)) == c.ok,
			"%s: twin ok=%s" % [c.tag, c.ok])
		_check(bool(gd.get("refused_newer", not c.newer)) == c.newer,
			"%s: twin refused_newer=%s" % [c.tag, c.newer])
		_check(String(gd.get("error", "<none>")) == c.err,
			"%s: twin speaks the refusal verbatim (got '%s')" % [c.tag, gd.get("error", "")])
		if c.ok:
			_check(int((gd.get("data", {}) as Dictionary).get("version", -1)) == SaveMigration.CURRENT,
				"%s: twin ladders to the current format (v%d)" % [c.tag, SaveMigration.CURRENT])
		# The flag-ON path: the native VM. Byte-for-byte identical to the twin.
		if vm != null:
			var vr: Variant = vm.call_fn("migrate", [raw])
			_check(vr is Dictionary, "%s: VM returns a result dict" % c.tag)
			if vr is Dictionary:
				_check(_eq(gd, vr),
					"%s: flag-off == flag-on BYTE-FOR-BYTE on the result dict" % c.tag)
				_check(String((vr as Dictionary).get("error", "<none>")) == c.err,
					"%s: the VM speaks the SAME refusal verbatim" % c.tag)

	if vm != null:
		print("  byte-identity: %d cases — flag-off (_migrate_gd) == flag-on (VM) byte-for-byte, refusals verbatim" % cases.size())


## (2) THE REAL SAVE PATH — drive save_manager's own load doors as far as headless
## allows (no player/world, so apply_snapshot's world-placement is out of reach —
## but the migrate call site inside load_into_world / restore_anchor / _read_anchor
## IS the door, and it is what routes). Proves: a valid save passes the real door,
## a newer save refuses at it, and (flag on) the door routed the VM (counter climbs).
func _gate_real_path() -> void:
	var before_calls := int(SaveMigration.contour_status().get("calls", 0))
	var engaged := bool(SaveMigration.contour_status().get("engaged", false))
	var mode := int(SaveMigration.contour_status().get("mode", 0))

	# --- restore_anchor / anchors_info / _read_anchor (replay_away=false: no
	#     wall-clock replay, so this drive never fires the sim) --------------------
	var v2: Dictionary = _fixture("v2_current")
	var future := {"version": SaveMigration.CURRENT + 99, "player": {"x": 3.0, "z": 4.0},
		"hours": 2.0, "day": 5, "state": {}, "wear": {}}
	_write_anchor("gate_v2", v2)
	_write_anchor("gate_future", future)

	var info := SaveGame.anchors_info()
	var names := []
	for row in info:
		names.append(String(row.get("name", "")))
	_check("gate_v2" in names,
		"real path: a valid v2 anchor migrates through _read_anchor and lists (names=%s)" % [names])
	_check(not ("gate_future" in names),
		"real path: a newer-format anchor is refused at the real door (skipped from the list)")

	var r_future := SaveGame.restore_anchor("gate_future")
	_check(not bool(r_future.get("ok", true))
			and String(r_future.get("error", "")) == "no anchor 'gate_future'",
		"real path: restore_anchor refuses the newer save (never a partial world) — '%s'" % r_future.get("error", ""))
	var r_v2 := SaveGame.restore_anchor("gate_v2")
	# The valid save passed the real migrate (got past _read_anchor's refusal
	# gate); headless simply has no player to seat it into.
	_check(not bool(r_v2.get("ok", true))
			and String(r_v2.get("error", "")) == "no player in the world to restore into",
		"real path: a valid save clears the real migrate door (halts only for want of a player) — '%s'" % r_v2.get("error", ""))

	# --- load_into_world (the live-save door; replay_away=true) ------------------
	# Valid: wall_time == now so the away-replay is ~0 (no runaway sim). The real
	# door parses + migrates + applies; with no player it stops after the clock.
	var live := {"version": 2, "hours": 9.5, "day": 42,
		"wall_time": Time.get_unix_time_from_system(), "civil": true,
		"player": {"x": 0.0, "z": 0.0}, "state": {}, "wear": {}, "cells": {}}
	_write_save(live)
	GameClock.day = -1
	await SaveGame.load_into_world()
	_check(GameClock.day == 42,
		"real path: load_into_world migrates+applies a valid save through the live door (day=%d)" % GameClock.day)

	# Newer at the live door: the covenant's whole point — refuse the newer save
	# honestly, and NEVER apply it. But "refuse" has TWO lawful outcomes at this
	# door, and the gate must pin BOTH hermetically (owning the .bak fallback set
	# itself, not leaning on whatever an earlier suite's autosave left in .bak1).
	#
	# (a) NO valid fallback — refuse into nothing, and NEVER a silent reset.
	#     save.json holds the newer save; the backups are empty. The loader
	#     refuses, finds no older world, and _spawn_fresh does NOT touch the
	#     clock (save_manager._spawn_fresh:220) — the sentinel survives untouched.
	_clear_live_saves()
	_write_save({"version": SaveMigration.CURRENT + 50, "player": {"x": 0.0, "z": 0.0},
		"hours": 1.0, "day": 3, "state": {}, "wear": {}})
	GameClock.day = 777
	await SaveGame.load_into_world()
	_check(GameClock.day == 777,
		"real path: a newer save with no backup is refused into nothing — the clock is NOT reset (day still %d)" % GameClock.day)

	# (b) A VALID older backup present — refuse the newer save, then fall back to
	#     the last-good world (save_manager.load_into_world:113 — "never to
	#     nothing"). This is the REAL day-9 behaviour, now made deterministic: a
	#     KNOWN day-321 world in .bak1 is what the door lands on. The covenant is
	#     NOT "keep the sentinel" here — it is "never the newer save, never fresh,
	#     always the best older valid world." Assert exactly that.
	_clear_live_saves()
	_write_save({"version": SaveMigration.CURRENT + 50, "player": {"x": 0.0, "z": 0.0},
		"hours": 1.0, "day": 3, "state": {}, "wear": {}})
	var backup := {"version": 2, "hours": 4.0, "day": 321,
		"wall_time": Time.get_unix_time_from_system(), "civil": true,
		"player": {"x": 0.0, "z": 0.0}, "state": {}, "wear": {}, "cells": {}}
	var bak1 := FileAccess.open(SaveGame.PATH + ".bak1", FileAccess.WRITE)
	bak1.store_string(JSON.stringify(backup, "\t"))
	bak1.close()
	GameClock.day = 777
	await SaveGame.load_into_world()
	_check(GameClock.day == 321,
		"real path: a newer save is refused and the door falls back to the last-good backup — not the newer save (day 3), not fresh, but the older world (day %d)" % GameClock.day)

	# --- the engagement counter: proof the real door routed (no silent fallback) -
	# When the flag is set AND the kernel is live, routing MUST engage — anything
	# else (a silent GDScript pass, or a mode -1 from a module that won't compile)
	# is a hard failure. When the kernel is genuinely absent (off macOS / no dylib)
	# a flag-on refusal is the honest, expected cross-platform outcome.
	var want_route := OS.get_environment("STRATA_CONTOUR") == "1" and Contour.available()
	var after_calls := int(SaveMigration.contour_status().get("calls", 0))
	if engaged:
		_check(after_calls > before_calls,
			"real path: the live save doors routed migrate through the Contour VM (%d->%d calls) — no silent fallback"
				% [before_calls, after_calls])
		print("SAVE-LOAD-GATE ROUTED (mode 2, %d VM-answered migrate calls)" % after_calls)
	else:
		_check(not want_route,
			"STRATA_CONTOUR=1 with a live kernel MUST engage the VM (mode %d) — never a silent fallback" % mode)
		if mode == 1:
			_check(after_calls == before_calls,
				"real path: flag-off save doors stay on the GDScript twin (calls %d, no silent routing)" % after_calls)
			print("SAVE-LOAD-GATE OFF (mode 1, GDScript twin — byte-identical, no VM)")
		else:
			# Flag set but kernel genuinely absent: a LOUD refusal, the honest
			# cross-platform outcome (the framework file rides every game).
			print("SAVE-LOAD-GATE REFUSED (mode -1, kernel/module unavailable — loud, not silent)")

	# Housekeeping (the isolated HOME is per-run, but leave no litter). Clear the
	# whole live-save set — the refuse-newer check now plants a .bak1 backup, so
	# the save.json-only sweep would leave that behind for the next suite.
	_rm_anchor("gate_v2")
	_rm_anchor("gate_future")
	_clear_live_saves()


# --- helpers ----------------------------------------------------------------

func _fixture(name: String) -> Variant:
	var path := "res://tests/fixtures/saves/%s.json" % name
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_anchor(name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveGame.ANCHORS_DIR))
	var path := SaveGame.ANCHORS_DIR.path_join(name + ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func _rm_anchor(name: String) -> void:
	var path := SaveGame.ANCHORS_DIR.path_join(name + ".json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_save(data: Dictionary) -> void:
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


## Clear the entire live-save set the door reads — save.json AND its rotated
## backups .bak1/.bak2 (and any half-written .tmp). The gate owns this set so
## the refuse-newer covenant is asserted against a known fallback state, never
## an earlier suite's autosaved residue (save_manager.load_into_world walks
## [PATH, .bak1, .bak2] in order — refusal falls back through the backups).
func _clear_live_saves() -> void:
	for p: String in [SaveGame.PATH, SaveGame.PATH + ".bak1",
			SaveGame.PATH + ".bak2", SaveGame.PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Exact structural equality — the byte-for-byte compare. Recurses dicts/arrays
## key-by-key (a Variant `==` quirk on nested Dictionaries can't hide a mismatch);
## leaves compare with `==`, an exact IEEE bit compare on floats.
func _eq(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _eq(a[k], b[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _eq(a[i], b[i]):
				return false
		return true
	return a == b
