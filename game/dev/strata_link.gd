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
##   verbs                    -> every verb this link speaks, one line,
##                               space-separated, machine-readable:
##                               "ok verbs ping status reload_world ..."
##                               Strata gates its UI on THIS, never a
##                               hardcoded list; the scene tests pin it to
##                               the dispatcher's own arms so a new verb
##                               cannot ship unlisted.
##   reload_world             -> re-reads the baked tile + biome map NOW
##                               (HotReload would catch it within 1s; this
##                               makes Send-to-Game synchronous). Replies
##                               "ok reloaded tile=<yes|no-tile> biomes"
##                               (no-tile: no baked tile is loaded, nothing
##                               to reload). A tile that IS loaded but will
##                               not re-read (missing/unreadable/non-square
##                               exr) answers "err reload failed: tile did
##                               not reload (old tile stays live)" — never
##                               "ok" over a world that didn't change
##                               (audit QW3).
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
##   preview_mesh <dir>       -> the M2 fast path: wear the export on the
##                               GPU preview grid (PreviewTerrain) — a
##                               texture upload, ground next frame, no
##                               cell/collision/far rebuild; the streamed
##                               world steps aside (visibility only, sims
##                               untouched). "preview_mesh off" restores
##                               the streamed world exactly. Reply:
##                               "ok preview_mesh <size>m sea=<m> wear=<ms>ms"
##   view_layer <name>        -> false-color drape on the preview grid:
##                               shaded|moisture|temperature|flow|slope|biome
##                               (errs when no preview is worn, or when
##                               the export lacks that layer's file).
##                               Colours are Strata's own: the drape
##                               samples the export's ramps.png LUT (M3
##                               parity — the game cannot drift from the
##                               app); data layers wear the chart air
##                               (fog/volumetrics off, ambient floor,
##                               linear tonemap — rendering only, the sim
##                               never hears about it), shaded keeps the
##                               world's real light and weather.
##   probe <x> <z>            -> the ACTIVE view layer's value at a world
##                               position (value-under-cursor, M3):
##                               "ok probe moisture 0.43 at (1024, -300)".
##                               Physical units (temperature °C, shaded =
##                               height m, biome = id from biome.png,
##                               slope = 1-n.y); the grammar is pinned by
##                               Strata's LayerProbe parser — change both
##                               or neither. Errs: no preview worn, bad
##                               args, outside the worn world, layer file
##                               missing from the export.
##   camera                   -> mirror the ACTIVE 3D camera in one line, so
##                               the host can unproject its own cursor rays
##                               (engine-viewport M4: Strata paint-picks
##                               against ITS height mirror — the engine
##                               supplies the view, the doc stays the truth):
##                               "ok camera pos=<x>,<y>,<z> fwd=<x>,<y>,<z>
##                                up=<x>,<y>,<z> fov=<deg> vp=<w>x<h>"
##                               pos in world meters; fwd/up unit vectors
##                               (-basis.z / basis.y); fov is the camera's
##                               fov in degrees — VERTICAL while the camera
##                               keeps height (Godot's default), the host
##                               scales horizontal by vp aspect; vp is the
##                               viewport's visible size in pixels. Errs
##                               honestly with no active camera (headless).
##   toolkit status           -> the hand's state in one line (Strata's
##                               toolbar mirror polls this on pane focus):
##                               "ok tool=sculpt view=fly brush=12.0m
##                                biome=5:<id> place=3/100:<slot> hud=on
##                                biomes=<id,id,...> cats=<c,c,...|->
##                                river=<n>"
##                               The trailing fields are chrome contract
##                               v2 — every name a tool shows as in-game
##                               text, so Strata renders REAL pickers:
##                               biomes = the profile's macro-terrain
##                               names in 1-9 key order (data-driven,
##                               never hardcoded), cats = the PLACE
##                               palette's categories ("-" without
##                               cards), river = pending pen points.
##   toolkit on|off           -> enter/exit the Toolkit (what F1 does —
##                               chrome contract v2: the flyover one
##                               click / one hotkey away in Strata).
##                               Works from the play posture; replies
##                               with the state that RESULTED ("ok
##                               toolkit on|off", idempotent). Entering
##                               with no player in the world (title
##                               screen) errs "err no player in tree".
##   undo / redo              -> one step back / forward through the in-game
##                               undo stream (undo v2, audit R3) — Strata's
##                               ⌘Z / ⇧⌘Z when the pane is front in builder
##                               mode. ONE bounded command stack every hand
##                               tool pushes to (sculpt/terrain/biome region
##                               mementos, place/delete/move record ops, the
##                               carved river), so the old cross-tool footgun
##                               cannot exist: undo pops the last ACTION,
##                               never the current mode's guess. Replies "ok
##                               undo <tool>" / "ok redo <tool>" naming what
##                               moved, or "ok undo nothing" on an empty
##                               stack. Answers in every posture (the stack
##                               is the editor's, not the hand's).
##   toolkit undo             -> the same step-back, under the toolkit verb
##                               (Strata's Undo In Game menu, ⌥⌘Z); an alias
##                               of `undo`, gated on the hand.
##   toolkit tool <name>      -> switch the active tool
##                               (sculpt|place|terrain|biome|river)
##   toolkit brush <m>        -> set the active tool's brush radius in
##                               meters (clamped to its keyboard range;
##                               the reply carries what landed)
##   toolkit biome <1-9>      -> pick the biome (the 1-9 keys)
##   toolkit place <slot>     -> select the PLACE palette slot (1-based
##                               index or card slot name)
##   toolkit keys             -> the hand's key bindings, one line of
##                               space-separated <binding>=<meaning>
##                               tokens (Strata renders honest help from
##                               this instead of hardcoding F1/Tab/Z):
##                               "ok keys F1=toolkit Tab=tool Z=undo
##                                F5=save BracketLeft=smaller
##                                BracketRight=bigger 1-9=pick G=move
##                                R=rotate Comma=shrink Period=grow
##                                X=delete O=panel N=navmesh M=map
##                                Enter=carve Escape=release WASD=fly
##                                E=up Q=down Shift=fast Ctrl=flatten
##                                LMB=apply RMB=pick/inspect Wheel=speed"
##                               Binding names are Godot key names read
##                               from the live InputMap (a rebind changes
##                               the reply); answers with or without the
##                               hand — it is static help, not state.
##   hud <on|off>             -> hide/show the in-game text UI — TOTAL
##                               (chrome contract v2): off darkens the
##                               Toolkit HUD lines, the SEL line, the
##                               sim-inspector label, the O world panel,
##                               and every gameplay prompt/say/notify
##                               (they all live under two CanvasLayers,
##                               both gated). While dark, HUD.notify
##                               routes to the `notices` drain instead
##                               of a label nobody can see — the pane
##                               shows NOTHING but the world when
##                               Strata's chrome is driving.
##   panel                    -> the O world panel, machine-readable:
##                               every section the in-game overlay shows
##                               (HERE/AIR/CLIMATE/.../LINK), one line —
##                               "ok panel <NAME>=<text>[\t<NAME>=<text>...]"
##                               Sections TAB-separated, names uppercase,
##                               embedded newlines flattened to " | "
##                               (ASCII on purpose — the wire stays
##                               single-byte clean).
##                               Both renderers read Toolkit
##                               .panel_sections() — one truth, no drift.
##                               Data, not hand state: answers in every
##                               posture. Strata's WorldPanel parser pins
##                               this grammar — change both or neither.
##   inspect                  -> the RMB sim-inspector + the PLACE
##                               selection over the link (RMB in the
##                               pane, glance at Strata's inspector):
##                               "ok inspect sel=<id>:<kit>:<yaw°>:<scale>
##                                agent=<name> text=<sim_debug>"
##                               sel/agent read "-" when nothing is
##                               picked/inspected; text= (last field,
##                               spaces allowed, newlines -> " | ")
##                               appears only with an agent. kit is the
##                               record's file basename; yaw in whole
##                               degrees; scale 2dp. Errs "err toolkit
##                               not active" without the hand — the
##                               inspector is an editor's eye. Strata's
##                               InspectReport parser pins this grammar.
##   notices                  -> drain the notice queue (chrome contract
##                               v2): while the chrome drives (`hud
##                               off`), HUD.notify lines queue here —
##                               "ok notices <n>[\t<line>...]", TAB-
##                               separated, oldest first, cleared by the
##                               read. Strata polls this on its 2s
##                               heartbeat and lands the lines in its
##                               status bar. Cap 32, oldest dropped.
##   overrides status         -> the P4 seam artifact in one line, for
##                               Strata's UI and probes:
##                               "ok overrides placements=<n> layers=<n>
##                                pending=<yes|no> last_write=<utc|never>
##                                file=data/overrides/overrides.json".
##                               placements counts the live Chronicle;
##                               pending=yes means hand edits newer than
##                               the artifact (the next stroke-quiet
##                               flush rewrites it). Answers without the
##                               hand — it is data, not Toolkit state.
##   state set <key> <value>  -> force a WorldState key (DESIGN_QUESTS B12:
##                               the mirror-law harness door at the desk —
##                               the same trial the quest harness runs,
##                               driven from Strata; dev-gated like time/
##                               weather because the whole link is). value
##                               parses as JSON (true/1/0.5/"text"/null);
##                               a bare word lands as a String. Replies
##                               "ok state <key>=<json>". Latches ride
##                               WorldState.changed, so a forced key
##                               settles quests exactly like a sim write.
##
## summary() feeds the Toolkit world panel (systems it can't see are debt).

const PORT := 46464
const PROTOCOL := 1

## Every verb _execute answers — the `verbs` discovery reply (audit QW7).
## The scene tests assert this list matches the dispatcher's match arms
## exactly, both ways: add a verb there and it MUST land here too.
const VERBS: Array[String] = ["ping", "status", "verbs", "reload_world",
	"teleport", "screenshot", "weather", "time", "preview_world",
	"preview_mesh", "camera", "view", "view_layer", "probe", "toolkit", "hud",
	"panel", "inspect", "notices", "overrides", "state", "undo", "redo"]

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
		"verbs":
			return "ok verbs " + " ".join(VERBS)
		"reload_world":
			# Honest reload (audit QW3): the re-read can FAIL — say so
			# instead of "ok" over a world that didn't change. The old
			# tile stays live either way (Terrain never tears it down).
			var tile := Terrain.reload_tile(StrataConventions.BAKED_TILE_PATH)
			if tile == "failed":
				return "err reload failed: tile did not reload (old tile stays live)"
			Terrain.reload_biomes()
			# The undo stack's mementos point at the world that just changed
			# under them — a reverted stroke over a fresh tile would be
			# garbage. Disk is the truth across a reload; the stream restarts.
			ToolkitHistory.clear()
			return "ok reloaded tile=%s biomes" % ("yes" if tile == "reloaded" else "no-tile")
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
		"preview_mesh":
			# The M2 fast path: the GPU shaping viewport (PreviewTerrain).
			if parts.size() < 2:
				return "err preview_mesh needs a dir (or off)"
			return _preview_mesh(line.substr(len("preview_mesh")).strip_edges())
		"view_layer":
			if parts.size() < 2:
				return "err view_layer needs %s" % "|".join(PreviewTerrain.LAYERS.keys())
			if _preview == null or not _preview.worn:
				return "err no preview mesh worn (preview_mesh <dir> first)"
			return _preview.set_layer(parts[1])
		"camera":
			return _camera()
		"probe":
			# Value-under-cursor (M3): the active drape layer's value at a
			# world XZ — Strata's readout is written against this grammar.
			if parts.size() < 3 or not parts[1].is_valid_float() \
					or not parts[2].is_valid_float():
				return "err probe needs x z"
			if _preview == null or not _preview.worn:
				return "err no preview mesh worn (preview_mesh <dir> first)"
			return _preview.probe(float(parts[1]), float(parts[2]))
		"view":
			if parts.size() < 2 or not (parts[1] in ["orbit", "fly"]):
				return "err view needs orbit|fly"
			if not Toolkit.active:
				return "err toolkit not active"
			Toolkit.set_view_mode(parts[1] == "orbit")
			return "ok view %s" % parts[1]
		"toolkit":
			return _toolkit(parts)
		"overrides":
			# The P4 seam artifact's vitals (counts + last write) — reads
			# the Chronicle and the file, never the Toolkit's state, so it
			# answers in every posture including headless.
			if parts.size() < 2 or parts[1] != "status":
				return "err overrides needs status"
			return "ok " + Overrides.status_line()
		"state":
			# The B12 forcing door: write one WorldState key, mirror-law
			# style — quests hear it through `changed` like any sim truth.
			if parts.size() < 4 or parts[1] != "set":
				return "err state needs set <key> <value>"
			return _state_set(parts[2], line.split(" ", false, 3)[3])
		"hud":
			if parts.size() < 2 or not (parts[1] in ["on", "off"]):
				return "err hud needs on|off"
			var on := parts[1] == "on"
			Toolkit.set_hud_visible(on)
			HUD.visible = on  # gameplay text (prompt/say/notify) rides along
			return "ok hud %s" % parts[1]
		"panel":
			# The O world panel, machine-readable (chrome contract v2):
			# the SAME sections the overlay renders, TAB-separated. Data,
			# not hand state — the sims answer in every posture.
			var toks := PackedStringArray()
			for s: Array in Toolkit.panel_sections():
				toks.append("%s=%s" % [s[0], String(s[1])
					.replace("\n", " | ").replace("\t", " ")])
			return "ok panel " + "\t".join(toks)
		"inspect":
			return _inspect()
		"notices":
			# Drain the queued notice lines (oldest first); the read clears.
			var drained := "ok notices %d" % _notices.size()
			if not _notices.is_empty():
				drained += "\t" + "\t".join(_notices)
			_notices.clear()
			return drained
		"undo":
			# One step back through the in-game undo stream (undo v2, audit
			# R3) — Strata's ⌘Z when the pane is front in builder mode. The
			# ONE stack every hand tool pushes to; the reply names the tool
			# whose action reverted, "nothing" when the stack is empty.
			var undone := Toolkit.undo_last()
			return "ok undo %s" % (undone if undone != "" else "nothing")
		"redo":
			# One step forward (Strata's ⇧⌘Z) — re-applies the last undone
			# action; "nothing" when there is nothing to redo.
			var redone := Toolkit.redo_last()
			return "ok redo %s" % (redone if redone != "" else "nothing")
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
		return "err toolkit needs status|tool|brush|biome|place|keys|on|off|undo"
	if parts[1] == "keys":
		# Static data (the bindings, not the hand's state): answers even
		# without the hand, so Strata can render help before F1 is pressed.
		return "ok keys " + Toolkit.link_keys()
	if parts[1] == "on" or parts[1] == "off":
		# Enter/exit the hand (what F1 does — chrome contract v2): the ONE
		# subverb pair that must work from the play posture, so it rides
		# above the active gate. Idempotent; the reply is the state that
		# RESULTED, and an enter with nobody in the world errs honestly.
		var want := parts[1] == "on"
		if want != Toolkit.active:
			if want and get_tree().get_first_node_in_group("player") == null:
				return "err no player in tree"
			if Toolkit.set_active(want) != want:
				return "err toolkit did not %s" % ("enter" if want else "exit")
		return "ok toolkit %s" % parts[1]
	if not Toolkit.active:
		return "err toolkit not active"
	match parts[1]:
		"status":
			var s: Dictionary = Toolkit.link_state()
			var place := "-"
			if int(s["place_count"]) > 0:
				place = "%d/%d:%s" % [int(s["place"]),
					int(s["place_count"]), s["place_slot"]]
			var cats: Array = s["cats"]
			return "ok tool=%s view=%s brush=%.1fm biome=%d:%s place=%s hud=%s biomes=%s cats=%s river=%d" % [
				s["tool"], s["view"], float(s["brush_m"]),
				int(s["biome"]), s["biome_id"], place,
				"on" if s["hud"] else "off",
				",".join(s["biome_ids"]),
				",".join(cats) if not cats.is_empty() else "-",
				int(s["river"])]
		"undo":
			# One step back through the shared stack, remotely — the same
			# ToolkitHistory the top-level `undo` verb and the key drive.
			# Names the tool whose action reverted, "nothing" when empty.
			var undone := Toolkit.undo_last()
			return "ok undo %s" % (undone if undone != "" else "nothing")
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
			return "err toolkit needs status|tool|brush|biome|place|keys|on|off|undo"


## The RMB sim-inspector + the PLACE selection, one line (chrome contract
## v2): what the in-game inspector label and SEL line show, machine-lean —
## Strata's Inspect section renders THIS after an RMB in the pane. Gated
## on the hand (inspecting is an editor's act); grammar pinned by Strata's
## InspectReport parser — change both or neither.
func _inspect() -> String:
	if not Toolkit.active:
		return "err toolkit not active"
	var s: Dictionary = Toolkit.link_state()
	var sel := "-"
	if String(s["sel_id"]) != "":
		sel = "%s:%s:%.0f:%.2f" % [s["sel_id"],
			String(s["sel_kit"]).get_file().get_basename(),
			rad_to_deg(float(s["sel_yaw"])), float(s["sel_scale"])]
	var line := "ok inspect sel=%s" % sel
	var agent: Node = Toolkit.inspected()
	if agent == null:
		return line + " agent=-"
	line += " agent=%s" % String(agent.name).replace(" ", "_")
	var text := String(agent.sim_debug()).strip_edges() \
		.replace("\n", " | ").replace("\t", " ")
	if text != "":
		line += " text=" + text
	return line


## Transient notices while the chrome drives (chrome contract v2): with
## the text UI dark (`hud off`), HUD.notify routes here instead of a
## label nobody can see; the `notices` verb drains oldest-first. Capped —
## an unpolled queue drops its oldest, never grows unbounded.
const NOTICE_CAP := 32
var _notices: PackedStringArray = []


func post_notice(text: String) -> void:
	if _notices.size() >= NOTICE_CAP:
		_notices.remove_at(0)
	_notices.append(text.replace("\t", " ").replace("\n", " | "))


## The state set verb's write: value parses as JSON (true/false/numbers/
## quoted strings/null); anything that isn't JSON lands as a String, so
## `state set weather.state storm` reads naturally at the desk.
func _state_set(key: String, raw: String) -> String:
	var value: Variant = JSON.parse_string(raw)
	if value == null and raw != "null":
		value = raw  # a bare word is a string
	WorldState.set_value(key, value)
	return "ok state %s=%s" % [key, JSON.stringify(value)]


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
	var rec := {"id": StrataConventions.BAKED_WORLD_ID, "layer": "surface", "kind": "tile",
		"origin": {"x": -size * 0.5, "z": -size * 0.5}, "size": size,
		"feather": 600, "heightmap": dir.path_join("height.exr"),
		"height_min": 0.0, "height_max": 1.0}
	if not Terrain.preview_tile(rec, float(world.get("sea_level_m", Terrain.sea_level))):
		return "err could not load %s" % rec["heightmap"]
	return "ok preview %.0fm sea=%.1fm (in memory — Send persists)" % [
		size, Terrain.sea_level]


## The M2 fast path: one PreviewTerrain grid, created on demand under the
## current scene, wears the export as a texture swap — the SHAPING loop's
## viewport (preview_world stays the walk-it viewer: it re-tiles the live
## kernel so collision and sims feel the new ground). "off" leaves
## preview and the streamed world returns exactly as recorded. In memory
## only, like preview_world — the checkout never changes.
var _preview: PreviewTerrain = null


func _preview_mesh(dir: String) -> String:
	if dir == "off":
		if _preview != null:
			_preview.leave()
		return "ok preview_mesh off (streamed world restored)"
	if _preview == null:
		_preview = PreviewTerrain.new()
		get_tree().current_scene.add_child(_preview)
	var line := _preview.wear(dir)
	if line.begins_with("err"):
		return line
	return "ok preview_mesh %s (in memory — off restores)" % line


## The camera mirror (engine-viewport M4): the ACTIVE 3D camera, one line,
## machine-lean. Strata unprojects its own cursor rays through this and
## marches them into ITS CPU height mirror — the paint funnel (DocModel.edit
## → journal → bake) never forks, the engine only supplies the view. High
## precision on purpose: a stroke lands where the ring showed it.
func _camera() -> String:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return "err no active 3d camera"
	var p := cam.global_position
	var b := cam.global_transform.basis
	var fwd := -b.z.normalized()
	var up := b.y.normalized()
	var vp := cam.get_viewport().get_visible_rect().size
	return "ok camera pos=%.3f,%.3f,%.3f fwd=%.5f,%.5f,%.5f up=%.5f,%.5f,%.5f fov=%.2f vp=%dx%d" % [
		p.x, p.y, p.z, fwd.x, fwd.y, fwd.z, up.x, up.y, up.z,
		cam.fov, int(vp.x), int(vp.y)]


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
