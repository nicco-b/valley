extends Node
## Scene-context tests: anything that needs autoloads alive (Conditions,
## WorldState interplay). Run by test.sh: godot --headless scene_tests.tscn
## — exits 0/1.

var _failures := 0


func _ready() -> void:
	_test_conditions()
	_test_conditions_v2()
	_test_skills()
	_test_clock()
	_test_clock_lock()
	_test_weather_lock()
	_test_weather_clear()
	_test_seasons()
	_test_climate()
	_test_climate_v2()
	_test_water()
	_test_swell()
	_test_shoaling()
	_test_buoyancy()
	_test_hydrology()
	_test_hydrology_sim_lakes_contour()
	_test_strata_water()
	_test_river_drape()
	_test_bathy_edit_invalidate()
	_test_region_reseed()
	_test_sea_reload_visibility()
	_test_lake_outline()
	_test_lake_outline_bathy()
	_test_lake_mirror()
	_test_water_field()
	_test_wave_sources()
	_test_foam_memory()
	_test_flora()
	_test_moon()
	_test_wildlife()
	_test_villager()
	_test_body_records()
	_test_fabric_spring()
	_test_wear()
	await _test_nav()
	_test_sand_sim()
	_test_fabric()
	_test_tile_override()
	_test_kernel_retile_race()
	_test_placement_reseat()
	_test_cell_records_armor()
	_test_import_frame_refusal()
	_test_layer_region()
	_test_toolkit_history()
	_test_undo_footgun()
	_test_placement_edit()
	_test_toolkit_snap()
	_test_multi_select_group()
	_test_duplicate()
	_test_snap_apply()
	_test_socket_snap()
	_test_link_toolkit_ops()
	_test_prefab()
	_test_river_undo()
	_test_overrides_emit()
	_test_scatter_roundtrip()
	_test_edit_flush()
	_test_budget()
	_test_audio()
	_test_ambience()
	_test_water_audio()
	await _test_threshold()
	await _test_interior_hand()
	_test_map()
	_test_map_travel()
	await _test_bless_posture()
	_test_pause_esc_routing()
	_test_embedded_pane_posture()
	_test_story_dry_spell_real()
	_test_names()
	_test_playtest_anchors()
	_test_save_migration()
	await _test_strata_link()
	_test_teleport_defer()
	_test_contour()
	_test_conditions_contour()
	_test_contour_bridge()
	_test_flora_contour()
	_test_items_contour()
	_test_skills_contour()
	_test_budget_contour()
	_test_agent_mirror_json_safe()
	if _failures > 0:
		print("SCENE-TESTS FAIL: %d failed" % _failures)
	else:
		print("SCENE-TESTS PASS")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


## The world budget (a METER, NOT A WALL): the three axes grade green/amber/red
## against the thresholds (framework DEFAULTS under data/world/budget.json), the
## meter reads live state without ever writing it, and the `budget` link line
## carries the grammar Strata's Budget row parses. Grading is pinned at the
## boundaries so a tuned threshold cannot silently invert a colour.
func _test_budget() -> void:
	# Grading boundaries: below amber is green, amber..red-1 is amber, red+ is red.
	var a := int(Budget.thresholds.cell_placements.amber)
	var r := int(Budget.thresholds.cell_placements.red)
	_check(Budget.grade(a - 1, "cell_placements") == Budget.GREEN,
		"budget: below amber grades green")
	_check(Budget.grade(a, "cell_placements") == Budget.AMBER,
		"budget: at amber grades amber")
	_check(Budget.grade(r, "cell_placements") == Budget.RED,
		"budget: at red grades red")
	# The content record loaded over the framework defaults (valley ships one).
	_check(a > 0 and r > a, "budget: cell thresholds are ordered (amber<red)")
	# The link line grammar Strata's BudgetReport parser pins.
	var line := Budget.link_line()
	_check(line.begins_with("ok budget cell=") and " agents=" in line
		and " records=" in line and " est_ms=" in line,
		"budget: link line carries all three axes + est_ms (got %s)" % line)
	# The meter is read-only: reading it must not perturb the Chronicle.
	var before := Budget.total_records()
	Budget.snapshot()
	Budget.worst_grade()
	_check(Budget.total_records() == before, "budget: reading never mutates the Chronicle")


## Audio (PLAN_AUDIO A1): the house bus graph is framework-owned and built
## at boot (LAW A2), the SFX records are validated content (LAW A3), and a
## content-empty game (no SFX records ship in valley) plays silent, never
## errors (FW1). No sound is ever fingerprinted (LAW A1) — proven by soak,
## asserted here structurally: audio only reads AudioServer, never sim.
func _test_audio() -> void:
	# The house graph: Master (bus 0) + the five children, routed as the
	# plan's tree — World under Master, Ambience/SFX under World, Music/UI
	# straight to Master.
	_check(AudioServer.get_bus_name(0) == "Master", "audio: Master is bus 0")
	for bus in ["World", "Ambience", "SFX", "Music", "UI"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "audio: house bus %s exists" % bus)
	var sends := {"World": "Master", "Ambience": "World", "SFX": "World",
		"Music": "Master", "UI": "Master"}
	for bus in sends:
		_check(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == sends[bus],
			"audio: %s routes to %s" % [bus, sends[bus]])
	# The wart A1 fixes: UI (and Music) bypass World, so the underwater
	# low-pass on World (player.gd) can never muffle them — "UI is audible
	# underwater" is structural, not incidental.
	_check(AudioServer.get_bus_send(AudioServer.get_bus_index("UI")) != "World",
		"audio: UI does not route through World (never muffled underwater)")
	# SFX records are validated content: the desk judges kind audio_sfx by
	# the game's own loader schema. A bad record (missing a required field)
	# is caught; a complete one passes — the same words `records validate`
	# hands the desk.
	_check(not Records.schema_for("audio_sfx").is_empty(),
		"audio: audio_sfx schema registered for the records desk")
	var bad := {"id": "x", "files": [], "volume_db": -6.0}  # no bus
	_check(Records.validate_kind("audio_sfx", bad) != "",
		"audio: records validate audio_sfx catches a bad record (no bus)")
	var good := {"id": "x", "files": ["a.wav"], "volume_db": -6.0, "bus": "SFX"}
	_check(Records.validate_kind("audio_sfx", good) == "",
		"audio: a complete audio_sfx record validates")
	# Content-empty (valley ships no SFX records — the wavs are Nicco's):
	# an unknown event is a silent no-op, never a crash. The thunder socket
	# rides exactly this until a thunder_near record lands.
	Audio.play("no_such_event")
	Audio.play("thunder_near", Vector3.ZERO)
	Audio.play_file("res://assets/audio/does_not_exist.wav")
	_check(true, "audio: play of an unknown/absent sound is a safe no-op")
	# The Mix face's data: bus levels in tree order, one <bus>:<db> token
	# each (the `audio` verb's payload).
	var levels := Audio.bus_levels()
	_check(levels.begins_with("Master:") and " UI:" in levels,
		"audio: bus_levels lists the house buses (got %s)" % levels)

	# Commit-to-mix (X4 A3-breadth item 3): the write door on a TEMP file —
	# the shipped mix.json stays untouched here (the link-level probe below
	# exercises the real path with a snapshot/restore). A tuned SFX level
	# lands as "levels.SFX" and the existing "ducks" table survives
	# byte-for-byte (never a blind overwrite).
	var tmp_mix := "user://mix_commit_test.json"
	if FileAccess.file_exists(tmp_mix):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_mix))
	var seeded := {"ducks": [{"id": "probe_duck", "when": "interiors.inside",
		"bus": "Ambience", "gain": 0.5}]}
	var seed_f := FileAccess.open(tmp_mix, FileAccess.WRITE)
	seed_f.store_string(JSON.stringify(seeded, "\t"))
	seed_f.close()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), -3.25)
	var commit_r := Audio.commit_levels(tmp_mix)
	_check(bool(commit_r.get("ok", false)),
		"audio: commit_levels writes ok (got %s)" % commit_r.get("error", ""))
	var landed = Records.load_json(tmp_mix)
	_check(landed is Dictionary and absf(float(landed.get("levels", {}).get("SFX", 0.0)) - (-3.25)) < 0.01,
		"audio: commit_levels lands the live SFX level (got %s)" % landed)
	_check(landed.get("ducks", []).size() == 1
		and String(landed["ducks"][0].get("id", "")) == "probe_duck",
		"audio: commit_levels preserves the existing ducks table untouched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_mix))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), 0.0)


## The ambience machine (PLAN_AUDIO A2): beds are RECORDS now, the evaluator
## is record-driven, and valley's two shipped beds reproduce the OLD
## hardcoded curves BYTE-FOR-BYTE (the migration acceptance: same curves in
## = same params out, asserted numerically). Also: the desk validates the
## kind, the crossfade math is pure, and the mix.json interior duck drives
## the `audio` verb's duck token.
func _test_ambience() -> void:
	# Stand up the real machine (a world node, not an autoload — beds belong
	# to the world, never the title): its _ready registers the kind with the
	# desk and loads the shipped beds, exactly as valley.tscn does at boot.
	var amb := Ambience.new()
	add_child(amb)
	# The desk owns the beds: schema registered, dir registered at the true
	# nested path (the A1 wart fix — audio_sfx/audio_ambience live below
	# data/<kind>), reload counts that path.
	_check(not Records.schema_for(Ambience.AMBIENCE_KIND).is_empty(),
		"ambience: audio_ambience schema registered for the desk")
	_check(Records.dir_for(Ambience.AMBIENCE_KIND) == Ambience.AMBIENCE_DIR,
		"ambience: reload counts the registered nested dir, not data/audio_ambience")
	_check(Records.dir_for(Audio.SFX_KIND) == Audio.SFX_DIR,
		"ambience: audio_sfx dir registered (A1 wart: was counting data/audio_sfx)")
	# The beds themselves are CONTENT (data/audio_ambience — valley ships
	# wind/night/shore_lap; a content-empty tree has none). The desk wiring
	# above is framework and always asserts; the shipped-bed tallies/parse/
	# live-load below SKIP honestly when the beds are absent.
	var have_beds := Records.count_dir(Ambience.AMBIENCE_KIND) > 0
	if have_beds:
		_check(Records.count_dir(Ambience.AMBIENCE_KIND) == 3,
			"ambience: count_dir tallies the three shipped beds — wind/night plus W10's shore_lap (got %d)"
				% Records.count_dir(Ambience.AMBIENCE_KIND))
	else:
		print("  ambience: SKIP shipped-bed checks (no audio_ambience content — content-empty tree)")
	# The desk judges a bed by the game's own loader: a bed missing `bus`
	# is caught; a complete one passes.
	var bad_bed := {"id": "b", "file": "x.wav"}  # no bus
	_check(Records.validate_kind(Ambience.AMBIENCE_KIND, bad_bed) != "",
		"ambience: the desk catches a bed missing a required field")
	var good_bed := {"id": "b", "file": "x.wav", "bus": "Ambience"}
	_check(Records.validate_kind(Ambience.AMBIENCE_KIND, good_bed) == "",
		"ambience: a complete bed record validates")

	# -- crossfade math (pure) --
	# nightness_for: the window's dusk ramp rises, the dawn ramp recedes.
	var win := {"in": [19.0, 21.5], "out": [5.0, 7.0]}
	_check(Ambience.nightness_for(win, 3.0) == 1.0, "ambience: deep night is full nightness")
	_check(Ambience.nightness_for(win, 12.0) == 0.0, "ambience: noon is zero nightness")
	_check(Ambience.nightness_for(null, 3.0) == 0.0,
		"ambience: no solar window is pure day (neutral floor)")
	# crossfade_step: a linear ramp over crossfade_s; 0 snaps.
	_check(is_equal_approx(Ambience.crossfade_step(0.0, 1.0, 4.0, 1.0), 0.25),
		"ambience: crossfade eases 1/4 of the way in one second over 4s")
	_check(Ambience.crossfade_step(0.0, 1.0, 4.0, 10.0) == 1.0,
		"ambience: crossfade reaches the target and stops")
	_check(Ambience.crossfade_step(0.3, 1.0, 0.0, 0.016) == 1.0,
		"ambience: crossfade_s 0 snaps to target")

	# -- the migration A/B: bed_linear reproduces the OLD hardcoded formula
	# term-for-term, at a grid of (hour, wind, storminess, interior) inputs.
	# This is "same params out" proven numerically — the shipped records
	# are the old code, as data.
	var wind_rec: Variant = Records.load_json(Ambience.AMBIENCE_DIR + "/wind_bed.json")
	var night_rec: Variant = Records.load_json(Ambience.AMBIENCE_DIR + "/night_bed.json")
	if have_beds:
		_check(wind_rec is Dictionary and night_rec is Dictionary,
			"ambience: the two shipped beds parse")
	if wind_rec is Dictionary and night_rec is Dictionary:
		var mismatch := 0
		for h in [0.0, 3.0, 5.5, 7.0, 12.0, 18.0, 20.0, 21.5, 23.0]:
			for w in [0.0, 0.4, 1.0]:
				for st in [0.0, 0.5, 1.0]:
					for duck in [1.0, 0.08]:
						var n := Ambience.nightness_for(wind_rec["solar_window"], h)
						var got_w := Ambience.bed_linear(wind_rec, n, w, st, duck)
						var got_n := Ambience.bed_linear(night_rec, n, w, st, duck)
						if got_w != _ref_wind(h, w, duck) or got_n != _ref_night(h, st, duck):
							mismatch += 1
		_check(mismatch == 0,
			"ambience: shipped beds match the old wind/night curves byte-for-byte (%d off)"
				% mismatch)

	# -- end-to-end: drive the REAL evaluator one frame and prove each
	# loaded bed's live player volume is the old curve's value at the live
	# clock/weather (the full path: record -> _process -> volume_db). No
	# player node in the test tree, so biome is "" and the universal beds
	# stay fully present; nothing is inside, so no duck.
	var was_inside2: bool = Interiors.inside
	Interiors.inside = false
	amb._process(0.016)
	var h: float = GameClock.solar_hours()
	var loaded: Array = amb.get("_beds")
	if have_beds:
		_check(loaded.size() == 3, "ambience: all three shipped beds loaded live (got %d)" % loaded.size())
	for bed: Dictionary in loaded:
		var id := String(bed.rec["id"])
		var want := 0.0
		if id == "wind_bed":
			want = linear_to_db(clampf(_ref_wind(h, Weather.wind, 1.0), 0.0001, 1.0))
		elif id == "night_bed":
			want = linear_to_db(clampf(_ref_night(h, Weather.storminess, 1.0), 0.0001, 1.0))
		else:
			# shore_lap (W10a): biomes ["strand"] never matches the empty
			# no-player biome this test drives, so presence stays 0 and the
			# bed is silent — proves a biome-keyed bed off its biome is inaudible.
			want = linear_to_db(clampf(0.0001, 0.0001, 1.0))
		_check(is_equal_approx(bed.player.volume_db, want),
			"ambience: %s live volume matches the old curve (%.4f vs %.4f)"
				% [id, bed.player.volume_db, want])
	Interiors.inside = was_inside2

	# -- the mix.json interior duck drives the duck token (3b). Force the
	# interior predicate and read Audio's live duck state, then restore.
	var was_inside: bool = Interiors.inside
	Interiors.inside = false
	_check(is_equal_approx(Audio.bus_duck("Ambience"), 1.0) and Audio.active_ducks() == "-",
		"ambience: no duck when outside (bus_duck 1.0, token '-')")
	Interiors.inside = true
	# The interior duck rule lives in data/audio/mix.json (content). No mix,
	# no rule — the bus stays open (the outside case above already proved the
	# neutral 1.0/'-'); SKIP the ducked assertion on a content-empty tree.
	if FileAccess.file_exists("res://data/audio/mix.json"):
		_check(is_equal_approx(Audio.bus_duck("Ambience"), 0.08),
			"ambience: interior ducks the Ambience bus to 0.08 (got %f)"
				% Audio.bus_duck("Ambience"))
		_check(Audio.active_ducks() == "interior_hush",
			"ambience: the duck token names the active rule (got %s)" % Audio.active_ducks())
	else:
		print("  ambience: SKIP interior-duck (no data/audio/mix.json — content-empty tree)")
	Interiors.inside = was_inside
	amb.queue_free()  # leave no bed players behind


## W10a: the positional water beds. WaterAudio owns two rows the desk
## validates identically to audio_ambience (schema + registered nested
## dir + reloader), plants one AudioStreamPlayer3D per river reach and
## per fall site, and drives their gain from Hydrology.flow_norm/drop —
## pure functions, asserted numerically, the same idiom as bed_linear.
func _test_water_audio() -> void:
	var wa := WaterAudio.new()
	add_child(wa)
	# _ready (just ran via add_child) registers the desk kind and defers the
	# first _rebuild; force it now so the emitters exist for this frame's
	# assertions (mirrors the .call_deferred() in _ready).
	wa._rebuild()

	_check(not Records.schema_for(WaterAudio.WATER_AUDIO_KIND).is_empty(),
		"water_audio: audio_water_emitter schema registered for the desk")
	_check(Records.dir_for(WaterAudio.WATER_AUDIO_KIND) == WaterAudio.WATER_AUDIO_DIR,
		"water_audio: reload counts the registered data/audio/water dir")
	# The emitter rows are CONTENT (data/audio_water — valley ships two); a
	# content-empty tree has none, so the desk wiring above always asserts but
	# the shipped-row tally SKIPs honestly (the emitter checks below already
	# SKIP on an empty-river world).
	if Records.count_dir(WaterAudio.WATER_AUDIO_KIND) > 0:
		_check(Records.count_dir(WaterAudio.WATER_AUDIO_KIND) == 2,
			"water_audio: count_dir tallies the two shipped rows (got %d)"
				% Records.count_dir(WaterAudio.WATER_AUDIO_KIND))
	else:
		print("  water_audio: SKIP shipped-row check (no audio_water content — content-empty tree)")

	if Terrain.rivers.is_empty():
		_check(true, "water_audio: content-empty world (no rivers) — skipped emitter checks")
	else:
		var river_emitters: Array = wa.get("_river_emitters")
		_check(river_emitters.size() == Terrain.rivers.size(),
			"water_audio: one river-reach emitter per river (got %d for %d rivers)"
				% [river_emitters.size(), Terrain.rivers.size()])
		var fall_count := 0
		for r in Terrain.rivers:
			fall_count += (r.get("falls", []) as Array).size()
		var falls_emitters: Array = wa.get("_falls_emitters")
		_check(falls_emitters.size() == fall_count,
			"water_audio: one roar emitter per fall site (got %d for %d falls)"
				% [falls_emitters.size(), fall_count])
	wa.queue_free()

	# -- pure gain math --
	var river_rec := {"gain_ref": 0.22}
	_check(is_equal_approx(WaterAudio.river_gain(river_rec, 0.5), 0.11),
		"water_audio: river_gain scales linearly with flow_norm")
	_check(WaterAudio.river_gain(river_rec, 0.0) == 0.0,
		"water_audio: an idle river (flow_norm 0) is silent")
	_check(WaterAudio.river_gain(river_rec, -1.0) == 0.0,
		"water_audio: a negative flow_norm never goes negative-gain")

	var falls_rec := {"gain_ref": 0.55, "drop_ref": 12.0}
	_check(is_equal_approx(WaterAudio.falls_gain(falls_rec, 1.0, 12.0), 0.55),
		"water_audio: a full-drop fall at full flow hits gain_ref exactly")
	_check(is_equal_approx(WaterAudio.falls_gain(falls_rec, 1.0, 6.0), 0.275),
		"water_audio: half the reference drop halves the roar")
	_check(WaterAudio.falls_gain(falls_rec, 1.0, 24.0) == WaterAudio.falls_gain(falls_rec, 1.0, 12.0),
		"water_audio: drop clamps at drop_ref — no louder-than-full roar")
	_check(WaterAudio.falls_gain(falls_rec, 0.0, 12.0) == 0.0,
		"water_audio: a full-drop fall on a dry river is silent")


## The OLD hardcoded ambience curves (ambience.gd before A2), kept here as
## the reference the record-driven beds must reproduce bit-for-bit.
func _ref_nightness(h: float) -> float:
	return clampf(smoothstep(19.0, 21.5, h) + 1.0 - smoothstep(5.0, 7.0, h), 0.0, 1.0)


func _ref_wind(h: float, wind: float, duck: float) -> float:
	return lerpf(0.5, 0.18, _ref_nightness(h)) * (0.35 + 1.1 * wind) * duck


func _ref_night(h: float, storminess: float, duck: float) -> float:
	return _ref_nightness(h) * 0.16 * (1.0 - storminess * 0.7) * duck


## StrataLink (ONE_APP P3): the live-link verbs answer over a real local
## socket — ping round-trips, teleport without a player errs honestly,
## unknown verbs never hang the hub. Skips when the link isn't listening
## (release build or the port taken by a running game).
func _test_strata_link() -> void:
	if not StrataLink.summary().begins_with("listening"):
		print("  strata link: SKIP (not listening — port busy or release build)")
		return
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", StrataLink.port) != OK:
		_check(false, "link connect")
		return
	for i in 100:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await get_tree().process_frame
	_check(peer.get_status() == StreamPeerTCP.STATUS_CONNECTED, "link connects")
	var replies := await _link_send(peer, ["ping", "bogus_verb", "teleport 1 2", "status"])
	_check(replies.size() == 4, "one reply per command (got %d)" % replies.size())
	if replies.size() == 4:
		_check(replies[0].begins_with("ok pong"), "ping -> pong")
		_check(replies[1].begins_with("err"), "unknown verb errs, never hangs")
		# No player node in the test scene: the honest error path.
		_check(replies[2] == "err no player in tree", "teleport without player errs")
		_check(replies[3].begins_with("ok") and "focus=" in replies[3], "status reports focus")
	# The time verb (ONE_APP P8): +<h> advances THROUGH advance_hours (the
	# sim lives the stretch), the reply carries the new clock; bad args err
	# with the contract line the Strata client matches on.
	var h0 := fmod(GameClock.hours + 2.0, 24.0)
	var treplies := await _link_send(peer, ["time +2", "time", "time 25", "time -3"])
	_check(treplies.size() == 4, "time replies land (got %d)" % treplies.size())
	if treplies.size() == 4:
		var rep: String = treplies[0]
		_check(rep.begins_with("ok ") and rep.contains("h day="), "time +2 reply shape")
		var rep_h := float(rep.trim_prefix("ok ").split("h")[0])
		_check(absf(rep_h - GameClock.hours) < 0.05, "time reply carries the new clock")
		_check(absf(fposmod(GameClock.hours - h0, 24.0)) < 0.05
			or absf(fposmod(GameClock.hours - h0, 24.0) - 24.0) < 0.05,
			"time +2 advanced the clock ~2h (at %.2f, wanted %.2f)" % [GameClock.hours, h0])
		for i in [1, 2, 3]:
			_check(treplies[i] == "err time needs +<h> or <0..24>",
				"time arg %d errs with the contract line" % i)
	# The absolute form: travel FORWARD to a clock hour (here: now+1h,
	# so it stays a same-day hop and never crosses midnight mid-assert).
	var target := snappedf(fmod(GameClock.hours + 1.0, 24.0), 0.01)
	var areplies := await _link_send(peer, ["time %.2f" % target])
	_check(areplies.size() == 1 and areplies[0].begins_with("ok "),
		"time <hour> answers ok")
	_check(absf(GameClock.hours - target) < 0.05,
		"time <hour> lands on the hour (at %.2f, wanted %.2f)" % [GameClock.hours, target])
	# The view verb (P8 viewer): toolkit isn't active in the test scene,
	# so the honest error answers; bad args err with the contract line.
	var vreplies := await _link_send(peer, ["view orbit", "view bogus"])
	_check(vreplies.size() == 2, "view replies land (got %d)" % vreplies.size())
	if vreplies.size() == 2:
		_check(vreplies[0] == "err toolkit not active", "view orbit errs without toolkit")
		_check(vreplies[1] == "err view needs orbit|fly", "view arg errs with the contract line")
	await _test_link_discovery(peer)
	await _test_state_verb(peer)
	await _test_reload_honesty(peer)
	await _test_reload_adopt(peer)
	await _test_far_terrain_reload()
	_test_water_field_reseats_on_bless()
	await _test_preview_world(peer)
	await _test_preview_mesh(peer)
	await _test_preview_scatter(peer)
	await _test_preview_water(peer)
	await _test_living_preview(peer)
	await _test_camera_verb(peer)
	await _test_toolkit_verbs(peer)
	await _test_toolkit_power(peer)
	await _test_panel_verb(peer)
	await _test_inspect_notices(peer)
	await _test_pulse(peer)
	await _test_boot_phase(peer)
	await _test_pane_health(peer)
	await _test_records_desk(peer)
	await _test_names_verbs(peer)
	await _test_marker_verbs(peer)
	await _test_vernier_verb(peer)
	await _test_audio_verbs(peer)
	peer.disconnect_from_host()


## Discovery verbs (audit QW7): `verbs` answers every verb the link
## speaks — pinned BOTH WAYS against the dispatcher's own match arms
## (parsed from source), so a new verb cannot ship unlisted and the list
## cannot advertise a verb nobody answers. `toolkit keys` answers the
## hand's bindings with or without the hand, every token machine-readable.
func _test_link_discovery(peer: StreamPeerTCP) -> void:
	var replies := await _link_send(peer, ["verbs", "toolkit keys"])
	_check(replies.size() == 2, "discovery replies land (got %d)" % replies.size())
	if replies.size() != 2:
		return
	# -- verbs: shape, then completeness against the dispatcher source.
	var vr := String(replies[0])
	_check(vr.begins_with("ok verbs "), "verbs answers ok (got %s)" % vr)
	var listed := vr.trim_prefix("ok verbs ").split(" ", false)
	var src := FileAccess.get_file_as_string("res://game/dev/strata_link.gd")
	var body := src.substr(src.find("func _execute"))
	body = body.substr(0, body.find("\nfunc ", 1))
	var arms: Array[String] = []
	var re := RegEx.create_from_string("(?m)^\\t\\t\"([a-z_]+)\":")
	for m in re.search_all(body):
		arms.append(m.get_string(1))
	_check(arms.size() >= 12, "dispatcher arms found in source (got %d)" % arms.size())
	for a in arms:
		_check(a in listed, "verbs reply lists the dispatcher's '%s' (rot check)" % a)
	for v in listed:
		_check(v in arms, "advertised verb '%s' exists in the dispatcher" % v)
	# Every advertised verb ANSWERS over the wire (bare verbs may err on
	# missing args, but never "unknown verb" — list and dispatcher agree
	# live, not just in source).
	var live := await _link_send(peer, Array(listed))
	_check(live.size() == listed.size(),
		"every advertised verb answers (got %d/%d)" % [live.size(), listed.size()])
	for i in mini(live.size(), listed.size()):
		_check(not String(live[i]).begins_with("err unknown verb"),
			"advertised verb '%s' is spoken (got %s)" % [listed[i], live[i]])
	# -- toolkit keys: answers WITHOUT the hand (static help, not state);
	# every token one <binding>=<meaning> pair; the load-bearing bindings
	# ride the live InputMap (F1 here == the InputMap's toolkit_toggle).
	_check(not Toolkit.active, "keys probe runs without the hand")
	var kr := String(replies[1])
	_check(kr.begins_with("ok keys "), "toolkit keys answers ok (got %s)" % kr)
	var toks := kr.trim_prefix("ok keys ").split(" ", false)
	_check(toks.size() >= 15, "keys reply carries the bindings (got %d)" % toks.size())
	for t in toks:
		_check(t.count("=") == 1 and t.split("=", false).size() == 2,
			"keys token is <binding>=<meaning> (got '%s')" % t)
	for want in ["F1=toolkit", "Tab=tool", "Z=undo", "F5=save",
			"BracketLeft=smaller", "BracketRight=bigger", "1-9=pick",
			"O=panel", "M=map", "WASD=fly", "Escape=release"]:
		_check(want in toks, "keys reply carries %s" % want)


## reload_world honesty (audit QW3): a failed tile re-read answers err —
## never "ok reloaded" over a world that didn't change — and the old
## tile stays live. The failure is real: the exr is hidden on disk, the
## verb sent, the file restored, recovery asserted.
func _test_reload_honesty(peer: StreamPeerTCP) -> void:
	if not Terrain.has_world_tile():
		print("  reload honesty: SKIP (no baked tile cache)")
		return
	var h0: float = Terrain.height(3000.0, 3000.0)
	var healthy := await _link_send(peer, ["reload_world"])
	_check(healthy.size() == 1 and String(healthy[0]) == "ok reloaded tile=yes biomes",
		"reload_world with a healthy tile answers ok (got %s)" % str(healthy))
	var tile_abs := ProjectSettings.globalize_path(
		"res://data/terrain/tiles/baked_world.exr")
	var hidden := tile_abs + ".qw3hidden"
	_check(DirAccess.rename_absolute(tile_abs, hidden) == OK, "probe hides the tile")
	var broken := await _link_send(peer, ["reload_world"])
	_check(broken.size() == 1
			and String(broken[0]) == "err reload failed: tile did not reload (old tile stays live)",
		"reload_world with an unreadable tile answers err (got %s)" % str(broken))
	_check(Terrain.height(3000.0, 3000.0) == h0,
		"the old tile stays live after a failed reload")
	_check(DirAccess.rename_absolute(hidden, tile_abs) == OK, "probe restores the tile")
	var back := await _link_send(peer, ["reload_world"])
	_check(back.size() == 1 and String(back[0]) == "ok reloaded tile=yes biomes",
		"reload_world recovers once the tile returns (got %s)" % str(back))
	_check(Terrain.height(3000.0, 3000.0) == h0,
		"recovered reload reads bit-identical ground")


## In-session bless ADOPTS a tile the pane booted without (strata ONE_APP,
## 2026-07-09 — the empty-scene-after-bless fix). The shaping viewer boots
## content-empty (no tile record on disk yet, sea=-1e12); the bless writes
## the tile + record + sea.json, then the app drives `reload_world`. Before
## the fix reload_world only REFRESHED a tile already in _tiles, so it
## answered "no-tile" over the freshly-written world and the scene stayed
## empty until a relaunch. This simulates that boot state (drop the live
## tile + sea the way a content-empty viewer holds them, with the record
## still on disk as the importer just wrote it) and asserts one reload_world
## makes the world TILE-backed with a real sea level — no relaunch.
func _test_reload_adopt(peer: StreamPeerTCP) -> void:
	if not Terrain.has_world_tile():
		print("  reload adopt: SKIP (no baked tile cache)")
		return
	var full_size: float = Terrain.world_tile_size()
	var real_sea: float = Terrain.sea_level
	_check(full_size > 1000.0 and real_sea > -1e11,
		"a baked world starts tile-backed with a real sea (%.0fm, sea=%.1fm)" % [full_size, real_sea])
	# Mimic the content-empty viewer boot: no tile loaded, sea unset. The
	# tile record + sea.json remain on disk (the importer wrote them).
	var stash := Terrain._tiles.duplicate()
	Terrain._tiles = []
	if Terrain.kernel:
		Terrain.kernel.set_tiles(Terrain._tiles)
	Terrain.sea_level = -1e12
	_check(not Terrain.has_world_tile(),
		"content-empty boot: no world tile before the bless reload")
	# The exact verb the in-session bless drives — adopt, don't just refresh.
	var reply := await _link_send(peer, ["reload_world"])
	_check(reply.size() == 1 and String(reply[0]) == "ok reloaded tile=yes biomes",
		"reload_world ADOPTS the freshly-blessed tile (got %s)" % str(reply))
	_check(Terrain.has_world_tile(),
		"the world is tile-backed after one reload_world (no relaunch)")
	_check(absf(Terrain.world_tile_size() - full_size) < 0.5,
		"the adopted tile carries the full world frame (%.0fm)" % Terrain.world_tile_size())
	_check(Terrain.sea_level > -1e11,
		"the imported sea level is live after adopt (sea=%.1fm, not -1e12)" % Terrain.sea_level)
	# Leave the world as the suite found it (a real tile), so later tests
	# that lean on has_world_tile() are unaffected.
	if not stash.is_empty() and Terrain._tiles.is_empty():
		Terrain._tiles = stash
		if Terrain.kernel:
			Terrain.kernel.set_tiles(Terrain._tiles)


## Mission Y3: the map's far-terrain quadtree must pick up an in-session
## bless — the reported bug was "press M, the ground still reads the
## pre-bless surface." far_terrain.gd already listens for Terrain.edited
## and rebuilds any leaf whose rect the edit touches (debounced
## EDIT_REBUILD_DELAY=1.2s so a burst of edits coalesces into one rebuild);
## reload_world's whole-frame edited emit is exactly the "everything just
## changed" case that debounce is FOR. This pins it end to end: a real
## FarTerrain node, focused where a real reload_world adopt call (the exact
## in-session-bless verb) lands a tile with a drastically different height,
## must show the NEW height in its cached leaf mesh within a few seconds —
## never the frozen pre-bless one.
func _test_far_terrain_reload() -> void:
	if not Terrain.has_world_tile():
		print("  far_terrain reload: SKIP (no baked tile cache)")
		return
	# Mimic the content-empty boot (same stash pattern as _test_reload_adopt):
	# the far-terrain leaf we build first must read the PROCEDURAL ground
	# (no tile), so the post-bless height change is unmistakable.
	var stash: Array = Terrain._tiles.duplicate()
	var stash_sea: float = Terrain.sea_level
	Terrain._tiles = []
	if Terrain.kernel:
		Terrain.kernel.set_tiles(Terrain._tiles)
	Terrain.sea_level = -1e12

	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(512.0, 0.0, 512.0)
	var far := Node3D.new()
	far.set_script(load("res://game/world/far_terrain.gd"))
	add_child(far)

	const KEY := "1024_0_0"  # the MIN_TILE leaf covering (0,0)-(1024,1024)
	const VERT_IDX := 16 * 33 + 16  # tile-center vertex (local 512,512)
	var settled := false
	for i in 240:
		await get_tree().process_frame
		if far._cache.has(KEY):
			settled = true
			break
	_check(settled, "far_terrain builds the pre-bless (procedural) leaf")
	if not settled:
		player.queue_free()
		far.queue_free()
		if not stash.is_empty():
			Terrain._tiles = stash
			Terrain.sea_level = stash_sea
			if Terrain.kernel:
				Terrain.kernel.set_tiles(Terrain._tiles)
		return
	var mesh0: ArrayMesh = far._cache[KEY].mesh
	var y0: float = (mesh0.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			as PackedVector3Array)[VERT_IDX].y

	# The exact in-session-bless verb: re-read the tile record + heightmap
	# still on disk (untouched — only the in-memory _tiles was dropped).
	var reply: String = Terrain.reload_world()
	_check(reply == "reloaded", "reload_world adopts the tile (got %s)" % reply)

	var rebuilt := false
	var elapsed := 0.0
	while elapsed < 5.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var mi: MeshInstance3D = far._cache.get(KEY)
		if mi == null or mi.mesh == mesh0:
			continue
		var y1: float = (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				as PackedVector3Array)[VERT_IDX].y
		if absf(y1 - y0) > 1.0:
			rebuilt = true
			break
	_check(rebuilt,
		"far_terrain's cached leaf reflects the bless within 5s (not the pre-bless surface)")

	player.queue_free()
	far.queue_free()
	if not stash.is_empty():
		Terrain._tiles = stash
		Terrain.sea_level = stash_sea
		if Terrain.kernel:
			Terrain.kernel.set_tiles(Terrain._tiles)


## The tier-2 water field reseats on an in-session bless (E1a, the post-bless
## DOUBLE WATER fix). The WaterSheet rides WaterField's baked terrain base +
## live depth, but that base otherwise rebakes only on a ~384m focus DRIFT — so
## a bless (reload_world) that swaps the ground leaves the sheet riding the
## PRE-bless heights: a flat sheet floating above the new shoreline, a second
## lake over the real one. The fix wires Terrain.water_reloaded → WaterField so
## the adopt forces a base rebake (and clears the stale pooled depth on the live
## path). The GPU field is off headless, so this gate can't render the sheet;
## it pins the WIRING + the recorded rebake intent, which is exactly what a
## regression (dropping the connection) would break. Before the fix the signal
## had no WaterField listener and _force_bake stayed false — this FAILS.
func _test_water_field_reseats_on_bless() -> void:
	_check(Terrain.water_reloaded.is_connected(WaterField._on_water_reloaded),
		"WaterField listens for water_reloaded (the bless-reseat wiring)")
	# The adopt records a base-rebake intent in every posture (headless it is an
	# inert, never-fingerprinted flag; _process consumes it on the next live
	# frame). Drive the exact signal a bless emits and assert the intent lands.
	WaterField._force_bake = false
	Terrain.water_reloaded.emit()
	_check(WaterField._force_bake,
		"a water reload forces a WaterField base rebake (no stale floating sheet)")


## The toolkit verbs (ONE_APP P9·C): Strata's native toolbar drives the
## in-game hand over the link. Status mirrors the REAL Toolkit state,
## the setters route through it (tool/brush/biome/place — never a
## parallel store), hud darkens the overlays, and without the hand every
## subverb errs honestly. A disposable player body lets the Toolkit
## enter headless — the same shape the --toolkit posture boots into.
func _test_toolkit_verbs(peer: StreamPeerTCP) -> void:
	# No hand yet (the play posture / title screen): the honest error.
	var replies := await _link_send(peer, ["toolkit status", "toolkit tool sculpt"])
	_check(replies.size() == 2, "toolkit replies land (got %d)" % replies.size())
	for r in replies:
		_check(r == "err toolkit not active", "toolkit errs without the hand")
	# Give the Toolkit its hand: a disposable player, then enter.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	_check(Toolkit.active, "toolkit enters over the test player")
	replies = await _link_send(peer, [
		"toolkit status",       # 0: the boot state
		"toolkit tool biome",   # 1
		"toolkit brush 300",    # 2: biome rides the macro brush (24..1200)
		"toolkit biome 3",      # 3
		"toolkit tool sculpt",  # 4
		"toolkit brush 22.5",   # 5: sculpt brush
		"toolkit brush 9999",   # 6: clamped to the keyboard range
		"toolkit status",       # 7: mirrors everything set above
		"toolkit tool bogus",   # 8
		"toolkit brush nope",   # 9
		"toolkit biome 0",      # 10
		"toolkit bogus",        # 11
		"hud off",              # 12
		"hud sideways",         # 13
	])
	_check(replies.size() == 14, "toolkit verb replies land (got %d)" % replies.size())
	if replies.size() == 14:
		_check(replies[0].begins_with("ok tool=sculpt view=fly brush=12.0m biome=5:")
			and " hud=on " in replies[0],
			"toolkit status reports the boot state (got %s)" % replies[0])
		# The chrome's picker names (contract v2): status carries every
		# macro-terrain name from the PROFILE's table (1-9 key order,
		# data-driven — Strata renders real pickers, never "1..9"), the
		# PLACE categories, and the river pen's pending point count.
		_check(" biomes=" in replies[0] and " cats=" in replies[0]
			and replies[0].ends_with(" river=0"),
			"status carries the chrome fields (got %s)" % replies[0])
		var bfield := String(replies[0]).split(" biomes=")[1].split(" ")[0]
		var bnames := bfield.split(",", false)
		_check(bnames.size() == Terrain.biomes.size(),
			"status biomes lists every profile name (got %d of %d)"
				% [bnames.size(), Terrain.biomes.size()])
		if not bnames.is_empty() and not Terrain.biomes.is_empty():
			_check(bnames[0] == String(Terrain.biomes[0].id).replace(" ", "_"),
				"status biomes ride the profile's own ids (got %s)" % bnames[0])
		_check(replies[1] == "ok tool biome", "toolkit tool switches")
		_check(replies[2] == "ok brush 300.0m", "biome brush is the macro brush")
		_check(replies[3].begins_with("ok biome 3:"), "toolkit biome picks")
		_check(replies[4] == "ok tool sculpt", "toolkit tool switches back")
		_check(replies[5] == "ok brush 22.5m", "sculpt brush sets in meters")
		_check(replies[6] == "ok brush 64.0m", "brush clamps to the keyboard range")
		_check(replies[7].begins_with("ok tool=sculpt view=fly brush=64.0m biome=3:"),
			"toolkit status mirrors the link's own writes (got %s)" % replies[7])
		_check(replies[8] == "err toolkit tool needs sculpt|place|terrain|biome|river",
			"unknown tool errs with the contract line")
		_check(replies[9] == "err toolkit brush needs meters > 0",
			"bad brush errs with the contract line")
		_check(replies[10].begins_with("err toolkit biome needs 1.."),
			"biome 0 errs with the contract line")
		_check(replies[11] == "err toolkit needs status|tool|brush|biome|place|snap|select|move|duplicate|keys|on|off|undo",
			"unknown subverb errs with the contract line")
		# hud off is the batch's LAST state change: the darkness is
		# assertable here (hud on rides its own batch below).
		_check(replies[12] == "ok hud off" and not HUD.visible
			and not Toolkit._hud.visible, "hud off darkens both overlays")
		_check(replies[13] == "err hud needs on|off", "bad hud arg errs")
	var hreplies := await _link_send(peer, ["hud on"])
	_check(hreplies.size() == 1 and hreplies[0] == "ok hud on" and HUD.visible
		and Toolkit._hud.visible, "hud on relights both overlays")
	# One Z over the wire (undo v2): the shared stack the key drives. Empty
	# here (cleared) — the honest "nothing" no-op, never a cross-tool delete.
	ToolkitHistory.clear()
	var ureplies := await _link_send(peer, ["toolkit undo"])
	_check(ureplies.size() == 1 and ureplies[0] == "ok undo nothing",
		"toolkit undo answers 'nothing' on an empty stack (got %s)" % str(ureplies))
	# The place slot rides the Cards palette (skip empty: fresh clone
	# without the placeholder drop still has the tracked cards, but honest).
	var count := int(Toolkit.link_state()["place_count"])
	if count > 0:
		var pre := await _link_send(peer,
			["toolkit place 1", "toolkit place 0", "toolkit place no_such/slot"])
		_check(pre.size() == 3, "place replies land (got %d)" % pre.size())
		if pre.size() == 3:
			_check(pre[0].begins_with("ok place 1/%d:" % count),
				"place by index answers the landed slot (got %s)" % pre[0])
			_check(pre[1].begins_with("err no such place slot"), "place 0 errs")
			_check(pre[2].begins_with("err no such place slot"), "unknown slot errs")
			# Round-trip by NAME: select the slot status just reported.
			var slot := String(Toolkit.link_state()["place_slot"])
			var by_name := await _link_send(peer, ["toolkit place " + slot])
			_check(by_name.size() == 1 and by_name[0] == "ok place 1/%d:%s" % [count, slot],
				"place by slot name round-trips (got %s)" % str(by_name))
	else:
		print("  toolkit place: SKIP (no cards in this checkout)")
	# Teardown by hand (Toolkit._exit wants the real player rig): restore
	# the defaults the keyboard expects, release the hand, drop the player.
	Toolkit.set_tool("sculpt")
	Toolkit.set_brush_m(12.0)
	Toolkit.set_biome(5)
	Toolkit.active = false
	Toolkit.set_hud_visible(true)  # hud_on stays true; overlay dark (inactive)
	# Leave the group NOW — queue_free is deferred, and the power probe
	# next door must not find this ghost when it asserts "no player".
	player.remove_from_group("player")
	player.queue_free()


## toolkit on|off (chrome contract v2): F1 over the wire. Off without
## the hand is already the asked-for state (ok, idempotent); on without
## a player errs honestly; with a full player rig the round trip enters
## and exits the REAL paths — physics frozen and returned, and the exit
## saves ride the same F5 writes (guarded so the checkout stays clean).
func _test_toolkit_power(peer: StreamPeerTCP) -> void:
	_check(not Toolkit.active, "power probe starts without the hand")
	var pre := await _link_send(peer, ["toolkit off", "toolkit on"])
	_check(pre.size() == 2, "power replies land (got %d)" % pre.size())
	if pre.size() == 2:
		_check(pre[0] == "ok toolkit off", "off without the hand is idempotent")
		_check(pre[1] == "err no player in tree", "on without a player errs honestly")
	# Guard: _exit persists through the F5 path — the edit layer is
	# written unconditionally and Overrides.emit can mint the artifact
	# into a pristine checkout; snapshot everything it may touch (absent
	# files as null) and put it all back (the _test_overrides_emit pattern).
	var guard_paths := [Terrain.EDIT_PATH, Overrides.FILE,
		Overrides.DIR + "/terrain_pen_override.f32z",
		Overrides.DIR + "/terrain_sculpt.f32z"]
	var guard: Dictionary = {}
	for gp: String in guard_paths:
		guard[gp] = FileAccess.get_file_as_bytes(gp) \
				if FileAccess.file_exists(gp) else null
	# The full player rig (the _test_map shape): _exit re-seats this.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var cam_rig := Node3D.new()
	cam_rig.name = "CameraRig"
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var pcam := Camera3D.new()
	pcam.name = "Camera3D"
	arm.add_child(pcam)
	cam_rig.add_child(arm)
	player.add_child(cam_rig)
	add_child(player)
	var on := await _link_send(peer, ["toolkit on", "toolkit on"])
	_check(on.size() == 2, "on replies land (got %d)" % on.size())
	if on.size() == 2:
		_check(on[0] == "ok toolkit on" and Toolkit.active,
			"toolkit on enters the hand (got %s)" % on[0])
		_check(on[1] == "ok toolkit on", "on is idempotent")
	_check(not player.is_physics_processing(), "the hand freezes the player")
	var off := await _link_send(peer, ["toolkit off"])
	_check(off.size() == 1 and off[0] == "ok toolkit off" and not Toolkit.active,
		"toolkit off returns the player (got %s)" % str(off))
	_check(player.is_physics_processing(), "exit unfreezes the player")
	_check(pcam.current, "exit hands the view back to the player camera")
	# Leave no trace: restore every guarded file _exit's saves touched —
	# bytes back where they were, absent files absent again (and the
	# artifact dir gone if the emit minted it).
	for gp: String in guard_paths:
		var was: Variant = guard[gp]
		if was == null:
			if FileAccess.file_exists(gp):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(gp))
		else:
			var f := FileAccess.open(gp, FileAccess.WRITE)
			f.store_buffer(was)
			f.close()
	var ov_dir := ProjectSettings.globalize_path(Overrides.DIR)
	if guard[Overrides.FILE] == null and DirAccess.dir_exists_absolute(ov_dir) \
			and DirAccess.get_files_at(ov_dir).is_empty():
		DirAccess.remove_absolute(ov_dir)
	Overrides.pending = false
	Overrides._layer_cache.clear()
	player.remove_from_group("player")
	player.queue_free()


## The panel verb (chrome contract v2): the O world panel, machine-
## readable — TAB-separated NAME=text sections, names uppercase, one per
## overlay row, straight from the ONE builder both renderers share.
## Answers in every posture (data, not hand state).
func _test_panel_verb(peer: StreamPeerTCP) -> void:
	var replies := await _link_send(peer, ["panel"])
	_check(replies.size() == 1 and String(replies[0]).begins_with("ok panel HERE="),
		"panel answers ok, HERE first (got %s)" % str(replies))
	if replies.size() != 1:
		return
	var toks := String(replies[0]).trim_prefix("ok panel ").split("\t")
	var secs: Array = Toolkit.panel_sections()
	_check(toks.size() == secs.size(),
		"panel carries every overlay section (got %d of %d)"
			% [toks.size(), secs.size()])
	for i in mini(toks.size(), secs.size()):
		var t := String(toks[i])
		_check("=" in t, "panel section is NAME=text (got '%s')" % t.substr(0, 40))
		var name := t.split("=")[0]
		_check(name == secs[i][0],
			"panel section %d matches the overlay's (%s vs %s)" % [i, name, secs[i][0]])
		_check(name == name.to_upper(), "panel names are uppercase (got %s)" % name)
	for want in ["HERE", "AIR", "CLIMATE", "WATER", "FLORA", "SPRING", "SAND",
			"WAYS", "LAND", "FABRIC", "CARDS", "DOORS", "STORY", "LINK"]:
		_check(("\t%s=" % want) in replies[0] or replies[0].begins_with("ok panel %s=" % want),
			"panel carries the %s section" % want)


## inspect + notices + the TOTAL hud gate (chrome contract v2): RMB's
## sim-inspector and the SEL line answer over the link; with the chrome
## driving (`hud off`) NO text UI survives in view and HUD.notify routes
## to the `notices` drain instead of a dark label.
func _test_inspect_notices(peer: StreamPeerTCP) -> void:
	# Without the hand: the honest err; the drain answers (and clears).
	var pre := await _link_send(peer, ["inspect", "notices", "notices"])
	_check(pre.size() == 3, "inspect/notices replies land (got %d)" % pre.size())
	if pre.size() == 3:
		_check(pre[0] == "err toolkit not active", "inspect errs without the hand")
		_check(String(pre[1]).begins_with("ok notices "), "notices answers without the hand")
		_check(pre[2] == "ok notices 0", "a drained queue reads empty")
	# The hand, over a disposable player (the _test_toolkit_verbs shape).
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	_check(Toolkit.active, "toolkit enters for the inspect test")
	var bare := await _link_send(peer, ["inspect"])
	_check(bare.size() == 1 and bare[0] == "ok inspect sel=- agent=-",
		"inspect with nothing picked reads dashes (got %s)" % str(bare))
	# An agent with a mind to read: sim_debug flattens onto the line,
	# the node name loses its spaces (the reply stays token-parseable).
	var sc := GDScript.new()
	sc.source_code = "extends Node3D\nfunc sim_debug() -> String:\n\treturn \"mood hungry\\ngoal water hole\""
	sc.reload()
	var agent := Node3D.new()
	agent.set_script(sc)
	agent.name = "probe agent"
	add_child(agent)
	Toolkit._inspected = agent
	var got := await _link_send(peer, ["inspect"])
	_check(got.size() == 1
		and got[0] == "ok inspect sel=- agent=probe_agent text=mood hungry | goal water hole",
		"inspect reads the agent's mind, flattened (got %s)" % str(got))
	# The PLACE selection rides the same line (placement v2's sel state).
	var x := 909.0 * 128.0
	var z := 906.0 * 128.0
	var cell: Vector2i = CellRecords.cell_of(Vector3(x, 0.0, z))
	var rec: Dictionary = CellRecords.add(
		Vector3(x, Terrain.height(x, z), z), "res://kits/kit_probe.glb", TAU / 8.0, 1.5)
	Toolkit._tool = Toolkit.Tool.PLACE
	Toolkit._pick_at(Vector3(x, 0.0, z))
	_check(Toolkit._sel_id == String(rec["id"]), "the probe record is selected")
	got = await _link_send(peer, ["inspect"])
	if got.size() == 1 and " sel=" in got[0]:
		var sel := String(got[0]).split(" sel=")[1].split(" ")[0]
		var f := sel.split(":")
		_check(f.size() == 4 and f[0] == String(rec["id"]) and f[1] == "kit_probe"
			and f[2] == "45" and f[3] == "1.50",
			"inspect sel carries id:kit:yaw:scale (got %s)" % sel)
	else:
		_check(false, "inspect with a selection answers (got %s)" % str(got))
	# A freed agent reads as nothing again — validity, never a crash.
	Toolkit._inspected = null
	agent.free()
	# THE TOTAL GATE: hud off leaves NO text UI visible in the view —
	# the Toolkit lines (HUD, SEL, inspector, world panel) and every
	# gameplay label (prompt/say/notify/satchel) — and notify reroutes.
	var dark := await _link_send(peer, ["hud off"])
	_check(dark.size() == 1 and dark[0] == "ok hud off", "hud off lands")
	Toolkit._world_panel.visible = true  # even the O panel's own switch
	HUD.prompt("press E")                # even a prompt fired while dark
	for lbl: Array in [["toolkit hud", Toolkit._hud_label],
			["sim inspector", Toolkit._inspector],
			["world panel", Toolkit._world_panel],
			["prompt", HUD._prompt], ["say", HUD._line],
			["notice", HUD._notice], ["satchel", HUD._satchel]]:
		_check(not (lbl[1] as CanvasItem).is_visible_in_tree(),
			"hud off is TOTAL: %s stays dark" % lbl[0])
	HUD.notify("first notice")
	HUD.notify("second\tnotice")
	_check(not HUD._notice.is_visible_in_tree(), "a dark notify never lights the label")
	var drained := await _link_send(peer, ["notices", "notices"])
	_check(drained.size() == 2, "notice drains land (got %d)" % drained.size())
	if drained.size() == 2:
		_check(drained[0] == "ok notices 2\tfirst notice\tsecond notice",
			"notify routes to the drain, oldest first, tabs stripped (got %s)" % drained[0])
		_check(drained[1] == "ok notices 0", "the drain clears on read")
	# Relit: notify shows on screen again and stays OFF the drain.
	var lit := await _link_send(peer, ["hud on"])
	_check(lit.size() == 1 and lit[0] == "ok hud on", "hud on lands")
	HUD.notify("back on screen")
	_check(HUD._notice.visible, "a lit notify lights the label")
	var empty := await _link_send(peer, ["notices"])
	_check(empty.size() == 1 and empty[0] == "ok notices 0",
		"a lit notify never queues")
	# Leave no trace: record, cell file, labels, posture.
	HUD.prompt("")
	HUD._notice.visible = false
	Toolkit._deselect()
	ToolkitHistory.clear()
	CellRecords.remove(cell, String(rec["id"]))
	var cell_path := "%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]
	if FileAccess.file_exists(cell_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cell_path))
	Toolkit._world_panel.visible = false
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## The batched heartbeat (native-embed F2): `pulse` answers the WHOLE 2s
## mirror poll — toolkit status, panel, inspect, notices, status — in ONE
## reply instead of five. Each nested section must be the VERBATIM line its
## own verb gives (one truth, no drift), the sections framed by the record
## separator (0x1e). Also MEASURES the win: one pulse round-trip vs five
## separate sends, wall time printed for the ledger. Strata's GamePulse
## parser pins this grammar — change both or neither.
func _test_pulse(peer: StreamPeerTCP) -> void:
	var RS := char(30)  # ASCII record separator, the pulse section frame
	# The five verbs the heartbeat used to send, in the pulse's own order.
	var verbs := ["toolkit status", "panel", "inspect", "notices", "status"]
	var keys := ["toolkit", "panel", "inspect", "notices", "status"]
	# pulse advertised (discovery pins it, but assert here too — the fallback
	# on Strata's side gates on exactly this).
	var vr := await _link_send(peer, ["verbs"])
	_check(vr.size() == 1 and "pulse" in String(vr[0]).split(" "),
		"verbs advertises pulse (got %s)" % str(vr))
	# One pulse: one reply line, framed into the five named sections.
	var pr := await _link_send(peer, ["pulse"])
	_check(pr.size() == 1, "pulse answers in ONE reply line (got %d)" % pr.size())
	if pr.size() != 1:
		return
	var line := String(pr[0])
	_check(line.begins_with("ok pulse"), "pulse answers ok (got %s)" % line.substr(0, 40))
	var chunks := line.split(RS)
	_check(chunks[0] == "ok pulse", "pulse header is the first section frame")
	var got := {}
	for i in range(1, chunks.size()):
		var c := String(chunks[i])
		var eq := c.find("=")
		if eq > 0:
			got[c.substr(0, eq)] = c.substr(eq + 1)
	for k in keys:
		_check(got.has(k), "pulse carries the '%s' section" % k)
	# The identical-surface law: each nested section is the standalone verb's
	# reply, gathered the old five-send way in the same instant. `toolkit`
	# and `inspect` are STATE lines (no per-poll churn) — byte-identical.
	# `panel` and `status` carry per-poll counters (LINK's served, fps) that
	# tick between two sends, exactly the fields Strata's mirror already
	# ignores (SimClock reads only the clock; the panel's stable rows drive
	# publish-on-change) — so those two are checked by SHAPE, not bytes.
	var singles := await _link_send(peer, verbs)
	_check(singles.size() == verbs.size(),
		"the five verbs answer for the comparison (got %d)" % singles.size())
	if singles.size() == verbs.size():
		_check(got["toolkit"] == String(singles[0]),
			"pulse toolkit section == the standalone verb (%s vs %s)"
				% [got["toolkit"], singles[0]])
		_check(got["inspect"] == String(singles[2]),
			"pulse inspect section == the standalone verb (%s vs %s)"
				% [got["inspect"], singles[2]])
		# panel: same section frame as the standalone (HERE first, LINK last),
		# the churning LINK served aside.
		_check(String(got["panel"]).begins_with("ok panel HERE=")
				and String(singles[1]).begins_with("ok panel HERE="),
			"pulse panel section is the world panel (got %s)" % String(got["panel"]).substr(0, 24))
		_check(String(got["panel"]).split("\t").size()
				== String(singles[1]).split("\t").size(),
			"pulse panel carries every section the standalone does")
		# status: the clock + focus shape (served/fps churn, like the mirror
		# ignores them).
		_check(String(got["status"]).begins_with("ok ")
				and "focus=" in got["status"] and "h focus" in got["status"],
			"pulse status section carries the clock + focus (got %s)" % got["status"])
		# notices: the pulse above already drained, so the standalone re-read
		# is legitimately empty now — assert the pulse section is a drain reply.
		_check(String(got["notices"]).begins_with("ok notices "),
			"pulse notices section is a drain reply (got %s)" % got["notices"])
	# MEASURE (native-embed F2 ledger): one pulse vs five sends, wall time.
	# Same in-process peer, so this times the game-side compute + wire, not
	# the per-connection cost that dominates Strata's LiveLink (one connect/
	# write/read/close per send) — there the win is 5 sockets/tick -> 1.
	var reps := 40
	var t0 := Time.get_ticks_usec()
	for r in reps:
		await _link_send(peer, ["pulse"])
	var pulse_us := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for r in reps:
		await _link_send(peer, verbs)
	var five_us := Time.get_ticks_usec() - t0
	print("  [pulse] MEASURE over %d ticks: pulse %.3fms/tick (1 round-trip) vs "
		% [reps, pulse_us / 1000.0 / reps]
		+ "five-verb %.3fms/tick (5 round-trips) — round-trips/tick 5 -> 1"
		% [five_us / 1000.0 / reps])
	_check(true, "pulse measurement recorded (see [pulse] MEASURE line)")


## S1 — the pane-reveal boot phase (boot-speed B1, docs/PLAN_STRATA_TOOL.md).
## `boot` answers the streamer's honest reveal phase over the wire, and rides
## the `pulse` heartbeat as its own section — Strata's PaneBoot parser pins this
## grammar. No streamer lives in this headless test scene, so the phase reads
## "booting" (no honest frame yet) and first_frame=0 settled=0 — exactly the
## content-empty case the host holds the boot cover through. The grammar is the
## contract regardless of which phase happens to be live here.
func _test_boot_phase(peer: StreamPeerTCP) -> void:
	var br := await _link_send(peer, ["boot"])
	_check(br.size() == 1, "boot answers in one reply (got %d)" % br.size())
	if br.size() != 1:
		return
	var line := String(br[0])
	_check(line.begins_with("ok boot phase="),
		"boot answers the phase grammar (got %s)" % line)
	_check("first_frame=" in line and "settled=" in line,
		"boot carries first_frame + settled (got %s)" % line)
	var phase := ""
	for tok in line.trim_prefix("ok boot ").split(" ", false):
		if tok.begins_with("phase="):
			phase = tok.trim_prefix("phase=")
	_check(phase in ["booting", "revealing", "live"],
		"boot phase is one of booting|revealing|live (got '%s')" % phase)
	# The pulse heartbeat carries boot as its own section (the same VERBATIM
	# line), so Strata's one-round-trip poll reads the reveal phase too.
	var RS := char(30)
	var pr := await _link_send(peer, ["pulse"])
	_check(pr.size() == 1 and String(pr[0]).begins_with("ok pulse"),
		"pulse answers for the boot-section check")
	if pr.size() == 1:
		var got := {}
		for c in String(pr[0]).split(RS):
			var eq := String(c).find("=")
			if eq > 0:
				got[String(c).substr(0, eq)] = String(c).substr(eq + 1)
		_check(got.has("boot"), "pulse carries the 'boot' section")
		_check(String(got.get("boot", "")).begins_with("ok boot phase="),
			"pulse boot section is the standalone boot line (got %s)"
				% String(got.get("boot", "")))


## PANE_HEALTH (agent-observability-pipeline item 3): the frame-sanity probe
## that catches the "white-map" class of degenerate render mechanically — a
## near-uniform frame (a broken shader, an unshaded flat pane) reads
## uniform > 0.92 and verdicts degenerate; a varied frame verdicts ok. Since
## the 2026-07-11 recalibration there's a third case, pinned below: a frame
## that's near-flat by VARIANCE without ever saturating a uniform bucket
## (per-pixel dither/noise scattered a real pink-wash failure across too
## many quantized buckets for the old uniform-only rule to see) verdicts
## suspect, not ok. The headless test scene has no live GPU frame to score
## (the dummy renderer draws nothing — the same honest gate `flyover`/
## `thumbnail` already answer), so the WIRE half only pins that honest
## grammar; the SCORING half is driven directly against synthetic Images
## through the exact same _pane_health_stats() the live capture calls, so
## this pins the real math, not a mock of it.
func _test_pane_health(peer: StreamPeerTCP) -> void:
	# -- wire grammar: headless has no image, so the honest err answers,
	# never a hang and never a fake "ok" over nothing.
	var wr := await _link_send(peer, ["pane_health"])
	_check(wr.size() == 1, "pane_health answers in one reply (got %d)" % wr.size())
	if wr.size() == 1:
		_check(String(wr[0]).begins_with("err pane_health no image"),
			"pane_health errs honestly headless (got %s)" % wr[0])

	# -- scoring: a fully-flattened frame (the white-map failure's shape)
	# scores uniform~1.0 and verdicts degenerate.
	var flat := Image.create(64, 64, false, Image.FORMAT_RGB8)
	flat.fill(Color(0.9, 0.9, 0.9))
	var flat_stats: Dictionary = StrataLink._pane_health_stats(flat)
	_check(float(flat_stats["uniform"]) > 0.99,
		"a solid-color frame scores uniform~1.0 (got %.3f)" % float(flat_stats["uniform"]))
	_check(String(flat_stats["verdict"]) == "degenerate",
		"a solid-color frame verdicts degenerate (got %s)" % flat_stats["verdict"])

	# -- scoring: a varied frame (a checkerboard + per-pixel jitter — the
	# shape of a real render's sky gradient + ground detail, never one
	# dominant bucket) scores well under the line and verdicts ok.
	var varied := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for y in range(64):
		for x in range(64):
			var base := 0.2 if (x / 8 + y / 8) % 2 == 0 else 0.7
			var jitter := rng.randf_range(-0.05, 0.05)
			varied.set_pixel(x, y, Color(base + jitter, base * 0.8 + jitter, base * 0.6 + jitter))
	var varied_stats: Dictionary = StrataLink._pane_health_stats(varied)
	_check(float(varied_stats["uniform"]) < StrataLink.PANE_HEALTH_UNIFORM_DEGENERATE,
		"a varied frame scores under the degenerate line (got %.3f)" % float(varied_stats["uniform"]))
	_check(float(varied_stats["variance"]) > StrataLink.PANE_HEALTH_VARIANCE_SUSPECT_MAX,
		"a varied frame scores well clear of the suspect line too (got %.4f)"
			% float(varied_stats["variance"]))
	_check(String(varied_stats["verdict"]) == "ok",
		"a varied frame verdicts ok (got %s)" % varied_stats["verdict"])

	# -- scoring: THE PINNED REGRESSION (2026-07-11) — tonight's real live-
	# pane failure. The pane rendered a near-uniform pink wash and pane_health
	# answered "ok pane_health uniform=0.370 mean=0.644 var=0.0003
	# verdict=ok": the old uniform-only rule missed it because the wash
	# carried enough per-pixel dither/noise/gradient to spread across
	# multiple 5-bit-quantized buckets (no single bucket cleared 0.92) even
	# though the frame was, by luma variance, nearly flat — this world's
	# known-flattest REAL frame (the hazy-sky reference, header doc above)
	# scores var=0.0001, same order of magnitude. Tonight's exact pixels
	# weren't logged, so this fixture reproduces the FAILURE SHAPE
	# deterministically instead of guessing an exact match: three distinct
	# near-pink bands (rows, not noise, so the math below is exact and
	# doesn't depend on an RNG seed), none dominant, each landing in its own
	# quantization bucket — uniform=0.375, mean=0.6365, var=0.00065 by
	# construction (hand-derived, not measured: p_A=1536/4096, p_B=p_C=
	# 1280/4096; luma_A=0.63652, luma_B=0.60436, luma_C=0.66868). Close to
	# tonight's real numbers and squarely the same class. Must NOT verdict
	# ok — that would be this exact regression happening again silently.
	var wash := Image.create(64, 64, false, Image.FORMAT_RGB8)
	var band_a := Color(0.66, 0.62, 0.66)  # rows 0..23  (1536px, 37.5% — modal)
	var band_b := Color(0.74, 0.54, 0.58)  # rows 24..43 (1280px)
	var band_c := Color(0.58, 0.70, 0.74)  # rows 44..63 (1280px)
	for y in range(64):
		var band := band_a if y < 24 else (band_b if y < 44 else band_c)
		for x in range(64):
			wash.set_pixel(x, y, band)
	var wash_stats: Dictionary = StrataLink._pane_health_stats(wash)
	_check(float(wash_stats["uniform"]) < StrataLink.PANE_HEALTH_UNIFORM_DEGENERATE,
		"the pink-wash regression never trips the old uniform-only line (got %.3f) — that's WHY it slipped through"
			% float(wash_stats["uniform"]))
	_check(float(wash_stats["variance"]) < StrataLink.PANE_HEALTH_VARIANCE_SUSPECT_MAX,
		"the pink-wash regression reads as near-flat by variance (got %.5f, want < %.4f)"
			% [float(wash_stats["variance"]), StrataLink.PANE_HEALTH_VARIANCE_SUSPECT_MAX])
	_check(String(wash_stats["verdict"]) == "suspect",
		"THE FIX: a near-uniform, low-variance frame like tonight's must not verdict ok (got %s, uniform=%.3f var=%.5f)"
			% [wash_stats["verdict"], float(wash_stats["uniform"]), float(wash_stats["variance"])])


## The records desk (Strata R5): the game judges an edited record with its
## OWN loader schema before the desk commits (an invalid write never
## lands), answers the kind's field-type hints, and re-reads a kind live
## after a landed write. Judgement is the SAME Records.validate the loaders
## trust — never a parallel rule.
##
## The schema + reloader registries fill when a game SYSTEM loads (every
## load_dir registers its schema; WildlifeManager registers a reloader) —
## none of those systems live in the headless test scene, so this test
## stands up a SYNTHETIC kind through the exact same public doors a game
## system uses (load_dir registers the schema even for an absent dir;
## register_reloader the reloader), and drives the link against it. The
## real wildlife round trip is the desk's end-to-end acceptance. No files
## are written here: this is the game's HALF of the write path (validate +
## reload); the byte-faithful rewrite is Strata's, covered by its own tests.
func _test_records_desk(peer: StreamPeerTCP) -> void:
	# A game system registers its schema by loading its dir (the dir need
	# not exist for the schema to register — an empty kind still has rules).
	Records.load_dir("res://data/probe_kind", {"id": TYPE_STRING, "count": TYPE_FLOAT})
	# ...and a reloader if it can re-read live. We flip a captured latch so
	# the test can prove the link actually CALLED it (not just replied ok).
	var rebound := [false]
	Records.register_reloader("probe_kind", func() -> void: rebound[0] = true)
	# JSON with spaces on purpose — the record is the rest of the line and
	# must ride intact past the verb's token split.
	var ok_json := '{"id": "probe_rec", "count": 2}'
	var miss_json := '{"count": 2}'
	var type_json := '{"id": "probe_rec", "count": "lots"}'
	var replies := await _link_send(peer, [
		"records validate probe_kind " + ok_json,
		"records validate probe_kind " + miss_json,
		"records validate probe_kind " + type_json,
		"records validate probe_kind not json at all",
		"records validate schemaless_kind " + ok_json,
		"records schema probe_kind",
		"records reload probe_kind",
		"records reload nosuchkind",
		"records bogus probe_kind",
	])
	_check(replies.size() == 9, "records replies land (got %d)" % replies.size())
	if replies.size() != 9:
		return
	# validate: the game's own judgement, ok on a well-formed record and the
	# loader's exact words on a bad one — the desk surfaces these verbatim.
	_check(replies[0] == "ok validate probe_kind",
		"a valid record validates ok (got %s)" % replies[0])
	_check(replies[1] == "err validate probe_kind: missing field 'id'",
		"a missing required field errs in the game's words (got %s)" % replies[1])
	_check(String(replies[2]).begins_with("err validate probe_kind: field 'count' should be float"),
		"a wrong-typed field errs in the game's words (got %s)" % replies[2])
	_check(String(replies[3]).begins_with("err validate probe_kind: not a JSON object"),
		"non-object JSON errs honestly (got %s)" % replies[3])
	# An unknown kind has no registered schema — a record that PARSED as an
	# object is all the game can promise; it passes (the honest floor).
	_check(replies[4] == "ok validate schemaless_kind",
		"a schemaless kind validates a parsed object (got %s)" % replies[4])
	# schema: the field-type hints the loader trusts, one truth with validate.
	_check(String(replies[5]).begins_with("ok schema probe_kind "),
		"schema answers the kind's hints (got %s)" % replies[5])
	_check("id:String" in replies[5] and "count:float" in replies[5],
		"schema carries the loader's field types (got %s)" % replies[5])
	# reload: a kind with a live reloader re-reads and rebinds — and the link
	# actually invoked it (the latch flipped), not just answered ok.
	_check(String(replies[6]).begins_with("ok reload probe_kind ")
			and "no-rebind" not in String(replies[6]),
		"a kind with a reloader re-reads live (got %s)" % replies[6])
	_check(rebound[0], "the reload verb actually called the registered reloader")
	# A kind with no reloader is honest about it — never a silent ok.
	_check(String(replies[7]).begins_with("ok reload nosuchkind 0 no-rebind"),
		"a reloaderless kind says restart-to-apply (got %s)" % replies[7])
	_check(String(replies[8]).begins_with("err records needs"),
		"a bogus subverb errs with the contract line (got %s)" % replies[8])

	# -- edge grammar (PLAN.md axiom-4 amendment): a kind declares which
	# fields are graph edges and a SEMANTIC validator judges the whole
	# record. `records schema` emits the edge tokens (Strata's licence to
	# render/edit them); `records validate` runs the validator so a bad edge
	# bounces with the GAME's words. Pinned both ways below.
	Records.register_edges("probe_edge_kind",
		[{"field": "after", "to": "stage-id"}])
	Records.load_dir("res://data/probe_edge_kind", {"id": TYPE_STRING})
	# A stand-in semantic validator: the record's `bad` flag stands for "the
	# game's lint refused it" (the real quests validator is QuestLint; here we
	# only prove the desk relays a validator's verdict verbatim).
	Records.register_validator("probe_edge_kind",
		func(rec: Dictionary) -> String:
			return "edge cycle at 'z'" if rec.get("bad", false) else "")
	var good_edge := '{"id": "e", "after": ["a"]}'
	var bad_edge := '{"id": "e", "after": ["z"], "bad": true}'
	# The REAL quests kind: a well-formed but CYCLIC quest must bounce through
	# QuestLint (story.gd registered it as the quests validator) — the mission's
	# core claim, "the game's own lint judges cycles/unknown stages".
	var cyclic_quest := '{"format": 2, "id": "probe_cycle", "title": "P", "tier": "errand", "stages": [{"id": "a", "start": true, "after": ["b"]}, {"id": "b", "after": ["a"], "terminal": true, "journal": "x"}]}'
	var sound_quest := '{"format": 2, "id": "probe_ok", "title": "P", "tier": "errand", "stages": [{"id": "a", "start": true}, {"id": "done", "terminal": true, "journal": "done"}]}'
	var ereplies := await _link_send(peer, [
		"records schema probe_edge_kind",
		"records validate probe_edge_kind " + good_edge,
		"records validate probe_edge_kind " + bad_edge,
		"records schema quests",
		"records validate quests " + cyclic_quest,
		"records validate quests " + sound_quest,
	])
	_check(ereplies.size() == 6, "edge replies land (got %d)" % ereplies.size())
	if ereplies.size() == 6:
		# schema emits the declared edge as edge:<field>><to> alongside the
		# field hints — the grammar Strata's RecordSchema parser pins.
		_check("edge:after>stage-id" in ereplies[0],
			"schema emits the edge grammar token (got %s)" % ereplies[0])
		_check("id:String" in ereplies[0],
			"schema still carries field hints beside edges (got %s)" % ereplies[0])
		# validate: a sound record passes, a refused edge bounces with the
		# validator's OWN words (the desk never invents the verdict).
		_check(ereplies[1] == "ok validate probe_edge_kind",
			"a valid edge record validates ok (got %s)" % ereplies[1])
		_check(ereplies[2] == "err validate probe_edge_kind: edge cycle at 'z'",
			"a refused edge bounces with the game's words (got %s)" % ereplies[2])
		# The REAL quests kind declares its `after` edge — the shipped licence
		# Strata reads to light up quest-flow editing.
		_check("edge:after>stage-id" in ereplies[3],
			"the shipped quests kind declares its after edge (got %s)" % ereplies[3])
		# The real QuestLint judges the whole edited quest: a cycle bounces
		# with the game's own words; a sound quest passes. This is what an
		# illegal drag hits before anything lands.
		_check(String(ereplies[4]).begins_with("err validate quests:")
				and "cycle" in String(ereplies[4]),
			"a cyclic quest bounces with QuestLint's cycle words (got %s)" % ereplies[4])
		_check(ereplies[5] == "ok validate quests",
			"a sound quest validates ok through the real lint (got %s)" % ereplies[5])
	# The CAST SHEET's characters kind over the wire (CREATION_KIT_REVIEW_V2
	# #3a): a creature's or villager's day, edited like a quest. `records schema
	# characters` answers the shape the desk renders typed editors from;
	# `records validate characters` runs the SAME whole-record judgement the
	# loader does — a schedule with a malformed activity bounces with the game's
	# own words, over the link, before anything lands. This is the acceptance's
	# "edit an activity record over the link" half, proven headless.
	var good_villager := '{"id": "wire_v", "identity": {"name": "Wire", "kind": "villager"}, "body": {"card": "chars/villager_keeper"}, "home": {"x": 0, "z": 0}, "schedule": [{"id": "garden", "at": "roam", "satisfies": "work"}]}'
	var bad_villager := '{"id": "wire_v", "identity": {"name": "Wire", "kind": "villager"}, "body": {"card": "chars/villager_keeper"}, "home": {"x": 0, "z": 0}, "schedule": [{"id": "garden", "at": "roam"}]}'
	var vreplies := await _link_send(peer, [
		"records schema characters",
		"records validate characters " + good_villager,
		"records validate characters " + bad_villager,
	])
	_check(vreplies.size() == 3, "character desk replies land (got %d)" % vreplies.size())
	if vreplies.size() == 3:
		_check("schedule:Array" in String(vreplies[0]),
			"schema characters answers the schedule field's shape (got %s)" % vreplies[0])
		_check(vreplies[1] == "ok validate characters",
			"a sound character validates ok over the link (got %s)" % vreplies[1])
		_check(String(vreplies[2]).begins_with("err validate characters:")
				and "satisfies" in String(vreplies[2]),
			"a malformed schedule bounces with the game's words (got %s)" % vreplies[2])
	# Leave no trace: drop the synthetic kinds from the registries.
	Records._schemas.erase("probe_kind")
	Records._reloaders.erase("probe_kind")
	Records._schemas.erase("probe_edge_kind")
	Records._edges.erase("probe_edge_kind")
	Records._validators.erase("probe_edge_kind")


## The audio verbs over the link (PLAN_AUDIO A1, 4a/4b-ii). play_sound
## auditions an event or a res-path (fire-and-forget, sync ok — silent
## no-op for content valley doesn't ship); `audio` mirrors the house bus
## levels and `audio set` drives one live, honest about a non-house bus.
func _test_audio_verbs(peer: StreamPeerTCP) -> void:
	var r := await _link_send(peer, [
		"play_sound",
		"play_sound thunder_near",
		"play_sound res://assets/audio/does_not_exist.wav",
		"audio",
		"audio set SFX -4.5",
		"audio set Nonsense 0",
		"audio set SFX",
		"audio bogus",
	])
	_check(r.size() == 8, "audio verb replies land (got %d)" % r.size())
	if r.size() != 8:
		return
	_check(String(r[0]).begins_with("err play_sound needs"),
		"play_sound bare errs with the contract line (got %s)" % r[0])
	_check(r[1] == "ok play_sound thunder_near",
		"play_sound <event> answers ok, fire-and-forget (got %s)" % r[1])
	_check(String(r[2]) == "ok play_sound res://assets/audio/does_not_exist.wav",
		"play_sound <res-path> answers ok even for absent content (got %s)" % r[2])
	# `audio` mirrors the live buses in tree order + the duck token.
	var levels := String(r[3])
	_check(levels.begins_with("ok audio Master:") and " UI:" in levels
		and levels.ends_with("duck:-"),
		"audio reply carries the house buses + duck token (got %s)" % levels)
	# `audio set` drives the live bus and reports it back.
	_check(r[4] == "ok audio SFX -4.5", "audio set drives a house bus (got %s)" % r[4])
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
		- (-4.5)) < 0.01, "audio set actually moved the SFX bus")
	_check(String(r[5]).begins_with("err audio set: 'Nonsense'"),
		"audio set on a non-house bus errs (got %s)" % r[5])
	_check(String(r[6]).begins_with("err audio set needs"),
		"audio set missing db errs with the contract line (got %s)" % r[6])
	_check(String(r[7]).begins_with("err audio needs"),
		"audio bogus subverb errs with the contract line (got %s)" % r[7])

	# Commit-to-mix over the link (X4 A3-breadth item 3): `audio commit`
	# lands the CURRENT live bus levels into the REAL data/audio/mix.json —
	# snapshot + restore around it (the `_test_names_verbs` precedent) so a
	# green run leaves the worktree byte-identical.
	var mix_file := ProjectSettings.globalize_path("res://data/audio/mix.json")
	var mix_original := (FileAccess.get_file_as_string(mix_file)
		if FileAccess.file_exists(mix_file) else "")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -2.0)
	var c := await _link_send(peer, ["audio commit"])
	_check(c.size() == 1, "audio commit reply lands (got %d)" % c.size())
	if c.size() == 1:
		var commit_line := String(c[0])
		_check(commit_line.begins_with("ok audio commit ") and "Music:-2.0" in commit_line,
			"audio commit answers with the just-landed levels (got %s)" % commit_line)
		var on_disk = Records.load_json(mix_file)
		_check(on_disk is Dictionary
			and absf(float(on_disk.get("levels", {}).get("Music", 0.0)) - (-2.0)) < 0.01,
			"audio commit: mix.json on disk carries the committed level (got %s)" % on_disk)
	# Restore the shipped file byte-for-byte, then reload so the live table
	# (ducks + any levels) matches the real content again.
	if mix_original.is_empty():
		if FileAccess.file_exists(mix_file):
			DirAccess.remove_absolute(mix_file)
	else:
		var restore_f := FileAccess.open(mix_file, FileAccess.WRITE)
		restore_f.store_string(mix_original)
		restore_f.close()
	Audio.reload_mix()
	# Leave the mix as found (other probes read levels).
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), 0.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), 0.0)
	# The audition arm (A3, 4b-ii): play_sound auditions an ambience LAYER
	# by id through the held voice (beds loop) and `play_sound stop` silences
	# it — the Mix face's Audition/Stop buttons, proven over the wire. The
	# bed rides the ambience records this game ships (wind_bed), so what the
	# probe hears is what ships (LAW A4).
	Audio.audition_stop()  # clean slate — nothing auditioning
	var a := await _link_send(peer, [
		"play_sound wind_bed",
		"play_sound stop",
		"play_sound stop",
	])
	_check(a.size() == 3, "audition replies land (got %d)" % a.size())
	if a.size() == 3:
		_check(a[0] == "ok play_sound wind_bed",
			"play_sound <ambience id> auditions the bed (got %s)" % a[0])
		_check(a[1] == "ok play_sound stop",
			"play_sound stop answers ok (got %s)" % a[1])
		_check(a[2] == "ok play_sound stop",
			"play_sound stop is idempotent — a second stop is a clean no-op (got %s)" % a[2])
	# The held voice actually RUNS the bed and the stop actually silences it
	# (not just an ok over the wire). The scene-test context is autoload-only
	# — no Ambience scene node, so its index is empty and the wire audition
	# above is a content-empty no-op; here we drive Audio.audition directly
	# with a bed record over the game's OWN shipped wav, proving the graph
	# path (loops, plays on the record's house bus, stops). The full-scene
	# headless probe proves the wire path end-to-end where the node exists.
	var bed := {
		"id": "wind_bed", "file": "res://assets/audio/wind_loop.wav",
		"bus": "Ambience", "day_gain": 0.5,
	}
	if ResourceLoader.exists(String(bed["file"])):
		Audio.audition(bed)
		_check(Audio._audition.playing,
			"audition holds a looping voice for a bed")
		_check(Audio._audition.bus == String(bed["bus"]),
			"audition plays on the bed's OWN house bus (%s), through the real graph"
			% Audio._audition.bus)
		_check(Audio._audition.stream is AudioStreamWAV
			and (Audio._audition.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED,
			"audition loops the bed so it can be judged")
		Audio.audition_stop()
		_check(not Audio._audition.playing,
			"audition_stop silences the held voice")
	else:
		print("  audition: SKIP (no wind_loop.wav asset)")


## preview_world (ONE_APP P8, the viewer): the game wears a Strata export
## IN MEMORY — the ground reshapes, the sea moves, and NOTHING under
## res://data changes; restoring is just wearing the original again.
## Runs only when the real tile cache exists (it is the restore point).
func _test_preview_world(peer: StreamPeerTCP) -> void:
	if not Terrain.has_world_tile():
		print("  preview world: SKIP (no baked tile cache to restore to)")
		return
	var orig_rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/regions/baked_world.json"))
	if not (orig_rec is Dictionary):
		print("  preview world: SKIP (no baked_world.json record)")
		return
	var orig_sea: float = Terrain.sea_level
	# Probe points OUTSIDE the sculpt layer's ±2048m frame and away from
	# tile feather — the flat preview must read exactly 42m there.
	var before_a: float = Terrain.height(3000.0, 3000.0)
	# A synthetic export: flat 42m world, sea at 5m.
	var dir := ProjectSettings.globalize_path("user://preview_test_world")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(64, 64, false, Image.FORMAT_RF)
	img.fill(Color(42.0, 0.0, 0.0))
	img.save_exr(dir.path_join("height.exr"))
	var mf := FileAccess.open(dir.path_join("bake_manifest.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify({"world": {
		"size_m": [16384.0, 16384.0], "sea_level_m": 5.0}}))
	mf.close()
	var tile_mtime := FileAccess.get_modified_time(ProjectSettings.globalize_path(
		"res://data/terrain/tiles/baked_world.exr"))
	var replies := await _link_send(peer, ["preview_world " + dir])
	_check(replies.size() == 1 and replies[0].begins_with("ok preview"),
		"preview_world answers ok (got %s)" % str(replies))
	_check(absf(Terrain.height(3000.0, 3000.0) - 42.0) < 0.01,
		"preview reshapes the ground in memory (%.2f)" % Terrain.height(3000.0, 3000.0))
	_check(absf(Terrain.sea_level - 5.0) < 0.01, "preview carries the sea level")
	_check(FileAccess.get_modified_time(ProjectSettings.globalize_path(
		"res://data/terrain/tiles/baked_world.exr")) == tile_mtime,
		"the checkout's tile cache is untouched")
	# Restore: wear the original record again (the same in-memory door).
	_check(Terrain.preview_tile(orig_rec, orig_sea), "restore wears the original")
	_check(Terrain.height(3000.0, 3000.0) == before_a,
		"restore returns bit-identical ground")
	DirAccess.remove_absolute(dir.path_join("height.exr"))
	DirAccess.remove_absolute(dir.path_join("bake_manifest.json"))
	DirAccess.remove_absolute(dir)


## preview_mesh + view_layer (engine-viewport M2, the fast path): the GPU
## preview grid wears an export as a texture swap — Terrain is NEVER
## touched (the deliberate opposite of preview_world), the streamed
## world's dress steps aside by group with its visibility recorded, and
## leaving preview restores it exactly. The verb matrix errs with its
## contract lines: bad args, missing manifest/height, missing layer
## files, view_layer before a wear.
func _test_preview_mesh(peer: StreamPeerTCP) -> void:
	# Stage hands for the lifecycle: two dress nodes in the steps-aside
	# group — one visible (the normal world), one ALREADY hidden (restore
	# must return recorded visibility, not blanket-show).
	var ground := Node3D.new()
	ground.add_to_group(PreviewTerrain.STEPS_ASIDE_GROUP)
	add_child(ground)
	var cellar := Node3D.new()
	cellar.add_to_group(PreviewTerrain.STEPS_ASIDE_GROUP)
	cellar.visible = false
	add_child(cellar)
	var sea_before: float = Terrain.sea_level
	var height_before: float = Terrain.height(3000.0, 3000.0)
	# A synthetic export, built in two acts so the missing-height error
	# answers first: manifest (flat 42m world, sea at 5m), then height.exr,
	# moisture.png and colormap.png — temperature.png deliberately absent.
	var dir := ProjectSettings.globalize_path("user://preview_mesh_world")
	DirAccess.make_dir_recursive_absolute(dir)
	var mf := FileAccess.open(dir.path_join("bake_manifest.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify({"world": {
		"size_m": [16384.0, 16384.0], "sea_level_m": 5.0}}))
	mf.close()
	var pre := await _link_send(peer, [
		"preview_mesh",              # 0: bare verb errs
		"view_layer moisture",       # 1: no preview worn yet
		"view_layer",                # 2: bare verb errs with the layer list
		"preview_mesh /no/such/dir", # 3: honest missing-manifest error
		"preview_mesh " + dir,       # 4: manifest yes, height not yet
		"probe 0 0",                 # 5: no preview worn yet
		"probe",                     # 6: bare verb errs
		"probe 1 two",               # 7: non-numeric args err
	])
	_check(pre.size() == 8, "preview_mesh pre-wear replies land (got %d)" % pre.size())
	if pre.size() == 8:
		_check(pre[0] == "err preview_mesh needs a dir (or off)", "bare preview_mesh errs")
		_check(pre[1] == "err no preview mesh worn (preview_mesh <dir> first)",
			"view_layer before a wear errs honestly")
		_check(pre[2] == "err view_layer needs shaded|moisture|temperature|flow|slope|biome|province",
			"bare view_layer errs with the layer list")
		_check(pre[3].begins_with("err no bake_manifest.json"), "missing manifest errs")
		_check(pre[4].begins_with("err no height.exr"), "missing height.exr errs")
		_check(pre[5] == "err no preview mesh worn (preview_mesh <dir> first)",
			"probe before a wear errs honestly")
		_check(pre[6] == "err probe needs x z", "bare probe errs")
		_check(pre[7] == "err probe needs x z", "non-numeric probe args err")
	var img := Image.create(64, 64, false, Image.FORMAT_RF)
	img.fill(Color(42.0, 0.0, 0.0))
	img.save_exr(dir.path_join("height.exr"))
	var gray := Image.create(64, 64, false, Image.FORMAT_L8)
	gray.fill(Color(0.5, 0.5, 0.5))
	gray.save_png(dir.path_join("moisture.png"))
	var rgba := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	rgba.fill(Color(0.2, 0.6, 0.3, 1.0))
	rgba.save_png(dir.path_join("colormap.png"))
	# The wear: ok reply carries the world frame, the sea, and the swap
	# time; the dress hides; Terrain never hears about any of it.
	var worn := await _link_send(peer, ["preview_mesh " + dir])
	_check(worn.size() == 1 and worn[0].begins_with("ok preview_mesh 16384m sea=5.0m wear="),
		"preview_mesh answers the contract shape (got %s)" % str(worn))
	_check(StrataLink._preview != null and StrataLink._preview.worn,
		"the preview grid is worn")
	_check(not ground.visible, "the streamed dress steps aside")
	_check(not cellar.visible, "an already-hidden dress node stays hidden")
	_check(Terrain.sea_level == sea_before,
		"preview_mesh never touches Terrain's sea level")
	_check(Terrain.height(3000.0, 3000.0) == height_before,
		"preview_mesh never touches the height function (the kernel is not re-tiled)")
	# The layer matrix: present files drape, the absent ones err by name
	# (temperature.png and flow.exr are deliberately missing here — the
	# old-export path M3 keeps honest), computed layers (slope) and
	# file-less modes (shaded) always answer.
	var layers := await _link_send(peer, [
		"view_layer moisture",     # 0
		"view_layer temperature",  # 1: file absent from this export
		"view_layer bogus",        # 2
		"view_layer slope",        # 3
		"view_layer biome",        # 4
		"view_layer shaded",       # 5
		"view_layer flow",         # 6: file absent from this export
		"view_layer moisture",     # 7: back on, to ride through the re-wear
	])
	_check(layers.size() == 8, "view_layer replies land (got %d)" % layers.size())
	if layers.size() == 8:
		_check(layers[0].begins_with("ok layer moisture"), "moisture drapes")
		_check(layers[1] == "err layer file missing: temperature.png (re-export from Strata)",
			"a layer the export lacks errs by filename")
		_check(layers[2] == "err view_layer needs shaded|moisture|temperature|flow|slope|biome|province",
			"unknown layer errs with the layer list")
		_check(layers[3].begins_with("ok layer slope"), "slope computes in-shader")
		_check(layers[4].begins_with("ok layer biome"), "biome drapes the colormap")
		_check(layers[5].begins_with("ok layer shaded"), "shaded always answers")
		_check(layers[6] == "err layer file missing: flow.exr (re-export from Strata)",
			"flow without flow.exr errs by filename (the old-export path)")
		_check(layers[7].begins_with("ok layer moisture"), "moisture re-drapes")
	# The probe (M3 value-under-cursor): the ACTIVE layer's value at a
	# world XZ, physical units, grammar pinned by Strata's LayerProbe.
	# flow.exr (raw floats) and biome.png (ids) join the export here.
	var fimg := Image.create(64, 64, false, Image.FORMAT_RF)
	fimg.fill(Color(15.0, 0.0, 0.0))
	fimg.save_exr(dir.path_join("flow.exr"))
	var bbytes := PackedByteArray()
	bbytes.resize(64 * 64)
	bbytes.fill(7)  # id 7 everywhere — exact bytes, no float round-trip
	var bimg := Image.create_from_data(64, 64, false, Image.FORMAT_L8, bbytes)
	bimg.save_png(dir.path_join("biome.png"))
	var probes := await _link_send(peer, [
		"probe 0 0",               # 0: moisture is active — png 0.5
		"probe 99999 0",           # 1: outside the worn world
		"view_layer shaded",       # 2
		"probe 1024 -300",         # 3: shaded = height (flat 42m world)
		"view_layer slope",        # 4
		"probe 0 0",               # 5: flat world -> slope 0
		"view_layer flow",         # 6: flow.exr present now
		"probe 0 0",               # 7: raw exr value
		"view_layer biome",        # 8
		"probe 0 0",               # 9: the id from biome.png
		"view_layer moisture",     # 10: restore for the re-wear leg
	])
	_check(probes.size() == 11, "probe replies land (got %d)" % probes.size())
	if probes.size() == 11:
		_check(probes[0] == "ok probe moisture 0.50 at (0, 0)",
			"probe answers the active layer (got %s)" % probes[0])
		_check(probes[1] == "err probe (99999, 0) outside the world (max 8192m from center)",
			"probe outside the world errs (got %s)" % probes[1])
		_check(probes[3] == "ok probe shaded 42.0 at (1024, -300)",
			"shaded probe answers height in meters (got %s)" % probes[3])
		_check(probes[5] == "ok probe slope 0.00 at (0, 0)",
			"slope probe computes from the height mirror (got %s)" % probes[5])
		_check(probes[6].begins_with("ok layer flow"), "flow drapes once flow.exr exists")
		_check(probes[7] == "ok probe flow 15.00 at (0, 0)",
			"flow probe answers the raw exr value (got %s)" % probes[7])
		_check(probes[9] == "ok probe biome 7 at (0, 0)",
			"biome probe answers the id from biome.png (got %s)" % probes[9])
	# Warm re-wear (the slider loop): still ok, the dress stays aside
	# WITHOUT re-recording (restore must remember the original state),
	# and the active drape survives the push.
	var rewear := await _link_send(peer, ["preview_mesh " + dir])
	_check(rewear.size() == 1 and rewear[0].begins_with("ok preview_mesh"),
		"warm re-wear answers ok")
	_check(not ground.visible, "re-wear keeps the dress aside")
	_check(String(StrataLink._preview._layer) == "moisture",
		"the drape survives a re-wear")
	# A re-wear whose export DROPPED the draped layer falls back to
	# shaded honestly instead of draping stale bytes.
	DirAccess.remove_absolute(dir.path_join("moisture.png"))
	var dropped := await _link_send(peer, ["preview_mesh " + dir])
	_check(dropped.size() == 1 and dropped[0].begins_with("ok preview_mesh"),
		"re-wear without the draped layer still wears")
	_check(String(StrataLink._preview._layer) == "shaded",
		"a dropped layer falls back to shaded")
	# Leave: the dress returns EXACTLY as recorded (visible stays visible,
	# hidden stays hidden), the grid hides, and off is idempotent.
	var off := await _link_send(peer, [
		"preview_mesh off", "preview_mesh off", "view_layer shaded"])
	_check(off.size() == 3, "off replies land (got %d)" % off.size())
	if off.size() == 3:
		_check(off[0] == "ok preview_mesh off (streamed world restored)", "off restores")
		_check(off[1] == "ok preview_mesh off (streamed world restored)", "off is idempotent")
		_check(off[2] == "err no preview mesh worn (preview_mesh <dir> first)",
			"view_layer after off errs honestly")
	_check(ground.visible, "the visible dress node returns visible")
	_check(not cellar.visible, "the hidden dress node returns hidden")
	_check(not StrataLink._preview.worn and not StrataLink._preview.visible,
		"the grid steps back after off")
	# Leave no trace: the export files, the stage hands, the grid.
	for f in ["height.exr", "colormap.png", "flow.exr", "biome.png",
			"bake_manifest.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	ground.queue_free()
	cellar.queue_free()
	StrataLink._preview.queue_free()
	StrataLink._preview = null


## The scatter overlay (M4 in-viewport preview): when the worn export carries
## a Strata scatter bake, the preview grid grows a MultiMesh of proxy markers
## standing on the SAME relief — so the operator judges trees-on-hills. The
## contract this pins: the overlay WEARS on preview_mesh (the reply tail
## carries the count), the markers sit at the placement y (on the relief),
## the instance cap subsamples a dense bake WITHOUT a silent truncation (the
## reply names the cap), and — the regression, the 2026-07-09 fall-through
## family — it LEAVES on preview_mesh off (the MultiMesh is freed, not left
## hanging over the restored streamed world).
func _test_preview_scatter(peer: StreamPeerTCP) -> void:
	var dir := ProjectSettings.globalize_path("user://preview_scatter_world")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("scatter"))
	# The base export (flat 42m world) so the mesh wears; the scatter rides it.
	var mf := FileAccess.open(dir.path_join("bake_manifest.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify({"world": {
		"size_m": [16384.0, 16384.0], "sea_level_m": 5.0}}))
	mf.close()
	var img := Image.create(64, 64, false, Image.FORMAT_RF)
	img.fill(Color(42.0, 0.0, 0.0))
	img.save_exr(dir.path_join("height.exr"))
	# A tiny scatter bake: one cell, three props at a known y=42.
	var props := [
		{"id": "sc_a", "cat": "trees", "x": 0.0, "y": 42.0, "z": 0.0, "yaw": 0.0, "scale": 1.0, "pick": 0.1},
		{"id": "sc_b", "cat": "rocks", "x": 100.0, "y": 42.0, "z": -50.0, "yaw": 1.0, "scale": 2.0, "pick": 0.4},
		{"id": "sc_c", "cat": "trees", "x": -80.0, "y": 42.0, "z": 30.0, "yaw": 2.0, "scale": 0.8, "pick": 0.9},
	]
	_write_scatter_cell(dir, 0, 0, props)
	_write_scatter_manifest(dir, props.size(), [[0, 0, "cell_0_0.json", props.size()]])
	# Wear: the reply tail carries the count and the overlay stands one
	# MultiMesh instance per placement. (The instance TRANSFORMS live in the
	# RenderingServer buffer, which the headless dummy renderer discards — so
	# the on-relief placement is a real-renderer/visual property, not asserted
	# here; instance_count, which lives on the resource, is.)
	var worn := await _link_send(peer, ["preview_mesh " + dir])
	_check(worn.size() == 1 and String(worn[0]).begins_with("ok preview_mesh"),
		"scatter wear answers ok (got %s)" % str(worn))
	_check(worn.size() == 1 and String(worn[0]).contains("scatter=3"),
		"the wear reply carries the scatter count (got %s)" % str(worn))
	var pv: PreviewTerrain = StrataLink._preview
	_check(pv != null and pv._scatter_mmi != null,
		"the scatter overlay is worn")
	if pv != null and pv._scatter_mmi != null:
		_check(pv._scatter_mmi.multimesh.instance_count == 3,
			"the overlay instances every placement (got %d)" %
				pv._scatter_mmi.multimesh.instance_count)
		_check(pv._scatter_mmi.get_parent() == pv,
			"the overlay is a child of the preview grid (wears/leaves with it)")
	# A re-wear whose bake dropped the scatter (no scatter/manifest) clears the
	# overlay honestly — bare relief, no stale markers.
	DirAccess.remove_absolute(dir.path_join("scatter/manifest.json"))
	var bare := await _link_send(peer, ["preview_mesh " + dir])
	_check(bare.size() == 1 and not String(bare[0]).contains("scatter="),
		"a bake without scatter drops the overlay from the reply (got %s)" % str(bare))
	_check(pv != null and pv._scatter_mmi == null,
		"the overlay is gone when the new bake has no scatter")
	# The cap: 8000 props in one cell subsample to exactly SCATTER_CAP, and the
	# reply NAMES the cap (no silent truncation — the drop is total−shown).
	var many: Array = []
	for i in 8000:
		many.append({"id": "sc_%d" % i, "cat": "trees",
			"x": float(i % 128) - 64.0, "y": 42.0, "z": float(i / 128) - 64.0,
			"yaw": 0.0, "scale": 1.0, "pick": 0.0})
	_write_scatter_cell(dir, 0, 0, many)
	_write_scatter_manifest(dir, many.size(), [[0, 0, "cell_0_0.json", many.size()]])
	var capped := await _link_send(peer, ["preview_mesh " + dir])
	_check(capped.size() == 1 and String(capped[0]).contains("/8000(cap)"),
		"the capped reply names the cap and the total (got %s)" % str(capped))
	var capped_n := pv._scatter_mmi.multimesh.instance_count if pv != null and pv._scatter_mmi != null else -1
	_check(capped_n > 0 and capped_n <= PreviewTerrain.SCATTER_CAP,
		"the overlay honors the instance cap (got %d, cap %d)" % [capped_n, PreviewTerrain.SCATTER_CAP])
	# THE regression: leave frees the overlay — it does not hang over the
	# restored streamed world (the 2026-07-09 fall-through family).
	var off := await _link_send(peer, ["preview_mesh off"])
	_check(off.size() == 1 and off[0] == "ok preview_mesh off (streamed world restored)",
		"off restores")
	_check(pv != null and pv._scatter_mmi == null,
		"the scatter overlay LEAVES with the drape on off")
	# Leave no trace.
	for f in ["height.exr", "bake_manifest.json", "scatter/cell_0_0.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir.path_join("scatter"))
	DirAccess.remove_absolute(dir)
	StrataLink._preview.queue_free()
	StrataLink._preview = null


## T1 · the water overlay (PLAN_STRATA_TOOL). The rivers/lakes/waterfalls the
## bake computes (hydrology.json, in every export) draw on the drape, honor the
## "Hydrology: live ⏸" toggle (preview_water on|off), and — the regression that
## matters — LEAVE with the drape so no blue lines hang over the streamed world
## (builder mode). Same env as _test_preview_scatter: a synthetic export dir
## worn over the REAL link + PreviewTerrain.
func _test_preview_water(peer: StreamPeerTCP) -> void:
	var dir := ProjectSettings.globalize_path("user://preview_water_world")
	DirAccess.make_dir_recursive_absolute(dir)
	# Base export so the mesh wears; the water rides the same dir.
	var mf := FileAccess.open(dir.path_join("bake_manifest.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify({"world": {
		"size_m": [16384.0, 16384.0], "sea_level_m": 5.0}}))
	mf.close()
	var img := Image.create(64, 64, false, Image.FORMAT_RF)
	img.fill(Color(42.0, 0.0, 0.0))
	img.save_exr(dir.path_join("height.exr"))
	# A tiny hydrology.json in the export shape: one two-node river carrying one
	# waterfall, one lake with a true triangular outline, one disc-fallback lake.
	_write_hydrology(dir, {
		"format": 1, "sea_level_m": 5.0,
		"rivers": [{
			"id": "r0", "catchment_m2": 5.0e6,
			"nodes": [
				{"x": -200.0, "z": 0.0, "width": 3.0, "surface": 40.0},
				{"x": 200.0, "z": 0.0, "width": 9.0, "surface": 35.0}],
			"waterfalls": [{"x": 0.0, "z": 0.0, "drop_m": 6.0}]}],
		"lakes": [
			{"id": "l0", "x": 500.0, "z": 500.0, "radius": 80.0, "surface": 30.0,
				"depth": 8.0, "outline": [
					{"x": 420.0, "z": 420.0}, {"x": 580.0, "z": 420.0},
					{"x": 500.0, "z": 580.0}]},
			{"id": "l1", "x": -500.0, "z": -500.0, "radius": 60.0, "surface": 20.0,
				"depth": 5.0, "outline": []}]})
	# Wear: the reply names the counts and the overlay stands one MeshInstance3D
	# (surfaces live on the resource, which the headless dummy renderer keeps —
	# unlike the RenderingServer instance buffer scatter can't assert here).
	var worn := await _link_send(peer, ["preview_mesh " + dir])
	_check(worn.size() == 1 and String(worn[0]).begins_with("ok preview_mesh"),
		"water wear answers ok (got %s)" % str(worn))
	_check(worn.size() == 1 and String(worn[0]).contains("water=1r/2l"),
		"the wear reply carries the water count (got %s)" % str(worn))
	var pv: PreviewTerrain = StrataLink._preview
	_check(pv != null and pv._water_mi != null, "the water overlay is worn")
	if pv != null and pv._water_mi != null:
		_check(pv._water_mi.get_parent() == pv,
			"the overlay is a child of the preview grid (wears/leaves with it)")
		# Three surfaces: river ribbons (triangles), lake outlines, waterfall
		# ticks (both lines) — the shapes the bake already computed.
		_check(pv._water_mi.mesh != null and pv._water_mi.mesh.get_surface_count() == 3,
			"the mesh carries river + lake + waterfall surfaces (got %d)" %
				(pv._water_mi.mesh.get_surface_count() if pv._water_mi.mesh != null else -1))
		_check(pv._water_mi.visible, "the overlay is visible by default (live)")
		# W4 — the HONEST chart: ribbon vertices sit at TRUE 1× width, draped to
		# the export relief (flat 42m here) + the z-guard epsilon — never the old
		# 3×-wide quad floating 2m over the record surface. The survey width
		# rides NORMAL.xz for the ★6 fade shader instead.
		if pv._water_mi.mesh != null and pv._water_mi.mesh.get_surface_count() == 3:
			var arr: Array = pv._water_mi.mesh.surface_get_arrays(0)
			var rv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var rn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			_check(rv.size() > 0 and absf(rv[0].y - (42.0 + 0.3)) < 0.05,
				"W4: the ribbon drapes to the export height (+epsilon), no 2m float (y=%.2f)"
					% (rv[0].y if rv.size() > 0 else -1.0))
			# First segment, first vert: node width 3 → true half 1.5m off the
			# centerline (the river runs along z=0, so the vert sits at |z|=1.5).
			_check(rv.size() > 0 and absf(absf(rv[0].z) - 1.5) < 0.05,
				"W4: vertices carry TRUE 1x half-width (|z|=%.2f, want 1.5)"
					% (absf(rv[0].z) if rv.size() > 0 else -1.0))
			_check(rn.size() == rv.size() and rn.size() > 0 and rn[0].length() > 0.5,
				"W4: the survey exaggeration rides NORMAL.xz for the fade shader")
			_check(pv._water_river_mat != null,
				"W4: the river surface wears the ★6 fade shader material")
	# The ⏸ toggle: preview_water off hides WITHOUT re-solving (the node stays,
	# just invisible), on shows it again. No re-wear, no stale geometry.
	var off_w := await _link_send(peer, ["preview_water off"])
	_check(off_w.size() == 1 and off_w[0] == "ok preview_water off",
		"preview_water off answers ok (got %s)" % str(off_w))
	_check(pv != null and pv._water_mi != null and not pv._water_mi.visible,
		"the toggle HIDES the overlay (node kept, invisible)")
	var on_w := await _link_send(peer, ["preview_water on"])
	_check(on_w.size() == 1 and on_w[0] == "ok preview_water on",
		"preview_water on answers ok (got %s)" % str(on_w))
	_check(pv != null and pv._water_mi != null and pv._water_mi.visible,
		"the toggle SHOWS the overlay again")
	# A re-wear whose bake dropped the hydrology (no hydrology.json) clears the
	# overlay honestly — bare relief, no stale rivers.
	DirAccess.remove_absolute(dir.path_join("hydrology.json"))
	var bare := await _link_send(peer, ["preview_mesh " + dir])
	_check(bare.size() == 1 and not String(bare[0]).contains("water="),
		"a bake without hydrology drops the overlay from the reply (got %s)" % str(bare))
	_check(pv != null and pv._water_mi == null,
		"the overlay is gone when the new bake has no hydrology")
	# THE regression: leave frees the overlay — it never hangs over the restored
	# streamed world (builder mode). Re-wear the water first, then leave.
	_write_hydrology(dir, {"format": 1, "sea_level_m": 5.0,
		"rivers": [{"id": "r0", "catchment_m2": 1.0e6, "nodes": [
			{"x": 0.0, "z": -100.0, "width": 4.0, "surface": 30.0},
			{"x": 0.0, "z": 100.0, "width": 4.0, "surface": 30.0}],
			"waterfalls": []}], "lakes": []})
	await _link_send(peer, ["preview_mesh " + dir])
	_check(pv != null and pv._water_mi != null, "the overlay re-wears")
	var off := await _link_send(peer, ["preview_mesh off"])
	_check(off.size() == 1 and off[0] == "ok preview_mesh off (streamed world restored)",
		"off restores")
	_check(pv != null and pv._water_mi == null,
		"the water overlay LEAVES with the drape on off (never leaks to builder mode)")
	# Leave no trace.
	for f in ["height.exr", "bake_manifest.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	StrataLink._preview.queue_free()
	StrataLink._preview = null


## Write a hydrology.json (the export shape WorldExporter writes / valley reads).
func _write_hydrology(dir: String, root: Dictionary) -> void:
	var f := FileAccess.open(dir.path_join("hydrology.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(root))
	f.close()


## Write one scatter cell file (the ScatterExport per-cell shape).
func _write_scatter_cell(dir: String, cx: int, cz: int, props: Array) -> void:
	var f := FileAccess.open(
		dir.path_join("scatter/cell_%d_%d.json" % [cx, cz]), FileAccess.WRITE)
	f.store_string(JSON.stringify(props))
	f.close()


## Write the scatter manifest (the ScatterExport manifest shape the overlay
## reads: format, count, cells:[{cell,file,count}]). sha256 is omitted — the
## throwaway preview never verifies (only the blessed streamer does).
func _write_scatter_manifest(dir: String, total: int, cells: Array) -> void:
	var entries: Array = []
	for c: Array in cells:
		entries.append({"cell": [c[0], c[1]], "file": c[2], "count": c[3], "sha256": ""})
	var f := FileAccess.open(dir.path_join("scatter/manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"format": 1, "cell_size_m": 128.0, "count": total,
		"world": {"size_m": [16384.0, 16384.0], "sea_level_m": 5.0},
		"cells": entries}))
	f.close()


## M6a — the living preview resolves on pause (PLAN_LIVING_PREVIEW §9).
## Two halves, both over the real link + real machinery:
##
## (A) the RESOLVE contract + Walk Here honesty (§6), no streamer needed:
##   wear a drape → Walk Here REFUSES (you cannot walk a photograph) → fire
##   preview_world → the kernel re-tiles to the shape AND _drape_resolved
##   flips → Walk Here now LANDS on the shaped ground (kernel height).
##
## (B) the CONFIRM signal + CROSSFADE + shaped collision (§3), driving a real
##   world_streamer: wear a drape, reshape via preview_world so the kernel
##   re-tiles and the near ring rebuilds; the streamer emits near_ring_settled
##   on the busy->idle edge; strata_link leaves the drape one beat later; the
##   rebuilt cell carries the SHAPED height in real trimesh collision. Half B
##   builds real flora/scatter cells, so it SKIPs honestly when the world
##   assets aren't present (fresh clone / bare CI) — the tile-cache-skip idiom.
func _test_living_preview(peer: StreamPeerTCP) -> void:
	if not Terrain.has_world_tile() or Terrain.kernel == null:
		print("  living preview: SKIP (no kernel or baked tile)")
		return
	# Snapshot the world so the reshapes below restore bit-identically.
	var orig_rec: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/regions/baked_world.json"))
	if not (orig_rec is Dictionary):
		print("  living preview: SKIP (no baked_world.json record)")
		return
	var orig_sea: float = Terrain.sea_level
	# M6a.1 — the distance gate's tunable is registered in every posture.
	_check(Vernier.has("living_preview.resolve_max_dist"),
		"living: the resolve-distance tunable is registered (Vernier)")
	_check(absf(float(Vernier.get_value("living_preview.resolve_max_dist")) - 2500.0) < 0.01,
		"living: the gate default is 2500m from focus")
	# A synthetic export: a flat 42m world, sea at 5m, with the height.exr the
	# drape wears and preview_world re-tiles from.
	var dir := ProjectSettings.globalize_path("user://living_preview_world")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(64, 64, false, Image.FORMAT_RF)
	img.fill(Color(42.0, 0.0, 0.0))
	img.save_exr(dir.path_join("height.exr"))
	var mf := FileAccess.open(dir.path_join("bake_manifest.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify({"world": {
		"size_m": [16384.0, 16384.0], "sea_level_m": 5.0}}))
	mf.close()
	# W4 — the export carries hydrology: the resolve must import it into the
	# LIVE water stack (Terrain.rivers/water_bodies), in memory, pre-bless.
	_write_hydrology(dir, {"format": 1, "sea_level_m": 5.0,
		"rivers": [{"id": "r0", "catchment_m2": 5.0e6, "nodes": [
			{"x": -200.0, "z": 0.0, "width": 3.0, "surface": 40.0},
			{"x": 200.0, "z": 0.0, "width": 9.0, "surface": 35.0}],
			"waterfalls": [{"x": 0.0, "z": 0.0, "drop_m": 6.0}]}],
		"lakes": [{"id": "l0", "x": 500.0, "z": 500.0, "radius": 80.0,
			"surface": 30.0, "depth": 8.0, "outline": []}]})
	var rivers_before: int = Terrain.rivers.size()

	# -- (A) the resolve contract + Walk Here honesty ----------------------
	var worn := await _link_send(peer, ["preview_mesh " + dir])
	_check(worn.size() == 1 and worn[0].begins_with("ok preview_mesh"),
		"living: the drape wears (got %s)" % str(worn))
	_check(StrataLink._preview != null and StrataLink._preview.worn,
		"living: the drape is worn")
	_check(not StrataLink._drape_resolved,
		"living: a fresh drape is UNRESOLVED (the kernel lacks its shape)")
	# Walk Here over an unresolved drape refuses honestly (§6). No player is
	# needed — the guard fires before the player lookup.
	var refuse := await _link_send(peer, ["teleport 100 100"])
	_check(refuse.size() == 1 and refuse[0].begins_with("err resolve first"),
		"living: Walk Here refuses over an unresolved drape (got %s)" % str(refuse))
	# The RESOLVE: preview_world re-tiles the kernel to the 42m shape and marks
	# the drape resolved.
	var resolved := await _link_send(peer, ["preview_world " + dir])
	_check(resolved.size() == 1 and resolved[0].begins_with("ok preview"),
		"living: preview_world resolves (got %s)" % str(resolved))
	# W4 — the resolve imported the export's hydrology into the live stack: the
	# reply names the counts, and Terrain now carries the export's river (with
	# its waterfall) and lake — the SAME records water_bodies builds the real
	# ribbons/lake meshes from, so what the gate reveals below is the game's
	# water. Disk untouched (in memory, like the tile).
	_check(resolved.size() == 1 and resolved[0].contains("water=1r/1l"),
		"W4: the resolve reply carries the imported water counts (got %s)" % str(resolved))
	_check(Terrain.rivers.size() == 1 and String(Terrain.rivers[0].id) == "hyd_r0",
		"W4: the export's river is live in Terrain.rivers (got %d)" % Terrain.rivers.size())
	_check(Terrain.rivers.size() == 1 and (Terrain.rivers[0].falls as Array).size() == 1,
		"W4: the river carries its waterfall record")
	_check(Terrain.rivers.size() == 1 and bool(Terrain.rivers[0].no_sim),
		"W4: preview water is region-tier (no_sim, off the soak digest)")
	_check(Terrain.water_bodies.size() == 1
			and String(Terrain.water_bodies[0].id) == "hyd_l0",
		"W4: the export's lake is live in Terrain.water_bodies (got %d)"
			% Terrain.water_bodies.size())
	_check(absf(Terrain.height(3000.0, 3000.0) - 42.0) < 0.01,
		"living: the kernel now carries the shaped ground (%.2f)" % Terrain.height(3000.0, 3000.0))
	_check(StrataLink._drape_resolved,
		"living: the resolve marks the kernel resolved (Walk Here arms)")
	# Walk Here now LANDS on the shaped ground. A CharacterBody3D player so the
	# body branch runs; the drop height is Terrain.height + 1.5 (~43.5m).
	var pl := CharacterBody3D.new()
	pl.add_to_group("player")
	add_child(pl)
	var land := await _link_send(peer, ["teleport 200 200"])
	_check(land.size() == 1 and land[0].begins_with("ok player"),
		"living: Walk Here lands after a resolve (got %s)" % str(land))
	_check(absf(pl.global_position.y - (Terrain.height(200.0, 200.0) + 1.5)) < 0.01,
		"living: the walker stands on the SHAPED ground (%.2fm)" % pl.global_position.y)

	# -- (B) the DISTANCE GATE: far resolve keeps the chart, near crossfades --
	# The operator's 2026-07-10 M6a verdict (§5): at survey distance the raw
	# resolved world reads as mud, so the chart drape STAYS the face; the
	# resolve still happens underneath (kernel + near ring + collision). Only
	# near the ground does the crossfade fire. Real cells carry real flora —
	# SKIP half B without the world assets, so a bare clone never reds on a
	# missing billboard texture.
	var have_assets := DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path("res://assets/paintings/blooms"))
	if have_assets:
		# Focus OUTSIDE the home-guard/sculpt frame (like preview_world's
		# 3000,3000 probe) so the near cells sit on the flat 42m plateau — the
		# origin cell is shaped by the spawn guard and would read taller.
		pl.global_position = Vector3(3000.0, 0.0, 3000.0)
		var gy := Terrain.height(3000.0, 3000.0)  # the focus ground (~42m)
		# A camera whose distance to that focus the gate reads. Start it at
		# SURVEY distance: 3000m up over the focus, well past the 2500m gate.
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = Vector3(3000.0, gy + 3000.0, 3000.0)
		cam.make_current()
		var streamer: Node3D = load("res://game/world/world_streamer.gd").new()
		add_child(streamer)  # _ready fills the near ring synchronously
		# Let the initial async ring drain so we measure a CLEAN busy->idle
		# edge from the reshape, not the boot fill.
		await _pump_until_settled(streamer, 240)
		var settles := [0]
		streamer.near_ring_settled.connect(func() -> void: settles[0] += 1)
		# Re-wear + reshape THROUGH the link so the gate arms against this
		# streamer (found by group). The kernel is already at 42m from (A); a
		# re-tile still dirties every loaded cell (edited over the whole frame).
		await _link_send(peer, ["preview_mesh " + dir])
		_check(StrataLink._preview.worn, "living: the drape is worn before the resolve")
		await _link_send(peer, ["preview_world " + dir])
		# Drive frames (cooldowns zeroed) until the streamer confirms settled.
		var fired := await _pump_until_signal(streamer, settles, 600)
		_check(fired, "living: near_ring_settled fires after the resolve (§3 confirm)")
		_check(StrataLink._near_ring_confirmed,
			"living: the resolve records the near-ring confirm")
		# THE GATE, FAR: a few frames past the confirm, the drape is STILL worn —
		# at survey distance the chart is the better face, the resolve rode
		# underneath (§5 verdict). No stale-ground crossfade here.
		for i in 8:
			await get_tree().process_frame
		_check(StrataLink._preview.worn,
			"living: FAR resolve keeps the chart worn (survey face stays)")
		_check(StrataLink._drape_resolved,
			"living: the kernel resolved underneath even while the chart stays up")
		# The resolve DID rebuild real ground under the chart — the near cell
		# carries the shaped height in REAL collision (Walk Here works far too).
		var cell := Vector2i(roundi(3000.0 / 128.0), roundi(3000.0 / 128.0))
		var body: Node = streamer._terrain.get(cell)
		_check(body != null, "living: the near cell rebuilt under the far chart")
		if body != null:
			var col := _find_collision_shape(body)
			_check(col != null and col.shape is ConcavePolygonShape3D,
				"living: the rebuilt cell carries trimesh collision")
			if col != null and col.shape is ConcavePolygonShape3D:
				var faces: PackedVector3Array = col.shape.get_faces()
				var maxy := -1e30
				for v in faces:
					maxy = maxf(maxy, v.y)
				_check(faces.size() > 0 and absf(maxy - 42.0) < 1.0,
					"living: the collision sits at the SHAPED height (~42m, got %.2f)" % maxy)
		# THE GATE, DESCEND: drop the camera below the 2500m threshold. The
		# deferred crossfade fires now (the near ring is already confirmed).
		cam.global_position = Vector3(3000.0, gy + 50.0, 3000.0)
		var lifted := false
		for i in 8:
			await get_tree().process_frame
			if not StrataLink._preview.worn:
				lifted = true
				break
		_check(lifted, "living: descending below the gate lifts the chart (crossfade)")
		# THE GATE, CLIMB BACK: rise back to survey — the chart re-wears from the
		# still-current bake (no re-send; the kernel stays resolved).
		cam.global_position = Vector3(3000.0, gy + 3000.0, 3000.0)
		var rewore := false
		for i in 8:
			await get_tree().process_frame
			if StrataLink._preview.worn:
				rewore = true
				break
		_check(rewore, "living: climbing back to survey re-wears the chart (cheap, no re-send)")
		_check(StrataLink._drape_resolved,
			"living: the re-worn chart is still kernel-resolved (Walk Here still lands)")
		# THE TUNABLE gates it: widen resolve_max_dist past the survey distance
		# and the same far camera now reads as 'near' — the chart lifts.
		await _link_send(peer, ["vernier set living_preview.resolve_max_dist 100000"])
		var tuned_lift := false
		for i in 8:
			await get_tree().process_frame
			if not StrataLink._preview.worn:
				tuned_lift = true
				break
		_check(tuned_lift, "living: widening the tunable lifts the far chart (the gate is the knob)")
		await _link_send(peer, ["vernier set living_preview.resolve_max_dist 2500"])
		cam.queue_free()
		streamer.queue_free()
	else:
		print("  living preview (distance gate): SKIP (no world assets)")

	# Teardown: leave the drape, restore the world bit-identically, drop the
	# player, erase the export. The world is exactly as the next test finds it.
	await _link_send(peer, ["preview_mesh off"])
	pl.queue_free()
	# W4 restore: re-read the checkout's own water records off disk (the same
	# door a real import uses) so the preview water leaves no trace, THEN
	# re-wear the original tile (preview_tile seats sea + kernel tiles; the
	# reload already re-inited the kernel against the disk water).
	Terrain._reload_water()
	_check(Terrain.rivers.size() == rivers_before,
		"W4: restore returns the checkout's own rivers (%d, was %d)"
			% [Terrain.rivers.size(), rivers_before])
	_check(Terrain.preview_tile(orig_rec, orig_sea), "living: restore wears the original")
	StrataLink._drape_resolved = false
	if StrataLink._preview != null:
		StrataLink._preview.queue_free()
		StrataLink._preview = null
	for f in ["height.exr", "bake_manifest.json", "hydrology.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## Drive frames while zeroing the streamer's rebuild cooldowns (test speed —
## the 0.8s quiet cooldown is a live-sculpt frame-smoothness knob, not part of
## what we assert), returning once every rebuild queue has drained or the
## frame budget is spent.
func _pump_until_settled(streamer: Node3D, budget: int) -> void:
	for i in budget:
		streamer._quiet_cooldown = 0.0
		streamer._rebuild_cooldown = 0.0
		await get_tree().process_frame
		if streamer._is_near_ring_settled():
			return


## Like _pump_until_settled but stops as soon as the settle COUNTER ticks (the
## near_ring_settled signal fired). Returns whether it fired within budget.
func _pump_until_signal(streamer: Node3D, counter: Array, budget: int) -> bool:
	for i in budget:
		streamer._quiet_cooldown = 0.0
		streamer._rebuild_cooldown = 0.0
		await get_tree().process_frame
		if counter[0] > 0:
			return true
	return false


## First CollisionShape3D under a node (depth-first).
func _find_collision_shape(n: Node) -> CollisionShape3D:
	for child in n.get_children():
		if child is CollisionShape3D:
			return child
		var deep := _find_collision_shape(child)
		if deep != null:
			return deep
	return null


## The camera mirror (engine-viewport M4): `camera` answers the ACTIVE 3D
## camera — position, forward, up, fov, viewport — precisely enough that
## the host's unprojected cursor rays land where the engine draws. Without
## a current camera it errs honestly (never a made-up view). The probe
## plants a camera at a KNOWN transform and pins every reported number.
func _test_camera_verb(peer: StreamPeerTCP) -> void:
	var had_camera := get_viewport().get_camera_3d() != null
	if not had_camera:
		var bare := await _link_send(peer, ["camera"])
		_check(bare.size() == 1 and bare[0] == "err no active 3d camera",
			"camera errs honestly without a current camera (got %s)" % str(bare))
	# A known view: perched at (100, 250, -300), yawed 90° left (fwd = -x,
	# up stays +y), fov 70. looking_at keeps the math out of the probe.
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(100.0, 250.0, -300.0)
	cam.look_at(Vector3(50.0, 250.0, -300.0), Vector3.UP)
	cam.fov = 70.0
	cam.make_current()
	await get_tree().process_frame
	var replies := await _link_send(peer, ["camera"])
	_check(replies.size() == 1 and String(replies[0]).begins_with("ok camera "),
		"camera answers ok (got %s)" % str(replies))
	if replies.size() == 1 and String(replies[0]).begins_with("ok camera "):
		var fields := {}
		for tok in String(replies[0]).trim_prefix("ok camera ").split(" ", false):
			var kv := tok.split("=")
			_check(kv.size() == 2, "camera token is key=value (got '%s')" % tok)
			if kv.size() == 2:
				fields[kv[0]] = kv[1]
		for key in ["pos", "fwd", "up", "fov", "vp"]:
			_check(fields.has(key), "camera reply carries %s=" % key)
		var pos_p: PackedStringArray = String(fields.get("pos", "")).split(",")
		var fwd_p: PackedStringArray = String(fields.get("fwd", "")).split(",")
		var up_p: PackedStringArray = String(fields.get("up", "")).split(",")
		_check(pos_p.size() == 3 and fwd_p.size() == 3 and up_p.size() == 3,
			"camera vectors are x,y,z triples")
		if pos_p.size() == 3 and fwd_p.size() == 3 and up_p.size() == 3:
			var pos := Vector3(float(pos_p[0]), float(pos_p[1]), float(pos_p[2]))
			var fwd := Vector3(float(fwd_p[0]), float(fwd_p[1]), float(fwd_p[2]))
			var up := Vector3(float(up_p[0]), float(up_p[1]), float(up_p[2]))
			_check(pos.distance_to(Vector3(100.0, 250.0, -300.0)) < 0.01,
				"camera pos is the planted position (got %s)" % str(pos))
			_check(fwd.distance_to(Vector3(-1.0, 0.0, 0.0)) < 0.001,
				"camera fwd is -basis.z (got %s)" % str(fwd))
			_check(up.distance_to(Vector3(0.0, 1.0, 0.0)) < 0.001,
				"camera up is basis.y (got %s)" % str(up))
			_check(absf(fwd.length() - 1.0) < 0.001 and absf(up.length() - 1.0) < 0.001,
				"camera fwd/up are unit vectors")
		_check(absf(float(fields.get("fov", "0")) - 70.0) < 0.01,
			"camera fov is the planted 70° (got %s)" % fields.get("fov"))
		var vp_p: PackedStringArray = String(fields.get("vp", "")).split("x")
		_check(vp_p.size() == 2 and int(vp_p[0]) > 0 and int(vp_p[1]) > 0,
			"camera vp is <w>x<h> in pixels (got %s)" % fields.get("vp"))
	# Teardown: the planted camera leaves; without another current camera
	# the verb goes back to the honest error (never a stale mirror).
	cam.queue_free()
	await get_tree().process_frame
	if not had_camera:
		var after := await _link_send(peer, ["camera"])
		_check(after.size() == 1 and after[0] == "err no active 3d camera",
			"camera errs again once the camera leaves (got %s)" % str(after))


## Send commands one per line, then pump frames until every reply lands.
## The naming desk (the gazetteer): resolve/fallback, the records-desk
## schema it rides, and the key-preserving write round trip on a TEMP file
## (the shipped content stays untouched). Content-empty is a first-class
## state — a missing table loads zero names, zero errors, and resolve still
## answers the id.
func _test_names() -> void:
	# Rides the records desk: the kind's {id,name} schema is registered, so
	# `records validate names` judges a name-record by the loader's own rule.
	var sch := Records.schema_for("names")
	_check(int(sch.get("id", -1)) == TYPE_STRING and int(sch.get("name", -1)) == TYPE_STRING,
		"names: the loader registered its {id,name} schema")
	_check(Records.validate_kind("names", {"id": "x", "name": "Y"}) == "",
		"names: a well-formed name-record validates")
	_check(Records.validate_kind("names", {"id": "x"}) != "",
		"names: a name-record missing its name is refused")

	# resolve: the honest fallback to the id itself when a place has no name.
	_check(Names.resolve("no_such_place") == "no_such_place",
		"names: resolve falls back to the id itself")
	_check(not Names.has_name("no_such_place"), "names: an unnamed id has_name=false")

	# The few names valley ships for its own places (content — data/names).
	# A content-empty tree has no gazetteer, so these SKIP honestly.
	if Names.has_name("hyd_l1"):
		_check(Names.resolve("hyd_l1") == "The Aquifer Pool",
			"names: a shipped name resolves (got %s)" % Names.resolve("hyd_l1"))
		_check(Names.kind_of("hyd_l1") == "lake", "names: a shipped name carries its kind")
	else:
		print("  names: SKIP shipped-name checks (no data/names content — content-empty tree)")

	# The write round trip on a TEMP file — the real content stays untouched.
	var tmp := "user://names_test.json"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	# content-empty: a table that isn't there loads zero names, zero errors.
	Names.reload(tmp)
	_check(Names.named_ids().is_empty(), "names: a missing file loads content-empty")
	_check(Names.resolve("hyd_r1") == "hyd_r1",
		"names: content-empty resolve falls back to the id")

	# A validated create...
	var w1 := Names.write("cove_a", "First Cove", "cove", tmp)
	_check(bool(w1.get("ok", false)),
		"names: write creates a validated record (got %s)" % w1.get("error", ""))
	_check(Names.resolve("cove_a") == "First Cove", "names: a written name resolves live")
	_check(Names.kind_of("cove_a") == "cove", "names: a written name keeps its kind")
	# ...then a second, and the first SURVIVES (key-preserving upsert).
	Names.write("cove_b", "Second Cove", "", tmp)
	_check(Names.resolve("cove_a") == "First Cove" and Names.resolve("cove_b") == "Second Cove",
		"names: writing a second entry preserves the first")
	# A rename in place keeps the row's prior kind when the verb omits it.
	Names.write("cove_a", "Renamed Cove", "", tmp)
	_check(Names.resolve("cove_a") == "Renamed Cove" and Names.kind_of("cove_a") == "cove",
		"names: a rename preserves the prior kind")
	_check(Names.named_ids().size() == 2, "names: a rename upserts, never duplicates")
	# Validation refuses an empty name before anything reaches disk.
	_check(not bool(Names.write("cove_c", "   ", "", tmp).get("ok", false)),
		"names: an empty name is refused")

	# contour_status().engaged (docs/PORT_LEDGER.md F4's standing follow-up,
	# closed G2): resolve/has_name/kind_of/named_ids/entries are all ROUTED —
	# assert the posture this boot resolved into, and that an engaged VM's
	# call counter actually climbs (no silent fallback), the same law
	# _test_conditions_contour and _test_hydrology already assert.
	var names_cs: Dictionary = Names.contour_status()
	if bool(names_cs.get("engaged", false)):
		_check(int(names_cs.get("mode", 0)) == 2 and int(names_cs.get("calls", 0)) > 0,
			"names: STRATA_CONTOUR routing ENGAGED by default (native queries earned the counter, no silent fallback)")
		var before3: int = int(Names.contour_status().calls)
		Names.resolve("hyd_l1")
		Names.has_name("hyd_l1")
		Names.kind_of("hyd_l1")
		Names.named_ids()
		Names.entries()
		var after3: int = int(Names.contour_status().calls)
		_check(after3 > before3,
			"names: routed queries answered by the Contour VM (calls %d->%d, no silent fallback)" % [before3, after3])
	else:
		_check((int(names_cs.get("mode", 0)) == 1 or int(names_cs.get("mode", 0)) == -1)
				and int(names_cs.get("calls", -1)) == 0,
			"names: routing off (=0 hatch / kernel-less) — GDScript twin, no silent engage")

	# Restore the LIVE table from the shipped content (other surfaces/tests
	# see the real gazetteer again).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	Names.reload()
	if Names.has_name("hyd_l1"):
		_check(Names.resolve("hyd_l1") == "The Aquifer Pool",
			"names: the live table restored from shipped content")
	else:
		print("  names: SKIP restore-from-shipped (no data/names content — content-empty tree)")


## The naming desk over the link: `names` reads the table, `name <id> <text>`
## writes it (create-or-update). The write touches the shipped file, so the
## test snapshots its bytes and restores them after — a green run leaves the
## worktree byte-identical.
func _test_names_verbs(peer: StreamPeerTCP) -> void:
	var file := ProjectSettings.globalize_path("res://data/names/names.json")
	var had_file := FileAccess.file_exists(file)
	var original := FileAccess.get_file_as_string(file)

	# names: the shipped table, rows tab-separated, fields unit-separated.
	var before := await _link_send(peer, ["names"])
	_check(before.size() == 1 and String(before[0]).begins_with("ok names count="),
		"names: the table answers ok with a count (got %s)" % str(before))
	if had_file:
		_check("hyd_l1" in String(before[0]) and "The Aquifer Pool" in String(before[0]),
			"names: the table carries a shipped named place")
	else:
		print("  names: SKIP shipped-place check (no data/names content — content-empty tree)")

	# name: create-or-update, validated and reloaded; then it reads back.
	var wrote := await _link_send(peer, [
		"name hyd_l7 North Tarn", "names", "name", "name bad_no_text"])
	_check(wrote.size() == 4, "name: replies land (got %d)" % wrote.size())
	if wrote.size() == 4:
		_check(String(wrote[0]) == "ok name hyd_l7 North Tarn",
			"name: a write answers ok with the resolved name (got %s)" % wrote[0])
		_check("hyd_l7" in String(wrote[1]) and "North Tarn" in String(wrote[1]),
			"name: the new name is in the table right after (got %s)" % wrote[1])
		_check(String(wrote[2]) == "err name needs <id> <text>",
			"name: a bare verb errs with its contract line (got %s)" % wrote[2])
		_check(String(wrote[3]) == "err name needs <id> <text>",
			"name: an id with no text errs (got %s)" % wrote[3])
	# The live table saw the write (the verb rebound the gazetteer).
	_check(Names.resolve("hyd_l7") == "North Tarn", "name: the live table reflects the write")

	# Restore the shipped file byte-for-byte and rebind — no test residue.
	# Content-empty tree: the `name` verb above CREATED data/names/names.json
	# (and its dir); remove them so the gate leaves the tree as it found it.
	if had_file:
		var f := FileAccess.open(file, FileAccess.WRITE)
		if f != null:
			f.store_string(original)
			f.close()
	else:
		DirAccess.remove_absolute(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/names"))
	Names.reload()
	_check(Names.resolve("hyd_l7") == "hyd_l7",
		"name: restoring the file returns the gazetteer to shipped content")


## Ghost markers (COLLAB §3c, the deferred G2 piece): `marker set` places a
## named billboard node under current_scene, y-placed on Terrain.height;
## `marker clear` removes it; `clear all` wipes wholesale. Drives the verb
## pair headlessly and asserts the node itself, not just the reply text —
## the discovery test (`_test_link_discovery`) already pins `marker` into
## VERBS/the dispatcher; this pins its BEHAVIOR.
func _test_marker_verbs(peer: StreamPeerTCP) -> void:
	var root := get_tree().current_scene
	var x := 1234.0
	var z := -567.0
	var expect_y: float = Terrain.height(x, z)

	# Bare/short forms err with the contract line, never crash or "unknown".
	var bad := await _link_send(peer, ["marker", "marker set", "marker set only_id",
		"marker set peer_a not_a_number 0.0 Nicco", "marker clear"])
	_check(bad.size() == 5, "marker: bad-arg replies land (got %d)" % bad.size())
	if bad.size() == 5:
		_check(String(bad[0]).begins_with("err marker needs"), "marker: bare verb errs")
		_check(String(bad[1]).begins_with("err marker set needs"), "marker: bare set errs")
		_check(String(bad[2]).begins_with("err marker set needs"), "marker: set with only an id errs")
		_check(String(bad[3]).begins_with("err marker set needs numeric"),
			"marker: non-numeric x/z errs (got %s)" % bad[3])
		_check(String(bad[4]).begins_with("err marker clear needs"), "marker: bare clear errs")

	# set: a peer's ghost lands at (x, Terrain.height(x,z), z) with its label.
	var placed := await _link_send(peer, ["marker set peer_a %.1f %.1f Nicco" % [x, z]])
	_check(placed.size() == 1 and String(placed[0]) == "ok marker set peer_a",
		"marker set: answers ok with the id (got %s)" % str(placed))
	var node := root.get_node_or_null("CollabMarker_peer_a") as Node3D
	_check(node != null, "marker set: the node exists under current_scene")
	if node != null:
		_check(absf(node.global_position.x - x) < 0.01 and absf(node.global_position.z - z) < 0.01,
			"marker set: lands at the requested (x, z)")
		_check(absf(node.global_position.y - expect_y) < 0.01,
			"marker set: y-placed on Terrain.height (got %.2f want %.2f)"
				% [node.global_position.y, expect_y])
		var tag := node.get_node_or_null("Tag") as Label3D
		_check(tag != null and tag.text == "Nicco", "marker set: the Label3D carries the label")

	# set again, same id: MOVES + relabels in place — one node, not two.
	var moved := await _link_send(peer, ["marker set peer_a %.1f %.1f Nicco (afk)" % [x + 10.0, z]])
	_check(moved.size() == 1 and String(moved[0]) == "ok marker set peer_a",
		"marker set (again): still one ok reply (got %s)" % str(moved))
	var again := root.get_node_or_null("CollabMarker_peer_a") as Node3D
	_check(again == node, "marker set (again): re-uses the SAME node (moves, doesn't duplicate)")
	if again != null:
		_check(absf(again.global_position.x - (x + 10.0)) < 0.01, "marker set (again): moved")
		_check((again.get_node("Tag") as Label3D).text == "Nicco (afk)",
			"marker set (again): relabeled")

	# a second peer, then clear one — the other survives untouched.
	await _link_send(peer, ["marker set peer_b 0.0 0.0 Elena"])
	var cleared := await _link_send(peer, ["marker clear peer_a"])
	_check(cleared.size() == 1 and String(cleared[0]) == "ok marker clear peer_a",
		"marker clear: answers ok (got %s)" % str(cleared))
	_check(root.get_node_or_null("CollabMarker_peer_a") == null,
		"marker clear: the node is gone")
	_check(root.get_node_or_null("CollabMarker_peer_b") != null,
		"marker clear: an untouched peer's marker survives")
	# clearing an id that was never set (or already cleared) is a no-op ok,
	# never an error — the idempotent floor `clear all` on a stale roster needs.
	var again_clear := await _link_send(peer, ["marker clear peer_a"])
	_check(again_clear.size() == 1 and String(again_clear[0]) == "ok marker clear peer_a",
		"marker clear: clearing an already-gone id still answers ok")

	# clear all: wholesale wipe, then a repeat is still ok at zero markers.
	var wiped := await _link_send(peer, ["marker clear all"])
	_check(wiped.size() == 1 and String(wiped[0]) == "ok marker clear all",
		"marker clear all: answers ok (got %s)" % str(wiped))
	_check(root.get_node_or_null("CollabMarker_peer_b") == null,
		"marker clear all: every marker is gone")
	var wiped_again := await _link_send(peer, ["marker clear all"])
	_check(wiped_again.size() == 1 and String(wiped_again[0]) == "ok marker clear all",
		"marker clear all: idempotent at zero markers")


## P4 — the cvar registry's link verb (game/dev/vernier.gd + StrataLink's
## `vernier` dispatcher arm). The registry's OWN mechanics (passive
## registration, duplicate refusal, type coercion) are unit-tested
## headless in tests/run_tests.gd; this pins the WIRE + the REAL wiring:
## `list` answers the actual tunables water_field.gd/sea_swell.gd/
## weather.gd registered (not a synthetic fixture set), `get`/`set` name
## one by its registered name, an unknown name errs honestly from BOTH
## (never a silent no-op), and `set` flips the REAL live var — not a
## shadow copy Vernier keeps for itself — with provenance landing "link".
## Each `_link_send` call is awaited to completion before the next is
## sent, so a later assertion never races an earlier command's effect.
func _test_vernier_verb(peer: StreamPeerTCP) -> void:
	var list_r := await _link_send(peer, ["vernier list"])
	_check(list_r.size() == 1 and String(list_r[0]).begins_with("ok vernier list "),
		"vernier list answers ok (got %s)" % str(list_r))
	if list_r.size() == 1:
		var lr := String(list_r[0])
		for want in ["water.fill_channels:bool:", "sea.force_amp:float:",
				"sea.force_surf:float:", "weather.fog_override:float:"]:
			_check(want in lr, "vernier list carries the real wired tunable %s" % want)

	var bad := await _link_send(peer,
		["vernier", "vernier get bogus.name", "vernier set bogus.name 1"])
	_check(bad.size() == 3, "vernier bad-arg replies land (got %d)" % bad.size())
	if bad.size() == 3:
		_check(String(bad[0]) == "err vernier needs list|get <name>|set <name> <value>",
			"a bare vernier verb errs with the contract line")
		_check(String(bad[1]) == "err vernier: no such tunable: bogus.name",
			"vernier get on an unknown name errs honestly")
		_check(String(bad[2]) == "err vernier: no such tunable: bogus.name",
			"vernier set on an unknown name errs honestly (never a silent no-op)")

	var boot := await _link_send(peer, ["vernier get water.fill_channels"])
	_check(boot.size() == 1 and "provenance=boot" in String(boot[0]),
		"a never-touched tunable answers provenance=boot (got %s)" % str(boot))

	var flip_before := WaterField.fill_channels
	var set_r := await _link_send(peer, ["vernier set water.fill_channels on"])
	_check(set_r.size() == 1 and String(set_r[0]) == "ok vernier set water.fill_channels=true",
		"vernier set flips a bool tunable (got %s)" % str(set_r))
	_check(WaterField.fill_channels == true,
		"the REAL WaterField.fill_channels flipped, not a shadow copy")

	var after := await _link_send(peer, ["vernier get water.fill_channels"])
	_check(after.size() == 1 and "provenance=link" in String(after[0]),
		"provenance says link after a `vernier set` (got %s)" % str(after))

	var fset := await _link_send(peer, ["vernier set sea.force_amp 0.42"])
	_check(fset.size() == 1 and String(fset[0]) == "ok vernier set sea.force_amp=0.42",
		"vernier set lands a float tunable (got %s)" % str(fset))
	_check(is_equal_approx(SeaSwell.force_amp, 0.42),
		"the REAL SeaSwell.force_amp flipped")
	var fget := await _link_send(peer, ["vernier get sea.force_amp"])
	_check(fget.size() == 1
			and String(fget[0]) == "ok vernier get sea.force_amp=0.42 type=float provenance=link",
		"vernier get reads the landed value back (got %s)" % str(fget))

	# Leave no residue: restore both to their pre-test state (other
	# probes assume WaterField/SeaSwell sit at their natural defaults).
	await _link_send(peer,
		["vernier set water.fill_channels %s" % ("on" if flip_before else "off")])
	await _link_send(peer, ["vernier set sea.force_amp -1"])


func _link_send(peer: StreamPeerTCP, commands: Array) -> Array:
	for c in commands:
		peer.put_data((str(c) + "\n").to_utf8_buffer())
	var buffer := ""
	for i in 300:
		await get_tree().process_frame
		peer.poll()
		while peer.get_available_bytes() > 0:
			buffer += peer.get_string(peer.get_available_bytes())
		if buffer.count("\n") >= commands.size():
			break
	var out: Array = []
	for line in buffer.split("\n", false):
		out.append(line)
	return out


## A minimal world_streamer stand-in for _test_teleport_defer: it answers the
## near-ring settle gate (_is_near_ring_settled) and carries the settle signal
## _teleport listens on, so the deferral path is driven deterministically —
## no async cell streaming, no world assets (the real streamer's settle edge
## is exercised end-to-end by _test_living_preview).
class _FakeStreamer extends Node:
	signal near_ring_settled
	var settled := false
	func _is_near_ring_settled() -> bool:
		return settled


## Fix 4c: a teleport issued before the near ring has settled must NOT drop the
## walker through the world (during boot / a fresh stream-in the collision mesh
## for the ring may not exist and Terrain.height is stale). _teleport now DEFERS
## the ground-snap to the next near_ring_settled edge instead of snapping onto
## nothing, then lands on the shaped ground. Precedent: commit 911b756 gated a
## risky action behind the settle state — here we complete rather than refuse.
func _test_teleport_defer() -> void:
	var saved_preview: Variant = StrataLink._preview
	StrataLink._preview = null  # let the drape guard pass through to the gate
	var fake := _FakeStreamer.new()
	fake.add_to_group("world_streamer")
	add_child(fake)
	var pl := CharacterBody3D.new()
	pl.add_to_group("player")
	add_child(pl)
	# Park the walker "fallen" so a deferred (not-yet-fired) snap is visible.
	pl.global_position = Vector3(0.0, -9000.0, 0.0)
	# NOT settled: the teleport must defer, not snap onto absent collision.
	fake.settled = false
	var reply := StrataLink._teleport(2000.0, 2000.0)
	_check(reply.begins_with("ok player") and reply.contains("deferred"),
		"teleport before settle defers honestly (got %s)" % reply)
	_check(pl.global_position.y < -1000.0,
		"the deferred teleport did NOT snap the walker yet (no ground under it)")
	# The ring settles: the deferred snap fires, landing on Terrain.height+1.5.
	fake.settled = true
	fake.near_ring_settled.emit()
	var want := Terrain.height(2000.0, 2000.0) + 1.5
	_check(absf(pl.global_position.y - want) < 0.01,
		"the deferred snap lands on the shaped ground after settle (%.2f ~ %.2f)"
			% [pl.global_position.y, want])
	_check(pl.global_position.y > -100.0, "the walker did NOT fall through the world")
	# ALREADY settled: a teleport snaps immediately, exactly as before the fix.
	pl.global_position = Vector3(0.0, -9000.0, 0.0)
	var now := StrataLink._teleport(1500.0, 1500.0)
	_check(now == "ok player -> (%.0f, %.0f)" % [1500.0, 1500.0],
		"teleport with a settled ring snaps immediately (got %s)" % now)
	_check(absf(pl.global_position.y - (Terrain.height(1500.0, 1500.0) + 1.5)) < 0.01,
		"the immediate snap lands on ground")
	pl.queue_free()
	fake.queue_free()
	StrataLink._preview = saved_preview


## The pen override layer (P0 seam fix): pens add meters OVER the blessed
## tile — commit reshapes, restore returns the ground bit-identical, and
## the tile on disk is never written. In-memory only (no save here, so a
## dev checkout's data stays untouched). Skips honestly where the baked
## tile cache doesn't exist (fresh clone / CI).
func _test_tile_override() -> void:
	if not Terrain.has_world_tile():
		print("  tile override: SKIP (no baked tile cache)")
		return
	var p := Vector2(1500.0, -1500.0)
	var before: float = Terrain.height(p.x, p.y)
	var snap: Image = Terrain.snapshot_tile_override()
	_check(snap != null, "override snapshot exists once a tile is loaded")
	var painted: Rect2 = Terrain.paint_tile_override(p, 200.0, 5.0)
	_check(painted.size != Vector2.ZERO, "override paint returns its rect")
	_check(Terrain.height(p.x, p.y) == before,
		"paint alone does not reshape (commit does)")
	Terrain.commit_tile_override(painted)
	var lifted: float = Terrain.height(p.x, p.y) - before
	_check(absf(lifted - 5.0) < 0.8,
		"commit raises the ground ~5m (got %.2fm)" % lifted)
	Terrain.restore_tile_override(snap)
	_check(Terrain.height(p.x, p.y) == before,
		"restore returns bit-identical ground")


## The auto-preview crash (2026-07-08): re-tiling the live kernel while
## worker threads sample it — set_tiles now swaps atomically inside the
## kernel, so this hammer must run clean. (Before the fix this was a
## torn-Ref/vector race: intermittent SIGSEGV inside tile_blend.)
func _test_kernel_retile_race() -> void:
	if Terrain.kernel == null or not Terrain.has_world_tile():
		print("  kernel retile race: SKIP (no kernel or tile)")
		return
	var snap: Image = Terrain.snapshot_tile_override()
	var stop := [false]
	var task := WorkerThreadPool.add_task(func () -> void:
		while not stop[0]:
			var block := Terrain.height_block(-2000.0, -2000.0, 40.0, 32, 32)
			if block.size() != 1024:
				stop[0] = true
	)
	# Main thread: re-tile the live kernel as fast as the pen can.
	for i in 120:
		Terrain.commit_tile_override(
			Terrain.paint_tile_override(Vector2(900.0, 900.0), 150.0, 0.05))
	stop[0] = true
	WorkerThreadPool.wait_for_task_completion(task)
	Terrain.restore_tile_override(snap)
	_check(true, "kernel survives 120 live re-tiles under worker sampling")


## Ground-relative placement (the regeneration hazard, valley half):
## CellRecords.add stores ground_dy (height above the ground at placement),
## seat_y rides the CURRENT ground + dy after the terrain regenerates, and
## legacy absolute-Y records migrate opportunistically on their next save.
## Skips honestly where the baked tile cache doesn't exist (fresh clone/CI).
## The map (the orbit map, 2026-07-08): M borrows the view — open frames
## the tile on the shared OrbitRig and freezes the player; the camera
## carries the chart air (fogs exempted, ambient floor for midnight) as a
## RENDERING override only — the weather sim never hears about it; close
## returns the hand. Streaming follows the map only when zoomed in close.
## DATA-ARMOR (audit 2026-07-08): a corrupt placed-object file must not
## crash the boot or silently vanish placements — the bad file is kept
## aside as *.corrupt, records that parse survive, a warning is surfaced;
## and saves are atomic (temp + rename, never truncate-in-place).
func _test_cell_records_armor() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CellRecords.DIR))
	var bad: String = CellRecords.DIR + "/cell_900_900.json"
	var mixed: String = CellRecords.DIR + "/cell_901_900.json"
	var good: String = CellRecords.DIR + "/cell_902_900.json"
	_write_file(bad, "[{\"kit\": \"crate\", \"x\": 1")  # truncated mid-write
	_write_file(mixed, JSON.stringify([
		{"kit": "crate", "x": 1.0, "y": 2.0, "z": 3.0, "yaw": 0.0},
		{"oops": true}]))  # one good record, one that fails validation
	_write_file(good, JSON.stringify([
		{"kit": "crate", "x": 115456.0, "y": 2.0, "z": 115200.0, "yaw": 0.0}]))

	# A fresh CellRecords node walks the REAL boot path over the planted
	# files (the autoload booted before they existed).
	var cr: Node = load("res://game/world/cell_records.gd").new()
	add_child(cr)
	_check(cr.records(Vector2i(900, 900)).is_empty(),
		"corrupt cell boots empty (no crash)")
	_check(not FileAccess.file_exists(bad),
		"corrupt file moved out of the save path")
	_check(FileAccess.file_exists(bad + ".corrupt"),
		"corrupt file kept aside as .corrupt")
	_check(cr.records(Vector2i(901, 900)).size() == 1,
		"records that parse survive a bad sibling")
	_check(FileAccess.file_exists(mixed + ".corrupt"),
		"lossy read preserves the original aside")
	_check(cr.load_warnings.size() == 2,
		"warnings surfaced for both bad files (got %d)" % cr.load_warnings.size())

	# Atomic save: adding to a loaded cell rewrites via temp + rename and
	# leaves no temp file behind.
	cr.add(Vector3(902 * 128.0, 5.0, 900 * 128.0), "test_kit", 0.0, 1.0)
	_check(not FileAccess.file_exists(good + ".tmp"), "no temp file left behind")
	var reread: Variant = JSON.parse_string(FileAccess.get_file_as_string(good))
	_check(reread is Array and (reread as Array).size() == 2,
		"atomic save landed both records")

	remove_child(cr)
	cr.free()
	for p: String in [bad, bad + ".corrupt", mixed, mixed + ".corrupt",
			good, good + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## DATA-ARMOR (audit 2026-07-08): the Strata importer must refuse an
## export whose frame doesn't match the game's world frame — exit nonzero,
## both sizes named, nothing written. A matching frame still imports.
## Runs the real importer as a subprocess against a synthetic export.
func _test_import_frame_refusal() -> void:
	var world_abs: String = ProjectSettings.globalize_path("user://mismatch_world")
	var out_abs: String = ProjectSettings.globalize_path("user://mismatch_out")
	DirAccess.make_dir_recursive_absolute(world_abs)
	DirAccess.make_dir_recursive_absolute(out_abs)
	var img := Image.create(8, 8, false, Image.FORMAT_RF)
	if img.save_exr(world_abs.path_join("height.exr")) != OK:
		print("  import frame refusal: SKIP (no EXR saver in this binary)")
		return
	var sha := FileAccess.get_sha256(world_abs.path_join("height.exr"))
	var project := ProjectSettings.globalize_path("res://")

	_write_file("user://mismatch_world/bake_manifest.json", JSON.stringify({
		"name": "mismatch_test", "files": {"height.exr": sha},
		"world": {"size_m": [2048.0, 2048.0], "sea_level_m": 0.0}}))
	var r := _run_importer(world_abs, out_abs, project)
	_check(int(r.code) != 0, "mismatched import exits nonzero (got %s)" % r.code)
	_check("2048" in String(r.out) and "16384" in String(r.out),
		"refusal names both sizes (got: %s)" % String(r.out).substr(0, 200))
	_check(not FileAccess.file_exists(out_abs.path_join("baked_world.exr")),
		"refused import writes nothing")

	_write_file("user://mismatch_world/bake_manifest.json", JSON.stringify({
		"name": "mismatch_test", "files": {"height.exr": sha},
		"world": {"size_m": [16384.0, 16384.0], "sea_level_m": 0.0}}))
	r = _run_importer(world_abs, out_abs, project)
	_check(int(r.code) == 0, "matching import exits 0 (got %s: %s)" % [
		r.code, String(r.out).substr(0, 300)])
	_check(FileAccess.file_exists(out_abs.path_join("baked_world.exr")),
		"matching import writes the scratch tile")

	for p: String in ["user://mismatch_world/height.exr",
			"user://mismatch_world/bake_manifest.json",
			"user://mismatch_out/baked_world.exr",
			"user://mismatch_out/baked_world.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Run tools/strata/import_world.gd headless against an export dir, every
## output redirected to a scratch dir (TILE_OUT) — the live tile, biome
## map, and sea level stay untouched. Returns {code, out}.
func _run_importer(world_abs: String, out_abs: String, project: String) -> Dictionary:
	var output: Array = []
	var code := OS.execute("/bin/sh", ["-c",
		"STRATA_WORLD='%s' TILE_OUT='%s' '%s' --headless --path '%s' -s res://tools/strata/import_world.gd 2>&1" % [
			world_abs, out_abs, OS.get_executable_path(), project]],
		output, true)
	return {"code": code, "out": "\n".join(PackedStringArray(output))}


func _write_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_map() -> void:
	# A minimal player: body + the camera-rig chain _close re-seats.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var cam_rig := Node3D.new()
	cam_rig.name = "CameraRig"
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var pcam := Camera3D.new()
	pcam.name = "Camera3D"
	arm.add_child(pcam)
	cam_rig.add_child(arm)
	player.add_child(cam_rig)
	add_child(player)
	var wx_before: String = Weather.state
	var fog_before: float = Weather.fog_amount()
	MapScreen._open()
	_check(MapScreen.active, "map opens")
	_check(not player.is_physics_processing(), "map freezes the player")
	_check(MapScreen._rig.distance > 0.0, "map frames at a real distance")
	var env: Environment = MapScreen._cam.environment
	_check(env != null, "map camera carries its own air")
	if env != null:
		_check(not env.volumetric_fog_enabled, "chart air: no volumetric murk")
		_check(env.fog_density < 0.0002, "chart air: fog thinned to a long fade")
		_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR,
			"chart air: ambient floor set")
	_check(Weather.state == wx_before, "weather sim untouched by the map")
	_check(is_equal_approx(Weather.fog_amount(), fog_before),
		"fog sim untouched by the map (exemption is rendering-only)")
	_check(not MapScreen.wants_streaming(),
		"tile framing: the quadtree carries the view")
	MapScreen._rig.distance = 300.0
	_check(MapScreen.wants_streaming(), "zoomed close: cells stream at the focus")
	MapScreen._close()
	_check(not MapScreen.active, "map closes")
	_check(player.is_physics_processing(), "close returns the hand")
	player.queue_free()


## The map's RMB fast travel must land where you CLICKED, not a kilometre
## past it. The world is a baked 16384m tile whose ground stands hundreds of
## metres above y=0, and the map's orbit camera is steeply pitched — so the
## old landing (intersect the ray with the flat y=0 plane) drifted far
## downrange over any elevated terrain. MapScreen.ray_to_terrain marches the
## real height field to the SURFACE instead. Driven through a real Camera3D
## (project_ray_* end to end) over a synthetic flat-but-elevated field, so
## the ground truth is analytic: the ray meets the plane y=H at one point.
func _test_map_travel() -> void:
	const H := 300.0  # a flat terrain lifted 300m — the tile is no lowland
	var sampler := func(_x: float, _z: float) -> float: return H
	var cam := Camera3D.new()
	add_child(cam)  # under the root viewport: project_ray_* needs the frame
	# Seat it like the orbit rig: high and steeply pitched over the tile.
	var target := Vector3(0.0, H, 0.0)
	var az := 0.7
	var el := 0.7  # ~40deg above the ground plane — the chart look
	var dist := 9000.0
	cam.global_position = target + Vector3(
		dist * cos(el) * sin(az), dist * sin(el), dist * cos(el) * cos(az))
	cam.look_at(target, Vector3.UP)
	await get_tree().process_frame  # let the transform settle before ray casts

	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	# An off-centre pixel: a genuine unproject, not just a look at the target.
	var px := vp * 0.5 + Vector2(220.0, -140.0)
	var org := cam.project_ray_origin(px)
	var dir := cam.project_ray_normal(px).normalized()
	_check(dir.y < -0.001, "map travel: the test ray points down at the ground")

	# Analytic truth: where this ray crosses the plane y=H.
	var t_surface := (org.y - H) / -dir.y
	var truth := org + dir * t_surface
	# What the OLD landing did: intersect the flat y=0 plane instead.
	var t_zero := org.y / -dir.y
	var plane0 := org + dir * t_zero

	var hit: Vector3 = MapScreen.ray_to_terrain(org, dir, sampler)
	_check(hit != Vector3.INF, "map travel: the ray finds the surface")
	if hit != Vector3.INF:
		_check(absf(hit.y - H) < 1.0, "map travel: the hit sits ON the ground (y=H)")
		var err := Vector2(hit.x - truth.x, hit.z - truth.z).length()
		_check(err < 2.0,
			"map travel: surface hit lands where clicked (%.2fm off)" % err)
		# The bug this fixes: the y=0 plane drifted the drop far downrange.
		# Over 300m of elevation at this pitch that is hundreds of metres —
		# assert the fix beats it by a wide margin, so a regression that
		# reinstates the plane fails loudly.
		var drift := Vector2(plane0.x - truth.x, plane0.z - truth.z).length()
		_check(drift > 100.0,
			"map travel: the retired y=0 plane drifted %.0fm (the bug)" % drift)
		_check(err < drift * 0.1,
			"map travel: the surface march beats the plane by 10x+")
	# A ray pointing UP out of the world finds no ground (INF, plane fallback).
	_check(MapScreen.ray_to_terrain(org, Vector3(0.0, 1.0, 0.0), sampler) == Vector3.INF,
		"map travel: a skyward ray finds no surface")
	cam.queue_free()


## THE STUCK POSTURE (Mission V2): after a bless the builder must land in a
## ground-adjacent World view that WASD moves — not stranded at the orbit's
## whole-tile framing altitude (~13km), where "World" reads as a second map
## screen and M just toggles between two whole-world views. The root cause:
## entering orbit (frame_tile) overwrites the fly camera's position with the
## tile ride and the orbit _process re-seats it every frame, so leaving orbit
## could not "return the fly camera where it stands" — it left it in the sky.
## This pins the three ways out of orbit all land ground-adjacent, and M
## toggles cleanly. Fails on baseline: the fly→orbit→fly restore and the
## spawn-less bless both stranded the camera at the tile-framing altitude.
func _test_bless_posture() -> void:
	if not Terrain.has_world_tile():
		print("  bless posture: SKIP (no baked tile cache)")
		return
	# Ground-adjacent means a survey crane (~60m); the orbit tile frame is
	# ~13km up. 500m is the honest boundary between the two.
	const GROUND_ADJACENT := 500.0
	var frame_alt: float = Terrain.world_tile_size()  # the ~13km strand, roughly

	# The full player rig (the _test_map shape): _enter/_exit re-seat it.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var cam_rig := Node3D.new()
	cam_rig.name = "CameraRig"
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var pcam := Camera3D.new()
	pcam.name = "Camera3D"
	arm.add_child(pcam)
	cam_rig.add_child(arm)
	player.add_child(cam_rig)
	add_child(player)
	# Seat the player on a recorded-spawn-agnostic spot with real ground.
	player.global_position = Vector3(0.0, Terrain.height(0.0, 0.0) + 1.2, 0.0)

	Toolkit._enter()  # fly camera live over the player (survey crane)
	_check(Toolkit.active and not Toolkit.orbit, "toolkit enters in fly")
	var fly_alt := Toolkit._cam.global_position.y - Terrain.height(
		Toolkit._cam.global_position.x, Toolkit._cam.global_position.z)
	_check(fly_alt < GROUND_ADJACENT, "fly boot is ground-adjacent (%.0fm)" % fly_alt)

	# (A) The fly→orbit→fly peek: glance at the whole tile, come back where you
	# stood. Baseline lost the pose (orbit clobbered it, nothing restored it)
	# and left the camera up at the tile-framing altitude.
	var stood := Toolkit._cam.global_position
	Toolkit.set_view_mode(true)  # orbit: the camera rides ~13km up
	await get_tree().process_frame
	await get_tree().process_frame
	var orbit_alt := Toolkit._cam.global_position.y - Terrain.height(
		Toolkit._cam.global_position.x, Toolkit._cam.global_position.z)
	_check(orbit_alt > frame_alt * 0.3,
		"orbit rides at the whole-tile altitude (%.0fm)" % orbit_alt)
	Toolkit.set_view_mode(false)  # view fly: must return to where we stood
	await get_tree().process_frame
	var back := Toolkit._cam.global_position
	_check(back.distance_to(stood) < 5.0,
		"leaving orbit returns the fly camera where it stood (%.1fm off)"
		% back.distance_to(stood))
	var world_alt := back.y - Terrain.height(back.x, back.z)
	_check(world_alt < GROUND_ADJACENT,
		"World view is ground-adjacent after the peek (%.0fm, not the sky)" % world_alt)

	# (B) THE SPAWN-LESS BLESS: reload_world adopts the tile and reseat finds no
	# recorded spawn (a content-empty or spawn-less world), so nothing is
	# deferred — yet leaving orbit must STILL land ground-adjacent, never the
	# strand. Guard the spawn record (gitignored, regenerable) and put it back.
	var spawn_path: String = Terrain.SPAWN_RECORD_PATH
	var had_spawn := FileAccess.file_exists(spawn_path)
	var spawn_bytes := FileAccess.get_file_as_bytes(spawn_path) if had_spawn \
		else PackedByteArray()
	if had_spawn:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(spawn_path))
	_check(not (Terrain.recorded_spawn() is Vector2),
		"the spawn-less precondition holds (no recorded spawn)")
	Toolkit.set_view_mode(true)  # back into orbit (the shaping viewer posture)
	await get_tree().process_frame
	await get_tree().process_frame
	var reloaded := Terrain.reload_world()  # the in-session-bless verb
	var reseated := Toolkit.reseat_after_bless()  # returns false: no spawn
	_check(reloaded == "reloaded" and not reseated,
		"spawn-less bless: tile adopted, nothing to reseat over")
	Toolkit.set_view_mode(false)  # view fly (the engageBuilderPosture delta)
	await get_tree().process_frame
	var bpos := Toolkit._cam.global_position
	var bless_alt := bpos.y - Terrain.height(bpos.x, bpos.z)
	_check(not Toolkit.orbit and bless_alt < GROUND_ADJACENT,
		"spawn-less bless lands a ground-adjacent World view (%.0fm, not %.0fm sky)"
		% [bless_alt, orbit_alt])
	# Restore the guarded spawn record.
	if had_spawn:
		var f := FileAccess.open(spawn_path, FileAccess.WRITE)
		f.store_buffer(spawn_bytes)
		f.close()

	# (C) The World view is a MOVABLE fly camera: a manual step sticks (the
	# orbit rig is no longer clobbering _cam every frame — the classic stuck
	# cause). In fly, _process drives rotation + WASD only; a nudge holds.
	var pre_move := Toolkit._cam.global_position
	Toolkit._cam.global_position += Vector3(40.0, 0.0, 0.0)
	await get_tree().process_frame
	_check(Toolkit._cam.global_position.distance_to(pre_move) > 1.0,
		"fly camera holds a move — not clobbered by the orbit rig")

	# (D) M toggles map↔world cleanly: the map is the whole-tile framing; the
	# World view it returns to is NOT.
	MapScreen._open()
	await get_tree().process_frame
	_check(MapScreen.active, "M opens the map")
	_check(MapScreen._rig.distance > frame_alt * 0.5,
		"the map is the whole-tile framing (%.0fm)" % MapScreen._rig.distance)
	MapScreen._close()
	await get_tree().process_frame
	_check(not MapScreen.active, "M closes the map")
	var wpos := Toolkit._cam.global_position
	var closed_alt := wpos.y - Terrain.height(wpos.x, wpos.z)
	_check(closed_alt < GROUND_ADJACENT,
		"closing M returns to the ground-adjacent World view, not the map (%.0fm)"
		% closed_alt)

	# Teardown: hand the world back, leave no player behind.
	Toolkit.set_view_mode(false)
	Toolkit.active = false
	Toolkit.set_process(false)
	player.remove_from_group("player")
	player.queue_free()


## The Esc precedence (TICKET: Esc in the embedded pane must not pop the
## Campfire). PauseMenu._esc_action is pure, so both paths test without
## live key events: standalone Esc TOGGLEs the save/quit menu; the pane
## RELEASEs the pointer to Strata's chrome instead. Higher-precedence
## states (no player, Toolkit flying, map open) win first, in both postures.
func _test_pause_esc_routing() -> void:
	var A := PauseMenu.EscAction
	# Standalone (own window / shipped game): Esc opens the Campfire.
	_check(PauseMenu._esc_action(true, false, false, false) == A.TOGGLE,
		"standalone Esc toggles the pause menu")
	# Embedded in Strata's pane: Esc releases the pointer, never the menu.
	_check(PauseMenu._esc_action(true, false, false, true) == A.RELEASE,
		"embedded pane Esc releases the pointer, not the menu")
	# No player is the title screen — Esc is ignored in either posture.
	_check(PauseMenu._esc_action(false, false, false, false) == A.IGNORE,
		"title screen ignores Esc (standalone)")
	_check(PauseMenu._esc_action(false, false, false, true) == A.IGNORE,
		"title screen ignores Esc (embedded)")
	# The Toolkit owns Esc while flying — even embedded (its own release wins).
	_check(PauseMenu._esc_action(true, true, false, false) == A.IGNORE,
		"Toolkit owns Esc while flying (standalone)")
	_check(PauseMenu._esc_action(true, true, false, true) == A.IGNORE,
		"Toolkit owns Esc while flying (embedded)")
	# The map closes first, before either the menu or the pane release.
	_check(PauseMenu._esc_action(true, false, true, false) == A.CLOSE_MAP,
		"open map closes first (standalone)")
	_check(PauseMenu._esc_action(true, false, true, true) == A.CLOSE_MAP,
		"open map closes first (embedded)")


## TICKET (take 2): `--embedded` doesn't survive to OS.get_cmdline_args()
## inside the real pane, so Toolkit.embedded_pane() now trusts the display
## server's own name first. Both injectable params are exercised so the
## posture is provable without a live embedded boot.
func _test_embedded_pane_posture() -> void:
	_check(Toolkit.embedded_pane("embedded", PackedStringArray()),
		"display server name \"embedded\" reads as the pane, even with no args")
	_check(not Toolkit.embedded_pane("macOS", PackedStringArray()),
		"standalone desktop (\"macOS\") is not the pane")
	_check(not Toolkit.embedded_pane("headless", PackedStringArray()),
		"a headless probe (\"headless\") is not the pane")
	_check(Toolkit.embedded_pane("macOS", PackedStringArray(["--embedded"])),
		"the --embedded arg still counts, as a harmless OR")


func _test_placement_reseat() -> void:
	if not Terrain.has_world_tile():
		print("  placement reseat: SKIP (no baked tile cache)")
		return
	var x := 900.0
	var z := -900.0
	var cell: Vector2i = CellRecords.cell_of(Vector3(x, 0.0, z))
	var pre_count: int = CellRecords.records(cell).size()
	var h0: float = Terrain.height(x, z)
	CellRecords.add(Vector3(x, h0 + 0.25, z), "test_kit", 0.0, 1.0)
	var rec: Dictionary = CellRecords.records(cell).back()
	_check(rec.has("ground_dy"), "placed record carries ground_dy")
	_check(absf(float(rec.get("ground_dy", -99.0)) - 0.25) < 0.001,
		"ground_dy is the height above the ground at placement")
	# A legacy record (absolute Y only, pre-ground_dy) rides its stored Y...
	var legacy := {"kit": "test_kit", "x": x + 3.0, "y": h0 + 1.0, "z": z + 3.0,
		"yaw": 0.0, "scale": 1.0}
	_check(CellRecords.seat_y(legacy) == h0 + 1.0, "legacy record seats at stored Y")
	# ...and gains its anchor the next time the cell saves anyway.
	CellRecords.records(cell).append(legacy)
	CellRecords.add(Vector3(x, h0, z), "test_kit", 0.0, 1.0)  # any save-through
	_check(legacy.has("ground_dy") and \
		absf(float(legacy.get("ground_dy", -99.0)) \
			- (h0 + 1.0 - Terrain.height(x + 3.0, z + 3.0))) < 0.001,
		"legacy record migrates ground_dy on its cell's next save")
	# Regenerate the ground: raise it ~5m under the placement and re-seat.
	var snap: Image = Terrain.snapshot_tile_override()
	Terrain.commit_tile_override(Terrain.paint_tile_override(Vector2(x, z), 200.0, 5.0))
	var h1: float = Terrain.height(x, z)
	_check(absf((h1 - h0) - 5.0) < 0.8, "ground rose ~5m (got %.2fm)" % (h1 - h0))
	_check(absf(CellRecords.seat_y(rec) - (h1 + 0.25)) < 0.001,
		"record seats on the NEW ground + dy (%.2f vs %.2f)"
			% [CellRecords.seat_y(rec), h1 + 0.25])
	Terrain.restore_tile_override(snap)
	# Leave no trace: pop the test records and the cell file they created.
	CellRecords.remove_last(cell)
	CellRecords.remove_last(cell)
	CellRecords.remove_last(cell)
	if CellRecords.records(cell).size() == pre_count and pre_count == 0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]))


## Undo v2 (audit R3) — the pens' region mementos. layer_region carves out
## just the painted rect (tile RECTS, not whole tiles: a bounded stack of
## strokes stays memory-flat), and restore_layer_region blits it back. The
## inverse-of-inverse identity for the three paint layers: capture BEFORE,
## mutate, capture AFTER, restore before -> bit-identical to the original,
## restore after -> the mutation returns. In-memory only (never saved), and
## the original is restored last, so the checkout's layers are untouched.
func _test_layer_region() -> void:
	# EDITS layer: always present (the sculpt edit layer).
	var wr := Rect2(480.0, 480.0, 240.0, 240.0)
	var orig_e: PackedByteArray = Terrain.layer_region("edits", wr).img.get_data()
	var before_e: Dictionary = Terrain.layer_region("edits", wr)
	Terrain.apply_brush(Vector3(600.0, 0.0, 600.0), 80.0, 6.0)
	var after_e: Dictionary = Terrain.layer_region("edits", wr)
	_check(after_e.img.get_data() != orig_e, "apply_brush changes the edits region")
	Terrain.restore_layer_region(before_e)
	_check(Terrain.layer_region("edits", wr).img.get_data() == orig_e,
		"restore(before) returns the edits region bit-identical")
	Terrain.restore_layer_region(after_e)
	_check(Terrain.layer_region("edits", wr).img.get_data() == after_e.img.get_data(),
		"restore(after) re-applies the edits mutation")
	Terrain.restore_layer_region(before_e)  # leave the checkout's layer clean

	# OVERRIDE layer: only with a baked world tile loaded.
	if Terrain.has_world_tile():
		var pre := Terrain.snapshot_tile_override()  # ensures the layer exists
		var orig_o: PackedByteArray = Terrain.layer_region("override", wr).img.get_data()
		var before_o: Dictionary = Terrain.layer_region("override", wr)
		Terrain.paint_tile_override(Vector2(600.0, 600.0), 80.0, 5.0)
		var after_o: Dictionary = Terrain.layer_region("override", wr)
		_check(after_o.img.get_data() != orig_o, "paint changes the override region")
		Terrain.restore_layer_region(before_o)
		_check(Terrain.layer_region("override", wr).img.get_data() == orig_o,
			"restore(before) returns the override region bit-identical")
		Terrain.restore_layer_region(after_o)
		_check(Terrain.layer_region("override", wr).img.get_data() == after_o.img.get_data(),
			"restore(after) re-applies the override mutation")
		Terrain.restore_layer_region(before_o)
		Terrain.restore_tile_override(pre)  # full clean-up, override untouched
	else:
		print("  layer region: override sub-check SKIP (no baked tile)")

	# BIOME layer: only with a biome index map.
	if Terrain._biome_img != null:
		var orig_b: PackedByteArray = Terrain.layer_region("biome", wr).img.get_data()
		var before_b: Dictionary = Terrain.layer_region("biome", wr)
		var idx := (Terrain.biome_at(600.0, 600.0) + 1) % Terrain.biomes.size()
		Terrain.paint_biome_index(600.0, 600.0, 80.0, idx)
		var after_b: Dictionary = Terrain.layer_region("biome", wr)
		_check(after_b.img.get_data() != orig_b, "paint changes the biome region")
		Terrain.restore_layer_region(before_b)
		_check(Terrain.layer_region("biome", wr).img.get_data() == orig_b,
			"restore(before) returns the biome region bit-identical")
		Terrain.restore_layer_region(after_b)
		_check(Terrain.layer_region("biome", wr).img.get_data() == after_b.img.get_data(),
			"restore(after) re-applies the biome mutation")
		Terrain.restore_layer_region(before_b)  # leave the biome map clean
	else:
		print("  layer region: biome sub-check SKIP (no biome map)")


## Undo v2 (audit R3) — the bounded command stack itself, on synthetic
## actions (label + undo/redo Callables). Undo pops newest-first and pushes
## to the redo stack; a fresh push forks the timeline (redo cleared); the
## stack is bounded to CAP and the oldest drops off the bottom; empty
## undo/redo are safe no-ops.
func _test_toolkit_history() -> void:
	ToolkitHistory.clear()
	var log: Array[String] = []
	var mk := func(name: String) -> Dictionary:
		return {"label": name,
			"undo": func() -> void: log.append("-" + name),
			"redo": func() -> void: log.append("+" + name)}
	ToolkitHistory.push(mk.call("a"))
	ToolkitHistory.push(mk.call("b"))
	ToolkitHistory.push(mk.call("c"))
	_check(ToolkitHistory.depth() == 3, "three actions on the stack")
	_check(ToolkitHistory.peek_undo_label() == "c", "peek names the newest action")
	_check(ToolkitHistory.undo() and log[-1] == "-c", "undo pops the newest first")
	_check(ToolkitHistory.undo() and log[-1] == "-b", "undo walks back")
	_check(ToolkitHistory.can_redo() and ToolkitHistory.peek_redo_label() == "b",
		"an undone action is redoable")
	_check(ToolkitHistory.redo() and log[-1] == "+b", "redo re-applies it")
	# A fresh push forks the timeline — the redo of c is gone.
	ToolkitHistory.push(mk.call("d"))
	_check(not ToolkitHistory.can_redo(), "a new action clears the redo stack")
	_check(ToolkitHistory.depth() == 3, "the stack is a, b, d")
	# Empty-stack honesty.
	ToolkitHistory.clear()
	_check(not ToolkitHistory.undo() and not ToolkitHistory.redo(),
		"undo/redo on an empty stack are safe no-ops")
	# Bounded: the oldest drops when the cap is reached.
	for i in ToolkitHistory.CAP + 5:
		ToolkitHistory.push(mk.call("f%d" % i))
	_check(ToolkitHistory.depth() == ToolkitHistory.CAP,
		"the stack is bounded to CAP (got %d)" % ToolkitHistory.depth())
	var steps := 0
	while ToolkitHistory.undo():
		steps += 1
	_check(steps == ToolkitHistory.CAP, "undo walks back exactly CAP steps, no more")
	ToolkitHistory.clear()


## Undo v2 (audit R3) — the cross-tool footgun dies BY CONSTRUCTION. The
## old Z dispatch fell through to CellRecords.remove_last, so Z in biome
## mode silently deleted a placed object. Now undo pops the last ACTION off
## the shared stack, never the current mode's guess: paint a biome stroke,
## press Z, and the biome reverts while every placement lives — in ANY tool,
## and on an empty stack Z touches nothing. The biome stroke's inverse-of-
## inverse identity rides along.
func _test_undo_footgun() -> void:
	ToolkitHistory.clear()
	# A placement that must survive every Z below (a far synthetic cell).
	var px := 707.0 * 128.0
	var pz := 707.0 * 128.0
	var cell: Vector2i = CellRecords.cell_of(Vector3(px, 0.0, pz))
	var pre: int = CellRecords.records(cell).size()
	CellRecords.add(Vector3(px, Terrain.height(px, pz), pz), "test_kit", 0.0, 1.0)
	_check(CellRecords.records(cell).size() == pre + 1, "the test placement lands")

	if Terrain._biome_img != null:
		var b := Vector2(1200.0, 1200.0)
		var before_i: int = Terrain.biome_at(b.x, b.y)
		var before_img: PackedByteArray = Terrain._biome_img.get_data()
		Toolkit._tool = Toolkit.Tool.BIOME
		Toolkit._biome_index = (before_i + 1) % Terrain.biomes.size()
		Toolkit._macro_radius = 120.0
		var d0 := ToolkitHistory.depth()
		Toolkit._biome_paint_at(Vector3(b.x, 0.0, b.y))
		_check(Terrain.biome_at(b.x, b.y) == Toolkit._biome_index,
			"biome pen paints the picked index")
		Toolkit._commit_biome_stroke()  # stroke release: pushes the action
		_check(ToolkitHistory.depth() == d0 + 1, "a biome stroke pushes ONE action")
		var painted: int = Toolkit._biome_index
		# THE footgun scenario: Z while in biome mode. The old code deleted
		# the placement; the stack pops the biome action instead.
		Toolkit._undo()
		_check(CellRecords.records(cell).size() == pre + 1,
			"Z in biome mode never deletes a placement (footgun dead by construction)")
		_check(Terrain.biome_at(b.x, b.y) == before_i, "Z reverts the biome stroke")
		_check(Terrain._biome_img.get_data() == before_img,
			"undo returns a bit-identical index map")
		# Shift+Z re-applies it; then undo back to leave the map clean.
		Toolkit._redo()
		_check(Terrain.biome_at(b.x, b.y) == painted, "redo re-applies the biome stroke")
		Toolkit._undo()
		Toolkit._biome_unsaved = false
		ToolkitHistory.clear()
	else:
		print("  undo footgun: biome sub-check SKIP (no biome map)")

	# An empty stack: Z in EVERY tool is a no-op — no LIFO fallback, no
	# placement ever dies (the removed cross-tool door stays shut).
	ToolkitHistory.clear()
	for t in [Toolkit.Tool.BIOME, Toolkit.Tool.SCULPT, Toolkit.Tool.TERRAIN,
			Toolkit.Tool.PLACE, Toolkit.Tool.RIVER]:
		Toolkit._tool = t
		Toolkit._undo()
		Toolkit._redo()
	_check(CellRecords.records(cell).size() == pre + 1,
		"Z/Shift+Z with an empty stack deletes nothing, in any tool")

	# Teardown: pop the placement, remove the file if the test created it.
	# Direct tool set — the hand was never _enter()ed, so _update_hud's
	# label doesn't exist (set_tool would touch it).
	Toolkit._tool = Toolkit.Tool.SCULPT
	Toolkit._biome_index = 4  # the boot default the link's status test expects
	Toolkit._macro_radius = 160.0
	Toolkit._biome_unsaved = false
	CellRecords.remove_last(cell)
	if CellRecords.records(cell).is_empty() and pre == 0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]))
	ToolkitHistory.clear()


## Snapping math (audit R1 polish) — the pure ToolkitSnap seam, no engine
## state: grid snaps XZ to the lattice (Y intact, step 0 the identity); the
## ground normal is +Y on the flat and tilts downhill on a slope, unit length;
## aligned_basis lays local +Y along the normal as a proper rotation and
## reproduces Basis(Y, yaw) on the flat; the grid-step ladder cycles and snaps
## an off-ladder value to its nearest rung.
func _test_toolkit_snap() -> void:
	# snappedf rounds half up (floor(v/step + 0.5)*step): 13 -> 12, -6 -> -4.
	var p := ToolkitSnap.snap_to_grid(Vector3(13.0, 7.5, -6.0), 4.0)
	_check(p == Vector3(12.0, 7.5, -4.0),
		"grid snaps XZ to the nearest step, Y untouched (got %s)" % p)
	_check(ToolkitSnap.snap_to_grid(Vector3(10.0, 1.0, 10.0), 4.0) == Vector3(12.0, 1.0, 12.0),
		"grid snaps up at the half-step (10 -> 12)")
	_check(ToolkitSnap.snap_to_grid(Vector3(13.0, 7.5, -6.0), 0.0)
			== Vector3(13.0, 7.5, -6.0), "grid step 0 is the identity")
	# Ground normal.
	_check(ToolkitSnap.ground_normal(10.0, 10.0, 10.0, 1.0) == Vector3.UP,
		"flat ground normal is exactly +Y")
	var n := ToolkitSnap.ground_normal(0.0, 1.0, 0.0, 1.0)  # rises to the east
	_check(n.y > 0.0 and n.x < 0.0 and absf(n.z) < 1e-6,
		"a rising-east slope tilts the normal west (got %s)" % n)
	_check(absf(n.length() - 1.0) < 1e-5, "the ground normal is unit length")
	# aligned_basis.
	var flat := ToolkitSnap.aligned_basis(Vector3.UP, PI / 3.0)
	_check(flat.is_equal_approx(Basis(Vector3.UP, PI / 3.0)),
		"aligned_basis on the flat is exactly Basis(Y, yaw)")
	var b := ToolkitSnap.aligned_basis(n, 0.0)
	_check((b.y - n).length() < 1e-5, "aligned_basis up follows the normal")
	_check(absf(b.determinant() - 1.0) < 1e-4, "aligned_basis is a proper rotation")
	_check(absf(b.x.dot(b.y)) < 1e-5 and absf(b.y.dot(b.z)) < 1e-5
			and absf(b.x.dot(b.z)) < 1e-5, "aligned_basis is orthonormal")
	_check(ToolkitSnap.aligned_basis(Vector3.ZERO, 0.0).y == Vector3.UP,
		"a zero normal falls back to flat +Y")
	# The step ladder.
	_check(ToolkitSnap.cycle_grid_step(4.0, 1) == 8.0, "grid step coarsens 4 -> 8")
	_check(ToolkitSnap.cycle_grid_step(16.0, 1) == 1.0, "grid step wraps 16 -> 1")
	_check(ToolkitSnap.cycle_grid_step(1.0, -1) == 16.0, "grid step wraps 1 -> 16")
	_check(ToolkitSnap.cycle_grid_step(3.0, -1) == 2.0,
		"an off-ladder 3 snaps to the nearest rung then refines")
	# --- Kit-bashing socket math (L11), pure like the grid math above.
	# socket_world carries a local socket into world: at a piece placed at
	# (10,0,10) turned 90° (yaw PI/2), a local +X socket [2,0,0] rotates to -Z.
	var sw := ToolkitSnap.socket_world(Vector3(10.0, 0.0, 10.0), PI / 2.0, 1.0,
		Vector3(2.0, 0.0, 0.0), 0.0)
	_check((sw["pos"] as Vector3).is_equal_approx(Vector3(10.0, 0.0, 8.0)),
		"socket_world rotates the local offset by the piece yaw (got %s)" % sw["pos"])
	_check(absf(fposmod(float(sw["yaw"]) - PI / 2.0, TAU)) < 1e-5,
		"socket_world adds the piece yaw to the socket yaw")
	# scale rides the offset: the same socket at scale 2 sits twice as far out.
	var sw2 := ToolkitSnap.socket_world(Vector3.ZERO, 0.0, 2.0, Vector3(1.5, 0.0, 0.0), 0.0)
	_check((sw2["pos"] as Vector3).is_equal_approx(Vector3(3.0, 0.0, 0.0)),
		"socket_world scales the local offset by the piece scale")
	# snap_to_socket is the inverse of socket_world: a piece placed by it has its
	# socket land exactly on the target, facing OPPOSITE (the click-together law).
	var tgt_pos := Vector3(5.0, 1.0, -2.0)
	var tgt_yaw := 0.7
	var lp := Vector3(-1.5, 0.6, 0.0)
	var lyaw := PI  # the incoming "west" socket
	var pose := ToolkitSnap.snap_to_socket(tgt_pos, tgt_yaw, lp, lyaw, 1.0)
	var back := ToolkitSnap.socket_world(pose["pos"], float(pose["yaw"]), 1.0, lp, lyaw)
	_check((back["pos"] as Vector3).is_equal_approx(tgt_pos),
		"snap_to_socket seats the incoming socket ON the target point")
	_check(absf(fposmod(float(back["yaw"]) - (tgt_yaw + PI), TAU)) < 1e-5,
		"the mated socket faces opposite the target (yaw + PI)")
	# best_socket_snap: nearest compatible candidate within reach mates; an
	# out-of-reach or type-mismatched candidate yields {} (place as usual).
	var ins: Array = [{"type": "wall", "pos": Vector3(-1.5, 0.6, 0.0), "yaw": PI}]
	var cands: Array = [
		{"type": "wall", "pos": Vector3(20.0, 0.0, 0.0), "yaw": 0.0},  # too far
		{"type": "wall", "pos": Vector3(2.0, 0.6, 0.0), "yaw": 0.0},   # in reach
	]
	var chosen := ToolkitSnap.best_socket_snap(Vector3(2.4, 0.0, 0.0), ins, cands, 3.0, 1.0)
	_check(not chosen.is_empty(), "best_socket_snap mates a compatible socket in reach")
	var cw := ToolkitSnap.socket_world(chosen["pos"], float(chosen["yaw"]), 1.0,
		Vector3(-1.5, 0.6, 0.0), PI)
	_check((cw["pos"] as Vector3).is_equal_approx(Vector3(2.0, 0.6, 0.0)),
		"the chosen mate lands on the in-reach candidate, not the far one")
	_check(ToolkitSnap.best_socket_snap(Vector3(2.4, 0.0, 0.0), ins,
		[{"type": "floor", "pos": Vector3(2.0, 0.0, 0.0), "yaw": 0.0}], 3.0, 1.0).is_empty(),
		"an incompatible socket type never mates (place as usual)")
	_check(ToolkitSnap.best_socket_snap(Vector3(2.4, 0.0, 0.0), ins,
		[{"type": "wall", "pos": Vector3(20.0, 0.0, 0.0), "yaw": 0.0}], 3.0, 1.0).is_empty(),
		"a socket out of reach never mates")


## Find a record by id anywhere in the Chronicle (a test helper — post-move/
## undo the cell is not known up front). {} when it is gone.
func _find_rec(id: String) -> Dictionary:
	for c: Vector2i in CellRecords.all_cells():
		var r: Dictionary = CellRecords.record(c, id)
		if not r.is_empty():
			return r
	return {}


## Box multi-select + group move (audit R1 polish) over undo v2: find_in_box
## returns exactly the records inside the rect, id-sorted (deterministic); a
## group move lands the primary at the target with every member's relative
## offset preserved and pushes ONE undo action; Z reverses the WHOLE group in
## one step. Synthetic far cells, no files left.
func _test_multi_select_group() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	Toolkit._tool = Toolkit.Tool.PLACE
	ToolkitHistory.clear()
	var bx := 861.0 * 128.0
	var bz := 861.0 * 128.0
	# Three records in a tight cluster with known relative offsets.
	var offs := [Vector2(0, 0), Vector2(4, 0), Vector2(0, 6)]
	var ids: Array[String] = []
	var orig := {}
	for o: Vector2 in offs:
		var rr: Dictionary = CellRecords.add(
			Vector3(bx + o.x, Terrain.height(bx + o.x, bz + o.y), bz + o.y),
			"kit_grp", 0.0, 1.0)
		ids.append(String(rr.id))
		orig[String(rr.id)] = Vector2(bx + o.x, bz + o.y)
	# find_in_box: the enclosing rect catches all three; a tighter one drops
	# the +6z member; the reply is id-sorted (the determinism anchor).
	var found := CellRecords.find_in_box(Vector2(bx - 2, bz - 2), Vector2(bx + 8, bz + 10))
	_check(found.size() == 3, "box select finds all three in the rect (got %d)" % found.size())
	var tight := CellRecords.find_in_box(Vector2(bx - 2, bz - 2), Vector2(bx + 8, bz + 3))
	_check(tight.size() == 2, "a tighter box excludes the out-of-rect record (got %d)" % tight.size())
	_check(String(found[0].id) < String(found[1].id)
			and String(found[1].id) < String(found[2].id),
		"find_in_box returns ids sorted (group-op determinism)")
	# Select and group-move.
	Toolkit._set_selection(found)
	_check(Toolkit._selection_set().size() == 3, "the group is the selection")
	# The gizmo handles + the box rubber-band build ImmediateMesh geometry
	# without error, headless (the pure mesh path — no GPU needed to assemble).
	Toolkit._rebuild_gizmo(Vector3.INF)
	_check((Toolkit._gizmo.mesh as ImmediateMesh).get_surface_count() >= 1,
		"the gizmo builds handle geometry for the selection")
	Toolkit._box_active = true
	Toolkit._box_a = Vector3(bx, Terrain.height(bx, bz), bz)
	Toolkit._update_box_preview(Vector3(bx + 50.0, Terrain.height(bx + 50.0, bz), bz))
	_check((Toolkit._box_preview.mesh as ImmediateMesh).get_surface_count() >= 1,
		"the box rubber-band builds geometry while active")
	Toolkit._box_active = false
	Toolkit._update_box_preview(Vector3.INF)
	_check((Toolkit._box_preview.mesh as ImmediateMesh).get_surface_count() == 0,
		"the box rubber-band clears when the drag ends")
	var prim := CellRecords.record(found[0].cell, String(found[0].id))
	var pax := float(prim.x)
	var paz := float(prim.z)
	var rel := {}
	for m: Dictionary in found:
		var r: Dictionary = CellRecords.record(m.cell, String(m.id))
		rel[String(m.id)] = Vector2(float(r.x) - pax, float(r.z) - paz)
	var d0 := ToolkitHistory.depth()
	var tx := bx + 300.0
	var tz := bz - 250.0
	Toolkit._group_move_to(Vector3(tx, Terrain.height(tx, tz), tz))
	_check(ToolkitHistory.depth() == d0 + 1, "a group move pushes ONE undo action")
	var post := Toolkit._selection_set()
	_check(post.size() == 3, "the group stays selected across the move")
	for pm: Dictionary in post:
		var r: Dictionary = CellRecords.record(pm.cell, String(pm.id))
		var want: Vector2 = rel[String(pm.id)]
		_check(absf(float(r.x) - (tx + want.x)) < 0.001
				and absf(float(r.z) - (tz + want.y)) < 0.001,
			"each member keeps its relative offset after the group move")
	# Z reverses the WHOLE group in one step.
	Toolkit._undo()
	for id: String in ids:
		var r := _find_rec(id)
		var want: Vector2 = orig[id]
		_check(not r.is_empty() and absf(float(r.x) - want.x) < 0.001
				and absf(float(r.z) - want.y) < 0.001,
			"Z returns every group member to its before-state")
	# Determinism: the same move from the same before-state lands bit-identical.
	Toolkit._set_selection(found)
	Toolkit._group_move_to(Vector3(tx, Terrain.height(tx, tz), tz))
	var a1 := {}
	for pm: Dictionary in Toolkit._selection_set():
		var r: Dictionary = CellRecords.record(pm.cell, String(pm.id))
		a1[String(pm.id)] = Vector2(float(r.x), float(r.z))
	Toolkit._undo()
	Toolkit._set_selection(found)
	Toolkit._group_move_to(Vector3(tx, Terrain.height(tx, tz), tz))
	for pm: Dictionary in Toolkit._selection_set():
		var r: Dictionary = CellRecords.record(pm.cell, String(pm.id))
		var w: Vector2 = a1[String(pm.id)]
		_check(float(r.x) == w.x and float(r.z) == w.y,
			"a repeated group move is deterministic")
	# Leave no trace.
	Toolkit._deselect()
	ToolkitHistory.clear()
	CellRecords.flush()
	_wipe_records(ids)
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## Alt-drag duplicate (audit R1 polish): duplicate mints a NEW id per selected
## member (originals untouched), the copies become the selection, and the whole
## batch is ONE undo action — Z removes every copy in one step.
func _test_duplicate() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	Toolkit._tool = Toolkit.Tool.PLACE
	ToolkitHistory.clear()
	var bx := 863.0 * 128.0
	var bz := 863.0 * 128.0
	var ids: Array[String] = []
	for o: Vector2 in [Vector2(0, 0), Vector2(5, 0)]:
		var rr: Dictionary = CellRecords.add(
			Vector3(bx + o.x, Terrain.height(bx + o.x, bz + o.y), bz + o.y),
			"kit_dup", 0.7, 1.3)
		ids.append(String(rr.id))
	var found := CellRecords.find_in_box(Vector2(bx - 2, bz - 2), Vector2(bx + 8, bz + 2))
	Toolkit._set_selection(found)
	var d0 := ToolkitHistory.depth()
	var made: Array = Toolkit._sel_duplicate()
	_check(made.size() == 2, "duplicate makes one copy per selected (got %d)" % made.size())
	_check(ToolkitHistory.depth() == d0 + 1, "duplicate pushes ONE undo action")
	var new_ids: Array[String] = []
	for m: Dictionary in made:
		new_ids.append(String(m.id))
	_check(new_ids[0] != ids[0] and new_ids[0] != ids[1]
			and new_ids[1] != ids[0] and new_ids[1] != ids[1]
			and new_ids[0] != new_ids[1], "each copy carries a fresh unique id")
	# The copies inherit yaw/scale (the whole record, minus identity).
	var c0 := _find_rec(new_ids[0])
	_check(absf(float(c0.yaw) - 0.7) < 1e-6 and absf(float(c0.scale) - 1.3) < 1e-6,
		"a copy inherits the original's yaw and scale")
	_check(Toolkit._selection_set().size() == 2, "the copies are the selection")
	for id: String in ids:
		_check(not _find_rec(id).is_empty(), "the originals survive the duplicate")
	# Z removes every copy in one step; the originals stay.
	Toolkit._undo()
	for id: String in new_ids:
		_check(_find_rec(id).is_empty(), "Z removes the copy")
	for id: String in ids:
		_check(not _find_rec(id).is_empty(), "Z spares the originals")
	# Leave no trace.
	Toolkit._deselect()
	ToolkitHistory.clear()
	CellRecords.flush()
	_wipe_records(ids)
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## The snap flags applied through the move funnel (audit R1 polish): grid snap
## lands the XZ on the lattice; snap-to-ground forces ground_dy 0 (seats flush);
## align-to-normal writes a unit `tilt` matching the ground, and toggling it off
## ERASES the key (the null-erase in CellRecords.update). Every edit rides undo.
func _test_snap_apply() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	Toolkit._tool = Toolkit.Tool.PLACE
	ToolkitHistory.clear()
	var bx := 865.0 * 128.0
	var bz := 865.0 * 128.0
	var rec: Dictionary = CellRecords.add(
		Vector3(bx, Terrain.height(bx, bz) + 2.0, bz), "kit_snap", 0.0, 1.0)
	var id := String(rec.id)
	Toolkit._pick_at(Vector3(bx, 0.0, bz))
	_check(Toolkit._sel_id == id, "the snap probe is selected")
	# Grid snap: move to an off-lattice point, land on the 4m grid.
	Toolkit._snap_grid = true
	Toolkit._grid_step = 4.0
	Toolkit._snap_ground = false
	Toolkit._snap_normal = false
	var gx := bx + 13.0
	var gz := bz - 6.0
	Toolkit._sel_move_to(Vector3(gx, Terrain.height(gx, gz), gz))
	var moved := _find_rec(id)
	_check(absf(fmod(float(moved.x), 4.0)) < 1e-4 and absf(fmod(float(moved.z), 4.0)) < 1e-4,
		"grid snap lands the moved XZ on the lattice (got %.2f,%.2f)" % [moved.x, moved.z])
	# Snap-to-ground: ground_dy forced to 0, seats flush on the terrain.
	Toolkit._snap_grid = false
	Toolkit._snap_ground = true
	Toolkit._sel_move_to(Vector3(bx + 20.0, Terrain.height(bx + 20.0, bz), bz))
	moved = _find_rec(id)
	_check(absf(float(moved.ground_dy)) < 1e-6, "snap-to-ground forces ground_dy 0")
	_check(absf(CellRecords.seat_y(moved) - Terrain.height(float(moved.x), float(moved.z))) < 1e-4,
		"a grounded record seats flush on the terrain")
	# Align-to-normal: a unit `tilt` matching the ground normal is stored.
	Toolkit._snap_ground = false
	Toolkit._snap_normal = true
	var nx := bx + 40.0
	var nz := bz + 40.0
	Toolkit._sel_move_to(Vector3(nx, Terrain.height(nx, nz), nz))
	moved = _find_rec(id)
	_check(moved.has("tilt") and (moved.tilt as Array).size() == 3,
		"align-to-normal writes a tilt normal")
	var tn := Vector3(float(moved.tilt[0]), float(moved.tilt[1]), float(moved.tilt[2]))
	_check(absf(tn.length() - 1.0) < 1e-4 and tn.y > 0.0, "the stored tilt is a unit up-ward normal")
	var gn: Array = Toolkit._ground_normal_arr(float(moved.x), float(moved.z))
	_check(tn.is_equal_approx(Vector3(gn[0], gn[1], gn[2])),
		"the tilt matches the ground normal under the record")
	# Toggle align off and move again — the tilt key is ERASED, not left stale.
	Toolkit._snap_normal = false
	Toolkit._sel_move_to(Vector3(bx + 60.0, Terrain.height(bx + 60.0, bz), bz))
	moved = _find_rec(id)
	_check(not moved.has("tilt"), "toggling align off erases the tilt key (null-erase)")
	# Leave no trace.
	Toolkit._deselect()
	ToolkitHistory.clear()
	CellRecords.flush()
	_wipe_records([id])
	Toolkit._snap_grid = false
	Toolkit._grid_step = Toolkit.GRID_STEP_DEFAULT
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## The id of the single record that appeared since `known` (a {id: true}
## snapshot of the whole Chronicle) — the test's "which one did _place_at just
## add" resolver, cell-agnostic (a socket mate can land in a neighbour cell).
func _new_record_id_since(known: Dictionary) -> String:
	for c: Vector2i in CellRecords.all_cells():
		for r: Dictionary in CellRecords.records(c):
			if not known.has(String(r.get("id", ""))):
				return String(r.get("id", ""))
	return ""


func _all_record_ids() -> Dictionary:
	var out := {}
	for c: Vector2i in CellRecords.all_cells():
		for r: Dictionary in CellRecords.records(c):
			out[String(r.get("id", ""))] = true
	return out


## Kit-bashing socket snap (L11): a piece whose card declares sockets, dropped
## near a compatible socket of an already-placed piece, MATES it — position AND
## orientation click, landing as ONE undoable record op through the same
## CellRecords funnel every snap rides (so undo v2 covers it). And the zero-
## regression floor, proven three ways: no socket in reach, a socket out of
## reach, and an incoming piece with no sockets all place EXACTLY as before.
## Synthetic far cells, no files left.
func _test_socket_snap() -> void:
	var wall_slot := "arch/ruins/broken_wall"
	if not Cards.has(wall_slot) or Cards.sockets_for_file(Cards.resolve(wall_slot)).is_empty():
		print("  socket snap: SKIP (broken_wall card has no sockets in this checkout)")
		return
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	Toolkit._tool = Toolkit.Tool.PLACE
	Toolkit._snap_grid = false
	Toolkit._snap_ground = false
	Toolkit._snap_normal = false
	Toolkit._snap_socket = false
	ToolkitHistory.clear()
	var bx := 872.0 * 128.0
	var bz := 872.0 * 128.0
	var placed: Array[String] = []

	# Piece A (a wall), socket snap OFF: it lands where it is dropped.
	_check(Toolkit.set_place_slot(wall_slot) > 0, "the wall slot is in the palette")
	var before_a := _all_record_ids()
	var a_hit := Vector3(bx, Terrain.height(bx, bz), bz)
	Toolkit._place_at(a_hit)
	var aid := _new_record_id_since(before_a)
	placed.append(aid)
	var a := _find_rec(aid)
	_check(absf(float(a.x) - a_hit.x) < 1e-4 and absf(float(a.z) - a_hit.z) < 1e-4,
		"piece A lands at the drop point (socket snap off)")

	# A's east+west sockets, from A's actual record + its card (the same
	# transform the Toolkit gathers candidates through).
	var east := {}
	var west := {}
	for s: Dictionary in Cards.sockets_for_file(String(a.kit)):
		if String(s.get("name", "")) == "east":
			east = s
		elif String(s.get("name", "")) == "west":
			west = s
	_check(not east.is_empty() and not west.is_empty(),
		"the wall card declares named east + west sockets")
	var a_seat := Vector3(float(a.x), CellRecords.seat_y(a), float(a.z))
	var a_sc := float(a.get("scale", 1.0))
	var a_east := ToolkitSnap.socket_world(a_seat, float(a.yaw), a_sc,
		Vector3(east.pos[0], east.pos[1], east.pos[2]), float(east.yaw))

	# Piece B, socket snap ON, cursor near A's east socket (XZ): B MATES — its
	# own west socket clicks onto A's east, not at the raw cursor.
	Toolkit._snap_socket = true
	var b_cursor := Vector3(a_east.pos.x + 0.4,
		Terrain.height(a_east.pos.x, a_east.pos.z), a_east.pos.z - 0.3)
	var before_b := _all_record_ids()
	var depth0 := ToolkitHistory.depth()
	Toolkit._place_at(b_cursor)
	_check(ToolkitHistory.depth() == depth0 + 1,
		"a socket-snapped place is ONE undo action")
	var bid := _new_record_id_since(before_b)
	placed.append(bid)
	var b := _find_rec(bid)
	_check(not b.is_empty(), "piece B landed as a record")
	var b_west := ToolkitSnap.socket_world(
		Vector3(float(b.x), CellRecords.seat_y(b), float(b.z)),
		float(b.yaw), float(b.get("scale", 1.0)),
		Vector3(west.pos[0], west.pos[1], west.pos[2]), float(west.yaw))
	_check((b_west.pos - a_east.pos).length() < 0.1,
		"B's socket clicks ONTO A's east socket (Δ=%.3fm)" % (b_west.pos - a_east.pos).length())
	_check(absf(fposmod(float(b_west.yaw) - (float(a_east.yaw) + PI), TAU)) < 1e-3,
		"B's mated socket faces opposite A's (the click-together law)")
	_check(Vector2(float(b.x) - b_cursor.x, float(b.z) - b_cursor.z).length() > 0.1,
		"B snapped to the socket, not to the raw cursor")

	# Z removes the snapped piece — the record op undoes like any other.
	Toolkit._undo()
	_check(_find_rec(bid).is_empty(), "Z removes the socket-snapped piece")

	# Zero regression #1: snap ON but no socket in reach (far from A) -> B lands
	# at the drop point, exactly as with snap off.
	var far := Vector3(bx + 400.0, 0.0, bz + 400.0)
	far.y = Terrain.height(far.x, far.z)
	var before_far := _all_record_ids()
	Toolkit._place_at(far)
	var fid := _new_record_id_since(before_far)
	placed.append(fid)
	var fr := _find_rec(fid)
	_check(absf(float(fr.x) - far.x) < 1e-4 and absf(float(fr.z) - far.z) < 1e-4,
		"no socket in reach: snap-on places at the drop point (zero regression)")

	# Zero regression #2: an incoming piece with NO sockets, dropped right on
	# A's socket, never snaps — it places as today.
	var plain_slot := "arch/ruins/toppled_column"
	if Cards.has(plain_slot) and Cards.sockets_for_file(Cards.resolve(plain_slot)).is_empty():
		_check(Toolkit.set_place_slot(plain_slot) > 0, "the socketless slot is in the palette")
		var c_cursor := Vector3(a_east.pos.x, Terrain.height(a_east.pos.x, a_east.pos.z), a_east.pos.z)
		var before_c := _all_record_ids()
		Toolkit._place_at(c_cursor)
		var cid := _new_record_id_since(before_c)
		placed.append(cid)
		var cr := _find_rec(cid)
		_check(absf(float(cr.x) - c_cursor.x) < 1e-4 and absf(float(cr.z) - c_cursor.z) < 1e-4,
			"a piece with no sockets never snaps (places exactly as today)")

	# Leave no trace.
	Toolkit._deselect()
	ToolkitHistory.clear()
	CellRecords.flush()
	_wipe_records(placed)
	Toolkit._snap_socket = false
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## The link's R1-polish verbs over the REAL dispatch (audit R1 polish), driven
## headless through StrataLink._execute — the same line grammar Strata sends,
## so the wire contract for snap/select/move/duplicate is pinned without a
## socket (the pane's captured-pointer mouse drag cannot run headless; this is
## the honest seam that can). Gate, happy path, and error lines.
func _test_link_toolkit_ops() -> void:
	# Gated on the hand: the R1-polish subverbs err honestly with no hand.
	Toolkit.active = false
	_check(StrataLink._execute("toolkit snap grid on") == "err toolkit not active",
		"toolkit snap errs without the hand")
	_check(StrataLink._execute("toolkit select box 0 0 1 1") == "err toolkit not active",
		"toolkit select errs without the hand")
	# With the hand + a small cluster.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	Toolkit._tool = Toolkit.Tool.PLACE
	ToolkitHistory.clear()
	var bx := 867.0 * 128.0
	var bz := 867.0 * 128.0
	var ids: Array[String] = []
	for o: Vector2 in [Vector2(0, 0), Vector2(4, 0)]:
		var rr: Dictionary = CellRecords.add(
			Vector3(bx + o.x, Terrain.height(bx + o.x, bz + o.y), bz + o.y),
			"kit_lnk", 0.0, 1.0)
		ids.append(String(rr.id))
	# select box -> ok count; the selection is live.
	var sel := StrataLink._execute("toolkit select box %f %f %f %f" % [
		bx - 2.0, bz - 2.0, bx + 8.0, bz + 2.0])
	_check(sel == "ok select 2", "link box-select answers the count (got %s)" % sel)
	_check(Toolkit._selection_set().size() == 2, "the link selected the group")
	# snap toggles: state flips and the reply names it.
	_check(StrataLink._execute("toolkit snap grid on") == "ok snap grid on"
			and Toolkit._snap_grid, "link snap grid on flips the flag")
	_check(StrataLink._execute("toolkit snap step 8") == "ok snap step 8.00m"
			and absf(Toolkit._grid_step - 8.0) < 1e-6, "link snap step sets the grid step")
	_check(StrataLink._execute("toolkit snap ground on") == "ok snap ground on"
			and Toolkit._snap_ground, "link snap ground on flips the flag")
	# move the group over the wire.
	var mv := StrataLink._execute("toolkit move %f %f" % [bx + 200.0, bz + 200.0])
	_check(mv == "ok move 2", "link move answers the count moved (got %s)" % mv)
	# duplicate over the wire -> two new copies selected.
	var d0 := ToolkitHistory.depth()
	var du := StrataLink._execute("toolkit duplicate")
	_check(du == "ok duplicate 2", "link duplicate answers the copy count (got %s)" % du)
	_check(ToolkitHistory.depth() == d0 + 1, "link duplicate is ONE undo action")
	# Error lines: unknown snap kind, short select.
	_check(StrataLink._execute("toolkit snap wobble on") == "err toolkit snap needs grid|ground|normal|socket",
		"an unknown snap kind errs with the contract line")
	_check(String(StrataLink._execute("toolkit select box 1 2")).begins_with("err toolkit select"),
		"a short select box errs with the contract line")
	# Leave no trace: undo the duplicate, wipe every record + cell file.
	Toolkit._undo()
	Toolkit._deselect()
	ToolkitHistory.clear()
	CellRecords.flush()
	_wipe_records(ids)
	Toolkit._snap_grid = false
	Toolkit._snap_ground = false
	Toolkit._grid_step = Toolkit.GRID_STEP_DEFAULT
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## Remove every record named by id (wherever it sits), then delete any now-empty
## cell files the test created — the far synthetic cells leave no trace.
func _wipe_records(ids: Array) -> void:
	var touched := {}
	for id: String in ids:
		for c: Vector2i in CellRecords.all_cells():
			if not CellRecords.record(c, String(id)).is_empty():
				CellRecords.remove(c, String(id))
				touched[c] = true
	for c: Vector2i in touched.keys():
		if CellRecords.records(c).is_empty():
			var path := "%s/cell_%d_%d.json" % [CellRecords.DIR, c.x, c.y]
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# A group MOVE empties its SOURCE cell (the records migrate to the target),
	# and flush() writes that source as "[]" — a cell no tracked id sits in, so
	# the loop above never visits it. Sweep the dir for any empty cell file and
	# drop it (content-empty hermeticity: the far synthetic cells leave NO
	# residue). Only "[]"/blank files are removed — cells with real records
	# (valley's own gazetteer of placements) are never touched.
	var cdir := ProjectSettings.globalize_path(CellRecords.DIR)
	var da := DirAccess.open(cdir)
	if da != null:
		for fn: String in da.get_files():
			if fn.begins_with("cell_") and fn.ends_with(".json"):
				var body := FileAccess.get_file_as_string(cdir.path_join(fn)).strip_edges()
				if body == "[]" or body == "":
					DirAccess.remove_absolute(cdir.path_join(fn))
	# If the sweep left the dir empty, it was created by this run on a
	# content-empty tree — remove it so `git status` stays clean.
	var da2 := DirAccess.open(cdir)
	if da2 != null and da2.get_files().is_empty() and da2.get_directories().is_empty():
		DirAccess.remove_absolute(cdir)


## Undo v2 (audit R3) — a carved river joins the stack (node ops). Enter
## carves and writes pen_N.json; undo lifts the river out (Terrain
## .remove_river rebuilds the kernel, the file goes, the ground returns);
## redo re-carves from the record. Ends erased — no river, no file, so the
## soak never sees a penned channel this test made.
func _test_river_undo() -> void:
	ToolkitHistory.clear()
	var before_n: int = Terrain.rivers.size()
	var mid := Vector2(2000.0, 2060.0)
	var h_pre: float = Terrain.height(mid.x, mid.y)
	Toolkit._carve_river([Vector2(2000.0, 2000.0), Vector2(2000.0, 2120.0)])
	if Terrain.rivers.size() != before_n + 1:
		print("  river undo: SKIP (course too short / no carve)")
		ToolkitHistory.clear()
		return
	_check(ToolkitHistory.depth() == 1, "the carve pushes one action")
	var carved_id := String(Terrain.rivers.back().id)
	var pen_path := "res://data/water/rivers/%s.json" % carved_id
	_check(FileAccess.file_exists(pen_path), "the carve writes its pen file")
	_check(Terrain.height(mid.x, mid.y) <= h_pre + 0.001, "the carve never raises the ground")
	# Undo: river out, file gone, ground back.
	Toolkit._undo()
	_check(Terrain.rivers.size() == before_n, "undo removes the river")
	_check(not FileAccess.file_exists(pen_path), "undo deletes the pen file")
	_check(absf(Terrain.height(mid.x, mid.y) - h_pre) < 0.01,
		"undo restores the ground the carve lowered")
	# Redo: back.
	Toolkit._redo()
	_check(Terrain.rivers.size() == before_n + 1, "redo re-carves the river")
	_check(FileAccess.file_exists(pen_path), "redo rewrites the pen file")
	# Leave clean: undo again, and belt-and-braces delete the file.
	Toolkit._undo()
	_check(Terrain.rivers.size() == before_n, "final undo leaves no river")
	if FileAccess.file_exists(pen_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pen_path))
	ToolkitHistory.clear()
	Toolkit._tool = Toolkit.Tool.SCULPT  # direct: the hand was never entered


## Placement editing v2 (audit #1) over undo v2 (audit R3): the hand edits
## what it placed. Pick = nearest record within reach; move keeps the
## ground offset (the ground-relative law) and migrates cell files across a
## boundary; rotate/scale are data edits; delete is TARGETED (never LIFO);
## each pushes a record action onto the shared stack, and Z reverts the last
## by before/after state (cell migration and all); yaw/scale/id survive a
## save/load round trip; legacy rows are named the moment they're picked.
## Synthetic far-off cells, no files left.
func _test_placement_edit() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	_check(Toolkit.active, "toolkit enters for the placement-edit test")
	Toolkit._tool = Toolkit.Tool.PLACE
	ToolkitHistory.clear()  # a clean stream: each edit below is one step back
	var x := 903.0 * 128.0
	var z := 900.0 * 128.0
	var cell: Vector2i = CellRecords.cell_of(Vector3(x, 0.0, z))
	_check(CellRecords.records(cell).is_empty(), "test cell starts empty")

	# ids: minted at add, unique — the stable name every later layer
	# (selection, undo, the P4 overrides diff) hangs on to.
	var h0: float = Terrain.height(x, z)
	var r1: Dictionary = CellRecords.add(Vector3(x, h0 + 0.5, z), "kit_a", 1.0, 1.0)
	var r2: Dictionary = CellRecords.add(
		Vector3(x + 2.0, Terrain.height(x + 2.0, z), z), "kit_b", 2.0, 1.2)
	var id1 := String(r1["id"])
	var id2 := String(r2["id"])
	_check(id1 != "" and id2 != "" and id1 != id2, "adds mint unique ids")

	# Pick: nearest record within reach; empty ground deselects.
	Toolkit._pick_at(Vector3(x + 0.4, 0.0, z))
	_check(Toolkit._sel_id == id1, "pick selects the nearest record")
	Toolkit._pick_at(Vector3(x + 1.8, 0.0, z))
	_check(Toolkit._sel_id == id2, "pick prefers the closer record")
	Toolkit._pick_at(Vector3(x + 60.0, 0.0, z))
	_check(Toolkit._sel_id == "", "empty ground deselects")

	# Move (G): the ground offset rides — the ground-relative law — and
	# the record migrates cell files when x/z cross a boundary.
	Toolkit._pick_at(Vector3(x, 0.0, z))
	_check(Toolkit._sel_id == id1, "re-pick lands the first record")
	var nx := x + 300.0
	var nz := z - 40.0
	Toolkit._sel_move_to(Vector3(nx, Terrain.height(nx, nz), nz))
	var ncell: Vector2i = CellRecords.cell_of(Vector3(nx, 0.0, nz))
	_check(ncell != cell, "the test move crosses a cell boundary")
	var moved: Dictionary = CellRecords.record(ncell, id1)
	_check(not moved.is_empty(), "moved record lives in its new cell")
	_check(CellRecords.record(cell, id1).is_empty(), "moved record left the old cell")
	_check(absf(float(moved.get("ground_dy", -9.0)) - 0.5) < 0.001,
		"the ground offset rides the move (ground-relative law)")
	_check(absf(CellRecords.seat_y(moved) - (Terrain.height(nx, nz) + 0.5)) < 0.001,
		"moved record seats on the NEW ground + dy")
	_check(CellRecords.has_dirty(), "an edit waits on the stroke-quiet flush")
	# Z: the move reverts to its before-state — position, offset, cell.
	Toolkit._undo()
	var back: Dictionary = CellRecords.record(cell, id1)
	_check(not back.is_empty() and float(back.x) == x and float(back.z) == z,
		"Z returns the move to its before-state")
	_check(CellRecords.record(ncell, id1).is_empty(), "undo empties the new cell")
	_check(Toolkit._sel_cell == cell and Toolkit._sel_id == id1,
		"the selection follows the undo home")

	# Rotate and scale: plain data edits, one memento per tap.
	var yaw0 := float(back["yaw"])
	Toolkit._sel_rotate(1.0)
	back = CellRecords.record(cell, id1)
	_check(absf(float(back["yaw"]) - wrapf(yaw0 + Toolkit.SEL_YAW_STEP, 0.0, TAU)) < 0.001,
		"R steps the yaw")
	Toolkit._sel_scale(1)
	back = CellRecords.record(cell, id1)
	_check(absf(float(back["scale"]) - 1.08) < 0.001, "scale steps up")
	Toolkit._undo()
	back = CellRecords.record(cell, id1)
	_check(absf(float(back["scale"]) - 1.0) < 0.001, "Z reverts the scale step")

	# Persistence: a fresh Chronicle reads the same id/yaw/scale back.
	CellRecords.flush()
	_check(not CellRecords.has_dirty(), "flush clears the dirty ledger")
	var cr: Node = load("res://game/world/cell_records.gd").new()
	add_child(cr)
	var loaded: Dictionary = cr.record(cell, id1)
	_check(not loaded.is_empty(), "the id survives a save/load round trip")
	_check(absf(float(loaded.get("yaw", -9.0)) - float(back["yaw"])) < 0.000001
		and absf(float(loaded.get("scale", -9.0)) - float(back["scale"])) < 0.000001,
		"yaw/scale persist through save/load")
	remove_child(cr)
	cr.free()

	# Targeted delete: the selected record is the OLDER one — LIFO would
	# have taken the other. X takes THIS one; Z brings it back, selected.
	Toolkit._sel_delete()
	_check(CellRecords.record(cell, id1).is_empty(), "X deletes THE selected record")
	_check(not CellRecords.record(cell, id2).is_empty(),
		"the newer record survives (targeted, not LIFO)")
	_check(Toolkit._sel_id == "", "delete deselects")
	Toolkit._undo()
	_check(not CellRecords.record(cell, id1).is_empty(), "Z returns the deleted record")
	_check(Toolkit._sel_id == id1, "the returned record is the selection again")

	# Place action: _place_at pushes {before {}, after rec}; Z removes THAT
	# record by id even under a newer sibling — never the LIFO tail. Needs
	# the palette (cards are tracked; resolve can still miss binaries — skip
	# honestly, the targeted machinery is covered above either way).
	if not Toolkit._palette.is_empty():
		var pre: int = CellRecords.records(cell).size()
		Toolkit._place_at(Vector3(x + 5.0, Terrain.height(x + 5.0, z), z))
		if CellRecords.records(cell).size() == pre + 1:
			var placed_id := String(CellRecords.records(cell).back()["id"])
			var r3: Dictionary = CellRecords.add(
				Vector3(x + 7.0, Terrain.height(x + 7.0, z), z), "kit_c", 0.0, 1.0)
			Toolkit._undo()
			_check(CellRecords.record(cell, placed_id).is_empty(),
				"Z removes the PLACED record by id")
			_check(not CellRecords.record(cell, String(r3["id"])).is_empty(),
				"Z after place spares the newer LIFO tail")
		else:
			print("  placement edit: place memento sub-check skipped (unresolvable slot)")
	else:
		print("  placement edit: place memento sub-check skipped (no cards)")

	# Legacy rows (no id): picking one names it on the spot.
	var legacy := {"kit": "legacy_kit", "x": x + 40.0, "y": 5.0, "z": z,
		"yaw": 0.0, "scale": 1.0}
	CellRecords.records(cell).append(legacy)
	Toolkit._pick_at(Vector3(x + 40.0, 0.0, z))
	_check(legacy.has("id"), "picking a legacy record mints its id")
	_check(Toolkit._sel_id == String(legacy.get("id", "")), "the named legacy row is selected")

	# Leave no trace: pop everything, remove the files the test created.
	Toolkit._deselect()
	ToolkitHistory.clear()
	CellRecords.flush()
	for c: Vector2i in [cell, ncell]:
		while CellRecords.remove_last(c):
			pass
		var path := "%s/cell_%d_%d.json" % [CellRecords.DIR, c.x, c.y]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## Prefabs / groups (Creation Kit audit §2.1): a composed place captured as
## a reusable record, then re-stamped. Places 3 pieces, K captures the
## cluster, clears the scene, places the prefab elsewhere, and asserts all 3
## members land with their relative transforms preserved and ONE undo
## removes the whole stamp. Also pins the record law: it validates through
## Records.load_json and the browser-shaped {members: [...]} contract, and
## the palette gains the prefab entry. Leaves the checkout clean.
func _test_prefab() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	_check(Toolkit.active, "toolkit enters for the prefab test")
	Toolkit._tool = Toolkit.Tool.PLACE
	ToolkitHistory.clear()

	var bx := 905.0 * 128.0
	var bz := 900.0 * 128.0
	var cell: Vector2i = CellRecords.cell_of(Vector3(bx, 0.0, bz))
	while CellRecords.remove_last(cell):
		pass
	var name := "test_yard"
	var pf_path: String = Prefabs.DIR + "/" + name + ".json"
	if FileAccess.file_exists(pf_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pf_path))

	# Three pieces at a known cross: A at origin, B +3x, C +3z (all on the
	# ground, so ground_dy ≈ 0). The centroid — the capture anchor — is
	# (bx+1, bz+1).
	var pa := Vector3(bx, Terrain.height(bx, bz), bz)
	var pb := Vector3(bx + 3.0, Terrain.height(bx + 3.0, bz), bz)
	var pc := Vector3(bx, Terrain.height(bx, bz + 3.0), bz + 3.0)
	var a: Dictionary = CellRecords.add(pa, "kit_a", 0.5, 1.0)
	var b: Dictionary = CellRecords.add(pb, "kit_b", 1.5, 1.2)
	var c: Dictionary = CellRecords.add(pc, "kit_c", 2.5, 0.8)
	_check(CellRecords.records(cell).size() == 3, "three pieces placed")

	# Pick the anchor piece; K sweeps up the cluster within reach and saves.
	Toolkit._pick_at(pa)
	_check(Toolkit._sel_id == String(a["id"]), "anchor piece selected")
	var n: int = Toolkit.capture_prefab(name, 8.0)
	_check(n == 3, "capture sweeps all 3 pieces (got %d)" % n)
	_check(Prefabs.has(name), "prefab lands in the live catalog")
	_check(Prefabs.members(name).size() == 3, "prefab record holds 3 members")

	# The record validates through the game's one load path AND the
	# browser-shaped {members: [...]} contract Strata's RecordCatalog reads.
	var reload: Variant = Records.load_json(pf_path)
	_check(reload is Dictionary and (reload as Dictionary).get("members") is Array
		and ((reload as Dictionary)["members"] as Array).size() == 3,
		"prefab record on disk is {members:[3]}")
	_check(reload is Dictionary
		and Records.validate(reload, {"members": TYPE_ARRAY}, pf_path),
		"prefab record passes Records.validate")

	# The palette gained the prefab entry (Kit + prefabs), placeable by slot.
	_check(Toolkit.set_place_slot("prefab/" + name) > 0,
		"prefab is selectable in the PLACE palette")

	# Clear the scene — the prefab must stand alone as a record.
	for id: String in [String(a["id"]), String(b["id"]), String(c["id"])]:
		CellRecords.remove(cell, id)
	_check(CellRecords.records(cell).is_empty(), "scene cleared before re-stamp")
	ToolkitHistory.clear()

	# Stamp the prefab at a fresh spot; all 3 members land.
	var hx := 906.0 * 128.0
	var hz := 901.0 * 128.0
	var ncell: Vector2i = CellRecords.cell_of(Vector3(hx, 0.0, hz))
	while CellRecords.remove_last(ncell):
		pass
	Toolkit._place_prefab_at(Vector3(hx, Terrain.height(hx, hz), hz), name)
	var placed: Array = CellRecords.records(ncell)
	_check(placed.size() == 3, "prefab stamps all 3 members (got %d)" % placed.size())

	# Relative transforms preserved: keyed by kit (order-independent), the
	# pairwise XZ offsets match the captured cross, and each member's own
	# yaw/scale rides along.
	var by_kit: Dictionary = {}
	for r: Dictionary in placed:
		by_kit[String(r.get("kit", ""))] = r
	_check(by_kit.has("kit_a") and by_kit.has("kit_b") and by_kit.has("kit_c"),
		"every captured kit re-appears")
	if by_kit.has("kit_a") and by_kit.has("kit_b") and by_kit.has("kit_c"):
		var ra: Dictionary = by_kit["kit_a"]
		var rb: Dictionary = by_kit["kit_b"]
		var rc: Dictionary = by_kit["kit_c"]
		_check(absf((float(rb.x) - float(ra.x)) - 3.0) < 0.01
			and absf(float(rb.z) - float(ra.z)) < 0.01,
			"member B keeps its +3x offset from A")
		_check(absf(float(rc.x) - float(ra.x)) < 0.01
			and absf((float(rc.z) - float(ra.z)) - 3.0) < 0.01,
			"member C keeps its +3z offset from A")
		_check(absf(float(rb.get("yaw", -9.0)) - 1.5) < 0.001
			and absf(float(rb.get("scale", -9.0)) - 1.2) < 0.001,
			"member yaw/scale ride the capture")
		# Ground-relative law: each member re-seats on the CURRENT ground +
		# its captured offset (~0 here — captured on the ground).
		_check(absf(CellRecords.seat_y(ra)
			- Terrain.height(float(ra.x), float(ra.z))) < 0.01,
			"member re-seats on the current ground (regeneration law)")

	# ONE Z undoes the whole stamp; redo brings the whole set back.
	Toolkit._undo()
	_check(CellRecords.records(ncell).is_empty(),
		"one Z removes every prefab member")
	ToolkitHistory.redo()
	_check(CellRecords.records(ncell).size() == 3,
		"redo re-stamps the whole prefab")

	# Leave no trace: the records, the cells, and the prefab file.
	Toolkit._deselect()
	ToolkitHistory.clear()
	CellRecords.flush()
	for cc: Vector2i in [cell, ncell]:
		while CellRecords.remove_last(cc):
			pass
		var path := "%s/cell_%d_%d.json" % [CellRecords.DIR, cc.x, cc.y]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(pf_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pf_path))
	# Drop the captured prefab from the live catalog too, so the palette
	# (and every later test's place_count) returns to pristine.
	Prefabs._prefabs.erase(name)
	Toolkit._rebuild_palette()
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## The P4 overrides round trip, emitter half: hand work (a placed record
## + a pen stroke) lands in data/overrides/overrides.json on the SAME
## stroke-quiet flush the layers ride — placements keyed by stable id,
## terrain layers as deflate_f32le blobs Strata can inflate. Schema
## round-trips, the `overrides status` verb answers, a second emit is
## byte-idempotent. Restores every touched file — the checkout stays
## clean.
func _test_overrides_emit() -> void:
	if not Terrain.has_world_tile():
		print("  overrides emit: SKIP (no baked tile cache)")
		return
	# Snapshot everything the emitter may touch, absent files as null.
	var guard_paths := [Overrides.FILE,
		Overrides.DIR + "/terrain_pen_override.f32z",
		Overrides.DIR + "/terrain_sculpt.f32z",
		Terrain.TILE_OVERRIDE_EXR, Terrain.TILE_OVERRIDE_META]
	var guard: Dictionary = {}
	for gp: String in guard_paths:
		guard[gp] = FileAccess.get_file_as_bytes(gp) \
				if FileAccess.file_exists(gp) else null
	var ov_snap: Image = Terrain.snapshot_tile_override()

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	Toolkit._tool = Toolkit.Tool.PLACE

	# Hand work: one placed record (write-through) + one pen stroke.
	var x := 907.0 * 128.0
	var z := 905.0 * 128.0
	var cell: Vector2i = CellRecords.cell_of(Vector3(x, 0.0, z))
	var rec: Dictionary = CellRecords.add(
		Vector3(x, Terrain.height(x, z) + 0.25, z), "kit_ov", 0.5, 1.1)
	var rid := String(rec["id"])
	_check(Overrides.pending, "a placement marks the artifact stale")
	var pp := Vector2(1800.0, -1750.0)
	Terrain.commit_tile_override(Terrain.paint_tile_override(pp, 150.0, 8.0))
	Toolkit._terrain_unsaved = true  # what a real stroke sets

	# Half the quiet window: nothing emitted yet.
	var pre_bytes: Variant = guard[Overrides.FILE]
	Toolkit._flush_quiet = 0.0
	Toolkit._process(Toolkit.FLUSH_QUIET * 0.5)
	var half: Variant = FileAccess.get_file_as_bytes(Overrides.FILE) \
			if FileAccess.file_exists(Overrides.FILE) else null
	_check(half == pre_bytes, "half the quiet window: artifact untouched")

	# Past the window: the flush emits.
	Toolkit._process(Toolkit.FLUSH_QUIET)
	_check(FileAccess.file_exists(Overrides.FILE),
		"stroke-quiet flush writes overrides.json")
	_check(not Overrides.pending, "emit clears the pending flag")

	# Schema round trip.
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(Overrides.FILE))
	_check(parsed is Dictionary and int(parsed.get("format", 0)) == 1,
		"artifact parses, format 1")
	var placements: Dictionary = parsed.get("placements", {})
	_check(placements.has(rid), "the placed record is keyed by its id")
	var entry: Dictionary = placements.get(rid, {})
	var ecell: Array = entry.get("cell", [0, 0])
	_check(String(entry.get("kit", "")) == "kit_ov"
		and absf(float(entry.get("x", 0.0)) - x) < 0.001
		and int(ecell[0]) == cell.x and int(ecell[1]) == cell.y,
		"the placement entry carries kit/x/cell verbatim (got %s)" % [entry])
	_check(entry.has("ground_dy"), "the ground anchor rides the entry")
	var layers: Array = (parsed.get("terrain", {}) as Dictionary).get("layers", [])
	var pen: Dictionary = {}
	for l: Dictionary in layers:
		if String(l.get("id", "")) == "pen_override":
			pen = l
	_check(not pen.is_empty(), "the pen layer is listed")
	if not pen.is_empty():
		var blob_path: String = "res://" + String(pen["file"])
		_check(FileAccess.get_sha256(blob_path) == String(pen["sha256"]),
			"the blob sha256 matches the file")
		var res: Array = pen["res"]
		var raw := FileAccess.get_file_as_bytes(blob_path).decompress(
			int(res[0]) * int(res[1]) * 4, FileAccess.COMPRESSION_DEFLATE)
		_check(raw.size() == int(res[0]) * int(res[1]) * 4,
			"the blob inflates to the declared grid")
		var floats := raw.to_float32_array()
		# The sampling law: the stroke center maps to a texel that gained
		# ~8m over WHATEVER was already painted there (a dressed checkout
		# legitimately carries earlier pen work — measure the delta, not
		# an absolute).
		var mpp := float(pen["m_per_px"])
		var ox := int(roundf((pp.x - float(pen["x0"])) / mpp))
		var oz := int(roundf((pp.y - float(pen["z0"])) / mpp))
		var center := floats[oz * int(res[0]) + ox]
		var was := ov_snap.get_pixel(ox, oz).r if ov_snap != null else 0.0
		_check(center - was > 6.0 and center - was < 8.5,
			"the painted stroke survives the round trip (%+.2fm at center)"
				% (center - was))

	# The link verb (data, not hand state — answers in any posture).
	var status: String = StrataLink._execute("overrides status")
	_check(status.begins_with("ok overrides placements="),
		"`overrides status` answers (got %s)" % status)
	_check(" layers=" in status and " last_write=" in status,
		"status carries layer count and last write")

	# Idempotence: a second emit changes nothing on disk.
	var bytes1 := FileAccess.get_file_as_bytes(Overrides.FILE)
	var mtime1 := FileAccess.get_modified_time(Overrides.FILE)
	Overrides.emit()
	_check(FileAccess.get_file_as_bytes(Overrides.FILE) == bytes1
		and FileAccess.get_modified_time(Overrides.FILE) == mtime1,
		"an unchanged emit is byte- and mtime-idempotent")

	# Leave no trace: record, layers, artifact, toolkit posture.
	CellRecords.remove(cell, rid)
	var cell_path := "%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]
	if FileAccess.file_exists(cell_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cell_path))
	Terrain.restore_tile_override(ov_snap)
	for gp: String in guard_paths:
		var was: Variant = guard[gp]
		if was == null:
			if FileAccess.file_exists(gp):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(gp))
		else:
			var f := FileAccess.open(gp, FileAccess.WRITE)
			f.store_buffer(was)
			f.close()
	Overrides.pending = false
	Overrides._layer_cache.clear()
	Toolkit._terrain_unsaved = false
	Toolkit._flush_quiet = 0.0
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## The scatter overrides round trip (strata M4, ONE_APP P4 scatter half): a
## synthetic baked export loads through ScatterBake; the hand's move/delete
## (ScatterHand) reshapes it; overrides.gd emits the deltas keyed by stable id
## for Strata to replay. Self-contained: writes a throwaway baked/ + hand.json,
## restores every file it touches so the checkout stays clean.
func _test_scatter_roundtrip() -> void:
	var baked_dir := ScatterBake.DIR
	var man := ScatterBake.MANIFEST
	var cell_file := baked_dir + "/cell_0_0.json"
	var hand := ScatterHand.PATH
	# Guard: snapshot (absent = null) everything we write, restore at the end.
	var guard := {}
	for p: String in [man, cell_file, hand, Overrides.FILE]:
		guard[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null
	var baked_preexisted := DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(baked_dir))

	# A one-prop baked export (ScatterBake reads the file directly; the sha is
	# only enforced by the importer, so a placeholder is fine here).
	var pid := "sc_probe0000abcd01"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(baked_dir))
	var cell_json := JSON.stringify([{
		"id": pid, "cat": "rocks", "x": 10.0, "y": 40.0, "z": 20.0,
		"yaw": 0.0, "scale": 1.0, "pick": 0.25}])
	_write_probe(cell_file, cell_json)
	_write_probe(man, JSON.stringify({
		"format": 1, "cell_size_m": 128.0, "count": 1,
		"world": {"size_m": [16384.0, 16384.0]},
		"cells": [{"cell": [0, 0], "file": "cell_0_0.json", "count": 1, "sha256": ""}]}))
	# Start from a clean hand store.
	if FileAccess.file_exists(hand):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(hand))
	ScatterHand.reload()
	ScatterBake.reset()

	# 1. Baked scatter loads; the prop is present, unmoved.
	_check(ScatterBake.has_baked(), "synthetic baked export is seen")
	_check(absf(ScatterBake.cell_size() - 128.0) < 0.001, "manifest cell size read")
	var loaded := ScatterBake.load_cell(Vector2i(0, 0))
	_check(loaded.size() == 1, "the baked cell loads one prop (got %d)" % loaded.size())
	if loaded.size() == 1:
		_check(String(loaded[0].get("id", "")) == pid
			and not bool(loaded[0].get("moved", true)), "the prop rides through unmoved")

	# 2. The hand moves it — the delta the Toolkit would write.
	ScatterHand.move(pid, Vector3(1000.0, 123.5, -2000.0), 1.25, 1.75, "rocks", 0.25)
	ScatterHand.reload()  # prove it persisted to disk, not just memory
	var moved := ScatterBake.load_cell(Vector2i(0, 0))
	_check(moved.size() == 1 and bool(moved[0].get("moved", false))
		and absf(float(moved[0].get("x", 0.0)) - 1000.0) < 0.001
		and absf(float(moved[0].get("y", 0.0)) - 123.5) < 0.001,
		"the hand's move repositions the baked prop (got %s)" % [moved])

	# 3. overrides.gd emits the delta keyed by the stable id.
	var counts := Overrides.emit()
	_check(int(counts.get("scatter", 0)) == 1, "emit reports one scatter delta")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Overrides.FILE))
	var sc: Dictionary = (parsed as Dictionary).get("scatter", {}) if parsed is Dictionary else {}
	_check(sc.has(pid), "overrides.json carries the scatter delta by id")
	if sc.has(pid):
		var d: Dictionary = sc[pid]
		_check(String(d.get("op", "")) == "move"
			and absf(float(d.get("x", 0.0)) - 1000.0) < 0.001
			and String(d.get("cat", "")) == "rocks",
			"the delta is a move carrying transform + category")

	# 4. A delete drops the prop and survives as a delete op.
	ScatterHand.remove(pid)
	ScatterHand.reload()
	_check(ScatterBake.load_cell(Vector2i(0, 0)).is_empty(),
		"a hand-deleted prop is gone from the baked load")
	Overrides.emit()
	var parsed2: Variant = JSON.parse_string(FileAccess.get_file_as_string(Overrides.FILE))
	var sc2: Dictionary = (parsed2 as Dictionary).get("scatter", {}) if parsed2 is Dictionary else {}
	_check(sc2.has(pid) and String((sc2[pid] as Dictionary).get("op", "")) == "delete",
		"the delete rides the seam artifact")

	# Restore every touched file; the hand store cache is reset for the process.
	for p: String in guard:
		var abs := ProjectSettings.globalize_path(p)
		if guard[p] == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(abs)
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_buffer(guard[p])
				f.close()
	if not baked_preexisted:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(baked_dir))
	ScatterHand.reload()
	ScatterBake.reset()


func _write_probe(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


## The stroke-quiet disk flush (audit quick win 3, crash-safety): hand
## edits write through the SAME F5 path a few seconds after the last
## stroke — nothing lands before FLUSH_QUIET, the biome PNG lands after.
## The original file bytes are restored so the checkout stays clean (the
## in-memory map is already reverted via Z, so memory == disk holds).
func _test_edit_flush() -> void:
	if Terrain._biome_img == null:
		print("  edit flush: SKIP (no biome map on this checkout)")
		return
	var png_path: String = Terrain.BIOME_MAP_PATH
	var orig_bytes := FileAccess.get_file_as_bytes(png_path)
	_check(not orig_bytes.is_empty(), "biome map PNG exists to flush over")
	# The flush now emits the P4 overrides artifact too — snapshot it so
	# this test leaves the checkout exactly as found.
	var ov_paths := [Overrides.FILE,
		Overrides.DIR + "/terrain_pen_override.f32z",
		Overrides.DIR + "/terrain_sculpt.f32z"]
	var ov_guard: Dictionary = {}
	for gp: String in ov_paths:
		ov_guard[gp] = FileAccess.get_file_as_bytes(gp) \
				if FileAccess.file_exists(gp) else null
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	var p := Vector2(-1200.0, 1200.0)
	var before: int = Terrain.biome_at(p.x, p.y)
	Toolkit._tool = Toolkit.Tool.BIOME
	Toolkit._biome_index = (before + 1) % Terrain.biomes.size()
	Toolkit._macro_radius = 60.0
	Toolkit._biome_paint_at(Vector3(p.x, 0.0, p.y))
	_check(Toolkit._flush_quiet == 0.0, "a stroke resets the flush clock")
	# Half the quiet window: the clock runs, nothing on disk yet.
	Toolkit._process(Toolkit.FLUSH_QUIET * 0.5)
	_check(Toolkit._biome_unsaved, "half the quiet window: no flush yet")
	_check(FileAccess.get_file_as_bytes(png_path) == orig_bytes,
		"half the quiet window: disk untouched")
	# Past the window: the flush fires — the same write F5 makes.
	Toolkit._process(Toolkit.FLUSH_QUIET)
	_check(not Toolkit._biome_unsaved, "stroke-quiet flush saved the biome map")
	_check(FileAccess.get_file_as_bytes(png_path) != orig_bytes,
		"the flush actually wrote the painted map")
	# Revert the stroke in memory, the file bytes on disk; leave no trace.
	Toolkit._undo()
	var f := FileAccess.open(png_path, FileAccess.WRITE)
	f.store_buffer(orig_bytes)
	f.close()
	for gp: String in ov_paths:
		var was: Variant = ov_guard[gp]
		if was == null:
			if FileAccess.file_exists(gp):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(gp))
		else:
			var g := FileAccess.open(gp, FileAccess.WRITE)
			g.store_buffer(was)
			g.close()
	Overrides.pending = false
	Overrides._layer_cache.clear()
	Toolkit._biome_unsaved = false
	Toolkit._biome_dirty = Rect2()
	Toolkit._flush_quiet = 0.0
	Toolkit.set_tool("sculpt")
	Toolkit._biome_index = 4
	Toolkit._macro_radius = 160.0
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()


## The shared condition language (Conditions) — the gate every future
## quest/dialogue will evaluate. The dialogue/quest ENGINES retired with
## the old valley; the language they spoke lives on and stays tested.
func _test_conditions() -> void:
	_check(Conditions.eval({}), "empty condition passes")
	WorldState.set_flag("test.flag")
	_check(Conditions.eval({"flag": "test.flag"}), "flag condition")
	_check(not Conditions.eval({"flag": "test.unset"}), "flag on unset fails")
	_check(not Conditions.eval({"not_flag": "test.flag"}), "not_flag condition")
	_check(Conditions.eval({"not_flag": "test.other"}), "not_flag on unset")
	WorldState.set_value("test.count", 3)
	_check(Conditions.eval({"gte": ["test.count", 3]}), "gte pass")
	_check(not Conditions.eval({"gte": ["test.count", 4]}), "gte fail")
	_check(not Conditions.eval({"item": ["nonexistent_item", 1]}), "item condition")
	# All keys AND together: one failing clause fails the whole gate.
	_check(not Conditions.eval({"flag": "test.flag", "gte": ["test.count", 4]}),
		"clauses AND — one failure fails the gate")


func _test_skills() -> void:
	# Skill records are game content (data/skills); a content-empty game
	# ships none. The derivation machinery — an unknown skill is level 0 —
	# is framework and always holds.
	if Skills.defs().is_empty():
		print("  skills: SKIP (no skill records — content-empty game)")
	else:
		_check(Skills.defs().size() >= 4, "skill records load")
		WorldState.set_value("player.dist_walked", 1300.0)
		_check(Skills.level("wayfaring") == 2, "wayfaring level from distance")
		WorldState.set_value("player.dist_walked", 0.0)
		_check(Skills.level("wayfaring") == 0, "level derives, never sticks")
	_check(Skills.level("nonexistent") == 0, "unknown skill is level 0")


## advance_hours is the shared catch-up path (load, laptop sleep, debug
## skip): it must tick every skipped hour and roll days across midnight.
func _test_clock() -> void:
	var ticks: Array = []
	var on_tick := func(h: int) -> void: ticks.append(h)
	GameClock.hour_tick.connect(on_tick)
	GameClock.hours = 22.0
	GameClock.day = 3
	GameClock.advance_hours(4.0)
	GameClock.hour_tick.disconnect(on_tick)
	_check(ticks.size() == 4, "advance fires hour_tick for every skipped hour")
	_check(ticks == [23, 0, 1, 2], "ticks pass through midnight in order")
	_check(GameClock.day == 4, "day rolls over during advance")
	_check(absf(GameClock.hours - 2.0) < 0.001, "clock lands on the right hour")
	_check(absf(GameClock.hours_delta(3600.0) - 1.0) < 0.001,
		"1:1 time — one real hour is one game hour")
	var day_before: int = GameClock.day
	GameClock.return_to_now()
	_check(absf(GameClock.hours - GameClock.civil_now()) < 0.01,
		"return_to_now re-anchors to real local time")
	_check(GameClock.day == day_before, "return_to_now keeps days lived")


## The clock LOCK (2026-07-09): a REAL hold. While held, the automatic 1:1
## _process advance is suspended and the swallowed wall gap is not banked;
## an EXPLICIT advance_hours (the `time`/`scrub` verbs, the T key) still
## moves the clock, and the lock stays engaged after (scrub-then-re-hold).
## Determinism: holding does no sim work, so it's a no-op on the fingerprint.
func _test_clock_lock() -> void:
	var was_held: bool = GameClock.held
	var h0: float = GameClock.hours
	var d0: int = GameClock.day
	# Engage via the link verb — the mirror-truth reply and the WorldState
	# mirror both land.
	var on := StrataLink._execute("time_lock on")
	_check(on == "ok time_lock on", "time_lock on answers the state (got %s)" % on)
	_check(GameClock.held, "time_lock on holds the clock")
	_check(bool(WorldState.get_value("time.hold", false)),
		"the clock lock mirrors to WorldState (saves)")
	# A held clock does NOT auto-advance: drive one real-time tick (the same
	# path _process takes) and assert the dial holds. Both the small-delta
	# ease and the large-gap catch-up are swallowed while held.
	GameClock.hours = 8.0
	GameClock._tick(1.0)      # small-delta ease path
	GameClock._tick(3600.0)   # large-gap catch-up path
	_check(absf(GameClock.hours - 8.0) < 1e-6, "a held clock ignores the auto-advance")
	# An EXPLICIT move still works while locked (the scrub/T-key door), and the
	# lock survives the move.
	GameClock.advance_hours(2.0)
	_check(absf(GameClock.hours - 10.0) < 1e-6, "advance_hours moves a locked clock (explicit)")
	_check(GameClock.held, "the clock stays locked after an explicit move (scrub re-holds)")
	# Release: the dial is free again and the mirror clears.
	var off := StrataLink._execute("time_lock off")
	_check(off == "ok time_lock off", "time_lock off answers the state (got %s)" % off)
	_check(not GameClock.held, "time_lock off frees the clock")
	_check(not bool(WorldState.get_value("time.hold", true)),
		"the released lock mirrors to WorldState")
	# Idempotent.
	_check(StrataLink._execute("time_lock on") == "ok time_lock on"
			and StrataLink._execute("time_lock on") == "ok time_lock on",
		"time_lock is idempotent")
	_check(StrataLink._execute("time_lock wobble").begins_with("err time_lock"),
		"time_lock rejects a bad arg")
	# Leave no trace.
	GameClock.set_hold(was_held)
	GameClock.hours = h0
	GameClock.day = d0


## The weather LOCK (2026-07-09): while held, hourly evolution pauses — the
## fronts don't march, none spawn, the wind stops wandering. The per-frame
## render eases continue (the Elements keep drawing the held state). Catch-up
## replays hour_ticks through the same guard, so a locked sky holds across a
## skipped stretch.
func _test_weather_lock() -> void:
	var was_held: bool = Weather.held
	# A known starting sky. force_kind appends a full-cover front — hold a
	# REFERENCE to it (GDScript dicts are by-ref) so index churn from later
	# spawns/expiries can't fool the march check.
	Weather.force_kind("storm")
	var front: Dictionary = Weather.fronts[Weather.fronts.size() - 1]
	var edge_before: float = float(front.edge)
	var on := StrataLink._execute("weather_lock on")
	_check(on == "ok weather_lock on", "weather_lock on answers the state (got %s)" % on)
	_check(Weather.held, "weather_lock on holds the weather")
	_check(bool(WorldState.get_value("weather.hold", false)),
		"the weather lock mirrors to WorldState (saves)")
	# Drive many hour_ticks and assert nothing evolved: same front count, the
	# tracked front's edge unmoved (no march), the wind angle unmoved.
	var count_before: int = Weather.fronts.size()
	var angle_before: float = Weather._wind_angle
	for h in 12:
		Weather._transition(h)
	_check(Weather.fronts.size() == count_before, "a held sky spawns no new fronts")
	_check(absf(float(front.edge) - edge_before) < 1e-6, "a held sky does not march its fronts")
	_check(absf(Weather._wind_angle - angle_before) < 1e-9, "a held sky's wind stops wandering")
	# Release: evolution resumes — one tick now marches the tracked front.
	var off := StrataLink._execute("weather_lock off")
	_check(off == "ok weather_lock off", "weather_lock off answers the state (got %s)" % off)
	_check(not Weather.held, "weather_lock off frees the weather")
	Weather._transition(0)
	# Re-read the march off the LIVE array, not the by-ref dict: under
	# STRATA_CONTOUR the §6 Weather system rebuilds the fronts array (fresh dict
	# objects), so a stale pointer wouldn't see the march. A front dict's OBJECT
	# IDENTITY is not the sim contract — its CONTENTS are (the soak fingerprint
	# pins those, flag-ON == flag-OFF). The full-cover storm marches to
	# edge_before + speed*3600 and is never dropped; a fresh spawn sits windward
	# at -WORLD_R (< edge_before), so a storm past edge_before is the marched one.
	var marched := false
	for f: Dictionary in Weather.fronts:
		if String(f.kind) == "storm" and float(f.edge) > edge_before:
			marched = true
	_check(marched, "a freed sky marches again")
	_check(StrataLink._execute("weather_lock wobble").begins_with("err weather_lock"),
		"weather_lock rejects a bad arg")
	# Leave no trace.
	Weather.set_hold(was_held)


## Fix 4a: "weather clear" (and any unrecognized kind coming over the
## untrusted link) must NEVER crash force_kind on KINDS[kind].speed — the
## KINDS table has no "clear" key, so an unguarded force_kind died with
## "Invalid get index on Nil". force_kind now falls back to "calm" (the same
## guard load_state() carries), and the "weather" link verb reports the kind
## actually forced, so the reply stays honest.
func _test_weather_clear() -> void:
	var was_held: bool = Weather.held
	# Over the REAL link verb path (the crash's entry point, strata_link.gd).
	var reply := StrataLink._execute("weather clear")
	_check(reply == "ok weather calm",
		"weather clear normalizes to calm and reports it honestly (got %s)" % reply)
	_check(Weather.state == "calm", "force_kind('clear') leaves a valid state, no crash")
	_check(Weather.fronts.size() > 0
			and String(Weather.fronts[Weather.fronts.size() - 1].kind) == "calm",
		"force_kind('clear') appended a valid full-cover calm front")
	# A direct call with a bogus kind also normalizes rather than crash, and
	# returns the resolved kind.
	_check(Weather.force_kind("nonsense_kind") == "calm",
		"force_kind normalizes an unknown kind to calm")
	# A KNOWN kind is untouched (the guard only catches misses).
	_check(Weather.force_kind("storm") == "storm",
		"force_kind passes a known kind through unchanged")
	Weather.set_hold(was_held)


## Seasons follow the real calendar; daylight, solar noon, and the
## solar-hour warp derive from the real date and the player's location.
func _test_seasons() -> void:
	_check(GameClock.season_for({"month": 1, "day": 15}) == "winter", "january is winter")
	_check(GameClock.season_for({"month": 3, "day": 19}) == "winter", "mar 19 still winter")
	_check(GameClock.season_for({"month": 3, "day": 20}) == "spring", "mar 20 turns spring")
	_check(GameClock.season_for({"month": 7, "day": 2}) == "summer", "july is summer")
	_check(GameClock.season_for({"month": 10, "day": 5}) == "autumn", "october is autumn")
	_check(GameClock.season_for({"month": 12, "day": 21}) == "winter", "dec 21 turns winter")
	_check(GameClock.season_for({"month": 12, "day": 25}, true) == "summer",
		"southern hemisphere flips the season")
	var solstice_summer: float = GameClock.daylight_hours_for(172, 45.0)
	var solstice_winter: float = GameClock.daylight_hours_for(355, 45.0)
	_check(solstice_summer > 15.0, "summer solstice daylight is long at 45N")
	_check(solstice_winter < 9.0, "winter solstice daylight is short at 45N")
	_check(absf(GameClock.daylight_hours_for(172, 0.0) - 12.1) < 0.3,
		"equator stays near 12h year round")
	_check(GameClock.daylight_hours_for(172, -45.0) < 9.0,
		"southern winter in june")
	_check(GameClock.daylight_hours_for(172, 89.0) <= 23.5,
		"polar day clamps — the sun always sets")
	_check(GameClock.season != "", "live season is set")
	_check(WorldState.get_value("time.season") == GameClock.season,
		"season mirrored to WorldState")
	var span: Vector2 = GameClock.daylight_span()
	_check(span.y > span.x, "sunrise precedes sunset")
	var today_dl: float = GameClock.daylight_hours_for(
		GameClock.day_of_year(Time.get_date_dict_from_system()), Settings.latitude)
	_check(absf((span.y - span.x) - today_dl) < 0.01,
		"span width matches the sunrise equation")
	GameClock.hours = fposmod(span.x, 24.0)
	_check(absf(GameClock.solar_hours() - 6.0) < 0.01, "sunrise maps to solar 6:00")
	GameClock.hours = fposmod(span.y - 0.001, 24.0)
	_check(absf(GameClock.solar_hours() - 18.0) < 0.05, "sunset maps to solar 18:00")
	GameClock.hours = fposmod((span.x + span.y) * 0.5, 24.0)
	_check(absf(GameClock.solar_hours() - 12.0) < 0.01, "solar noon maps to 12:00")


## Water contract on the Strata world: authored lakes/rivers retired, so
## the water language must hold with only the world sea present.
func _test_water() -> void:
	# The authored-body arrays are valid (possibly empty) — no crash on
	# a world Strata dressed without hand-placed lakes/rivers.
	_check(Terrain.water_bodies is Array, "water_bodies is a valid (maybe empty) list")
	_check(Terrain.rivers is Array, "rivers is a valid (maybe empty) list")
	# A content-empty game has no sea record — the Watershed's guard/surface
	# geometry below is a property of a LOADED world (a sea level, an
	# imported lake). The Watershed machinery is proven by _test_hydrology /
	# _test_strata_water; here we need a world to stand in.
	if Terrain.sea_level <= -1e11:
		print("  water: SKIP (no sea record — content-empty game)")
		return
	# The world sea level loads from the record.
	_check(Terrain.sea_level > -1e11, "the world sea level loads from the record")
	# The home valley is guarded OUT of the open sea (home_guard is 0 in the
	# protected interior). With the authored pond retired, water here can
	# only come from an imported hyd_* lake record (ONE_APP P2) — never a
	# leftover of the retired pond, never the sea leaking past the guard.
	var wc := Vector2(65.0, -285.0)  # the watershed center — inside the guard
	_check(Terrain.home_guard(wc.x, wc.y) == 0.0, "home valley sits inside the guard")
	var covered := false
	for w in Terrain.water_bodies:
		if String(w.id).begins_with("hyd_") \
				and Vector2(w.center).distance_to(wc) < float(w.radius):
			covered = true
	if covered:
		_check(Terrain.water_surface(wc.x, wc.y) > -1e6,
			"an imported lake over the home interior answers water")
	else:
		_check(Terrain.water_surface(wc.x, wc.y) < -1e6,
			"no water in the guarded home interior once the pond is retired")
	# Everything beyond the guard is the open world sea.
	_check(Terrain.home_guard(9000.0, 9000.0) > 0.0, "the open world lies outside the guard")
	_check(is_equal_approx(Terrain.water_surface(9000.0, 9000.0), Terrain.sea_surface()),
		"the world sea fills everything outside the home guard")


## W1 ocean swell: presentation-only (off headless), but its energy math
## is a pure function — pin the herald: storm swell precedes the storm,
## grows monotonically as the front nears, peaks overhead, and a calm
## sea still breathes. Physics stays flat: sea_surface() ignores swell.
func _test_swell() -> void:
	var wdir := Vector2(1.0, 0.0)
	var storm_at := func(edge: float) -> Array:
		return [{"kind": "storm", "dx": 1.0, "dz": 0.0, "edge": edge,
			"width": 4000.0, "speed": 4.0}]
	var focus := Vector2.ZERO
	var calm: Dictionary = SeaSwell.compute([], focus, 0.12, wdir)
	var far: Dictionary = SeaSwell.compute(storm_at.call(-8000.0), focus, 0.12, wdir)
	var near_f: Dictionary = SeaSwell.compute(storm_at.call(-2000.0), focus, 0.12, wdir)
	var over: Dictionary = SeaSwell.compute(storm_at.call(1000.0), focus, 0.12, wdir)
	_check(float(calm.amp) > 0.0, "a calm sea still breathes")
	_check(float(far.amp) < float(near_f.amp), "swell grows as the storm nears")
	_check(float(near_f.amp) < float(over.amp), "an overhead storm rolls hardest")
	_check(float(over.amp) > 3.0 * float(calm.amp),
		"storm swell reads far bigger than calm")
	_check(String(near_f.source) == "storm",
		"an approaching storm owns the swell before its rain arrives")
	_check(float(near_f.len) > float(calm.len), "heavy swell runs longer wavelengths")
	_check(Vector2(near_f.dir).is_equal_approx(wdir),
		"swell travels the front's own heading")
	# The sea the sim sees is untouched: flat level + tide only.
	var flat_sea: float = Terrain.sea_surface()
	_check(absf(flat_sea - Terrain.sea_level) <= Terrain.TIDE_AMP + 1e-4,
		"sea_surface() stays flat-sea + tide — the swell is presentation only")


## W2 shoaling + breakers: the shader's per-vertex math has a pure
## GDScript mirror on SeaSwell — pin it. Gain is 1 in the deep (the open
## sea is untouched), grows monotonically as depth shrinks, and caps;
## the 0.78 surf criterion breaks a storm on the shallow bar, spares the
## deep coast, and spares the same bar under a calm sea.
func _test_shoaling() -> void:
	var deep := SeaSwell.shoal_gain(40.0, 200.0)
	_check(absf(deep - 1.0) < 1e-3, "deep water swell is unchanged")
	var g8 := SeaSwell.shoal_gain(40.0, 8.0)
	var g3 := SeaSwell.shoal_gain(40.0, 3.0)
	var g1 := SeaSwell.shoal_gain(40.0, 1.0)
	_check(g8 > deep and g3 > g8 and g1 >= g3,
		"shoaling gain grows monotonically as depth shrinks")
	_check(g1 <= SeaSwell.SHOAL_MAX + 1e-6, "shoal gain caps (Green's law bounded)")
	# Storm primary component: SWELL_MAX * PRIMARY_SHARE ≈ 0.42m amp.
	var storm_a: float = SeaSwell.SWELL_MAX * SeaSwell.PRIMARY_SHARE
	_check(SeaSwell.break_frac(storm_a, 60.0, 1.2) > 1.0,
		"storm swell breaks on the 1.2m bar")
	_check(SeaSwell.break_frac(storm_a, 60.0, 10.0) < 1.0,
		"ten meters of water carries storm swell unbroken")
	_check(SeaSwell.break_frac(SeaSwell.BASE_AMP * SeaSwell.PRIMARY_SHARE,
			24.0, 1.2) < 1.0, "a calm sea spares the same bar")
	_check(SeaSwell.break_depth(storm_a, 60.0)
			> SeaSwell.break_depth(0.1 * SeaSwell.PRIMARY_SHARE, 30.0),
		"heavier swell breaks in deeper water — the surf band widens with the storm")


## S3 buoyancy: the SeaSwell CPU mirror (surface_at/probe_at) pinned against
## the shader's deep-water Gerstner math, then a FloatBody driven headless —
## it rides a rising level up and drifts downstream on its mooring tether.
## Presentation-only: nothing here touches WorldState or the soak digest.
func _test_buoyancy() -> void:
	var was_amp: float = SeaSwell.amp
	var was_len: float = SeaSwell.wavelength
	var was_dir: Vector2 = SeaSwell.direction
	# --- The mirror (surface_at / probe_at) ---
	SeaSwell.amp = 0.8
	SeaSwell.wavelength = 55.0
	SeaSwell.direction = Vector2(1.0, 0.0)
	# The raw forward map: the un-inverted Gerstner sum at a REST point p,
	# time t — returns [hoff (the horizontal displacement to its world spot),
	# height, slope]. probe_at inverts this, so it is the ground truth to
	# pin against (and reads SeaSwell's own public constants — one lockstep).
	var raw := func(p: Vector2, t: float) -> Array:
		var ho := Vector2.ZERO
		var hh := 0.0
		var gr := Vector2.ZERO
		for i in 4:
			var wl: float = SeaSwell.wavelength * SeaSwell.LSC[i]
			var a: float = SeaSwell.amp * SeaSwell.ASC[i] * smoothstep(
				SeaSwell.SWELL_STEP * 2.0, SeaSwell.SWELL_STEP * 3.0, wl)
			if a < 1e-4:
				continue
			var d: Vector2 = SeaSwell.direction.rotated(SeaSwell.ROT[i])
			var k := TAU / wl
			var w: float = sqrt(SeaSwell.GRAV * k)
			var ph := k * (d.x * p.x + d.y * p.y) - w * t
			var c := cos(ph)
			hh += a * sin(ph)
			ho -= d * (SeaSwell.TROCHOID * a * c)
			gr += d * (k * a * c)
		return [ho, hh, gr]
	# At the rest-origin every phase is zero (t=0, dot=0): still water,
	# sloping along the swell heading. Probe at the WORLD point it displaces
	# to (its hoff) — the world origin is NOT the rest origin (the trochoid
	# gathers it aside), which is exactly what probe_at must invert.
	var r0: Array = raw.call(Vector2.ZERO, 0.0)
	var o: Vector3 = SeaSwell.probe_at((r0[0] as Vector2).x, (r0[0] as Vector2).y, 0.0)
	_check(absf(o.y) < 0.02, "buoyancy: still water at the phase origin")
	_check(o.x > 0.0, "buoyancy: the surface slope points along the swell heading")
	# A crest and a trough exist, bounded by the summed amplitudes (0.8).
	var hmax := -1e9
	var hmin := 1e9
	for i in 220:
		var hh: float = SeaSwell.surface_at(55.0 * float(i) / 220.0, 0.0, 0.0)
		hmax = maxf(hmax, hh)
		hmin = minf(hmin, hh)
	_check(hmax > 0.15 and hmin < -0.15,
		"buoyancy: the swell carries a crest and a trough")
	_check(hmax < 0.85 and hmin > -0.85,
		"buoyancy: the crest is bounded by the summed amplitudes")
	# Height scales with swell energy — a storm rides higher than a breeze.
	SeaSwell.amp = 0.4
	var half := -1e9
	for i in 220:
		half = maxf(half, SeaSwell.surface_at(55.0 * float(i) / 220.0, 0.0, 0.0))
	_check(hmax > half * 1.5, "buoyancy: a bigger swell rides higher")
	SeaSwell.amp = 0.8
	# The trochoid inversion recovers a known crest: forward-map a rest point
	# with the raw sum, then surface_at at the displaced world point must
	# return its height (proves the fixed-point undoes the horizontal gather —
	# without it the read would be the better part of a meter off).
	var p0 := Vector2(12.0, -5.0)
	var tt := 3.7
	var rr: Array = raw.call(p0, tt)
	var world: Vector2 = p0 + (rr[0] as Vector2)
	_check(absf(SeaSwell.surface_at(world.x, world.y, tt) - float(rr[1])) < 0.05,
		"buoyancy: the trochoid inversion recovers the crest height")
	# A calm sea (below the 0.001m gate) sits floaters dead flat.
	SeaSwell.amp = 0.0
	_check(SeaSwell.probe_at(3.0, 4.0, 1.0) == Vector3.ZERO,
		"buoyancy: a calm sea sits floaters flat")
	SeaSwell.amp = was_amp
	SeaSwell.wavelength = was_len
	SeaSwell.direction = was_dir

	# --- The FloatBody, driven headless on an injected surface ---
	var fb := FloatBody.new()
	var hull := Node3D.new()
	add_child(hull)
	fb.target = hull
	fb.moor = Vector3.ZERO
	fb.tether = 3.0
	# A surface that ramps with a level knob and slopes gently along +x, plus
	# a strong east current — deterministic, no GPU, no wall-clock.
	var lvl := {"y": 0.0}
	fb.surface_fn = func(pos: Vector3, _t: float) -> Vector3:
		return Vector3(0.0, lvl.y + pos.x * 0.05, 0.0)
	fb.current_fn = func(_pos: Vector3) -> Vector2:
		return Vector2(5.0, 0.0)
	for _i in 60:
		fb.step(0.1, 0.0)
	_check(absf(hull.position.y) < 0.2, "buoyancy: a floater settles onto the calm surface")
	# Raise the water — the hull rides the level up.
	lvl.y = 2.0
	for _i in 60:
		fb.step(0.1, 0.0)
	_check(hull.position.y > 1.5, "buoyancy: a floater rides a rising level up")
	# The current drifts it downstream; the mooring tethers how far.
	_check(hull.position.x > 0.15, "buoyancy: the current drifts a floater downstream")
	_check(hull.position.x <= fb.tether + 1e-3, "buoyancy: the mooring tethers the drift")
	# It leans into the surface slope, but never rolls over.
	var lean: float = Vector3.UP.angle_to(hull.basis.y)
	_check(lean > 0.01, "buoyancy: a floater leans into the surface slope")
	_check(lean <= FloatBody.LEAN_MAX + 1e-3,
		"buoyancy: the lean is bounded — a roll, not a capsize")
	hull.queue_free()
	fb.free()

	# --- The acceptance A/B: bobs on storm swell, sits flat at dawn calm ---
	# Drive a FloatBody off the REAL SeaSwell mirror (a hull at a fixed
	# mooring, no current) and watch its height across time.
	var bob := FloatBody.new()
	var hull2 := Node3D.new()
	add_child(hull2)
	bob.target = hull2
	bob.moor = Vector3(20.0, 0.0, -8.0)
	bob.tether = 0.0   # pin the mooring — only the vertical bob shows
	bob.current_fn = func(_pos: Vector3) -> Vector2:
		return Vector2.ZERO
	bob.surface_fn = func(pos: Vector3, t: float) -> Vector3:
		return SeaSwell.probe_at(pos.x, pos.z, t)
	# Storm swell: the hull rolls up and down as the crests pass under it.
	SeaSwell.amp = 0.8
	SeaSwell.wavelength = 55.0
	SeaSwell.direction = Vector2(1.0, 0.0)
	var ymin := 1e9
	var ymax := -1e9
	for i in 240:
		bob.step(0.05, float(i) * 0.05)
		if i >= 120:  # let the spring lock on, then measure the swing
			ymin = minf(ymin, hull2.position.y)
			ymax = maxf(ymax, hull2.position.y)
	_check(ymax - ymin > 0.1, "buoyancy: storm swell rolls the hull up and down")
	# Dawn calm: flatten the sea, let it settle — the bob dies flat.
	SeaSwell.amp = 0.0
	for i in 120:
		bob.step(0.05, 12.0 + float(i) * 0.05)
	var y_calm: float = hull2.position.y
	var settled := absf(y_calm) < 0.05
	for i in 60:
		bob.step(0.05, 18.0 + float(i) * 0.05)
		if absf(hull2.position.y - y_calm) > 0.02:
			settled = false
	_check(settled, "buoyancy: a dawn-calm sea sits the hull flat")
	hull2.queue_free()
	bob.free()
	SeaSwell.amp = was_amp
	SeaSwell.wavelength = was_len
	SeaSwell.direction = was_dir


func _test_hydrology() -> void:
	# One tick builds the catchments from real flow routing.
	var was_state: String = Weather.state
	var was_wet: float = Climate.wetness
	Weather.force_kind("calm")
	Climate.wetness = 0.5
	# The domain comes from the watershed record, not code (the map is
	# replaceable; the system isn't).
	_check(Hydrology.center == Vector2(65.0, -285.0) and Hydrology.domain == 2048.0,
		"watershed domain loads from data/water/watersheds/home.json")
	# With the authored pond/brook retired, the watershed routes and runs
	# its hourly balance over empty water — it must not crash, and its
	# level dicts stay valid (empty is fine until Strata proposes rivers).
	for i in 6:
		Hydrology._hourly(0)
	_check(Hydrology.lake_level is Dictionary and Hydrology.river_storage is Dictionary,
		"hydrology runs clean with no authored water bodies")
	# Contour routing plumbing (Wave D2; F1 THE FLIP): STRATA_CONTOUR now defaults
	# ON, so a default scene-test boot with a live kernel ENGAGES (mode 2) and the 6
	# _hourly calls above routed through the native §6 `Hydrology` system — the tick
	# counter EARNED it, no silent fallback. The escape hatch (STRATA_CONTOUR=0) or a
	# kernel-less platform resolves to the GDScript twin (mode 1, or a loud -1) with
	# the counter at 0. Assert whichever posture this boot resolved; the flag-off ==
	# flag-on fingerprint (identical worlds) is proven by the six-run soak matrix.
	var hyd_cs: Dictionary = Hydrology.contour_status()
	if bool(hyd_cs.get("engaged", false)):
		_check(int(hyd_cs.get("mode", 0)) == 2 and int(hyd_cs.get("calls", 0)) > 0,
			"hydrology Contour routing ENGAGED by default (native §6 ticks earned the counter, no silent fallback)")
	else:
		_check((int(hyd_cs.get("mode", 0)) == 1 or int(hyd_cs.get("mode", 0)) == -1)
				and int(hyd_cs.get("calls", -1)) == 0,
			"hydrology Contour routing off (=0 hatch / kernel-less) — GDScript twin, no silent engage")
	for id in Hydrology.lake_level:
		var lv: float = Hydrology.lake_level[id]
		_check(lv >= Hydrology.LAKE_LEVEL_MIN and lv <= Hydrology.LAKE_LEVEL_MAX,
			"any lake level stays on its rails")
	# Snowmelt catch-up (audit finding): _last_snow must resume from the
	# SAVED snow, not boot's 0.0 — else the first replayed hour after a
	# snowy reload drops that hour's meltwater and rivers/lakes diverge
	# from continuous play. Simulate restore: set the saved key, corrupt
	# _last_snow to the boot value, reload.
	var saved_snow: float = float(WorldState.get_value("climate.snow", 0.0))
	WorldState.set_value("climate.snow", 0.4)
	Hydrology._last_snow = 0.0
	Hydrology.load_state()
	_check(is_equal_approx(Hydrology._last_snow, 0.4),
		"load_state resumes _last_snow from saved snow (no dropped meltwater)")
	WorldState.set_value("climate.snow", saved_snow)
	Hydrology._last_snow = Climate.snow
	Weather.force_kind(was_state)
	Climate.wetness = was_wet


## Wave G2: `system SimRivers` + `system Lakes` (game/world/sim_rivers.ct,
## game/world/lakes.ct) route the two sibling leaves Wave D3 certified
## (sim_river_step, lake_step) — the recorded next rung off the Hydrology row.
## Both are FINGERPRINT-DORMANT in the home fixture (_test_hydrology already
## proves "no authored water bodies" there), so parity for these two rides
## Plumb (fresh manifest rows over the deployed sim_rivers.ct/lakes.ct copies)
## plus THIS dedicated fixture: an authored sim-tier river pair feeding an
## authored sim-tier lake, built the same way _test_strata_water builds a
## region river (Terrain._river_from_record), temporarily spliced into
## Terrain's live arrays so a real _hourly tick exercises the routed path
## end-to-end, then torn back down so no later test sees the fixture.
func _test_hydrology_sim_lakes_contour() -> void:
	var rivers_before: Array = Terrain.rivers.duplicate()
	var bodies_before: Array = Terrain.water_bodies.duplicate()
	var levels_before := Terrain.river_levels.duplicate()
	var lake_levels_before := Terrain.lake_levels.duplicate()
	var storage_before: Dictionary = Hydrology.river_storage.duplicate()
	var lake_level_before: Dictionary = Hydrology.lake_level.duplicate()
	var catchment_before: Dictionary = Hydrology.catchment_area.duplicate()

	# Two short sim-tier rivers (no_sim absent -> false), mouths at the same
	# point so both feed one authored sim-tier lake there — the cross-basin
	# coupling this system split keeps host-side (THE lake sums both).
	var mouth := Vector2(9000.0, 9000.0)  # far outside the home watershed grid
	# Record -> _index_river -> append: the SAME seating _load_rivers/add_river
	# perform (terrain.gd). EVERY river in Terrain's registry must carry the
	# renderer index fields (bbox/grid/grid_w — built by _index_river) or
	# _river_probe script-errors on every height/carve query for as long as the
	# fixture is spliced in (caught by the gate's script-error tripwire: ~1400
	# 'bbox' errors from the Climate/Weather terrain sampling inside the four
	# _hourly ticks below). The W4 one-river-renderer law: one registry, fully
	# indexed records only, never a half-record.
	var r1 := Terrain._river_from_record({
		"id": "g2_test_r1",
		"nodes": [
			{"x": mouth.x - 40.0, "z": mouth.y, "width": 3.0, "surface": 10.0},
			{"x": mouth.x, "z": mouth.y, "width": 3.0, "surface": 9.0}]},
		"g2_test_r1")
	Terrain._index_river(r1)
	Terrain.rivers.append(r1)
	var r2 := Terrain._river_from_record({
		"id": "g2_test_r2",
		"nodes": [
			{"x": mouth.x, "z": mouth.y - 40.0, "width": 2.5, "surface": 10.5},
			{"x": mouth.x, "z": mouth.y, "width": 2.5, "surface": 9.0}]},
		"g2_test_r2")
	Terrain._index_river(r2)
	Terrain.rivers.append(r2)
	Terrain.river_levels.resize(Terrain.rivers.size())
	Terrain.river_levels[r1.idx] = 0.0
	Terrain.river_levels[r2.idx] = 0.0
	var lake := Terrain._lake_from_record({
		"id": "g2_test_lake", "center": {"x": mouth.x, "z": mouth.y},
		"radius": 20.0, "surface": 8.0, "outlet": "aquifer"},
		"g2_test_lake", Terrain.water_bodies.size())
	Terrain.water_bodies.append(lake)
	Terrain.lake_levels.resize(Terrain.water_bodies.size())
	Terrain.lake_levels[lake.idx] = 0.0

	# Seed Hydrology's own state the way _ready seeds boot-authored water
	# (SimRivers/Lakes never re-derive a fixture's storage/catchment on their
	# own — that stays host-orchestrated, same as every other route_* leaf).
	Hydrology.river_storage[r1.id] = Hydrology.SPRING_M3H / Hydrology.RIVER_K
	Hydrology.river_storage[r2.id] = Hydrology.SPRING_M3H / Hydrology.RIVER_K
	Hydrology.catchment_area[r1.id] = 5e4
	Hydrology.catchment_area[r2.id] = 3e4
	Hydrology.lake_level[lake.id] = 0.0

	for i in 4:
		Hydrology._hourly(0)

	_check(Hydrology.river_storage.has(r1.id) and Hydrology.river_storage.has(r2.id),
		"the authored sim rivers keep breathing under Hydrology")
	_check(is_finite(float(Hydrology.river_storage[r1.id]))
			and float(Hydrology.river_storage[r1.id]) >= 0.0,
		"g2_test_r1 storage stays finite and non-negative")
	_check(Hydrology.lake_level.has(lake.id), "the authored sim lake keeps a level")
	var lv: float = Hydrology.lake_level[lake.id]
	_check(lv >= Hydrology.LAKE_LEVEL_MIN and lv <= Hydrology.LAKE_LEVEL_MAX,
		"g2_test_lake's level stays on its rails after 4 routed ticks")

	# Routing introspection: SimRivers/Lakes resolve to the SAME posture as
	# Hydrology (one boot, one STRATA_CONTOUR flag) — engaged earns a call
	# count > 0 with no refusal; off/kernel-less earns exactly 0, same law
	# _test_hydrology already asserts for the region-river system.
	var cs: Dictionary = Hydrology.contour_status()
	if bool(cs.get("sim_engaged", false)):
		_check(int(cs.get("sim_mode", 0)) == 2 and int(cs.get("sim_calls", 0)) > 0,
			"SimRivers routing ENGAGED by default (native §6 ticks earned the counter)")
	else:
		_check((int(cs.get("sim_mode", 0)) == 1 or int(cs.get("sim_mode", 0)) == -1)
				and int(cs.get("sim_calls", -1)) == 0,
			"SimRivers routing off (=0 hatch / kernel-less) — GDScript twin, no silent engage")
	if bool(cs.get("lake_engaged", false)):
		_check(int(cs.get("lake_mode", 0)) == 2 and int(cs.get("lake_calls", 0)) > 0,
			"Lakes routing ENGAGED by default (native §6 ticks earned the counter)")
	else:
		_check((int(cs.get("lake_mode", 0)) == 1 or int(cs.get("lake_mode", 0)) == -1)
				and int(cs.get("lake_calls", -1)) == 0,
			"Lakes routing off (=0 hatch / kernel-less) — GDScript twin, no silent engage")

	# Tear down: restore every array/dict this test spliced into, so no later
	# test (or the soak, if this ever ran inside one) sees the fixture.
	Terrain.rivers = rivers_before
	Terrain.water_bodies = bodies_before
	Terrain.river_levels = levels_before
	Terrain.lake_levels = lake_levels_before
	Hydrology.river_storage = storage_before
	Hydrology.lake_level = lake_level_before
	Hydrology.catchment_area = catchment_before


## ONE_APP P2: Strata's hydrology.json lands as hyd_* water records —
## rivers on the region tier (real catchment, breathing discharge), lakes
## at their fill elevation on the region lake tier, waterfalls riding the
## river dicts. The cache half skips honestly on checkouts that never
## imported a P2 export; the record normalization half always runs.
func _test_strata_water() -> void:
	# Normalization is a pure function — pin the waterfall carry-through
	# without needing any imported cache on disk.
	var rec := {"id": "t", "no_sim": true, "catchment_m2": 5e5,
		"waterfalls": [{"x": 10.0, "z": -4.0, "drop_m": 3.5}],
		"nodes": [
			{"x": 0.0, "z": 0.0, "width": 4.0, "surface": 10.0},
			{"x": 50.0, "z": 0.0, "width": 6.0, "surface": 8.0}]}
	var river := Terrain._river_from_record(rec, "t")
	var falls: Array = river.falls
	_check(falls.size() == 1 and Vector2(falls[0].pos) == Vector2(10.0, -4.0)
			and is_equal_approx(float(falls[0].drop), 3.5),
		"waterfall records normalize onto the river dict")
	# The soak digest law: imported (regenerable) water never reaches the
	# fingerprinted dicts, whatever is on disk.
	_check(not str(Hydrology.lake_level).contains("hyd_")
			and not str(Hydrology.river_storage).contains("hyd_"),
		"hyd_* records stay out of the fingerprinted dicts")

	var hyd_rivers: Array = []
	for r in Terrain.rivers:
		if String(r.id).begins_with("hyd_"):
			hyd_rivers.append(r)
	var hyd_lakes: Array = []
	for w in Terrain.water_bodies:
		if String(w.id).begins_with("hyd_"):
			hyd_lakes.append(w)
	if hyd_rivers.is_empty() and hyd_lakes.is_empty():
		print("  strata water: SKIP (no hyd_* cache — import a P2 export to exercise it)")
		return
	for r in hyd_rivers:
		_check(Hydrology.region_storage.has(r.id),
			"%s breathes on the region tier" % r.id)
		_check(Hydrology.flow_norm(r.id) > 0.0, "%s flows at baseflow" % r.id)
		_check(float(r.catchment) > 0.0, "%s carries its real catchment" % r.id)
	for w in hyd_lakes:
		_check(Hydrology.region_lake_level.has(w.id),
			"%s level rides the region lake tier" % w.id)
		var c: Vector2 = w.center
		_check(absf(Terrain.water_surface(c.x, c.y)
				- (float(w.surface) + Terrain.lake_levels[w.idx])) < 1e-3,
			"%s answers water at its fill elevation" % w.id)
		_check(float(w.basin_depth) == 0.0,
			"%s never re-carves the tile (the depression is already in it)" % w.id)


## The river ribbon must HUG the valley floor, not float above it: the drape
## (water_bodies._drape) clamps its downstream pooling to the local ground so
## the water surface never hangs over the dips and meanders that fall between
## the coarse (~48m) record nodes. Two synthetic profiles pin both halves of
## the fix, then the real imported bake proves the regression on live data.
func _test_river_drape() -> void:
	var WB: GDScript = load("res://game/world/water_bodies.gd")
	var depth := 1.2
	var eps := 1e-3

	# (1) Open dip: the ground itself dips between two record nodes. The old
	# unbounded max-scan lifted the dip to the downstream node's level —
	# floating meters over the floor. The clamp holds it at the ground.
	var open_pos: Array = [Vector2(0, 0), Vector2(48, 0), Vector2(96, 0)]
	var open_surf := PackedFloat32Array([8.0, 3.0, 8.0])  # record line ~ ground
	var open_ground := func(x: float, _z: float) -> float:
		return [8.0, 3.0, 8.0][int(round(x / 48.0))]
	var open: PackedFloat32Array = WB._drape(open_pos, open_surf, depth, open_ground)
	_check(open[1] <= 3.0 + depth + eps,
		"drape hugs an open dip (mid surf %.2f <= ground+depth %.2f)" % [
			open[1], 3.0 + depth])

	# (2) Contained pool: the SAME dip, but inside a gorge whose banks rise
	# well above the water. Here the pool SHOULD fill flat behind the lip —
	# the clamp allows it because the ground contains it.
	var deep_ground := func(_x: float, _z: float) -> float: return 20.0
	var pooled: PackedFloat32Array = WB._drape(open_pos, open_surf, depth, deep_ground)
	_check(is_equal_approx(pooled[1], 8.0),
		"drape pools a contained dip flat behind the lip (mid surf %.2f ~ 8)" % pooled[1])
	for v in pooled:
		_check(v <= 20.0 + depth + eps, "a contained pool never tops its banks")

	# (3) Real imported bake: for a live hyd_ river, resample its polyline the
	# way _ribbon does and drape it against the REAL terrain. The new drape
	# must hug everywhere; the OLD max-scan must have floated somewhere — the
	# regression, proven on the shipped data (SKIP with no import on disk).
	var river: Dictionary = {}
	for r in Terrain.rivers:
		if String(r.id).begins_with("hyd_") and (r.nodes as Array).size() >= 2:
			river = r
			break
	if river.is_empty():
		print("  river drape: SKIP real-bake hug (no hyd_* river imported)")
		return
	var step := 1.8  # water_bodies.RIBBON_STEP
	var rd: float = river.depth
	var row_pos: Array = []
	var row_surf := PackedFloat32Array()
	var nodes: Array = river.nodes
	var carry := 0.0
	for i in nodes.size() - 1:
		var a: Dictionary = nodes[i]
		var b: Dictionary = nodes[i + 1]
		var pa: Vector2 = a.pos
		var ab: Vector2 = b.pos - pa
		var seg := ab.length()
		if seg < 1e-4:
			continue
		var s := carry
		while s < seg:
			var f := s / seg
			row_pos.append(pa + ab * f)
			row_surf.append(lerpf(a.surface, b.surface, f))
			s += step
		carry = s - seg
	var last: Dictionary = nodes[nodes.size() - 1]
	row_pos.append(last.pos)
	row_surf.append(float(last.surface))
	var dr5: PackedFloat32Array = WB._drape(row_pos, row_surf, rd, Terrain.height)
	# Old behaviour, reconstructed: drape then an UNCLAMPED downstream max-scan.
	var old := PackedFloat32Array(); old.resize(row_pos.size())
	for i in row_pos.size():
		var p: Vector2 = row_pos[i]
		old[i] = minf(row_surf[i], Terrain.height(p.x, p.y) + rd)
	for i in range(old.size() - 2, -1, -1):
		old[i] = maxf(old[i], old[i + 1])
	var new_float := -1e9
	var old_float := -1e9
	for i in row_pos.size():
		var p: Vector2 = row_pos[i]
		var ceil_s := Terrain.height(p.x, p.y) + rd
		new_float = maxf(new_float, dr5[i] - ceil_s)
		old_float = maxf(old_float, old[i] - ceil_s)
	_check(new_float <= eps,
		"%s: draped ribbon hugs the real bake (max float %.3fm)" % [river.id, new_float])
	print("  river drape: %s old max-scan floated %.2fm, clamped drape floats %.4fm" % [
		river.id, old_float, new_float])


## Mission Y3 sweep: the sea/lake bathymetry (_bathy) is a follow cache keyed
## on a focus-snapped anchor — _bathy_follow only rebakes when that anchor
## MOVES, so a lake's fixed-position tier (a documented "one-shot bake") and
## the sea's near/mid tiers (idle while the focus sits still) never notice
## the ground changing under them: a bless (reload_world's whole-frame
## edited) or a sculpted stroke left the shoaling/surf line reading the OLD
## seabed forever. _on_terrain_edited_bathy is the fix — it staleness-checks
## every registered tier's bake footprint against the edited rect and, on a
## hit, resets the anchor to INF so the very next _bathy_follow call (every
## _process, regardless of whether focus moved) treats the goal as new and
## rebakes off the live ground. Pure dict logic — no tree, no kernel, no
## renderer needed, so this runs everywhere (including headless).
func _test_bathy_edit_invalidate() -> void:
	var wb: Node3D = load("res://game/world/water_bodies.gd").new()
	# A "lake" tier sitting still at (500, 500), radius 80 — the one-shot
	# case: nothing ever moves its goal, so only an edit can unstick it.
	wb._bathy = {
		"lake:hyd_test": {"mi": null, "radius": 80.0, "step": 1.0, "n": 4,
			"level": 10.0, "arrays": [], "anchor": Vector2(500.0, 500.0),
			"goal": Vector2(500.0, 500.0), "task": -1, "out": PackedFloat32Array()},
		"near": {"mi": null, "radius": 300.0, "step": 3.0, "n": 4,
			"level": 12.0, "arrays": [], "anchor": Vector2(3000.0, 3000.0),
			"goal": Vector2(3000.0, 3000.0), "task": -1, "out": PackedFloat32Array()},
	}
	# An edit far from both tiers' footprints: neither anchor is touched.
	wb._on_terrain_edited_bathy(Rect2(-50.0, -50.0, 10.0, 10.0))
	_check(Vector2(wb._bathy["lake:hyd_test"].anchor) == Vector2(500.0, 500.0),
		"bathy: an edit outside a tier's footprint leaves its anchor alone")
	_check(Vector2(wb._bathy["near"].anchor) == Vector2(3000.0, 3000.0),
		"bathy: an edit outside the OTHER tier's footprint leaves it alone too")
	# An edit clipping the lake tier's footprint (500,500 +/- 80): the fixed
	# lake anchor — which nothing else would ever unstick — resets to INF.
	wb._on_terrain_edited_bathy(Rect2(540.0, 540.0, 20.0, 20.0))
	_check(not Vector2(wb._bathy["lake:hyd_test"].anchor).is_finite(),
		"bathy: an edit touching the lake's footprint invalidates its anchor")
	_check(Vector2(wb._bathy["near"].anchor) == Vector2(3000.0, 3000.0),
		"bathy: the untouched sea tier is still left alone")
	# The mission's actual trigger: reload_world's whole-frame edited rect
	# covers everything (including this tier's anchor, well inside the
	# 16384m world frame) — every tier resets.
	wb._on_terrain_edited_bathy(Rect2(-8192.0, -8192.0, 16384.0, 16384.0))
	_check(not Vector2(wb._bathy["near"].anchor).is_finite(),
		"bathy: a whole-frame bless invalidates the sea tier's anchor too")
	# An unbaked tier (anchor still INF) is left alone — its first bake
	# reads whatever is live anyway, nothing stale to invalidate.
	wb._bathy["mid"] = {"mi": null, "radius": 1600.0, "step": 12.0, "n": 4,
		"level": 12.0, "arrays": [], "anchor": Vector2.INF,
		"goal": Vector2.INF, "task": -1, "out": PackedFloat32Array()}
	wb._on_terrain_edited_bathy(Rect2(-8192.0, -8192.0, 16384.0, 16384.0))
	_check(not Vector2(wb._bathy["mid"].anchor).is_finite(),
		"bathy: an unbaked tier's INF anchor is a no-op, not a crash")


## Zero-flow regression: a river imported WHILE the game runs (reload_world /
## Strata import) must be seeded on the region tier, or it idles at "0 m3/h,
## norm 0.00". _reseed_region_water runs the same baseflow seed _ready does —
## for newcomers ONLY: a river already breathing keeps its live storage across
## an unrelated reload.
func _test_region_reseed() -> void:
	var river: Dictionary = {}
	for r in Terrain.rivers:
		if String(r.id).begins_with("hyd_"):
			river = r
			break
	if river.is_empty():
		print("  region reseed: SKIP (no hyd_* river imported)")
		return
	var id: String = river.id
	var had_storage: bool = Hydrology.region_storage.has(id)
	var saved_storage: float = float(Hydrology.region_storage.get(id, 0.0))
	var saved_qref: float = float(Hydrology.region_qref.get(id, 0.0))

	# Import-while-running: the reservoir is missing → discharge reads zero.
	Hydrology.region_storage.erase(id)
	Hydrology.region_qref.erase(id)
	_check(Hydrology.discharge(id) == 0.0, "unseeded imported river reads zero discharge")
	# The honest signal re-seeds it at baseflow: idle flow_norm lands on the
	# tier's design line (~0.35).
	Terrain.water_reloaded.emit()
	_check(Hydrology.region_storage.has(id), "reload re-seeds the imported river")
	_check(Hydrology.discharge(id) > 0.0, "re-seeded river flows (%.0f m3/h)" % Hydrology.discharge(id))
	_check(absf(Hydrology.flow_norm(id) - 0.35) < 0.01,
		"re-seeded river idles at baseflow (norm %.3f ~ 0.35)" % Hydrology.flow_norm(id))

	# Reload again with the river now "playing" at a distinct storage: an
	# unrelated reload must NOT reset it.
	var live_val: float = float(Hydrology.region_storage[id]) * 3.7 + 123.0
	Hydrology.region_storage[id] = live_val
	Terrain.water_reloaded.emit()
	_check(is_equal_approx(float(Hydrology.region_storage[id]), live_val),
		"a live river's storage survives an unrelated reload")

	# Restore whatever the boot seed left, so later tests see an untouched tier.
	if had_storage:
		Hydrology.region_storage[id] = saved_storage
		Hydrology.region_qref[id] = saved_qref


## Mission V1 — THE SEA MUST COME BACK AFTER A BLESS. A living-preview pane
## boots CONTENT-EMPTY (Terrain.sea_level = -1e12), so water_bodies._ready
## builds NO sea discs. Through a shaping session the PreviewTerrain drape
## steps every water tier aside on _enter and restores it on leave (the
## double-cycle here — the classic double-hide would capture the ALREADY-hidden
## node on the second wear and make hidden the new normal). The BLESS then
## re-reads the world off disk (Terrain._reload_water sets sea_level and emits
## water_reloaded), and the sea must appear for the FIRST time here. On baseline
## water_reloaded rebuilt only the rivers, so a blessed world showed its rivers
## but NEVER its sea — the "rivers but no sea" report. This pins the whole
## sequence and asserts every water tier is visible at the end. Pure nodes +
## the real drape/reload machinery — no streamer, no kernel, runs headless.
func _test_sea_reload_visibility() -> void:
	var saved_sea: float = Terrain.sea_level
	# A content-empty living-preview boot: no sea on disk yet.
	Terrain.sea_level = -1e12
	var wb: Node3D = load("res://game/world/water_bodies.gd").new()
	add_child(wb)  # _ready: connects to preview_sea, builds no sea (dry)
	var ws: Node3D = load("res://game/world/water_sheet.gd").new()
	add_child(ws)  # the near wave-field tier — still steps aside by group
	_check(wb._sea_far == null,
		"sea/reload: a content-empty boot builds NO sea (the living-preview pane)")

	# THE SHAPING POSTURE (M6c, the game-look water half): the drape wears and
	# the SEA holds over the preview relief at the export's own level — real
	# water, not a chart plane — even on a content-empty pane that had no sea.
	# The tier-2 water sheet (no preview base to ride) still steps aside by
	# group. Twice (the slider re-wear loop). _enter hides the group; the
	# preview_sea broadcast (what wear() fires) drives the sea's posture.
	var drape := PreviewTerrain.new()
	add_child(drape)
	drape._sea_level = 8.0
	for cycle in 2:
		drape._enter()
		StrataLink.preview_sea.emit(true, drape._sea_level)
		_check(wb._sea_far != null and wb._sea_far.is_visible_in_tree(),
			"sea/reload: cycle %d — the shaping sea holds over the drape" % cycle)
		_check(wb._sea_near != null and is_equal_approx(wb._sea_near.position.y, 8.0),
			"sea/reload: cycle %d — the shaping sea seats at the export's level" % cycle)
		_check(not wb._bathy.has("near"),
			"sea/reload: cycle %d — the shaping sea carries NO bathymetry (deep W1)" % cycle)
		_check(not ws.visible,
			"sea/reload: cycle %d — the tier-2 water sheet still steps aside" % cycle)
		drape.leave()  # restores the group AND broadcasts preview_sea(false)
		_check(ws.visible,
			"sea/reload: cycle %d — leaving restores the stepped-aside sheet" % cycle)
		_check(wb._sea_far == null,
			"sea/reload: cycle %d — leaving drops the shaping sea (dry live world)" % cycle)

	# THE BLESS (no drape worn): the importer wrote a real sea level; reload
	# re-reads it. Mirror Terrain._reload_water (set the level, emit
	# water_reloaded) without touching the operator's world on disk.
	Terrain.sea_level = 12.0
	Terrain.water_reloaded.emit()
	_check(wb._sea_far != null,
		"sea/reload: the bless rebuilds the sea a content-empty boot never made")
	if wb._sea_far != null:
		_check(wb._sea_far.is_visible_in_tree() and wb._sea_near.is_visible_in_tree()
				and wb._sea_mid.is_visible_in_tree(),
			"sea/reload: every sea tier is visible after the bless")
		_check(wb._bathy.has("near") and wb._bathy.has("mid"),
			"sea/reload: the LIVE sea carries its bathymetry again after the bless")
	_check(ws.is_visible_in_tree(),
		"sea/reload: the water_sheet tier is visible after the bless")

	# The realistic ordering: a bless while the drape is STILL worn (reload_world
	# fires water_reloaded before it lifts the drape) keeps the SHAPING sea at
	# the export's level; leaving the drape reveals the blessed sea at its live
	# level — one water truth, both postures.
	drape._enter()
	StrataLink.preview_sea.emit(true, drape._sea_level)
	Terrain.water_reloaded.emit()
	_check(wb._sea_near != null and is_equal_approx(wb._sea_near.position.y, 8.0),
		"sea/reload: a bless under the worn drape keeps the shaping sea (8m, not 12m)")
	drape.leave()
	_check(wb._sea_near != null and is_equal_approx(wb._sea_near.position.y, 12.0)
			and wb.is_visible_in_tree(),
		"sea/reload: leaving the drape reveals the blessed sea at its live level (12m)")

	# Teardown: drop the throwaway nodes, restore the world's sea level so later
	# tests see an untouched Terrain.
	drape.queue_free()
	ws.queue_free()
	wb.queue_free()
	Terrain.sea_level = saved_sea


## The lake-shape E2E (P2+): a Strata export whose lake carries its TRUE
## shoreline outline — driven through the REAL import_world.gd — must land as
## a hyd_ record that keeps the outline, and WaterBodies must build a
## vertex-dense surface that HUGS that outline instead of the floating
## equal-area disc. The committed fixture (tests/fixtures/lake_e2e_world) is a
## kidney/L-shaped depression baked by Strata's HydrologySolver (see
## LakeOutlineE2ETests.swift), so the notch is dry ground the old disc floated
## over. Proves items (2)–(4) of the rung end to end.
func _test_lake_outline() -> void:
	var world_abs := ProjectSettings.globalize_path("res://tests/fixtures/lake_e2e_world")
	if not FileAccess.file_exists(world_abs.path_join("hydrology.json")):
		print("  lake outline: SKIP (no E2E fixture)")
		return
	# (2) Run the real importer; it must carry the outline into the record.
	var out_abs := ProjectSettings.globalize_path("user://lake_e2e_out")
	DirAccess.make_dir_recursive_absolute(out_abs)
	var project := ProjectSettings.globalize_path("res://")
	var r := _run_importer(world_abs, out_abs, project)
	_check(int(r.code) == 0, "E2E import exits 0 (%s)" % String(r.out).substr(0, 200))
	var rec_path := out_abs.path_join("hyd_l1.json")
	_check(FileAccess.file_exists(rec_path), "importer wrote the lake record")
	var rec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(rec_path))
	var outline_raw: Array = rec.get("outline", [])
	_check(outline_raw.size() >= 6,
		"importer carried the true shoreline (%d verts, not a disc)" % outline_raw.size())
	# (3) WaterBodies builds a dense surface clipped to the real outline.
	var WaterBodies := load("res://game/world/water_bodies.gd")
	var wb: Node = WaterBodies.new()
	var center := Vector2(float(rec["center"]["x"]), float(rec["center"]["z"]))
	var world_poly := PackedVector2Array()
	for p: Dictionary in outline_raw:
		world_poly.append(Vector2(float(p["x"]), float(p["z"])))
	var local: PackedVector2Array = wb._local_outline(world_poly, center)
	var lake_step := maxf(0.9, float(rec["radius"]) / 128.0)
	var poly_mesh: ArrayMesh = wb._polygon_disc(local, lake_step)
	var disc_mesh: ArrayMesh = wb._disc(float(rec["radius"]), lake_step)
	var pv: PackedVector3Array = poly_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(pv.size() > 200, "outline surface is vertex-dense (%d verts)" % pv.size())
	# (4) It HUGS the shore: nearly every built triangle sits inside the true
	# polygon, while the equal-area disc spills well past it — the floating rim.
	var pin := _tri_inside_fraction(wb, poly_mesh, local)
	var din := _tri_inside_fraction(wb, disc_mesh, local)
	_check(pin > 0.9, "outline mesh stays inside the real shore (%.2f in)" % pin)
	_check(din < pin - 0.1,
		"the disc fallback floats past the shore (disc %.2f < outline %.2f)" % [din, pin])
	wb.free()
	# (5) The QUERY tracks the same shore the mesh does. Load the imported record
	# into a bare Terrain and ask water_surface_base at the two notch witnesses:
	# a point inside the true shore but PAST where the disc reaches must answer
	# water at the fill elevation; a point inside the disc's OVERHANG but on dry
	# land (outside the polygon) must answer NO water. Witnesses are found by
	# scanning the shoreline bbox, so the test survives any importer re-framing.
	var t: Node = load("res://game/world/terrain.gd").new()
	var lake: Dictionary = t._lake_from_record(rec, "l1", 0)
	t.water_bodies.append(lake)
	t.lake_levels.resize(1)
	var rad := float(rec["radius"])
	var water_pt := Vector2.INF  # inside polygon, outside disc
	var dry_pt := Vector2.INF    # inside disc, outside polygon (the overhang)
	var lo2 := world_poly[0]
	var hi2 := world_poly[0]
	for p in world_poly:
		lo2 = Vector2(minf(lo2.x, p.x), minf(lo2.y, p.y))
		hi2 = Vector2(maxf(hi2.x, p.x), maxf(hi2.y, p.y))
	var span := hi2 - lo2
	for iz in 33:
		for ix in 33:
			var wp := lo2 + Vector2(span.x * ix / 32.0, span.y * iz / 32.0)
			var inpoly: bool = t._poly_contains(world_poly, wp.x, wp.y)
			var indisc: bool = (wp - center).length() < rad
			if inpoly and not indisc and not water_pt.is_finite():
				water_pt = wp
			if indisc and not inpoly and not dry_pt.is_finite():
				dry_pt = wp
	if water_pt.is_finite() and dry_pt.is_finite():
		_check(t.water_surface_base(water_pt.x, water_pt.y) == float(rec["surface"]),
			"query: inside the true shore but past the disc answers water at fill (%.0f, %.0f)"
				% [water_pt.x, water_pt.y])
		_check(t.water_surface_base(dry_pt.x, dry_pt.y) < -1e11,
			"query: inside the disc overhang but on dry land answers NO water (%.0f, %.0f)"
				% [dry_pt.x, dry_pt.y])
	else:
		print("  lake outline query: SKIP (no notch witness — disc ~ polygon)")
	t.free()
	# Scrub the scratch import so the run leaves nothing behind.
	var d := DirAccess.open(out_abs)
	if d != null:
		for f in d.get_files():
			d.remove(f)


## Fix 4b: an OUTLINE lake sizes its surface grid off the shoreline bbox
## (_polygon_disc's nx*nz), not off 2*radius, so _bathy_register's disc-formula
## count check ALWAYS mismatched for outline lakes and dropped their bathymetry
## (no CUSTOM0 depth channel → no shoaling/wave-break) with a push_warning nobody
## saw. _bathy_register now takes the actual mesh grid, so the outline path
## registers correctly; a genuine mismatch is now a loud push_error. Synthetic
## outline lake (no E2E fixture needed) with radius >= LAKE_SWELL_MIN_R.
func _test_lake_outline_bathy() -> void:
	var wb: Node3D = load("res://game/world/water_bodies.gd").new()
	# An irregular (non-circular) shoreline; bbox ~110×100m, radius ~55 >= 40.
	var poly := PackedVector2Array([
		Vector2(-55, -18), Vector2(-8, -50), Vector2(42, -34),
		Vector2(55, 12), Vector2(18, 48), Vector2(-32, 40), Vector2(-50, 6)])
	var step := 0.9
	var mesh: ArrayMesh = wb._polygon_disc(poly, step)
	var mi := MeshInstance3D.new()
	mi.name = "lake_bathy_probe"
	mi.mesh = mesh
	var vcount: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var grid: Dictionary = wb._poly_grid(poly, step)
	# The polygon-disc vertex count must equal the grid dims the bake will use —
	# the invariant the old disc formula (n*n, n from 2*radius) always violated.
	_check(vcount == int(grid.nx) * int(grid.nz),
		"outline mesh vertex count == its bbox grid (%d == %d×%d)" % [vcount, grid.nx, grid.nz])
	# The disc formula the OLD check used would NOT match — proving why outline
	# lakes were silently skipped before this fix.
	var disc_n := int(ceil(55.0 * 2.0 / step)) + 2
	_check(vcount != disc_n * disc_n,
		"the old disc-formula count (%d²) genuinely mismatches the outline mesh (%d)"
			% [disc_n, vcount])
	# Register with the real grid: it lands, no false push_error, CUSTOM0 present.
	wb._bathy_register("lake:bathy_probe", mi, 55.0, step, 0.0, grid)
	_check(wb._bathy.has("lake:bathy_probe"),
		"outline lake registers bathymetry (no false grid mismatch)")
	if wb._bathy.has("lake:bathy_probe"):
		var st: Dictionary = wb._bathy["lake:bathy_probe"]
		_check(int(st.nx) == int(grid.nx) and int(st.nz) == int(grid.nz),
			"registered grid records the outline mesh dims (%d×%d)" % [st.nx, st.nz])
		var arrs := mi.mesh.surface_get_arrays(0)
		var custom: PackedFloat32Array = arrs[Mesh.ARRAY_CUSTOM0]
		_check(custom.size() == vcount * 3,
			"outline lake mesh now carries the CUSTOM0 depth channel (%d floats)" % custom.size())
	mi.free()
	wb.free()


## W5.3 (★ 2 RULED: STYLIZED MIRROR): the gouache-quantized sky+sun mirror
## rides LAKE materials only. Lake materials built by _build_lakes carry
## lake_mirror=1; the sea-tier material factory and the plain river/base
## material never set it (shader default 0) — the sea keeps its Gerstner
## life, rivers stay matte. The shader itself must hold the gouache law in
## code: both the mirror mix and the reflected sky gradient are floor()-
## quantized, and the calm gate exists so a stirred lake goes matte.
func _test_lake_mirror() -> void:
	var wb: Node3D = load("res://game/world/water_bodies.gd").new()
	# Isolate: swap in one synthetic small lake (radius < LAKE_SWELL_MIN_R so
	# no bathy/swell machinery runs), restore the real records after.
	var saved_bodies: Array = Terrain.water_bodies
	var saved_levels: PackedFloat32Array = Terrain.lake_levels
	Terrain.water_bodies = [{"id": "mirror_probe", "center": Vector2(0, 0),
		"radius": 30.0, "surface": 10.0, "idx": 0}]
	Terrain.lake_levels = PackedFloat32Array([0.0])
	wb._build_lakes()
	var lake_mi: MeshInstance3D = wb._lake_meshes.get("mirror_probe")
	_check(lake_mi != null, "the synthetic lake builds")
	if lake_mi != null:
		var lm: ShaderMaterial = lake_mi.mesh.surface_get_material(0)
		_check(float(lm.get_shader_parameter("lake_mirror")) == 1.0,
			"lake material wears the quantized mirror (lake_mirror=1)")
	# The sea-tier factory and the base river material never set the term —
	# an unset uniform reads null here, and the shader default is 0.
	var sea_mat: ShaderMaterial = wb._sea_material(3.0, 1600.0)
	_check(sea_mat.get_shader_parameter("lake_mirror") == null,
		"sea material does NOT wear the mirror (Gerstner life kept)")
	var river_mat: ShaderMaterial = wb._material(Vector2.ZERO)
	_check(river_mat.get_shader_parameter("lake_mirror") == null,
		"base/river material does NOT wear the mirror")
	# The gouache law, held in code: the shader source quantizes the mirror
	# mix and the reflected sky, and gates on calm — posterized strokes,
	# never a chrome glaze (the coordinator-relayed ★ 2 ruling's terms).
	var src := FileAccess.get_file_as_string("res://game/shaders/water.gdshader")
	_check(src.contains("uniform float lake_mirror"),
		"shader carries the lake_mirror uniform")
	_check(src.contains("m = floor(m * MIRROR_STEPS"),
		"the mirror mix is floor-quantized (gouache bands)")
	_check(src.contains("up = floor(up * SKY_BANDS"),
		"the reflected sky gradient is posterized")
	_check(src.contains("float calm = 1.0 - clamp(stir"),
		"the calm gate exists — a stirred lake goes matte")
	# Restore the real world records; free the probe scaffolding.
	Terrain.water_bodies = saved_bodies
	Terrain.lake_levels = saved_levels
	wb.free()


# Fraction of a mesh's triangles whose centroid lies inside `poly` (XZ) —
# 1.0 means the surface never spills past the shoreline.
func _tri_inside_fraction(wb: Node, mesh: ArrayMesh, poly: PackedVector2Array) -> float:
	var arrs := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		return 0.0
	var inside := 0
	var tris := 0
	var i := 0
	while i + 2 < idx.size():
		var a: Vector3 = v[idx[i]]
		var b: Vector3 = v[idx[i + 1]]
		var c: Vector3 = v[idx[i + 2]]
		var cen := Vector2((a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0)
		if wb._point_in_poly(cen, poly):
			inside += 1
		tris += 1
		i += 3
	return float(inside) / float(maxi(tris, 1))


func _test_water_field() -> void:
	# Tier 2 is presentation: headless (no RenderingDevice) it stays off,
	# and the whole game must run without it — the canonical water is
	# Hydrology. The scene-test runner is headless, so this is the
	# disabled path, and it must never crash a caller.
	_check(not WaterField.enabled, "tier-2 field disabled without a GPU (headless)")
	_check(WaterField.depth_at(Vector3(70, 0, -310)) == 0.0,
		"field depth reads 0 when disabled")
	# The current fallback is the real gameplay path when the field is off:
	# dry ground reads zero current — and nothing crashes. The fixed probe
	# point died with P2 (an imported lake can cover any spot), so FIND a
	# dry inland point; skip honestly if the import flooded them all.
	var dry := Vector2.INF
	for gz in range(-8, 9):
		for gx in range(-8, 9):
			var p := Vector2(gx * 400.0, gz * 400.0)
			if Terrain.home_guard(p.x, p.y) == 0.0 \
					and Terrain.water_surface(p.x, p.y) < -1e6:
				dry = p
				break
		if dry.is_finite():
			break
	if dry.is_finite():
		_check(WaterField.current_at(Vector3(dry.x, 0, dry.y)) == Vector2.ZERO,
			"no current on dry ground (%.0f, %.0f)" % [dry.x, dry.y])
	else:
		print("  water field: SKIP dry-ground current (no dry guarded point on this import)")
	_check(not WaterWaves.enabled, "tier-2.5 wave field disabled without a GPU")
	# The wave kernel spec (CPU reference = what the GLSL must do):
	# a dent rings OUTWARD, total energy DECAYS, nothing blows up.
	var n := 48
	var prev := PackedFloat32Array()
	prev.resize(n * n)
	var curr := prev.duplicate()
	curr[24 * n + 24] = -0.05  # the splat: a pressed dent
	prev[24 * n + 24] = -0.05
	var e0 := WaveReference.energy(curr)
	var reached_at := -1
	for step_i in 40:
		var next := WaveReference.step(prev, curr, n)
		prev = curr
		curr = next
		if reached_at < 0 and absf(curr[24 * n + 34]) > 0.0005:
			reached_at = step_i  # the ring arrived 10 cells out
	_check(reached_at > 5, "waves propagate at finite speed (arrived step %d)" % reached_at)
	var e1 := WaveReference.energy(curr)
	_check(e1 < e0 and e1 > 0.0, "wave energy decays but persists (%.5f -> %.5f)" % [e0, e1])
	var bounded := true
	for v in curr:
		if not is_finite(v) or absf(v) > 0.1:
			bounded = false
	_check(bounded, "wave field stays bounded (CFL-stable at K=%.2f)" % WaveReference.K)
	_check(is_equal_approx(WaveReference.K, WaveGpu.K)
			and is_equal_approx(WaveReference.DAMP, WaveGpu.DAMP),
		"CPU reference constants match the GPU driver")
	# Every compute kernel must compile to SPIR-V — headless CI never
	# creates a RenderingDevice, so import-time compilation is the only
	# GLSL check any CI can run. Catches syntax errors before a human
	# hits them in a windowed session.
	for kernel in ["sand_apply", "sand_relax", "sand_copy",
			"water_flux", "water_depth", "water_probe",
			"wave_splat", "wave_step", "wave_copy"]:
		var src: RDShaderFile = load("res://game/shaders/compute/%s.glsl" % kernel)
		var ok := src != null and src.get_spirv() != null \
			and src.get_spirv().compile_error_compute == ""
		_check(ok, "compute kernel compiles: " + kernel)


## PLAN_SUBSTANCES S1: everything that moves rings the water. The GPU
## field is off headless (the WaterWaves law), so these pin the SOURCE
## math — the pure ring functions every body speaks through — and drive
## a scripted crossing into the CPU reference kernel: the sand
## discipline, applied to who touches the water.
func _test_wave_sources() -> void:
	# A hound wading at a trot rings; standing still settles; dry paws
	# never ring; fleeing rings harder; bigger bodies ring bigger.
	var trot := WaterWaves.wade_ring(0.3, 2.2, 0.7)
	_check(trot != Vector2.ZERO, "a wading creature rings the water")
	_check(WaterWaves.wade_ring(0.3, 0.0, 0.7) == Vector2.ZERO,
		"standing still settles — no ring")
	_check(WaterWaves.wade_ring(-0.1, 2.2, 0.7) == Vector2.ZERO,
		"dry ground never rings")
	var flee := WaterWaves.wade_ring(0.3, 3.6, 0.7)
	_check(flee.y > trot.y, "faster wading rings harder")
	var big := WaterWaves.wade_ring(0.3, 2.2, 1.0)
	_check(big.x > trot.x and big.y > trot.y, "bigger bodies ring bigger")
	var splash := WaterWaves.splash_ring(3.6, 0.7)
	_check(splash.x > flee.x and splash.y > flee.y,
		"a deep entry throws one big ring")
	# The scripted crossing: four strides of hound rings splatted into
	# the reference field must put real energy in, and the rings must
	# outlive the crossing and spread past the last paw-fall.
	var n := 48
	var texel := WaveGpu.REGION / WaveGpu.GRID
	var prev := PackedFloat32Array()
	prev.resize(n * n)
	var curr := prev.duplicate()
	for stride in 4:
		_splat_ref(curr, n, 12.0 + stride * 6.0, 24.0,
			trot.x / texel, -trot.y)
	var e0 := WaveReference.energy(curr)
	_check(e0 > 0.0, "a creature crossing puts energy in the field")
	for i in 30:
		var next := WaveReference.step(prev, curr, n)
		prev = curr
		curr = next
	_check(WaveReference.energy(curr) > 0.0,
		"the rings outlive the crossing")
	_check(absf(curr[24 * n + 41]) > 1e-5,
		"the rings spread past the last paw-fall")
	# Rain rides the one weather truth: a storm pocks the window, a calm
	# sky rings nothing (wind chop is its own term).
	_check(WaterWaves.rain_rate(1.0) > 0.0, "storm rain pocks the window")
	_check(WaterWaves.rain_rate(0.0) == 0.0, "calm produces no rain rings")
	_check(WaterWaves.chop_rate(1.0) > WaterWaves.chop_rate(0.12),
		"wind scales the chop")
	# The ★ knobs, shipped as knobs: the doubled window and the ring
	# posterize live where a probe A/B can retune them.
	_check(WaveGpu.GRID == 1024 and is_equal_approx(WaveGpu.REGION, 128.0),
		"window ships doubled: 128m at 1024² (the ★ knob)")
	var wsh: Shader = load("res://game/shaders/water.gdshader")
	_check("ring_posterize" in wsh.code,
		"ring posterize knob exists in the water shader")
	_check(not WaterWaves.summary().is_empty(), "WAVES Toolkit line speaks")


## PLAN_SUBSTANCES S2: the water remembers. The GPU field is off headless,
## so these pin the foam SPEC — deposit law, TIME-based decay (the DAMP
## lesson: a per-step constant decays at whatever the frame rate happens
## to be), drift advection — on the CPU reference, plus the flagged-
## eyesore fixes' presence: distance fade + foam-age posterize in the
## shader, the mouth feather in the ribbon builder.
func _test_foam_memory() -> void:
	# The deposit law (wave_splat's foam term): chop under the floor
	# leaves clean water; strides, wakes, splashes each leave their weight.
	_check(WaveReference.foam_deposit(0.002) == 0.0,
		"wind chop deposits no foam (under the floor)")
	var wake := WaveReference.foam_deposit(0.012)
	var stride := WaveReference.foam_deposit(WaterWaves.WADE_STRENGTH)
	var splash := WaveReference.foam_deposit(0.09)
	_check(wake > 0.0 and stride > wake and splash > stride,
		"splash > stride > wake > chop — foam scales with the speaker")
	# TIME-based decay: 6 seconds is 6 seconds whether it ran as 60
	# small frames or 6 big ones — the same water, any frame rate.
	var n := 16
	var still := PackedFloat32Array()
	still.resize(n * n)
	var tau := 6.0
	var f_small := still.duplicate()
	var f_big := still.duplicate()
	f_small[8 * n + 8] = 0.6
	f_big[8 * n + 8] = 0.6
	for i in 60:
		f_small = WaveReference.foam_step(f_small, still, n,
			exp(-0.1 / tau), Vector2.ZERO, 0.1)
	for i in 6:
		f_big = WaveReference.foam_step(f_big, still, n,
			exp(-1.0 / tau), Vector2.ZERO, 1.0)
	_check(absf(f_small[8 * n + 8] - 0.6 / exp(1.0)) < 0.01,
		"foam falls to 1/e after τ seconds (%.3f)" % f_small[8 * n + 8])
	_check(absf(f_small[8 * n + 8] - f_big[8 * n + 8]) < 1e-4,
		"decay is a function of TIME, not steps (%.4f vs %.4f)" % [
			f_small[8 * n + 8], f_big[8 * n + 8]])
	# Drift: a curd pulled 0.5 texels/step for 8 steps rides 4 texels
	# downstream — breaker foam's ride ashore, in miniature.
	var f_drift := still.duplicate()
	f_drift[8 * n + 4] = 1.0
	for i in 8:
		f_drift = WaveReference.foam_step(f_drift, still, n,
			1.0, Vector2(0.5, 0.0), 0.0)
	var cx := 0.0
	var total := 0.0
	for x in n:
		cx += f_drift[8 * n + x] * x
		total += f_drift[8 * n + x]
	_check(total > 0.0 and absf(cx / total - 8.0) < 0.35,
		"foam rides the drift (centroid %.2f, want 8)" % (cx / total))
	# Travelling crests re-deposit: a field holding a crest above CREST_H
	# feeds foam; still water feeds none.
	var crest := still.duplicate()
	crest[8 * n + 8] = 0.12
	var fed := WaveReference.foam_step(still.duplicate(), crest, n,
		1.0, Vector2.ZERO, 0.5)
	_check(fed[8 * n + 8] > 0.0 and fed[8 * n + 9] == 0.0,
		"a travelling crest re-deposits foam where it rides")
	# GLSL lockstep: the kernel sources must carry the reference's
	# constants (the compile check catches syntax; this catches drift).
	var splat_src := FileAccess.get_file_as_string(
		"res://game/shaders/compute/wave_splat.glsl")
	var step_src := FileAccess.get_file_as_string(
		"res://game/shaders/compute/wave_step.glsl")
	_check("FOAM_FLOOR = 0.004" in splat_src and "FOAM_GAIN = 25.0" in splat_src,
		"wave_splat.glsl carries the reference deposit constants")
	_check("CREST_H = 0.05" in step_src and "CREST_GAIN = 6.0" in step_src,
		"wave_step.glsl carries the reference crest constants")
	# The knob is a knob, and time-based: the autoload hands the kernel
	# exp(-dt/τ), never a bare per-frame constant.
	_check(WaterWaves.foam_decay > 0.0, "foam_decay ★ knob exists (%.1fs)" % [
		WaterWaves.foam_decay])
	_check("foam" in WaterWaves.summary() or not WaterWaves.enabled,
		"WAVES Toolkit line speaks foam")
	# The flagged eyesores, fixed where a headless run can see them:
	# distance fade + foam-age posterize live in the water shader...
	var wsh: Shader = load("res://game/shaders/water.gdshader")
	_check("foam_fade_near" in wsh.code and "foam_posterize" in wsh.code,
		"water shader carries distance fade + foam-age posterize")
	_check("ALPHA = alpha_v" in wsh.code,
		"water shader honors the mouth feather alpha")
	# ...and the mouth feather ramps the ribbon into its lake: alpha 1→0,
	# flow to zero, surface down to the lake's live level.
	var wb: Node3D = load("res://game/world/water_bodies.gd").new()
	var nodes: Array = [
		{"pos": Vector2(0, 0), "half": 3.0, "surface": 0.0},
		{"pos": Vector2(36, 0), "half": 3.0, "surface": -0.5},
	]
	var mesh: ArrayMesh = wb._ribbon(nodes, 0.0, 1.0, [],
		{"level": -3.0, "span": 12.0})
	var arrays: Array = mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var last := cols.size() - 1
	_check(cols[0].a > 0.99, "ribbon head keeps full alpha")
	_check(cols[last].a < 0.05, "ribbon mouth feathers to alpha 0")
	_check(uv2[last].length() < 0.05, "mouth flow fades to zero (advection agrees)")
	_check(absf(verts[last].y - (-3.0)) < 0.15,
		"mouth surface drops to the lake's level (%.2f, want -3)" % verts[last].y)
	var mid_alpha := cols[int(cols.size() / 2.0)].a
	_check(mid_alpha > cols[last].a and mid_alpha <= 1.0,
		"the feather is a ramp, not a cliff")
	wb.free()
	# A river that ends nowhere near a lake keeps a hard, honest end.
	var wb2: Node3D = load("res://game/world/water_bodies.gd").new()
	var plain: ArrayMesh = wb2._ribbon(nodes, 0.0, 1.0, [])
	wb2.free()
	var pcols: PackedColorArray = plain.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_check(pcols[pcols.size() - 1].a > 0.99, "a mouthless river never feathers")


## The wave_splat.glsl stamp as pure CPU math (cosine dent, hard rails)
## — keep in step with the kernel, like WaveReference.
func _splat_ref(field: PackedFloat32Array, n: int, cx: float, cy: float,
		radius_px: float, w: float) -> void:
	for y in n:
		for x in n:
			var d := Vector2(x - cx, y - cy).length() / maxf(radius_px, 1.0)
			if d < 1.0:
				field[y * n + x] = clampf(
					field[y * n + x] + w * (0.5 + 0.5 * cos(d * PI)),
					-0.2, 0.2)


func _test_climate() -> void:
	# Temperature falls with elevation (lapse). Find the lowest and highest of a
	# broad sample — robust to whatever Strata world is loaded, not the old valley.
	var lo_p := Vector2.ZERO
	var hi_p := Vector2.ZERO
	var lo_h := 1e12
	var hi_h := -1e12
	for gx in range(-4, 5):
		for gz in range(-4, 5):
			var p := Vector2(gx * 700.0, gz * 700.0)
			var ph := Terrain.height(p.x, p.y)
			if ph < lo_h:
				lo_h = ph
				lo_p = p
			if ph > hi_h:
				hi_h = ph
				hi_p = p
	_check(Climate.temperature(hi_p.x, hi_p.y) < Climate.temperature(lo_p.x, lo_p.y),
		"higher ground runs colder (lapse rate)")
	var span: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span.x - 2.0, 24.0)  # before dawn
	var predawn: float = Climate.temperature(0.0, -100.0)
	GameClock.hours = fposmod((span.x + span.y) * 0.5 + 3.0, 24.0)  # mid-afternoon
	var afternoon: float = Climate.temperature(0.0, -100.0)
	_check(predawn < afternoon, "pre-dawn is colder than mid-afternoon")
	var was_state: String = Weather.state
	var was_wet: float = Climate.wetness
	Weather.force_kind("storm")
	Climate.wetness = 0.2
	Climate._hourly(0)
	_check(Climate.wetness > 0.2, "storm hours soak the ground")
	Weather.force_kind("calm")
	var wet: float = Climate.wetness
	Climate._hourly(0)
	_check(Climate.wetness < wet, "calm hours dry the ground")
	_check(float(WorldState.get_value("climate.wetness")) == Climate.wetness,
		"wetness mirrored to WorldState")
	_check(Climate.snow_line_for(20.0) > Climate.snow_line_for(2.0),
		"warm air lifts the snowline")
	_check(Climate.snow_line_for(-3.0) < 0.0,
		"a freezing floor drops the snowline below the valley")
	var was_snow: float = Climate.snow
	Weather.force_kind("calm")
	Climate.snow = 0.5
	Climate.wetness = 0.1
	Climate._hourly(0)
	_check(Climate.snow < 0.5, "warm calm hours melt the snow")
	_check(Climate.wetness > 0.0, "meltwater soaks the ground")
	Climate.snow = was_snow
	Weather.force_kind(was_state)
	Climate.wetness = was_wet
	Weather._transition(0)


## Climate v2 phase 1: the rain shadow and the wetness field.
func _test_climate_v2() -> void:
	# Wet air crossing a big wall must leave its lee dry. The test FINDS
	# its wall on whatever world is loaded (the old version was pinned to
	# the retired Range's coordinates): the tallest point on a coarse
	# grid, wind blown in off the nearest sea. It steps aside when the
	# world has no wall worth the name — matching the physics, where only
	# a big sustained barrier wrings the air dry (ORO_CLEAR/ORO_DEEP).
	var peak := Vector2.ZERO
	var peak_h := -1e12
	for gx in range(-14, 15):
		for gz in range(-14, 15):
			var pp := Vector2(gx * 512.0, gz * 512.0)
			var ph := Terrain.height(pp.x, pp.y)
			if ph > peak_h:
				peak_h = ph
				peak = pp
	# Wind travel direction: in off the nearest cardinal sea, over the
	# peak, into the lee (axis-aligned keeps the probe points in separate
	# 2048m wetness cells).
	var d := Vector2.ZERO
	var sea_dist := 1e12
	for card: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2(0, 1), Vector2(0, -1)]:
		for step in range(1, 26):
			var sp := peak + card * (step * 400.0)
			if Terrain.height(sp.x, sp.y) < Terrain.sea_level:
				if step * 400.0 < sea_dist:
					sea_dist = step * 400.0
					d = -card  # air arrives FROM the sea side
				break
	# The peak sits at a probe distance the lee's upwind scan samples
	# exactly (ORO_UP includes 1300m).
	var lee_probe := peak + d * 1300.0
	var excess := peak_h - maxf(Terrain.height(lee_probe.x, lee_probe.y), 0.0)
	if d == Vector2.ZERO or excess < 400.0:
		print("  (skip rain shadow: no wall tall enough on this world — peak %.0fm, excess %.0fm)"
				% [peak_h, excess])
	else:
		var was_angle: float = Weather._wind_angle
		var was_wet: float = Climate.wetness
		var was_snow: float = Climate.snow
		Weather._wind_angle = d.angle()
		Weather.wind_dir = d
		Weather.force_kind("storm")
		var wind_pt := peak - d * 1300.0
		var lee_pt := lee_probe
		var rain_wind: float = Weather.rain_at(wind_pt.x, wind_pt.y)
		var rain_lee: float = Weather.rain_at(lee_pt.x, lee_pt.y)
		_check(rain_wind > rain_lee * 1.5,
			"rain shadow: windward %.2f vs lee %.2f" % [rain_wind, rain_lee])
		# The wetness field diverges under that sky: the windward cell
		# soaks fast while the lee cell only creeps (a long enough storm
		# would eventually soak both — the shadow buys TIME, not immunity).
		Climate.wetness = 0.3
		for i in 5:
			Climate._hourly(0)
		_check(Climate.wetness_at(wind_pt.x, wind_pt.y)
				> Climate.wetness_at(lee_pt.x, lee_pt.y) + 0.1,
			"wetness field: windward soaks, the lee lags")
		Climate.wetness = was_wet
		Climate.snow = was_snow
		Weather._wind_angle = was_angle
		Weather.wind_dir = Vector2.from_angle(was_angle)
		Weather.force_kind("calm")
	# Legacy migration: a save with only the scalar floods the field. The
	# synthetic legacy shape is injected through the FORCING DOOR (force_value,
	# docs/SUBSTRATE.md §2a point 5): under the flipped default posture
	# (mirror retired) a plain set_value of a held-owned key is correctly a
	# no-op — an external mutation must write through, exactly like `state set`.
	# (The real load path is unaffected: SaveManager rides WorldState.restore.)
	var keep_wet: float = Climate.wetness
	WorldState.force_value("climate.wet_grid", null)
	WorldState.force_value("climate.wetness", 0.42)
	Climate.load_state()
	_check(absf(Climate.wetness - 0.42) < 0.001,
		"legacy scalar migrates into the field")
	_check(absf(Climate.wetness_at(-6000.0, 6000.0) - 0.42) < 0.001,
		"migration floods every cell")
	Climate.wetness = keep_wet
	# Phase 2 — the thermal field. Aspect is pure: slopes facing the
	# sun's current bearing run warmer, nothing at night or under the
	# noon zenith, and mirrored slopes mirror.
	_check(Climate.aspect_term(-0.5, 9.0) > 0.3,
		"morning warms the east-facing slope")
	_check(Climate.aspect_term(-0.5, 15.0) < -0.3,
		"the same slope cools in the afternoon shade")
	_check(absf(Climate.aspect_term(-0.5, 12.0)) < 0.01,
		"the zenith sun plays no favorites")
	_check(Climate.aspect_term(-0.5, 0.0) == 0.0, "no aspect at night")
	_check(absf(Climate.aspect_term(0.5, 9.0) + Climate.aspect_term(-0.5, 9.0)) < 0.001,
		"mirrored slopes mirror")
	# Maritime: the swing damps with sea proximity. World-agnostic: find
	# one fully-inland land point (no sea in its 1.8km cross → swing 1.0)
	# and one open-sea point on the same coarse grid, and the sea point
	# must read more maritime. Skips only when the world lacks one side.
	var ref_swing: float = Climate._swing(Climate.REFERENCE.x, Climate.REFERENCE.y)
	_check(ref_swing >= Climate.MARITIME_SWING and ref_swing <= 1.0,
		"reference swing bounded (%.2f)" % ref_swing)
	var inland := Vector2.INF
	var offshore := Vector2.INF
	for gx in range(-14, 15):
		for gz in range(-14, 15):
			var mp := Vector2(gx * 512.0, gz * 512.0)
			var mh := Terrain.height(mp.x, mp.y)
			if inland.x == INF and mh > Terrain.sea_level + 5.0 \
					and Climate._swing(mp.x, mp.y) >= 0.999:
				inland = mp
			elif offshore.x == INF and mh < Terrain.sea_level \
					and Climate._swing(mp.x, mp.y) <= Climate.MARITIME_SWING + 0.1:
				offshore = mp
	if inland.x == INF or offshore.x == INF:
		print("  (skip maritime: world lacks a deep-inland or open-sea point)")
	else:
		_check(Climate._swing(offshore.x, offshore.y) < Climate._swing(inland.x, inland.y),
			"open water reads more maritime than deep inland")
	# The reference reads base temperature minus its own altitude lapse (not
	# pinned to a flat valley floor any more — the reference sits on real terrain).
	var ref_h := maxf(Terrain.height(Climate.REFERENCE.x, Climate.REFERENCE.y), 0.0)
	_check(absf(Climate.temperature(Climate.REFERENCE.x, Climate.REFERENCE.y)
			- (Climate.base_temperature() - Climate.LAPSE * ref_h)) < 3.0,
		"temperature at the reference follows the lapse rate")
	# Phase 3 — humidity. Same point, same wind: only the pinned factor
	# moves, so these hold on any map.
	_check(Climate._humidity_for(0.0, -150.0, 0.5, 10.0)
			> Climate._humidity_for(0.0, -150.0, 0.5, 700.0),
		"the air thins dry with altitude")
	_check(Climate._humidity_for(0.0, -150.0, 0.9, 10.0)
			> Climate._humidity_for(0.0, -150.0, 0.1, 10.0),
		"wet ground humidifies the air above it")
	Weather.force_kind("calm")
	var hum_calm: float = Climate.humidity(Climate.REFERENCE.x, Climate.REFERENCE.y)
	Weather.force_kind("storm")
	_check(Climate.humidity(Climate.REFERENCE.x, Climate.REFERENCE.y) > hum_calm + 0.1,
		"a wet front saturates the air")
	Weather.force_kind("calm")
	# Dew at dawn: humid, still, pre-dawn air WETS the ground instead of
	# drying it. Wind set so the upwind probes reach the east sea.
	var was_angle2: float = Weather._wind_angle
	var was_hours: float = GameClock.hours
	Weather.wind_dir = Vector2(-1.0, 0.0)
	Weather._wind_angle = Weather.wind_dir.angle()
	var span2: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span2.x - 1.0, 24.0)  # ~solar 5: the dew window
	Climate.wetness = 0.75
	Climate._hourly(0)
	# Dew needs a humidity source upwind — the sea. A content-empty world
	# has no sea to breathe moisture, so the ground can't dew; the humidity
	# machinery above is proven synthetically regardless.
	if Terrain.sea_level > -1e11:
		_check(Climate.wetness > 0.76,
			"pre-dawn saturated air dews the ground (%.3f)" % Climate.wetness)
	else:
		print("  climate dew: SKIP (no sea to source humidity — content-empty game)")
	GameClock.hours = was_hours
	Weather._wind_angle = was_angle2
	Weather.wind_dir = Vector2.from_angle(was_angle2)
	Climate.wetness = keep_wet
	# The Toolkit sees all of it: the world panel's HERE block composes
	# every per-position query without a camera (falls back to the
	# valley), and the substrate summaries carry the new numbers.
	var here: String = Toolkit._here_summary()
	for token in ["hum=", "wet=", "swing=", "aspect=", "stage=", "biome=", "snowline"]:
		_check(here.contains(token), "world panel HERE block carries " + token)
	_check(Climate.summary().contains("hum("), "Climate summary carries humidity")
	_check(Weather.summary().contains("oro="), "Weather summary carries the oro factor")
	_check(absf(Weather.wind_dir.length() - 1.0) < 0.001,
		"wind direction stays a unit vector as it wanders")


## Flora lifecycle: vitality chases climate, flags latch story-seeds.
func _test_flora() -> void:
	_check(FloraLife.target_for("spring", 0.8, 18.0) > FloraLife.target_for("winter", 0.8, 18.0),
		"spring outgrows winter")
	_check(FloraLife.target_for("summer", 0.1, 34.0) < FloraLife.target_for("summer", 0.7, 22.0),
		"hot and dry starves the flora")
	var was_v: float = FloraLife.vitality
	var was_wet: float = Climate.wetness
	Climate.wetness = 0.0
	FloraLife.vitality = 0.1
	WorldState.set_value("flora.parched", false)
	WorldState.set_value("flora.bloom", false)
	FloraLife._hourly(0)
	_check(WorldState.has_flag("flora.parched"), "dry + starved flora -> parched flag")
	Climate.wetness = 1.0
	FloraLife.vitality = 0.9
	FloraLife._hourly(0)
	_check(WorldState.has_flag("flora.bloom"), "soaked + thriving flora -> bloom flag")
	_check(not WorldState.has_flag("flora.parched"), "recovery clears parched")
	# Lifecycle stages are a pure function of season + vitality (framework).
	_check(FloraLife.stage_for("spring", 0.9) == "bloom", "lush spring blooms")
	_check(FloraLife.stage_for("spring", 0.4) == "sprout", "lean spring sprouts")
	_check(FloraLife.stage_for("autumn", 0.7) == "seed", "autumn seeds")
	_check(FloraLife.stage_for("summer", 0.2) == "dry", "parched flora reads dry")
	# v2 — species records: game content (data/flora). A content-empty
	# game has no species, so composition and moisture-varied spatial
	# vitality (which read the species table) can't be asserted. The
	# vitality FIELD math is proven by the harvest block below.
	if not FloraLife.species.is_empty():
		_check(FloraLife.species.size() >= 6, "species records loaded")
		var tuft: Dictionary = {}
		for def: Dictionary in FloraLife.species:
			if str(def.id) == "bloom_tuft":
				tuft = def
		_check(not tuft.is_empty(), "bloom_tuft record exists")
		_check(FloraLife.stage_art(tuft, "bloom") == FloraLife.stage_art(tuft, "grow"),
			"missing stage art falls back to grow (same placeholder slots)")
		_check(str(tuft.get("yields", "")) == "dried_bloom", "bloom_tuft yields dried_bloom")
		# Species composition: biome weights + the moisture gate.
		_check(FloraLife.species_weight(tuft, "oasis_green", 0.8) > 0.0,
			"tufts grow in the oasis")
		_check(FloraLife.species_weight(tuft, "bare_peak", 0.8) == 0.0,
			"no tufts on bare peaks")
		_check(FloraLife.species_weight(tuft, "oasis_green", 0.8)
				> FloraLife.species_weight(tuft, "oasis_green", 0.0),
			"drought gates the thirsty species down")
		# Spatial vitality tracks the live moisture field: the same point
		# reads greener when the ground is wet than when it's dry.
		FloraLife.vitality = 0.5
		Climate.wetness = 0.1
		var dry_v: float = FloraLife.vitality_at(0.0, 0.0)
		Climate.wetness = 0.9
		var wet_v: float = FloraLife.vitality_at(0.0, 0.0)
		_check(wet_v >= dry_v and is_finite(wet_v) and wet_v > 0.0 and wet_v <= 1.0,
			"spatial vitality tracks local moisture (%.3f dry -> %.3f wet)" % [dry_v, wet_v])
	else:
		print("  flora species: SKIP (no species records — content-empty game)")
	# Honest harvest: gathering wounds the cell, hours heal it, and a
	# healed cell is forgotten (the save only remembers open wounds).
	var cell := Vector2i(0, -3)  # floor((70,-310)/128)
	FloraLife.harvest_at(70.0, -310.0)
	_check(FloraLife.depletion(cell) > 0.0, "gathering wounds the cell")
	_check(not (WorldState.get_value("flora.cells", {}) as Dictionary).is_empty(),
		"wound mirrored to WorldState")
	var before: float = FloraLife.depletion(cell)
	FloraLife._regrow()
	var after: float = FloraLife.depletion(cell)
	_check(after < before and after > 0.0, "an hour regrows a little, not all")
	for i in 400:
		FloraLife._regrow()
	_check(FloraLife.depletion(cell) == 0.0, "the wound heals in time")
	_check((WorldState.get_value("flora.cells", {}) as Dictionary).is_empty(),
		"healed cells are forgotten — save stays lean")
	# Depletion survives a save/load (load_state re-reads the mirror).
	FloraLife.harvest_at(-500.0, 900.0)
	FloraLife.load_state()
	_check(FloraLife.depletion(Vector2i(-4, 7)) > 0.0, "depletion survives load_state")
	for i in 400:
		FloraLife._regrow()
	FloraLife.vitality = was_v
	Climate.wetness = was_wet
	WorldState.set_value("flora.bloom", false)
	WorldState.set_value("flora.parched", false)


## Moon phase: real synodic cycle, stateless in real time.
func _test_moon() -> void:
	var epoch: float = GameClock.NEW_MOON_EPOCH
	_check(GameClock.moon_phase_at(epoch) < 0.001, "epoch is a new moon")
	var half: float = GameClock.SYNODIC_DAYS * 0.5 * 86400.0
	_check(absf(GameClock.moon_phase_at(epoch + half) - 0.5) < 0.001,
		"half a synodic month later is full")
	var full_light := 0.5 - 0.5 * cos(TAU * 0.5)
	_check(absf(full_light - 1.0) < 0.001, "full moon is fully lit")
	var phase: float = GameClock.moon_phase()
	_check(phase >= 0.0 and phase < 1.0, "live phase in range")


## Wildlife tier-3: pure-data animals live full days without a body.
func _test_wildlife() -> void:
	# WildlifeManager + the body are game content (the hound), not
	# framework — a content-empty scaffolded game has neither. AgentSim
	# (the generic mind) rides the framework and is proven elsewhere.
	if not ResourceLoader.exists("res://game/wildlife/wildlife_manager.gd"):
		print("  wildlife: SKIP (no WildlifeManager — content-empty game)")
		return
	var mgr: Node = load("res://game/wildlife/wildlife_manager.gd").new()
	var herd: Dictionary = mgr.spawn_herd({
		"id": "test_herd", "count": 2.0,
		"home": {"x": 0.0, "z": 0.0}, "range": 100.0,
		"body_scene": "res://game/wildlife/hound_body.tscn",
		"activities": [
			{"id": "drink", "at": {"x": 50.0, "z": 0.0}, "satisfies": "thirst",
				"rate": 16.0, "hours": [5.0, 9.0]},
			{"id": "prowl", "at": "roam", "satisfies": "wander", "rate": 5.0},
		]})
	var sim: AgentSim = herd.individuals[0].sim
	var span: Vector2 = GameClock.daylight_span()
	GameClock.hours = fposmod(span.x + 1.0, 24.0)  # solar ~7:00, drink window
	sim.needs.thirst = 10.0
	sim.needs.wander = 90.0
	sim.decide()
	_check(sim.current.id == "drink", "thirsty animal heads to water at dawn")
	var start: Vector2 = sim.pos
	sim.advance(1.0)
	_check((sim.pos - Vector2(50.0, 0.0)).length() < 12.0,
		"an hour of data-tier time completes the journey")
	_check(sim.pos != start, "data animal moved without a body")
	sim.advance(1.0)  # arrived: this hour is spent drinking
	_check(sim.needs.thirst > 10.0, "drinking satisfies thirst")
	mgr._save_state()
	var rows: Array = WorldState.get_value("wildlife.test_herd", [])
	_check(rows.size() == 2, "herd persists to WorldState")
	# Herd cohesion: roam draws near the group's heart, not anywhere.
	for i in herd.individuals.size():
		herd.individuals[i].sim.pos = Vector2(20.0 * i, 0.0)
	mgr._update_cohesion(herd)
	var roamer: AgentSim = herd.individuals[1].sim
	_check(roamer.roam_center.is_finite(), "cohesion sets the herd's heart")
	var roam_spot: Vector2 = roamer.resolve_at({"at": "roam"})
	_check((roam_spot - roamer.roam_center).length() <= roamer.cohesion_radius + 0.1,
		"roam targets stay with the herd")
	mgr.free()  # after every mgr use — a freed Node here cost a long bisect
	var body_script := load("res://game/wildlife/wildlife_body.gd")
	var noon: float = body_script.sense_range_for(12.0, 0.0)
	var dark: float = body_script.sense_range_for(0.0, 0.0)
	var moonlit: float = body_script.sense_range_for(0.0, 1.0)
	_check(noon > dark, "creatures see farther by day than by night")
	_check(moonlit > dark, "a full moon lends the night some sight")
	_check(noon > moonlit, "but never as much as the sun")


## A person in the world (CREATION_KIT_REVIEW_V2 #3, THE CAST SHEET): a named
## CHARACTER (identity/body/home/schedule/mind) follows a daily SCHEDULE by the
## clock, walks it across advance_hours, targets a placed MARKER by its record
## id (falling back to home when it's gone), and counts on the budget's agent
## axis. The mind is AgentSim (framework); VillagerManager is a framework
## autoload, so — unlike wildlife — there is no content skip. The live dir
## ships no records, so the SHIPPED EXAMPLE (tests/fixtures/characters/mara.json)
## is the coverage, driven through the real doors — the same record the
## character lint proves clean.
func _test_villager() -> void:
	# The characters schema registered at boot (the autoload's _load ran
	# load_dir even over an empty dir) — the records desk validates a character
	# edit against it, and can re-read the kind live after a landed write.
	_check(not Records.schema_for("characters").is_empty(),
		"the characters schema registers (the desk validates edits for free)")
	_check(Records.schema_for("characters").has("schedule"),
		"the schema covers the schedule field")
	_check(Records.schema_for("characters").has("identity"),
		"the schema covers the identity field (name + kind)")
	_check(Records.reloader_for("characters").is_valid(),
		"the characters kind registers a live reloader")
	# Schedule validation beyond the field schema: every activity needs a
	# string id + satisfies (the mind scores against the need it names).
	_check(VillagerManager.validate_schedule([
		{"id": "a", "satisfies": "rest"}]) == "",
		"a sound schedule validates clean")
	_check(VillagerManager.validate_schedule([
		{"id": "a"}]) != "",
		"an activity missing 'satisfies' is caught")
	# Full validate coverage through the records desk's OWN door (#3a): the
	# semantic validator is wired, so Records.validate_kind — the truth
	# `records validate characters` answers with — runs the whole CHARACTER
	# judgement (kind, body, home, schedule, mind), not just the field types. A
	# malformed record bounces HERE, before an edit lands, instead of
	# green-lighting a spawn the loader would drop.
	var _cbase := {"id": "x", "identity": {"name": "X", "kind": "villager"},
		"body": {"card": "chars/villager_keeper"}, "home": {"x": 0, "z": 0}}
	_check(Records.validate_kind("characters",
		_cbase.duplicate().merged({"schedule": [{"id": "a", "satisfies": "rest"}]})) == "",
		"a sound character validates clean through the records desk")
	_check(Records.validate_kind("characters",
		_cbase.duplicate().merged({"schedule": [{"id": "a"}]})) != "",
		"the desk's validate runs the schedule check, not just field types")
	_check(Records.validate_kind("characters",
		_cbase.duplicate().merged({"identity": {"name": "X", "kind": "wizard"},
			"schedule": []}, true)).contains("villager|creature"),
		"the desk's validate enumerates identity.kind (villager|creature)")
	# The marker keyword vocabulary (§4c: a marker is a card with a keyword) —
	# injected like the records-desk probe, so no marker asset need ship.
	Cards._slots["probe/marker"] = {"keyword": "marker",
		"files": ["res://kits/probe_marker.glb"]}
	Cards._by_file["res://kits/probe_marker.glb"] = "probe/marker"
	_check(Cards.is_marker("res://kits/probe_marker.glb"),
		"a card carrying keyword 'marker' reads as a marker")
	_check(not Cards.is_marker("res://kits/not_a_marker.glb"),
		"an ordinary card is not a marker")
	Cards._slots.erase("probe/marker")
	Cards._by_file.erase("res://kits/probe_marker.glb")
	# A placed marker the schedule will target (a cell-record with a stable id).
	var mx := 912.0 * 128.0
	var mz := 908.0 * 128.0
	var cell: Vector2i = CellRecords.cell_of(Vector3(mx, 0.0, mz))
	var marker: Dictionary = CellRecords.add(
		Vector3(mx, Terrain.height(mx, mz), mz), "res://kits/probe_marker.glb", 0.0, 1.0)
	var marker_id := String(marker.id)
	# The SHIPPED EXAMPLE record (tests/fixtures/characters/mara.json) — the
	# one the character lint proves clean — drives the whole day. We load it,
	# re-anchor her home + garden marker at the placed marker (so the marker
	# resolves to a real placement), and spawn through the real door. A LOCAL
	# manager instance (never in the tree) drives the mind directly — the
	# WildlifeManager test shape — so no autoload frames perturb it.
	var mgr: Node = load("res://game/villagers/villager_manager.gd").new()
	var home := Vector2(mx - 60.0, mz)
	var mara: Dictionary = Records.load_json("res://tests/fixtures/characters/mara.json")
	_check(mara is Dictionary and mara.get("id") == "mara",
		"the shipped example character record loads")
	mara.home = {"x": home.x, "z": home.y}
	mara.schedule[0].at = {"marker": marker_id}  # garden -> the placed marker
	var v: Dictionary = mgr.spawn_character(mara)
	_check(not v.is_empty(), "a villager mind rises from the example record")
	_check(v.name == "Mara" and v.kind == "villager",
		"identity.name/kind ride onto the entry")
	_check(v.palette.has("base"), "the record's body.palette rides to embodiment")
	var sim: AgentSim = v.sim
	_check(not sim.solar_gate and is_equal_approx(sim.keep_bias, 1.1),
		"identity.kind=villager keeps the clock; mind.keep_bias tuned the mind")
	# Mid-morning, work depleted: she chooses the garden, and the marker
	# target resolves to the placed marker's live XZ (not a raw coordinate).
	GameClock.hours = 9.0
	sim.needs.work = 5.0
	sim.needs.rest = 95.0
	sim.decide()
	_check(sim.current.id == "garden", "at mid-morning she chooses the garden")
	_check((sim.target - Vector2(mx, mz)).length() < 1.0,
		"the marker target resolves to the placed marker's position (%s)" % sim.target)
	# She walks her schedule across advance_hours (the manager's catch-up path).
	var start: Vector2 = sim.pos
	mgr.sim_advance_hours(1.0)
	_check(sim.pos != start, "she walks her schedule across advance_hours")
	_check((sim.pos - Vector2(mx, mz)).length() < 14.0,
		"an hour of schedule-time carries her to the marker")
	# Honest fallback: delete the marker, and the next resolution is home —
	# never a dangling reference.
	CellRecords.remove(cell, marker_id)
	_check(sim.resolve_at(sim.current) == sim.home,
		"a deleted marker falls back to home, never a dangling target")
	# Schedule-following by the CLOCK: at night the rest window wins.
	GameClock.hours = 22.0
	sim.needs.work = 95.0
	sim.needs.rest = 5.0
	sim.decide()
	_check(sim.current.id == "rest", "by night she keeps to the rest window")
	# Persistence: the mind survives a save/restore roundtrip.
	mgr._save_state()
	var saved: Dictionary = WorldState.get_value("villager.mara", {})
	_check(not saved.is_empty(), "the villager persists to WorldState")
	# The embodied presence (deliverable 4): a body wears the name and answers
	# an examine with "<name> — <what she's doing>", no dialogue. Instantiated
	# and freed synchronously, so no physics frame runs (no nav, no crash). The
	# record's palette rides on too (CharacterPaint.apply, no crash on a tint).
	var body: Node = load("res://game/villagers/villager_body.tscn").instantiate()
	body.villager_name = "Mara"
	body.palette = v.palette
	add_child(body)
	var presences := body.find_children("*", "Interactable", true, false)
	_check(presences.size() == 1 and (presences[0] as Interactable).prompt == "Mara",
		"the villager body carries one examinable presence, prompt = her name")
	body.set_activity({"id": "garden", "note": "tending the garden"})
	body._on_examined(null)  # the walker examines her
	_check(HUD._line.text == "Mara — tending the garden",
		"examine speaks her name and her activity, no dialogue (got %s)" % HUD._line.text)
	HUD._line.visible = false  # leave the say label as we found it
	body.free()
	mgr.free()  # after every mgr use — a freed Node here cost wildlife a long bisect
	# The budget's agent axis: a villager on the SHIPPED autoload counts (it
	# registered its population with the meter at boot). Add one, read the
	# meter, leave no trace.
	var before: int = Budget.agent_count()
	var counted: Dictionary = VillagerManager.spawn_character({
		"id": "budget_probe", "identity": {"name": "Probe", "kind": "villager"},
		"body": {"card": "chars/villager_keeper"},
		"home": {"x": 0.0, "z": 0.0},
		"schedule": [{"id": "idle", "at": "roam", "satisfies": "wander"}]})
	_check(Budget.agent_count() == before + 1,
		"an embodied-or-not character counts on the budget's agent axis")
	VillagerManager.villagers.erase(counted)
	_check(Budget.agent_count() == before, "removing the villager clears the count")
	# Leave no trace on disk: drop the marker's cell file.
	var cell_path := "%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]
	if FileAccess.file_exists(cell_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cell_path))


## Body records (FW4): the mesh binding that used to be TRAPPED inside
## player.tscn/villager_body.tscn as an ext_resource is now a data record
## the record system can see. This proves both halves: BodyData validates
## the shipped records (and fails LOUDLY on an unknown field / unknown
## family / bad mesh), and the scenes wire their $Body/Model from the
## record — behaviour-identical to the old embed (the AnimationPlayer the
## character scripts reach for is present after instantiation).
func _test_body_records() -> void:
	# The three shipped records load and carry the fox placeholder mesh.
	for bn in ["fox", "player", "villager"]:
		var rec := BodyData.load("res://data/bodies/%s.json" % bn)
		_check(not rec.is_empty(), "body record '%s' loads and validates" % bn)
		_check(rec.get("body_family") == "skinned_glb",
			"body record '%s' is a skinned_glb" % bn)
		_check(String(rec.get("mesh", "")).ends_with("biped_fox.glb"),
			"body record '%s' names the fox placeholder mesh" % bn)
	# Fail-loud discipline: an unknown FIELD, an unknown FAMILY, and a
	# missing mesh each return {} (the push_errors are expected here).
	var tmp := "user://body_probe.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string('{"format":1,"body_family":"skinned_glb",' +
		'"mesh":"res://assets/models/creatures/biped_fox.glb","wat":1}')
	f.close()
	_check(BodyData.load(tmp).is_empty(), "an unknown field fails the load loudly")
	f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string('{"format":1,"body_family":"origami",' +
		'"mesh":"res://assets/models/creatures/biped_fox.glb"}')
	f.close()
	_check(BodyData.load(tmp).is_empty(), "an unknown family fails the load loudly")
	f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string('{"format":1,"body_family":"skinned_glb"}')
	f.close()
	_check(BodyData.load(tmp).is_empty(), "a missing mesh fails the load loudly")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	# BodyLoader wires a "Model" child (carrying its AnimationPlayer) from
	# each record — the exact ordering the scenes rely on: the Body node's
	# _ready adds Model before the character root reaches for it. Driven on
	# a bare loader per record (the full player.tscn runs player.gd's
	# _ready, which defers a world-load we don't want mid-suite; the real
	# player.tscn is exercised by the pace live-parity probe, and the real
	# villager_body.tscn by _test_villager above — both instantiate the
	# scene whole and would crash here if $Body/Model were absent).
	for bn in ["fox", "player", "villager"]:
		var loader := BodyLoader.new()
		loader.record = "res://data/bodies/%s.json" % bn
		add_child(loader)  # _ready fires -> Model added
		var model: Node = loader.get_node_or_null("Model")
		_check(model != null, "BodyLoader wires Model from the '%s' record" % bn)
		if model != null:
			_check(model.find_children("*", "AnimationPlayer", true, false).size() == 1,
				"the '%s' Model carries its AnimationPlayer" % bn)
		loader.free()


## F2 fabric: spring bones are presentation-tier. Headless, the gate
## must refuse — a creature body boots with NO simulator under it, so
## the soak digest can never meet spring state — while the gate-free
## builder must still assemble the windowed path's chains correctly
## (right bones, right joint counts, gouache damping) on both shipped
## rigs. Both halves proved here, meaningfully, under the dummy display.
func _test_fabric_spring() -> void:
	# Chains ride real content now (FW4: fabric_spring.gd carries no
	# PRESETS): the hound's from its wildlife record, the fox's from
	# player.gd's own const — proving the record/const round-trip, not
	# a copy of the tuning. The hound body + record are game content —
	# proven only where they ship. The fox (the framework's default-look
	# body) proves the same builder below, so a content-empty game keeps
	# real fabric coverage.
	if ResourceLoader.exists("res://game/wildlife/hound_body.tscn") \
			and FileAccess.file_exists("res://data/wildlife/star_hounds.json"):
		var hound_rec: Dictionary = Records.load_json("res://data/wildlife/star_hounds.json")
		var hound_chains: Array[Dictionary] = []
		hound_chains.assign(hound_rec.fabric)
		var hound: Node = load("res://game/wildlife/hound_body.tscn").instantiate()
		add_child(hound)
		var model: Node = hound.get_node("Body/Model")
		_check(FabricSpring.adopt(model, hound_chains) == null, "headless adopt refuses")
		_check(hound.find_children("*", "SpringBoneSimulator3D", true, false).is_empty(),
			"headless hound body carries no simulator")
		var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var fs: FabricSpring = FabricSpring.build(skel, hound_chains)
		_check(fs != null, "builder assembles the windowed node")
		if fs != null:
			_check(fs.setting_count == 1, "hound adopts one chain (the tail)")
			_check(fs.get_root_bone_name(0) == "tail.1"
				and fs.get_end_bone_name(0) == "tail_star",
				"tail chain spans tail.1..tail_star")
			_check(fs.get_joint_count(0) == 5, "five tail joints ride the chain (got %d)"
				% fs.get_joint_count(0))
			_check(fs.get_drag(0) >= 0.5, "gouache tuning: heavily damped, never jiggly")
			_check(fs.wind_scale > 0.0, "the tail hears the wind at all")
		hound.queue_free()
	# The fox: ears are LEAF bones — each one-bone chain must grow a
	# virtual tip or there is no lever for the wind to push.
	var fox_script := load("res://game/player/player.gd")
	var fox_chains: Array[Dictionary] = fox_script.FABRIC_CHAINS
	var fox: Node = load("res://assets/models/creatures/biped_fox.glb").instantiate()
	add_child(fox)
	var fskel: Skeleton3D = fox.find_children("*", "Skeleton3D", true, false)[0]
	var ff: FabricSpring = FabricSpring.build(fskel, fox_chains)
	_check(ff != null and ff.setting_count == 2, "fox adopts both ears")
	if ff != null and ff.setting_count == 2:
		_check(ff.is_end_bone_extended(0) and ff.is_end_bone_extended(1),
			"leaf ears grow virtual tips")
		# The virtual tip is a lever on the last joint, not a joint of its
		# own: a one-bone ear stays one joint.
		_check(ff.get_joint_count(0) == 1, "one-bone ear stays one joint (got %d)"
			% ff.get_joint_count(0))
	fox.queue_free()


## Desire paths persist: footsteps wear permanent cells that fade over
## hours and survive a save/load. (The pantry/rumor long-memory retired
## with the authored inhabitants — it lived on the NPC bodies.)
func _test_wear() -> void:
	var spot := Vector2(4321.5, -4321.5)  # far from any real trail
	for i in 5:
		InteractionField.stamp(spot)
		InteractionField._clock += 30.0  # crowding guard: wear needs revisits, not shuffling
	var snap: Dictionary = InteractionField.wear_snapshot()
	var key := "4321_-4322"
	_check(snap.has(key), "footsteps wear a permanent cell")
	_check(float(snap[key]) > 0.15, "repeated walking deepens the wear")
	InteractionField._age_wear(0)
	var aged: Dictionary = InteractionField.wear_snapshot()
	_check(float(aged[key]) < float(snap[key]), "unwalked paths fade over hours")
	InteractionField.wear_restore(snap)
	_check(absf(float(InteractionField.wear_snapshot()[key]) - float(snap[key])) < 0.002,
		"wear survives a save/load roundtrip")
	InteractionField.wear_restore({})  # leave no test residue in the field


## Near-tier navigation: bake from faces, path across, fall back cleanly.
func _test_nav() -> void:
	await get_tree().physics_frame  # let NavigationServer settle before we bake
	# A 20x20m plane in the streamer's exact triangle winding.
	var res := 11
	var step := 2.0
	var faces := PackedVector3Array()
	for iz in res - 1:
		for ix in res - 1:
			var a := Vector3(ix * step, 0.0, iz * step)
			var b := Vector3((ix + 1) * step, 0.0, iz * step)
			var c := Vector3(ix * step, 0.0, (iz + 1) * step)
			var d := Vector3((ix + 1) * step, 0.0, (iz + 1) * step)
			faces.append_array([a, b, c, b, d, c])
	var navmesh: NavigationMesh = Nav.bake_navmesh(faces)
	_check(navmesh.get_polygon_count() > 0, "bake produces walkable polygons")
	var cell := Vector2i(999, 999)
	var origin := Vector3(9990.0, 0.0, 9990.0)
	Nav.add_cell(cell, navmesh, origin)
	NavigationServer3D.map_force_update(Nav._map)
	await get_tree().physics_frame  # NavigationServer syncs the new region on the step
	var p: PackedVector3Array = Nav.path(
		origin + Vector3(2.0, 0.5, 2.0), origin + Vector3(18.0, 0.5, 18.0))
	_check(p.size() >= 2, "path across the baked cell")
	_check(p[p.size() - 1].distance_to(origin + Vector3(18.0, 0.0, 18.0)) < 2.5,
		"path reaches the goal")
	Nav.remove_cell(cell)
	var fallback: PackedVector3Array = Nav.path(Vector3.ZERO, Vector3(10.0, 0.0, 10.0))
	_check(fallback.size() == 2, "no navmesh -> straight-line fallback")

	# The determinism-law proof (docs/PLAN_NAVMESH.md): the embodied body paths
	# AROUND an obstacle while the sim mind walks STRAIGHT THROUGH it. Bake a
	# 24x24m plane with a square hole carved at x,z in [8,16] — the way the real
	# streamer carves water and placement footprints out of the walkable soup.
	# A body crossing (2,12)->(22,12) must bow north or south around the hole;
	# the SIM's straight capped-step line (agent_sim.gd) at z=12 cuts through it.
	# Same bytes, two presentations — this is the whole point of the split.
	var ores := 25  # 0..24 vertices, step 1.0
	var ofaces := PackedVector3Array()
	for iz in ores - 1:
		for ix in ores - 1:
			# Carve the footprint: the quad is out if it falls inside [8,16]^2.
			if ix >= 8 and ix < 16 and iz >= 8 and iz < 16:
				continue
			var a := Vector3(ix, 0.0, iz)
			var b := Vector3(ix + 1, 0.0, iz)
			var cc := Vector3(ix, 0.0, iz + 1)
			var d := Vector3(ix + 1, 0.0, iz + 1)
			ofaces.append_array([a, b, cc, b, d, cc])
	var obs_mesh: NavigationMesh = Nav.bake_navmesh(ofaces)
	_check(obs_mesh.get_polygon_count() > 0, "obstacle cell bakes walkable polygons")
	# The proof reads the WALKABLE SURFACE the bake produced (headless has no live
	# NavigationServer map sync, so we assert the polygons directly — the ground
	# truth the router walks). A straight run at z=12 from (2,12) to (22,12) —
	# the SIM's capped-step line — passes dead through the [8,16] footprint; the
	# navmesh has NO walkable polygon there, so the embodied body cannot follow
	# it and must bow around. Walkable ground DOES exist north and south of the
	# hole, so a route around exists. Same target, two presentations.
	_check(12.0 >= 8.0 and 12.0 < 16.0, "the straight sim line crosses the carved footprint")
	_check(not _nav_covers(obs_mesh, 12.0, 12.0),
		"footprint centre is carved OUT of walkable ground (body can't cross it)")
	_check(_nav_covers(obs_mesh, 2.0, 12.0) and _nav_covers(obs_mesh, 22.0, 12.0),
		"both banks the sim line joins are walkable")
	_check(_nav_covers(obs_mesh, 12.0, 5.0) and _nav_covers(obs_mesh, 12.0, 19.0),
		"walkable ground detours north and south of the footprint")


## Is world point (x,z) inside any of the navmesh's walkable polygons? Reads
## the baked surface straight from the resource (vertices + polygon index sets),
## XZ point-in-polygon by ray crossing — the ground truth the router walks,
## queried without a live NavigationServer map (headless has no map sync).
func _nav_covers(mesh: NavigationMesh, x: float, z: float) -> bool:
	var vs := mesh.get_vertices()
	for pi in mesh.get_polygon_count():
		var poly := mesh.get_polygon(pi)
		var n := poly.size()
		var inside := false
		var j := n - 1
		for k in n:
			var vk := vs[poly[k]]
			var vj := vs[poly[j]]
			if (vk.z > z) != (vj.z > z) \
					and x < (vj.x - vk.x) * (z - vk.z) / (vj.z - vk.z) + vk.x:
				inside = not inside
			j = k
		if inside:
			return true
	return false


## The granular kernel: sand is conserved, spikes slump to repose, flows
## spread — pure math, no thread, no rendering.
func _test_sand_sim() -> void:
	var g := 16
	var delta_field := PackedFloat32Array()
	delta_field.resize(g * g)
	var base := PackedFloat32Array()
	base.resize(g * g)
	var active := PackedInt32Array()
	var queued := PackedByteArray()
	queued.resize(g * g)
	var center := (g / 2) * g + g / 2
	delta_field[center] = 0.3
	queued[center] = 1
	active.append(center)
	var before := 0.0
	for i in g * g:
		before += delta_field[i]
	for step in 300:
		SandField.relax(delta_field, base, active, queued, g, 0.04, 0.3, 4000)
	var after := 0.0
	var peak := 0.0
	for i in g * g:
		after += delta_field[i]
		peak = maxf(peak, delta_field[i])
	_check(absf(after - before) < 0.0005, "sand is conserved through avalanches")
	_check(peak < 0.29, "a spike slumps toward the angle of repose")
	_check(delta_field[center - 1] > 0.0, "material flows to the neighbors")
	# Steep base terrain: material walks downhill across cells.
	var slope_delta := PackedFloat32Array()
	slope_delta.resize(g * g)
	var slope_base := PackedFloat32Array()
	slope_base.resize(g * g)
	for y in g:
		for x in g:
			slope_base[y * g + x] = -x * 0.1  # falls to +x
	var a2 := PackedInt32Array()
	var q2 := PackedByteArray()
	q2.resize(g * g)
	var mid := (g / 2) * g + 3
	slope_delta[mid] = 0.25
	q2[mid] = 1
	a2.append(mid)
	for step in 300:
		SandField.relax(slope_delta, slope_base, a2, q2, g, 0.04, 0.3, 4000)
	var right := 0.0
	var left := 0.0
	for y in g:
		for x in g:
			if x >= 6:
				right += slope_delta[y * g + x]
			elif x <= 2:
				left += slope_delta[y * g + x]
	_check(right > 0.06 and right > left * 2.0, "piled sand avalanches downhill")


## F1 wind fabric (PLAN_FABRIC): the cloth slots carry the "wind" flag,
## a resolved file finds its card again (the override path's lookup), and
## the fabric_wind shader + material wiring builds headless. Card-level
## only — binaries are untracked cache and the loader tolerates them
## missing, so no GLB is loaded here.
func _test_fabric() -> void:
	# The fabric CARDS are game content (valley's textiles); a content-
	# empty game has none. The shader wiring below is framework and always
	# rides. `entry_for_file` on an unknown path is machinery too.
	var slots: Array = Cards.fabric_slots()
	if not slots.is_empty():
		for s in ["props/textile", "props/textile/banner", "props/camp/tent", "props/nautical/net"]:
			_check(slots.has(s), "fabric flag on " + s)
		var f: String = Cards.resolve("props/textile/banner", 0)
		var e: Dictionary = Cards.entry_for_file(f)
		_check(String(e.get("wind", "")) == "fabric", "resolved file finds its fabric card")
		_check(float(e.get("wind_hang", 0.0)) > 0.0, "wind_hang rides the card")
	else:
		print("  fabric cards: SKIP (no fabric slots — content-empty game)")
	_check(Cards.entry_for_file("res://nope.glb").is_empty(), "unknown file yields {}")
	var sh: Shader = load("res://game/shaders/fabric_wind.gdshader")
	_check(sh != null, "fabric_wind shader loads")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("hang", 1.2)
	_check(float(mat.get_shader_parameter("hang")) == 1.2, "fabric material takes its knobs")


## The Threshold (PLAN_INTERIORS I1): the `door` key rides an ordinary
## placement row to disk verbatim, enter stands the player in the pocket
## at altitude, exit stands them back at the door, and a save made inside
## restores inside — with the honest fallback to the door when the
## interior record is gone. Guards the live save file (snapshot +
## restore) and leaves no cell file behind.
func _test_threshold() -> void:
	# The interior record loads and carries its one way home.
	var def: Dictionary = Interiors.definition("smugglers_cellar")
	# The cellar is valley content; a content-empty game has no interiors.
	# The machinery's ground truth — a missing interior answers {} — still
	# holds and is the fallback every game leans on, so prove that much.
	if def.is_empty():
		_check(Interiors.definition("no_such_interior").is_empty(),
			"a missing interior answers {} (the fallback's ground truth)")
		print("  threshold: SKIP crossing (no interior records — content-empty game)")
		return
	_check(not def.is_empty(), "smugglers_cellar record loads")
	var exits := 0
	for row: Dictionary in def.get("placements", []):
		if bool((row.get("door", {}) as Dictionary).get("exit", false)):
			exits += 1
	_check(exits == 1, "the cellar has exactly one exit-door row")
	_check(Interiors.definition("no_such_interior").is_empty(),
		"a missing interior answers {} (the fallback's ground truth)")

	# A door is a placement row that learned one key: disk ride-through.
	var x := 905.0 * 128.0
	var z := 905.0 * 128.0
	var cell: Vector2i = CellRecords.cell_of(Vector3(x, 0.0, z))
	_check(CellRecords.records(cell).is_empty(), "threshold test cell starts empty")
	var h: float = Terrain.height(x, z)
	var rec: Dictionary = CellRecords.add(Vector3(x, h, z),
		"res://assets/models/arch/village/door_01.glb", 0.0, 1.0)
	CellRecords.update(cell, String(rec["id"]),
		{"door": {"interior": "smugglers_cellar"}})
	CellRecords.flush()
	var on_disk: Variant = Records.load_json(
		"%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y])
	var disk_door: Dictionary = {}
	if on_disk is Array and (on_disk as Array).size() == 1:
		disk_door = ((on_disk as Array)[0] as Dictionary).get("door", {})
	_check(String(disk_door.get("interior", "")) == "smugglers_cellar",
		"the door key rides the cell file verbatim (no migration)")

	# Crossing mechanics: a bare body in the player group is enough here
	# (physics standing is the headless probe's job, on the real world).
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	var door_pos := Vector3(x, h, z)
	player.global_position = door_pos
	Interiors.fade_seconds = 0.02  # frames, not wall-clock, under test
	await Interiors.enter("smugglers_cellar", door_pos, 0.0, player)
	_check(Interiors.inside, "enter raises the ONE presentation flag")
	_check(player.global_position.y > Interiors.POCKET_ALT - 50.0,
		"the player stands at pocket altitude")
	# Binaries are untracked cache: expect exactly the resolvable rows
	# (+1 for the light rig), so a binary-less checkout stays honest.
	var resolvable := 0
	for row: Dictionary in def.get("placements", []):
		if Kit.scene_for(str(row.get("kit", ""))) != null:
			resolvable += 1
	_check(is_instance_valid(Interiors._pocket)
		and Interiors._pocket.get_child_count() == resolvable + 1,
		"the pocket holds the interior's placements (%d resolvable)" % resolvable)

	# Save v2, made inside: {x,z} anchors at the DOOR (a v1-shaped reader
	# still lands somewhere true) + the interior id and local position.
	# Guard the live save and its backup clock — the test leaves no trace.
	var save_guard: Dictionary = {}
	for gp: String in [SaveGame.PATH, SaveGame.PATH + ".bak1", SaveGame.PATH + ".bak2"]:
		save_guard[gp] = FileAccess.get_file_as_string(gp) \
			if FileAccess.file_exists(gp) else null
	SaveGame._last_backup_unix = Time.get_unix_time_from_system()
	SaveGame.save_game()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
	_check(saved is Dictionary and int((saved as Dictionary).get("version", 0)) == 2,
		"the save wears version 2")
	var pd: Dictionary = (saved as Dictionary).get("player", {})
	_check(String(pd.get("interior", "")) == "smugglers_cellar",
		"the save carries the interior id")
	_check(absf(float(pd.get("x", 1e12)) - x) < 0.01
		and absf(float(pd.get("z", 1e12)) - z) < 0.01,
		"the save's {x,z} is the DOOR, not the pocket")
	_check(pd.has("ix") and pd.has("iy") and pd.has("iz"),
		"the save carries the pocket-local position")

	# Exit: pocket freed, flag down, player at the door.
	await Interiors.exit(player)
	_check(not Interiors.inside, "exit lowers the flag")
	_check(Interiors._pocket == null, "the pocket frees on exit")
	_check(Vector2(player.global_position.x - x,
		player.global_position.z - z).length() < 3.0,
		"exit stands the player at the door")

	# Restore: the load routes back inside through the Threshold.
	await SaveGame.load_into_world()
	_check(Interiors.inside and Interiors.interior_id == "smugglers_cellar",
		"a save made inside restores inside")
	_check(player.global_position.y > Interiors.POCKET_ALT - 50.0,
		"restore seats the player back at altitude")
	await Interiors.exit(player)

	# The honest fallback: the interior record is gone — wake at the door.
	var gone: Dictionary = saved
	(gone["player"] as Dictionary)["interior"] = "gone_cellar"
	var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(gone))
	f.close()
	await SaveGame.load_into_world()
	_check(not Interiors.inside, "a gone interior falls back outside")
	_check(Vector2(player.global_position.x - x,
		player.global_position.z - z).length() < 3.0,
		"the fallback seat is the door itself")

	# Leave no trace: the save files, the fade pace, the cell, the player.
	for gp: String in save_guard:
		if save_guard[gp] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(gp))
		else:
			var g := FileAccess.open(gp, FileAccess.WRITE)
			g.store_string(save_guard[gp])
			g.close()
	Interiors.fade_seconds = 0.35
	while CellRecords.remove_last(cell):
		pass
	var cpath := "%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]
	if FileAccess.file_exists(cpath):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cpath))
	player.remove_from_group("player")
	player.queue_free()


## I2 — the hand inside (PLAN_INTERIORS §4). InteriorRecords is the
## Chronicle's second book: while the player stands in a pocket the
## Toolkit's place/select/move/delete/undo funnel targets THAT interior's
## records (the active-book seam, toolkit `_book()`), the mementos carry
## which store they touched so Z reverses across the threshold, and the
## JSON on disk is the room (local coords, no ground_dy, y absolute).
## Drives everything headless over a THROWAWAY interior so the hand-typed
## smugglers' cellar is never clobbered.
func _test_interior_hand() -> void:
	var tid := "test_interior_hand"
	var tpath := "%s/%s.json" % [InteriorRecords.DIR, tid]
	# A throwaway interior: one exit-door row is enough to enter and leave.
	var seed := {
		"id": tid, "name": "the test cell", "light": "dark_warm",
		"ambience": "", "placements": [
			{"id": "ex", "kit": "res://assets/models/arch/village/door_01.glb",
				"x": 0.0, "y": 0.0, "z": 2.0, "yaw": 0.0, "scale": 1.0,
				"door": {"exit": true}}]}
	var pre_existed := FileAccess.file_exists(tpath)
	# Content-empty tree: data/interiors may not exist yet. The real
	# InteriorRecords writer make_dir_recursive's before WRITE; this test
	# opens the file directly, so mirror that (else open() returns null and
	# store_string crashes). Idempotent where the dir already exists.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(InteriorRecords.DIR))
	var f0 := FileAccess.open(tpath, FileAccess.WRITE)
	f0.store_string(JSON.stringify(seed, "\t"))
	f0.close()

	# The definition loads through the book's own loader (the records-desk
	# validate verb rides this) and answers {} for a missing id.
	_check(not InteriorRecords._definition(tid).is_empty(),
		"the interior book loads its definition")

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	# Enter the pocket far from anything; the door XZ sets the pocket origin.
	var dx := 918.0 * 128.0
	var dz := 918.0 * 128.0
	var door_pos := Vector3(dx, Terrain.height(dx, dz), dz)
	player.global_position = door_pos
	Interiors.fade_seconds = 0.02
	await Interiors.enter(tid, door_pos, 0.0, player)
	_check(Interiors.inside and Interiors.interior_id == tid,
		"the player crosses into the test interior")
	var origin: Vector3 = Interiors._pocket.position

	# The active book: inside, the hand's funnel points at InteriorRecords.
	_check(Toolkit._book() == InteriorRecords, "inside, _book() is the interior book")
	_check(InteriorRecords.active() == tid, "the book is focused on the interior")

	Toolkit._enter()
	Toolkit._tool = Toolkit.Tool.PLACE
	Toolkit._snap_grid = false
	Toolkit._snap_ground = false
	Toolkit._snap_normal = false
	ToolkitHistory.clear()
	# A card slot, never a prefab entry (those append after the cards).
	Toolkit._place_index = 0
	if Toolkit._palette.is_empty() or Toolkit._palette[0].has("prefab"):
		print("  interior hand: SKIP place (no card palette)")
	else:
		var world_cell: Vector2i = CellRecords.cell_of(door_pos)
		var cells_before: int = CellRecords.records(world_cell).size()
		var rows_before: int = InteriorRecords.records(Vector2i.ZERO).size()
		# Place INSIDE at a floor hit — the record lands in the interior
		# book, in WORLD coords, with no terrain seating (no ground_dy).
		var hit := origin + Vector3(3.0, 0.5, 1.0)
		Toolkit._place_at(hit)
		var rows_after: int = InteriorRecords.records(Vector2i.ZERO).size()
		_check(rows_after == rows_before + 1,
			"place inside lands in the interior book (%d -> %d)" % [rows_before, rows_after])
		_check(CellRecords.records(world_cell).size() == cells_before,
			"place inside NEVER touches the world cells")
		var placed: Dictionary = InteriorRecords.records(Vector2i.ZERO).back()
		var pid := String(placed["id"])
		_check(not placed.has("ground_dy"),
			"an interior record carries no ground_dy (no terrain to anchor)")
		_check(absf(float(placed.y) - hit.y) < 0.001,
			"y is the raycast hit (snap-to-hit inside), absolute")

		# Z undoes the interior place — in the interior book.
		Toolkit._undo()
		_check(InteriorRecords.record(Vector2i.ZERO, pid).is_empty(),
			"Z removes the placed interior record")
		_check(InteriorRecords.records(Vector2i.ZERO).size() == rows_before,
			"the book is back to its before-count")

		# Move + rotate a piece inside, then Z each — the edit funnels ride
		# the active book, mementos and all.
		Toolkit._place_at(origin + Vector3(-2.0, 0.5, -1.0))
		var mid := String(InteriorRecords.records(Vector2i.ZERO).back()["id"])
		Toolkit._pick_at(origin + Vector3(-2.0, 0.0, -1.0))
		_check(Toolkit._sel_id == mid, "RMB picks the interior record")
		var yaw0 := float(InteriorRecords.record(Vector2i.ZERO, mid).yaw)
		Toolkit._sel_rotate(1.0)
		_check(absf(float(InteriorRecords.record(Vector2i.ZERO, mid).yaw)
				- wrapf(yaw0 + Toolkit.SEL_YAW_STEP, 0.0, TAU)) < 0.001,
			"R turns the interior record")
		Toolkit._sel_move_to(origin + Vector3(4.0, 0.7, 4.0))
		var moved: Dictionary = InteriorRecords.record(Vector2i.ZERO, mid)
		_check(absf(float(moved.x) - (origin.x + 4.0)) < 0.001
				and absf(float(moved.y) - (origin.y + 0.7)) < 0.001,
			"G moves the interior record to the floor hit (world coords)")
		Toolkit._undo()  # undo the move
		Toolkit._undo()  # undo the rotate
		Toolkit._undo()  # undo the place
		_check(InteriorRecords.record(Vector2i.ZERO, mid).is_empty(),
			"three Z walk the interior edits all the way back")

		# --- Undo ACROSS the threshold (the honest cross-store Z): place
		# inside, step out, place in the world, then Z the world place and Z
		# the interior place — each lands in the store it touched.
		Toolkit._place_at(origin + Vector3(1.0, 0.4, 1.0))
		var inside_id := String(InteriorRecords.records(Vector2i.ZERO).back()["id"])
		await Interiors.exit(player)
		_check(not Interiors.inside, "stepped back out to the world")
		_check(Toolkit._book() == CellRecords, "outside, _book() is the world cells")
		Toolkit._deselect()
		var wcell: Vector2i = CellRecords.cell_of(door_pos)
		var wbefore: int = CellRecords.records(wcell).size()
		Toolkit._place_at(Vector3(dx, Terrain.height(dx, dz), dz))
		_check(CellRecords.records(wcell).size() == wbefore + 1,
			"place outside lands in the world cells")
		var world_id := String(CellRecords.records(wcell).back()["id"])
		Toolkit._undo()  # the newest action: the world place
		_check(CellRecords.record(wcell, world_id).is_empty(),
			"the first Z reverses the WORLD place (CellRecords)")
		_check(not InteriorRecords.record(Vector2i.ZERO, inside_id).is_empty(),
			"the interior record still stands (untouched by the world undo)")
		Toolkit._undo()  # the older action: the interior place, from outside
		_check(InteriorRecords.record(Vector2i.ZERO, inside_id).is_empty(),
			"the second Z reaches BACK across the threshold to the interior book")

	# --- The JSON on disk is the room: add a record, flush, and read the
	# file back — LOCAL coords (world minus the pocket origin), header kept,
	# no ground_dy. Then a fresh focus restores world coords.
	InteriorRecords.focus(tid, origin)  # re-point (exit left the book intact)
	var rec: Dictionary = InteriorRecords.add(
		origin + Vector3(5.0, 0.25, -3.0), "kit_iface", 1.5, 1.1)
	var rid := String(rec["id"])
	InteriorRecords.flush()
	_check(not InteriorRecords.has_dirty(), "flush clears the interior dirty ledger")
	var on_disk: Variant = Records.load_json(tpath)
	_check(on_disk is Dictionary and String((on_disk as Dictionary).get("name", ""))
			== "the test cell", "the interior header survives a save")
	var disk_rows: Array = (on_disk as Dictionary).get("placements", [])
	var disk_rec: Dictionary = {}
	for row: Dictionary in disk_rows:
		if String(row.get("id", "")) == rid:
			disk_rec = row
	_check(not disk_rec.is_empty(), "the added record reached disk")
	_check(absf(float(disk_rec.get("x", 1e9)) - 5.0) < 0.001
			and absf(float(disk_rec.get("y", 1e9)) - 0.25) < 0.001
			and absf(float(disk_rec.get("z", 1e9)) + 3.0) < 0.001,
		"disk coords are LOCAL to the pocket origin (world minus origin)")
	_check(not disk_rec.has("ground_dy"),
		"the interior file carries no ground_dy (no terrain)")
	# A fresh focus reads local off disk and restores world coords in memory.
	InteriorRecords.focus(tid, origin)
	var reread: Dictionary = InteriorRecords.record(Vector2i.ZERO, rid)
	_check(not reread.is_empty()
			and absf(float(reread.x) - (origin.x + 5.0)) < 0.001,
		"a fresh focus restores world coords from the local file")

	# Leave no trace: release the hand (Toolkit._exit wants the real player
	# rig — release by hand as the other toolkit tests do), leave the pocket
	# if still standing, restore the fade pace, drop the temp file + player.
	Toolkit.set_tool("sculpt")  # restore the boot defaults later probes read
	Toolkit.set_brush_m(12.0)
	Toolkit.set_biome(5)
	Toolkit._place_index = 0
	Toolkit.active = false
	Toolkit.set_process(false)
	if Interiors.inside:
		await Interiors.exit(player)
	Interiors.fade_seconds = 0.35
	if not pre_existed and FileAccess.file_exists(tpath):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tpath))
	var wcpath := "%s/cell_%d_%d.json" % [
		CellRecords.DIR, CellRecords.cell_of(door_pos).x, CellRecords.cell_of(door_pos).y]
	if FileAccess.file_exists(wcpath):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(wcpath))
	player.remove_from_group("player")
	player.queue_free()


## Conditions v2 (DESIGN_QUESTS §5): composition, the new predicates,
## flag-truthiness over latch dictionaries, mechanical key extraction,
## and the closed-table lint. The language is closed — these rows are
## the whole vocabulary, forever.
func _test_conditions_v2() -> void:
	# Composition: all / any / not; bare dictionaries still AND (v1).
	WorldState.set_flag("test.v2.a")
	_check(Conditions.eval({"all": [{"flag": "test.v2.a"}, {"not_flag": "test.v2.b"}]}),
		"all composes")
	_check(Conditions.eval({"any": [{"flag": "test.v2.b"}, {"flag": "test.v2.a"}]}),
		"any composes")
	_check(not Conditions.eval({"any": [{"flag": "test.v2.b"}, {"flag": "test.v2.c"}]}),
		"any fails when every arm fails")
	_check(not Conditions.eval({"not": {"flag": "test.v2.a"}}), "not negates")
	_check(Conditions.eval({"not": {"flag": "test.v2.b"}}), "not on unset passes")
	# eq / lte symmetrize v1's gte; strings compare too.
	WorldState.set_value("test.v2.n", 0.4)
	WorldState.set_value("test.v2.s", "storm")
	_check(Conditions.eval({"eq": ["test.v2.s", "storm"]}), "eq on strings")
	_check(Conditions.eval({"lte": ["test.v2.n", 0.5]}), "lte pass")
	_check(not Conditions.eval({"lte": ["test.v2.n", 0.3]}), "lte fail")
	_check(Conditions.eval({"gte": ["test.v2.n", 0.4]}), "gte reads floats now")
	# A latch dictionary IS a set flag (the memoir rides in the value).
	WorldState.set_value("journal.qa.stage", {"day": 4, "season": "summer", "prose": "x"})
	_check(Conditions.eval({"flag": "journal.qa.stage"}), "latch dict reads as a set flag")
	_check(not Conditions.eval({"not_flag": "journal.qa.stage"}), "not_flag sees the latch")
	# season / weather sugar, time_between (solar, inclusive, wraps),
	# since (latches store their day). Mirrors saved and restored around.
	var season0: Variant = WorldState.get_value("time.season")
	var hour0: Variant = WorldState.get_value("time.hour")
	var day0: Variant = WorldState.get_value("time.day")
	WorldState.set_value("time.season", "autumn")
	_check(Conditions.eval({"season": "autumn"}), "season sugar")
	_check(Conditions.eval({"season": ["winter", "autumn"]}), "season list")
	_check(not Conditions.eval({"season": "spring"}), "season fail")
	WorldState.set_value("time.hour", 19)
	_check(Conditions.eval({"time_between": [18, 20]}), "time_between inside")
	_check(not Conditions.eval({"time_between": [21, 23]}), "time_between outside")
	_check(not Conditions.eval({"time_between": [22, 4]}), "time_between wrap misses 19")
	WorldState.set_value("time.hour", 23)
	_check(Conditions.eval({"time_between": [22, 4]}), "time_between wraps midnight")
	WorldState.set_value("time.day", 8)
	_check(Conditions.eval({"since": ["journal.qa.stage", 3]}), "since reads the latch day")
	_check(not Conditions.eval({"since": ["journal.qa.stage", 5]}), "since not yet")
	_check(not Conditions.eval({"since": ["journal.qa.unset", 1]}), "since on no latch fails")
	# knows (the S1 shape — a key read today, minds later).
	WorldState.set_value("npc.player.knows.qa_fact", true)
	_check(Conditions.eval({"knows": ["player", "qa_fact"]}), "knows reads the mind mirror")
	_check(not Conditions.eval({"knows": ["keeper", "qa_fact"]}), "knows fails unheard")
	# item_tag: the keyword law in the pack (identity-free counts).
	Items._defs["qa_berry"] = {"id": "qa_berry", "name": "QA Berry", "tags": ["food"]}
	Items.add("qa_berry", 2)
	_check(Conditions.eval({"item_tag": ["food", 2]}), "item_tag counts by tag")
	_check(not Conditions.eval({"item_tag": ["food", 3]}), "item_tag respects n")
	_check(not Conditions.eval({"item_tag": ["tool", 1]}), "item_tag misses untagged")
	Items.add("qa_berry", -2)
	Items._defs.erase("qa_berry")
	# Reserved rows fail closed; unknown predicates fail closed.
	_check(not Conditions.eval({"opinion_band": ["keeper", "warm"]}),
		"reserved predicate fails closed")
	_check(not Conditions.eval({"custom": ["moody"], "watch": ["test.v2.a"]}),
		"custom fails closed until the hooks door (Q3)")
	# keys_of: mechanical, total (the index seed).
	var keys := Conditions.keys_of({"all": [
		{"flag": "a.b"}, {"since": ["journal.q.s", 2]},
		{"season": "winter"}, {"item": ["pot", 1]},
		{"custom": ["moody"], "watch": ["npc.keeper.mood"]}]})
	for want in ["a.b", "journal.q.s", "time.day", "time.season",
			"player.inventory", "npc.keeper.mood"]:
		_check(keys.has(want), "keys_of extracts %s" % want)
	# The closed-table lint refuses what the evaluator refuses.
	_check(not Conditions.lint({"expr": "1 > 0"}, "qa").is_empty(),
		"lint refuses unknown predicates")
	_check(not Conditions.lint({"told": ["a", "b", "f"]}, "qa").is_empty(),
		"lint refuses reserved rows")
	_check(not Conditions.lint({"custom": ["moody"]}, "qa").is_empty(),
		"lint refuses custom without watch")
	_check(Conditions.lint({"any": [{"flag": "x"}, {"weather": ["storm"]}]}, "qa").is_empty(),
		"lint passes the spoken language")
	# Restore the mirrors the clock owns.
	WorldState.set_value("time.season", season0)
	WorldState.set_value("time.hour", hour0)
	WorldState.set_value("time.day", day0)


## The Dry Spell v2 end-to-end THROUGH THE REAL SIM (Q1's "done means"):
## FloraLife mints flora.parched from real vitality, Story latches the
## root off the mirror; forced storms rain the valley green through real
## advance_hours catch-up, the terminal latches, and both memoir entries
## read in the J screen. The only pokes are sanctioned doors: the save
## door (flora.vitality + load_state) and the dev weather door
## (force_kind — the Y key's path).
func _test_story_dry_spell_real() -> void:
	# dry_spell is a shipped VALLEY quest, not framework. The Story
	# machinery it exercises is proven synthetically in the quest harness
	# (tests/quests/*.test.json, inline records) — so a content-empty game
	# keeps real Story coverage without this valley record.
	if not Story.quests.has("dry_spell"):
		print("  dry spell: SKIP (quest not shipped — content-empty game)")
		return
	_check(Story.quests.has("dry_spell"), "the dry spell record loads")
	# Hermetic slate: drop any journal state earlier tests minted and let
	# Story re-derive (the save door — restore emits no signals).
	var snap := WorldState.snapshot()
	var clean: Dictionary = {}
	for k: String in snap:
		if not k.begins_with("journal.") and not k.begins_with("choice."):
			clean[k] = snap[k]
	clean["flora.parched"] = false
	clean["flora.vitality"] = 0.18
	WorldState.restore(clean)
	FloraLife.load_state()
	Story.load_state()
	_check(Story.cycle_count("dry_spell") == 0, "hermetic slate (no cycles)")
	# Drought: the REAL hourly flora path mints the flag with hysteresis.
	var day_before := int(WorldState.get_value("time.day", 0))
	GameClock.advance_hours(2.0)
	_check(WorldState.has_flag("flora.parched"),
		"FloraLife mints flora.parched from real vitality")
	_check(Story.cycle_count("dry_spell") == 1, "the errand opens off the real mirror")
	_check(Story.reached("dry_spell", "open"), "open latched")
	_check(not Story.reached("dry_spell", "rains"), "rains waits for the weather")
	# The Story Debugger's live frontier (gap #2b): while open is the frontier
	# and flora.parched still holds, the journal verb reports the watching
	# condition as a W row keyed on flora.parched, its LIVE value true, NOT
	# passing yet — the exact wire the desk renders a value-crossing-threshold
	# from. (parched is true here, so not_flag flora.parched fails → pass 0.)
	var watching := StrataLink._execute("journal")
	_check("W|open|" in watching and "flora.parched" in watching,
		"journal reports open's watching condition on flora.parched (got %s)"
			% watching.substr(0, 200))
	_check("|0|flora.parched|true" in watching,
		"the frontier watch shows the LIVE value (true) NOT passing yet (got %s)"
			% watching.substr(0, 240))
	var prefix: String = Story._latch_prefix(Story.quests["dry_spell"])
	var latch: Variant = WorldState.get_value(prefix + "open")
	_check(latch is Dictionary and String((latch as Dictionary).get("prose", ""))
			.begins_with("The valley is parched"),
		"the memoir prose is sealed IN the latch")
	var latch_day := int((latch as Dictionary).get("day", -1))
	_check(latch_day >= day_before and latch_day <= int(WorldState.get_value("time.day", 0)),
		"the latch is sealed with the day it happened")
	# Rain: force storm fronts (the dev door) and let the sim LIVE the
	# days through advance_hours — vitality climbs, hysteresis clears the
	# flag, the objective and the terminal latch during catch-up.
	var healed := false
	for i in 20:
		Weather.force_kind("storm")
		GameClock.advance_hours(24.0)
		if not WorldState.has_flag("flora.parched"):
			healed = true
			break
	_check(healed, "twenty storm days green the valley (vitality %.2f)" % FloraLife.vitality)
	_check(Story.objective_done("dry_spell", "open", "wait"), "the wait objective latched")
	_check(Story.reached("dry_spell", "rains"), "rains latched through real catch-up")
	_check(Story.resolved("dry_spell"), "the errand resolved")
	_check(Story.reached_day("dry_spell", "rains") >= Story.reached_day("dry_spell", "open"),
		"the memoir's days run forward")
	# The J screen: both entries render from the latch prose, under
	# Remembered (resolved cycles fade there).
	Story._journal_ui.refresh()
	var page: String = Story._journal_ui._text.text
	_check("The Dry Spell" in page, "the journal names the thread")
	_check("The valley is parched" in page, "entry one reads in the journal")
	_check("It rained" in page, "entry two reads in the journal")
	_check("Remembered" in page, "a resolved errand rests under Remembered")
	# Resolved: the frontier is empty, so the debugger's watch rows are gone —
	# there is nothing left to wait on (a remembered quest shows history only).
	var after := StrataLink._execute("journal")
	_check(not ("W|open|" in after) and not ("W|rains|" in after),
		"a resolved quest emits NO watching-condition rows (frontier empty)")


## The playtest desk (CREATION_KIT_REVIEW_V2 gap #2): named save-v2 anchors,
## the journal verb, and scrub's honest semantics — restore is EXACT (no
## wall-clock replay), scrub-forward advances the live sim, scrub-back
## RESTORES the nearest anchor at/before the target then advances forward
## (never un-latching in place), and the reply names the anchor it used.
## Driven through the REAL SaveGame + StrataLink._execute, headless.
func _test_playtest_anchors() -> void:
	# Guards: the live clock, the whole WorldState, and any pre-existing
	# anchor slots — this test leaves no trace.
	var clock_day := GameClock.day
	var clock_hours := GameClock.hours
	var ws_guard := WorldState.snapshot()
	var pre_anchors: Dictionary = {}
	var adir := DirAccess.open(SaveGame.ANCHORS_DIR)
	if adir != null:
		for f in adir.get_files():
			pre_anchors[f] = true
	# A disposable player (the threshold test's shape): snapshot_data needs
	# one in the world to anchor to.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(512.0, 0.0, -512.0)

	# --- round trip: an anchor restores the EXACT frozen moment ---
	GameClock.day = 3
	GameClock.hours = 8.0
	WorldState.set_value("test.anchor.mark", "A")
	WorldState.set_value("journal.test_anchor.open", {"day": 3, "prose": "sealed"})
	var saved := SaveGame.save_anchor("Moment A!")
	_check(bool(saved.get("ok", false)), "save_anchor lands (%s)" % saved)
	_check(String(saved.get("name", "")) == "moment-a",
		"the slot name is sanitised (got '%s')" % saved.get("name", ""))
	_check(int(saved.get("day", -1)) == 3, "the anchor stamps its day")
	# The slot is a real file in the game's save dir (session state, not data/).
	_check(FileAccess.file_exists(SaveGame.ANCHORS_DIR.path_join("moment-a.json")),
		"the anchor is a file in the save dir")

	# Move on: change the mark, latch another journal key, walk the clock.
	WorldState.set_value("test.anchor.mark", "B")
	WorldState.set_value("journal.test_anchor.rains", {"day": 5, "prose": "later"})
	GameClock.day = 5
	GameClock.hours = 20.0

	var restored := SaveGame.restore_anchor("moment-a")
	_check(bool(restored.get("ok", false)), "restore_anchor lands (%s)" % restored)
	_check(GameClock.day == 3 and absf(GameClock.hours - 8.0) < 0.01,
		"restore returns the exact clock (day %d, %.2fh)" % [GameClock.day, GameClock.hours])
	_check(WorldState.get_value("test.anchor.mark") == "A",
		"restore reloads the earlier WorldState wholesale (mark back to A)")
	_check(not (WorldState.get_value("journal.test_anchor.rains") is Dictionary),
		"the later latch is gone — restore reloaded a world where it hadn't happened")
	_check(WorldState.get_value("journal.test_anchor.open") is Dictionary,
		"the anchor's own latch survives the round trip")

	# --- scrub forward: advances the LIVE sim, restores nothing ---
	var here := float(GameClock.day) * 24.0 + GameClock.hours  # day3/8h = 80h
	var fwd := StrataLink._execute("scrub %.2f" % (here + 12.0))  # -> day3/20h
	_check(fwd.begins_with("ok scrub from=live"),
		"scrub forward rides the live sim, no restore (got %s)" % fwd)
	_check(absf((float(GameClock.day) * 24.0 + GameClock.hours) - (here + 12.0)) < 0.05,
		"scrub forward lands on the target hour")

	# --- scrub back: RESTORES the nearest anchor at/before target, names it ---
	# We are at day3/20h; the anchor sits at day3/8h. Target day3/9h is BEFORE
	# now, so scrub must restore moment-a then advance one hour forward.
	var back := StrataLink._execute("scrub %.2f" % (72.0 + 9.0))  # day3/9h = 81h
	_check(back.begins_with("ok scrub"), "scrub back answers ok (got %s)" % back)
	_check("restored=moment-a" in back,
		"scrub back NAMES the anchor it restored from (honesty — got %s)" % back)
	_check(GameClock.day == 3 and absf(GameClock.hours - 9.0) < 0.05,
		"scrub back = restore@8h + advance 1h -> day3/9h (got day%d/%.2fh)"
			% [GameClock.day, GameClock.hours])
	_check(WorldState.get_value("test.anchor.mark") == "A",
		"scrub back reloaded the anchor's world (mark is A again)")

	# --- scrub back with no anchor before the target errs honestly ---
	var none := StrataLink._execute("scrub -50")
	_check(none.begins_with("err scrub no anchor"),
		"scrub before the earliest anchor errs honestly (got %s)" % none)

	# --- the anchors rail + journal verb answer as data ---
	var rail := StrataLink._execute("anchors")
	_check(rail.begins_with("ok anchors count=") and "moment-a" in rail,
		"anchors lists the slot with its moment (got %s)" % rail)
	var jr := StrataLink._execute("journal")
	_check(jr.begins_with("ok journal active=") and "remembered=" in jr,
		"journal answers as parseable data (got %s)" % jr.substr(0, 60))

	# --- monotone: a bare restore never ADVANCES the clock (no trap arm) ---
	# restore_anchor must not call advance_hours — it reloads, it doesn't
	# replay. (The determinism gate proves the fork's trap stays silent.)
	WorldState.set_value("journal.test_anchor.rains", {"day": 9, "prose": "future"})
	GameClock.day = 9
	var r2 := SaveGame.restore_anchor("moment-a")
	_check(bool(r2.get("ok", false)) and GameClock.day == 3,
		"a second restore snaps straight back to the anchor's day (no replay)")

	# Leave no trace: remove anchor slots we minted, restore clock + WorldState.
	var adir2 := DirAccess.open(SaveGame.ANCHORS_DIR)
	if adir2 != null:
		for f in adir2.get_files():
			if not pre_anchors.has(f):
				DirAccess.remove_absolute(
					ProjectSettings.globalize_path(SaveGame.ANCHORS_DIR.path_join(f)))
	player.remove_from_group("player")
	player.queue_free()
	WorldState.restore(ws_guard)
	GameClock.day = clock_day
	GameClock.hours = clock_hours


## The save covenant ladder (PLAN_SHIP §1.7 / S4 groundwork, save_migration.gd):
## an OLDER save migrates up to the format this build reads; a save from a
## NEWER build refuses honestly (never a crash, never a silent reset); a
## versionless/foreign file refuses. Pure — SaveMigration is static, no
## autoloads touched. Also drives every fixture in tests/fixtures/saves/
## through the ladder (the "fixture saves per release" phase, wired into
## test.sh): each release archives a real save; every later build must still
## place it on the ladder.
func _test_save_migration() -> void:
	# --- an old (v1, pre-interiors) save ladders up to the current format ---
	var v1 := {
		"version": 1, "hours": 8.0, "day": 3, "wall_time": 1700000000,
		"player": {"x": 12.0, "z": -34.0}, "state": {}, "wear": {},
	}
	var up := SaveMigration.migrate(v1)
	_check(bool(up.get("ok", false)), "v1 save migrates (%s)" % up.get("error", ""))
	_check(int(up.data.version) == SaveMigration.CURRENT,
		"the ladder lifts v1 to the current format (v%d)" % int(up.data.version))
	_check(up.data.has("cells") and up.data.cells is Dictionary,
		"v1→v2 fills the `cells` default the old save predates")
	_check(up.data.get("civil", null) == false,
		"v1→v2 defaults `civil` false so apply_snapshot re-anchors the clock")
	# the original fields survive the reshape untouched
	_check(int(up.data.day) == 3 and absf(float(up.data.hours) - 8.0) < 0.001
		and float(up.data.player.x) == 12.0,
		"the ladder carries the old save's own fields through unchanged")
	# the migration does not mutate its input dict (works on a copy)
	_check(int(v1.version) == 1, "migrate leaves the caller's dict at v1 (copy, not mutate)")

	# --- a current (v2) save is a pass-through, byte-shaped the same ---
	var v2 := {
		"version": 2, "hours": 1.0, "day": 1, "civil": true,
		"player": {"x": 0.0, "z": 0.0}, "state": {}, "wear": {}, "cells": {},
	}
	var same := SaveMigration.migrate(v2)
	_check(bool(same.get("ok", false)) and int(same.data.version) == 2,
		"a v2 save passes through the ladder unchanged")

	# --- a save from a NEWER build refuses honestly (the covenant's core) ---
	var future := {"version": SaveMigration.CURRENT + 1, "player": {"x": 0.0, "z": 0.0}}
	var refused := SaveMigration.migrate(future)
	_check(not bool(refused.get("ok", true)), "a newer-format save does not load")
	_check(bool(refused.get("refused_newer", false)),
		"a newer-format save is flagged refused_newer (the player can be told)")
	_check("newer version" in String(refused.get("error", "")),
		"the refusal names the honest sentence (got '%s')" % refused.get("error", ""))
	_check(refused.data.is_empty(),
		"a refused save yields no data — never a partial, half-migrated world")

	# --- a versionless / foreign file refuses rather than guess ---
	var bare := SaveMigration.migrate({"hello": "world"})
	_check(not bool(bare.get("ok", true)) and not bool(bare.get("refused_newer", false)),
		"a versionless dict refuses (not misread as v1), and it is not 'newer'")
	var not_dict := SaveMigration.migrate("just a string")
	_check(not bool(not_dict.get("ok", true)), "a non-dict payload refuses")

	# --- every release fixture still places on the ladder (the test.sh phase) ---
	var fixtures_dir := "res://tests/fixtures/saves"
	var fdir := DirAccess.open(fixtures_dir)
	if fdir == null:
		_check(false, "the save-fixtures dir exists (tests/fixtures/saves)")
	else:
		var seen := 0
		for fname in fdir.get_files():
			if not fname.ends_with(".json"):
				continue
			seen += 1
			var raw: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(fixtures_dir.path_join(fname)))
			var r := SaveMigration.migrate(raw)
			_check(bool(r.get("ok", false)),
				"fixture %s ladders to the current format (%s)" % [fname, r.get("error", "")])
			_check(int(r.data.get("version", -1)) == SaveMigration.CURRENT,
				"fixture %s arrives at v%d" % [fname, SaveMigration.CURRENT])
		_check(seen >= 1, "at least one release save fixture is on record")


## The state verb (DESIGN_QUESTS B12): the desk's mirror-law forcing
## door — one WorldState key per command, JSON-typed, latches riding
## `changed` exactly like a sim write. Bad args err with contract lines.
func _test_state_verb(peer: StreamPeerTCP) -> void:
	var replies := await _link_send(peer, [
		"state set test.link.flag true",   # 0: JSON bool
		"state set test.link.num 0.5",     # 1: JSON number
		"state set test.link.word storm",  # 2: bare word -> String
		"state",                           # 3: bare verb errs
		"state get test.link.flag",        # 4: only set is spoken
		"state set test.link.flag",        # 5: missing value errs
	])
	_check(replies.size() == 6, "state replies land (got %d)" % replies.size())
	if replies.size() == 6:
		_check(replies[0] == "ok state test.link.flag=true", "state set parses JSON bools")
		_check(WorldState.get_value("test.link.flag") == true, "the bool landed typed")
		_check(replies[1] == "ok state test.link.num=0.5", "state set parses numbers")
		_check(is_equal_approx(float(WorldState.get_value("test.link.num")), 0.5),
			"the number landed typed")
		_check(replies[2] == "ok state test.link.word=\"storm\"", "a bare word lands as a String")
		_check(WorldState.get_value("test.link.word") == "storm", "the string landed")
		for i in [3, 4, 5]:
			_check(replies[i] == "err state needs set <key> <value>",
				"state arg %d errs with the contract line" % i)
	# The forcing door drives the REAL latch path: a quest hears the key.
	WorldState.set_value("test.link.flag", null)
	WorldState.set_value("test.link.num", null)
	WorldState.set_value("test.link.word", null)


## The Contour VM host (game/sim/contour.gd, PLAN_ENGINE §3 E2). Two halves:
##   available → a Contour call answers bit-identical to its GDScript twin
##               (ToolkitSnap), in-game, over scalar AND composite (basis/dict)
##               results — the native Lattice VM running in THIS process.
##   absent    → an honest NO-OP: a Contour that never compiled (or a missing
##               module, or a build with no dylib) returns false/null and never
##               crashes, so every consumer keeps its GDScript path.
## SKIP-when-absent (the framework file rides every game): off macOS / without
## the built dylib, only the no-op contract is asserted.
func _test_contour() -> void:
	# --- the honest no-op contract, ALWAYS asserted (dylib present or not) ----
	# A fresh host with no module compiled: not ready, calls return null, no crash.
	var cold := Contour.new()
	_check(not cold.is_ready(), "contour: a host with no module is not ready")
	_check(cold.call_fn("cycle_grid_step", [3.0, 1]) == null,
		"contour: call_fn on an uncompiled host is null (honest no-op)")
	# A missing module is a diagnostic, not a crash (content-empty-safe).
	var miss := Contour.new()
	var miss_err := miss.compile_file("res://tests/contour/does_not_exist.ct")
	_check(miss_err != "" and not miss.is_ready(),
		"contour: a missing module yields a diagnostic, host stays un-ready")

	# --- the available path: bit-identity to the GDScript twin, in-game -------
	if not Contour.available():
		print("  contour: SKIP available-path (no native kernel — GDScript twin only)")
		return
	var vm := Contour.new()
	var err := vm.compile_file("res://tests/contour/toolkit_snap.ct")
	_check(err == "", "contour: toolkit_snap.ct compiles (%s)" % err)
	if err != "":
		return
	_check(vm.is_ready(), "contour: the VM is ready after compile")

	# The GDScript twin, loaded as a script object so its static functions can
	# be invoked by name (callv is an Object method — the class ref can't carry
	# it; the same shape the native-spike probe used).
	var twin_gd: GDScript = load("res://game/dev/toolkit_snap.gd")
	_check(twin_gd != null, "contour: the GDScript twin loads")
	if twin_gd == null:
		return

	# Every call the twin answers, the VM answers BIT-IDENTICALLY. `==` on the
	# result Variants is an exact IEEE compare (same value, not approx) — scalar,
	# vector, BASIS (composite result), and DICT (composite result) all covered.
	var cases := [
		["cycle_grid_step", [3.0, 1]],                                  # scalar -> scalar
		["cycle_grid_step", [16.0, 1]],                                 # ladder wrap
		["snap_to_grid",    [Vector3(13.0, 7.5, -6.0), 4.0]],           # vec3 -> vec3
		["ground_normal",   [0.0, 1.0, 0.0, 1.0]],                      # 4 floats -> vec3
		["aligned_basis",   [Vector3(0.2, 0.9, 0.3), 0.7]],            # -> BASIS (LAT_BUF)
		["socket_world",    [Vector3(10.0, 0.0, 10.0), PI / 2.0, 1.0,
							  Vector3(2.0, 0.0, 0.0), 0.0]],             # -> DICT (LAT_BUF)
	]
	for c in cases:
		var fn: String = c[0]
		var args: Array = c[1]
		var twin: Variant = twin_gd.callv(fn, args)
		var got: Variant = vm.call_fn(fn, args)
		_check(_contour_eq(got, twin),
			"contour: %s bit-identical to ToolkitSnap.%s (twin=%s got=%s)" % [fn, fn, twin, got])
	print("  contour: %d calls (scalar/vec/basis/dict) bit-identical to the GDScript twin — native VM in-process" % cases.size())

	# --- the LAT_STR rung: a bare top-level string result crosses DIRECT ------
	# (Before this increment a `-> string` result was the documented LAT_ERR —
	# "result kind 'string' not marshalable" — and string-returning ports rode
	# wrap-in-array _abi adapters, unwrapped [0] valley-side. Retired.)
	var svm := Contour.new()
	var serr := svm.compile("sim func subst(text, subst) -> string:\n\tif subst.has(\"who\"):\n\t\treturn text + subst[\"who\"]\n\treturn text\n")
	_check(serr == "", "contour: string-result module compiles (%s)" % serr)
	if serr == "":
		var s: Variant = svm.call_fn("subst", ["hello ", {"who": "valley"}])
		_check(s is String and s == "hello valley",
			"contour: a bare string result crosses the ABI directly (LAT_STR), got %s" % [s])
		var empty: Variant = svm.call_fn("subst", ["", {}])
		_check(empty is String and empty == "",
			"contour: an empty string result round-trips (buflen 0)")
		var uni: Variant = svm.call_fn("subst", ["héllo ☂ ", {"who": "çà"}])
		_check(uni is String and uni == "héllo ☂ çà",
			"contour: a multi-byte UTF-8 string result crosses byte-exact")


# Exact structural equality for a Contour result vs its GDScript twin. `==` on
# floats/vectors is a bit compare; dicts compare key-by-key so a Variant `==`
# quirk on nested Dictionaries can't hide a mismatch.
func _contour_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _contour_eq(a[k], b[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _contour_eq(a[i], b[i]):
				return false
		return true
	return a == b


## The FIRST Contour system under the sim (PLAN_ENGINE E2): the Campfire's four
## pure leaf statics (Conditions.latch_day/_truthy/_loose_eq/_one_of) routed
## through the native Lattice VM behind STRATA_CONTOUR=1. Two halves:
##   (1) parity — the VM answers game/state/conditions.ct bit-identically to the
##       certified spec (the datum Plumb corpus values), in-game. SKIP if the
##       native kernel is absent (framework file rides every game / platform).
##   (2) wiring — Conditions.contour_status() reflects the boot flag, and when
##       ENGAGED (STRATA_CONTOUR=1 + kernel) a real Conditions.eval() drives the
##       VM (the answered-call counter climbs) — PROOF the sim path routed, not a
##       silent GDScript fallback. Flag OFF: the counter stays 0 (byte-identical
##       twin). This half runs on every configuration; test.sh runs it BOTH ways.
func _test_conditions_contour() -> void:
	# --- (2) wiring: contour_status reflects the flag, on every config ---------
	var st: Dictionary = Conditions.contour_status()
	if bool(st.engaged):
		var before: int = int(Conditions.contour_status().calls)
		WorldState.set_value("test.contour.route", true)
		# An eval touching three leaves: flag -> _truthy, eq -> _loose_eq,
		# season -> _one_of. Each answered by the VM increments the counter.
		Conditions.eval({"flag": "test.contour.route"})
		Conditions.eval({"eq": ["test.contour.route", true]})
		Conditions.eval({"season": "summer"})
		var after: int = int(Conditions.contour_status().calls)
		_check(after > before,
			"conditions: STRATA_CONTOUR=1 routes Conditions.eval through the Contour VM (calls %d->%d, no silent fallback)" % [before, after])
		WorldState.set_value("test.contour.route", null)
		print("  conditions: routing ENGAGED — the sim's leaf helpers answered by the Lattice VM (%d calls)" % after)

		# keys_of/custom_names (docs/PORT_LEDGER.md D3b's recorded follow-up,
		# routed G2): the VM answers these two too now — counter climbs again,
		# and a spot-check against known-correct output (the same nested
		# all/any/custom composition D3b's corpus certified) catches a
		# marshalling or VM regression loud, not silently.
		var before2: int = int(Conditions.contour_status().calls)
		var kc := {"all": [{"custom": ["h1"], "watch": ["x"]},
			{"any": [{"custom": ["h2"], "watch": ["y", "z"]}]}]}
		_check(Conditions.keys_of(kc) == ["x", "y", "z"],
			"conditions: routed keys_of matches the certified nested all/any/custom composition")
		_check(Conditions.custom_names(kc) == ["h1", "h2"],
			"conditions: routed custom_names matches the certified nested composition")
		var after2: int = int(Conditions.contour_status().calls)
		_check(after2 > before2,
			"conditions: STRATA_CONTOUR=1 routes keys_of/custom_names through the Contour VM (calls %d->%d, no silent fallback)" % [before2, after2])
	else:
		# Flag off (mode 1) or refused (mode -1) — never a silent VM route.
		_check(int(st.mode) == 1 or int(st.mode) == -1,
			"conditions: unresolved-safe routing mode (%d)" % int(st.mode))
		var before: int = int(st.calls)
		Conditions.eval({"flag": "test.contour.route2"})
		_check(int(Conditions.contour_status().calls) == before,
			"conditions: flag-off Conditions.eval stays on the GDScript twin (no silent routing)")
		print("  conditions: routing OFF (mode %d) — GDScript twin, byte-identical" % int(st.mode))

	# --- (1) parity: the VM answers conditions.ct bit-identical to the spec ----
	if not Contour.available():
		print("  conditions: SKIP VM-parity (no native kernel — GDScript twin only)")
		return
	var vm := Contour.new()
	var err := vm.compile_file("res://game/state/conditions.ct")
	_check(err == "", "conditions: conditions.ct compiles (%s)" % err)
	if err != "":
		return
	# The certified corpus values (datum plumb/corpus/conditions_*.jsonl), asserted
	# in-game against the native VM. `==` is an exact compare; a divergence here is
	# a marshalling or VM regression, loud.
	var latch := [
		[[{"day": 5}], 5], [[{"day": 3.0}], 3], [[{"day": 0}], 0],
		[[{"season": "summer"}], -1], [[{}], -1],
		[[7], 7], [[0], 0], [[4.9], 4], [[-2.5], -2],
		["x", -1], [[true], -1], [[null], -1],
	]
	for c in latch:
		var got: Variant = vm.call_fn("latch_day", c[0] if c[0] is Array else [c[0]])
		_check(got == c[1], "conditions.ct latch_day(%s) == %s (got %s)" % [c[0], c[1], got])
	var truthy := [
		[null, false], [false, false], [true, true], [0, true], [5, true],
		[1.5, true], [0.0, true], ["hi", true], ["", true], [{"day": 2}, true], [{}, true],
	]
	for c in truthy:
		_check(vm.call_fn("_truthy", [c[0]]) == c[1],
			"conditions.ct _truthy(%s) == %s" % [c[0], c[1]])
	var eqs := [
		[[1, 1.0], true], [[2, 3], false], [[5, 5], true],
		[[1.0, 1.000001], true], [[1.0, 1.1], false],
		[["a", "a"], true], [["a", "b"], false], [["1", 1], false],
	]
	for c in eqs:
		_check(vm.call_fn("_loose_eq", c[0]) == c[1],
			"conditions.ct _loose_eq(%s) == %s" % [c[0], c[1]])
	var ones := [
		[["summer", ["summer", "winter"]], true],
		[["spring", ["summer", "winter"]], false],
		[["storm", []], false], [["storm", "storm"], true], [["storm", "rain"], false],
	]
	for c in ones:
		_check(vm.call_fn("_one_of", c[0]) == c[1],
			"conditions.ct _one_of(%s) == %s" % [c[0], c[1]])
	print("  conditions: %d spec cases bit-identical to conditions.ct via the native Lattice VM" % (latch.size() + truthy.size() + eqs.size() + ones.size()))


## THE SYSTEMS BRIDGE (game/sim/contour_bridge.gd, Mission C0): a Contour §7
## timed `system` ticking IN-GAME against WorldState, one clock step per call.
## Three proofs (all SKIP without the native kernel — the framework file rides
## every game / platform):
##   (1) PARITY — the toy `Fade` system's probe.level trajectory over 4 ticks is
##       BIT-IDENTICAL (LE IEEE-754 hex) to lattice-cli's own tick of the same
##       module + seed + dt (the datum EmbedTickTests reference), so an in-game
##       tick == a lattice-cli tick.
##   (2) REPLAY LAW — snapshot WorldState mid-`over`, restore into a FRESH world,
##       and tick to completion: byte-identical to the un-snapshotted run. The
##       continuation (Fade.__time) + clock (time.elapsed) ride WorldState, so
##       they survive SaveGame snapshot/restore.
##   (3) DECLARED-ACCESS-ONLY — the bridge seeds only declared reads and applies
##       only declared writes; an undeclared write is refused by the language at
##       compile, and a reserved write (time.*/*.__time) is refused by the bridge.
func _test_contour_bridge() -> void:
	if not ContourBridge.available():
		print("  contour_bridge: SKIP (no native kernel — GDScript twin only)")
		return

	var WS := load("res://game/state/world_state.gd")
	# The lattice-cli reference trajectory for Fade over probe (start 0, target
	# 100, over 3.0s, dt 1.0): t = 1/3, 2/3, 1.0 (pinned), then done → holds. From
	# `lattice-cli run probe_cli.ct trajectory` (datum EmbedTickTests pins the same).
	var ref_hex := ["aaaaaaaaaaaa4040", "aaaaaaaaaaaa5040", "0000000000005940", "0000000000005940"]

	# --- (1) parity: the probe trajectory bit-matches lattice-cli ---------------
	var ws1 = WS.new()
	ws1.set_value("probe.start", 0.0)
	ws1.set_value("probe.target", 100.0)
	var b1 := ContourBridge.new(ws1)
	var err := b1.compile_file("res://tests/contour/probe_time.ct")
	_check(err == "", "contour_bridge: probe_time.ct compiles (%s)" % err)
	if err != "":
		ws1.free()
		return
	var reads := Array(b1.declared_reads()); reads.sort()
	var writes := Array(b1.declared_writes())
	_check(reads == ["probe.start", "probe.target"], "contour_bridge: declared reads = %s" % [reads])
	_check(writes == ["probe.level"], "contour_bridge: declared writes = %s" % [writes])
	var got_hex := []
	for i in 4:
		_check(b1.tick(1.0), "contour_bridge: tick %d applied" % i)
		got_hex.append(_f64_hex(ws1.get_value("probe.level")))
	_check(got_hex == ref_hex,
		"contour_bridge: probe.level trajectory bit-identical to lattice-cli (%s vs %s)" % [got_hex, ref_hex])
	_check(ws1.get_value("Fade.__time") != null, "contour_bridge: Fade.__time continuation rode into WorldState")
	_check(ws1.get_value("time.elapsed") != null, "contour_bridge: time.elapsed rode into WorldState")

	# --- (2) replay law: snapshot mid-over, restore FRESH, complete -------------
	var ws2 = WS.new()
	ws2.set_value("probe.start", 0.0)
	ws2.set_value("probe.target", 100.0)
	var b2 := ContourBridge.new(ws2)
	b2.compile_file("res://tests/contour/probe_time.ct")
	b2.tick(1.0); b2.tick(1.0)                       # two ticks → mid-`over`
	var cont: Dictionary = ws2.get_value("Fade.__time")
	_check(int(cont.get("phase", -1)) == 0 and not bool(cont.get("done", true)),
		"contour_bridge: mid-over after 2 ticks (phase=%s done=%s)" % [cont.get("phase"), cont.get("done")])
	var snap: Dictionary = ws2.snapshot()            # the SaveGame snapshot shape
	var a_hex := []
	b2.tick(1.0); a_hex.append(_f64_hex(ws2.get_value("probe.level")))
	b2.tick(1.0); a_hex.append(_f64_hex(ws2.get_value("probe.level")))
	# restore the mid-over snapshot into a FRESH world + bridge, then complete
	var ws3 = WS.new()
	ws3.restore(snap)
	var b3 := ContourBridge.new(ws3)
	b3.compile_file("res://tests/contour/probe_time.ct")
	var b_hex := []
	b3.tick(1.0); b_hex.append(_f64_hex(ws3.get_value("probe.level")))
	b3.tick(1.0); b_hex.append(_f64_hex(ws3.get_value("probe.level")))
	_check(a_hex == b_hex,
		"contour_bridge: restore-then-replay bit-identical (%s vs %s)" % [a_hex, b_hex])
	_check(b_hex.size() == 2 and b_hex[1] == "0000000000005940",
		"contour_bridge: restored run completes at probe.target (100.0)")

	# --- (3) declared-access refusals: undeclared (compiler) + reserved (bridge)
	var sneak := "system Sneak:\n\treads: probe.start\n\twrites: probe.level\n\tsim func step():\n\t\tprobe.level = probe.start\n\t\tprobe.secret = 1.0\n"
	var ws4 = WS.new()
	var b4 := ContourBridge.new(ws4)
	var sneak_err := b4.compile(sneak)
	_check(sneak_err != "" and sneak_err.contains("probe.secret"),
		"contour_bridge: undeclared write refused loudly (%s)" % sneak_err)
	_check(not b4.is_ready(), "contour_bridge: a refused module leaves the bridge un-ready")
	var reserved := "system Clock:\n\treads: probe.start\n\twrites: time.elapsed\n\tsim func step():\n\t\ttime.elapsed = probe.start\n"
	var ws5 = WS.new()
	var b5 := ContourBridge.new(ws5)
	var reserved_err := b5.compile(reserved)
	_check(reserved_err != "" and reserved_err.contains("reserved"),
		"contour_bridge: reserved write (time.elapsed) refused by the bridge (%s)" % reserved_err)

	for n in [ws1, ws2, ws3, ws4, ws5]:
		n.free()
	print("  contour_bridge: probe ticks bit-identical to lattice-cli, continuations survive save/restore, declared-access-only enforced")


## THE FIRST SYSTEM FILE (game/world/flora_life.ct, Mission C1): flora's hourly
## vitality ease as a Contour §6 `Flora` system, wired behind STRATA_CONTOUR
## through the systems bridge. Two proofs (both SKIP without the native kernel):
##   (1) PARITY — the Flora system's flora.vitality trajectory over 6 hourly
##       ticks is BIT-IDENTICAL (LE IEEE-754 hex) to the GDScript twin's own
##       easing (FloraLife.target_for + the snappedf(clampf(...)) step), computed
##       side by side in-game — so the .ct system == the .gd _hourly, byte-exact.
##   (2) WIRING — FloraLife.contour_status() reflects the boot flag, and when
##       engaged a real FloraLife._hourly drives the counter (the sim path routed
##       through the VM, not a silent GDScript fallback). This is the same routing
##       the soak exercises 720× inside its fingerprinted window.
func _test_flora_contour() -> void:
	# --- (2) wiring: contour_status reflects the flag, no silent fallback -------
	var st: Dictionary = FloraLife.contour_status()
	if bool(st.engaged):
		var before: int = int(FloraLife.contour_status().calls)
		var saved_v: float = FloraLife.vitality           # snapshot ALL live state
		var saved_vit: Variant = WorldState.get_value("flora.vitality")
		var saved_bloom: Variant = WorldState.get_value("flora.bloom")
		var saved_parched: Variant = WorldState.get_value("flora.parched")
		FloraLife._hourly(0)                              # one real hourly tick → routes
		var after: int = int(FloraLife.contour_status().calls)
		_check(after == before + 1,
			"flora: STRATA_CONTOUR=1 routes _hourly's ease through the Contour Flora system (calls %d->%d, no silent fallback)" % [before, after])
		FloraLife.vitality = saved_v                      # ... and restore it verbatim
		WorldState.set_value("flora.vitality", saved_vit)
		WorldState.set_value("flora.bloom", saved_bloom)
		WorldState.set_value("flora.parched", saved_parched)
		print("  flora: routing ENGAGED — the hourly vitality ease ticks the native Contour §6 system (%d ticks)" % after)
	else:
		_check(int(st.mode) == 1 or int(st.mode) == -1,
			"flora: unresolved-safe routing mode (%d)" % int(st.mode))
		print("  flora: routing OFF (mode %d) — GDScript twin, byte-identical" % int(st.mode))

	# --- (1) parity: the Flora system == the GDScript twin, hour by hour --------
	if not ContourBridge.available():
		print("  flora: SKIP system-parity (no native kernel — GDScript twin only)")
		return
	var WS := load("res://game/state/world_state.gd")
	var ws = WS.new()
	ws.set_value("flora.vitality", 0.7)
	var b := ContourBridge.new(ws)
	var err := b.compile_file("res://game/world/flora_life.ct")
	_check(err == "", "flora: flora_life.ct compiles (%s)" % err)
	if err != "":
		ws.free()
		return
	# The RMW resource shows up in BOTH declared reads and declared writes.
	var reads := Array(b.declared_reads()); reads.sort()
	var writes := Array(b.declared_writes())
	_check(reads == ["flora.env", "flora.vitality"], "flora: declared reads = %s" % [reads])
	_check(writes == ["flora.vitality"], "flora: declared writes (RMW) = %s" % [writes])
	# Six hours of the SAME environment; compare the system's flora.vitality to
	# the twin's easing computed alongside it (target_for is the certified leaf).
	var env := {"season": "spring", "moist": 0.5, "temp": 20.0}
	var tgt: float = FloraLife.target_for(env.season, env.moist, env.temp)
	var twin := 0.7
	var got := []
	var exp := []
	for i in 6:
		_check(b.tick_seeded({"flora.env": env}, 3600.0), "flora: system tick %d applied" % i)
		twin = snappedf(clampf(twin + (tgt - twin) * 0.06, 0.0, 1.0), 0.001)  # EASE_PER_HOUR
		got.append(_f64_hex(ws.get_value("flora.vitality")))
		exp.append(_f64_hex(twin))
	_check(got == exp,
		"flora: 6-hour vitality trajectory bit-identical to the GDScript twin (%s vs %s)" % [got, exp])
	# It eased UP toward the wet-spring target and never overshot — a live tick.
	_check(float(ws.get_value("flora.vitality")) > 0.7 and float(ws.get_value("flora.vitality")) < tgt,
		"flora: vitality eased toward target_for(spring,0.5,20)=%.4f" % tgt)
	ws.free()
	print("  flora: 6 hourly ticks of flora_life.ct bit-identical to the GDScript twin via the systems bridge")


## LE IEEE-754 hex of a float — the appendix's exact bit-level wire (the Godot
## side of Plumb's diff), so a comparison here is byte-exact, not approximate.
func _f64_hex(v: Variant) -> String:
	return PackedFloat64Array([float(v)]).to_byte_array().hex_encode()


## The P1 RULES TRIO (Mission D1b): items / skills / budget route their RULES
## through Contour behind STRATA_CONTOUR. Each test (1) proves the live autoload's
## routing reflects the flag with NO SILENT FALLBACK — flag-ON engages and the
## engagement counter climbs, flag-OFF is byte-identical GDScript — and (2) proves
## the ported rules bit-identical to the GDScript twin via a local VM, whatever the
## live flag (like _test_flora_contour builds its own bridge).
func _test_items_contour() -> void:
	var st: Dictionary = Items.contour_status()
	if bool(st.engaged):
		var before: int = int(Items.contour_status().calls)
		var saved: Variant = WorldState.get_value("player.inventory")
		WorldState.set_value("player.inventory", {})
		Items.add("probe_apple", 3)                 # routes add
		var n: int = Items.count("probe_apple")     # routes count
		_check(n == 3, "items: routed add+count agree (got %d)" % n)
		var after: int = int(Items.contour_status().calls)
		_check(after >= before + 2,
			"items: STRATA_CONTOUR=1 routes the inventory rules through Contour (calls %d->%d, no silent fallback)" % [before, after])
		WorldState.set_value("player.inventory", saved)
		print("  items: routing ENGAGED — inventory rules tick the native Contour VM (%d calls)" % after)
	else:
		_check(int(st.mode) == 1 or int(st.mode) == -1,
			"items: unresolved-safe routing mode (%d)" % int(st.mode))
		print("  items: routing OFF (mode %d) — GDScript twin, byte-identical" % int(st.mode))

	if not Contour.available():
		print("  items: SKIP rule-parity (no native kernel)")
		return
	var vm := Contour.new()
	var err := vm.compile_file("res://game/items/items.ct")
	_check(err == "", "items: items.ct compiles (%s)" % err)
	if err != "":
		return
	var defs := {"apple": {"tags": ["food", "forage"]}, "berry": {"tags": ["food"]},
		"axe": {"tags": ["tool"]}}
	var inv := {"apple": 2, "berry": 3, "axe": 1}
	_check(int(vm.call_fn("count", [inv, "apple"])) == 2, "items: count == twin")
	_check(int(vm.call_fn("count", [inv, "ghost"])) == 0, "items: count(absent) == 0")
	_check(int(vm.call_fn("count_tag", [inv, defs, "food"])) == 5, "items: count_tag(food) == 5")
	_check(int(vm.call_fn("count_tag", [inv, defs, "tool"])) == 1, "items: count_tag(tool) == 1")
	# add's order-faithful, erase-free transform, bit-compared to the GDScript twin.
	for step: Array in [["apple", 3], ["axe", -1], ["coin", 5], ["apple", -20]]:
		var got: Variant = vm.call_fn("add", [inv, step[0], step[1]])
		var twin := inv.duplicate()
		twin[step[0]] = int(twin.get(step[0], 0)) + step[1]
		if twin[step[0]] <= 0:
			twin.erase(step[0])
		_check(JSON.stringify(got) == JSON.stringify(twin),
			"items: add(%s,%d) == twin (%s vs %s)" % [step[0], step[1], JSON.stringify(got), JSON.stringify(twin)])
	print("  items: count/count_tag/add bit-identical to the GDScript twin via Contour")


func _test_skills_contour() -> void:
	var def := {"id": "d1b_probe", "name": "Probe", "stat": "stat.d1b_scene",
		"thresholds": [10.0, 40.0, 80.0]}
	var st: Dictionary = Skills.contour_status()
	if bool(st.engaged):
		var before: int = int(Skills.contour_status().calls)
		var saved: Variant = WorldState.get_value("stat.d1b_scene")
		WorldState.set_value("stat.d1b_scene", 45.0)
		var lvl: int = Skills._level_for(def)      # routes _level_for
		var pr: float = Skills.progress(def)       # routes progress
		_check(lvl == 2, "skills: routed _level_for(45) == 2 (got %d)" % lvl)
		_check(is_equal_approx(pr, 0.125), "skills: routed progress(45) == 0.125 (got %f)" % pr)
		var after: int = int(Skills.contour_status().calls)
		_check(after >= before + 2,
			"skills: STRATA_CONTOUR=1 routes the progression rules through Contour (calls %d->%d, no silent fallback)" % [before, after])
		WorldState.set_value("stat.d1b_scene", saved)
		print("  skills: routing ENGAGED — progression rules tick the native Contour VM (%d calls)" % after)
	else:
		_check(int(st.mode) == 1 or int(st.mode) == -1,
			"skills: unresolved-safe routing mode (%d)" % int(st.mode))
		print("  skills: routing OFF (mode %d) — GDScript twin, byte-identical" % int(st.mode))

	if not Contour.available():
		print("  skills: SKIP rule-parity (no native kernel)")
		return
	var vm := Contour.new()
	var err := vm.compile_file("res://game/skills/skills.ct")
	_check(err == "", "skills: skills.ct compiles (%s)" % err)
	if err != "":
		return
	# Sweep the stat; the routed level + progress bit-identical to the twin.
	var got := []
	var exp := []
	for v in [0.0, 5.0, 25.0, 40.0, 79.0, 200.0]:
		var world := {def.stat: v}
		got.append("%d,%s" % [int(vm.call_fn("_level_for", [world, def])), _f64_hex(vm.call_fn("progress", [world, def]))])
		# the GDScript twin, computed alongside
		var tl := 0
		for t in def.thresholds:
			if v >= float(t):
				tl += 1
		var tp: float
		if tl >= def.thresholds.size():
			tp = 1.0
		else:
			var prev := 0.0 if tl == 0 else float(def.thresholds[tl - 1])
			tp = clampf((v - prev) / (float(def.thresholds[tl]) - prev), 0.0, 1.0)
		exp.append("%d,%s" % [tl, _f64_hex(tp)])
	_check(got == exp, "skills: level+progress sweep bit-identical to the twin (%s vs %s)" % [got, exp])
	print("  skills: _level_for/progress bit-identical to the GDScript twin via Contour")


func _test_budget_contour() -> void:
	var th := {"cell_placements": {"amber": 250, "red": 600},
		"agents": {"amber": 500, "red": 1200},
		"records": {"amber": 10000, "red": 40000}, "per_placement_ms": 0.02}
	var st: Dictionary = Budget.contour_status()
	if bool(st.engaged):
		var before: int = int(Budget.contour_status().calls)
		var saved: Dictionary = Budget.thresholds
		Budget.thresholds = th
		var g: int = Budget.grade(700, "agents")    # routes grade -> amber (1)
		_check(g == 1, "budget: routed grade(700,agents) == amber (got %d)" % g)
		var after: int = int(Budget.contour_status().calls)
		_check(after >= before + 1,
			"budget: STRATA_CONTOUR=1 routes the grade rule through Contour (calls %d->%d, no silent fallback)" % [before, after])
		Budget.thresholds = saved
		print("  budget: routing ENGAGED — the grade rule ticks the native Contour VM (%d calls)" % after)
	else:
		_check(int(st.mode) == 1 or int(st.mode) == -1,
			"budget: unresolved-safe routing mode (%d)" % int(st.mode))
		print("  budget: routing OFF (mode %d) — GDScript twin, byte-identical" % int(st.mode))

	if not Contour.available():
		print("  budget: SKIP rule-parity (no native kernel)")
		return
	var vm := Contour.new()
	var err := vm.compile_file("res://game/dev/budget.ct")
	_check(err == "", "budget: budget.ct compiles (%s)" % err)
	if err != "":
		return
	# grade over every axis + boundary, bit-compared to the twin (0 green/1/2).
	for axis in ["cell_placements", "agents", "records", "missing"]:
		for value in [0, 250, 400, 600, 900, 45000]:
			var got: int = int(vm.call_fn("grade", [th, value, axis]))
			var t: Dictionary = th.get(axis, {})
			var twin := 0
			if value >= int(t.get("red", 1 << 30)):
				twin = 2
			elif value >= int(t.get("amber", 1 << 30)):
				twin = 1
			_check(got == twin, "budget: grade(%d,%s) == twin (%d vs %d)" % [value, axis, got, twin])
	_check(int(vm.call_fn("worst_grade", [th, 100, 700, 50])) == 1, "budget: worst_grade amber")
	_check(int(vm.call_fn("worst_grade", [th, 10, 10, 50000])) == 2, "budget: worst_grade red")
	print("  budget: grade/worst_grade bit-identical to the GDScript twin via Contour")


## THE AGENT MIRROR IS JSON-SAFE (the 2026-07-11 windowed wedge): AgentMind's
## declared resources cross the WorldState mirror as JSON-compatible values —
## positions as {x,z} wire dicts, never Vector2s — because the whole store rides
## SaveGame's JSON round trip (world_state.gd's contract). A mirrored Vector2
## came back from the next boot's restore as a stringified "(x, y)"; set_value's
## then-untyped `==` early-out ERRORED on every typed rewrite, the write never
## landed, and every mind wedged at _advance_contour's read-back each tick.
## Proves, through a REAL engaged mind: (1) every agent.* mirror value
## JSON-round-trips type-stable, and (2) a poisoned pre-contract mirror HEALS on
## the next tick — zero SCRIPT ERRORs (test.sh's stderr grep co-signs).
func _test_agent_mirror_json_safe() -> void:
	if not ResourceLoader.exists("res://game/wildlife/wildlife_manager.gd"):
		print("  agent mirror: SKIP (content-empty game — no wildlife to raise a mind)")
		return
	if not bool(AgentSim.contour_status().get("engaged", false)):
		print("  agent mirror: SKIP (no native kernel — GDScript twin only)")
		return
	var mgr: Node = load("res://game/wildlife/wildlife_manager.gd").new()
	var herd: Dictionary = mgr.spawn_herd({
		"id": "mirror_herd", "count": 1.0,
		"home": {"x": 0.0, "z": 0.0}, "range": 50.0,
		"body_scene": "res://game/wildlife/hound_body.tscn",
		"activities": [
			{"id": "drink", "at": {"x": 30.0, "z": 0.0}, "satisfies": "thirst", "rate": 16.0},
			{"id": "prowl", "at": "roam", "satisfies": "wander", "rate": 5.0},
		]})
	var sim: AgentSim = herd.individuals[0].sim
	sim.advance(0.5)
	for k in ["agent.needs", "agent.pos", "agent.target", "agent.current",
			"agent.produced", "agent.rng", "agent.last_utilities"]:
		var v: Variant = WorldState.get_value(k)
		var rt: Variant = JSON.parse_string(JSON.stringify(v))
		var stable: bool = typeof(rt) == typeof(v) \
				or (typeof(v) == TYPE_INT and typeof(rt) == TYPE_FLOAT)  # JSON has no int
		_check(stable, "agent mirror '%s' JSON-round-trips type-stable (%s -> %s)"
			% [k, type_string(typeof(v)), type_string(typeof(rt))])
	_check(WorldState.get_value("agent.pos") is Dictionary,
		"agent.pos crosses as the {x,z} wire dict, not a Vector2")
	# A PRE-CONTRACT save's poisoned mirror (the stringified vector a JSON
	# reload produced) heals on the next engaged tick instead of wedging.
	WorldState.set_value("agent.pos", "(-198.6849, -439.4683)")
	WorldState.set_value("agent.target", "(-196.9978, -444.865)")
	sim.advance(0.5)
	_check(WorldState.get_value("agent.pos") is Dictionary,
		"a poisoned pos mirror heals to the wire dict on the next tick")
	_check(WorldState.get_value("agent.target") is Dictionary,
		"a poisoned target mirror heals too")
	_check(sim.pos.is_finite(), "the mind's pos stays live through the heal")
	mgr.free()
	print("  agent mirror: JSON-safe wire contract + poisoned-save heal proven on an engaged mind")
