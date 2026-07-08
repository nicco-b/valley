extends Node
## The Toolkit / StrataLink (autoload) — Strata's hand reaching into the
## live sim (ONE_APP P3, live view v1). A tiny localhost line protocol so
## the Strata hub can drive a running game: paint a ridge in Strata, press
## Walk Here, stand on it. Debug builds only; the transport is a socket
## today and direct calls if the embedded pane (P3.5) passes its gate —
## the VERBS are the contract, not the wire.
##
## Protocol: one command per line over TCP 127.0.0.1:46464; one reply line
## per command ("ok ..." / "err ...").
##   ping                     -> ok pong <protocol>
##   status                   -> ok <hours>h focus=(x,z) fps=<n>
##   reload_world             -> re-reads the baked tile + biome map NOW
##                               (HotReload would catch it within 1s; this
##                               makes Send-to-Game synchronous)
##   teleport <x> <z>         -> fly cam if the Toolkit is open, else player
##   screenshot <path>        -> saves the viewport to an absolute png path
##   weather <kind>           -> Weather.force_kind (calm/storm/... )
##   time +<hours>            -> advance the clock by float hours
##   time <0..24>             -> advance FORWARD to the next occurrence of
##                               that clock hour (today if still ahead,
##                               else tomorrow). Both route through
##                               GameClock.advance_hours — the sim contract's
##                               one door (never a dial-set); replies
##                               "ok <hours 2dp>h day=<day>"
##   preview_world <dir>      -> wear a Strata export IN MEMORY ONLY (the
##                               P8 viewer: tile + sea level from the
##                               export's height.exr + bake_manifest.json;
##                               NOTHING under res://data is written — the
##                               checkout stays pristine until a real Send)
##   toolkit status           -> the hand's state in one line (Strata's
##                               toolbar mirror polls this on pane focus):
##                               "ok tool=sculpt view=fly brush=12.0m
##                                biome=5:<id> place=3/100:<slot> hud=on"
##   toolkit tool <name>      -> switch the active tool
##                               (sculpt|place|terrain|biome|river)
##   toolkit brush <m>        -> set the active tool's brush radius in
##                               meters (clamped to its keyboard range;
##                               the reply carries what landed)
##   toolkit biome <1-9>      -> pick the biome (the 1-9 keys)
##   toolkit place <slot>     -> select the PLACE palette slot (1-based
##                               index or card slot name)
##   hud <on|off>             -> hide/show the in-game text HUD (the
##                               embedded pane goes chrome-less when
##                               Strata's toolbar is driving)
##
## summary() feeds the Toolkit world panel (systems it can't see are debt).

const PORT := 46464
const PROTOCOL := 1

## Actual port (STRATA_LINK_PORT env overrides — a second instance, e.g.
## the P3.5 embedded pane or a probe, gets its own link beside the game).
var port := PORT

var _server: TCPServer = null
var _peers: Array[StreamPeerTCP] = []
var _served := 0  # commands answered (summary/observability)


func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		return
	var env := OS.get_environment("STRATA_LINK_PORT")
	if not env.is_empty() and env.is_valid_int():
		port = int(env)
	_server = TCPServer.new()
	# Bracket-prefixed logs on purpose: test.sh's smoke gate filters "[".
	# A second running instance simply doesn't listen (no warning spam).
	if _server.listen(port, "127.0.0.1") != OK:
		print("[stratalink] port %d busy — link off in this instance" % port)
		_server = null
		set_process(false)
		return
	print("[stratalink] listening on 127.0.0.1:%d" % port)


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_peers.append(peer)
	for i in range(_peers.size() - 1, -1, -1):
		var peer := _peers[i]
		peer.poll()
		var st := peer.get_status()
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
			_peers.remove_at(i)
			continue
		if st != StreamPeerTCP.STATUS_CONNECTED:
			continue
		while peer.get_available_bytes() > 0:
			var line := _read_line(peer)
			if line.is_empty():
				break
			var reply := _execute(line.strip_edges())
			peer.put_data((reply + "\n").to_utf8_buffer())
			_served += 1


## Read up to one newline-terminated command (small lines; commands are
## a handful of tokens, never binary).
func _read_line(peer: StreamPeerTCP) -> String:
	var out := PackedByteArray()
	while peer.get_available_bytes() > 0:
		var b: int = peer.get_u8()
		if b == 10:  # \n
			return out.get_string_from_utf8()
		out.append(b)
	# No newline yet: treat what we have as a whole line (clients send
	# complete lines; a torn read across polls is not worth buffering for).
	return out.get_string_from_utf8()


## Execute one command line -> one reply line. Every verb answers; an
## unknown verb answers too (the hub must never hang on us).
func _execute(line: String) -> String:
	var parts := line.split(" ", false)
	if parts.is_empty():
		return "err empty"
	match parts[0]:
		"ping":
			return "ok pong %d" % PROTOCOL
		"status":
			var focus := _focus()
			return "ok %.2fh focus=(%.0f, %.0f) fps=%d served=%d" % [
				GameClock.hours, focus.x, focus.y,
				Engine.get_frames_per_second(), _served]
		"reload_world":
			var did := Terrain.reload_tile("res://data/terrain/tiles/baked_world.exr")
			Terrain.reload_biomes()
			return "ok reloaded tile=%s biomes" % ("yes" if did else "no-tile")
		"teleport":
			if parts.size() < 3:
				return "err teleport needs x z"
			return _teleport(float(parts[1]), float(parts[2]))
		"screenshot":
			if parts.size() < 2:
				return "err screenshot needs a path"
			var img := get_viewport().get_texture().get_image()
			if img == null or img.is_empty():
				return "err no viewport image (headless?)"
			var err := img.save_png(parts[1])
			return ("ok %s" % parts[1]) if err == OK else ("err save_png %d" % err)
		"weather":
			if parts.size() < 2:
				return "err weather needs a kind"
			Weather.force_kind(parts[1])
			return "ok weather %s" % parts[1]
		"time":
			if parts.size() < 2:
				return "err time needs +<h> or <0..24>"
			return _time(parts[1])
		"preview_world":
			if parts.size() < 2:
				return "err preview_world needs a dir"
			# Paths may carry spaces: everything after the verb is the dir.
			return _preview_world(line.substr(len("preview_world")).strip_edges())
		"view":
			if parts.size() < 2 or not (parts[1] in ["orbit", "fly"]):
				return "err view needs orbit|fly"
			if not Toolkit.active:
				return "err toolkit not active"
			Toolkit.set_view_mode(parts[1] == "orbit")
			return "ok view %s" % parts[1]
		"toolkit":
			return _toolkit(parts)
		"hud":
			if parts.size() < 2 or not (parts[1] in ["on", "off"]):
				return "err hud needs on|off"
			var on := parts[1] == "on"
			Toolkit.set_hud_visible(on)
			HUD.visible = on  # gameplay text (prompt/say/notify) rides along
			return "ok hud %s" % parts[1]
		_:
			return "err unknown verb '%s'" % parts[0]


## The Toolkit verbs (ONE_APP P9·C): Strata's native toolbar drives the
## in-game hand. Every subverb routes through the Toolkit's OWN state
## (never a parallel store — the mirror and the keyboard cannot drift);
## without the hand (play posture, title screen) they err honestly
## instead of half-acting. Meaningful in --toolkit AND --viewer (the
## viewer's Toolkit is active in orbit; status says view=orbit).
func _toolkit(parts: PackedStringArray) -> String:
	if parts.size() < 2:
		return "err toolkit needs status|tool|brush|biome|place"
	if not Toolkit.active:
		return "err toolkit not active"
	match parts[1]:
		"status":
			var s: Dictionary = Toolkit.link_state()
			var place := "-"
			if int(s["place_count"]) > 0:
				place = "%d/%d:%s" % [int(s["place"]),
					int(s["place_count"]), s["place_slot"]]
			return "ok tool=%s view=%s brush=%.1fm biome=%d:%s place=%s hud=%s" % [
				s["tool"], s["view"], float(s["brush_m"]),
				int(s["biome"]), s["biome_id"], place,
				"on" if s["hud"] else "off"]
		"tool":
			if parts.size() < 3 or not Toolkit.set_tool(parts[2]):
				return "err toolkit tool needs sculpt|place|terrain|biome|river"
			return "ok tool %s" % parts[2]
		"brush":
			if parts.size() < 3 or not parts[2].is_valid_float() \
					or float(parts[2]) <= 0.0:
				return "err toolkit brush needs meters > 0"
			return "ok brush %.1fm" % Toolkit.set_brush_m(float(parts[2]))
		"biome":
			if parts.size() < 3 or not parts[2].is_valid_int() \
					or not Toolkit.set_biome(int(parts[2])):
				return "err toolkit biome needs 1..%d" % mini(9, Terrain.biomes.size())
			return "ok biome %d:%s" % [int(parts[2]),
				String(Terrain.biomes[int(parts[2]) - 1].id)]
		"place":
			if parts.size() < 3:
				return "err toolkit place needs a slot (1-based index or card slot)"
			var landed: int = Toolkit.set_place_slot(parts[2])
			if landed == 0:
				return "err no such place slot '%s'" % parts[2]
			var s: Dictionary = Toolkit.link_state()
			return "ok place %d/%d:%s" % [landed, int(s["place_count"]), s["place_slot"]]
		_:
			return "err toolkit needs status|tool|brush|biome|place"


## Advance the clock for the hub — always FORWARD, always through
## GameClock.advance_hours (the sim contract's one door: weather rolls,
## NPCs and climate LIVE the skipped hours — exactly the dev T-key path).
## "+2.5" adds hours; a bare "18" travels to the next 18:00 (today if
## still ahead, else tomorrow — the sim can't unlive hours).
func _time(arg: String) -> String:
	var delta: float
	if arg.begins_with("+"):
		var h := arg.substr(1)
		if not h.is_valid_float() or float(h) < 0.0:
			return "err time needs +<h> or <0..24>"
		delta = float(h)
	elif arg.is_valid_float() and float(arg) >= 0.0 and float(arg) <= 24.0:
		delta = fposmod(float(arg) - GameClock.hours, 24.0)
		if delta < 0.02:  # already standing on it: its next occurrence
			delta += 24.0
	else:
		return "err time needs +<h> or <0..24>"
	GameClock.advance_hours(delta)
	return "ok %.2fh day=%d" % [GameClock.hours, GameClock.day]


## The P8 viewer: swap the live world tile + sea level from a Strata
## world_vN export, ENTIRELY in memory — the hub previews a bake in the
## real engine (shaders, sims, weather) without committing anything to
## the checkout. A later real import/Send persists; a restart reverts.
func _preview_world(dir: String) -> String:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		dir.path_join("bake_manifest.json")))
	if not (manifest is Dictionary):
		return "err no bake_manifest.json in %s" % dir
	var world: Dictionary = manifest.get("world", {})
	var size_arr: Array = world.get("size_m", [16384.0, 16384.0])
	var size := maxf(float(size_arr[0]), float(size_arr[1]))
	var rec := {"id": "baked_world", "layer": "surface", "kind": "tile",
		"origin": {"x": -size * 0.5, "z": -size * 0.5}, "size": size,
		"feather": 600, "heightmap": dir.path_join("height.exr"),
		"height_min": 0.0, "height_max": 1.0}
	if not Terrain.preview_tile(rec, float(world.get("sea_level_m", Terrain.sea_level))):
		return "err could not load %s" % rec["heightmap"]
	return "ok preview %.0fm sea=%.1fm (in memory — Send persists)" % [
		size, Terrain.sea_level]


## Drop the view at a world XZ: the Toolkit fly cam when it's open (the
## authoring posture), otherwise the player body.
func _teleport(x: float, z: float) -> String:
	if Toolkit.active and Toolkit.has_camera():
		Toolkit.move_to(Vector2(x, z))
		return "ok toolkit cam -> (%.0f, %.0f)" % [x, z]
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return "err no player in tree"
	var body := player as CharacterBody3D
	body.global_position = Vector3(x, Terrain.height(x, z) + 1.5, z)
	body.velocity = Vector3.ZERO
	return "ok player -> (%.0f, %.0f)" % [x, z]


## Where the world is being looked at from (fly cam, else player, else origin).
func _focus() -> Vector2:
	if Toolkit.active and Toolkit.has_camera():
		var p := Toolkit.cam_position()
		return Vector2(p.x, p.z)
	var player: Node3D = get_tree().get_first_node_in_group("player")
	return Vector2(player.global_position.x, player.global_position.z) \
			if player else Vector2.ZERO


## Toolkit world panel line.
func summary() -> String:
	if _server == null:
		return "link off"
	return "listening :%d, %d peer(s), %d served" % [port, _peers.size(), _served]
