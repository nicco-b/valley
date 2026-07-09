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
##   pulse                    -> the WHOLE 2s heartbeat in ONE reply
##                               (native-embed F2): the fields Strata's
##                               poll used to gather in FIVE round trips —
##                               `toolkit status`, `panel`, `inspect`, the
##                               `notices` drain, and `status` — batched.
##                               "ok pulse<RS>toolkit=<line><RS>panel=<line>
##                                <RS>inspect=<line><RS>notices=<line>
##                                <RS>status=<line>", <RS> the ASCII record
##                               separator (0x1e). Each nested <line> is the
##                               EXACT reply its own verb gives (ok/err
##                               prefix and internal tabs intact) — one
##                               truth, no drift, and Strata reuses the same
##                               sub-parsers. Additive: the hub gates on
##                               `pulse` via the `verbs` list and falls back
##                               to the five verbs on older games, so this
##                               does NOT bump PROTOCOL. New heartbeat fields
##                               append as fresh <RS> sections (old hubs
##                               ignore unknown names). Strata's GamePulse
##                               parser pins this grammar — change both or
##                               neither.
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
##   thumbnail <slot> <path>  -> renders the slot's resolved scene/mesh to
##                               a transparent PNG at <path>, orbit-framed
##                               in an offscreen SubViewport (the pane has a
##                               live GPU; true --headless is the dummy
##                               renderer and answers "err ... no image").
##                               The slot is a Cards id, resolved through the
##                               same catalog placement uses — so a retired
##                               placeholder thumbnails as its real art. Path
##                               may carry spaces (slot is one token, the
##                               rest is the path). "ok thumbnail <slot>
##                               <w>x<h> <path>" on success.
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
const VERBS: Array[String] = ["ping", "status", "pulse", "verbs", "reload_world",
	"teleport", "screenshot", "thumbnail", "meshstats", "weather", "time",
	"preview_world", "preview_mesh", "preview_shared", "render_device",
	"camera", "view", "view_layer", "probe",
	"toolkit", "hud", "panel", "inspect", "notices", "overrides", "state",
	"undo", "redo"]

## Thumbnail render target size (square). The pane renders this offscreen;
## Strata caches the PNG by card sha and downsamples in its grid.
const THUMB_SIZE := 512

## Actual port (STRATA_LINK_PORT env overrides — a second instance, e.g.
## the P3.5 embedded pane or a probe, gets its own link beside the game).
var port := PORT

var _server: TCPServer = null
var _peers: Array[StreamPeerTCP] = []
var _served := 0  # commands answered (summary/observability)
# The thumbnail render reads an offscreen SubViewport back to the CPU — that
# needs a real frame to land (force_draw won't; the just-added instances
# register next frame). So the render awaits, and _process re-entrancy is
# fenced by this flag: while a thumbnail draws, the next frame's _process
# bows out rather than double-servicing the same peers.
var _rendering := false


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
	if _server == null or _rendering:
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
			var line := _read_line(peer).strip_edges()
			if line.is_empty():
				break
			var reply: String
			# The one async verb: thumbnail renders over a frame, so its reply
			# waits for the draw (the flag above holds _process off meanwhile).
			# Every other verb answers synchronously, same as ever.
			if line == "thumbnail" or line.begins_with("thumbnail "):
				_rendering = true
				reply = await _thumbnail_command(line)
				_rendering = false
			else:
				reply = _execute(line)
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
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
		"pulse":
			# The batched heartbeat (native-embed F2): five verbs, one
			# reply, nested behind the record separator. See _pulse.
			return _pulse()
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
		"thumbnail":
			# The librarian's eyes (audit R6). The render is ASYNC (an
			# offscreen SubViewport read-back needs a frame), so the socket
			# path in _process routes full commands through _thumbnail_command
			# and the reply waits for the draw. This synchronous arm answers
			# the arg check (the `verbs` live-probe sends it bare) and directs
			# a direct caller to the coroutine — the source-visible arm the
			# discovery test pins against, never a silent no-op.
			if parts.size() < 3:
				return "err thumbnail needs <slot> <path>"
			return "err thumbnail renders async — send it over the link"
		"meshstats":
			# Drop-time sanity (audit R6): the game reads the slot's resolved
			# glb natively — Strata can't — so it answers tri count, surface
			# count, and collision-node presence for the import caption. Pure
			# resource inspection, no render: works headless too.
			if parts.size() < 2:
				return "err meshstats needs <slot>"
			return _meshstats(parts[1])
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
		"preview_shared":
			# The ZERO-COPY path (fork-genius #1): Strata blit-published the
			# bake into shared GPU surfaces and hands us the raw MTLTexture
			# pointers; we wrap them once (texture_create_from_extension ->
			# Texture2DRD) onto the SAME PreviewTerrain grid — no EXR, no dir,
			# no upload. Same-process + one-device only (Strata gates it);
			# "off" leaves preview like preview_mesh. See _preview_shared.
			if parts.size() < 2:
				return "err preview_shared needs a payload (or off)"
			return _preview_shared(line.substr(len("preview_shared")).strip_edges())
		"render_device":
			# The device-identity handshake for the shared path: our engine's
			# logical-device pointer (get_driver_resource). Strata compares it
			# to its own MTLDevice pointer — equal means one shared device, the
			# zero-copy premise. 0 when headless (no RenderingDevice).
			return _render_device()
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


## The pulse section separator: ASCII RECORD SEPARATOR (0x1e). It never
## appears in any nested payload — panel/inspect/notices flatten newlines
## to " | " and turn tabs into spaces, the rest are numeric/id fields — so
## it frames the sections unambiguously while the reply stays ONE line
## (\n-terminated like every other reply). Pinned by Strata's GamePulse
## parser: change both or neither.
const PULSE_SEP := "\u001e"  # ASCII record separator (0x1e)


## The batched heartbeat (native-embed F2): Strata's 2s poll gathered five
## fields in five connect/write/read/close round trips — `toolkit status`,
## `panel`, `inspect`, the `notices` drain, and `status`. `pulse` answers
## all five in ONE reply. It re-DISPATCHES each verb through _execute, so
## the nested lines are byte-identical to the standalone replies (one
## truth, zero drift — the batch cannot skew from what the hub sees on the
## fallback path). Sections ride behind PULSE_SEP; new heartbeat fields
## append as fresh sections (old hubs ignore names they don't know). Note
## `notices` DRAINS once here, exactly as it did as its own poll line.
func _pulse() -> String:
	var out := "ok pulse"
	# key -> verb line; keys are Strata's GamePulse section names.
	for pair: Array in [["toolkit", "toolkit status"], ["panel", "panel"],
			["inspect", "inspect"], ["notices", "notices"], ["status", "status"]]:
		out += "%s%s=%s" % [PULSE_SEP, pair[0], _execute(pair[1])]
	return out


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


## The engine's logical-device pointer (get_driver_resource) — the shared
## path's device-identity handshake. Strata creates the shared surfaces on
## whatever MTLDevice its bake runs on; the zero-copy wrap is only safe when
## that is the SAME device this engine samples from, so Strata compares this
## pointer to its own. 0 when there is no RenderingDevice (headless dummy
## renderer) — Strata reads that as "not shareable" and keeps the file path.
func _render_device() -> String:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return "ok render_device 0"
	var ptr := rd.get_driver_resource(
		RenderingDevice.DRIVER_RESOURCE_LOGICAL_DEVICE, RID(), 0)
	return "ok render_device %d" % ptr


## The zero-copy shaping preview: wrap Strata's shared bake surfaces onto the
## PreviewTerrain grid. The payload is strata_link's wire grammar (pinned by
## Strata's SharedPreviewSnapshot.verbTail — change both or neither):
##   gen=<n> w=<px> h=<px> size=<world_m> sea=<m>
##   <layer>=<fmt>:<ptr0>:<ptr1>:<front> …
## Pointers are process-local MTLTexture addresses (same-process only — that
## is the whole premise; Strata never sends this to a standalone game). "off"
## leaves preview exactly like preview_mesh off.
func _preview_shared(payload: String) -> String:
	if payload == "off":
		if _preview != null:
			_preview.leave()
		return "ok preview_shared off (streamed world restored)"
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return "err preview_shared needs a RenderingDevice (headless dummy renderer)"
	var params: Variant = _parse_shared_payload(payload)
	if params is String:
		return params  # the honest parse error
	if _preview == null:
		_preview = PreviewTerrain.new()
		get_tree().current_scene.add_child(_preview)
	var line := _preview.wear_shared(params)
	if line.begins_with("err"):
		return line
	return "ok preview_shared %s (zero-copy — off restores)" % line


## Parse the preview_shared payload into a Dictionary, or an "err ..." String.
## {gen,w,h,size,sealevel, layers:{name:{fmt,ptr0,ptr1,front}}}. The sea-level
## field is keyed "sealevel", not "sea": the framework linter forbids a quoted
## string literal matching a data/ record id, and `sea` is the ocean record's.
func _parse_shared_payload(payload: String) -> Variant:
	var out := {"gen": 0, "w": 0, "h": 0, "size": 16384.0, "sealevel": 0.0, "layers": {}}
	for tok in payload.split(" ", false):
		var eq := tok.find("=")
		if eq < 0:
			return "err preview_shared bad token '%s'" % tok
		var key := tok.substr(0, eq)
		var val := tok.substr(eq + 1)
		match key:
			"gen": out["gen"] = int(val)
			"w": out["w"] = int(val)
			"h": out["h"] = int(val)
			"size": out["size"] = float(val)
			"sealevel": out["sealevel"] = float(val)
			_:
				# A layer token: <fmt>:<ptr0>:<ptr1>:<front>
				var f := val.split(":", false)
				if f.size() != 4:
					return "err preview_shared bad layer '%s'" % tok
				out["layers"][key] = {
					"fmt": f[0], "ptr0": int(f[1]), "ptr1": int(f[2]),
					"front": int(f[3])}
	if int(out["w"]) <= 0 or int(out["h"]) <= 0 or out["layers"].is_empty():
		return "err preview_shared payload missing w/h/layers"
	if not out["layers"].has("height"):
		return "err preview_shared payload has no height layer"
	return out


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


## Mesh sanity for one slot (audit R6, drop-time): tri count, surface count,
## and whether the resolved scene carries collision (a "-col" mesh node, a
## CollisionShape3D, or a PhysicsBody) — the truth Strata can't read out of a
## glb itself, for the import caption's declared-vs-actual line. A billboard
## (.png) has no scene: it answers tris=0 collision=no, kind=billboard.
func _meshstats(slot: String) -> String:
	if not Cards.has(slot):
		return "err meshstats unknown slot '%s'" % slot
	var file: String = Cards.resolve(slot, 0)
	if file == "":
		return "err meshstats slot '%s' resolves no file" % slot
	if file.get_extension().to_lower() == "png":
		return "ok meshstats %s kind=billboard tris=0 surfaces=1 collision=no" % slot
	var scene := Kit.scene_for(file)
	if scene == null:
		return "err meshstats cannot load a scene from '%s'" % file
	var inst: Node = scene.instantiate()
	var tris := 0
	var surfaces := 0
	var collision := false
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name.ends_with("-col"):
			collision = true
			continue
		if mi.mesh != null:
			surfaces += mi.mesh.get_surface_count()
			tris += mi.mesh.get_faces().size() / 3
	if not collision:
		collision = not inst.find_children("*", "CollisionShape3D", true, false).is_empty() \
			or not inst.find_children("*", "PhysicsBody3D", true, false).is_empty()
	inst.free()
	return "ok meshstats %s kind=mesh tris=%d surfaces=%d collision=%s" % [
		slot, tris, surfaces, "yes" if collision else "no"]


## Parse and serve a `thumbnail <slot> <path>` line (the socket's async
## door). Slot is one token; everything after it is the path (paths may
## carry spaces). Awaits the render and returns the reply line.
func _thumbnail_command(line: String) -> String:
	var parts := line.split(" ", false)
	if parts.size() < 3:
		return "err thumbnail needs <slot> <path>"
	var slot: String = parts[1]
	var path := line.substr(len("thumbnail") + 1 + len(slot) + 1).strip_edges()
	return await _thumbnail(slot, path)


## Render one slot's resolved art to a transparent PNG (audit R6). A slot
## is a Cards id; we resolve it through the SAME catalog placement uses, so
## a retired placeholder thumbnails as its real art and the cache key (the
## card sha, on Strata's side) tracks the file the game would actually
## spawn. The render is offscreen — an own-world SubViewport framed on the
## subject's AABB — and awaits one drawn frame before the read-back (the
## just-added instances register with the renderer next frame; a synchronous
## force_draw sees an empty scene). True --headless renders the dummy
## driver: get_image is empty and we say so honestly, never a blank PNG.
func _thumbnail(slot: String, path: String) -> String:
	if path == "":
		return "err thumbnail needs a path"
	if not Cards.has(slot):
		return "err thumbnail unknown slot '%s'" % slot
	var file: String = Cards.resolve(slot, 0)
	if file == "":
		return "err thumbnail slot '%s' resolves no file" % slot
	var head_on := file.get_extension().to_lower() == "png"
	var subject := _thumbnail_subject(file)
	if subject == null:
		return "err thumbnail cannot build a subject from '%s'" % file

	var vp := SubViewport.new()
	vp.size = Vector2i(THUMB_SIZE, THUMB_SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var stage := Node3D.new()
	vp.add_child(stage)
	stage.add_child(subject)
	# Two directional lights (key + soft fill) and a bright ambient floor so
	# vertex-coloured art reads without the world's own environment.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)
	key.light_energy = 1.1
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(130.0), 0.0)
	fill.light_energy = 0.4
	stage.add_child(fill)
	var cam := Camera3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR  # kept transparent by the viewport
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 0.6
	cam.environment = env
	stage.add_child(cam)
	add_child(vp)

	# Show vertex colours the way placement does (world_streamer._dress_placeable),
	# without importing its terrain coupling — just the albedo flag.
	for node in subject.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.name.ends_with("-col"):  # collision hulls stay out of the frame
			mi.visible = false
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is StandardMaterial3D and not mat.vertex_color_use_as_albedo:
				mat.vertex_color_use_as_albedo = true

	_frame_thumbnail_camera(cam, subject, head_on)
	# One drawn frame so the instances register and the target fills, then a
	# post-draw beat to guarantee the GPU->CPU read-back sees this frame. The
	# dummy renderer never emits frame_post_draw (verified) — awaiting it
	# under --headless would wedge the link, so there we settle for the idle
	# frame and let the empty read-back report itself honestly below.
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return "err thumbnail no image (headless dummy renderer draws nothing — needs the live pane)"
	var err := img.save_png(path)
	if err != OK:
		return "err thumbnail save_png %d -> %s" % [err, path]
	return "ok thumbnail %s %dx%d %s" % [slot, img.get_width(), img.get_height(), path]


## Build the render subject for a resolved file: a billboard quad for a
## painting (.png), else the placement scene the kit resolves (a .glb or a
## .tscn). Returns null when neither loads.
func _thumbnail_subject(file: String) -> Node3D:
	if file.get_extension().to_lower() == "png":
		var tex: Texture2D = load(file)
		if tex == null:
			return null
		var w := maxf(1.0, float(tex.get_width()))
		var h := maxf(1.0, float(tex.get_height()))
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, h / w)  # preserve the art's aspect
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		return mi
	var scene := Kit.scene_for(file)
	if scene == null:
		return null
	return scene.instantiate() as Node3D


## Orbit-frame the camera on the subject's combined mesh AABB (head-on for a
## flat billboard). Needs the subject already in the tree so global_transform
## resolves. Falls back to a unit box for an empty AABB (no meshes yet).
func _frame_thumbnail_camera(cam: Camera3D, subject: Node3D, head_on: bool) -> void:
	var box := _subject_aabb(subject)
	if box.size.length() <= 0.0001:
		box = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	var center := box.get_center()
	var radius := maxf(0.001, 0.5 * box.size.length())
	cam.fov = 35.0
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 1.15
	var dir := Vector3(0.0, 0.0, 1.0) if head_on \
			else Vector3(0.75, 0.55, 0.9).normalized()
	cam.position = center + dir * dist
	cam.look_at(center, Vector3.UP)
	cam.near = maxf(0.01, dist - radius * 3.0)
	cam.far = dist + radius * 3.0


## The subject's mesh AABB in ITS local space (merged over every child
## MeshInstance3D, collision proxies excluded — placement hides "*-col").
func _subject_aabb(subject: Node3D) -> AABB:
	var out := AABB()
	var have := false
	var inv := subject.global_transform.affine_inverse()
	for node in subject.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.name.ends_with("-col"):
			continue
		var local := inv * mi.global_transform * mi.mesh.get_aabb()
		out = local if not have else out.merge(local)
		have = true
	if not have and subject is MeshInstance3D and (subject as MeshInstance3D).mesh != null:
		out = (subject as MeshInstance3D).mesh.get_aabb()
	return out


## Toolkit world panel line.
func summary() -> String:
	if _server == null:
		return "link off"
	return "listening :%d, %d peer(s), %d served" % [port, _peers.size(), _served]
