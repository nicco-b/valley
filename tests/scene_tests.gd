extends Node
## Scene-context tests: anything that needs autoloads alive (Conditions,
## WorldState interplay). Run by test.sh: godot --headless scene_tests.tscn
## — exits 0/1.

var _failures := 0


func _ready() -> void:
	_test_conditions()
	_test_skills()
	_test_clock()
	_test_seasons()
	_test_climate()
	_test_climate_v2()
	_test_water()
	_test_swell()
	_test_shoaling()
	_test_hydrology()
	_test_strata_water()
	_test_water_field()
	_test_flora()
	_test_moon()
	_test_wildlife()
	_test_fabric_spring()
	_test_wear()
	_test_nav()
	_test_sand_sim()
	_test_fabric()
	_test_tile_override()
	_test_kernel_retile_race()
	_test_placement_reseat()
	_test_cell_records_armor()
	_test_import_frame_refusal()
	_test_biome_undo()
	await _test_toolkit_undo()
	_test_placement_edit()
	_test_overrides_emit()
	_test_edit_flush()
	await _test_threshold()
	_test_map()
	await _test_strata_link()
	if _failures > 0:
		print("SCENE-TESTS FAIL: %d failed" % _failures)
	else:
		print("SCENE-TESTS PASS")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
		print("  FAIL: ", name)


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
	await _test_reload_honesty(peer)
	await _test_preview_world(peer)
	await _test_preview_mesh(peer)
	await _test_camera_verb(peer)
	await _test_toolkit_verbs(peer)
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
			and replies[0].ends_with("hud=on"),
			"toolkit status reports the boot state (got %s)" % replies[0])
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
		_check(replies[11] == "err toolkit needs status|tool|brush|biome|place|keys",
			"unknown subverb errs with the contract line")
		# hud off is the batch's LAST state change: the darkness is
		# assertable here (hud on rides its own batch below).
		_check(replies[12] == "ok hud off" and not HUD.visible
			and not Toolkit._hud.visible, "hud off darkens both overlays")
		_check(replies[13] == "err hud needs on|off", "bad hud arg errs")
	var hreplies := await _link_send(peer, ["hud on"])
	_check(hreplies.size() == 1 and hreplies[0] == "ok hud on" and HUD.visible
		and Toolkit._hud.visible, "hud on relights both overlays")
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
	player.queue_free()


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
		_check(pre[2] == "err view_layer needs shaded|moisture|temperature|flow|slope|biome",
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
		_check(layers[2] == "err view_layer needs shaded|moisture|temperature|flow|slope|biome",
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


## The biome pen's Z (audit quick win 2): one pre-stroke memento, the
## exact sculpt pattern — paint a stroke, tap Z, and the index map
## returns bit-identical; the memento is one-deep and consumed.
func _test_biome_undo() -> void:
	if Terrain._biome_img == null:
		print("  biome undo: SKIP (no biome map on this checkout)")
		return
	var p := Vector2(1200.0, 1200.0)
	var before: int = Terrain.biome_at(p.x, p.y)
	var before_img: PackedByteArray = Terrain._biome_img.get_data()
	Toolkit._tool = Toolkit.Tool.BIOME
	Toolkit._biome_index = (before + 1) % Terrain.biomes.size()
	Toolkit._macro_radius = 120.0
	Toolkit._biome_paint_at(Vector3(p.x, 0.0, p.y))
	_check(Terrain.biome_at(p.x, p.y) == Toolkit._biome_index,
		"biome pen paints the picked index")
	_check(Toolkit._biome_undo != null, "stroke start takes the Z memento")
	_check(Toolkit._biome_unsaved, "a stroke marks the biome map unsaved")
	Toolkit._biome_stroke = false  # stroke released
	Toolkit._undo()
	_check(Terrain.biome_at(p.x, p.y) == before, "Z reverts the biome stroke")
	_check(Terrain._biome_img.get_data() == before_img,
		"undo returns a bit-identical index map")
	_check(Toolkit._biome_undo == null, "the memento is one-deep (consumed)")
	# A second Z has nothing left: a safe no-op, never a deletion.
	Toolkit._undo()
	_check(Terrain._biome_img.get_data() == before_img,
		"Z on an empty biome memento changes nothing")
	# Leave no pending flush: memory equals disk again after the revert.
	Toolkit._biome_unsaved = false
	Toolkit._biome_dirty = Rect2()
	Toolkit._tool = Toolkit.Tool.SCULPT
	Toolkit._biome_index = 4
	Toolkit._macro_radius = 160.0


## The Z dispatch (audit quick win 1, the footgun): every tool answers Z
## for ITSELF — Z in biome mode must never fall through to a placement
## delete, Z with an empty memento is a no-op, and PLACE keeps its LIFO
## remove. A real physics floor gives the cursor ray ground to hit, so
## the OLD fallthrough would genuinely have deleted the record.
func _test_toolkit_undo() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1  # world layer — what _ray_to_ground casts at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500.0, 1.0, 500.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(700.0, -0.5, 700.0)
	add_child(floor_body)
	Toolkit._enter()
	_check(Toolkit.active, "toolkit enters for the undo test")
	Toolkit._cam.global_position = Vector3(700.0, 40.0, 700.0)
	Toolkit._pitch = -1.55  # straight down at the floor
	Toolkit._yaw = 0.0
	# Applied directly too: _process may not run between physics frames.
	Toolkit._cam.rotation = Vector3(Toolkit._pitch, Toolkit._yaw, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Toolkit._cam.rotation = Vector3(Toolkit._pitch, Toolkit._yaw, 0.0)
	var hit: Vector3 = Toolkit._ray_to_ground()
	_check(hit != Vector3.INF, "cursor ray hits the test floor")
	if hit == Vector3.INF:
		Toolkit.active = false
		player.remove_from_group("player")
		player.queue_free()
		floor_body.queue_free()
		return
	var cell: Vector2i = CellRecords.cell_of(hit)
	var pre: int = CellRecords.records(cell).size()
	CellRecords.add(hit, "test_kit", 0.0, 1.0)
	_check(CellRecords.records(cell).size() == pre + 1, "test placement lands")
	# THE footgun: Z in biome mode with nothing painted. The old default
	# branch reached CellRecords.remove_last and deleted the placement.
	Toolkit._tool = Toolkit.Tool.BIOME
	Toolkit._biome_undo = null
	Toolkit._undo()
	_check(CellRecords.records(cell).size() == pre + 1,
		"Z in biome mode never deletes a placement")
	# Empty mementos elsewhere: safe no-ops too.
	Toolkit._tool = Toolkit.Tool.RIVER
	Toolkit._undo()
	Toolkit._tool = Toolkit.Tool.SCULPT
	Toolkit._sculpt_undo = null
	Toolkit._undo()
	Toolkit._tool = Toolkit.Tool.TERRAIN
	Toolkit._pen_undo = null
	Toolkit._undo()
	_check(CellRecords.records(cell).size() == pre + 1,
		"Z with empty mementos deletes nothing anywhere")
	# PLACE keeps its LIFO remove — and empties honestly (no crash, notice).
	Toolkit._tool = Toolkit.Tool.PLACE
	Toolkit._undo()
	_check(CellRecords.records(cell).size() == pre, "Z in place mode removes the record")
	if pre == 0:
		Toolkit._undo()  # nothing left: the honest no-op path
		_check(CellRecords.records(cell).size() == 0,
			"Z in place mode on an empty cell is a no-op")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(
			"%s/cell_%d_%d.json" % [CellRecords.DIR, cell.x, cell.y]))
	# Teardown (the _test_toolkit_verbs pattern: no _exit — it wants the
	# real player rig and would save layers to the checkout). Degrouped
	# immediately: queue_free only lands at frame end, and a stale grouped
	# player would shadow the next test's real rig.
	Toolkit.set_tool("sculpt")
	Toolkit.active = false
	player.remove_from_group("player")
	player.queue_free()
	floor_body.queue_free()


## Placement editing v2 (audit #1): the hand edits what it placed.
## Pick = nearest record within reach; move keeps the ground offset
## (the ground-relative law) and migrates cell files across a boundary;
## rotate/scale are data edits; delete is TARGETED (never LIFO); Z
## reverts each through the one-deep {record-id, before-state} memento;
## yaw/scale/id survive a save/load round trip; legacy rows are named
## the moment they're picked. Synthetic far-off cells, no files left.
func _test_placement_edit() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	add_child(player)
	Toolkit._enter()
	_check(Toolkit.active, "toolkit enters for the placement-edit test")
	Toolkit._tool = Toolkit.Tool.PLACE
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

	# Place memento: _place_at records {op place}; Z removes THAT record
	# by id even under a newer sibling — never the LIFO tail. Needs the
	# palette (cards are tracked; resolve can still miss binaries — skip
	# honestly, the targeted machinery is covered above either way).
	if not Toolkit._palette.is_empty():
		var pre: int = CellRecords.records(cell).size()
		Toolkit._place_at(Vector3(x + 5.0, Terrain.height(x + 5.0, z), z))
		if CellRecords.records(cell).size() == pre + 1:
			var placed_id := String(Toolkit._place_undo["id"])
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
	Toolkit._place_undo = {}
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
	# Legacy migration: a save with only the scalar floods the field.
	var keep_wet: float = Climate.wetness
	WorldState.set_value("climate.wet_grid", null)
	WorldState.set_value("climate.wetness", 0.42)
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
	_check(Climate.wetness > 0.76,
		"pre-dawn saturated air dews the ground (%.3f)" % Climate.wetness)
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
	WorldState.set_value("valley.parched", false)
	WorldState.set_value("valley.bloom", false)
	FloraLife._hourly(0)
	_check(WorldState.has_flag("valley.parched"), "dry + starved flora -> parched flag")
	Climate.wetness = 1.0
	FloraLife.vitality = 0.9
	FloraLife._hourly(0)
	_check(WorldState.has_flag("valley.bloom"), "soaked + thriving flora -> bloom flag")
	_check(not WorldState.has_flag("valley.parched"), "recovery clears parched")
	# v2 — species records: loaded, validated, art slots fall back to grow.
	_check(FloraLife.species.size() >= 6, "species records loaded")
	var tuft: Dictionary = {}
	for def: Dictionary in FloraLife.species:
		if str(def.id) == "bloom_tuft":
			tuft = def
	_check(not tuft.is_empty(), "bloom_tuft record exists")
	_check(FloraLife.stage_art(tuft, "bloom") == FloraLife.stage_art(tuft, "grow"),
		"missing stage art falls back to grow (same placeholder slots)")
	_check(str(tuft.get("yields", "")) == "dried_bloom", "bloom_tuft yields dried_bloom")
	# Lifecycle stages are a pure function of season + vitality.
	_check(FloraLife.stage_for("spring", 0.9) == "bloom", "lush spring blooms")
	_check(FloraLife.stage_for("spring", 0.4) == "sprout", "lean spring sprouts")
	_check(FloraLife.stage_for("autumn", 0.7) == "seed", "autumn seeds")
	_check(FloraLife.stage_for("summer", 0.2) == "dry", "parched flora reads dry")
	# Species composition: biome weights + the moisture gate.
	_check(FloraLife.species_weight(tuft, "oasis_green", 0.8) > 0.0,
		"tufts grow in the oasis")
	_check(FloraLife.species_weight(tuft, "bare_peak", 0.8) == 0.0,
		"no tufts on bare peaks")
	_check(FloraLife.species_weight(tuft, "oasis_green", 0.8)
			> FloraLife.species_weight(tuft, "oasis_green", 0.0),
		"drought gates the thirsty species down")
	# Spatial vitality is stateless: it tracks the live moisture field, so
	# the same point reads greener when the ground is wet than when it's dry.
	FloraLife.vitality = 0.5
	Climate.wetness = 0.1
	var dry_v: float = FloraLife.vitality_at(0.0, 0.0)
	Climate.wetness = 0.9
	var wet_v: float = FloraLife.vitality_at(0.0, 0.0)
	_check(wet_v >= dry_v and is_finite(wet_v) and wet_v > 0.0 and wet_v <= 1.0,
		"spatial vitality tracks local moisture (%.3f dry -> %.3f wet)" % [dry_v, wet_v])
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
	WorldState.set_value("valley.bloom", false)
	WorldState.set_value("valley.parched", false)


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
	var mgr: Node = load("res://game/wildlife/wildlife_manager.gd").new()
	var herd: Dictionary = mgr.spawn_herd({
		"id": "test_herd", "count": 2.0,
		"home": {"x": 0.0, "z": 0.0}, "range": 100.0,
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


## F2 fabric: spring bones are presentation-tier. Headless, the gate
## must refuse — a creature body boots with NO simulator under it, so
## the soak digest can never meet spring state — while the gate-free
## builder must still assemble the windowed path's chains correctly
## (right bones, right joint counts, gouache damping) on both shipped
## rigs. Both halves proved here, meaningfully, under the dummy display.
func _test_fabric_spring() -> void:
	var hound: Node = load("res://game/wildlife/hound_body.tscn").instantiate()
	add_child(hound)
	var model: Node = hound.get_node("Body/Model")
	_check(FabricSpring.adopt(model) == null, "headless adopt refuses")
	_check(hound.find_children("*", "SpringBoneSimulator3D", true, false).is_empty(),
		"headless hound body carries no simulator")
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var fs: FabricSpring = FabricSpring.build(skel)
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
	var fox: Node = load("res://assets/models/creatures/biped_fox.glb").instantiate()
	add_child(fox)
	var fskel: Skeleton3D = fox.find_children("*", "Skeleton3D", true, false)[0]
	var ff: FabricSpring = FabricSpring.build(fskel)
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
	var p: PackedVector3Array = Nav.path(
		origin + Vector3(2.0, 0.5, 2.0), origin + Vector3(18.0, 0.5, 18.0))
	_check(p.size() >= 2, "path across the baked cell")
	_check(p[p.size() - 1].distance_to(origin + Vector3(18.0, 0.0, 18.0)) < 2.5,
		"path reaches the goal")
	Nav.remove_cell(cell)
	var fallback: PackedVector3Array = Nav.path(Vector3.ZERO, Vector3(10.0, 0.0, 10.0))
	_check(fallback.size() == 2, "no navmesh -> straight-line fallback")


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
	var slots: Array = Cards.fabric_slots()
	for s in ["props/textile", "props/textile/banner", "props/camp/tent", "props/nautical/net"]:
		_check(slots.has(s), "fabric flag on " + s)
	var f: String = Cards.resolve("props/textile/banner", 0)
	var e: Dictionary = Cards.entry_for_file(f)
	_check(String(e.get("wind", "")) == "fabric", "resolved file finds its fabric card")
	_check(float(e.get("wind_hang", 0.0)) > 0.0, "wind_hang rides the card")
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
