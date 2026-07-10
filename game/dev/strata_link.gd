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
##   reload_world             -> re-reads the world off disk NOW — tile,
##                               sea level, water bodies, biome map — the way
##                               a cold boot does, ADOPTING a tile the pane
##                               booted without (the in-session-bless fix).
##                               (HotReload would catch it within 1s; this
##                               makes Send-to-Game synchronous). Replies
##                               "ok reloaded tile=<yes|no-tile> biomes"
##                               (no-tile: no tile record on disk to adopt).
##                               A tile that IS present but will
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
##   flyover <s> <pattern>    -> the world as a FRAME SEQUENCE (Strata's
##                               Export Flyover…): the Toolkit's orbit rig
##                               frames the whole tile and sweeps one full
##                               turn while every step is captured to
##                               <pattern> (a printf %d slot, e.g.
##                               fly_%04d.png; path may carry spaces).
##                               <s> is the ASSEMBLED length in seconds at
##                               12 fps (frames = s×12, capped 600) — an
##                               honest v1: frames on disk + an ffmpeg
##                               note, never a fake video container. Async
##                               like thumbnail (each frame awaits a real
##                               draw); the view mode is restored after.
##                               "ok flyover <n> frames <w>x<h> <pattern>";
##                               errs headless (dummy renderer), toolkit
##                               inactive, bad pattern, or unwritable path.
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
##   marker set <id> <x> <z> <label…>
##                            -> COLLAB §3c's ghost markers: place (or move +
##                               relabel) a named billboard at a world
##                               position — a soft dot + a Label3D tag,
##                               y-placed on Terrain.height so it reads like
##                               a real place. Parented under current_scene
##                               (the preview_mesh/preview_shared convention)
##                               so it survives reload_world and cell
##                               streaming untouched — it is NOT part of the
##                               streamed world. Not an avatar, not networked
##                               gameplay: a location pin that happens to
##                               move (Strata's CollabSession drives one per
##                               live peer off the roster). "ok marker set
##                               <id>". Content-empty safe: no current_scene
##                               (no world loaded yet) answers an honest err
##                               instead of crashing.
##   marker clear <id>       -> remove one marker. "ok marker clear <id>"
##                               even when the id was never set (idempotent).
##   marker clear all        -> remove every marker wholesale (the
##                               collab-off / all-peers-gone case).
##                               "ok marker clear all"
##   vernier list             -> every registered live tunable (P4 — the
##                               cvar registry, game/dev/vernier.gd), one
##                               line: "ok vernier list <n>[\t<name>:
##                               <type>:<default>:<current>:<provenance>
##                               ...]", TAB-separated, sorted by name.
##   vernier get <name>       -> "ok vernier get <name>=<value> type=<t>
##                               provenance=<p>"; an unknown name answers
##                               "err vernier: no such tunable: <name>".
##   vernier set <name> <val> -> parses <val> as JSON like `state set`
##                               (true/1/0.5/"text"/null; a bare word
##                               lands as a String), coerces it to the
##                               tunable's declared type, calls its real
##                               setter, and stamps provenance "link":
##                               "ok vernier set <name>=<value that
##                               landed>". Unknown name/missing args
##                               error honestly, never silently no-op.
##
## summary() feeds the Toolkit world panel (systems it can't see are debt).

const PORT := 46464
const PROTOCOL := 1

## Every verb _execute answers — the `verbs` discovery reply (audit QW7).
## The scene tests assert this list matches the dispatcher's match arms
## exactly, both ways: add a verb there and it MUST land here too.
const VERBS: Array[String] = ["ping", "status", "pulse", "verbs", "reload_world",
	"teleport", "screenshot", "thumbnail", "flyover", "meshstats", "weather", "time",
	"time_lock", "weather_lock",
	"preview_world", "preview_mesh", "preview_shared", "preview_water", "render_device",
	"camera", "view", "view_layer", "probe",
	"toolkit", "hud", "panel", "inspect", "notices", "overrides", "state",
	"records", "budget", "undo", "redo", "prefab",
	"save_anchor", "restore_anchor", "anchors", "journal", "scrub",
	"play_sound", "audio", "name", "names", "marker", "vernier"]

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

## COLLAB §3c ghost markers: id -> the Node3D root `marker set` placed,
## parented under current_scene so it survives reload_world and cell
## streaming (see `_marker_place`). Wholesale-cleared by `marker clear all`.
var _markers: Dictionary = {}


func _ready() -> void:
	# Vernier (P4): the living-preview distance gate's one tunable, registered
	# BEFORE the DevMode gate below (sea_swell's precedent) so it exists in
	# every posture, including the headless scene tests. Passive — reads the
	# 2500m default once; never calls the setter on its own (M6a.1, §5-the-look).
	Vernier.register("living_preview.resolve_max_dist", TYPE_FLOAT, DEFAULT_RESOLVE_MAX_DIST,
		Callable(self, "vernier_set_resolve_max_dist"),
		Callable(self, "vernier_resolve_max_dist"),
		"Camera-to-focus distance (m) below which a living-preview resolve crossfades the chart drape off to the real world; above it the chart STAYS the survey face (the operator's 2026-07-10 M6a verdict).")
	if not DevMode.active():
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
			elif line == "flyover" or line.begins_with("flyover "):
				# The other async verb: the sweep spans many frames; the
				# same fence holds _process off while frames land.
				_rendering = true
				reply = await _flyover_command(line)
				_rendering = false
			else:
				reply = _execute(line)
			if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				peer.put_data((reply + "\n").to_utf8_buffer())
			_served += 1
	# M6a.1 — the living-preview DISTANCE GATE (PLAN_LIVING_PREVIEW §5, the
	# operator's 2026-07-10 verdict): once a resolve has re-tiled the kernel
	# under a worn drape, whether the chart drape lifts to the real world is
	# a per-frame call on where the camera is. Cheap and inert until a resolve
	# arms it (the flag-off / no-living-preview path never sets _living_gate).
	_living_gate_tick()


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
			# `day` + the two lock states ride the status line (2026-07-09):
			# Strata's SimClock parses them off the SAME heartbeat that carries
			# the hour, so the Live slider AND the Playtest scrubber read one
			# clock (no drift between the two faces), and both lock toggles
			# MIRROR the game's truth instead of a local guess. Appended after
			# the pre-existing fields — SimClock reads `<hours>h` first and the
			# rest by name, so older hubs ignore what they don't parse.
			return "ok %.2fh focus=(%.0f, %.0f) fps=%d served=%d day=%d hold=%d whold=%d" % [
				GameClock.hours, focus.x, focus.y,
				Engine.get_frames_per_second(), _served,
				GameClock.day, 1 if GameClock.held else 0, 1 if Weather.held else 0]
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
			#
			# reload_world (not reload_tile) RE-READS the world off disk the
			# way a cold boot does: it ADOPTS a tile the pane booted without
			# (the in-session-bless fix — the shaping viewer boots
			# content-empty, so reload_tile alone answered "no-tile" and the
			# scene stayed empty until a relaunch), and re-reads the sea level
			# + biome map the importer wrote. See Terrain.reload_world.
			var tile := Terrain.reload_world()
			if tile == "failed":
				return "err reload failed: tile did not reload (old tile stays live)"
			# THE CROSSING (M6a.1): bless re-reads the REAL world off disk — the
			# chart drape's survey-face job (§5) ends here. Drop it and disarm the
			# distance gate unconditionally, so a survey-distance bless (where the
			# gate was keeping the chart worn) can't strand the photograph over the
			# world the operator just chose. A no-op when no drape is worn.
			if _preview != null:
				_preview.leave()
			_reset_living_gate()
			_drape_resolved = false
			# The undo stack's mementos point at the world that just changed
			# under them — a reverted stroke over a fresh tile would be
			# garbage. Disk is the truth across a reload; the stream restarts.
			ToolkitHistory.clear()
			# THE BLESS LANDING (Y2): a reshaped world floods the boot-time
			# spawn — the frozen walker and the builder camera kept their pose
			# over the old (now underwater) spot. Re-seat BOTH onto the world's
			# freshly-recorded landing spot. Gated on the hand being UP: that is
			# the sanctioned bless transition (the walker is frozen under the
			# Toolkit), never a live walk — a reload while the player is actually
			# walking (the standalone `sendToGame` push) leaves them where they
			# stand. See Toolkit.reseat_after_bless.
			if Toolkit.active:
				Toolkit.reseat_after_bless()
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
		"flyover":
			# The flyover sweep is ASYNC too (frames land across many draws)
			# — the socket path routes full commands through _flyover_command;
			# this arm answers the arg check (the `verbs` live-probe sends it
			# bare) and directs a direct caller to the coroutine.
			if parts.size() < 3:
				return "err flyover needs <seconds> <out.png-pattern>"
			return "err flyover renders async — send it over the link"
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
		"time_lock":
			# The time-of-day LOCK (2026-07-09): a REAL hold in GameClock — the
			# 1:1 auto-advance suspends and the wall gap is swallowed (not a
			# Strata re-assert every poll). Idempotent; the reply is the state
			# that RESULTED, which the next `status` line also carries.
			if parts.size() < 2 or not (parts[1] in ["on", "off"]):
				return "err time_lock needs on|off"
			GameClock.set_hold(parts[1] == "on")
			return "ok time_lock %s" % ("on" if GameClock.held else "off")
		"weather_lock":
			# The weather LOCK (2026-07-09): Weather stops EVOLVING (fronts hold,
			# no spawn, wind stops wandering) while the Elements keep rendering
			# the held state. Independent of the clock lock.
			if parts.size() < 2 or not (parts[1] in ["on", "off"]):
				return "err weather_lock needs on|off"
			Weather.set_hold(parts[1] == "on")
			return "ok weather_lock %s" % ("on" if Weather.held else "off")
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
		"preview_water":
			# T1 · the "Hydrology: live ⏸" toggle. Show/hide the water overlay
			# (rivers/lakes/waterfalls, drawn from hydrology.json) on the worn
			# drape — draw-only, no re-solve. `err` when nothing is worn (the
			# Metal chart's own toggle still holds Strata-side).
			if parts.size() < 2 or not (parts[1] in ["on", "off"]):
				return "err preview_water needs on|off"
			if _preview == null:
				return "err no preview mesh worn (preview_mesh <dir> first)"
			return _preview.set_water(parts[1] == "on")
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
		"marker":
			# COLLAB §3c ghost markers — Strata's CollabSession drives one
			# per live peer off the roster (`marker set`), and clears it on
			# expiry/collab-off (`marker clear`/`marker clear all`).
			return _marker(parts, line)
		"vernier":
			# P4 — the cvar registry (game/dev/vernier.gd): list/get/set
			# every tunable a game file registered by name. SURGICAL: this
			# one arm is the whole wire surface; the registry itself never
			# touches the socket or DevMode — it rides the SAME single gate
			# every other verb here does (this whole file's _ready() never
			# listens without DevMode.active()), so "DevMode off" already
			# means this arm, like every other, is simply never reached.
			return _vernier(parts, line)
		"records":
			# The records desk's write path (Strata R5): the game judges
			# an edited record with its OWN loader schema before the desk
			# commits, and re-reads a kind live after a landed write. The
			# framework stays game-agnostic — Records holds the schema and
			# reloader registries; the game's loaders fill them.
			return _records(parts, line)
		"budget":
			# The world budget in one line (a METER, NOT A WALL): the three axes
			# the stress probe charted — this cell's placements, live agents,
			# total records — each graded green/amber/red. Data, not hand state
			# (the Chronicle and the population registry answer in every posture),
			# so Strata's inspector wears a Budget row without the Toolkit up.
			# Grammar pinned by Strata's BudgetReport parser — change both or
			# neither.
			return Budget.link_line()
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
		"prefab":
			# Composition as a Creation Kit power (§2.1): `prefab list` names
			# the captured prefabs, `prefab save <name>` keeps the current
			# selection's cluster as one (placing rides `toolkit place
			# prefab/<name>` then LMB, like any Kit slot).
			return _prefab(parts)
		"save_anchor":
			# The playtest desk (gap #2): snapshot the live world into a
			# named save-v2 slot (session state in the game's save dir, not
			# content). Everything after the verb is the slot name.
			if parts.size() < 2:
				return "err save_anchor needs a name"
			return _save_anchor(line.substr(len("save_anchor")).strip_edges())
		"restore_anchor":
			# Load a named anchor EXACTLY (no wall-clock replay). Monotone:
			# reloads an earlier world, never un-latches a quest.
			if parts.size() < 2:
				return "err restore_anchor needs a name"
			return _restore_anchor(line.substr(len("restore_anchor")).strip_edges())
		"anchors":
			# List the anchor slots with their stamped moment (day + hours),
			# tab-separated, sorted by absolute game-time — the scrubber's rail.
			return _anchors()
		"journal":
			# The Campfire's data over the link (gap #2b): quest latches +
			# frontier as Strata-renderable text. Story is the truth source;
			# journal_ui renders the SAME truth in-game.
			return _journal()
		"scrub":
			# The scrub convenience (gap #2c): travel to an absolute game-hour.
			# Forward = advance from live; back = RESTORE nearest anchor at/
			# before the target, THEN advance forward — honest by construction
			# (the reply names the anchor it restored from). Never un-latches.
			if parts.size() < 2 or not parts[1].is_valid_float():
				return "err scrub needs <abs-hours>"
			return _scrub(float(parts[1]))
		"play_sound":
			# The thumbnail verb's audio sibling (PLAN_AUDIO 4b-ii): audition
			# an SFX event by record id (full pipeline — variations, jitter,
			# bus, ducks, low-pass) OR a bare res-path on the SFX bus. Fire
			# and forget — sync reply, no async dance. An Audition button in
			# the record inspector / on audio cards drives it.
			# `stop` silences the held ambience audition; an SFX id, a bare
			# res-path, or an ambience LAYER id each audition through the real
			# graph. Beds loop (need `play_sound stop`); SFX are one-shots.
			# SURGICAL: one dispatcher arm — the VERBS list is unchanged.
			if parts.size() < 2:
				return "err play_sound needs <event|res-path|stop>"
			var arg := parts[1]
			if arg == "stop":
				Audio.audition_stop()
				return "ok play_sound stop"
			if arg.begins_with("res://"):
				Audio.play_file(arg)
			elif Audio.has_sfx(arg):
				Audio.play(arg)
			else:
				# Not an SFX id or a res-path: try an ambience bed by id so the
				# Audition button works on beds too. Unknown ids stay a silent
				# no-op (content-empty), reply still ok.
				Audio.audition_by_id(arg)
			return "ok play_sound %s" % arg
		"audio":
			# The Mix face (PLAN_AUDIO 4a): `audio` reports the house bus
			# levels in tree order (+ a duck token the A2 mix rules fill);
			# `audio set <bus> <db>` drives AudioServer live, the time-slider
			# contract. Levels are tuning — the graph stays framework-owned
			# (LAW A2; the fence's amended clause).
			return _audio(parts)
		"name":
			# The gazetteer's write door (the naming desk): create-or-update
			# a place's name. `name <id> <text…>` — the text is everything
			# after the id (spaces intact). Rides Names.write, which validates
			# the candidate through the game's OWN records-desk schema and
			# key-preservingly upserts data/names/names.json before the live
			# table rebinds — no second write path, no invented rule.
			var toks := line.split(" ", false, 2)
			if toks.size() < 3:
				return "err name needs <id> <text>"
			var r := Names.write(toks[1], toks[2])
			if not bool(r.get("ok", false)):
				return "err name %s: %s" % [toks[1], r.get("error", "failed")]
			return "ok name %s %s" % [toks[1], Names.resolve(toks[1])]
		"names":
			# The gazetteer's table (the desk's read side): every named place
			# as `id\x1fname\x1fkind`, rows tab-separated. Content-empty answers
			# `ok names count=0` and nothing else — an unnamed world, no error.
			var rows := PackedStringArray()
			for e: Dictionary in Names.entries():
				rows.append("%s%s%s" % [
					e.id, _clean(String(e.name)), _clean(String(e.kind))])
			var head := "ok names count=%d" % rows.size()
			return head if rows.is_empty() else head + "\t" + "\t".join(rows)
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
## `notices` DRAINS once here, exactly as it did as its own poll line. The
## `budget` section rides along as the sixth field — an additive fresh section
## (the world budget's three graded axes for Strata's Budget row); older hubs
## that don't parse it simply ignore the name, no PROTOCOL bump.
func _pulse() -> String:
	var out := "ok pulse"
	# key -> verb line; keys are Strata's GamePulse section names.
	for pair: Array in [["toolkit", "toolkit status"], ["panel", "panel"],
			["inspect", "inspect"], ["notices", "notices"], ["status", "status"],
			["budget", "budget"], ["audio", "audio"]]:
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
		"snap":
			# `toolkit snap grid|ground|normal|socket on|off` or `... step <m>`
			# (audit R1 polish + L11 socket): the same toggles B/K/H/J drive.
			if parts.size() >= 4 and parts[2] == "step" and parts[3].is_valid_float():
				return "ok snap step %.2fm" % Toolkit.set_grid_step(float(parts[3]))
			if parts.size() < 4 or not (parts[3] == "on" or parts[3] == "off"):
				return "err toolkit snap needs grid|ground|normal|socket on|off, or step <m>"
			var snap_r := Toolkit.set_snap(parts[2], parts[3] == "on")
			if snap_r < 0:
				return "err toolkit snap needs grid|ground|normal|socket"
			return "ok snap %s %s" % [parts[2], parts[3]]
		"select":
			# `toolkit select box <x0> <z0> <x1> <z1>` — box multi-select
			# (the headless seam for Shift+RMB). Returns the count.
			if parts.size() < 7 or parts[2] != "box":
				return "err toolkit select needs box <x0> <z0> <x1> <z1>"
			var n := Toolkit.select_box(
				Vector2(float(parts[3]), float(parts[4])),
				Vector2(float(parts[5]), float(parts[6])))
			return "ok select %d" % n
		"move":
			# `toolkit move <x> <z>` — group-move the selection so the
			# primary lands there, offsets preserved (headless drag seam).
			if parts.size() < 4 or not parts[2].is_valid_float() \
					or not parts[3].is_valid_float():
				return "err toolkit move needs <x> <z>"
			var moved := Toolkit.group_move(float(parts[2]), float(parts[3]))
			if moved == 0:
				return "err nothing selected"
			return "ok move %d" % moved
		"duplicate":
			# `toolkit duplicate` — copy the selection in place (alt-drag seam).
			var made := Toolkit.duplicate_selection()
			if made == 0:
				return "err nothing selected"
			return "ok duplicate %d" % made
		_:
			return "err toolkit needs status|tool|brush|biome|place|snap|select|move|duplicate|keys|on|off|undo"


## Prefabs over the link (§2.1). `prefab list` answers the captured names
## ("-" when none), `prefab save <name>` keeps the current selection's
## cluster as a reusable record and replies with the piece count. Gated on
## the hand like the toolkit verbs (capturing is an editor's act); placing a
## prefab needs no verb — `toolkit place prefab/<name>` selects it in the
## palette, then the pane's LMB stamps it.
func _prefab(parts: PackedStringArray) -> String:
	if not Toolkit.active:
		return "err toolkit not active"
	if parts.size() < 2:
		return "err prefab needs list|save"
	match parts[1]:
		"list":
			var ns: Array = Prefabs.names()
			return "ok prefab " + (" ".join(ns) if not ns.is_empty() else "-")
		"save":
			if parts.size() < 3:
				return "err prefab save needs a name"
			var n: int = Toolkit.capture_prefab(parts[2])
			if n == 0:
				return "err prefab save found nothing (select a piece first)"
			return "ok prefab saved %s %d" % [parts[2], n]
		_:
			return "err prefab needs list|save"


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


## P4 — the cvar registry's dispatcher (game/dev/vernier.gd). `list`
## renders every registered tunable TAB-separated, sorted by name; `get`/
## `set` name one by its registered name — an unknown name errs honestly
## from BOTH, the same "no such tunable" line, rather than a silent no-op
## or an engine crash on a null Entry. `set` parses its value like `state
## set` (JSON, bare word -> String) so the wire grammar stays one shape
## across both forcing doors, then stamps provenance "link" — Vernier's
## own set_value() does the coercion-to-declared-type + the real setter
## call; this function only renders the wire text.
func _vernier(parts: PackedStringArray, line: String) -> String:
	if parts.size() < 2:
		return "err vernier needs list|get <name>|set <name> <value>"
	match parts[1]:
		"list":
			var toks := PackedStringArray()
			for e: Vernier.Entry in Vernier.list():
				toks.append("%s:%s:%s:%s:%s" % [e.name, Vernier.type_name(e.type),
					JSON.stringify(e.default), JSON.stringify(e.current), e.provenance])
			return "ok vernier list %d" % toks.size() + (
				"\t" + "\t".join(toks) if not toks.is_empty() else "")
		"get":
			if parts.size() < 3:
				return "err vernier get needs <name>"
			if not Vernier.has(parts[2]):
				return "err vernier: no such tunable: %s" % parts[2]
			var e: Vernier.Entry = Vernier.get_entry(parts[2])
			return "ok vernier get %s=%s type=%s provenance=%s" % [
				e.name, JSON.stringify(Vernier.get_value(e.name)),
				Vernier.type_name(e.type), e.provenance]
		"set":
			if parts.size() < 4:
				return "err vernier set needs <name> <value>"
			if not Vernier.has(parts[2]):
				return "err vernier: no such tunable: %s" % parts[2]
			var raw := line.split(" ", false, 3)[3]
			var value: Variant = JSON.parse_string(raw)
			if value == null and raw != "null":
				value = raw  # a bare word is a string
			var landed: Variant = Vernier.set_value(parts[2], value, "link")
			return "ok vernier set %s=%s" % [parts[2], JSON.stringify(landed)]
		_:
			return "err vernier needs list|get <name>|set <name> <value>"


## COLLAB §3c ghost markers — the `marker` verb's dispatcher. `set` places
## (or moves + relabels) a named billboard; `clear <id>` drops one; `clear
## all` drops every marker wholesale (the collab-off / all-peers-gone case,
## idempotent even at zero markers).
func _marker(parts: PackedStringArray, line: String) -> String:
	if parts.size() < 2:
		return "err marker needs set <id> <x> <z> <label> | clear <id>|all"
	match parts[1]:
		"set":
			if parts.size() < 5:
				return "err marker set needs <id> <x> <z> <label>"
			if not parts[3].is_valid_float() or not parts[4].is_valid_float():
				return "err marker set needs numeric x z"
			var id := parts[2]
			var x := float(parts[3])
			var z := float(parts[4])
			# Everything after z is the label (spaces intact, like `name`).
			var toks := line.split(" ", false, 5)
			var label := toks[5].strip_edges() if toks.size() > 5 else ""
			if label.is_empty():
				label = id
			var root: Node = get_tree().current_scene
			if root == null:
				return "err marker set: no world loaded"
			_marker_place(root, id, x, z, label)
			return "ok marker set %s" % id
		"clear":
			if parts.size() < 3:
				return "err marker clear needs <id>|all"
			if parts[2] == "all":
				for id: String in _markers.keys().duplicate():
					_marker_remove(id)
				return "ok marker clear all"
			_marker_remove(parts[2])
			return "ok marker clear %s" % parts[2]
		_:
			return "err marker needs set|clear"


## Create-or-move-and-relabel one marker: a soft unshaded dot plus a
## billboarded Label3D tag above it, y-placed on Terrain.height so it reads
## like a real place rather than a floating HUD element. Parented under
## `root` (current_scene) — NOT the streamed world — so `reload_world` and
## cell streaming (which only ever touch their own tracked cells) never
## touch it; the marker survives exactly like preview_mesh/preview_shared.
func _marker_place(root: Node, id: String, x: float, z: float, label: String) -> void:
	var y := Terrain.height(x, z)
	var node: Node3D = _markers.get(id, null)
	if node == null:
		node = Node3D.new()
		node.name = "CollabMarker_%s" % id.validate_node_name()
		var dot := MeshInstance3D.new()
		dot.name = "Dot"
		var sphere := SphereMesh.new()
		sphere.radius = 0.6
		sphere.height = 1.2
		dot.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dot.material_override = mat
		node.add_child(dot)
		var tag := Label3D.new()
		tag.name = "Tag"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = Vector3(0, 2.0, 0)
		tag.font_size = 48
		tag.outline_size = 8
		node.add_child(tag)
		root.add_child(node)
		_markers[id] = node
	node.global_position = Vector3(x, y, z)
	(node.get_node("Tag") as Label3D).text = label


## Drop one marker (a no-op — not an error — when the id was never set, so
## `clear all` iterating a stale id list stays honest and idempotent).
func _marker_remove(id: String) -> void:
	var node: Node3D = _markers.get(id, null)
	if node == null:
		return
	node.queue_free()
	_markers.erase(id)


## The records desk (Strata R5): three subverbs over the SAME loader truth.
##   records validate <kind> <json>  -> judge one record by the game's own
##                                       loader schema for that kind. <json>
##                                       is the whole record object (spaces
##                                       allowed — it's the rest of the
##                                       line). "ok validate <kind>" when it
##                                       would load; "err validate <kind>:
##                                       <the game's words>" when it wouldn't
##                                       (a missing field, a wrong type) — the
##                                       desk surfaces that verbatim and never
##                                       lands the write.
##   records reload <kind>            -> re-read that kind's records and rebind
##                                       them live (the reloader the owning
##                                       system registered). "ok reload <kind>
##                                       <n>" naming how many records now load;
##                                       a kind with no live reloader answers
##                                       "ok reload <kind> <n> no-rebind
##                                       (restart to apply)" — honest, never a
##                                       silent no-op.
##   records schema <kind>            -> the required-field type hints the
##                                       loader trusts, so the desk marks which
##                                       scalars are typed: "ok schema <kind>
##                                       field:Type ..." ("-" when the kind has
##                                       no registered schema). EDGE fields the
##                                       game declared ride the same line as
##                                       "edge:<field>><to>" tokens (quests:
##                                       edge:after>stage-id) — the graph desk's
##                                       licence to render/edit them (PLAN.md
##                                       axiom-4 amendment); no token, no edge
##                                       editing.
## Data, not hand state: answers in every posture (the desk edits with or
## without the Toolkit up). Grammar pinned by Strata's RecordReport parser.
func _records(parts: PackedStringArray, line: String) -> String:
	if parts.size() < 3:
		return "err records needs validate|reload|schema <kind> ..."
	var kind := parts[2]
	match parts[1]:
		"validate":
			# The record object is the rest of the line after the kind — JSON
			# with spaces (nested objects, arrays) travels intact.
			var toks := line.split(" ", false, 3)
			if toks.size() < 4:
				return "err records validate needs <kind> <json>"
			var parsed: Variant = JSON.parse_string(toks[3])
			if not (parsed is Dictionary):
				return "err validate %s: not a JSON object" % kind
			var msg := Records.validate_kind(kind, parsed)
			if msg != "":
				return "err validate %s: %s" % [kind, msg]
			return "ok validate %s" % kind
		"reload":
			var reloader := Records.reloader_for(kind)
			# Count what the kind now loads (the desk shows the fresh tally)
			# from the REGISTERED dir — data/<kind> for a top-level kind, but
			# the true nested path for a kind whose desk name differs from its
			# basename (audio_sfx -> data/audio/sfx). count_dir judges each row
			# by the kind's schema without load_dir's re-registration side
			# effects (A1 wart: the naive data/audio_sfx counted zero).
			var count := Records.count_dir(kind)
			if not reloader.is_valid():
				return "ok reload %s %d no-rebind (restart to apply)" % [
					kind, count]
			reloader.call()
			return "ok reload %s %d" % [kind, count]
		"schema":
			# Field-type hints, then any EDGE declarations the game published
			# for the kind (edge:<field>><to> — quests: edge:after>stage-id).
			# Edge tokens ride the same space-joined line, additively: an old
			# desk reads the field hints and ignores tokens it doesn't know;
			# the graph-editing desk reads the edge grammar and lights up.
			var schema := Records.schema_for(kind)
			var edges := Records.edges_for(kind)
			var toks := PackedStringArray()
			for field: String in schema:
				toks.append("%s:%s" % [field, type_string(int(schema[field]))])
			for e: Dictionary in edges:
				toks.append("edge:%s>%s" % [
					String(e.get("field", "")), String(e.get("to", ""))])
			if toks.is_empty():
				return "ok schema %s -" % kind
			return "ok schema %s %s" % [kind, " ".join(toks)]
		_:
			return "err records needs validate|reload|schema <kind> ..."


## The Mix face over the link (PLAN_AUDIO 4a). Bare `audio` mirrors the
## live house bus levels (Audio reads AudioServer, so the reply follows
## whatever the settings slider or a duck last wrote) plus a trailing
## `duck:` token — the ids of every mix.json duck rule active RIGHT NOW
## (A2: `duck:interior` when inside, `duck:-` when nothing ducks), so the
## face can show WHY a bus is quiet even though its slider hasn't moved.
## `audio set <bus> <db>` drives one bus level live (the graph itself stays
## framework-owned — LAW A2).
func _audio(parts: PackedStringArray) -> String:
	if parts.size() == 1:
		return "ok audio %s duck:%s" % [Audio.bus_levels(), Audio.active_ducks()]
	if parts[1] == "set":
		if parts.size() < 4 or not parts[3].is_valid_float():
			return "err audio set needs <bus> <db>"
		var bus := parts[2]
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			return "err audio set: '%s' is not a house bus" % bus
		AudioServer.set_bus_volume_db(idx, float(parts[3]))
		return "ok audio %s %s" % [bus, parts[3]]
	if parts[1] == "commit":
		# Commit-to-mix (X4 A3-breadth item 3, PLAN_AUDIO 4a "write to
		# mix.json"): land the CURRENT live bus levels into data/audio/
		# mix.json as base_gain_db per bus, through Audio's own write door
		# (merge -> atomic write -> reload) — never a blind file overwrite.
		# The Mix face's "Commit to Mix" button drives this.
		var r := Audio.commit_levels()
		if not bool(r.get("ok", false)):
			return "err audio commit: %s" % r.get("error", "failed")
		return "ok audio commit %s duck:%s" % [Audio.bus_levels(), Audio.active_ducks()]
	return "err audio needs set <bus> <db> | commit"


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


# --- the playtest desk (gap #2): anchors, journal, scrub -------------------

## Current absolute game-time in hours (day*24 + hours) — the axis anchors,
## the journal, and scrub all speak.
func _abs_hours() -> float:
	return float(GameClock.day) * 24.0 + GameClock.hours


func _save_anchor(name: String) -> String:
	var r := SaveGame.save_anchor(name)
	if not bool(r.get("ok", false)):
		return "err %s" % r.get("error", "save_anchor failed")
	return "ok anchor %s day=%d %.2fh" % [r.name, int(r.day), float(r.hours)]


func _restore_anchor(name: String) -> String:
	var r := SaveGame.restore_anchor(name)
	if not bool(r.get("ok", false)):
		return "err %s" % r.get("error", "restore_anchor failed")
	return "ok restored %s day=%d %.2fh" % [r.name, int(r.day), float(r.hours)]


## The anchor rail: one tab-separated token per slot, sorted by absolute
## time. A slot token is `<name>/<day>/<hours>` (the slug can hold no '/',
## so it splits cleanly Strata-side). The header tokens carry the count and
## the live moment (`now=<day>/<hours>`) so the scrubber knows where "now"
## sits without a second round trip.
func _anchors() -> String:
	var infos := SaveGame.anchors_info()
	var toks := PackedStringArray()
	toks.append("count=%d" % infos.size())
	toks.append("now=%d/%.2f" % [GameClock.day, GameClock.hours])
	for info: Dictionary in infos:
		toks.append("%s/%d/%.2f" % [info.name, int(info.day), float(info.hours)])
	return "ok anchors " + "\t".join(toks)


## The journal over the link: Story's latches + frontier as text lines,
## flattened onto ONE reply (rows joined by tab, Strata splits them back).
## Prose control-chars collapse to spaces so a tab in authored prose can't
## forge a row boundary. Reads Story only — the same truth journal_ui renders.
func _journal() -> String:
	var rows := PackedStringArray()
	var active := 0
	var remembered: Array[Dictionary] = []
	for qid: String in Story.quests:
		var q: Dictionary = Story.quests[qid]
		if not Story.started(qid):
			continue
		if Story.resolved(qid):
			remembered.append(q)
			continue
		active += 1
		rows.append("# %s" % _clean(String(q.title)))
		for line in _journal_entries(q):
			rows.append(line)
		for sid: String in Story.frontier(qid):
			for obj: Dictionary in _stage(q, sid).get("objectives", []):
				if not Story.objective_done(qid, sid, obj.id):
					rows.append("  ○ %s" % _clean(String(obj.get("text", ""))))
		rows.append("")
	if not remembered.is_empty():
		rows.append("~ Remembered")
		for q: Dictionary in remembered:
			rows.append("# %s" % _clean(String(q.title)))
			for line in _journal_entries(q):
				rows.append(line)
			rows.append("")
	var head := "ok journal active=%d remembered=%d" % [active, remembered.size()]
	if rows.is_empty():
		return head
	return head + "\t" + "\t".join(rows)


## A quest's memoir entries (freshest cycle), day-then-stage order, each from
## the prose sealed at latch time — mirrors journal_ui._entries.
func _journal_entries(q: Dictionary) -> Array[String]:
	var latched: Array[Dictionary] = []
	var order := 0
	for stage: Dictionary in q.stages:
		order += 1
		if not Story.reached(q.id, stage.id):
			continue
		var latch: Variant = WorldState.get_value(Story._latch_prefix(q) + String(stage.id))
		if latch is Dictionary:
			latched.append({"day": int((latch as Dictionary).get("day", 0)),
				"order": order, "latch": latch})
	latched.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.day < b.day if a.day != b.day else a.order < b.order)
	var out: Array[String] = []
	for row: Dictionary in latched:
		var latch: Dictionary = row.latch
		var prose := _clean(String(latch.get("prose", "")))
		if prose.is_empty():
			continue
		out.append("Day %d, %s" % [int(latch.get("day", 0)), latch.get("season", "")])
		out.append(prose)
	return out


## Flatten a payload string for the tab-joined reply: tabs and newlines (the
## row/line separators) become spaces so authored prose can't forge structure.
func _clean(s: String) -> String:
	return s.replace("\t", " ").replace("\n", " ").replace("\r", " ")


func _stage(q: Dictionary, stage_id: String) -> Dictionary:
	for stage: Dictionary in q.stages:
		if stage.id == stage_id:
			return stage
	return {}


## Scrub to an absolute game-hour. FORWARD (target ≥ now) simply advances the
## live sim — the honest thing (the world can only live time). BACKWARD picks
## the nearest anchor at/before the target, restores it, then advances forward
## to the target: latches stay monotone (an earlier world reloaded, replayed
## up), and the reply NAMES the anchor it restored from so nothing is hidden.
##
## Scrub + lock semantics (2026-07-09): a scrub is an EXPLICIT move, so it
## works whether or not the clock is locked — advance_hours is the explicit
## door the lock never blocks (the lock only suspends the automatic 1:1
## advance in _process). The `held` flag is never touched here, so a scrub
## under a lock MOVES time to the target and STAYS locked: the sim lives the
## scrubbed hours, then the clock re-holds at the new moment on the next
## _process. (A backward scrub restores an anchor whose saved WorldState
## carries its own time.hold — restore_anchor reloads the lock as it stood
## when the anchor was saved, then the forward replay re-applies as above.)
## Weather's lock is orthogonal: a scrub's replayed hour_ticks skip evolution
## while weather is held, so a locked sky stays put across the scrub too.
func _scrub(target_abs: float) -> String:
	var cur := _abs_hours()
	if target_abs >= cur - 0.001:
		var fwd := target_abs - cur
		if fwd > 0.0:
			GameClock.advance_hours(fwd)
		return "ok scrub from=live to=day%d/%.2fh advanced=%.2fh" % [
			GameClock.day, GameClock.hours, fwd]
	# Backward: find the nearest anchor at/before the target.
	var infos := SaveGame.anchors_info()
	var best: Dictionary = {}
	for info: Dictionary in infos:
		if float(info.abs) <= target_abs + 0.001:
			if best.is_empty() or float(info.abs) > float(best.abs):
				best = info
	if best.is_empty():
		return "err scrub no anchor at/before day%d/%.2fh — save_anchor first" % [
			int(target_abs / 24.0), fmod(target_abs, 24.0)]
	var r := SaveGame.restore_anchor(String(best.name))
	if not bool(r.get("ok", false)):
		return "err %s" % r.get("error", "restore failed during scrub")
	var advanced := target_abs - float(best.abs)
	if advanced > 0.0:
		GameClock.advance_hours(advanced)
	return "ok scrub from=%s to=day%d/%.2fh restored=%s@day%d advanced=%.2fh" % [
		best.name, GameClock.day, GameClock.hours, best.name, int(best.day), advanced]


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
	# M6a — the RESOLVE (PLAN_LIVING_PREVIEW §3): when a drape is currently
	# worn (the living preview's sub-0.4s drag proxy), preview_world PROMOTES
	# it to the real world UNDERNEATH — the kernel now carries the shape (Walk
	# Here lands true, §6), and the near ring rebuilds real ground behind the
	# drape. Whether the drape then LIFTS to reveal that ground is a distance
	# call (M6a.1 below): near the ground the resolve is the better face and it
	# crossfades in; at survey distance the CHART is the better face (the
	# operator's 2026-07-10 verdict) and the drape stays worn. Arm the gate and
	# let it decide, per frame, from the camera. No drape worn → the plain
	# walk-it viewer, exactly as before.
	if _preview != null and _preview.worn:
		_drape_resolved = true
		_resolved_dir = dir
		_near_ring_confirmed = false
		_living_gate = true
		_arm_drape_crossfade()
	return "ok preview %.0fm sea=%.1fm (in memory — Send persists)" % [
		size, Terrain.sea_level]


## M6a — the living-preview CROSSFADE arm (§3): after a resolve re-tiles the
## kernel behind a worn drape, listen for the near ring to finish rebuilding
## the real ground — that confirm is the "no stale-ground flash" gate the
## distance tick then waits on. One-shot: the first near_ring_settled after
## the resolve marks it confirmed. No streamer in the tree (a bare test
## scene) → confirm never lands and the drape stays worn, the honest fallback.
func _arm_drape_crossfade() -> void:
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer == null or not streamer.has_signal("near_ring_settled"):
		return
	if not streamer.near_ring_settled.is_connected(_on_near_ring_settled_crossfade):
		streamer.near_ring_settled.connect(
			_on_near_ring_settled_crossfade, CONNECT_ONE_SHOT)


func _on_near_ring_settled_crossfade() -> void:
	# The real ground under the drape is now rebuilt (collision + scatter). Mark
	# it confirmed so the distance tick may lift the drape without flashing
	# stale ground — but ONLY if this is still the resolved drape. If the
	# operator resumed dragging, a fresh preview_mesh re-wore it UNRESOLVED and
	# reset the gate; that new drag's own resolve re-arms this.
	if _living_gate and _drape_resolved:
		_near_ring_confirmed = true
		_maybe_lift_drape()


## M6a.1 — the DISTANCE GATE (PLAN_LIVING_PREVIEW §5, the operator's
## 2026-07-10 M6a verdict: at the chooser's ~17km survey framing the raw
## resolved world — no water yet, no far-field polish, no hypsometric
## legibility — "reads as mud"; the chart drape is the better survey face).
## So a resolve NEVER blind-replaces the chart: the crossfade only fires when
## the observing camera is nearer than resolve_max_dist (~2500m from focus),
## where the resolve is the truer picture (Walk Here, close orbit). Above the
## threshold the resolve still happened underneath (kernel + near ring +
## collision) but the drape stays the worn face; descending below it lifts the
## drape (deferred crossfade), and climbing back above re-wears the chart from
## the still-current bake. Ticks every frame from _process while _living_gate.
func _living_gate_tick() -> void:
	if not _living_gate or _preview == null:
		return
	var dist := _camera_focus_dist()
	if _preview.worn:
		# The chart is the visible face. Lift it only once the real ground is
		# confirmed rebuilt AND the camera has dropped below the threshold.
		if _near_ring_confirmed and dist < _resolve_max_dist:
			_preview.leave()
	elif _resolved_dir != "" and dist >= _resolve_max_dist + RESOLVE_DIST_HYST:
		# Already crossfaded to the real world; the camera climbed back to a
		# survey framing — re-wear the chart from the still-current bake. Cheap
		# (a warm texture swap, ~7-13ms, no re-send: the export dir persists and
		# the kernel is unchanged, so _drape_resolved STAYS true). The
		# hysteresis band keeps a camera hovering at the threshold from
		# thrashing leave/re-wear every frame.
		_preview.wear(_resolved_dir)


## Lift the drape now if it is the resolved one, the real ground is confirmed,
## and the camera is near enough that the resolve is the better face. Called
## both on the confirm signal and from the distance tick.
func _maybe_lift_drape() -> void:
	if _living_gate and _preview != null and _preview.worn and _drape_resolved \
			and _near_ring_confirmed and _camera_focus_dist() < _resolve_max_dist:
		_preview.leave()


## Distance from the observing camera to the focus point on the ground — the
## survey-vs-near-ground signal the gate reads. No active camera → INF (treat
## as survey-far: keep the chart, the safe face). The focus is where the view
## is aimed (_focus): under the fly cam in the authoring posture, else the
## player. Height is sampled from the kernel so the distance is honest 3D.
func _camera_focus_dist() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return INF
	var f := _focus()
	return cam.global_position.distance_to(Vector3(f.x, Terrain.height(f.x, f.y), f.y))


## Clear the living-preview gate — no resolve is armed, so the distance tick
## goes inert. Called when the drape is dropped ("off"/leave) or re-wound to a
## fresh UNRESOLVED drag (a new preview_mesh); the next resolve re-arms it.
func _reset_living_gate() -> void:
	_living_gate = false
	_near_ring_confirmed = false
	_resolved_dir = ""


## The M2 fast path: one PreviewTerrain grid, created on demand under the
## current scene, wears the export as a texture swap — the SHAPING loop's
## viewport (preview_world stays the walk-it viewer: it re-tiles the live
## kernel so collision and sims feel the new ground). "off" leaves
## preview and the streamed world returns exactly as recorded. In memory
## only, like preview_world — the checkout never changes.
var _preview: PreviewTerrain = null
# M6a (§6): true when a preview_world has re-tiled the kernel UNDER the
# currently worn drape — i.e. the ground you see is the ground you can walk.
# A fresh wear clears it (the drape shows a shape the kernel lacks); a resolve
# sets it; leaving the drape makes it moot. Gates Walk Here honesty. Survives
# the distance gate's leave/re-wear (the kernel stays resolved across both).
var _drape_resolved := false
# M6a.1 — the DISTANCE GATE state (§5, the survey-face verdict):
#   _living_gate        — a resolve is armed; the tick watches the camera.
#   _near_ring_confirmed— the real ground rebuilt (safe to lift, no flash).
#   _resolved_dir       — the export dir the resolve tiled from, for a cheap
#                         re-wear when the camera climbs back to survey.
var _living_gate := false
var _near_ring_confirmed := false
var _resolved_dir := ""
# The camera-to-focus distance below which a resolve crossfades in; above it
# the chart stays the survey face. Live-tunable by NAME via Vernier
# (living_preview.resolve_max_dist). HYST is the re-wear-on-climb band that
# stops a camera parked at the threshold from thrashing every frame.
const DEFAULT_RESOLVE_MAX_DIST := 2500.0
const RESOLVE_DIST_HYST := 300.0
var _resolve_max_dist := DEFAULT_RESOLVE_MAX_DIST


## Vernier door for living_preview.resolve_max_dist (named methods, never a
## lambda — Vernier's shutdown-crash law). Negative clamps to 0 (a threshold
## below the ground is "always survey": the drape never lifts).
func vernier_set_resolve_max_dist(v: float) -> void:
	_resolve_max_dist = maxf(0.0, v)


func vernier_resolve_max_dist() -> float:
	return _resolve_max_dist


func _preview_mesh(dir: String) -> String:
	if dir == "off":
		if _preview != null:
			_preview.leave()
		_reset_living_gate()
		return "ok preview_mesh off (streamed world restored)"
	if _preview == null:
		_preview = PreviewTerrain.new()
		get_tree().current_scene.add_child(_preview)
	var line := _preview.wear(dir)
	if line.begins_with("err"):
		return line
	# A fresh drape is UNRESOLVED (§6): the grid shows a shape the live kernel
	# does not carry yet, so Walk Here refuses until the pause resolves it. It
	# also unwinds any prior resolve's distance gate — this drag is a new shape
	# whose own resolve will re-arm it.
	_drape_resolved = false
	_reset_living_gate()
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
		_reset_living_gate()
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
	# M6a — Walk Here honesty (§6): the player body drops onto Terrain.height
	# (the KERNEL). While a drape is worn but UNRESOLVED, the kernel still
	# carries the old ground under the photograph — you cannot walk a
	# photograph. Refuse until the pause resolves it (a preview_world re-tile).
	# The fly-cam branch above is unaffected — framing the shape needs no floor.
	if _preview != null and _preview.worn and not _drape_resolved:
		return "err resolve first (stop dragging — Walk Here needs shaped ground)"
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


## Parse and serve a `flyover <seconds> <pattern>` line (the map+flyover
## wave). Seconds is one token; everything after it is the frame pattern
## (paths may carry spaces). Awaits the whole sweep; one reply line.
func _flyover_command(line: String) -> String:
	var parts := line.split(" ", false)
	if parts.size() < 3:
		return "err flyover needs <seconds> <out.png-pattern>"
	if not parts[1].is_valid_float():
		return "err flyover seconds must be a number"
	var seconds := clampf(float(parts[1]), 1.0, 50.0)
	var pattern := line.substr(len("flyover") + 1 + len(parts[1]) + 1).strip_edges()
	if pattern.count("%") != 1 or not pattern.ends_with(".png"):
		return "err flyover pattern needs one %d frame slot ending .png (e.g. fly_%04d.png)"
	return await _flyover(seconds, pattern)


## The flyover itself: assert the orbit posture (the rig frames the whole
## tile — the viewer's boot look), sweep azimuth one full turn, and save
## the main viewport after every REAL draw. 12 fps of assembled time: the
## honest v1 ships frames + an ffmpeg line, not a video container. The
## view mode the user held is restored on every exit path.
func _flyover(seconds: float, pattern: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "err flyover no image (headless dummy renderer draws nothing — needs the live pane)"
	if not Toolkit.active:
		return "err toolkit not active"
	var frames := clampi(int(seconds * 12.0), 12, 600)
	var was_orbit: bool = Toolkit.orbit
	Toolkit.set_view_mode(true)
	var start_az: float = Toolkit.flyover_azimuth()
	var w := 0
	var h := 0
	for i in frames:
		Toolkit.flyover_pose(start_az + TAU * float(i) / float(frames))
		# One processed frame seats the rig on the camera; the post-draw
		# beat guarantees the read-back sees THIS frame (the thumbnail
		# lesson — and never awaited headless, where it would wedge).
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null or img.is_empty():
			_flyover_restore(was_orbit)
			return "err flyover no viewport image at frame %d" % i
		var err := img.save_png(pattern % i)
		if err != OK:
			_flyover_restore(was_orbit)
			return "err flyover save_png %d -> %s" % [err, pattern % i]
		w = img.get_width()
		h = img.get_height()
	_flyover_restore(was_orbit)
	return "ok flyover %d frames %dx%d %s" % [frames, w, h, pattern]


## Hand the view back after a sweep: the orbit posture re-frames the tile
## (undoing the cinematic pose); a fly-mode user gets the fly camera back.
func _flyover_restore(was_orbit: bool) -> void:
	if was_orbit:
		Toolkit.set_view_mode(true)  # frame_tile resets the rig
	else:
		Toolkit.set_view_mode(false)


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
