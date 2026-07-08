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
	_test_wear()
	_test_nav()
	_test_sand_sim()
	_test_tile_override()
	_test_kernel_retile_race()
	_test_placement_reseat()
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
	await _test_preview_world(peer)
	await _test_preview_mesh(peer)
	await _test_toolkit_verbs(peer)
	peer.disconnect_from_host()


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
		_check(replies[11] == "err toolkit needs status|tool|brush|biome|place",
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
	])
	_check(pre.size() == 5, "preview_mesh pre-wear replies land (got %d)" % pre.size())
	if pre.size() == 5:
		_check(pre[0] == "err preview_mesh needs a dir (or off)", "bare preview_mesh errs")
		_check(pre[1] == "err no preview mesh worn (preview_mesh <dir> first)",
			"view_layer before a wear errs honestly")
		_check(pre[2] == "err view_layer needs shaded|moisture|temperature|slope|biome",
			"bare view_layer errs with the layer list")
		_check(pre[3].begins_with("err no bake_manifest.json"), "missing manifest errs")
		_check(pre[4].begins_with("err no height.exr"), "missing height.exr errs")
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
	# The layer matrix: present files drape, the absent one errs by name,
	# computed layers (slope) and file-less modes (shaded) always answer.
	var layers := await _link_send(peer, [
		"view_layer moisture",     # 0
		"view_layer temperature",  # 1: file absent from this export
		"view_layer bogus",        # 2
		"view_layer slope",        # 3
		"view_layer biome",        # 4
		"view_layer shaded",       # 5
		"view_layer moisture",     # 6: back on, to ride through the re-wear
	])
	_check(layers.size() == 7, "view_layer replies land (got %d)" % layers.size())
	if layers.size() == 7:
		_check(layers[0].begins_with("ok layer moisture"), "moisture drapes")
		_check(layers[1] == "err layer file missing: temperature.png (re-export from Strata)",
			"a layer the export lacks errs by filename")
		_check(layers[2] == "err view_layer needs shaded|moisture|temperature|slope|biome",
			"unknown layer errs with the layer list")
		_check(layers[3].begins_with("ok layer slope"), "slope computes in-shader")
		_check(layers[4].begins_with("ok layer biome"), "biome drapes the colormap")
		_check(layers[5].begins_with("ok layer shaded"), "shaded always answers")
		_check(layers[6].begins_with("ok layer moisture"), "moisture re-drapes")
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
	for f in ["height.exr", "colormap.png", "bake_manifest.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	ground.queue_free()
	cellar.queue_free()
	StrataLink._preview.queue_free()
	StrataLink._preview = null


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
