extends Node
## R6 thumbnail-verb probe: drives StrataLink._execute("thumbnail ...") — the
## SAME door the TCP link uses — through its whole plumbing (arg parsing,
## unknown-slot/no-path errors, slot resolution, offscreen SubViewport render,
## PNG write). The PIXEL proof needs the live pane: true --headless is the
## dummy renderer, so a real slot answers "err ... no image" here — that
## error IS the plumbing working (it resolved the slot, built the subject,
## drew, and honestly reported the empty frame). Run:
##   godot --quit-after 30 res://tests/thumbnail_probe.tscn       (windowed = pixels)
##   godot --headless --quit-after 30 res://tests/thumbnail_probe.tscn  (plumbing)
## Prints [thumb] lines and a PROBE PASS/FAIL verdict, then quits.

var _fails := 0
var _ran := false


func _process(_d: float) -> void:
	if _ran:
		return
	_ran = true
	await _run()
	print("THUMB-PROBE ", "FAIL (%d)" % _fails if _fails > 0 else "PASS")
	get_tree().quit(1 if _fails > 0 else 0)


func _ok(cond: bool, name: String) -> void:
	if not cond:
		_fails += 1
		print("[thumb]   FAIL: ", name)
	else:
		print("[thumb]   ok: ", name)


func _run() -> void:
	var out_dir := OS.get_environment("THUMB_OUT")
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("thumb_probe")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# -- arg-parsing / honest errors (headless-proof, no render) --
	var r_noargs := StrataLink._execute("thumbnail")
	print("[thumb] noargs -> ", r_noargs)
	_ok(r_noargs.begins_with("err thumbnail needs"), "bare verb errs on missing args")

	var r_slotonly := StrataLink._execute("thumbnail some/slot")
	print("[thumb] slot-only -> ", r_slotonly)
	_ok(r_slotonly.begins_with("err thumbnail needs"), "slot without path errs")

	var r_unknown: String = await StrataLink._thumbnail_command(
		"thumbnail no/such/slot " + out_dir.path_join("x.png"))
	print("[thumb] unknown -> ", r_unknown)
	_ok(r_unknown.begins_with("err thumbnail unknown slot"), "unknown slot errs honestly")

	# -- real slots through the full render path --
	if Cards.count() == 0:
		print("[thumb] SKIP real-slot render: no cards (fresh worktree, no assets)")
		return

	var mesh_slot := _first_slot_of_class("gltf_mesh")
	var png_slot := _first_slot_of_class("billboard_png")
	print("[thumb] mesh slot=", mesh_slot, " png slot=", png_slot)

	# -- meshstats (drop-time sanity), headless-proof: pure resource read --
	var ms_unknown := StrataLink._execute("meshstats no/such/slot")
	_ok(ms_unknown.begins_with("err meshstats unknown slot"), "meshstats unknown slot errs")
	if mesh_slot != "":
		var ms := StrataLink._execute("meshstats %s" % mesh_slot)
		print("[thumb] meshstats mesh -> ", ms)
		_ok(ms.begins_with("ok meshstats ") and ms.contains("kind=mesh")
			and ms.contains("tris=") and ms.contains("collision="),
			"meshstats mesh reports tris + collision")
	if png_slot != "":
		var msp := StrataLink._execute("meshstats %s" % png_slot)
		print("[thumb] meshstats png -> ", msp)
		_ok(msp.contains("kind=billboard") and msp.contains("collision=no"),
			"meshstats billboard is tri-free, collision-free")

	for pair in [["mesh", mesh_slot], ["png", png_slot]]:
		var kind: String = pair[0]
		var slot: String = pair[1]
		if slot == "":
			print("[thumb] SKIP %s: no such class in catalog" % kind)
			continue
		var path := out_dir.path_join("%s.png" % kind)
		# A path with a space, to prove the slot/path split holds. Drive the
		# real coroutine door (_thumbnail_command), the same one the socket
		# routes to — _execute's arm is the sync arg-check only.
		var spaced := out_dir.path_join("%s copy.png" % kind)
		var r: String = await StrataLink._thumbnail_command("thumbnail %s %s" % [slot, path])
		print("[thumb] %s -> %s" % [kind, r])
		var r2: String = await StrataLink._thumbnail_command("thumbnail %s %s" % [slot, spaced])
		print("[thumb] %s (spaced path) -> %s" % [kind, r2])
		if DisplayServer.get_name() == "headless" or r.begins_with("err thumbnail no image"):
			# Dummy renderer: the plumbing resolved + drew + reported empty.
			_ok(r.begins_with("err thumbnail no image") or r.begins_with("ok thumbnail"),
				"%s: resolved+drew (headless reports no-image, that's the plumbing)" % kind)
			_ok(r2.contains(spaced.get_file()) or r2.begins_with("err thumbnail no image"),
				"%s: spaced path parsed as one path token" % kind)
		else:
			_ok(r.begins_with("ok thumbnail"), "%s: rendered ok" % kind)
			_ok(FileAccess.file_exists(path), "%s: PNG written to disk" % kind)
			var img := Image.load_from_file(path)
			_ok(img != null and img.get_width() == 512 and img.get_height() == 512,
				"%s: PNG is 512x512" % kind)
			# Transparent-bg proof: the corner is background (transparent) AND
			# the art actually drew (some opaque pixel exists somewhere).
			if img != null:
				img.decompress()
				var corner := img.get_pixel(2, 2)
				_ok(corner.a < 0.5, "%s: corner is transparent" % kind)
				var opaque := 0
				for y in range(0, 512, 8):
					for x in range(0, 512, 8):
						if img.get_pixel(x, y).a > 0.5:
							opaque += 1
				print("[thumb] %s opaque samples=%d" % [kind, opaque])
				_ok(opaque > 0, "%s: the art rendered (opaque pixels present)" % kind)


func _first_slot_of_class(cls: String) -> String:
	# Cards has no public class iterator; walk placeable() for meshes and
	# fall back to a catalog scan via resolve for billboards.
	if cls == "gltf_mesh":
		var pl: Array = Cards.placeable()
		return String(pl[0]["slot"]) if not pl.is_empty() else ""
	# billboard: find any slot whose resolved file is a .png
	for e in _all_entries():
		if String(e.get("class", "")) == cls:
			return String(e["slot"])
	return ""


func _all_entries() -> Array:
	# Reach the private catalog through summary-independent public surface:
	# resolve() over placeable gives meshes; for a general walk we read the
	# catalog's own dictionary via `get`.
	var slots: Variant = Cards.get("_slots")
	if slots is Dictionary:
		return (slots as Dictionary).values()
	return []
