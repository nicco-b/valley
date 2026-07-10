extends Node
## Audition probe (PLAN_AUDIO A3 acceptance): proves the `play_sound`
## audition verb plays AND stops a real ambience record THROUGH the house bus
## graph over the wire — the end-to-end path the scene tests can only prove in
## halves (their autoload-only context has no Ambience scene node, so the wire
## audition there is a content-empty no-op; the direct Audio.audition call
## proves the mechanism). Here we stand up the real thing: the Ambience
## evaluator node registers the game's shipped beds with Audio, then a TCP
## client drives `play_sound wind_bed` / `play_sound stop` at the live link and
## asserts the held audition voice actually ran on the bed's own bus and then
## fell silent — no error anywhere.
##
## Run headless: godot --headless --quit-after 4000 res://tests/audition_probe.tscn
## Success is the PROBE PASS line (the --quit-after backstop exits 0 even on a
## parse error, so the caller greps the line, never the exit code — the scene-
## test convention).

var _failures := 0


func _ready() -> void:
	await _run()
	if _failures == 0:
		print("AUDITION-PROBE PASS")
	else:
		print("AUDITION-PROBE FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: %s" % label)


func _run() -> void:
	if not StrataLink.summary().begins_with("listening"):
		# The link isn't up (port busy / release build): the probe can't run,
		# but that is not a failure of the audition path — skip loudly and pass,
		# the same posture the scene tests take on a busy port.
		print("  audition probe: SKIP (link not listening — port busy or release build)")
		return
	# Stand up the ambience evaluator so it registers the shipped beds with
	# Audio (the link reaches Audio, not this scene node) — the real runtime
	# wiring valley.tscn does, minus the whole world.
	var amb := Ambience.new()
	add_child(amb)
	await get_tree().process_frame  # let _ready run + register
	_check(Audio.audition_by_id != null, "Audio exposes audition_by_id")

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

	# Audition a real shipped bed over the wire, then read the held voice.
	var r1 := await _link_send(peer, ["play_sound wind_bed"])
	_check(r1.size() == 1 and r1[0] == "ok play_sound wind_bed",
		"play_sound <ambience id> answers ok over the wire (got %s)" % str(r1))
	await get_tree().process_frame
	_check(Audio._audition.playing,
		"the wire audition actually RUNS the bed on the held voice")
	_check(Audio._audition.bus == "Ambience",
		"the audition plays on the bed's house bus (through the real graph), got %s"
			% Audio._audition.bus)

	# Stop over the wire; the held voice falls silent.
	var r2 := await _link_send(peer, ["play_sound stop"])
	_check(r2.size() == 1 and r2[0] == "ok play_sound stop",
		"play_sound stop answers ok over the wire (got %s)" % str(r2))
	await get_tree().process_frame
	_check(not Audio._audition.playing, "play_sound stop silenced the held voice")

	# The `audio` mirror answers the house buses over the same link — the Mix
	# face's heartbeat data, proven live alongside the audition.
	var r3 := await _link_send(peer, ["audio"])
	_check(r3.size() == 1 and String(r3[0]).begins_with("ok audio Master:")
			and " Ambience:" in String(r3[0]) and "duck:" in String(r3[0]),
		"audio verb mirrors the house buses for the Mix face (got %s)" % str(r3))

	peer.disconnect_from_host()


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
